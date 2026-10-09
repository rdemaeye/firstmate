#!/usr/bin/env bash
# Live CodeCommit scenarios for fm-spawn default-branch resolution.
set -u
WT=/Users/Ryan/.no-mistakes/worktrees/3783e3f36cb9/01M4GA500WKFHK2Q72GM4Q06DQ
. "$WT/tests/fixtures.sh"
LAB=$(mktemp -d "${TMPDIR:-/tmp}/fm-lab.XXXXXX")
echo "# lab=$LAB"
URL=https://git-codecommit.us-east-1.amazonaws.com/v1/repos/ProscAmazonCloudWatch
PROJ="$LAB/ProscAmazonCloudWatch"
POOL="$LAB/pool"
git clone -q --no-progress -c credential.helper= -c 'credential.helper=!env -u AWS_PROFILE AWS_CONFIG_FILE=/Users/Ryan/.aws/config AWS_SHARED_CREDENTIALS_FILE=/Users/Ryan/.aws/credentials aws codecommit credential-helper $@' -c credential.UseHttpPath=true "$URL" "$PROJ" || exit 1
git -C "$PROJ" remote set-head origin -d 2>/dev/null
echo '$ git ls-remote --symref origin HEAD'; git -C "$PROJ" ls-remote --symref origin HEAD
echo '$ git remote set-head origin --auto'; git -C "$PROJ" remote set-head origin --auto 2>&1 | head -3
echo "# branches sharing HEAD's commit:"; git -C "$PROJ" branch -r --points-at origin/main
OLD=$(git -C "$PROJ" rev-parse origin/main~1)
TIP=$(git -C "$PROJ" rev-parse origin/main)
echo "# origin/main tip=$TIP ; pool starts at origin/main~1=$OLD"
git -C "$PROJ" worktree add --quiet --detach "$POOL" "$OLD"
mkdir -p "$LAB/base"; git -C "$WT" archive 19fcbbde12c4e916e0d5faa60c399d2fd2845740 | tar -x -C "$LAB/base"
: > "$LAB/empty"; FAKEBIN=$(make_spawn_fakebin "$LAB/fake")
export AWS_CONFIG_FILE="$HOME/.aws/config" AWS_SHARED_CREDENTIALS_FILE="$HOME/.aws/credentials"

spawn() { # <root> <id> <label>
  local root=$1 id=$2 home="$LAB/home-$2" out rc
  mkdir -p "$home/data/$id" "$home/projects" "$home/state" "$home/config"
  printf 'codex\n' > "$home/config/crew-harness"
  fm_test_spawn_brief "$home" "$id"; touch "$home/state/.last-watcher-beat"
  [ -z "${REG:-}" ] || printf -- '- ProscAmazonCloudWatch [%s] - live lab (added 2026-10-09)\n' "$REG" > "$home/data/projects.md"
  git -C "$POOL" checkout --quiet --detach "$OLD"; git -C "$POOL" remote set-head origin -d 2>/dev/null
  echo; echo "## scenario: $3"
  echo "\$ [registry: ${REG:-none}] [aws env: ${AWSNOTE:-operator AWS CLI config}] $(basename "$root")/bin/fm-spawn.sh $id $PROJ --mode no-mistakes --yolo off"
  ROOT=$root
  out=$(fm_test_run_spawn "$home" "$POOL" "$FAKEBIN" "$id" "$PROJ" --mode no-mistakes --yolo off); rc=$?
  printf '%s\n' "$out" | grep -E "spawned|error|refus" | head -5
  echo "exit=$rc"
  echo "pool HEAD=$(git -C "$POOL" rev-parse HEAD) (origin/main=$TIP) $( [ "$(git -C "$POOL" rev-parse HEAD)" = "$TIP" ] && echo '=> on origin/main tip' || echo '=> NOT moved to origin/main')"
  echo "origin/HEAD -> $(git -C "$POOL" symbolic-ref --short refs/remotes/origin/HEAD 2>/dev/null || echo unset)"
}

spawn "$LAB/base" live-before-r1 "BEFORE fix (base 19fcbbd): CodeCommit origin, no token"
spawn "$WT" live-api-r1 "AFTER fix: CodeCommit origin, real AWS API answers"
REG='no-mistakes default-branch=tomcat11' spawn "$WT" live-api-beats-token-r1 "AFTER fix: API answer beats a registered (stale) default-branch=tomcat11"
AWSNOTE='AWS CLI config+credentials files empty (no creds)' REG='no-mistakes default-branch=main' AWS_CONFIG_FILE=$LAB/empty AWS_SHARED_CREDENTIALS_FILE=$LAB/empty spawn "$WT" live-token-fallback-r1 "AFTER fix: AWS credentials unavailable, registered default-branch=main fallback"
AWSNOTE='AWS CLI config+credentials files empty (no creds)' AWS_CONFIG_FILE=$LAB/empty AWS_SHARED_CREDENTIALS_FILE=$LAB/empty spawn "$WT" live-refuse-r1 "AFTER fix: AWS credentials unavailable and no token -> refuse"
AWSNOTE='AWS CLI config+credentials files empty (no creds)' REG='no-mistakes default-branch=nope' AWS_CONFIG_FILE=$LAB/empty AWS_SHARED_CREDENTIALS_FILE=$LAB/empty spawn "$WT" live-bad-token-r1 "AFTER fix: AWS unavailable, registered branch absent on origin -> refuse"
git -C "$PROJ" worktree remove --force "$POOL"
chmod -R u+w "$LAB"; rm -rf "$LAB"; echo; echo "# lab removed: $( [ -e "$LAB" ] && echo no || echo yes)"
