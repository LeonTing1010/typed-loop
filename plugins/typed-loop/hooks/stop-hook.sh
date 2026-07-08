#!/bin/bash
# typed-loop Stop hook — the deterministic loop driver.
#
# Forked from ralph-loop's stop-hook. The ONE load-bearing change:
# ralph decides "done" by matching an agent-emitted <promise> string
# (a self-judged oracle, living in the agent's token stream).
# typed-loop decides "done" by running an EXTERNAL verify command and
# reading its exit code — an oracle that lives OUTSIDE the agent.
#
# It also adds, in deterministic bash (never agent judgment):
#   req1  git checkpoint per accepted iteration
#   req2  revert-on-regression ratchet (reset --hard to last good)
#   req3  stop = machine predicate (verify exit 0) + decreasing failure measure
#   req3  L0 human gate for unformalizable acceptance (stop INTO review, never self-ship)
#   req5  red-team-until-dry (K consecutive adversarial rounds find nothing)
#   req6  the deciding oracle (verify cmd) is independent of the looped agent
#
# The entry guard for req4 (forbid unbounded + no-predicate) lives in
# scripts/setup-typed-loop.sh, which refuses to create such a state.

set -euo pipefail

HOOK_INPUT=$(cat)
STATE_FILE=".claude/typed-loop.local.md"

[[ -f "$STATE_FILE" ]] || exit 0   # no active loop → allow exit

fm() { sed -n '/^---$/,/^---$/{ /^---$/d; p; }' "$STATE_FILE"; }
field() { fm | grep "^$1:" | head -1 | sed "s/^$1: *//" | sed 's/^"\(.*\)"$/\1/'; }

ITERATION=$(field iteration)
MAX_ITERATIONS=$(field max_iterations)
VERIFY_CMD=$(field verify_cmd)
MODE=$(field mode)
LAST_GOOD_SHA=$(field last_good_sha)
LAST_FAIL_COUNT=$(field last_fail_count)
REDTEAM=$(field redteam)
DRY_TARGET=$(field dry_target)
DRY_ROUNDS=$(field dry_rounds)
HUMAN_GATE=$(field human_gate)
STATE_SESSION=$(field session_id || true)

# Session isolation: don't block sessions that didn't start this loop.
HOOK_SESSION=$(echo "$HOOK_INPUT" | jq -r '.session_id // ""')
if [[ -n "$STATE_SESSION" ]] && [[ "$STATE_SESSION" != "$HOOK_SESSION" ]]; then
  exit 0
fi

