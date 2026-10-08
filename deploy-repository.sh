#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
#
# The deployment repository (m2repo) the build deploys into, sourced by
# the step that checks a caller's own deploy repository and by the
# build step that sets it. One file, so the property list that step
# checks is the list the build sets; two copies could drift apart and
# leave a property checked but not set, or set but not checked.
#
# maven-deploy-plugin reads three properties. The snapshot and release
# ones take precedence over altDeploymentRepository whatever the
# argument order, so setting altDeploymentRepository alone, even last,
# leaves both open as a way round it. Verified against Maven 3.9.16 and
# maven-deploy-plugin 3.1.4.
DEPLOY_REPOSITORY_PROPERTIES='altDeploymentRepository
altSnapshotDeploymentRepository
altReleaseDeploymentRepository'

# What find_deploy_repository_override prints for a word that begins
# with a double quote. Not a property name, so it cannot collide with
# one.
DEPLOY_REPOSITORY_QUOTE='a leading double quote'

# deploy_repository_args <m2repo-dir>
#
# Print the -D arguments pointing all three properties at the
# directory, one per line. The build places them after every caller
# argument: Maven honours the last value it reads for a property.
deploy_repository_args() {
  local dir="$1" property
  while IFS= read -r property; do
    printf -- '-D%s=staging::default::file:%s\n' "$property" "$dir"
  done <<< "$DEPLOY_REPOSITORY_PROPERTIES"
}

