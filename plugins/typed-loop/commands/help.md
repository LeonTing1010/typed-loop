---
description: "Explain typed-loop and its commands"
allowed-tools: ["Bash(${CLAUDE_PLUGIN_ROOT}/scripts/setup-typed-loop.sh:*)"]
hide-from-slash-command-tool: "true"
---

# typed-loop help

```!
"${CLAUDE_PLUGIN_ROOT}/scripts/setup-typed-loop.sh" --help
```

**Commands**
- `/typed-loop <PROMPT> --verify '<cmd>' [--max-iterations N] [--red-team [N]] [--human-gate]` — start
- `/cancel-typed-loop` — stop the active loop
- `/typed-loop:help` — this help

**Why it differs from ralph-loop (one sentence):** ralph decides "done" by
matching an agent-emitted `<promise>` string (the agent judges itself);
typed-loop decides "done" by running an external command and reading its exit
code (an oracle outside the agent). Everything else — the ratchet, the
decreasing measure, red-team-until-dry, the human gate — follows from moving
the oracle out of the token stream.