# Numeric sanity (corrupt state → stop, don't loop on garbage).
for pair in "iteration:$ITERATION" "max_iterations:$MAX_ITERATIONS" "last_fail_count:$LAST_FAIL_COUNT" "dry_rounds:$DRY_ROUNDS" "dry_target:$DRY_TARGET"; do
  name=${pair%%:*}; val=${pair#*:}
  if [[ ! "$val" =~ ^[0-9]+$ ]]; then
    echo "⚠️  typed-loop: state field '$name' is not a number (got '$val'); stopping." >&2
    rm -f "$STATE_FILE"; exit 0
  fi
done

# Bound reached (req4's second leg): stop.
if [[ "$MAX_ITERATIONS" -gt 0 ]] && [[ "$ITERATION" -ge "$MAX_ITERATIONS" ]]; then
  echo "🛑 typed-loop: max iterations ($MAX_ITERATIONS) reached without the gate going green." >&2
  echo "   Not shipped — the machine predicate was never satisfied. Inspect and rerun." >&2
  rm -f "$STATE_FILE"; exit 0
fi

# ---- helper: last assistant text block from the transcript (ralph's robust path) ----
last_assistant_text() {
  local tp; tp=$(echo "$HOOK_INPUT" | jq -r '.transcript_path // ""')
  [[ -f "$tp" ]] || { echo ""; return; }
  local lines; lines=$(grep '"role":"assistant"' "$tp" 2>/dev/null | tail -n 100 || true)
  [[ -n "$lines" ]] || { echo ""; return; }
  echo "$lines" | jq -rs 'map(.message.content[]? | select(.type=="text") | .text) | last // ""' 2>/dev/null || echo ""
}

# ---- helper: run the independent oracle. Echoes "<exit> <failcount>"; saves output to $VERIFY_OUT ----
VERIFY_OUT=""
run_verify() {
  VERIFY_OUT=$(mktemp)
  set +e
  eval "$VERIFY_CMD" >"$VERIFY_OUT" 2>&1
  local ec=$?
  set -e
  local fc
  # Fine-grained measure if the gate emits it; else binary (0 pass / 1 fail).
  fc=$(grep -oE 'TYPED_LOOP_FAILS=[0-9]+' "$VERIFY_OUT" | tail -1 | grep -oE '[0-9]+' || true)
  if [[ -z "$fc" ]]; then
    if [[ $ec -eq 0 ]]; then fc=0; else fc=1; fi
  fi
  echo "$ec $fc"
}

git_here() { git rev-parse --is-inside-work-tree >/dev/null 2>&1; }

# ---- helper: write updated state (atomic) ----
set_field() {  # set_field <name> <value>   (value written raw; quote strings yourself)
  local n="$1" v="$2" tmp="${STATE_FILE}.tmp.$$"
  sed "s#^$n: .*#$n: $v#" "$STATE_FILE" > "$tmp" && mv "$tmp" "$STATE_FILE"
}

PROMPT_TEXT=$(awk '/^---$/{i++; next} i>=2' "$STATE_FILE")
NEXT=$((ITERATION + 1))

# feed_back <reason-suffix> <system-msg> : block the stop, send prompt+suffix back.
feed_back() {
  local suffix="$1" msg="$2"
  set_field iteration "$NEXT"
  jq -n --arg p "$PROMPT_TEXT" --arg s "$suffix" --arg m "$msg" \
    '{decision:"block", reason: ($p + "\n\n---\n" + $s), systemMessage: $m}'
  exit 0
}

ship() {  # gate satisfied → stop cleanly
  local msg="$1"
  echo "$msg"
  rm -f "$STATE_FILE"
  exit 0
}

# ============================ decision tree ============================

# Mode A: no machine oracle — human-gate-only loop (unformalizable referent).
# Legitimate ONLY because setup's guard required human_gate=true here.
# The agent may request the human's verdict with <ready-for-review/>; the loop
# then STOPS INTO REVIEW. It never self-certifies correctness.
if [[ -z "$VERIFY_CMD" ]]; then
  OUT=$(last_assistant_text)
  if echo "$OUT" | grep -q '<ready-for-review/>'; then
    ship "🧑‍⚖️ typed-loop: agent requested human review (L0 gate). NOT verified by machine — a human must judge acceptance. Loop stopped for hand-off."
  fi
  feed_back \
"[typed-loop iter $NEXT · human-gate mode] No machine predicate exists for this referent (it is a human/taste judgment). Keep working. When — and ONLY when — the work is genuinely ready for a human to judge, output the exact token <ready-for-review/> to hand off. Do not claim correctness yourself." \
"🔁 typed-loop $NEXT · human gate (output <ready-for-review/> to hand off)"
fi

# Mode B: machine-gated loop. Run the independent oracle.
read -r EC FAILS <<<"$(run_verify)"
VOUT=$(tail -c 4000 "$VERIFY_OUT" 2>/dev/null || true); rm -f "$VERIFY_OUT"

if [[ "$EC" -eq 0 ]]; then
  # ---- gate GREEN ----
  # Unformalizable shell over a formal core: even with a green machine gate,
  # a human must sign off. Stop into review, don't self-ship.
  if [[ "$HUMAN_GATE" == "true" ]]; then
    ship "✅🧑‍⚖️ typed-loop: machine gate GREEN, but human_gate is on — acceptance has an unformalizable part. Stopped for human sign-off (NOT auto-shipped)."
  fi

  # red-team-until-dry (req5): before shipping, spend K adversarial rounds
  # trying to find a wrong-but-passing implementation. Each clean round that
  # ends in <dry/> increments dry_rounds; finding a hole makes the gate red
  # again next iteration (dry_rounds resets in the FAIL branch).
  if [[ "$REDTEAM" == "true" ]] && [[ "$DRY_ROUNDS" -lt "$DRY_TARGET" ]]; then
    OUT=$(last_assistant_text)
    if [[ "$MODE" == "redteam" ]] && echo "$OUT" | grep -q '<dry/>'; then
      DR=$((DRY_ROUNDS + 1))
      set_field dry_rounds "$DR"
      if [[ "$DR" -ge "$DRY_TARGET" ]]; then
        ship "✅ typed-loop: gate GREEN and red-team DRY ($DR/$DRY_TARGET clean rounds). Shipped. last_good=$LAST_GOOD_SHA"
      fi
      feed_back \
"[typed-loop iter $NEXT · red-team $DR/$DRY_TARGET] Gate is green and the last adversarial round found nothing. Do ANOTHER independent adversarial pass from a DIFFERENT angle: what input class, boundary, or interaction is not covered by any check in verify? If you find a wrong-but-passing case, ADD a failing check to the gate and fix it. If, after genuine effort, you find nothing, output <dry/>." \
"🗡️ typed-loop $NEXT · red-team $DR/$DRY_TARGET"
    fi
    # enter (or stay in) red-team mode
    set_field mode redteam
    feed_back \
"[typed-loop iter $NEXT · red-team 0/$DRY_TARGET] The machine gate (verify) is GREEN — but a green gate only proves the checks you wrote, not the checks you forgot. Act as an adversary: find a case that is WRONG in real use yet PASSES verify (missing property, unhandled boundary, cross-feature interaction). If you find one, ADD it as a failing check to the gate and fix the code. If after genuine effort you find nothing, output the exact token <dry/>." \
"🗡️ typed-loop $NEXT · red-team (adversarial completeness pass)"
  fi

  # no red-team (or dry target already met) → ship
  ship "✅ typed-loop: gate GREEN — the external verify command exits 0. Shipped at iteration $ITERATION. last_good=$LAST_GOOD_SHA"
fi

# ---- gate RED ---- (req2 ratchet + req1 checkpoint + req3 decreasing measure)
set_field mode normal
set_field dry_rounds 0

RATCHET_NOTE=""
if git_here; then
  CUR=$(git rev-parse HEAD 2>/dev/null || echo "")
  if [[ "$FAILS" -lt "$LAST_FAIL_COUNT" ]]; then
    # PROGRESS: measure strictly decreased → accept as new last-good checkpoint.
    git add -A >/dev/null 2>&1 || true
    git reset -q -- "$STATE_FILE" >/dev/null 2>&1 || true  # never checkpoint the loop's own bookkeeping
    if ! git diff --cached --quiet 2>/dev/null; then
      git commit -q -m "typed-loop: iter $ITERATION checkpoint (fails=$FAILS)" >/dev/null 2>&1 || true
      CUR=$(git rev-parse HEAD 2>/dev/null || echo "$CUR")
    fi
    set_field last_good_sha "\"$CUR\""
    set_field last_fail_count "$FAILS"
    RATCHET_NOTE="Progress: failures $LAST_FAIL_COUNT → $FAILS. Checkpoint committed as last-good ($CUR)."
  elif [[ "$FAILS" -gt "$LAST_FAIL_COUNT" ]]; then
    # REGRESSION: measure increased → revert the ratchet to last-good.
    # Protect the loop's own state file across the hard reset (it must survive
    # even if some earlier `git add -A` swept it into a tracked commit).
    if [[ -n "$LAST_GOOD_SHA" ]]; then
      _tl_save=$(mktemp); cp "$STATE_FILE" "$_tl_save"
      git reset --hard "$LAST_GOOD_SHA" >/dev/null 2>&1 || true
      mkdir -p "$(dirname "$STATE_FILE")"           # reset --hard may drop the (now-untracked) .claude/ dir
      cp "$_tl_save" "$STATE_FILE"; rm -f "$_tl_save"
      RATCHET_NOTE="REGRESSION reverted: failures rose $LAST_FAIL_COUNT → $FAILS, so the working tree was reset --hard to last-good ($LAST_GOOD_SHA). The loop never walks backward. Take a DIFFERENT approach this iteration."
    else
      RATCHET_NOTE="Regression (failures $LAST_FAIL_COUNT → $FAILS) but no last-good checkpoint to revert to yet."
    fi
  else
    RATCHET_NOTE="No net progress: failures stayed at $FAILS. The decreasing measure did not move — change approach rather than repeating."
  fi
else
  # No git → gate + measure still work, but no checkpoint/revert ratchet.
  if [[ "$FAILS" -lt "$LAST_FAIL_COUNT" ]]; then set_field last_fail_count "$FAILS"; fi
  RATCHET_NOTE="(no git repo → ratchet disabled; verify gate + measure still enforced). failures now=$FAILS."
fi

feed_back \
"[typed-loop iter $NEXT] The external verify gate is RED ($FAILS failing). $RATCHET_NOTE

verify output (tail):
$VOUT

Read the failures above, fix the cause, and let the loop re-run verify. The loop stops ONLY when verify exits 0 — you cannot end it by asserting you are done." \
"🔁 typed-loop $NEXT · gate RED ($FAILS) $( [[ -n "$RATCHET_NOTE" ]] && echo '· ratchet active' )"
