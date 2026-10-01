#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
#
# Checks the deploy-repository helpers the action sources. The build
# deploys into m2repo, and the merge lanes depend on finding it there:
# a caller argument that redirects the deploy breaks them without
# failing the build. This holds the detection to every spelling Maven
# accepts, and to the near-misses it must leave alone, since refusing
# an unrelated property would break a legitimate build.
#
# The functions come from the file the action sources, rather than
# living here twice, so this checks what the action runs.

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
# shellcheck source=../deploy-repository.sh disable=SC1091
. "${SCRIPT_DIR}/../deploy-repository.sh"

FAILED=0

refused() {
  local args="$1" expected="$2" found
  if found="$(find_deploy_repository_override "$args")" \
      && [ "$found" = "$expected" ]; then
    echo "refused ${expected}: ${args} ✅"
  else
    echo "expected ${expected} refused, got '${found:-nothing}': ${args} ❌"
    FAILED=1
  fi
}

allowed() {
  local args="$1" found
  if found="$(find_deploy_repository_override "$args")"; then
    echo "wrongly refused ${found}: ${args} ❌"
    FAILED=1
  else
    echo "allowed: ${args:-<empty>} ✅"
  fi
}

R=x::default::file:/elsewhere

# All three properties, in each spelling Maven accepts.
for p in altDeploymentRepository altSnapshotDeploymentRepository \
  altReleaseDeploymentRepository; do
  refused "-D${p}=${R}" "$p"
  refused "-D ${p}=${R}" "$p"
  refused "--define ${p}=${R}" "$p"
  refused "--define=${p}=${R}" "$p"
  # -Dname alone sets the property to "true", still an override.
  refused "-D${p}" "$p"
done

# Found among other arguments, and across the whitespace the build's
# unquoted expansion splits on.
refused "-B -DskipTests -DaltSnapshotDeploymentRepository=${R} -e" \
  altSnapshotDeploymentRepository
refused $'-Dfoo=bar\n\t-DaltReleaseDeploymentRepository='"${R}" \
  altReleaseDeploymentRepository
# A YAML block scalar puts each argument on its own line: an override
# on a later line must be found, not only one on the first.
refused $'-B\n-DskipTests\n-DaltDeploymentRepository='"${R}"$'\n' \
  altDeploymentRepository
# The two-word spelling split across a line break.
refused $'-D\naltSnapshotDeploymentRepository='"${R}" \
  altSnapshotDeploymentRepository
# The action's own default mvn-opts, followed by an override.
refused "-Dmaven.repo.local=/tmp/r -DaltDeploymentRepository=${R}" \
  altDeploymentRepository

# Near-misses: different properties, or not a property at all.
allowed ""
allowed "-Dmaven.repo.local=/tmp/r -Dorg.ops4j.pax.url.mvn.localRepository=/tmp/r"
allowed "-DaltDeploymentRepositoryUrl=${R}"
allowed "-DmyaltDeploymentRepository=${R}"
allowed "-Dfoo=altDeploymentRepository"
allowed "-Dfoo=-DaltDeploymentRepository=${R}"
allowed "-pl altDeploymentRepository"
# Maven accepts no abbreviated long option, so --def sets nothing.
allowed "--def altDeploymentRepository=${R}"
# A trailing -D with nothing after it names no property.
allowed "-B -D"
# Property names are case-sensitive.
allowed "-DAltDeploymentRepository=${R}"

# A word beginning with a double quote is refused, whatever it holds:
# Maven 3.9 strips the quotes into a real property, and an opening
# quote never closed joins every later word, the action's own deploy
# arguments included, into one value.
Q="$DEPLOY_REPOSITORY_QUOTE"
# The bypass the guard has to stop: a quoted override the -D check
# alone does not recognise, then an unterminated quote that absorbs
# what follows.
refused "\"-DaltSnapshotDeploymentRepository=${R}\" \"-Dharmless=value" "$Q"
refused "\"-Dharmless=value" "$Q"
refused "-B \"-Dharmless=value\"" "$Q"
refused '"' "$Q"
refused '""' "$Q"
# The value word of the two-word spellings: Maven strips its quotes.
refused "-D \"altDeploymentRepository=${R}\"" "$Q"
refused "--define \"x=1\"" "$Q"
# On a later line of a YAML block.
refused $'-B\n"-Dharmless=value' "$Q"
# A quote anywhere but the start of a word, and a single quote
# anywhere, reach Maven unchanged, so they stay allowed.
allowed '-Dfoo=a"b'
allowed '-Dfoo=value"'
allowed "'-Dfoo=value'"
allowed "-Dfoo='a b'"
allowed '-Dfoo=\"value\"'

# The arguments the build sets: all three, at the given directory.
EXPECTED="-DaltDeploymentRepository=staging::default::file:/w/m2repo
-DaltSnapshotDeploymentRepository=staging::default::file:/w/m2repo
-DaltReleaseDeploymentRepository=staging::default::file:/w/m2repo"
if [ "$(deploy_repository_args /w/m2repo)" = "$EXPECTED" ]; then
  echo "deploy_repository_args sets all three properties ✅"
else
  echo "deploy_repository_args printed something else ❌"
  deploy_repository_args /w/m2repo
  FAILED=1