# deploy_repository_targets <value> <directory>
#
# Return 0 when a deploy-repository value, the text after "name=",
# names the file repository at the directory; return 1 otherwise. The
# repository id and layout are ignored, since the build replaces the
# whole value. Quote characters are dropped first: callers wrote
# file:"${GITHUB_WORKSPACE}"/m2repo for years, expecting a shell to
# remove them, and they meant the directory either way. Only an
# absolute path counts; a relative one depends on where Maven starts.
deploy_repository_targets() {
  local value="$1" dir="$2" url
  case "$value" in
    *::*) ;;
    *) return 1 ;;
  esac
  url="${value##*::}"
  url="${url//\"/}"
  url="${url//\'/}"
  case "$url" in
    file:/*) url="${url#file:}" ;;
    *) return 1 ;;
  esac
  # file:///path is the same location as file:/path.
  case "$url" in
    ///*) url="${url#//}" ;;
  esac
  while [ "${url%/}" != "$url" ]; do url="${url%/}"; done
  while [ "${dir%/}" != "$dir" ]; do dir="${dir%/}"; done
  [ -n "$url" ] && [ "$url" = "$dir" ]
}

# find_deploy_repository_override <argument-string> [<m2repo-dir>]
#
# Print the first deploy-repository property the string sets, or
# DEPLOY_REPOSITORY_QUOTE for a word beginning with a double quote,
# and return 0; return 1 when it holds neither. The string is split on
# whitespace, as the build's unquoted expansion splits it, so each
# word is an argument Maven receives.
#
# Given a directory, a property whose value names it is passed over:
# the build sets that same directory last, so the caller's copy
# changes nothing. A leading double quote is reported regardless.
#
# Maven's command line accepts four spellings of a property, and only
# these, with no abbreviated long options:
#   -Dname=value   -D name=value   --define name=value
#   --define=name=value
# plus -Dname alone, which sets the property to "true". A name merely
# beginning with one of ours, such as -DaltDeploymentRepositoryUrl, is
# a different property and passes.
#
# A word beginning with a double quote is refused outright, whatever it
# holds. Maven 3.9 rewrites such words before parsing them: it strips
# the quotes from "-Dname=value", turning a word this check would not
# recognise into a real property, and an opening quote never closed
# joins every word after it into one, absorbing the action's own
# deploy repository arguments into a harmless property's value. The
# shell passes the quote characters to Maven literally. Rather than
# mirror a parser that differs between Maven versions, refuse the one
# shape that triggers it: a quote anywhere but the start of a word,
# and a single quote anywhere, reach Maven unchanged.
find_deploy_repository_override() {
  local allow="${2-}"
  local -a words
  local word setting name property count i
  # -d '' reads the whole string rather than its first line, splitting
  # on spaces, tabs and newlines alike, as the build's unquoted
  # expansion does. A caller writing mvn-params as a YAML block puts
  # each argument on its own line; reading one line would miss the
  # rest. read returns non-zero on reaching the end without a NUL,
  # which is the expected case here.
  read -r -d '' -a words <<< "$1" || true
  count="${#words[@]}"
  for ((i = 0; i < count; i++)); do
    word="${words[i]}"
    if [ "${word:0:1}" = '"' ]; then
      printf '%s\n' "$DEPLOY_REPOSITORY_QUOTE"
      return 0
    fi
    case "$word" in
      -D | --define)
        ((i + 1 < count)) || continue
        setting="${words[i + 1]}"
        # The value word of a two-word property is checked here, before
        # the loop skips past it: Maven strips its quotes too.
        if [ "${setting:0:1}" = '"' ]; then
          printf '%s\n' "$DEPLOY_REPOSITORY_QUOTE"
          return 0
        fi
        i=$((i + 1))
        ;;
      --define=*) setting="${word#--define=}" ;;
      -D*) setting="${word#-D}" ;;
      *) continue ;;
    esac
    name="${setting%%=*}"
    while IFS= read -r property; do
      if [ "$name" = "$property" ]; then
        # -Dname alone sets "true", which names no directory.
        if [ -n "$allow" ] && [ "$setting" != "$name" ] \
            && deploy_repository_targets "${setting#*=}" "$allow"; then
          continue 2
        fi
        printf '%s\n' "$property"
        return 0
      fi
    done <<< "$DEPLOY_REPOSITORY_PROPERTIES"
  done
  return 1
}

# find_caller_deploy_repository [--allow <m2repo-dir>] <label> <arguments>
#   [<label> <arguments>]...
#
# Print "<label><TAB><property>" for the first deploy-repository
# property the arguments set, and return 0; return 1 when they set
# none. Pass each source in the order the build passes it to Maven,
# including the action's own fixed arguments between them, labelled
# "-": the arguments either side of a source decide what it joins.
# With --allow, a property naming that directory is passed over, as
# find_deploy_repository_override describes.
#
# Each source is checked alone first, so the error names the one to
# change. Then all of them together, as Maven receives them: a trailing
# -D or --define in one source and a property name opening the next
# form a single two-word property that neither holds alone.
find_caller_deploy_repository() {
  local label property allow='' all=''
  if [ "${1-}" = "--allow" ]; then
    allow="$2"
    shift 2
  fi
  while [ "$#" -ge 2 ]; do
    label="$1"
    if [ "$label" != "-" ] \
        && property="$(find_deploy_repository_override "$2" "$allow")"; then
      printf '%s\t%s\n' "$label" "$property"
      return 0
    fi
    all="$all $2"
    shift 2
  done
  if property="$(find_deploy_repository_override "$all" "$allow")"; then
    printf '%s\t%s\n' "the caller arguments, split across two of them" \
      "$property"
    return 0
  fi
  return 1
}

# has_globbing_word <argument-string>
#
# Return 0 when a word in the string is a pathname pattern that matches
# a file from the current directory, so a shell expanding the string
# unquoted would replace it; return 1 otherwise. Prints nothing: the
# word may carry a credential.
#
# The action turns pathname expansion off around its own mvn calls,
# but Maven's launcher script expands MAVEN_ARGS unquoted itself, out
# of the action's reach. A pattern there that matches a file in the
# checkout reaches Maven as that file's name, which the deploy check
# never saw: a file named '"-Dname=value' turns back into the quoted
# argument this file refuses. A pattern matching nothing is passed on
# unchanged, so -Dtest=*IT stays usable wherever no file matches it.
has_globbing_word() {
  local -a words matches
  local word
  read -r -d '' -a words <<< "$1" || true
  for word in "${words[@]}"; do
    case "$word" in
      *[*?[]*)
        # Deliberately unquoted: this is the expansion being tested.
        # The word holds no whitespace, so only pathname expansion
        # applies. nullglob stays off, as in the launcher's shell, so
        # an unmatched pattern comes back unchanged.
        # shellcheck disable=SC2206
        matches=($word)
        if [ "${#matches[@]}" -ne 1 ] || [ "${matches[0]}" != "$word" ]; then
          return 0
        fi
        ;;
    esac
  done
  return 1
}
