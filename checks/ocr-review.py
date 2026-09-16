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
Cualquier argumento extra se pasa a `ocr review` (p. ej. --effort high, --background "...").
Siempre excluye .rompelo/** y .opencodereview/**: medido el 16-09-2026, sin eso ocr revisaba su propia salida.
"""
import json, os, shutil, subprocess, sys

ORDEN = {"critical": 4, "high": 3, "medium": 2, "low": 1, "": 0}


def git(*a):
    return subprocess.run(["git", *a], capture_output=True, text=True)


def salir(codigo, msg):
    print(msg)
    sys.exit(codigo)


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
    if umbral not in ORDEN or not umbral:
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
    sucio = bool(git("status", "--porcelain", "--untracked-files=all").stdout.strip())

    pasadas = []
    if base and head and base != head:
        if git("cat-file", "-e", f"{base}^{{commit}}").returncode != 0:
            salir(2, f"la base del contrato ({base[:12]}) no existe en este repo")
        pasadas.append((["--from", base, "--to", head], f"rango {base[:7]}..{head[:7]}"))
    if sucio or not pasadas:
        pasadas.append(([], "workspace"))

    comentarios, ficheros, tokens, avisos, modelo = [], 0, 0, [], None
    for args, etiqueta in pasadas:
        d = correr_ocr(args + extra, etiqueta)
        modelo = (d.get("llm") or {}).get("model", modelo)
        if d.get("status") == "skipped":
            continue
        if d.get("status") != "complete":
            salir(2, f"ocr ({etiqueta}) terminó con status {d.get('status')!r}: no doy la revisión por completa")
        s = d.get("summary") or {}
        ficheros += int(s.get("files_reviewed", 0))
        tokens += int(s.get("total_tokens", 0))
        avisos += d.get("warnings") or []
        comentarios += [dict(x, _pasada=etiqueta) for x in d.get("comments", [])]

    os.makedirs(os.path.join(root, ".rompelo"), exist_ok=True)
    with open(os.path.join(root, ".rompelo", "ocr-ultimo.json"), "w") as f:
        json.dump({"modelo": modelo, "pasadas": [e for _, e in pasadas], "ficheros": ficheros,
                   "tokens": tokens, "umbral": umbral, "avisos": avisos, "comentarios": comentarios}, f,
                  indent=1, ensure_ascii=False)

    if avisos:
        salir(2, f"ocr revisó {ficheros} ficheros pero {len(avisos)} subagente(s) fallaron: cobertura incompleta")
    if ficheros == 0:
        salir(2, f"ocr no vio ningún fichero revisable ({', '.join(e for _, e in pasadas)}): no puedo decir nada")
    graves = [x for x in comentarios if ORDEN.get(x.get("severity", ""), 0) >= ORDEN[umbral]]
    cabecera = f"ocr ({modelo}) revisó {ficheros} ficheros en {len(pasadas)} pasada(s), {tokens} tokens, umbral {umbral}"
    if graves:
        print(f"{cabecera}: {len(graves)} hallazgo(s) (+{len(comentarios) - len(graves)} por debajo del umbral)")
        for x in graves:
            print(f"  {x['path']}:{x.get('start_line', '?')}-{x.get('end_line', '?')} [{x.get('severity')}/{x.get('category')}] {x['content'][:160]}")
        print("detalle completo: .rompelo/ocr-ultimo.json; cada hallazgo necesita disposición (arreglado o refutado con motivo)")
        sys.exit(1)
    salir(0, f"{cabecera}: 0 hallazgos >= umbral ({len(comentarios)} por debajo)")


if __name__ == "__main__":
    main()
