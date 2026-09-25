#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
#
# Holds the action to the deployment repository (m2repo) contract a
# SNAPSHOT merge lane relies on. The lane seeds the maven-metadata.xml
# Nexus already publishes into m2repo before the build, so the
# maven-deploy-plugin continues the SNAPSHOT buildNumber from there
# rather than restarting at 1. That only works while the action leaves
# m2repo in place and deploys into it.
#
# seed writes two things into m2repo before the build:
#   - version-level metadata for the fixture's core subproject, as Nexus
#     publishes it, claiming SEEDED_BUILD_NUMBER deploys so far;
#   - a marker at a path no build of the fixture produces.
#
# check runs after a deploy and requires the marker to survive intact,
# core's next deploy to carry the following buildNumber, and the action
# to report the path it deployed to.
#
# Usage:
#   m2repo-contract.sh seed <m2repo-dir>
#   m2repo-contract.sh check <m2repo-dir> <reported-m2repo-path>

set -euo pipefail

MODE="${1:?mode: seed or check}"
M2REPO="${2:?m2repo directory}"

SEEDED_BUILD_NUMBER=41
CORE_DIR="${M2REPO}/org/lfreleng/fixture/core/1.0.0-SNAPSHOT"
MARKER="${M2REPO}/org/example/sentinel/1.0/sentinel.marker"
MARKER_TEXT='seeded before the build; must survive the deploy'

build_number() {
  python3 - "$1" <<'PY'
import sys
import xml.etree.ElementTree as ET

node = ET.parse(sys.argv[1]).find('./versioning/snapshot/buildNumber')
print(node.text.strip() if node is not None and node.text else 'missing')
PY
}

case "$MODE" in
  seed)
    mkdir -p "$CORE_DIR" "$(dirname "$MARKER")"
    cat > "${CORE_DIR}/maven-metadata.xml" <<EOF
<?xml version="1.0" encoding="UTF-8"?>
<metadata modelVersion="1.1.0">
  <groupId>org.lfreleng.fixture</groupId>
  <artifactId>core</artifactId>
  <version>1.0.0-SNAPSHOT</version>
  <versioning>
    <snapshot>
      <timestamp>20250101.000000</timestamp>
      <buildNumber>${SEEDED_BUILD_NUMBER}</buildNumber>
    </snapshot>
    <lastUpdated>20250101000000</lastUpdated>
    <snapshotVersions>
      <snapshotVersion>
        <extension>jar</extension>
        <value>1.0.0-20250101.000000-${SEEDED_BUILD_NUMBER}</value>
        <updated>20250101000000</updated>
      </snapshotVersion>
      <snapshotVersion>
        <extension>pom</extension>
        <value>1.0.0-20250101.000000-${SEEDED_BUILD_NUMBER}</value>
        <updated>20250101000000</updated>
      </snapshotVersion>
    </snapshotVersions>
  </versioning>
</metadata>
EOF
    printf '%s\n' "$MARKER_TEXT" > "$MARKER"
    echo "Seeded ${M2REPO} with core buildNumber ${SEEDED_BUILD_NUMBER}"
    ;;

  check)
    REPORTED="${3:?reported m2repo path}"
    EXPECTED_BUILD_NUMBER=$((SEEDED_BUILD_NUMBER + 1))
    FAILED=0

    if [ "$REPORTED" = "$M2REPO" ]; then
      echo "m2repo_path reports ${REPORTED} ✅"
    else
      echo "m2repo_path reports '${REPORTED}', expected '${M2REPO}' ❌" >&2
      FAILED=1
    fi

    if [ -f "$MARKER" ] && [ "$(cat "$MARKER")" = "$MARKER_TEXT" ]; then
      echo 'Content seeded before the build survived the deploy ✅'
    else
      echo "The seeded marker at ${MARKER} is gone or altered ❌" >&2
      echo 'Something cleared m2repo before or during the build.' >&2
      FAILED=1
    fi

    # Each probe below tolerates its own failure: find exits non-zero
    # when a directory is absent, and under set -e that would end the
    # script before the assertion reports it. An absent directory is an
    # empty match set, which the assertion then records as a failure.
    #
    # The deploy wrote into the seeded tree, not beside it: a subproject
    # nothing seeded starts its own numbering at 1.
    APP_JARS="$(find "${M2REPO}/org/lfreleng/fixture/app" -type f \
      -name 'app-1.0.0-*-1.jar' 2>/dev/null || true)"
    if [ -n "$APP_JARS" ]; then
      echo 'The deploy wrote its own output into m2repo ✅'
    else
      echo 'No deployed app jar in m2repo ❌' >&2
      FAILED=1
    fi

    METADATA="${CORE_DIR}/maven-metadata.xml"
    if [ -f "$METADATA" ]; then
      FOUND="$(build_number "$METADATA")" || FOUND='unparseable'
    else
      FOUND='missing'
    fi
    CORE_JARS="$(find "$CORE_DIR" -type f \
      -name "core-1.0.0-*-${EXPECTED_BUILD_NUMBER}.jar" 2>/dev/null || true)"
    if [ "$FOUND" = "$EXPECTED_BUILD_NUMBER" ] && [ -n "$CORE_JARS" ]; then
      echo "core continued from the seeded buildNumber:" \
        "${SEEDED_BUILD_NUMBER} -> ${FOUND} ✅"
    else
      echo "core metadata buildNumber is '${FOUND}', expected" \
        "${EXPECTED_BUILD_NUMBER}, continuing from the seeded" \
        "${SEEDED_BUILD_NUMBER} ❌" >&2
      echo 'Deployed core files:' >&2
      find "$CORE_DIR" -type f -name 'core-*.jar' >&2 || true
      FAILED=1
    fi

    exit "$FAILED"
    ;;

  *)
    echo "Unknown mode: ${MODE} ❌" >&2
    exit 1
    ;;
esac
