#!/bin/bash
# typed-loop setup — writes the loop state file, AFTER enforcing the req4 guard.
#
# req4: "unbounded + no predicate" is forbidden BY CONSTRUCTION. A loop must have
# at least one terminating authority:
#   --verify '<cmd>'      a machine predicate (exit 0 = done)   [UntilPredicate]
#   --max-iterations <n>  a hard bound                          [Bounded]
#   --human-gate          an honest human terminal              [UntilHuman]
# Supplying none is refused here — you cannot create the pathological state.

set -euo pipefail

PROMPT_PARTS=()
MAX_ITERATIONS=0
VERIFY_CMD=""
HUMAN_GATE="false"
REDTEAM="false"
DRY_TARGET=2

usage() {
  cat <<'H'
typed-loop — a well-typed agentic loop (the typed successor to ralph-loop)

The loop STOPS when an external verify command exits 0 — never when the agent
says so. Ships a git ratchet (checkpoint + revert-on-regression), a decreasing
failure measure, red-team-until-dry, and an honest human gate.

USAGE
  /typed-loop <PROMPT...> [OPTIONS]

OPTIONS
  --verify '<cmd>'        Machine oracle. Exits 0 when done. e.g. --verify 'bash verify.sh'
                          The gate MAY print a line  TYPED_LOOP_FAILS=<n>  for a
                          fine-grained decreasing measure; otherwise pass/fail is binary.
  --max-iterations <n>    Hard bound (0 = unbounded; allowed ONLY if --verify is set).
  --human-gate            Acceptance has an unformalizable part: stop INTO human review
                          instead of self-shipping (works with or without --verify).
  --red-team [<n>]        Before shipping, run adversarial completeness rounds until <n>
                          (default 2) consecutive rounds find nothing. Needs --verify.
  -h, --help              This help.

REQUIRED: at least one of  --verify  /  --max-iterations  /  --human-gate.

EXAMPLES
  /typed-loop Fix failing tests in src/ --verify 'npm test'
  /typed-loop Add feature X --verify 'bash verify.sh' --red-team --max-iterations 40
  /typed-loop Rewrite the onboarding copy --human-gate   # unformalizable → human judges

RATCHET needs a git repo (checkpoint + revert-on-regression). Without git the
verify gate and decreasing measure still apply; checkpoint/revert are skipped.
H
}

while [[ $# -gt 0 ]]; do
  case $1 in
    -h|--help) usage; exit 0 ;;
    --verify)
      [[ -n "${2:-}" ]] || { echo "❌ --verify requires a command, e.g. --verify 'npm test'" >&2; exit 1; }
      VERIFY_CMD="$2"; shift 2 ;;
    --max-iterations)
      [[ "${2:-}" =~ ^[0-9]+$ ]] || { echo "❌ --max-iterations requires a non-negative integer" >&2; exit 1; }
      MAX_ITERATIONS="$2"; shift 2 ;;
    --human-gate) HUMAN_GATE="true"; shift ;;
    --red-team)
      REDTEAM="true"
      if [[ "${2:-}" =~ ^[0-9]+$ ]]; then DRY_TARGET="$2"; shift 2; else shift; fi ;;
    *) PROMPT_PARTS+=("$1"); shift ;;
  esac
done

PROMPT="${PROMPT_PARTS[*]:-}"
[[ -n "$PROMPT" ]] || { echo "❌ No prompt provided. See /typed-loop --help" >&2; exit 1; }

# ---- req4 GUARD: forbid unbounded + no-predicate ----
if [[ -z "$VERIFY_CMD" ]] && [[ "$MAX_ITERATIONS" -eq 0 ]] && [[ "$HUMAN_GATE" != "true" ]]; then
  cat >&2 <<'G'
❌ typed-loop refuses to start: unbounded + no stop predicate.

   A loop with no terminating authority is the pathological state this plugin
   exists to make unrepresentable. Give it at least one:

     --verify '<cmd>'      (machine predicate — the recommended default)
     --max-iterations <n>  (a hard bound)
     --human-gate          (stop into human review)

   This is the ONE thing ralph-loop let you do that typed-loop will not.
G
  exit 1
fi

# red-team needs a machine gate to be adversarial against
if [[ "$REDTEAM" == "true" ]] && [[ -z "$VERIFY_CMD" ]]; then
  echo "❌ --red-team needs --verify (there must be a gate to attack). Add --verify '<cmd>'." >&2
  exit 1
fi
[[ "$REDTEAM" == "true" ]] || DRY_TARGET=0

mkdir -p .claude

LAST_GOOD_SHA=""
if git rev-parse --is-inside-work-tree >/dev/null 2>&1; then
  LAST_GOOD_SHA=$(git rev-parse HEAD 2>/dev/null || echo "")
fi

cat > .claude/typed-loop.local.md <<EOF
---
active: true
iteration: 1
session_id: ${CLAUDE_CODE_SESSION_ID:-}
max_iterations: $MAX_ITERATIONS
verify_cmd: "$VERIFY_CMD"
mode: normal
last_good_sha: "$LAST_GOOD_SHA"
last_fail_count: 999999
redteam: $REDTEAM
dry_target: $DRY_TARGET
dry_rounds: 0
human_gate: $HUMAN_GATE
started_at: "$(date -u +%Y-%m-%dT%H:%M:%SZ)"
---

$PROMPT
EOF

BOUND_DESC="unbounded"; [[ "$MAX_ITERATIONS" -gt 0 ]] && BOUND_DESC="$MAX_ITERATIONS"
GATE_DESC="none"; [[ -n "$VERIFY_CMD" ]] && GATE_DESC="$VERIFY_CMD"

cat <<EOF
🔒 typed-loop activated — the stop condition is a machine predicate, not your word.

  Machine oracle : $GATE_DESC
  Max iterations : $BOUND_DESC
  Red-team       : $( [[ "$REDTEAM" == "true" ]] && echo "on (dry target $DRY_TARGET)" || echo "off" )
  Human gate     : $HUMAN_GATE
  Ratchet        : $( git rev-parse --is-inside-work-tree >/dev/null 2>&1 && echo "on (git checkpoint + revert-on-regression)" || echo "off (no git repo)" )

The Stop hook now runs the oracle on every exit attempt. While the gate is RED,
the same prompt returns with the failures appended, the metric must strictly
decrease, and any regression is reset --hard to the last-good checkpoint. You
cannot end the loop by claiming you are done — only by making verify exit 0.

$PROMPT
EOF
