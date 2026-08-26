#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
#
# Reads the coverage report the action produced for the fixture reactor
# and checks the lines that cross a subproject boundary.
#
# The fixture puts the code in 'core' and the only test in 'app'. A
# report built from core's own execution data credits core with nothing.
# A report built from the whole reactor's credits core with the lines
# app's test reached. The second is what this checks.
#
# Usage: check-subproject-coverage.sh <fixture-dir> <expect-covered|expect-none>

set -euo pipefail

FIXTURE="${1:?fixture directory}"
EXPECT="${2:-expect-covered}"
REPORT="${FIXTURE}/core/target/site/jacoco/jacoco.xml"

# core carries no test of its own, so the report bound inside the build
# has nothing to report on and writes no file. Absent and empty both say
# the same thing here: coverage did not cross the boundary.
if [ ! -f "$REPORT" ]; then
  if [ "$EXPECT" = 'expect-none' ]; then
    echo 'No report for core, so no coverage crossed the boundary ✅'
    exit 0
  fi
  echo "No coverage report at ${REPORT} ❌" >&2
  echo 'The aggregate report pass did not run, or wrote elsewhere.' >&2
  exit 1
fi

# The counter on the Core class, rather than the report total, so a
# report that happens to cover app alone cannot pass this.
COVERED="$(
  python3 - "$REPORT" <<'PY'
import sys
import xml.etree.ElementTree as ET

tree = ET.parse(sys.argv[1])
for cls in tree.iter('class'):
    if cls.get('name') == 'fixture/Core':
        for counter in cls.findall('counter'):
            if counter.get('type') == 'LINE':
                print(counter.get('covered'))
                sys.exit(0)
print('missing')
PY
)"

echo "fixture/Core covered lines: ${COVERED}"

case "$EXPECT" in
  expect-covered)
    if [ "$COVERED" = 'missing' ]; then
      echo 'The report holds no counter for fixture/Core ❌' >&2
      exit 1
    fi
    if [ "$COVERED" -lt 1 ]; then
      echo 'core shows no covered line ❌' >&2
      echo "app's test reaches Core.greet, so a report covering the" >&2
      echo 'whole reactor credits core with those lines. A report' >&2
      echo "built from core's own execution data credits it with" >&2
      echo 'none, which is the failure this checks for.' >&2
      exit 1
    fi
    echo 'Coverage crosses the subproject boundary ✅'
    ;;
  expect-none)
    if [ "$COVERED" != 'missing' ] && [ "$COVERED" -gt 0 ]; then
      echo 'core shows covered lines where none were expected ❌' >&2
      exit 1
    fi
    echo 'Coverage stayed inside each subproject, as expected ✅'
    ;;
  *)
    echo "Unknown expectation: ${EXPECT} ❌" >&2
    exit 1
    ;;
esac
