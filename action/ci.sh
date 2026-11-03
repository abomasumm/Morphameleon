#!/usr/bin/env bash
# ci.sh: the GitHub Action's steps. action.yml calls one per step, so the key and the GitHub token are never
# in the same step, and the token is never around while models or the repo's own code run.
#   ci.sh install   tools the pipeline needs, at pinned versions
#   ci.sh restore   fetch saved progress (needs MM_TOKEN)
#   ci.sh run       install the kit or resume, then run until settled (needs NEBIUS_API_KEY)
#   ci.sh publish   open the pull request, without the kit's own files (needs MM_TOKEN)
#   ci.sh save      push progress to morphameleon/* branches (needs MM_TOKEN)
#   ci.sh report    write the run summary and the dashboard
set -uo pipefail
KIT=$(cd "$(dirname "$0")/.." && pwd)
ROOT=${GITHUB_WORKSPACE:-$PWD}
cd "$ROOT" || exit 1
AG=$ROOT/.agents; LOGS=$AG/logs; META=$LOGS/ci-meta.json
WORK=${RUNNER_TEMP:-${TMPDIR:-/tmp}}/morphameleon; mkdir -p "$WORK"
RESTORED=$WORK/restored
OUTPUT=${GITHUB_OUTPUT:-/dev/null}; SUMMARY=${GITHUB_STEP_SUMMARY:-/dev/null}
TF_URL=${MM_TF_URL-https://api.tokenfactory.nebius.com/v1}
PI_VERSION=1.0.4; GITLEAKS_VERSION=8.30.1; SEMGREP_VERSION=1.183.0
GITLEAKS_SHA=551f6fc83ea457d62a0d98237cbad105af8d557003051f41f3e7ca7b3f2470eb

die() { echo "::error::$*"; exit 1; }
warn() { echo "::warning::$*"; }
meta() { jq -r --arg k "$1" '.[$k] // empty' "$META" 2>/dev/null; }

# Authenticates one git command through the environment, so the token isn't in .git/config or on a command
# line. Hooks are off: the repo's code has run on this machine, and it must not see the token.
with_token() {
  local auth; auth=$(printf 'x-access-token:%s' "${MM_TOKEN:-}" | base64 | tr -d '\n')
  echo "::add-mask::$auth"
  GIT_TERMINAL_PROMPT=0 GIT_CONFIG_COUNT=2 \
    GIT_CONFIG_KEY_0="http.${GITHUB_SERVER_URL:-https://github.com}/.extraheader" GIT_CONFIG_VALUE_0="AUTHORIZATION: basic $auth" \
    GIT_CONFIG_KEY_1=core.hooksPath GIT_CONFIG_VALUE_1=/dev/null "$@"
}

cmd_install() {
  npm install -g "@earendil-works/pi-coding-agent@$PI_VERSION" --no-audit --no-fund --silent || die "Could not install pi."
  if [ "${RUNNER_OS:-}" = Linux ] && [ "${RUNNER_ARCH:-}" = X64 ]; then
    local tar="$WORK/gitleaks.tar.gz"
    if curl -fsSL -o "$tar" "https://github.com/gitleaks/gitleaks/releases/download/v$GITLEAKS_VERSION/gitleaks_${GITLEAKS_VERSION}_linux_x64.tar.gz" &&
       echo "$GITLEAKS_SHA  $tar" | sha256sum -c - >/dev/null; then
      mkdir -p "$WORK/bin" && tar -xzf "$tar" -C "$WORK/bin" gitleaks && echo "$WORK/bin" >>"${GITHUB_PATH:-/dev/null}"
    else warn "Could not install gitleaks; the secret scan is skipped."; fi
  fi
  command -v pipx >/dev/null && pipx install --quiet "semgrep==$SEMGREP_VERSION" >/dev/null 2>&1 ||
    warn "Could not install semgrep; the risky-code scan is skipped."
}

cmd_restore() {
  local cmd=${MM_COMMAND:-start}
  [ "$(git rev-parse --is-shallow-repository)" = true ] && { with_token git fetch -q --unshallow origin || die "Could not fetch the full history."; }
  git symbolic-ref -q HEAD >/dev/null || die "Run this workflow from a branch."
  rm -f "$RESTORED"
  with_token git fetch -q --prune origin '+refs/heads/morphameleon/*:refs/remotes/morphameleon/*' || die "Could not read saved progress."
  local have=no; git show-ref --verify --quiet refs/remotes/morphameleon/state && have=yes
  case "$cmd" in
    start)
      if [ $have = yes ]; then
        git show refs/remotes/morphameleon/state:state.tar.gz | tar -xzO .agents/logs/outcome 2>/dev/null | grep -qx done ||
          die "A migration is already in progress. Choose resume to continue it, or restart to throw it away."
      fi ;;
    restart) ;;
    resume|approve|reject|retry)
      [ $have = yes ] || die "There's no saved migration to $cmd. Choose start first."
      touch "$RESTORED" ;;
    *) die "Unknown command: $cmd" ;;
  esac
}

