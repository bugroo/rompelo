#!/usr/bin/env python3
"""Check triestado de rompelo sobre `ocr review` (alibaba/open-code-review).

`ocr review` devuelve 0 aunque encuentre defectos (doc oficial, «Exit codes»): tal cual sería un
check incapaz de fallar. Este envoltorio lee su JSON y decide:
  0  revisó N ficheros y no hay comentarios de severidad >= umbral
  1  hay comentarios >= umbral (se listan; el JSON entero queda en .rompelo/ocr-ultimo.json)
  2  no pudo mirar: sin ocr, sin repo, sin LLM, status != complete, avisos de subagentes caídos,
     o cero ficheros revisables (un 0 sobre nada no es verde)

Qué revisa: lo que difiere de la base del contrato (.rompelo/task.json → base). Si la base no es
HEAD, rango base..HEAD; si el árbol tiene cambios sin commitear, además modo workspace. Sin
contrato: solo workspace. Umbral: OCR_UMBRAL=critical|high|medium|low (defecto medium).
Tope de tamaño: OCR_MAX_LINEAS (defecto 1500, 0 = sin tope) líneas añadidas+borradas por pasada; por encima
sale con 2 ANTES de llamar a ocr. Medido el 16-09-2026: una pasada workspace sobre 1 800 líneas ajenas
(el árbol lo había ensuciado otro agente) costó 1,3 M tokens sin que nadie lo pidiera.
Cualquier argumento extra se pasa a `ocr review` (p. ej. --effort high, --background "...").
Esfuerzo: OCR_EFFORT=auto|low|medium|high (auto: low hasta OCR_LINEAS_LOW=150 líneas, medium por encima).
Presupuesto: OCR_PRESUPUESTO_TOKENS (600000; 0 = sin tope) → --max-tokens-budget; si ocr lo agota deja
ficheros en `warnings` y aquí eso es 2 (no pudo mirarlo todo), nunca 0.
Siempre excluye .rompelo/** y .opencodereview/**: medido el 16-09-2026, sin eso ocr revisaba su propia salida.
"""
import json, os, shutil, subprocess, sys

ORDEN = {"critical": 4, "high": 3, "medium": 2, "low": 1}


def peso(sev):
    """Severidad de un comentario. Desconocida o ausente cuenta como la más alta: un nivel nuevo o mal
    escrito no puede colarse por debajo del umbral en silencio (hallazgo de ocr sobre este fichero, 16-09-2026)."""
    return ORDEN.get(str(sev or "").strip().lower(), 5)


def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True)


def salir(codigo, msg):
    print(msg)
    sys.exit(codigo)


def lineas_diff(root, rango):
    """Líneas añadidas+borradas que ocr va a leer en una pasada. rango=[base, head] o None para
    workspace (HEAD..árbol más los ficheros sin seguimiento). .rompelo/ y .opencodereview/ no cuentan."""
    n = 0
    out = git("diff", "--numstat", *(rango or ["HEAD"]), "--", ".", ":(exclude).rompelo", ":(exclude).opencodereview").stdout
    for l in out.splitlines():
        p = l.split("\t")
        if len(p) >= 3 and p[0].isdigit() and p[1].isdigit():  # binarios salen como "-\t-": no cuentan
            n += int(p[0]) + int(p[1])
    if not rango:
        for l in git("status", "--porcelain", "--untracked-files=all").stdout.splitlines():
            if l.startswith("??") and not l[3:].startswith((".rompelo/", ".opencodereview/")):
                try:
                    with open(os.path.join(root, l[3:]), "rb") as f:
                        n += sum(1 for _ in f)
                except OSError:
                    pass
    return n


def correr_ocr(args, etiqueta):
    # .rompelo/ (contrato, evidencia, su propia salida) y .opencodereview/ (reglas) no son código de la tarea
    argv = ["ocr", "review", "--format", "json", "--audience", "agent", "--exclude", ".rompelo/**,.opencodereview/**", *args]
    try:
        r = subprocess.run(argv, capture_output=True, text=True, timeout=int(os.environ.get("OCR_TIMEOUT", "1800")))
    except subprocess.TimeoutExpired:
        salir(2, f"ocr ({etiqueta}) superó el plazo")
    if r.returncode != 0:
        salir(2, f"ocr ({etiqueta}) falló con código {r.returncode}: {r.stderr.strip()[-400:]}")
    try:
        d = json.loads(r.stdout)
    except ValueError:
        salir(2, f"ocr ({etiqueta}) no devolvió JSON: {r.stdout[:200]!r}")
    return d


