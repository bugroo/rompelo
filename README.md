# rompelo

**Your coding agent cannot say "done" until a check that has been seen failing says so.**

A closing gate for Claude Code and Codex. It hooks into `Stop`, reads a small per-task contract and
does not let the task end until the evidence exists: checks run on the current tree, a real crossing
when two systems must agree, findings with a decision. Plain code decides, outside the model.
Python 3.9 and git on macOS or Linux, no dependencies.

![The agent says done, the Stop hook calls rompelo, rompelo compares contract and evidence; if something is missing it blocks with reasons, if everything holds there is silence](docs/img/en/como-funciona.png)

## Install

```bash
git clone https://github.com/bugroo/rompelo ~/rompelo
```

1. **Hooks.** Claude Code: add the `Stop`, `PostToolUse` and `PostToolUseFailure` entries from
   [`adapters/claude/settings-fragment.json`](adapters/claude/settings-fragment.json) to
   `~/.claude/settings.json`. Codex: merge [`adapters/codex/hooks.json`](adapters/codex/hooks.json)
   into `~/.codex/hooks.json` and trust the hook in `/hooks` (details in
   [`adapters/codex/LEEME.md`](adapters/codex/LEEME.md), Spanish).
2. **Skill**, so the agent knows what to do when it reads `/rompelo`:
   ```bash
   mkdir -p ~/.claude/skills/rompelo && cp ~/rompelo/adapters/skill/SKILL.md ~/.claude/skills/rompelo/
   mkdir -p ~/.codex/skills/rompelo  && cp ~/rompelo/adapters/skill/SKILL.md ~/.codex/skills/rompelo/
   ```
3. **Checks.** Your commands live in `~/rompelo/checks/registry.local.json`, one id per command, as
   argv (no shell). Or let `rompelo init` detect them from `package.json`, `pyproject.toml`,
   `Cargo.toml`, `go.mod` or the `Makefile`.
   ```json
   {"my-app.test": {"argv": ["pnpm", "test"], "cwd": "repo", "min_lineas": 1, "timeout": 600}}
   ```
4. `rompelo doctor` confirms hooks, registry and allowlist.

## Use

Three ways to tell the agent:

1. `/rompelo <task>` in Claude Code, `$rompelo <task>` in Codex. It reads the skill and opens its contract.
2. Without the skill, at the top of the task: *"This task runs behind rompelo: `rompelo init --force
   --id <ID> --scope '<paths>' --check <ids> [--junta] [--prueba]`. Do not call it done until
   `rompelo close` closes green; whatever you cannot meet, write it as NOT VERIFIED."*
3. Nothing. With the repo enrolled and a contract open, `Stop` blocks anyway and hands the agent the
   exact commands.

By hand:

```bash
cd your-repo
rompelo init --id T-42 --scope 'src/**' --check my-app.test --junta   # contract + enroll the repo
# ... the agent works ...
rompelo check                                  # runs the checks and stores evidence (may take minutes)
rompelo cruce --nota "real request" -- curl -sf https://…   # the real crossing, AFTER the last change
rompelo close                                  # refuses if anything is missing; prints the report
```

Every block ends with a `Next:` line carrying the exact commands that unblock, in order
(`rompelo check --id …`, `rompelo cruce …`, `rompelo close`); `rompelo check` warns when a check itself
changed the tree. Two sessions on the same root share one `.rompelo/task.json`: `init --force` replaces
the other session's contract, so give each session its own worktree.

## What the gate requires

- Every contract check run on the **current** tree (content fingerprint, not the commit). Exit 0
  with no output is not green (`min_lineas`); a check that does not finish or start is an
  instrument failure, not a finding; a positive control that misses the known-bad case voids the green.
  A check may declare in the registry the paths that cannot change its verdict (`no_afecta`:
  docs, images), so editing the README after the suite does not force a re-run; everything else does.
- If the task touches a boundary, a real crossing after the last change.
- Every finding as `confirmado` (+ regression), `rechazado` (+ reason) or `aceptado` (+ note).
- Every claim about the outside world as `verificado` (source + quote), `derivado` or `no_verificado`.
- Nothing changed outside `scope_paths`; with `--prueba`, a test in the diff.
- The observer raises the rigor on its own (second pass, crossing by profile, level-3 checks with
  `rompelo permiso`) when it sees repeated errors, editing without checking, or auth, secrets, data,
  deploy or boundary paths being touched.

Evidence never stores command arguments or output. The contract only carries ids: no text from the
repo is executed. Repos outside the allowlist: silence. Unreadable contract: block.

## CI

Copy [`adapters/ci/rompelo-gate.yml`](adapters/ci/rompelo-gate.yml) to `.github/workflows/`. It re-runs
the checks on a runner where the agent has written nothing and reports per obligation: `PASS`,
`FAIL`, `ERROR`, `SKIPPED`, `WAIVED`. "OK PARTIAL" means something (boundary, `solo_local`) is only
crossed outside CI. Consumer registry: `ROMPELO_REGISTRO=repo` reads `.rompelo/registry.json`.

## The limit

The agent can edit its contract and write evidence by hand. The gate stops carelessness, not a
determined cheat; the independent judge is `verify --ci`. Green here means "I found none of my
kind", not "it is fine".

## More

[Full documentation](docs/README-completo.md) · [observation layer](docs/observacion.md) (Spanish) ·
[corpus of 48 real incidents](corpus/TABLA.md) · [audit of 2026-09-07](docs/auditoria-2026-09-07/SEGUIMIENTO.md) ·
[changelog](CHANGELOG.md). MIT license.
