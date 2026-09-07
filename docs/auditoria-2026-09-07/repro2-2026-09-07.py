import importlib.util, importlib.machinery, os, subprocess, tempfile, json, shutil
H = tempfile.mkdtemp(prefix="rompelo-home-"); os.environ["ROMPELO_HOME"] = H
loader = importlib.machinery.SourceFileLoader("rompelo", os.environ.get("ROMPELO_BIN") or os.path.expanduser("~/rompelo/bin/rompelo"))
spec = importlib.util.spec_from_loader("rompelo", loader); R = importlib.util.module_from_spec(spec); loader.exec_module(R)
def sh(*a, cwd=None): return subprocess.run(list(a), cwd=cwd, capture_output=True, text=True)
def repo():
    d = tempfile.mkdtemp(prefix="rompelo-repo-"); sh("git","init","-q",cwd=d); sh("git","config","user.email","x@x",cwd=d); sh("git","config","user.name","x",cwd=d); sh("git","config","core.quotePath","true",cwd=d); return os.path.realpath(d)
def commit(d): sh("git","add","-A",cwd=d); sh("git","commit","-q","-m","c",cwd=d)
def w(d,p,s): open(os.path.join(d,p),"w").write(s)
def rep(k, ok, det=""): print(f"{'REPRODUCIDO' if ok else 'NO reproducido'}  {k}  {det}")

# año.py: primera modificación vs segunda (entre dos estados sucios)
d = repo(); w(d,"año.py","a\n"); w(d,"run.sh","#!/bin/sh\n"); commit(d); b = R.head(d)
w(d,"año.py","b\n"); h1 = R.huella_arbol(d,b); w(d,"año.py","c\n"); h2 = R.huella_arbol(d,b)
rep("RMP-001a año.py: b→c NO cambia la huella (se firma como borrado)", h1 == h2, f"cambiados={R.ficheros_cambiados(d,b)}")
# ¿y el scope? scope_paths=['año.py'] → ¿fuera de scope por la ruta entrecomillada?
fuera = [p for p in R.ficheros_cambiados(d,b) if not any(R.casa(p,s) for s in ["año.py","*.py"])]
rep("RMP-001a' año.py sale como FUERA de scope aunque '*.py' lo cubra", bool(fuera), f"fuera={fuera}")
# +x sobre fichero ya modificado
w(d,"run.sh","#!/bin/sh\necho x\n"); h3 = R.huella_arbol(d,b); os.chmod(os.path.join(d,"run.sh"),0o755); h4 = R.huella_arbol(d,b)
rep("RMP-001b +x sobre fichero ya modificado NO cambia la huella", h3 == h4)
# +x sobre fichero limpio: sí cambia (aparece la entrada)
# symlink: ln→t2 vs ln→t3, contenido idéntico, ambos distintos del commit
d2 = repo(); w(d2,"t1.txt","same\n"); w(d2,"t2.txt","same\n"); w(d2,"t3.txt","same\n"); os.symlink("t1.txt",os.path.join(d2,"ln")); commit(d2); b2 = R.head(d2)
os.remove(os.path.join(d2,"ln")); os.symlink("t2.txt",os.path.join(d2,"ln")); s1 = R.huella_arbol(d2,b2)
os.remove(os.path.join(d2,"ln")); os.symlink("t3.txt",os.path.join(d2,"ln")); s2 = R.huella_arbol(d2,b2)
rep("RMP-001c symlink t2→t3 (mismo contenido) NO cambia la huella", s1 == s2)
# tabulador en nombre
d3 = repo(); w(d3,"a\tb.py","1\n"); commit(d3); b3 = R.head(d3); w(d3,"a\tb.py","2\n"); t1 = R.huella_arbol(d3,b3); w(d3,"a\tb.py","3\n"); t2 = R.huella_arbol(d3,b3)
rep("RMP-001e nombre con tabulador: 2→3 NO cambia la huella", t1 == t2, f"cambiados={R.ficheros_cambiados(d3,b3)}")
# ¿y con core.quotePath=false (config de usuario)? comprobar el valor global real de esta máquina
print("core.quotePath global en esta máquina:", sh("git","config","--global","core.quotePath").stdout.strip() or "(sin fijar → true por defecto)")
shutil.rmtree(H, ignore_errors=True)