fi

# Whatever the build sets, the guard must refuse: one list drives both.
while IFS= read -r arg; do
  if ! find_deploy_repository_override "$arg" >/dev/null; then
    echo "the build sets ${arg%%=*}, which the guard does not refuse ❌"
    FAILED=1
  fi
done < <(deploy_repository_args /w/m2repo)

# find_caller_deploy_repository: sources in the build's order, the
# action's fixed arguments labelled "-". The result names the source.
attributed() {
  local expected="$1" found
  shift
  if found="$(find_caller_deploy_repository "$@")" \
      && [ "$found" = "$expected" ]; then
    echo "attributed '${expected//$'\t'/ -> }' ✅"
  else
    echo "expected '${expected//$'\t'/ -> }', got" \
      "'${found//$'\t'/ -> }' ❌"
    FAILED=1
  fi
}

TAB=$'\t'
# Each source is named when it holds the override alone.
attributed "mvn-params${TAB}altSnapshotDeploymentRepository" \
  mvn-opts "-Dmaven.repo.local=/tmp/r" \
  mvn-params "-DaltSnapshotDeploymentRepository=${R}"
attributed "mvn-phases${TAB}altDeploymentRepository" \
  mvn-phases "clean deploy -DaltDeploymentRepository=${R}" \
  - "-f pom.xml -e"
attributed "MAVEN_ARGS${TAB}altReleaseDeploymentRepository" \
  MAVEN_ARGS "-DaltReleaseDeploymentRepository=${R}" \
  mvn-phases "clean deploy"

# The two-word spelling split across a source boundary: neither half
# sets a property alone, but Maven receives them adjacent.
attributed "the caller arguments, split across two of them${TAB}altDeploymentRepository" \
  mvn-opts "-Dmaven.repo.local=/tmp/r -D" \
  mvn-params "altDeploymentRepository=${R}"
attributed "the caller arguments, split across two of them${TAB}altSnapshotDeploymentRepository" \
  mvn-opts "--define" \
  mvn-params "altSnapshotDeploymentRepository=${R} -B"
# Across an empty source between them, which adds no argument.
attributed "the caller arguments, split across two of them${TAB}altDeploymentRepository" \
  mvn-profiles "-D" \
  mvn-opts "" \
  mvn-params "altDeploymentRepository=${R}"

# A trailing -D next to one of the action's own fixed arguments sets
# nothing of ours, so it must not be refused.
if found="$(find_caller_deploy_repository \
    mvn-phases "clean deploy -D" - "-f pom.xml -e")"; then
  echo "wrongly refused a -D before the action's -f: ${found} ❌"
  FAILED=1
else
  echo "allowed a trailing -D before the action's fixed arguments ✅"
fi
# An override text inside the action's own fixed arguments is not a
# caller's, so a source labelled "-" is never named alone.
if found="$(find_caller_deploy_repository \
    - "-DaltDeploymentRepository=${R}")" \
    && [ "${found%%"${TAB}"*}" = "-" ]; then
  echo "named the action's own fixed arguments as the source ❌"
  FAILED=1
else
  echo "never names the action's fixed arguments as a caller source ✅"
fi
# Clean sources in the build's order pass.
if found="$(find_caller_deploy_repository \
    MAVEN_ARGS "" mvn-phases "clean deploy" - "-f pom.xml -e" \
    - "-P" mvn-profiles "ci" \
    mvn-opts "-Dmaven.repo.local=/tmp/r" mvn-params "-DskipTests")"; then
  echo "wrongly refused clean sources: ${found} ❌"
  FAILED=1
else
  echo "allowed clean sources in the build's order ✅"
fi

# has_globbing_word: Maven's launcher expands MAVEN_ARGS unquoted, so a
# pattern matching a file in the checkout reaches Maven as that file's
# name. Files named as the quoted arguments Maven rewrites.
GLOB_DIR="$(mktemp -d)"
trap 'rm -rf "$GLOB_DIR"' EXIT
(
  cd "$GLOB_DIR"
  : > '"-DaltSnapshotDeploymentRepository=x::default::file:globbed'
  : > '"-Dharmless=value'
)

globs() {
  if (cd "$GLOB_DIR" && has_globbing_word "$1"); then
    echo "pattern expands: ${1//$'\n'/\\n} ✅"
  else
    echo "pattern not seen to expand: ${1//$'\n'/\\n} ❌"
    FAILED=1
  fi
}

literal() {
  if (cd "$GLOB_DIR" && has_globbing_word "$1"); then
    echo "wrongly seen to expand: ${1//$'\n'/\\n} ❌"
    FAILED=1
  else
    echo "passes through unchanged: ${1:-<empty>} ✅"
  fi
}

# The bypass from review: patterns matching those files.
globs '*altSnapshot* *harmless*'
globs '-B *harmless*'
globs $'-B\n*harmless*'
globs '?-Dharmless=value'
globs '["]-Dharmless=value'
# Patterns matching nothing pass through unchanged, so a test filter
# such as -Dtest=*IT stays usable.
literal '-Dtest=*IT'
literal '-Dtest=Foo?'
literal '-Dmaven.repo.local=/tmp/r -DskipTests'
literal ''

exit "$FAILED"
