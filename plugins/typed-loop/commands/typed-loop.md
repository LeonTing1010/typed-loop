---
description: "Start a typed-loop: the stop condition is an external verify command, not your self-judged promise"
argument-hint: "PROMPT --verify '<cmd>' [--max-iterations N] [--red-team [N]] [--human-gate]"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-typed-loop.sh:*)"]
hide-from-slash-command-tool: "true"
---

# typed-loop

Initialize the loop (the guard refuses unbounded + no-predicate):

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-typed-loop.sh" $ARGUMENTS
```

Now work on the task. When you try to exit, the Stop hook runs the **external
verify command** and decides for you:

- **Gate RED** → the same prompt returns with the real failures appended. The
  failure count is a *decreasing measure*: make it go down. Any **regression**
  (count goes up) is `reset --hard` to the last-good checkpoint — the loop
  never walks backward, so don't worry about breaking a prior fix; the ratchet
  will catch it.
- **Gate GREEN** → if `--red-team` is on, you'll be asked to adversarially hunt
  for a wrong-but-passing case for a few rounds (add a failing check + fix it if
  you find one; output `<dry/>` when a round genuinely finds nothing). Then it
  ships.
- **`--human-gate`** → when the work is ready for a *human* to judge (for
  acceptance that isn't machine-checkable), output `<ready-for-review/>` to hand
  off. Do not certify correctness yourself.

CRITICAL: you **cannot** end this loop by asserting you are done. The oracle is
the external command's exit code, which lives outside your token stream. The only
way out is to make `verify` exit 0 (or reach the bound / hand off to a human).
Trying to "escape" is pointless — there is no promise string to emit.
