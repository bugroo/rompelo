# rompelo

*Spanish for "break it."*

**Your coding agent cannot say "done" until a check that has been seen to fail says so.**

`rompelo` is a completion gate for AI coding agents. It plugs into the `Stop` hook of
Claude Code and Codex, reads a small contract for the current task, and blocks the agent from
finishing until the evidence exists: checks that ran on the current code, a real request
through the deployed path when two systems have to agree, findings with a decision, claims
with a source. Ordinary code decides, outside the model. Green results that could not have
been red do not count.

Documentación en español: [README.es.md](README.es.md).

## How it works

![How it works: the agent says done, the Stop hook calls rompelo, rompelo reads the contract and compares it with the evidence; missing evidence blocks with reasons, everything met means silence](docs/img/en/como-funciona.png)

## The problem it is built around

![Bar chart of 28 real incidents by class: blind instrument 8, signal at Stop 6, context 4, mixed 3, tool time 3, audit 2, runtime 2](docs/img/en/corpus.png)

Twenty-eight real incidents from one month of agent-written code, each written down with what
looked green at the moment the agent said "done" ([corpus/TABLA.md](corpus/TABLA.md), generated
from [incidents/](incidents/)). The largest class is not "the test failed". It is "the check
could not fail": a validator run on the wrong artifact, a guard that crashed and exited with
the code reserved for a real finding, a `0` after a timeout, "no tests" read as zero failures, a
mutation that never applied. A careful model does not catch these, because nothing looks
inconsistent. Only forcing the check to fail does.

## What the agent sees

![Real hook output: the task cannot be marked done; two checks not run; boundary touched and no real crossing recorded](docs/img/en/bloqueo.png)

The agent receives the exact list of unmet conditions and keeps working. Three blocks per task
and session; after that `rompelo` warns the user and lets go, so nobody gets trapped.

## Every gate was seen red before it was trusted

![Three steps: start from green, confirmed mutation turns it red, undo it and it is green again](docs/img/en/rojo-primero.png)

The test battery (63 cases, run in CI on every push) applies this cycle to every condition of the
gate itself. When a mutation is used to force red, the test first confirms the mutation actually
happened. A mutation that did not apply proves nothing, and that mistake is in the corpus twice.

## What the gate enforces

A repo opts in with `rompelo init`, which writes `.rompelo/task.json` and adds the repo to a local
allowlist. From then on the agent cannot end a task until:

| Condition | Satisfied by |
|---|---|
| every check id ran on the **current** working-tree content (content fingerprint, not the commit) | `rompelo check`. Ids resolve through your `checks/registry.json` (argv, no shell). Output is never stored, only exit code, duration and a hash |
| a check that exits 0 without its declared minimum output is **not** green | `min_lineas` in the registry |
| if the task touches an integration boundary, a real crossing **after** the last change | `rompelo cruce -- <real command>` or `--id <registered check>` |
| every finding has a disposition | `hallazgos` in the contract |
| every claim about the outside world has a state | `afirmaciones`: `verificado` needs a primary source and a verbatim quote, `derivado` needs what it derives from, `no_verificado` needs what is missing |
| every changed file is inside `scope_paths` | or widen the scope on purpose |
| if required, a test file is part of the diff | green is not covered |

What it deliberately does not do:

- It never executes strings found in the repository. The contract only carries ids; an injected
  command is rejected without running (proven with a canary file in the battery).
- It stays silent in repos outside the allowlist, so a foreign `.rompelo/` folder hooks nothing.
- It never reads command output, which could contain secrets.
- It fails closed: an unreadable contract in an enrolled repo blocks.
- It has no dependencies. Python 3.9 standard library and git.

## Install

```bash
git clone https://github.com/bugroo/rompelo ~/rompelo
cp ~/rompelo/checks/registry.example.json ~/rompelo/checks/registry.local.json   # your checks
```

`registry.local.json` is where your commands live, one id each, as argv:

```json
{
  "my-app.test": {"argv": ["pnpm", "test"], "cwd": "repo", "min_lineas": 1},
  "my-app.smoke": {"argv": ["node", "scripts/smoke.mjs"], "cwd": "repo"}
}
```

Then connect the hook:

- **Claude Code**: add the `Stop` entry from
  [`adapters/claude/settings-fragment.json`](adapters/claude/settings-fragment.json) to
  `~/.claude/settings.json`.
- **Codex**: merge [`adapters/codex/hooks.json`](adapters/codex/hooks.json) into
  `~/.codex/hooks.json` and trust the hook in `/hooks`. Details in
  [`adapters/codex/LEEME.md`](adapters/codex/LEEME.md).

## Use

```bash
cd your-repo
~/rompelo/bin/rompelo init --id T-42 --scope 'src/**' --check my-app.test --junta
# ... the agent works ...
~/rompelo/bin/rompelo check                                   # runs the registered checks, records evidence
~/rompelo/bin/rompelo cruce --nota "real request" -- curl -sf https://…   # the real crossing
~/rompelo/bin/rompelo close                                   # refuses if anything is missing
```

`rompelo verify` shows the current verdict at any time. `rompelo --help` lists everything.
The gate's messages are in Spanish today; English messages are on the roadmap.

## Verified, and not

- 63 cases in [`tests/rompelo-stop-test.sh`](tests/rompelo-stop-test.sh), each condition seen
  red with a confirmed mutation, then green. CI runs them on Ubuntu on every push.
- The Claude Code side has been crossed live: ending a turn with an unmet contract returned the
  block with the right reasons, and the configured `settings.json` line is replayed by
  [`tests/cruce-settings-claude.sh`](tests/cruce-settings-claude.sh), which has been seen to
  return all three of its exit codes.
- **Not verified:** the Codex side live. The adapter follows the official hook contract; the
  install and trust steps belong to the user. The observation layer in
  [docs/observacion.md](docs/observacion.md) is a design, not code.

## Roadmap, in order

1. Positive control per registered check: the instrument must detect a known-bad input before its green counts.
2. Observation layer: three triggers (task risk, repeated error signature, claims about the world) that raise rigor with a warning first, and ask once before spending on external checks.
3. Plain-language closing report: what was checked and seen failing, what could not be checked, what is the user's to decide.
4. `rompelo verify --ci` as the independent judge in pull requests.
5. Incidents that compile into registered checks, so a lesson becomes a detector instead of prose.

## Related work

[Agentic OS](https://github.com/KbWen/agentic-os) enforces a phased workflow with evidence through
git hooks and CI. [Hermes Agent](https://github.com/NousResearch/hermes-agent) learns skills from
experience. Mutation testing tools such as Stryker and PIT measure test strength. `rompelo` sits
next to them and adds the part none of them checks: that the check itself was looking.

MIT.
