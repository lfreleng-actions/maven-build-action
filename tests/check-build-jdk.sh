#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2026 The Linux Foundation
#
# Checks that a build of the multi-subproject fixture ran on the JDK
# asked for, from what the build itself left: each deployed jar's
# Build-Jdk-Spec, which maven-jar-plugin writes from the JDK running
# Maven, and app's Surefire reports, which record the forked JVM's
# java.specification.version. Both must name <java-version>, and the
# reports must hold a passing test and no failure or error.
#
# The JDK on PATH after the action proves what it installed; this
# proves what the build used.
#
# Usage: check-build-jdk.sh <m2repo-dir> <fixture-dir> <java-version>

set -euo pipefail

M2REPO="${1:?m2repo directory}"
FIXTURE="${2:?fixture directory}"
JAVA="${3:?java version}"
FAILED=0

fail() {
  echo "$1 ❌" >&2
  FAILED=1
}

for module in core app; do
  DIR="${M2REPO}/org/lfreleng/fixture/${module}"
  JARS="$(find "$DIR" -type f -name "${module}-*.jar" 2>/dev/null || true)"
  if [ -z "$JARS" ]; then
    fail "No deployed ${module} jar under ${DIR}"
    continue
  fi
  while IFS= read -r jar; do
    BUILT="$(unzip -p "$jar" META-INF/MANIFEST.MF \
      | sed -n 's/^Build-Jdk-Spec: *\([0-9]*\).*/\1/p')"
    if [ "$BUILT" = "$JAVA" ]; then
      echo "${jar##*/} built by JDK ${BUILT} ✅"
    else
      fail "${jar##*/} built by JDK '${BUILT}', expected ${JAVA}"
    fi
  done <<< "$JARS"
done

REPORTS="${FIXTURE}/app/target/surefire-reports"
COUNTS="$(
  python3 - "$REPORTS" "$JAVA" <<'PY'
import pathlib
import sys
import xml.etree.ElementTree as ET

reports = sorted(pathlib.Path(sys.argv[1]).glob("TEST-*.xml"))
java = sys.argv[2]
tests = bad = wrong = 0
for report in reports:
    suite = ET.parse(report).getroot()
    tests += int(suite.get("tests", 0)) - int(suite.get("skipped", 0))
    bad += int(suite.get("failures", 0)) + int(suite.get("errors", 0))
    props = {
        p.get("name"): p.get("value")
        for p in suite.iter("property")
    }
    if props.get("java.specification.version") != java:
        wrong += 1
print(len(reports), tests, bad, wrong)
PY
)"
read -r REPORT_COUNT PASSED BROKEN WRONG_JDK <<< "$COUNTS"
if [ "$REPORT_COUNT" -eq 0 ]; then
  fail "No Surefire reports under ${REPORTS}"
elif [ "$WRONG_JDK" -ne 0 ]; then
  fail "${WRONG_JDK} Surefire report(s) ran on a JDK other than ${JAVA}"
elif [ "$BROKEN" -ne 0 ] || [ "$PASSED" -lt 1 ]; then
  fail "Surefire: ${PASSED} test(s) ran, ${BROKEN} failed or errored"
else
  echo "Surefire: ${PASSED} test(s) passed on JDK ${JAVA} ✅"
fi

exit "$FAILED"
