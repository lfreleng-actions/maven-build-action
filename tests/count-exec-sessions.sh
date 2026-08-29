#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
#
# Count the session blocks in a JaCoCo exec file.
#
# A JaCoCo exec file opens each session with a header block: the byte
# 01 for the block type, then the magic number c0 c0, then two bytes of
# format version. The agent writes another one every time it appends to
# a file, so the count says how many runs a file holds. The version
# bytes are left out of the pattern, so a JaCoCo that changes them does
# not leave this counting zero.
#
# Usage: count-exec-sessions.sh <exec-file>

set -euo pipefail

FILE="${1:?usage: count-exec-sessions.sh <exec-file>}"

if [ ! -f "$FILE" ]; then
  echo "No such exec file: $FILE" >&2
  exit 1
fi

LC_ALL=C grep -ao "$(printf '\x01\xc0\xc0')" "$FILE" | wc -l
