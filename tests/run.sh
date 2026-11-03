#!/usr/bin/env bash
# tests/run.sh: the GitHub Action, end to end against a local "origin" and a fake pi and gh. No credits, no network.
set -uo pipefail
HERE=$(cd "$(dirname "$0")" && pwd); REPO=$(dirname "$HERE")
TMP=$(mktemp -d); trap 'rm -rf "$TMP"' EXIT
KEY=fake-key-do-not-use-1234567890
PASSED=0; FAILED=0
ok() { PASSED=$((PASSED+1)); echo "  ok    $1"; }
bad() { FAILED=$((FAILED+1)); echo "  FAIL  $1"; }
check() { if eval "$2"; then ok "$1"; else bad "$1"; fi; }

# What the Action downloads: tracked and new files, none of this machine's runtime state.
KIT=$TMP/kit; mkdir -p "$KIT"
( cd "$REPO" && git ls-files -co --exclude-standard -z | while IFS= read -r -d '' f; do [ -f "$f" ] && printf '%s\0' "$f"; done | tar -cf - --null -T - ) | tar -xf - -C "$KIT"
export PATH="$HERE/fake-bin:$PATH" MM_TF_URL="" MM_LOOP_SLEEP=1 MM_ORCH_GAP=0 STALL_SECONDS=4 GITHUB_REPOSITORY=x/y
export GIT_CONFIG_GLOBAL=$TMP/gitconfig; git config --global init.defaultBranch main; git config --global user.name t; git config --global user.email t@t

new_origin() { # name exit-code-of-tests -> makes $TMP/name.git
  local w=$TMP/$1.src; git init -q "$w"
  mkdir -p "$w/src"
  for f in a b; do echo "exports.$f = () => '$f'" >"$w/src/$f.js"; done
  cat >"$w/test.js" <<JS
const fs = require('fs');
if (process.env.NEBIUS_API_KEY && process.env.KEY_SEEN_LOG) fs.appendFileSync(process.env.KEY_SEEN_LOG, 'seen\n');
require('./src/a.js'); require('./src/b.js'); process.exit(${2:-0});
JS
  echo '{"name":"t","version":"1.0.0","scripts":{"test":"node test.js"}}' >"$w/package.json"
  ( cd "$w" && npm install --package-lock-only --silent >/dev/null 2>&1; git add -A; git commit -qm init )
  git clone -q --bare "$w" "$TMP/$1.git"
}
machine=0
new_machine() { # origin -> a fresh checkout, as actions/checkout leaves it; sets WS
  machine=$((machine+1)); WS=$TMP/ws$machine; git clone -q "$TMP/$1.git" "$WS"; git -C "$WS" config --unset-all user.name 2>/dev/null
  export GITHUB_WORKSPACE=$WS RUNNER_TEMP=$TMP/rt$machine GITHUB_OUTPUT=$TMP/out$machine GITHUB_STEP_SUMMARY=$TMP/sum$machine GITHUB_RUN_ID=$machine
  mkdir -p "$RUNNER_TEMP"; : >"$GITHUB_OUTPUT"; : >"$GITHUB_STEP_SUMMARY"
}
ci() { bash "$KIT/action/ci.sh" "$@"; }
# The steps of action.yml, in order, each with only the secrets its step gets.
action() { # command
  local rc=0; RUN_RC=0
  MM_TOKEN=tok MM_COMMAND=$1 ci restore || { RUN_RC=restore-failed; return; }
  NEBIUS_API_KEY=$KEY MM_COMMAND=$1 MM_TO="${MM_TO-TypeScript}" KEY_SEEN_LOG=$TMP/key-seen ci run; rc=$?; RUN_RC=$rc
  [ "$(outcome)" = done ] && MM_TOKEN=tok ci publish
  MM_TOKEN=tok ci save
  ci report
}
outcome() { sed -n 's/^outcome=//p' "$GITHUB_OUTPUT" | tail -1; }
ref() { git -C "$TMP/$1.git" rev-parse --verify -q "refs/heads/$2"; }

