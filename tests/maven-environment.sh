#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
#
# Proves the action keeps its private step variables out of every Maven
# process it starts.
#
# Each run step that calls Maven passes this action's inputs to its
# script through env: names such as MVN_PHASES and GLOBAL_SETTINGS.
# Those are implementation details, so no POM, plugin or test may see
# them: a profile activated on env.MVN_PHASES would make the build
# depend on how the action was called, and GLOBAL_SETTINGS holds the
# settings document, credentials and all.
#
# A profile keyed on one name, as a fixture POM would carry, checks only
# that name, and only when its value is non-empty. This checks every
# name instead. 'install' puts a recording mvn first on PATH, which
# saves each invocation's environment, then runs the real Maven. 'check'
# then fails on any env: name from any step of action.yaml in any of
# those environments, so a step variable added later is covered too.
# It also fails unless a caller's variable did arrive, so a recorder
# that saw nothing cannot pass, and unless each named Maven goal was
# recorded, so a run that slipped past the recorder cannot either.
#
# Usage:
#   maven-environment.sh install <bin-dir> <record-dir>
#   maven-environment.sh check <action.yaml> <record-dir> <caller-name> \
#     <goal>...

set -euo pipefail

usage() {
  echo 'usage: maven-environment.sh install <bin-dir> <record-dir>' >&2
  echo '       maven-environment.sh check <action.yaml> <record-dir>' \
    '<caller-name> <goal>...' >&2
  exit 2
}

install_recorder() {
  local bin="$1" record="$2" real
  real="$(command -v mvn)" || {
    echo 'No mvn on PATH to record' >&2
    exit 1
  }
  mkdir -p "$bin" "$record"
  # The record directory and the real Maven are fixed now, not read at
  # run time from an environment the action under test controls.
  cat > "$bin/mvn" <<EOF
#!/usr/bin/env bash
set -euo pipefail
out="\$(mktemp '${record}/invocation.XXXXXX')"
env -0 > "\$out.env"
printf '%s\0' "\$@" > "\$out.args"
exec '${real}' "\$@"
EOF
  chmod +x "$bin/mvn"
  echo "Recording Maven invocations in $record, running $real"
}

check_records() {
  local action="$1" record="$2" caller="$3" status=0 count=0 names
  shift 3
  # Every env: name of every step, from the action as checked out
  names="$(yq '.runs.steps[] | select(has("env")) | .env | keys | .[]' \
    "$action" | sort -u)"
  if [ -z "$names" ]; then
    echo "No step env: names found in $action" >&2
    exit 1
  fi
  shopt -s nullglob
  local envs=("$record"/invocation.*.env)
  if [ "${#envs[@]}" -eq 0 ]; then
    echo "No Maven invocation was recorded in $record ❌" >&2
    exit 1
  fi
  for env_file in "${envs[@]}"; do
    count=$((count + 1))
    # The goals and options say which of the action's Maven runs it was
    local args
    args="$(tr '\0' ' ' < "${env_file%.env}.args")"
    local leaked=()
    while IFS= read -r name; do
      if grep -qz "^${name}=" "$env_file"; then
        leaked+=("$name")
      fi
    done <<< "$names"
    if [ "${#leaked[@]}" -ne 0 ]; then
      echo "::error::mvn ${args} saw the action's step variables:" \
        "${leaked[*]}"
      status=1
    fi
    if ! grep -qz "^${caller}=" "$env_file"; then
      echo "::error::mvn ${args} did not see the caller's ${caller}," \
        'so the recording proves nothing'
      status=1
    fi
  done
  # Each Maven run the action starts, by a goal only that run passes.
  # grep reads the files itself: piping into grep -q under pipefail
  # fails whenever grep stops early and leaves the writer a SIGPIPE.
  local goal
  for goal in "$@"; do
    if ! grep -qzx -- "$goal" "$record"/invocation.*.args; then
      echo "::error::No recorded mvn ran ${goal}: the Maven run" \
        'expected to pass it was not recorded, so its environment' \
        'went unchecked'
      status=1
    fi
  done
  if [ "$status" -eq 0 ]; then
    echo "${count} Maven invocation(s), covering $*; none saw a step" \
      "variable, all saw ${caller} ✅"
  fi
  return "$status"
}

case "${1:-}" in
  install)
    [ "$#" -eq 3 ] || usage
    install_recorder "$2" "$3"
    ;;
  check)
    [ "$#" -ge 5 ] || usage
    check_records "${@:2}"
    ;;
  *)
    usage
    ;;
esac