unpack_state() {
  local base ref name
  mkdir -p "$WORK/state"
  git show refs/remotes/morphameleon/state:state.tar.gz | tar -xzf - -C "$WORK/state" .agents/logs/ci-meta.json || die "Saved progress is unreadable."
  base=$(jq -r .base_branch "$WORK/state/.agents/logs/ci-meta.json")
  git checkout -q -B "$base" refs/remotes/morphameleon/base || die "Could not restore the working branch."
  git branch -qf agents refs/remotes/morphameleon/work
  git for-each-ref --format='%(refname)' refs/remotes/morphameleon/task/ | while read -r ref; do
    name=${ref#refs/remotes/morphameleon/}; git branch -qf "$name" "$ref"
  done
  git show refs/remotes/morphameleon/state:state.tar.gz | tar -xzf - || die "Saved progress is unreadable."
  rm -rf "$AG/locks"; git worktree prune
  # This is a new machine: whatever was running is gone, and old pids could belong to anything.
  local f
  for f in "$AG"/tasks/T-*.md; do
    [ -f "$f" ] || continue
    case "$(sed -n 's/^status: //p' "$f" | head -1)" in
      claimed|building|gating|reviewing) python3 - "$f" <<'PY'
import re, sys
p = sys.argv[1]; s = open(p).read()
open(p, "w").write(re.sub(r"^status: .*$", "status: queued", s, count=1, flags=re.M))
PY
      ;;
    esac
  done
}

install_deps() {
  [ -f package.json ] || return 0
  # Install scripts come from the repo, so they don't get the key.
  ( unset NEBIUS_API_KEY; npm ci --no-audit --no-fund || npm install --no-audit --no-fund ) >"$WORK/npm.log" 2>&1 ||
    { tail -n 30 "$WORK/npm.log"; die "Could not install this repo's npm dependencies. Add any setup steps it needs before the action."; }
}

start_fresh() {
  [ -n "${MM_TO:-}" ] || die "Say what to migrate to in the 'to' input."
  local base base_sha kit_sha answers
  base=$(git rev-parse --abbrev-ref HEAD); base_sha=$(git rev-parse HEAD)
  [ "$base" != agents ] || die "The agents branch is reserved for the migration's work. Run from another branch."
  install_deps
  bash "$KIT/setup.sh" "$ROOT" >"$WORK/setup.log" 2>&1 || { cat "$WORK/setup.log"; die "Could not install the migration agent."; }
  rm -f "$AG/secrets.sh"     # the key comes from the environment and stays out of files
  { echo; echo "# Written by the GitHub Action"; echo "MAIN_BRANCH=\"$base\""
    echo "ORCH_MIN_GAP_MIN=${MM_ORCH_GAP:-2}"; echo "LOOP_SLEEP=${MM_LOOP_SLEEP:-20}"; } >>"$AG/local.sh"
  git add -- .agents AGENTS.md NOTES.md .gitignore
  git commit -qm "Add the migration agent (working copy, not part of the pull request)" || die "Could not commit the agent."
  kit_sha=$(git rev-parse HEAD)
  mkdir -p "$LOGS"
  jq -n --arg b "$base" --arg bs "$base_sha" --arg ks "$kit_sha" --arg p "${MM_PROFILE:-default}" \
    '{base_branch:$b, base_sha:$bs, kit_sha:$ks, profile:$p}' >"$META"

  answers=$WORK/answers.json
  jq -n --arg to "$MM_TO" --arg from "${MM_FROM:-}" --arg scope "${MM_SCOPE:-}" --arg keep "${MM_KEEP:-}" --arg must "${MM_MUST:-}" \
    '{to:$to, from:$from, scope:$scope, keep:$keep, must:$must}' >"$answers"
  bash "$AG/migrate.sh" init --answers "$answers" </dev/null || die "Could not read this repo."
  if [ "$(jq -r .baseline "$LOGS/migration-questions.json")" != green ]; then
    echo baseline-failed >"$LOGS/outcome"
    echo "::error::The tests fail on your current code. A migration can only be proven against passing tests, so nothing was changed."
    tail -n 30 "$LOGS/migration-baseline.log"
    return 1
  fi
  [ "$(jq '.modules|length' "$LOGS/migration-facts.json")" != 0 ] || die "No source modules found in this repo."
  git add MIGRATION.md && git commit -qm "Migration plan" || die "Could not commit the plan."
  bash "$AG/migrate.sh" start "${MM_PROFILE:-}" || die "Could not start the migration."
}

