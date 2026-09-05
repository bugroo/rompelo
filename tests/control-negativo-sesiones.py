#!/usr/bin/env python3
"""Control negativo del observador con sesiones REALES de Claude Code.

Reproduce, desde los transcripts de ~/.claude/projects/, los eventos que el hook habría recibido
(PostToolUse para resultados correctos, PostToolUseFailure para los que fallaron) contra un
ROMPELO_HOME desechable cuya allowlist contiene los repos de esas sesiones, y cuenta las alarmas.

Privacidad: aquí no se imprime ni se guarda texto de comandos ni de salidas. Solo programa,
códigos, recuentos y rutas del repo. El libro que se genera vive en el directorio temporal y se borra.

Uso:  tests/control-negativo-sesiones.py [--sesiones N] [--min-bash M] [--max-eventos K] [--max-alarmas A] [--ids id,id]
Salida: una tabla por sesión y un resumen. Exit 0 si las alarmas de patrón <= A (por defecto se informa, no se juzga: A=-1).
Con --alarmas-esperadas E el total tiene que ser exactamente E: las alarmas legítimas conocidas son el control
positivo (un observador que dejó de mirar daría 0 y pasaría un simple «<= A»). Y en toda sesión con fallos
reproducidos, algún código de salida tiene que ser distinto de 0: si no, el observador no ve los fallos (INC-0031).
"""
import argparse, collections, glob, json, os, re, shutil, subprocess, sys, tempfile

ROMPELO = os.path.join(os.path.dirname(os.path.dirname(os.path.abspath(__file__))), "bin", "rompelo")
PROYECTOS = os.path.expanduser("~/.claude/projects")


def pares(f, max_eventos):
    """Genera (entrada_hook) por cada tool_use con resultado, en orden. Sin texto fuera del JSON que
    se pasa al hook (que tampoco lo guarda)."""
    usos = {}
    n = 0
    with open(f, errors="replace") as fh:
        for linea in fh:
            try:
                o = json.loads(linea)
            except ValueError:
                continue
            m = o.get("message") or {}
            c = m.get("content")
            if not isinstance(c, list):
                continue
            for b in c:
                if b.get("type") == "tool_use":
                    usos[b.get("id")] = (b.get("name"), b.get("input") or {}, o.get("cwd"))
                elif b.get("type") == "tool_result" and b.get("tool_use_id") in usos:
                    nombre, entrada, cwd = usos.pop(b["tool_use_id"])
                    res = o.get("toolUseResult")
                    ev = {"session_id": o.get("sessionId") or "replay", "cwd": cwd or os.getcwd(),
                          "tool_name": nombre, "tool_input": entrada}
                    if b.get("is_error"):
                        ev["hook_event_name"] = "PostToolUseFailure"
                        ev["error"] = res if isinstance(res, str) else json.dumps(res)
                        ev["is_interrupt"] = bool(isinstance(res, dict) and res.get("interrupted"))
                    else:
                        ev["hook_event_name"] = "PostToolUse"
                        ev["tool_response"] = res if res is not None else {}
                    yield ev
                    n += 1
                    if max_eventos and n >= max_eventos:
                        return


