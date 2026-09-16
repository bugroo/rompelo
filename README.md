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

1. **Hooks.** Claude Code: add the `PreToolUse` (matcher `Bash`), `UserPromptSubmit`, `Stop`, `PostToolUse`
   and `PostToolUseFailure` entries from
   [`adapters/claude/settings-fragment.json`](adapters/claude/settings-fragment.json) to
   `~/.claude/settings.json`. Codex: merge [`adapters/codex/hooks.json`](adapters/codex/hooks.json)
   (same five events minus `PostToolUseFailure`) into `~/.codex/hooks.json` and trust the hook in `/hooks`
   (details in [`adapters/codex/LEEME.md`](adapters/codex/LEEME.md), Spanish). `rompelo doctor` tells you
   which events are missing.
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
(`rompelo check --id …`, `rompelo revisar …`, `rompelo cruce …`, `rompelo close`); `rompelo check` warns when a
check itself changed the tree. Two sessions on the same root share one `.rompelo/task.json`: `init --force`
replaces the other session's contract, so give each session its own worktree.

## When the gate fires

By default (`entrega`, since 2026-09-16) the gate stays silent while the agent works and fires when the work
is **delivered**:

- `PreToolUse` denies a `git commit`, `git push`, `gh pr create`, `wrangler deploy`, `scripts/desplegar.sh`…
  while the contract is unmet, with the reasons and the `Next:` line. Any other command passes untouched.
- `UserPromptSubmit` recognises the user asking to finish ("termina", "sube esto", "haz el commit", "ship it",
  "to production"…), declares the close and tells the agent what is still missing before it starts.
- `Stop` judges only once the close is declared (by the user, or by a failed `rompelo close`), and goes quiet
  again once the task really closes.

`turno` (the previous behaviour, judged at the end of every turn) is one line away: `"defecto": "turno"` in
[`config/disparo.json`](config/disparo.json), per repo under `por_repo`, or `rompelo init --disparo turno`.
Patterns for "delivers" and "asks to finish" live in the same file. [Details](docs/disparo.md) (Spanish).

## What the gate requires

- Every contract check run on the **current** tree (content fingerprint, not the commit). Exit 0
  with no output is not green (`min_lineas`); a check that does not finish or start is an
  instrument failure, not a finding; a positive control that misses the known-bad case voids the green.
  A check may declare in the registry the paths that cannot change its verdict (`no_afecta`:
  docs, images) and the only paths it looks at (`afecta`: a shell linter and `*.sh`): a check whose
  paths did not change does not apply, neither required nor run, and does not go stale because of a `.ts`.
- **The diff dictates the contract.** [`config/obliga.json`](config/obliga.json) (and `.rompelo/obliga.json`
  in the repo, versioned so CI sees it) maps paths to obligations: `functions/api/**` → boundary crossing,
  `*.sh` → the shell check, `src/**` → typecheck + test + a test in the diff. A changed path that matches adds
  them to the effective contract whether the agent declared them or not.
- If the task touches a boundary, a real crossing after the last change.
- Every finding as `confirmado` (+ regression), `rechazado` (+ reason; for security, bug, concurrency, memory,
  compat and data findings also `comprobado`: what was run or read that refutes it) or `aceptado` (+ note).
- At observation level 2, a real second pass: `rompelo revisar` opens a manifest with every changed file,
  its diff, the rules (`ocr delegate rule` when [open-code-review](https://github.com/alibaba/open-code-review)
  is installed, no LLM call) and the criterion; `rompelo revisar --cerrar` requires every file reviewed or
  skipped with a reason on the current fingerprint and moves the findings into the contract.
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
