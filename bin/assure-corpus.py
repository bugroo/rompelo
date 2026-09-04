#!/usr/bin/env python3
"""Genera corpus/TABLA.md a partir de incidents/*.yaml.

Es la vista humana; la fuente es el YAML. No se edita a mano.
Control positivo: si no encuentra incidentes, sale con 2 y no escribe nada.
"""
import glob, os, sys, collections
import yaml

RAIZ = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
ficheros = sorted(glob.glob(os.path.join(RAIZ, "incidents", "INC-*.yaml")))
if not ficheros:
    print("assure-corpus: 0 incidentes leídos; no escribo nada", file=sys.stderr)
    sys.exit(2)

CLAVES = ["id", "titulo", "fecha", "tipo", "evidencia_verde", "lo_que_faltaba",
          "gate", "gate_descripcion", "existe_hoy", "spike_cubre", "fuente", "clase", "senal_al_stop"]
inc = []
for f in ficheros:
    d = yaml.safe_load(open(f))
    faltan = [k for k in CLAVES if k not in d]
    if faltan:
        print(f"assure-corpus: {os.path.basename(f)} sin {faltan}", file=sys.stderr)
        sys.exit(2)
    # YAML lee «no» como False y «sí» como texto: se normaliza para no comparar bool con str.
    for k in ("existe_hoy", "spike_cubre"):
        v = d[k]
        d[k] = {True: "sí", False: "no"}.get(v, str(v))
    inc.append(d)

por_gate = collections.Counter(d["gate"] for d in inc)
spike = collections.Counter(d["spike_cubre"] for d in inc)
existe = collections.Counter(d["existe_hoy"] for d in inc)

out = []
out.append("# Corpus de fallos reales · tabla generada\n")
out.append(f"Generado desde `incidents/` ({len(inc)} incidentes). No editar a mano: `python3 bin/assure-corpus.py`.\n")
por_clase = collections.Counter(d["clase"] for d in inc)
S = [d for d in inc if d["clase"] == "S"]
recall_S = sum(1 for d in S if d["spike_cubre"] == "sí")
out.append("## Lo que decide\n")
out.append("Clases: **S** señal disponible al Stop · **T** en el momento de la herramienta (PreToolUse) · "
           "**C** contexto o ámbito · **A** auditoría/adjudicación · **R** runtime, después de desplegar · **I** instrumento: la comprobación no podía fallar · **M** mixto.\n")
out.append("| Pregunta | Recuento |\n|---|---|")
out.append("| Reparto por clase | " + " · ".join(f"**{c}**: {n}" for c, n in sorted(por_clase.items())) + f" (de {len(inc)}) |")
out.append(f"| recall del Stop gate sobre la clase S | **{recall_S} de {len(S)}** |")
out.append(f"| Cobertura del Stop gate sobre TODOS (no es la métrica, se deja por honestidad) | sí: {spike['sí']} · parcial: {spike.get('parcial',0)} · no: {spike['no']} |")
out.append(f"| ¿Cuántos tienen ya un control hoy? | sí: {existe['sí']} · parcial: {existe.get('parcial',0)} · **no: {existe['no']}** |")
out.append("")
out.append("## Por tipo de gate que lo habría cazado\n")
out.append("| Gate | Incidentes | Existe hoy |\n|---|---|---|")
for g, n in por_gate.most_common():
    ids = ", ".join(d["id"][-4:] for d in inc if d["gate"] == g)
    ex = ", ".join(sorted(set(d["existe_hoy"] for d in inc if d["gate"] == g)))
    out.append(f"| `{g}` | {n} ({ids}) | {ex} |")
out.append("")
out.append("## Los incidentes\n")
out.append("| Id | Fecha | Clase | Señal disponible al Stop | Gate | Existe hoy | Spike |\n|---|---|---|---|---|---|---|")
for d in inc:
    out.append(f"| {d['id'][-4:]} | {d['fecha']} | {d['clase']} | {d['senal_al_stop']} | `{d['gate']}` | {d['existe_hoy']} | {d['spike_cubre']} |")
out.append("")
out.append("## Títulos\n")
for d in inc:
    out.append(f"- **{d['id'][-4:]}** · {d['titulo']} (`{d['fuente']}`)")
out.append("")

destino = os.path.join(RAIZ, "corpus", "TABLA.md")
open(destino, "w").write("\n".join(out))
print(f"{destino}: {len(inc)} incidentes · spike cubre sí={spike['sí']} parcial={spike.get('parcial',0)} no={spike['no']}")