def raiz(cwd):
    r = subprocess.run(["git", "-C", cwd, "rev-parse", "--show-toplevel"], capture_output=True, text=True)
    return os.path.realpath(r.stdout.strip()) if r.returncode == 0 and r.stdout.strip() else None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--sesiones", type=int, default=5)
    ap.add_argument("--min-bash", type=int, default=40)
    ap.add_argument("--max-eventos", type=int, default=600)
    ap.add_argument("--max-alarmas", type=int, default=-1)
    ap.add_argument("--alarmas-esperadas", type=int, default=-1,
                    help="control positivo: las alarmas legítimas conocidas tienen que seguir saltando (exit 1 si el total no coincide)")
    ap.add_argument("--ids", default="")
    a = ap.parse_args()

    ficheros = sorted(glob.glob(os.path.join(PROYECTOS, "*", "*.jsonl")), key=os.path.getmtime, reverse=True)
    if a.ids:
        ids = set(a.ids.split(","))
        ficheros = [f for f in ficheros if os.path.basename(f).split(".")[0] in ids or any(os.path.basename(f).startswith(i) for i in ids)]
    elegidos = []
    for f in ficheros:
        with open(f, errors="replace") as fh:
            n = sum(1 for l in fh if '"name":"Bash"' in l)
        if n >= a.min_bash:
            elegidos.append((f, n))
        if len(elegidos) >= a.sesiones:
            break
    if not elegidos:
        print("no hay sesiones que cumplan el mínimo", file=sys.stderr)
        return 2

    tmp = tempfile.mkdtemp(prefix="rompelo-cn-")
    home = os.path.join(tmp, "home")
    os.makedirs(os.path.join(home, "checks"))
    os.makedirs(os.path.join(home, "config"))
    with open(os.path.join(home, "checks", "registry.json"), "w") as fh:
        fh.write("{}")
    # El observador se carga en proceso (un subproceso por evento tardaba ~100 ms; 2.500 eventos, 4 min).
    os.environ["ROMPELO_HOME"] = home
    import importlib.machinery, importlib.util, io, contextlib
    spec = importlib.util.spec_from_loader("rompelo_mod", importlib.machinery.SourceFileLoader("rompelo_mod", ROMPELO))
    rompelo = importlib.util.module_from_spec(spec)
    spec.loader.exec_module(rompelo)
    assert rompelo.ESTADO.startswith(home), "el observador no está mirando al ROMPELO_HOME desechable"
    raices = {}

    def observar(ev):
        sys.stdin = io.StringIO(json.dumps(ev))
        salida = io.StringIO()
        with contextlib.redirect_stdout(salida):
            rompelo.cmd_observe("claude", [])
        sys.stdin = sys.__stdin__
        return salida.getvalue()

    total_alarmas = 0
    ciego = False
    try:
        for f, nbash in elegidos:
            sid = os.path.basename(f).split(".")[0][:8]
            repos = set()
            eventos = list(pares(f, a.max_eventos))
            for ev in eventos:
                if ev["cwd"] not in raices:
                    raices[ev["cwd"]] = raiz(ev["cwd"]) if os.path.isdir(ev["cwd"]) else None
                if raices[ev["cwd"]]:
                    repos.add(raices[ev["cwd"]])
            with open(os.path.join(home, "config", "repos.json"), "w") as fh:
                json.dump({"repos": sorted(repos)}, fh)
            shutil.rmtree(os.path.join(home, "state"), ignore_errors=True)
            avisos = []
            codigos = collections.Counter()
            fallos = fallos_con_codigo = 0
            for ev in eventos:
                out = observar(ev)
                if out.strip():
                    try:
                        avisos.append(json.loads(out)["hookSpecificOutput"]["additionalContext"])
                    except (ValueError, KeyError):
                        avisos.append(out.strip()[:200])
                if ev["hook_event_name"] == "PostToolUseFailure":
                    fallos += 1
                    if re.match(r"\s*(?:Error:\s*)?Exit code:?\s*\d+", ev["error"]):
                        fallos_con_codigo += 1
            # lo que dice el libro (solo campos derivados)
            libro = []
            for lf in glob.glob(os.path.join(home, "state", "sesiones", "*.jsonl")):
                with open(lf) as fh:
                    libro += [json.loads(l) for l in fh if l.strip()]
            for e in libro:
                if e.get("tool") == "Bash":
                    codigos[str(e.get("codigo"))] += 1
            patrones = collections.Counter()
            perfiles = collections.Counter()
            for est in glob.glob(os.path.join(home, "state", "repos", "*.json")):
                d = json.load(open(est))
                for pth in d.get("patrones", []):
                    patrones[pth] += 1
                for pf in d.get("perfiles", []):
                    perfiles[pf] += 1
            total_alarmas += sum(patrones.values())
            # Una interrupción o un shell que no arranca no traen línea «Exit code»: solo cuentan los fallos que sí la traen.
            if fallos_con_codigo and not any(k not in ("0", "None") for k in codigos):
                print(f"❌ sesión {sid}: {fallos_con_codigo} fallos con línea «Exit code» y ningún código distinto de 0 en el libro: el observador no ve los fallos")
                ciego = True
            print(f"sesión {sid} · bash={nbash} · eventos reproducidos={len(eventos)} · fallos={fallos} · repos={len(repos)}")
            print(f"  códigos bash: {dict(codigos)}")
            print(f"  perfiles D1: {dict(perfiles) or '—'}")
            print(f"  patrones D2: {dict(patrones) or '—'}")
            for av in avisos:
                print("  aviso: " + av.split(". Subo el rigor")[0][:220])
        print(f"\nalarmas de patrón en total: {total_alarmas} en {len(elegidos)} sesiones")
        if ciego:
            return 1
        if a.max_alarmas >= 0 and total_alarmas > a.max_alarmas:
            print(f"❌ más de {a.max_alarmas}")
            return 1
        if a.alarmas_esperadas >= 0 and total_alarmas != a.alarmas_esperadas:
            print(f"❌ se esperaban exactamente {a.alarmas_esperadas} alarmas legítimas (control positivo)")
            return 1
        return 0
    finally:
        shutil.rmtree(tmp, ignore_errors=True)


if __name__ == "__main__":
    sys.exit(main())
