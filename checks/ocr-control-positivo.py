#!/usr/bin/env python3
"""Control positivo de ocr.review: el MISMO instrumento (envoltorio + ocr + LLM) sobre un malo conocido.
Repo temporal con una inyección SQL introducida en el árbol; --effort low para que cueste poco.
Imprime: 1 detectado · 0 ciego · 2 no pudo mirar. Cuesta una llamada al LLM (~15 s, ~40k tokens)."""
import os, subprocess, sys, tempfile
AQUI = os.path.dirname(os.path.abspath(__file__))
BUENO = 'export async function buscar(pool: { query: (q: string, p: string[]) => Promise<unknown> }, email: string) {\n  return pool.query("SELECT id FROM customers WHERE email = $1", [email]);\n}\n'
MALO = 'export async function buscar(pool: { query: (q: string) => Promise<unknown> }, email: string) {\n  return pool.query(`SELECT id FROM customers WHERE email = \'${email}\'`);\n}\n'
with tempfile.TemporaryDirectory() as t:
    def git(*a): return subprocess.run(["git", "-C", t, *a], capture_output=True, text=True)
    git("init", "-q", "-b", "main")
    open(os.path.join(t, "db.ts"), "w").write(BUENO)
    git("add", "-A"); git("-c", "user.name=cp", "-c", "user.email=cp@example.invalid", "commit", "-qm", "base")
    open(os.path.join(t, "db.ts"), "w").write(MALO)
    if open(os.path.join(t, "db.ts")).read() != MALO:
        print("no pude escribir el malo conocido"); sys.exit(2)
    r = subprocess.run([sys.executable, os.path.join(AQUI, "ocr-review.py"), "--effort", "low"], cwd=t, capture_output=True, text=True, timeout=900)
    if r.returncode == 1 and "db.ts:" in r.stdout:
        print("1 inyección SQL plantada; el mismo instrumento la detectó"); sys.exit(1)
    if r.returncode == 0:
        print("1 inyección SQL plantada; el instrumento NO la vio (ciego)"); sys.exit(0)
    print(f"el instrumento no pudo mirar su control conocido (código {r.returncode}): {(r.stdout + r.stderr).strip()[-300:]}"); sys.exit(2)
