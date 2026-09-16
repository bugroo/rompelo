#!/usr/bin/env python3
"""Regression tests for status provenance. Synthetic transcripts, no real history."""
import importlib.machinery
import importlib.util
import json
import os
from pathlib import Path
import subprocess
import tempfile
import unittest
from unittest.mock import patch
import concurrent.futures

BIN = Path(__file__).resolve().parents[1] / 'bin/rompelo'
loader = importlib.machinery.SourceFileLoader('rompelo_status', str(BIN))
spec = importlib.util.spec_from_loader(loader.name, loader)
rompelo = importlib.util.module_from_spec(spec)
loader.exec_module(rompelo)

class StatusTests(unittest.TestCase):
    def setUp(self):
        self.temp = tempfile.TemporaryDirectory()
        self.root = Path(self.temp.name).resolve()
        self.env = dict(os.environ, ROMPELO_HOME=str(self.root/'home'), CODEX_HOME=str(self.root/'codex'))
        self.transcript = self.root/'codex/sessions/test.jsonl'
        self.transcript.parent.mkdir(parents=True)

    def tearDown(self):
        self.temp.cleanup()

    def event(self, response='', **extra):
        event = {'session_id':'s','turn_id':'t','tool_use_id':'exec-x','cwd':str(self.root),
            'hook_event_name':'PostToolUse','tool_name':'Bash','tool_input':{'command':'false'},
            'tool_response':response,'transcript_path':str(self.transcript)}
        event.update(extra)
        return event

    def meta(self, **extra):
        payload={'id':'s','cli_version':'0.154.0'}; payload.update(extra)
        return {'type':'session_meta','payload':payload}

    def end(self, code=7, ident='exec-x', turn='t', sid='s', **extra):
        item={'type':'CommandExecution','id':ident,'exit_code':code,
            'status':'completed' if code == 0 else 'failed'}
        item.update(extra)
        return {'type':'event_msg','payload':{'type':'item_completed','thread_id':sid,'turn_id':turn,'item':item}}

    def write(self, *rows):
        self.transcript.write_text(''.join(json.dumps(x)+'\n' for x in rows))

    def observe(self, response='', **extra):
        event = self.event(response, **extra)
        result = subprocess.run([str(BIN),'observe','codex'], input=json.dumps(event), env=self.env,
            text=True,capture_output=True,timeout=5)
        self.assertEqual(result.returncode,0)
        self.assertEqual(result.stderr,'')
        path = self.root/'home/state/sesiones/codex-s.jsonl'
        return json.loads(path.read_text().splitlines()[-1])

    def resolve(self, cache=None, **extra):
        cache={} if cache is None else cache
        event=self.event(**extra)
        ev=rompelo.evento_desde_hook(event,'codex')
        with patch.dict(os.environ, self.env):
            rompelo.codex_reconciliar(event,[ev],cache)
        return ev,cache

    def test_stdout_exit_header_is_not_status(self):
        self.assertIsNone(self.observe('Exit code 0\n')['codigo'])

    def test_stdout_json_exit_code_is_not_status(self):
        self.assertIsNone(self.observe('{"exit_code":0}')['codigo'])

    def test_stdout_json_without_status_is_not_success(self):
        self.assertIsNone(self.observe('{"ok":false}')['codigo'])

    def test_native_status_wins_over_stdout(self):
        for code in (0,1,7,9,127,130,255):
            with self.subTest(code=code):
                self.write(self.meta(),self.end(code))
                row,_=self.resolve(response='Exit code 0\n{"exit_code":0}')
                self.assertEqual(row['codigo'],code)
                self.assertEqual(row['fuente_codigo'],'codex_rollout_0.154.0')

    def test_missing_and_wrong_identity(self):
        self.write(self.meta(),self.end())
        for kwargs in ({'session_id':'foreign'},{'turn_id':'wrong'},{'tool_use_id':'exec-'},
                       {'tool_use_id':None},{'turn_id':None},{'tool_use_id':'exec-y'}):
            with self.subTest(kwargs=kwargs):
                self.assertIsNone(self.resolve(**kwargs)[0]['codigo'])

    def test_invalid_codes_and_statuses(self):
        for code in (None,True,False,'0',-1,256,1.0):
            with self.subTest(code=repr(code)):
                self.write(self.meta(),self.end(code))
                self.assertIsNone(self.resolve()[0]['codigo'])
        for status in ('running','interrupted','unknown','completed'):
            self.write(self.meta(),self.end(7,status=status))
            self.assertIsNone(self.resolve()[0]['codigo'])

    def test_unknown_version_and_duplicate_header(self):
        for rows in ((self.meta(cli_version='0.155.0'),self.end()),
                     (self.meta(cli_version=[]),self.end()),
                     (self.meta(),self.meta(),self.end()),(self.end(),)):
            self.write(*rows)
            self.assertIsNone(self.resolve()[0]['codigo'])

    def test_duplicate_conflict_stays_unknown(self):
        self.write(self.meta(),self.end(),self.end())
        row,cache=self.resolve(); self.assertEqual(row['codigo'],7)
        with self.transcript.open('a') as fh: fh.write(json.dumps(self.end(0))+'\n')
        row,cache=self.resolve(cache); self.assertIsNone(row['codigo'])
        with self.transcript.open('a') as fh: fh.write(json.dumps(self.end(7))+'\n')
        self.assertIsNone(self.resolve(cache)[0]['codigo'])

    def test_foreign_and_nonruntime_records(self):
        for end in (self.end(sid='foreign'),self.end(type='Message'),
                    {'type':'response_item','payload':{'text':json.dumps(self.end())}}):
            self.write(self.meta(),end)
            self.assertIsNone(self.resolve()[0]['codigo'])

    def test_late_append_and_partial_record(self):
        self.write(self.meta())
        row,cache=self.resolve(); self.assertIsNone(row['codigo'])
        part=json.dumps(self.end())
        with self.transcript.open('a') as fh: fh.write(part[:30])
        row,cache=self.resolve(cache); self.assertIsNone(row['codigo'])
        with self.transcript.open('a') as fh: fh.write(part[30:]+'\n')
        row,cache=self.resolve(cache); self.assertEqual(row['codigo'],7)
        row,cache=self.resolve(cache); self.assertEqual(cache['bytes_ultima_lectura'],0)

    def test_rotation_and_truncate_regrow(self):
        self.write(self.meta(),self.end()); row,cache=self.resolve()
        self.transcript.rename(self.transcript.with_suffix('.old'))
        self.write(self.meta(),self.end(0)); row,cache=self.resolve(cache)
        self.assertEqual(row['codigo'],0)
        self.write(self.meta(),self.end(9),{'type':'response_item','payload':{'unused':'padding'*100}})
        row,cache=self.resolve(cache); self.assertEqual(row['codigo'],9)

    def test_invalid_json_and_large_line(self):
        for data in ('[]\n','bad\n','{"type":', 'x'*(rompelo.CODEX_LINEA+1)):
            self.transcript.write_text(data)
            self.assertIsNone(self.resolve()[0]['codigo'])

    def test_unapproved_paths_and_symlink(self):
        self.write(self.meta(),self.end())
        outside=self.root/'outside.jsonl'; outside.write_bytes(self.transcript.read_bytes())
        link=self.transcript.parent/'link.jsonl'; link.symlink_to(self.transcript)
        for p in (outside,link,self.transcript.parent):
            self.assertIsNone(self.resolve(transcript_path=str(p))[0]['codigo'])

    def test_byte_budget_and_resume(self):
        self.write(self.meta(),*[{'type':'response_item','payload':{'text':'x'*150}} for _ in range(50)],self.end())
        with patch.object(rompelo,'CODEX_BYTES',1024):
            row,cache=self.resolve(); self.assertIsNone(row['codigo'])
            self.assertLessEqual(cache['bytes_ultima_lectura'],1025)
            for _ in range(30): row,cache=self.resolve(cache)
            self.assertEqual(row['codigo'],7)

    def test_event_limit_fails_closed(self):
        self.write(self.meta(),self.end(0,'a'),self.end(7,'b'),self.end(7))
        with patch.object(rompelo,'CODEX_EVENTOS',2):
            row,cache=self.resolve()
            for _ in range(3): row,cache=self.resolve(cache)
            self.assertIsNone(row['codigo'])

    def test_large_compaction_does_not_hide_terminal_status(self):
        large={'timestamp':'2026-09-16T12:00:00Z','ordinal':363,'type':'compacted','payload':{'text':'x'*(5*1024*1024)}}
        self.write(self.meta(),large,self.end())
        row,cache=self.resolve(); self.assertIsNone(row['codigo'])
        for _ in range(4): row,cache=self.resolve(cache)
        self.assertEqual(row['codigo'],7)

    def test_no_raw_text_in_cache_or_book(self):
        marker='SYNTHETIC-PRIVATE-MARKER'
        self.write(self.meta(base_instructions=marker),self.end(stdout=marker,command=marker))
        row=self.observe(marker)
        self.assertEqual(row['codigo'],7)
        for p in (self.root/'home/state').rglob('*'):
            if p.is_file(): self.assertNotIn(marker,p.read_text())

    def test_duplicate_hooks_and_concurrent_writes(self):
        self.write(self.meta(),*[self.end(i%2,'exec-'+str(i)) for i in range(12)])
        with concurrent.futures.ThreadPoolExecutor(max_workers=6) as pool:
            list(pool.map(lambda i:self.observe(tool_use_id='exec-'+str(i%12)),range(24)))
        rows=[json.loads(x) for x in (self.root/'home/state/sesiones/codex-s.jsonl').read_text().splitlines()]
        self.assertEqual(len(rows),12)
        self.assertEqual({r['tool_use_id']:r['codigo'] for r in rows},{'exec-'+str(i):i%2 for i in range(12)})

    def test_late_result_keeps_original_order(self):
        event=self.event(tool_input={'command':'pnpm test'})
        first=rompelo.evento_desde_hook(event,'codex'); first['orden_ms']=1000
        edit={'orden_ms':2000,'ficheros':['/repo/a.py'],'repo':'/repo'}
        first['repo']='/repo'; book=[first,edit]
        self.write(self.meta(),self.end(0))
        with patch.dict(os.environ,self.env): rompelo.codex_reconciliar(event,book,{})
        self.assertIs(book[0],first)
        self.assertEqual(first['codigo'],0)
        self.assertIs(book[1],edit)

    def test_stop_reconciles_and_escalates(self):
        subprocess.run(['git','init','-q',str(self.root)],check=True)
        home=self.root/'home'; (home/'config').mkdir(parents=True)
        (home/'config/repos.json').write_text(json.dumps({'repos':[str(self.root)]}))
        self.write(self.meta())
        self.observe(tool_input={'command':'pnpm test'},tool_use_id='exec-a')
        self.observe(tool_input={'command':'pnpm test'},tool_use_id='exec-b')
        with self.transcript.open('a') as fh:
            for i in ('exec-a','exec-b'): fh.write(json.dumps(self.end(7,i))+'\n')
        result=subprocess.run([str(BIN),'hook','codex'],input=json.dumps(self.event(hook_event_name='Stop')),
            env=self.env,text=True,capture_output=True,timeout=5)
        self.assertEqual(result.returncode,0)
        states=list((home/'state/repos').glob('*.json')); self.assertEqual(len(states),1)
        state=json.loads(states[0].read_text())
        self.assertIn('check-en-rojo',state['patrones'])
        self.assertEqual(state['nivel'],2)

    def test_claude_success_and_failure_unchanged(self):
        event=self.event(tool_response={'stdout':'Exit code 7','stderr':'','interrupted':False})
        self.assertEqual(rompelo.evento_desde_hook(event,'claude')['codigo'],0)
        event.update(hook_event_name='PostToolUseFailure',error='Exit code 7\nError: intentional')
        self.assertEqual(rompelo.evento_desde_hook(event,'claude')['codigo'],7)

if __name__ == '__main__':
    unittest.main()