def main():
    extra = sys.argv[1:]
    umbral = os.environ.get("OCR_UMBRAL", "medium")
    if umbral not in ORDEN:
        salir(2, f"OCR_UMBRAL inválido: {umbral!r}")
    if not shutil.which("ocr"):
        salir(2, "ocr no está en PATH: binario de GitHub Release verificado con sha256sum.txt")
    top = git("rev-parse", "--show-toplevel")
    if top.returncode != 0:
        salir(2, "no es un repo git: ocr no tiene qué revisar")
    root = top.stdout.strip()
    head = git("rev-parse", "--verify", "HEAD").stdout.strip() or None
    base = None
    try:
        c = json.load(open(os.path.join(root, ".rompelo", "task.json")))
        base = c.get("base") or None
        if base == "sin-head":
            base = None
    except (OSError, ValueError):
        pass
    sucio = any(l[3:] and not l[3:].startswith((".rompelo/", ".opencodereview/"))
                for l in git("status", "--porcelain", "--untracked-files=all").stdout.splitlines())

    pasadas = []
    if base and head and base != head:
        if git("cat-file", "-e", f"{base}^{{commit}}").returncode != 0:
            salir(2, f"la base del contrato ({base[:12]}) no existe en este repo")
        pasadas.append((["--from", base, "--to", head], f"rango {base[:7]}..{head[:7]}"))
    if sucio or not pasadas:
        pasadas.append(([], "workspace"))

    try:
        tope = int(os.environ.get("OCR_MAX_LINEAS", "1500") or 0)
    except ValueError:
        salir(2, f"OCR_MAX_LINEAS inválido: {os.environ.get('OCR_MAX_LINEAS')!r}")
    if tope > 0:
        for args, etiqueta in pasadas:
            n = lineas_diff(root, [args[1], args[3]] if args else None)
            if n > tope:
                salir(2, f"diff demasiado grande para ocr: {n} líneas en la pasada {etiqueta} > OCR_MAX_LINEAS={tope}; "
                         "pásalo por partes (commits más pequeños, árbol limpio de cambios ajenos) o sube el tope a sabiendas")

    # Esfuerzo y presupuesto por pasada (ocr v1.12: --effort low|medium|high, --max-tokens-budget N). OCR_EFFORT=auto
    # (defecto): low hasta OCR_LINEAS_LOW líneas (150), medium por encima; un valor fijo manda. OCR_PRESUPUESTO_TOKENS
    # (defecto 600000; 0 = sin tope) corta la corrida antes de que un diff grande cueste una fortuna: ocr entonces
    # marca ficheros como failed(budget) en `warnings` y el envoltorio lo lee como 2 (cobertura incompleta), nunca 0.
    # Medido el 16-09-2026: una corrida entera de verify --ci con ocr en el contrato costó 1,3 M tokens (≈ 1,8 $).
    esfuerzo = os.environ.get("OCR_EFFORT", "auto").strip().lower()
    if esfuerzo not in ("auto", "low", "medium", "high"):
        salir(2, f"OCR_EFFORT inválido: {esfuerzo!r} (auto | low | medium | high)")
    try:
        umbral_low = int(os.environ.get("OCR_LINEAS_LOW", "150") or 0)
        presupuesto = int(os.environ.get("OCR_PRESUPUESTO_TOKENS", "600000") or 0)
    except ValueError:
        salir(2, "OCR_LINEAS_LOW / OCR_PRESUPUESTO_TOKENS tienen que ser enteros")

    def ajustes(args, etiqueta):
        out = []
        if "--effort" not in extra:
            e = esfuerzo
            if e == "auto":
                e = "low" if lineas_diff(root, [args[1], args[3]] if args else None) <= umbral_low else "medium"
            out += ["--effort", e]
        if presupuesto > 0 and "--max-tokens-budget" not in extra:
            out += ["--max-tokens-budget", str(presupuesto)]
        return out

    comentarios, ficheros, tokens, avisos, modelo = [], 0, 0, [], None
    for args, etiqueta in pasadas:
        d = correr_ocr(args + ajustes(args, etiqueta) + extra, etiqueta)
        modelo = (d.get("llm") or {}).get("model", modelo)
        if d.get("status") == "skipped":
            continue
        if d.get("status") != "complete":
            salir(2, f"ocr ({etiqueta}) terminó con status {d.get('status')!r}: no doy la revisión por completa")
        s = d.get("summary") or {}
        ficheros += int(s.get("files_reviewed", 0))
        tokens += int(s.get("total_tokens", 0))
        avisos += d.get("warnings") or []
        comentarios += [dict(x, _pasada=etiqueta) for x in (d.get("comments") or [])]

    os.makedirs(os.path.join(root, ".rompelo"), exist_ok=True)
    with open(os.path.join(root, ".rompelo", "ocr-ultimo.json"), "w") as f:
        json.dump({"modelo": modelo, "pasadas": [e for _, e in pasadas], "ficheros": ficheros,
                   "tokens": tokens, "umbral": umbral, "avisos": avisos, "comentarios": comentarios}, f,
                  indent=1, ensure_ascii=False)

    if avisos:
        salir(2, f"ocr revisó {ficheros} ficheros pero {len(avisos)} subagente(s) fallaron: cobertura incompleta")
    if ficheros == 0:
        salir(2, f"ocr no vio ningún fichero revisable ({', '.join(e for _, e in pasadas)}): no puedo decir nada")
    graves = [x for x in comentarios if peso(x.get("severity")) >= ORDEN[umbral]]
    cabecera = f"ocr ({modelo}) revisó {ficheros} ficheros en {len(pasadas)} pasada(s), {tokens} tokens, umbral {umbral}"
    if graves:
        print(f"{cabecera}: {len(graves)} hallazgo(s) (+{len(comentarios) - len(graves)} por debajo del umbral)")
        for x in graves:
            print(f"  {x.get('path', '?')}:{x.get('start_line', '?')}-{x.get('end_line', '?')} [{x.get('severity')}/{x.get('category')}] {str(x.get('content') or '')[:160]}")
        print("detalle completo: .rompelo/ocr-ultimo.json; cada hallazgo necesita disposición (arreglado o refutado con motivo)")
        sys.exit(1)
    salir(0, f"{cabecera}: 0 hallazgos >= umbral ({len(comentarios)} por debajo)")


if __name__ == "__main__":
    try:
        main()
    except SystemExit:
        raise
    except Exception as e:  # JSON mal formado, git ausente, permisos: el envoltorio no vio nada
        salir(2, f"el envoltorio falló antes de poder juzgar: {type(e).__name__}: {e}")