apply_command() {
  local cmd=$1
  case "$cmd" in
    resume) return 0 ;;
    approve|reject|retry)
      [[ ${MM_TASK:-} =~ ^T-[0-9]+$ ]] || die "Give a task id like T-003 in the 'task' input."
      case "$cmd" in
        approve) bash "$AG/runner.sh" approve "$MM_TASK" ;;
        reject)  bash "$AG/runner.sh" reject "$MM_TASK" "${MM_NOTE:-}" ;;
        retry)   bash "$AG/runner.sh" requeue "$MM_TASK" "${MM_NOTE:-}" ;;
      esac || die "Could not $cmd $MM_TASK."
      ;;
  esac
}

# The key must never reach anything that gets published: scrub it from saved files, and refuse to push
# if a model committed it.
guard_key() {
  local key=${NEBIUS_API_KEY:-}
  [ -n "$key" ] || return 0
  [ -d "$AG" ] || return 0
  MM_KEY=$key python3 - "$AG" "$ROOT/NOTES.md" "$ROOT/REPO_MAP.md" <<'PY'
import os, sys
key = os.environ["MM_KEY"].encode()
def scrub(path):
    try:
        data = open(path, "rb").read()
        if key in data:
            open(path, "wb").write(data.replace(key, b"[redacted]"))
            print("Removed the API key from " + os.path.basename(path))
    except OSError:
        pass
for top in sys.argv[1:]:
    if os.path.isfile(top):
        scrub(top)
    for folder, _, names in os.walk(top):
        for name in names:
            scrub(os.path.join(folder, name))
PY
  if [ -n "$(git log --all --format=%h -S"$key" -- 2>/dev/null | head -1)" ]; then
    echo key-leak >"$LOGS/outcome"
    echo "::error::A commit from this run contains your API key. Nothing will be pushed. Replace the key in Token Factory, then choose restart."
  fi
}

finish_run() {
  local rc=$? outcome
  guard_key
  pkill -TERM -f "$AG/" 2>/dev/null; pkill -TERM -f "pi -p --no-session" 2>/dev/null
  outcome=$(cat "$LOGS/outcome" 2>/dev/null); echo "outcome=${outcome:-failed}" >>"$OUTPUT"
  exit "$rc"
}

cmd_run() {
  local key=${NEBIUS_API_KEY:-} code cmd=${MM_COMMAND:-start}
  [ -n "$key" ] || die "No API key. Add your Token Factory key as a repository secret named NEBIUS_API_KEY."
  if [ -n "$TF_URL" ]; then
    code=$(curl -s -m 30 -o /dev/null -w '%{http_code}' -H "Authorization: Bearer $key" "$TF_URL/models")
    case "$code" in 401|403) die "Token Factory rejected the API key (HTTP $code). Check the NEBIUS_API_KEY secret." ;; esac
  fi
  trap finish_run EXIT
  git config user.name "github-actions[bot]"
  git config user.email "41898282+github-actions[bot]@users.noreply.github.com"
  if [ -f "$RESTORED" ]; then
    unpack_state; install_deps; apply_command "$cmd"
  else
    start_fresh || exit 1
  fi
  PROFILE=$(meta profile) bash "$AG/loop.sh" --until-settled </dev/null
}

# The pull request holds the migration and its plan, not the agent's own working files.
clean_tree() {
  local p
  git diff --name-only "$(meta base_sha)" "$(meta kit_sha)" | while IFS= read -r p; do
    if git cat-file -e "$(meta base_sha):$p" 2>/dev/null; then git checkout -q "$(meta base_sha)" -- "$p"
    else git rm -q --ignore-unmatch -- "$p"; fi
  done
}

cmd_publish() {
  [ -f "$META" ] || exit 0
  [ "$(cat "$LOGS/outcome" 2>/dev/null)" = done ] || exit 0
  if [ -s "$LOGS/published" ]; then echo "url=$(cat "$LOGS/published")" >>"$OUTPUT"; exit 0; fi
  local branch tree base url body
  base=$(meta base_branch); branch="migration/run-${GITHUB_RUN_ID:-$(date +%s)}"; tree=$WORK/publish
  git worktree add -q --detach "$tree" agents || die "Could not prepare the pull request."
  ( cd "$tree" && clean_tree; git add -A; git commit -qm "Remove the migration agent's working files" --no-verify
    with_token git push -q origin "HEAD:refs/heads/$branch" ) || die "Could not push $branch. Check that the workflow has contents: write."
  git worktree remove --force "$tree"
  body=$WORK/pr-body.md
  { echo "Morphameleon migrated this code. Tests pinned the old behaviour first, and every change passed those tests and a review by a different model family."
    echo; echo "The plan is in \`MIGRATION.md\`. Review this like any other change: nothing reaches \`$base\` until you merge it."
    echo; echo "Workflows don't run on this pull request automatically, because GitHub doesn't start them for its own token. Close and reopen it to run your checks."; } >"$body"
  if url=$(GH_TOKEN=${MM_TOKEN:-} GH_PROMPT_DISABLED=1 gh pr create --repo "${GITHUB_REPOSITORY:-}" --base "$base" --head "$branch" \
        --title "Migration to $(sed -n 's/^- To: //p' MIGRATION.md | head -1)" --body-file "$body" 2>"$WORK/gh.err"); then
    url=$(echo "$url" | tail -n 1); echo "$url" >"$LOGS/published"; echo "url=$url" >>"$OUTPUT"; echo "Pull request: $url"
  else
    cat "$WORK/gh.err"
    warn "The migration is on branch $branch, but the pull request wasn't opened. In Settings > Actions > General, allow GitHub Actions to create pull requests, or open it yourself."
  fi
}

