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

```
/plugin marketplace add LeonTing1010/typed-loop
/plugin install typed-loop
```

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
