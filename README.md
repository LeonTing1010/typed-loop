# typed-loop

A **well-typed agentic loop** for [Claude Code](https://claude.com/claude-code) — the typed successor to `ralph-loop`.

> `ralph-loop` decides *done* by matching an agent-emitted `<promise>` string — the
> agent is the oracle of its own termination. **`typed-loop` decides *done* by
> running an external `verify` command and reading its exit code** — an oracle
> that lives *outside* the agent's token stream. Same shell-loop shape; the stop
> condition moved from the agent's mouth to an exit code.

That one change is load-bearing. A loop is only as trustworthy as its stop
condition, and a stop condition the looped agent judges for itself is a
self-consistency check, not a convergence guarantee. `typed-loop` moves the
oracle — and the whole control structure — into deterministic bash + git, so the
agent is just the (nondeterministic) step function inside a harness it cannot
talk its way out of.

## Install

### Requirements

- **[Claude Code](https://claude.com/claude-code)** (the plugin registers a `Stop` hook).
- **`jq`** — required; the hook parses Claude Code's hook I/O with it.
  `brew install jq` (macOS) · `apt install jq` (Debian/Ubuntu).
- **`git`** — required for the ratchet (per-iteration checkpoint + revert-on-regression).
  Without a git repo the verify gate and the decreasing measure still work; only
  checkpoint/revert are skipped.
- **bash + coreutils** (`sed`, `awk`, `grep`, `mktemp`, `date`) — default on macOS/Linux.

### Steps

1. Add this repo as a plugin marketplace:

   ```
   /plugin marketplace add LeonTing1010/typed-loop
   ```

2. Install the plugin (the marketplace and the plugin are both named `typed-loop`;
   the `@typed-loop` suffix names the marketplace):

   ```
   /plugin install typed-loop@typed-loop
   ```

3. If the `/typed-loop` command or the `Stop` hook doesn't appear immediately,
   **restart Claude Code** so the plugin's hook registers.

### Verify it installed

- Run `/plugin` and confirm **typed-loop** shows as installed/enabled, **or**
- type `/typed-loop:help` — you should get the usage text.

### First run

```
# 1. Copy the gate contract into your repo and fill in your real checks:
cp <plugin>/scripts/verify.sh.template ./verify.sh
#    edit verify.sh → typecheck, tests, etc.; exit 0 when green.

# 2. Start a loop gated on it:
/typed-loop Fix the failing tests in src/ --verify 'bash verify.sh'
```

The loop now runs until `verify.sh` exits 0 (or a bound / human hand-off). While
it's red, the same prompt returns with the failures appended; a regression is
reverted to the last-good checkpoint. Stop it early with `/cancel-typed-loop`.

### Update / uninstall

```
/plugin marketplace update typed-loop     # pull the latest version
/plugin uninstall typed-loop@typed-loop   # remove it
```

### Troubleshooting

- **`jq: command not found`** in the hook → install `jq` (see Requirements).
- **The loop won't stop** → that's by design; it ends only when `verify` exits 0,
  the `--max-iterations` bound is hit, or (with `--human-gate`) you hand off. Use
  `/cancel-typed-loop` to end it manually.
- **"ratchet disabled (no git repo)"** → run inside a git repo to get
  checkpoint/revert; the gate and measure work regardless.

## Use

```
/typed-loop Fix the failing tests in src/ --verify 'npm test'
/typed-loop Add feature X --verify 'bash verify.sh' --red-team --max-iterations 40
/typed-loop Rewrite the onboarding copy --human-gate     # unformalizable → a human judges
/cancel-typed-loop
```

Copy `scripts/verify.sh.template` into your repo, fill in your real gates
(typecheck → tests → mutation → arch), and pass it as `--verify 'bash verify.sh'`.
Have it print `TYPED_LOOP_FAILS=<n>` for a fine-grained decreasing measure.

## What "well-typed" means here — six requirements, each enforced in bash/hook/git (never agent judgment)

| # | Requirement | Enforced by |
|---|---|---|
| 1 | git checkpoint per accepted iteration (state-level determinism) | `hooks/stop-hook.sh` progress branch commits a checkpoint |
| 2 | invariant gate + **revert-on-regression** ratchet | `hooks/stop-hook.sh` — `reset --hard` to `last_good_sha` when the measure rises |
| 3 | stop = machine predicate + decreasing measure + honest **L0 human gate** | `stop-hook.sh` runs `verify_cmd`; `TYPED_LOOP_FAILS` measure; `--human-gate` stops into review |
| 4 | forbid "unbounded + no predicate" (make the pathological state unrepresentable) | `scripts/setup-typed-loop.sh` entry **guard** refuses to create it |
| 5 | red-team **until-dry** | `stop-hook.sh` green branch drives adversarial rounds until K clean (`<dry/>`) |
| 6 | oracle **independent** of the looped agent | the deciding signal is `verify_cmd`'s exit code, run by the hook, not the agent |

## How it works

`hooks/hooks.json` registers a `Stop` hook. Every time the agent tries to end its
turn, `stop-hook.sh` reads `.claude/typed-loop.local.md`, runs the external verify
command, and decides:

- **gate RED** → block; the same prompt returns with the real failures appended.
  The failure count is a *decreasing measure* — a **regression** (count rises) is
  `reset --hard` to the last-good checkpoint, so the loop never walks backward.
- **gate GREEN** → if `--red-team` is on, run adversarial completeness rounds
  (find a wrong-but-passing case → add a failing check + fix; output `<dry/>` when
  a round genuinely finds nothing) until `N` clean rounds, then ship.
- **`--human-gate`** → for acceptance that isn't machine-checkable, stop *into*
  human review on `<ready-for-review/>` — the agent never certifies correctness
  itself.

You cannot end the loop by asserting you are done. There is no promise string to
emit; the only exits are `verify` exiting 0, reaching the bound, or handing off to
a human.

## Honest limits

- **(4) is a runtime guard, not a true type.** Claude Code has no type system over
  loop configs, so the "unbounded + no predicate" state is *refused at the entry
  point* rather than being uninhabitable.
- **Token-level replay is impossible** (you don't control LLM sampling). The
  ratchet gives *state-level* reproducibility via git — which is what the spec
  needs.
- **The ratchet needs a git repo.** Without one, the verify gate and decreasing
  measure still apply; checkpoint/revert are skipped.

## Provenance

`typed-loop` is the terminal artifact of a first-principles analysis: deterministic
simulation testing → dependent types → *"can you state correct precisely?"* → the
observation that an agentic loop's whole worth is its oracle, and the oracle must
live outside the looped agent. The `Stop`-hook mechanism is forked from Anthropic's
`ralph-loop` plugin; the stop condition and the ratchet are the new part.

Composes with the [`taprun`](https://github.com/LeonTing1010/taprun) methodology
plugins: `verify.sh` **is** the CDD verify pyramid, the red-team pass **is** CDD's
author-independent red-team, and the human gate **is** CDD's L0 (unformalizable
referent → human oracle, never a fake test).

## License

MIT © 2026 Leo ([LeonTing1010](https://github.com/LeonTing1010))
