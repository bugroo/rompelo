# rompelo

*Spanish for "break it."*

**Your coding agent cannot say "done" until a check that has been seen to fail says so.**

A completion gate for AI coding agents (Claude Code and Codex today, one adapter each).
Rules files ask the agent to behave; `rompelo` checks that it did, with ordinary code, outside
the model, and it refuses green results that could not have been red.

Spanish documentation: [README.es.md](README.es.md). The design notes and the incident corpus
are in Spanish too; the code and the test names are self-explanatory.

## Why this exists

Twenty-eight real incidents from one month of agent-written code, classified by what was
visible at the moment the agent said "done" ([corpus/TABLA.md](corpus/TABLA.md)):

| Class | Count | What it means |
|---|---|---|
| **I · blind instrument** | 8 | the check could not fail: wrong artifact, crash exiting with the "finding" code, `0` after a timeout, "no tests" read as zero failures, a mutation that never applied |
| S · signal at Stop | 6 | a real request, a browser, or the diff itself would have shown it |
| C · context | 4 | measured one scope, claimed another |
| T · tool time | 3 | `bash -x` leaking secrets, `git stash -u` deleting files, `UPDATE` on production |
| A · audit | 2 | a finding archived without a decision; two audits of one commit disagreeing |
| R · runtime | 2 | only visible days later in production |
| M · mixed | 3 | |

Most of them had green tests. That is the problem `rompelo` is built around: **a green result
is not information until you have seen it go red.**

## What the gate enforces

A repo opts in with `rompelo init`, which writes `.rompelo/task.json` (the contract) and adds the
repo to a local allowlist. From then on the agent's `Stop` hook calls `rompelo hook <agent>`,
and the agent cannot end the task until:

| Condition | How it is satisfied |
|---|---|
| every check id ran on the **current** working-tree content (content fingerprint) | `rompelo check`. Ids resolve through `checks/registry.json` (argv, no shell). Output is never stored, only exit code, duration and a hash |
| a check that exits 0 without its declared minimum output is **not** green | `min_lineas` in the registry: "clean" must be distinguishable from "did not look" |
| if the task touches an integration boundary, a real crossing **after** the last change | `rompelo cruce -- <real command>` or `--id <registered check>` |
| every finding has a disposition | `hallazgos` in the contract |
| every claim about the outside world has a state | `afirmaciones`: `verificado` needs a primary source and a verbatim quote, `derivado` needs what it derives from, `no_verificado` needs what is missing |
| every changed file is inside `scope_paths` | or widen the scope on purpose |
| if required, a test file is part of the diff | green is not covered |

What it deliberately does not do: it never executes strings found in the repository (the
contract only carries ids; an injected command is rejected without running, proven with a
canary), it stays silent in repos outside the allowlist, it never reads command output, and it
fails closed (an unreadable contract in an enrolled repo blocks). Three blocks per session and
task, then it warns and lets go.

## Install

```bash
git clone https://github.com/bugroo/rompelo ~/rompelo
cp ~/rompelo/checks/registry.example.json ~/rompelo/checks/registry.local.json   # your checks
```

Claude Code: add the `Stop` entry from `adapters/claude/settings-fragment.json` to
`~/.claude/settings.json`. Codex: merge `adapters/codex/hooks.json` into `~/.codex/hooks.json`
and trust the hook in `/hooks` (see `adapters/codex/LEEME.md`).

Requirements: Python 3.9+, git. No dependencies for the gate. `PyYAML` only for regenerating
the corpus table.

## Use

```bash
cd your-repo
~/rompelo/bin/rompelo init --id T-42 --scope 'src/**' --check mi-proyecto.test --junta
# work
~/rompelo/bin/rompelo check
~/rompelo/bin/rompelo cruce --nota "real request through the deployed path" -- curl -sf https://…
~/rompelo/bin/rompelo close
```

## Verified, and not

- 60 cases in `tests/rompelo-stop-test.sh`, each gate seen red with a mutation that was
  confirmed to apply, then green. Runs in CI on every push.
- The Claude Code side has been crossed live: ending a turn with an unmet contract returned
  the block with the right reasons.
- **Not verified:** the Codex side live (adapter follows the official hook contract; the
  install and trust steps are the user's), and the observation layer in
  [docs/observacion.md](docs/observacion.md), which is a design, not code.

## Roadmap, in order

1. Positive control per registered check: the instrument must detect a known-bad input before its green counts.
2. Observation layer: three triggers (task risk, repeated error signature, claims about the world), escalating rigor with a warning first.
3. Plain-language closing report: what was checked and seen failing, what could not be checked, what is yours to decide.
4. CI adapter (`rompelo verify --ci`) as the independent judge.
5. Incidents that compile into registered checks, so a lesson becomes a detector instead of prose.

## Related work

[Agentic OS](https://github.com/KbWen/agentic-os) enforces a phased workflow with evidence
through git hooks and CI; [Hermes Agent](https://github.com/NousResearch/hermes-agent) learns
skills from experience; mutation testing tools (Stryker, PIT) measure test strength. `rompelo`
sits next to them and adds the part none of them checks: that the check itself was looking.

MIT.
