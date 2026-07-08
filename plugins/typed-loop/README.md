# typed-loop

A **well-typed agentic loop** — the typed successor to `ralph-loop`.

> ralph-loop decides *done* by matching an agent-emitted `<promise>` string — the
> agent is the oracle of its own termination. **typed-loop decides *done* by
> running an external `verify` command and reading its exit code** — an oracle
> that lives *outside* the agent's token stream. Same shell-loop shape; the stop
> condition moved from the agent's mouth to an exit code.

## Install

Add the `tap` marketplace (this repo) and install:

```
/plugin marketplace add LeonTing1010/taprun
/plugin install typed-loop@tap
```

## Use

```
/typed-loop Fix the failing tests in src/ --verify 'npm test'
/typed-loop Add feature X --verify 'bash verify.sh' --red-team --max-iterations 40
/typed-loop Rewrite the onboarding copy --human-gate     # unformalizable → human judges
/cancel-typed-loop
```

Copy `scripts/verify.sh.template` into your repo, fill in your real gates
(typecheck → tests → mutation → arch — the CDD verify pyramid), and pass it as
`--verify 'bash verify.sh'`. Have it print `TYPED_LOOP_FAILS=<n>` for a
fine-grained decreasing measure.

## Why (the six requirements → where each is enforced)

This plugin is the deterministic-layer realization of a "well-typed Ralph". Each
requirement lives in bash/hook/git — **not** in agent judgment:

| # | Requirement | Enforced by |
|---|---|---|
| 1 | git checkpoint per accepted iteration (state-level determinism) | `hooks/stop-hook.sh` (progress branch commits a checkpoint) |
| 2 | invariant gate + **revert-on-regression** ratchet | `hooks/stop-hook.sh` (`reset --hard` to `last_good_sha` when the measure rises) |
| 3 | stop = machine predicate + decreasing measure + honest **L0 human gate** | `stop-hook.sh` runs `verify_cmd`; `TYPED_LOOP_FAILS` measure; `--human-gate` stops into review |
| 4 | forbid "unbounded + no predicate" (make the pathological state unrepresentable) | `scripts/setup-typed-loop.sh` entry **guard** (refuses to create it) |
| 5 | red-team **until-dry** | `stop-hook.sh` green-branch drives adversarial rounds until K clean (`<dry/>`) |
| 6 | oracle **independent** of the looped agent | the deciding signal is `verify_cmd`'s exit code, run by the hook, not the agent |

**Honest limits.** (4) is a *runtime guard*, not a true type — CC has no type
system over loop configs, so the pathological state is refused at the entry point
rather than being uninhabitable. Token-level replay is impossible (you don't
control LLM sampling); the ratchet gives *state-level* reproducibility (git), which
is what the spec needs. The ratchet requires a git repo; without one the gate and
measure still apply but checkpoint/revert are skipped.

Composes with the `taprun` methodology plugin: `verify.sh` **is** the CDD verify
pyramid, the red-team pass **is** CDD's author-independent red-team, and the human
gate **is** CDD's L0 (unformalizable referent → human oracle, never a fake test).

## Files

```
typed-loop/
├── .claude-plugin/plugin.json
├── hooks/
│   ├── hooks.json            registers the Stop hook (the driver)
│   └── stop-hook.sh          the loop driver — all six requirements in bash
├── scripts/
│   ├── setup-typed-loop.sh   entry + req4 guard
│   └── verify.sh.template     the independent-oracle contract (per-repo)
└── commands/{typed-loop,cancel-typed-loop,help}.md
```
