---
description: "Cancel the active typed-loop"
allowed-tools: ["Bash(test -f .claude/typed-loop.local.md:*)", "Bash(rm .claude/typed-loop.local.md)", "Read(.claude/typed-loop.local.md)"]
hide-from-slash-command-tool: "true"
---

# Cancel typed-loop

1. Check existence: `test -f .claude/typed-loop.local.md && echo EXISTS || echo NOT_FOUND`
2. **NOT_FOUND** → say "No active typed-loop."
3. **EXISTS** → read the `iteration:` field, then `rm .claude/typed-loop.local.md`, and report
   "Cancelled typed-loop (was at iteration N)."