cmd_save() {
  [ -f "$META" ] || { echo "Nothing to save."; exit 0; }
  [ "$(cat "$LOGS/outcome" 2>/dev/null)" = key-leak ] && { echo "Not saving: this run's commits contain the API key."; exit 0; }
  git show-ref --verify --quiet refs/heads/agents || { echo "Nothing to save yet."; exit 0; }
  local tarball=$WORK/state.tar.gz items=() i blob tree commit
  for i in .agents/tasks .agents/goals .agents/orch .agents/logs .agents/context.md .agents/STATUS.md .agents/migration-brief.md NOTES.md REPO_MAP.md; do
    [ -e "$i" ] && items+=("$i")
  done
  tar -czf "$tarball" "${items[@]}" || die "Could not pack progress."
  blob=$(git hash-object -w "$tarball")
  tree=$(printf '100644 blob %s\tstate.tar.gz\n' "$blob" | git mktree)
  commit=$(git -c user.name=morphameleon -c user.email=morphameleon@users.noreply.github.com commit-tree "$tree" -m "Saved migration progress")
  with_token git push -q --force --prune origin \
    "$commit:refs/heads/morphameleon/state" \
    "refs/heads/$(meta base_branch):refs/heads/morphameleon/base" \
    "refs/heads/agents:refs/heads/morphameleon/work" \
    'refs/heads/task/*:refs/heads/morphameleon/task/*' || die "Could not save progress. Check that the workflow has contents: write."
  echo "Progress saved to the morphameleon/* branches."
}

cmd_report() {
  local outcome out=$WORK/dashboard
  outcome=$(cat "$LOGS/outcome" 2>/dev/null); outcome=${outcome:-failed}
  {
    echo "## Morphameleon: $outcome"
    case "$outcome" in
      done)            echo "The migration finished. Review the pull request, or the \`morphameleon/work\` branch if none opened." ;;
      needs-you)       echo "It can't go further without you. Choose \`retry\`, \`approve\` or \`reject\` with a task id, or \`resume\` to continue." ;;
      limit-calls)     echo "It reached the model call limit. Progress is saved: choose \`resume\` to continue." ;;
      limit-time)      echo "It reached the time limit. Progress is saved: choose \`resume\` to continue." ;;
      baseline-failed) echo "Your tests fail on the current code, so nothing was changed. Fix them, then choose \`start\`." ;;
      key-leak)        echo "A commit contained your API key, so nothing was pushed. Replace the key, then choose \`restart\`." ;;
      *)               echo "The run stopped early. See the step that failed above." ;;
    esac
    if [ -x "$AG/runner.sh" ]; then
      echo; echo '```'; bash "$AG/runner.sh" status 2>/dev/null; echo '```'
      echo; echo "Model calls so far: $(grep -cvE ',(gate-|b2|flaky)[a-z]*,' "$LOGS/runs.csv" 2>/dev/null)"
    fi
  } >>"$SUMMARY"
  [ -f "$AG/dashboard.py" ] && [ -f "$LOGS/runs.csv" ] || exit 0
  [ "$outcome" = key-leak ] && exit 0
  python3 "$KIT/app/export_demo.py" "$ROOT" "$out" --single-file >/dev/null || { warn "Could not build the dashboard."; exit 0; }
  rm -rf "$out/diffs" "$out/state.json" "$out/project.json"
  if command -v gitleaks >/dev/null && ! gitleaks dir --no-banner --redact "$out" >"$WORK/leaks.log" 2>&1; then
    warn "The secret scan flagged the dashboard, so it wasn't uploaded. If your repo holds test keys, that may be why."
    exit 0
  fi
  echo "dashboard=$out" >>"$OUTPUT"
}

case "${1:-}" in
  install) cmd_install ;; restore) cmd_restore ;; run) cmd_run ;;
  publish) cmd_publish ;; save) cmd_save ;; report) cmd_report ;;
  *) sed -n '2,9p' "$0"; exit 1 ;;
esac