echo "A run from start to pull request"
new_origin one; new_machine one; main0=$(ref one main); : >"$TMP/key-seen"; export FAKE_GH_LOG=$TMP/gh1; : >"$FAKE_GH_LOG"
action start >"$TMP/log1" 2>&1
check "finishes with outcome done" '[ "$(outcome)" = done ]'
check "main on origin is unchanged" '[ "$(ref one main)" = "$main0" ]'
check "opens a pull request" 'grep -q "pr create" "$FAKE_GH_LOG"'
check "reports the pull request URL" 'grep -q "url=https://github.com/x/y/pull/7" "$GITHUB_OUTPUT"'
pr=$(git -C "$TMP/one.git" for-each-ref --format='%(refname:short)' refs/heads/migration/ | head -1)
files=$(git -C "$TMP/one.git" diff --name-only main "$pr" | sort | tr '\n' ' ')
check "pull request holds only the migration and its plan" '[ "$files" = "MIGRATION.md src/a.js src/b.js " ]'
check "the migration really changed the code" 'git -C "$TMP/one.git" show "$pr:src/a.js" | grep -q "migrated by"'
check "the repo's tests never saw the key" '[ ! -s "$TMP/key-seen" ]'
check "progress is saved" 'ref one morphameleon/state >/dev/null && ref one morphameleon/work >/dev/null'
check "the token is not in the repo's git config" '! grep -q tok "$WS/.git/config"'
check "the dashboard is a single file" '[ -f "$RUNNER_TEMP/morphameleon/dashboard/index.html" ] && [ ! -e "$RUNNER_TEMP/morphameleon/dashboard/state.json" ]'
check "the dashboard holds the run and no key" 'grep -q "T-001" "$RUNNER_TEMP/morphameleon/dashboard/index.html" && ! grep -q "$KEY" "$RUNNER_TEMP/morphameleon/dashboard/index.html"'
check "the summary names the outcome" 'grep -q "Morphameleon: done" "$GITHUB_STEP_SUMMARY"'
new_machine one; MM_TO=Rust action start >"$TMP/log1b" 2>&1
check "a finished migration allows a new start" '[ "$RUN_RC" = 0 ] && [ "$(outcome)" = done ]'

echo "Tests that already fail"
new_origin red 1; new_machine red; main0=$(ref red main)
action start >"$TMP/log2" 2>&1
check "stops with outcome baseline-failed" '[ "$(outcome)" = baseline-failed ]'
check "the job fails" '[ "$RUN_RC" != 0 ]'
check "explains why" 'grep -q "tests fail on your current code" "$TMP/log2"'
check "pushes nothing" '[ "$(git -C "$TMP/red.git" for-each-ref refs/heads/ | wc -l | tr -d " ")" = 1 ] && [ "$(ref red main)" = "$main0" ]'

echo "Bad input"
new_origin bad; new_machine bad
( NEBIUS_API_KEY="" MM_TO=x ci run ) >"$TMP/log3" 2>&1
check "a missing key stops before anything else" 'grep -q "No API key" "$TMP/log3" && [ ! -d "$WS/.agents" ]'
check "says how to add the key" 'grep -q "repository secret" "$TMP/log3"'
MM_TO="" action start >"$TMP/log3b" 2>&1
check "a missing target is refused" 'grep -q "what to migrate to" "$TMP/log3b"'
action resume >"$TMP/log3c" 2>&1
check "resume with nothing saved is refused" 'grep -q "no saved migration" "$TMP/log3c"'

