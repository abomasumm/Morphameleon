#!/usr/bin/env bash
# loop.sh: run the pipeline. Start it in a tmux/screen window:
#   tmux new -s agents '.agents/loop.sh'
# Every LOOP_SLEEP seconds (profile-dependent): the scheduler starts queued tasks, then the orchestrator
# tick wakes the orchestrator if a decision is waiting. Once a day after COS_HOUR: status note.
#
#   .agents/loop.sh --until-settled   stop once nothing more can happen without a person, and write why to
#                                     .agents/logs/outcome (used by the GitHub Action):
#                                     done | needs-you | limit-calls | limit-time
# Limits for --until-settled: MAX_MODEL_CALLS (per run; new work stops there, so tasks already running can add a
# few), TIME_LIMIT_MINUTES, GRACE_MINUTES (how long running tasks may finish after a limit), STALL_SECONDS (no change for this long means a person is needed).
set -uo pipefail
source "$(cd "$(dirname "$0")" && pwd)/lib.sh"
GOALS="$AG/goals"
OUTCOMES='gate-|b2|flaky'
model_calls() { local n; n=$(grep -cvE ",($OUTCOMES)[a-z]*," "$LOGS/runs.csv" 2>/dev/null); echo "${n:-0}"; }
goal_list() { local f; for f in "$GOALS"/G-*.md; do [ -f "$f" ] && echo "$f"; done; }
running_tasks() { local f n=0; for f in $(task_files); do case "$(fm_get "$f" status)" in claimed|building|gating|reviewing)
  pid_alive "$(fm_get "$f" pid)" && n=$((n+1)) ;; esac; done; echo "$n"; }
waiting_on_clock() { local f nb; for f in $(task_files); do [ "$(fm_get "$f" status)" = queued ] || continue
  nb=$(fm_get "$f" not_before); [ -n "$nb" ] && [ "$(date +%s)" -lt "$nb" ] && return 0; done; return 1; }
all_goals_done() { local f any=no; for f in $(goal_list); do any=yes; [ "$(fm_get "$f" status)" = "done" ] || return 1; done; [ $any = yes ]; }
fingerprint() { { for f in $(goal_list) $(task_files); do echo "$f $(fm_get "$f" status) $(fm_get "$f" attempt)"; done
  cat "$LOGS/runs.csv" 2>/dev/null | wc -l; } | cksum; }
stop_running() { local f pid; for f in $(task_files); do case "$(fm_get "$f" status)" in claimed|building|gating|reviewing)
  pid=$(fm_get "$f" pid); pid_alive "$pid" && { pkill -TERM -P "$pid" 2>/dev/null; kill -TERM "$pid" 2>/dev/null; } ;; esac; done; }

until_settled() {
  local t0 calls0 fp last_fp="" last_change limit="" limit_at=0
  local max=${MAX_MODEL_CALLS:-200} mins=${TIME_LIMIT_MINUTES:-300} grace=${GRACE_MINUTES:-30} stall=${STALL_SECONDS:-480}
  t0=$(date +%s); calls0=$(model_calls); last_change=$t0
  rm -f "$LOGS/outcome"
  while true; do
    if [ -z "$limit" ]; then
      [ $(( $(model_calls) - calls0 )) -ge "$max" ] && limit=limit-calls
      [ $(( $(date +%s) - t0 )) -ge $(( mins * 60 )) ] && limit=limit-time
      [ -n "$limit" ] && { limit_at=$(date +%s); echo "$(now) $limit reached; no new work starts"; }
    fi
    if [ -n "$limit" ]; then
      [ "$(running_tasks)" = 0 ] && { echo "$limit" >"$LOGS/outcome"; return; }
      if [ $(( $(date +%s) - limit_at )) -ge $(( grace * 60 )) ]; then
        echo "$(now) running tasks passed the grace period; stopping them (they restart on resume)"
        stop_running; echo "$limit" >"$LOGS/outcome"; return
      fi
    else
      "$AG/runner.sh" run >>"$LOGS/cron.log" 2>&1
      "$AG/orchestrate.sh" tick >>"$LOGS/cron.log" 2>&1
      all_goals_done && [ "$(running_tasks)" = 0 ] && { echo "done" >"$LOGS/outcome"; return; }
      fp=$(fingerprint)
      if [ "$fp" != "$last_fp" ] || [ "$(running_tasks)" != 0 ] || waiting_on_clock; then last_fp=$fp; last_change=$(date +%s)
      elif [ $(( $(date +%s) - last_change )) -ge "$stall" ]; then echo "needs-you" >"$LOGS/outcome"; return; fi
    fi
    sleep "$LOOP_SLEEP"
  done
}

[ "${1:-}" = --until-settled ] && { until_settled; echo "$(now) settled: $(cat "$LOGS/outcome")"; exit 0; }

COS_HOUR=${COS_HOUR:-8}; last=""
echo "$(now) loop started in $ROOT (orchestrator: $ORCH_MODEL)"
while true; do
  "$AG/runner.sh" run >>"$LOGS/cron.log" 2>&1
  "$AG/orchestrate.sh" tick >>"$LOGS/cron.log" 2>&1
  if [ "$((10#$(date +%H)))" -ge "$COS_HOUR" ] && [ "$last" != "$(today)" ]; then
    "$AG/cos.sh" daily >>"$LOGS/cron.log" 2>&1; last=$(today); echo "$(now) daily status written"
  fi
  sleep "$LOOP_SLEEP"
done
