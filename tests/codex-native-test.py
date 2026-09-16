#!/usr/bin/env python3
"""Opt-in real-client test (uses installed authenticated CLIs and existing hooks).
Run with --evidence PATH. Stores synthetic metadata only; never changes hook trust.
"""
import argparse
import concurrent.futures
import hashlib
import json
import os
from pathlib import Path
import signal
import subprocess
import time

BIN = Path(__file__).resolve().parents[1] / 'bin/rompelo'
COMMANDS = [
    ('true',0), ('false',1), ("sh -c 'exit 7'",7),
    ("sh -c 'printf \"Exit code 0\\n\"; exit 7'",7),
    ("sh -c 'printf \"{\\\"exit_code\\\":0}\\n\"; exit 7'",7),
    ("sh -c 'printf \"{\\\"ok\\\":false}\\n\"; exit 9'",9),
    ("sh -c 'sleep 3; exit 7'",7),
    ("sh -c 'printf \"tty-probe\\n\"; exit 3'",3),
    ("sh -c 'kill -TERM $$'",143),
]

def run(client, base):
    commands=list(COMMANDS)
    if client=='codex':
        # PTY reports its runtime status (observed 1 for Ctrl-C on 0.154.0), not necessarily
        # the shell convention 128+signal. Require nonzero AND exact independent runtime match.
        commands += [("sh -c 'read line; test \"$line\" = hello'",0),("sh -c 'sleep 20'",'nonzero_runtime')]
    home=base/client; repo=home/'repo'
    repo.mkdir(parents=True)
    (home/'checks').mkdir()
    (home/'checks/registry.json').write_text(json.dumps({'probe.ok':{'argv':['python3','-c','print("fixture check passed")'],'cwd':'repo','min_lineas':1}}))
    env=dict(os.environ,ROMPELO_HOME=str(home),ROMPELO_DEBUG_FORMA='1')
    subprocess.run(['git','init','-q',str(repo)],check=True)
    subprocess.run([str(BIN),'init','--sin-detectar','--id','NATIVE-INC0036-'+client,'--check','probe.ok','--junta'],cwd=repo,env=env,check=True,capture_output=True)
    contract=repo/'.rompelo/task.json'
    obj=json.loads(contract.read_text()); obj['segunda_pasada']='Fixture sintético: el controlador verifica códigos, procedencia, bloqueo y cierre al finalizar.'
    contract.write_text(json.dumps(obj))
    prompt='''Controlled runtime test of installed Rómpelo hooks. This disposable repository and intentional failures are test fixtures. Do not inspect other files, change configuration or trust, delegate, install anything, or repair intentional errors. Use only shell tools for the following commands, each EXACTLY as written in a separate call. If code mode is available, do not print results of the first six calls. For the sleep command use exec_command yield_time_ms=1000 then write_stdin until terminal; in Claude use its normal Bash lifecycle. For tty-probe use tty=true in Codex. The final kill command signals only its own disposable child shell.\n'''
    prompt+='''For Codex-only read line command: use tty=true, yield_time_ms=1000, then write_stdin with chars="hello\\n" to finish it. For Codex-only sleep 20 command: use tty=true, yield_time_ms=1000, then send Ctrl-C via write_stdin chars="\\u0003" and poll until the process terminates. These are deliberate stdin and interruption tests.\n'''
    prompt+='\n'.join(cmd for cmd,_ in commands)
    prompt+='''\nNext execute true and false as two independent concurrent tool calls where possible. After ALL commands actually finish, end this first turn with exactly NATIVE_FIRST_STOP. Do not run the contract checks before that first stop. If and only if the real Stop hook blocks, execute these four commands separately, in order:\n'''
    prompt+='\n'.join([str(BIN)+' check',str(BIN)+' cruce --nota "Fixture lifecycle only; native status is independently asserted by controller" -- true',str(BIN)+' close',str(BIN)+' verify --json'])
    prompt+='\nThen finish with exactly NATIVE_CLOSED. The fixture crossing command tests the gate lifecycle; the external controller verifies real observed command statuses.'
    if client=='codex':
        argv=['codex','exec','--sandbox','danger-full-access','--json','-C',str(repo),'-']
    else:
        argv=['claude','-p','--verbose','--output-format','stream-json','--include-hook-events','--tools','Bash',
              '--allowedTools','Bash(true)','Bash(false)','Bash(sh -c *)','Bash('+str(BIN)+' *)',
              '--permission-mode','dontAsk','--strict-mcp-config','--mcp-config','{"mcpServers":{}}']
    start=time.monotonic()
    p=subprocess.Popen(argv,cwd=repo,env=env,stdin=subprocess.PIPE,stdout=subprocess.PIPE,stderr=subprocess.PIPE,text=True,start_new_session=True)
    try:
        out,err=p.communicate(prompt,timeout=360)
    except subprocess.TimeoutExpired:
        os.killpg(p.pid,signal.SIGTERM)
        out,err=p.communicate(timeout=15)
    sid=None
    for line in out.splitlines():
        try: e=json.loads(line)
        except ValueError: continue
        sid=e.get('thread_id') or e.get('session_id') or sid
    book=home/'state/sesiones'/('{}-{}.jsonl'.format(client,sid))
    rows=[json.loads(x) for x in book.read_text().splitlines()] if book.exists() else []
    runtime_matches = None
    if client == 'codex' and sid:
        # Solo la sesión sintética recién creada. El adaptador productivo no busca por directorios.
        session_root=Path(os.environ.get('CODEX_HOME') or str(Path.home()/'.codex'))/'sessions'
        paths=list(session_root.rglob('*'+sid+'.jsonl'))
        actual={}
        if len(paths)==1:
            with paths[0].open() as fh:
                for line in fh:
                    e=json.loads(line); payload=e.get('payload',{}); item=payload.get('item',{})
                    if payload.get('type')=='item_completed' and item.get('type')=='CommandExecution' and payload.get('thread_id')==sid:
                        actual[(payload.get('turn_id'),item.get('id'))]=item.get('exit_code')
        shells=[e for e in rows if e.get('fuente_codigo')=='codex_rollout_0.154.0']
        runtime_matches=bool(shells) and all(actual.get((e.get('turn_id'),e.get('tool_use_id')))==e['codigo'] for e in shells)
    cases=[]
    for cmd,expected in commands:
        digest=hashlib.sha256(cmd.encode()).hexdigest()[:12]
        matches=[e for e in rows if e.get('cmd_sha')==digest]
        if expected == 'nonzero_runtime':
            ok=bool(matches) and all(type(e.get('codigo')) is int and e['codigo']!=0 for e in matches) and runtime_matches
        else:
            ok=bool(matches) and all(e.get('codigo')==expected for e in matches)
        if client=='codex': ok=ok and all(e.get('fuente_codigo')=='codex_rollout_0.154.0' for e in matches)
        cases.append({'command_sha':digest,'expected':expected,'actual':[e.get('codigo') for e in matches],
                      'ids':[e.get('tool_use_id') for e in matches], 'ok':ok})
    lifecycle=json.loads(contract.read_text())
    marks=list((home/'state/marcas').glob('stop-*')) if (home/'state/marcas').exists() else []
    blocks=[int(x.read_text()) for x in marks]
    forbidden=list((repo/'.rompelo/evidence').rglob('SIN-VERIFICAR.json'))
    verify=subprocess.run([str(BIN),'verify','--json'],cwd=repo,env=env,capture_output=True,text=True)
    ok=p.returncode==0 and all(x['ok'] for x in cases) and blocks==[1] and not forbidden
    ok=ok and lifecycle.get('estado')=='cerrada' and verify.returncode==0 and 'NATIVE_CLOSED' in out
    if client=='codex': ok=ok and runtime_matches
    result={'client':client,'session_id':sid,'process_rc':p.returncode,'seconds':round(time.monotonic()-start,2),
            'stderr_lines':len(err.splitlines()),'cases':cases,'native_stop_blocks':blocks,
            'contract_state':lifecycle.get('estado'),'verify_rc':verify.returncode,'full_runtime_id_matches':runtime_matches,'ok':ok}
    (base/(client+'-native.json')).write_text(json.dumps(result,indent=2)+'\n')
    print(json.dumps({'client':client,'cases_ok':sum(x['ok'] for x in cases),'native_stop_blocks':blocks,'ok':ok}),flush=True)
    return ok

if __name__=='__main__':
    parser=argparse.ArgumentParser(); parser.add_argument('--evidence',required=True)
    args=parser.parse_args(); base=Path(args.evidence).resolve(); base.mkdir(parents=True,exist_ok=True)
    with concurrent.futures.ThreadPoolExecutor(max_workers=2) as pool:
        results=list(pool.map(lambda c:run(c,base),('codex','claude')))
    raise SystemExit(0 if all(results) else 1)