echo "Limits, then resuming on a new machine"
new_origin lim; new_machine lim
MAX_MODEL_CALLS=1 action start >"$TMP/log4" 2>&1
check "stops at the call limit" '[ "$(outcome)" = limit-calls ]'
check "does not open a pull request" '[ -z "$(git -C "$TMP/lim.git" for-each-ref refs/heads/migration/)" ]'
new_machine lim; action start >"$TMP/log4b" 2>&1
check "start refuses to overwrite work in progress" 'grep -q "already in progress" "$TMP/log4b"'
new_machine lim; action resume >"$TMP/log4c" 2>&1
check "resume on a new machine finishes" '[ "$(outcome)" = done ]'
check "resume did not plan the work twice" '[ "$(ls "$WS"/.agents/goals/G-*.md | wc -l | tr -d " ")" = 1 ]'
new_origin tl; new_machine tl
TIME_LIMIT_MINUTES=0 action start >"$TMP/log4d" 2>&1
check "stops at the time limit" '[ "$(outcome)" = limit-time ]'

echo "Stopping a task that's still running"
new_origin slow; new_machine slow
FAKE_SLOW=1 MAX_MODEL_CALLS=3 GRACE_MINUTES=0 action start >"$TMP/log5" 2>&1
check "stops without waiting for it" '[ "$(outcome)" = limit-calls ]'
new_machine slow; action resume >"$TMP/log5b" 2>&1
check "the interrupted task restarts and finishes" '[ "$(outcome)" = done ] && grep -q "status: merged" "$WS/.agents/tasks/T-001.md"'

echo "A task that needs a person"
new_origin stuck; new_machine stuck
FAKE_MODE=fail action start >"$TMP/log6" 2>&1
check "stops with outcome needs-you" '[ "$(outcome)" = needs-you ]'
check "parks the task" 'grep -q "status: needs-you" "$WS/.agents/tasks/T-002.md"'
check "does not open a pull request" '[ -z "$(git -C "$TMP/stuck.git" for-each-ref refs/heads/migration/)" ]'
new_machine stuck; action retry >"$TMP/log6b" 2>&1
check "retry without a task id is refused" 'grep -q "task id like" "$TMP/log6b"'
new_machine stuck; MM_TASK=T-002 MM_NOTE="try again" action retry >"$TMP/log6c" 2>&1
check "retry finishes the migration" '[ "$(outcome)" = done ]'

echo "The API key never gets out"
new_origin leak; new_machine leak
FAKE_MODE=leak-log action start >"$TMP/log7" 2>&1
check "the run still finishes" '[ "$(outcome)" = done ]'
mkdir -p "$TMP/st"; git -C "$TMP/leak.git" show morphameleon/state:state.tar.gz | tar -xzf - -C "$TMP/st"
check "saved progress has no key" '! grep -rqF "$KEY" "$TMP/st"'
check "logs say it was redacted" 'grep -rqF "[redacted]" "$TMP/st"'
check "nothing printed the key" '! grep -qF "$KEY" "$TMP/log7"'
new_origin leak2; new_machine leak2
FAKE_MODE=leak-commit action start >"$TMP/log7b" 2>&1
check "a committed key stops the run" '[ "$(outcome)" = key-leak ]'
check "nothing is pushed" '[ "$(git -C "$TMP/leak2.git" for-each-ref refs/heads/ | wc -l | tr -d " ")" = 1 ]'

echo "The pull request can't be opened"
new_origin nopr; new_machine nopr
FAKE_GH_FAIL=1 action start >"$TMP/log8" 2>&1
check "the code is still pushed" '[ -n "$(git -C "$TMP/nopr.git" for-each-ref refs/heads/migration/)" ]'
check "says how to fix it" 'grep -q "allow GitHub Actions to create pull requests" "$TMP/log8"'

echo; echo "$PASSED passed, $FAILED failed"
[ "$FAILED" = 0 ] || { echo "Logs were in $TMP (removed on exit). Set KEEP=1 to keep them."; [ -n "${KEEP:-}" ] && { trap - EXIT; echo "$TMP"; }; exit 1; }
