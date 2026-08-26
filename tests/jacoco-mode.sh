#!/usr/bin/env bash
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
#
# Exercises the JaCoCo mode resolution in action.yaml.
#
# The logic decides whether to point every subproject's JaCoCo agent at
# one shared execution file, or to leave the layout to the project. Get
# that wrong against a project that places its own coverage data and the
# result is a build that passes and reports no coverage at all, which is
# the failure this suite exists to catch.
#
# The script under test is read out of action.yaml rather than copied,
# so the suite cannot drift away from what the action runs.

set -u

REPO_ROOT="$(cd "$(dirname -- "${BASH_SOURCE[0]}")/.." && pwd)"
ACTION="${REPO_ROOT}/action.yaml"
# The resolver sources the workspace-variable expansion from the action
# directory, so point that at the checkout under test.
export GITHUB_ACTION_PATH="$REPO_ROOT"
LOGIC="$(mktemp)"
trap 'rm -f "$LOGIC"' EXIT

# From 'set -euo pipefail', not from the first case statement. The
# action's shell options are part of what is under test: a command that
# exits non-zero on a legitimate input aborts the real step, and a suite
# running without those options reports success while the action fails.
awk '/^        set -euo pipefail$/{f=1} f && /^    - name: /{exit} f{print}' \
  "$ACTION" | sed 's/^        //' > "$LOGIC"

if [ ! -s "$LOGIC" ]; then
  echo 'Could not read the JaCoCo mode logic out of action.yaml ❌' >&2
  echo 'The step it lives in was renamed or reindented.' >&2
  exit 1
fi

PASS=0; FAIL=0
STUB=/tmp/jmstub; mkdir -p "$STUB"
# Effective POMs, shaped the way help:effective-pom really writes them:
# pretty-printed, one element per line. A single-line stub would let the
# pluginManagement and goal checks pass on text they cannot really parse.
epom() {
  # $1 = configuration body, $2 = goal, $3 = wrapper, $4 = properties
  printf '<project>\n'
  [ -n "${4:-}" ] && printf '  <properties>\n%s\n  </properties>\n' "$4"
  printf '  <build>\n'
  [ -n "${3:-}" ] && printf '    <%s>\n' "$3"
  printf '      <plugins>\n        <plugin>\n'
  printf '          <artifactId>jacoco-maven-plugin</artifactId>\n'
  printf '          <executions>\n            <execution>\n'
  printf '              <goals>\n                <goal>%s</goal>\n' \
    "${2:-prepare-agent}"
  printf '              </goals>\n            </execution>\n'
  printf '          </executions>\n'
  [ -n "${1:-}" ] && printf '          <configuration>\n%s\n          </configuration>\n' "$1"
  printf '        </plugin>\n      </plugins>\n'
  [ -n "${3:-}" ] && printf '    </%s>\n' "$3"
  printf '  </build>\n</project>\n'
}
DEFAULT_EPOM="$(epom)"
export DEFAULT_EPOM

cat > "$STUB/mvn" <<'STUBEOF'
#!/usr/bin/env bash
# Stubbed Maven. MVN_EXIT forces a failure; MVN_DEST / MVN_DATA answer
# help:evaluate per expression.
if [ -n "${MVN_EXIT:-}" ]; then exit "$MVN_EXIT"; fi
expr=""; epom=""; out=""
for a in "$@"; do
  case "$a" in
    -Dexpression=*) expr="${a#-Dexpression=}";;
    help:effective-pom) epom=1;;
    -Doutput=*) out="${a#-Doutput=}";;
  esac
done
# help:effective-pom writes through -Doutput, since -q discards its stdout.
if [ -n "$epom" ]; then
  [ -n "$out" ] && printf '%s\n' "${MVN_EPOM:-$DEFAULT_EPOM}" > "$out"
  exit 0
fi
case "$expr" in
  jacoco.destFile) printf '%s' "${MVN_DEST-null object or invalid expression}";;
  jacoco.dataFile) printf '%s' "${MVN_DATA-null object or invalid expression}";;
  jacoco.append) printf '%s' "${MVN_APPEND-null object or invalid expression}";;
  *) printf 'null object or invalid expression';;
esac
STUBEOF
chmod +x "$STUB/mvn"

# The resolver writes mode=off before doing most of its work, so an abort
# after that point leaves an output file that looks like a deliberate
# step-aside. Checking the exit status as well is what tells the two
# apart: T_RC names the status expected, defaulting to success.
run() {
  local name="$1"; shift
  local expect_mode="$1" expect_data="$2"; shift 2
  local expect_rc="${T_RC:-0}" rc=0
  local out; out="$(mktemp)"
  ( export PATH="$STUB:$PATH" GITHUB_OUTPUT="$out"
    export RUN_JACOCO="${T_RUN:-true}" JACOCO_MODE="${T_MODE:-auto}" MVN_OPTS="${T_OPTS:-}" \
      MVN_PARAMS="${T_PARAMS:-}" MVN_PROFILES="${T_PROFILES:-}" \
      PATH_PREFIX="${T_PREFIX:-.}" MVN_POM_FILE="${T_POM:-pom.xml}" \
      MAVEN_ARGS="${T_MAVEN_ARGS:-}" \
      GLOBAL_SETTINGS="${T_SETTINGS:-}"
    [ -n "${T_DEST+x}" ] && export MVN_DEST="$T_DEST"
    [ -n "${T_DATA+x}" ] && export MVN_DATA="$T_DATA"
    [ -n "${T_APPEND+x}" ] && export MVN_APPEND="$T_APPEND"
    [ -n "${T_EPOM+x}" ] && export MVN_EPOM="$T_EPOM"
    [ -n "${T_EXIT+x}" ] && export MVN_EXIT="$T_EXIT"
    bash "$LOGIC" ) >/dev/null 2>&1 || rc=$?
  local mode data stale
  mode="$(sed -n 's/^mode=//p' "$out")"
  data="$(sed -n 's/^data_file=//p' "$out")"
  stale="$(sed -n 's/^data_preexisting=//p' "$out")"
  if [ -n "${T_STALE+x}" ] && [ "$stale" != "$T_STALE" ]; then
    FAIL=$((FAIL+1))
    printf 'FAIL %-46s stale=%s expected=%s\n' "$name" "$stale" "$T_STALE"
    rm -f "$out"
    return
  fi
  if [ "$rc" != "$expect_rc" ]; then
    FAIL=$((FAIL+1))
    printf 'FAIL %-46s exit=%s expected=%s\n' "$name" "$rc" "$expect_rc"
    rm -f "$out"
    return
  fi
  if [ "$mode" = "$expect_mode" ] && { [ "$expect_data" = '*' ] || [ "$data" = "$expect_data" ]; }; then
    PASS=$((PASS+1))
  else
    FAIL=$((FAIL+1))
    printf 'FAIL %-46s mode=%-8s data=%s\n' "$name" "$mode" "$data"
  fi
  rm -f "$out"
}

cd "$(mktemp -d)" || exit 1
touch pom.xml
WS="$PWD"; export GITHUB_WORKSPACE="$WS"

# --- default: nothing set anywhere -> shared aggregation
( unset T_DEST T_DATA; run 'default -> shared' shared '*' )
# --- explicit modes
T_MODE=project run 'mode=project' project ''
# --- caller-supplied properties win, in every spelling
T_PARAMS='-Djacoco.dataFile=/w/j.exec' run '-Dx=v'         project '/w/j.exec'
T_PARAMS='-D jacoco.dataFile=/w/j.exec' run '-D x=v'       project '/w/j.exec'
T_PARAMS='--define jacoco.destFile=/w/j.exec' run '--define x v' project '/w/j.exec'
T_PARAMS='--define=jacoco.destFile=/w/j.exec' run '--define=x=v' project '/w/j.exec'
T_OPTS='-Djacoco.destFile=/w/j.exec' run 'via mvn-opts'    project '/w/j.exec'
T_MAVEN_ARGS='-Djacoco.dataFile=/w/j.exec' run 'via MAVEN_ARGS' project '/w/j.exec'
# --- parallel builds leave the layout alone
T_PARAMS='-T 2' run '-T in params'                          off ''
T_PARAMS='--threads 1C' run '--threads in params'           off ''
T_OPTS='-T 4' run '-T in mvn-opts'                          off ''
T_MAVEN_ARGS='-T 2' run '-T in MAVEN_ARGS'                  off ''
# --- .mvn/maven.config beside the working directory
mkdir -p .mvn && printf -- '-T 2\n' > .mvn/maven.config
run '-T in .mvn/maven.config'                               off ''
printf -- '-Djacoco.destFile=/w/j.exec\n' > .mvn/maven.config
run 'property in .mvn/maven.config'               project '/w/j.exec'
printf -- '# -T 2 is disabled here\n' > .mvn/maven.config
run 'commented -T in .mvn/maven.config'                     shared '*'
printf -- '  #-Djacoco.destFile=/w/j.exec\n' > .mvn/maven.config
run 'commented property in .mvn/maven.config'               shared '*'
# Verified against Maven 3.9.9: maven.config is the weakest source,
# MAVEN_ARGS overrides it, and an explicit argument overrides both.
printf -- '-Djacoco.destFile=/cfg/j.exec\n' > .mvn/maven.config
T_MAVEN_ARGS='-Djacoco.destFile=/env/j.exec' \
  run 'MAVEN_ARGS beats .mvn/maven.config'        project '/env/j.exec'
T_MAVEN_ARGS='-Djacoco.destFile=/env/j.exec' \
  T_PARAMS='-Djacoco.destFile=/cli/j.exec' \
  run 'explicit argument beats MAVEN_ARGS'        project '/cli/j.exec'
printf -- '' > .mvn/maven.config
rm -rf .mvn
# --- .mvn/maven.config beside a nested POM
mkdir -p sub/.mvn && touch sub/pom.xml
printf -- '-T 2\n' > sub/.mvn/maven.config
T_PREFIX='sub' run '-T in nested .mvn/maven.config'         off ''
T_PREFIX='.' T_POM='sub/pom.xml' run '-T via mvn-pom-file'  off ''
rm -rf sub
# --- the project owns the layout via its POM
# Read out of the effective POM, which carries every reactor project.
# help:evaluate answers for the top-level project alone, so a property a
# subproject sets reads back as nobody setting it.
T_EPOM="$(epom '' '' '' '    <jacoco.destFile>/p/j.exec</jacoco.destFile>')" \
  run 'POM destFile property' project ''
T_EPOM="$(epom '' '' '' '    <jacoco.dataFile>/p/j.exec</jacoco.dataFile>')" \
  run 'POM dataFile property' project ''
# Maven writes an empty property self-closing, as '<jacoco.destFile />'.
T_EPOM="$(epom '' '' '' '    <jacoco.destFile />')" \
  run 'POM property resolves empty' project ''
T_EPOM="$(epom '' '' '' '    <jacoco.append>false</jacoco.append>')" \
  run 'POM turns appending off' project ''
# <append> in the plugin configuration reaches the agent the same way,
# and beats an injected -D outright.
T_EPOM="$(epom '<append>false</append>')" \
  run 'POM append element off' project ''
# A reactor child owning the layout speaks for the build.
T_EPOM="$(printf '%s\n%s\n' "$(epom)" \
  "$(epom '' '' '' '    <jacoco.destFile>/c/j.exec</jacoco.destFile>')")" \
  run 'reactor child sets destFile' project ''
# --- probe failure fails closed
T_EXIT=1 run 'mvn probe fails -> project'                   project ''
# --- explicit shared overrides the probe
T_MODE=shared T_DEST='/p/j.exec' run 'mode=shared beats POM' shared '*'
# --- off
T_MODE=off run "mode=off" off ""

T_RUN=false run 'run-jacoco=false'                          off ''
T_MODE=bogus T_RC=1 run 'invalid mode rejected'             '' ''
T_PARAMS='-Djacoco.dataFile=/a -Djacoco.dataFile=/b' run 'last dataFile wins' project '/b'
T_PARAMS='-Djacoco.destFile=/d' run 'destFile only, no dataFile' project '/d'

T_PARAMS='-Djacoco.append=false' run 'append=false -> leave alone'  off ''
T_PARAMS='-Djacoco.append=true' run 'append=true -> still shared'    shared '*'
( unset T_DEST T_DATA; T_APPEND=true run 'POM append=true is not a layout' shared '*' )

# --- an explicit mode is the caller's call, not a guess to override
T_MODE=shared T_PARAMS='-T 2' run 'explicit shared keeps -T'        shared '*'
T_MODE=project T_PARAMS='-T 2 -Djacoco.dataFile=/w/j.exec' \
  run 'explicit project keeps -T'                                  project '/w/j.exec'
T_MODE=shared T_PARAMS='-Djacoco.append=false' \
  run 'explicit shared keeps append=false'                         shared '*'
# --- a relative caller path names one file per subproject, not one file
T_PARAMS='-Djacoco.dataFile=target/j.exec' \
  run 'relative caller path -> no report pass'                     project ''
# --- an explicit <configuration> beats -D and no property lookup sees it
T_EPOM="$(epom '<destFile>x</destFile>')" \
  run 'POM plugin destFile config'                                 project ''
T_EPOM="$(epom '<dataFile>x</dataFile>')" \
  run 'POM plugin dataFile config'                                 project ''
T_EPOM="$(epom)" run 'plain POM -> shared' shared '*'
# --- no JaCoCo plugin means no agent, so nothing to share
# An artifact in the effective POM does not mean an agent runs. A parent
# declaring JaCoCo in pluginManagement, or a project binding only the
# report goal, must be left alone: aggregating there would fail an
# ordinary tested build that never asked for coverage.
T_EPOM="$(epom '' 'prepare-agent' 'pluginManagement')" \
  run 'pluginManagement only -> off' off ''
T_EPOM="$(epom '' 'report')" run 'report goal only -> off' off ''
T_EPOM="$(epom '<skip>true</skip>')" run 'agent skipped in POM -> off' off ''
T_EPOM="$(epom '' 'prepare-agent-integration')" \
  run 'integration agent -> shared' shared '*'
T_PARAMS='-Djacoco.skip=true' run 'skip on command line -> off' off ''
# Maven reads a bare -Dname as true.
T_PARAMS='-Djacoco.skip' run 'valueless skip -> off' off ''
T_PARAMS='--define jacoco.skip' run 'valueless define skip -> off' off ''
T_PARAMS='--define=jacoco.skip' run 'valueless define= skip -> off' off ''
T_PARAMS='-D jacoco.skip=true' run 'spaced -D skip -> off' off ''
# Maven converts booleans case-insensitively, so TRUE is true.
T_PARAMS='-Djacoco.skip=TRUE' run 'uppercase skip -> off' off ''
T_MAVEN_ARGS='-Djacoco.append=FALSE' run 'uppercase append off -> off' off ''
T_EPOM="$(epom '<skip>TRUE</skip>')" run 'uppercase POM skip -> off' off ''
T_EPOM="$(epom '<append>FALSE</append>')" \
  run 'uppercase POM append off' project ''

# A plugin configuration element beats an injected -D, including one the
# caller passed, so the caller's path names a file nothing writes.
T_EPOM="$(epom '<destFile>/p/j.exec</destFile>')" T_PARAMS='-Djacoco.dataFile=/c/j.exec' \
  run 'POM element beats caller path' project ''
# A POM property does not beat a -D of the same name, so a caller who
# passes jacoco.destFile keeps the agent where they put it.
T_EPOM="$(epom '' '' '' '    <jacoco.destFile>/p/j.exec</jacoco.destFile>')" \
  T_PARAMS='-Djacoco.destFile=/c/j.exec' \
  run 'caller destFile beats POM destFile property' project '/c/j.exec'
# -D only outranks the property of the same name. A caller who passes
# only jacoco.dataFile leaves the POM's jacoco.destFile in charge of
# where the agent writes, so their path names a file nothing writes and
# no report pass may be scheduled against it.
T_EPOM="$(epom '' '' '' '    <jacoco.destFile>/p/j.exec</jacoco.destFile>')" \
  T_PARAMS='-Djacoco.dataFile=/c/j.exec' \
  run 'POM destFile property survives a caller dataFile' project ''
# The mirror image: the POM names only the report input, the caller owns
# the agent, so the caller's path is written and may be reported on.
T_EPOM="$(epom '' '' '' '    <jacoco.dataFile>/p/j.exec</jacoco.dataFile>')" \
  T_PARAMS='-Djacoco.destFile=/c/j.exec' \
  run 'caller destFile stands beside a POM dataFile property' \
  project '/c/j.exec'
# A bare -Djacoco.destFile carries no '=' and Maven reads it as true, so
# the caller has named a relative file rather than nothing.
T_PARAMS='-Djacoco.destFile' run 'valueless caller destFile' project ''

# Maven scopes an execution's configuration to that execution and merges
# it over the plugin-level default.
EX_POM() {
  # $1 = plugin-level body, $2 = prepare-agent execution body,
  # $3 = extra execution block. One element per line, the way
  # help:effective-pom really writes it.
  printf '%s\n' '<project>' '  <build>' '    <plugins>' '      <plugin>' \
    '        <artifactId>jacoco-maven-plugin</artifactId>'
  [ -n "${1:-}" ] && printf '%s\n%s\n%s\n' '        <configuration>' \
    "$1" '        </configuration>'
  printf '%s\n' '        <executions>' '          <execution>' \
    '            <goals>' '              <goal>prepare-agent</goal>' \
    '            </goals>'
  [ -n "${2:-}" ] && printf '%s\n%s\n%s\n' '            <configuration>' \
    "$2" '            </configuration>'
  printf '%s\n' '          </execution>'
  [ -n "${3:-}" ] && printf '%s\n' "$3"
  printf '%s\n' '        </executions>' '      </plugin>' '    </plugins>' \
    '  </build>' '</project>'
}
# A report execution naming a dataFile says nothing about where the
# agent writes, so aggregation still applies.
T_EPOM="$(EX_POM '' '' '          <execution>
            <id>r</id>
            <goals>
              <goal>report</goal>
            </goals>
            <configuration>
              <dataFile>/x.exec</dataFile>
            </configuration>
          </execution>')" \
  run 'report execution dataFile -> shared' shared '*'
# The prepare-agent execution naming a destFile does place the data.
T_EPOM="$(EX_POM '' '<destFile>/x.exec</destFile>')" \
  run 'agent execution destFile -> project' project ''
# An execution skip of false does override a plugin-level skip of true,
# so the agent writes. The report this action runs afterwards lands in a
# default-cli execution, which inherits the plugin-level skip and writes
# no XML, so there is nothing to aggregate and the step aside stands.
T_EPOM="$(EX_POM '<skip>true</skip>' '<skip>false</skip>')" \
  run 'plugin skip silences the report pass' off ''
# With no execution value the plugin-level default still stands.
T_EPOM="$(EX_POM '<skip>true</skip>' '')" \
  run 'plugin skip with no override -> off' off ''
T_MAVEN_ARGS='-Djacoco.skip=true' T_PARAMS='-Djacoco.skip=false' \
  run 'skip turned back off -> shared' shared '*'
T_MAVEN_ARGS='-Djacoco.skip=false' T_PARAMS='-Djacoco.skip=true' \
  run 'skip turned on last -> off' off ''
# A skipped execution runs nothing, so the destFile it would have used
# says nothing about the layout. The second execution is live and takes
# the default one, which aggregates.
T_EPOM="$(EX_POM '' '<skip>true</skip>
            <destFile>/x.exec</destFile>' '          <execution>
            <id>live</id>
            <goals>
              <goal>prepare-agent</goal>
            </goals>
          </execution>')" \
  run 'skipped execution destFile is not the layout' shared '*'
# The agent writes no file at all under these, so the shared file this
# action would inject stays empty and the report pass would fail a
# build whose tests ran.
T_PARAMS='-Djacoco.output=none' run 'jacoco.output=none -> off' off ''
T_PARAMS='-Djacoco.output=tcpserver' \
  run 'jacoco.output=tcpserver -> off' off ''
T_PARAMS='-Djacoco.output=FILE' run 'jacoco.output=file -> shared' \
  shared '*'
T_PARAMS='-Djacoco.dumpOnExit=false' \
  run 'jacoco.dumpOnExit=false -> off' off ''
T_EPOM="$(EX_POM '' '<output>none</output>')" \
  run 'agent execution output none -> project' project ''
T_EPOM="$(EX_POM '<dumpOnExit>false</dumpOnExit>')" \
  run 'plugin dumpOnExit false -> project' project ''
# Maven merges an execution's configuration over the plugin default, so
# a live execution turning each of these back on aggregates safely.
T_EPOM="$(EX_POM '<append>false</append>' '<append>true</append>')" \
  run 'execution restores appending -> shared' shared '*'
T_EPOM="$(EX_POM '<output>none</output>' '<output>file</output>')" \
  run 'execution restores file output -> shared' shared '*'
T_EPOM="$(EX_POM '<dumpOnExit>false</dumpOnExit>' \
  '<dumpOnExit>true</dumpOnExit>')" \
  run 'execution restores the exit dump -> shared' shared '*'
# ...and with no execution value the plugin default still stands.
T_EPOM="$(EX_POM '<output>none</output>' '')" \
  run 'plugin output none with no override -> project' project ''
T_EPOM="$(epom '' '' '' '    <jacoco.output>none</jacoco.output>')" \
  run 'POM jacoco.output property -> project' project ''
# -D outranks the POM property of the same name, so a caller who turns
# appending back on aggregates rather than stepping aside.
T_EPOM="$(epom '' '' '' '    <jacoco.append>false</jacoco.append>')" \
  T_PARAMS='-Djacoco.append=true' \
  run 'caller append=true beats POM property' shared '*'
# Maven's precedence for the skip, in all three directions. A POM
# property is not a plugin <skip> element and would otherwise leave the
# agent looking bound, failing the report pass on a build with no data.
T_EPOM="$(epom '' '' '' '    <jacoco.skip>true</jacoco.skip>')" \
  run 'POM jacoco.skip property -> off' off ''
# A -D beats that property.
T_EPOM="$(epom '' '' '' '    <jacoco.skip>true</jacoco.skip>')" \
  T_PARAMS='-Djacoco.skip=false' \
  run 'caller skip=false beats POM property' shared '*'
# ...and an explicit element beats the -D: the agent stays live despite
# -Djacoco.skip=true. The plugin-level skip still silences the report.
T_EPOM="$(EX_POM '<skip>true</skip>' '<skip>false</skip>')" \
  T_PARAMS='-Djacoco.skip=true' \
  run 'execution skip element beats caller skip' off ''
# An execution skip of false with no plugin-level skip element leaves
# the report pass free to run, so this one does aggregate.
T_EPOM="$(EX_POM '' '<skip>false</skip>')" \
  T_PARAMS='-Djacoco.skip=true' \
  run 'execution unskips the agent -> shared' shared '*'
# The same rule for the three settings that decide whether a shared file
# can be written at all.
T_EPOM="$(EX_POM '' '<append>true</append>')" \
  T_PARAMS='-Djacoco.append=false' \
  run 'append element beats caller append' shared '*'
T_EPOM="$(EX_POM '' '<output>file</output>')" \
  T_PARAMS='-Djacoco.output=none' \
  run 'output element beats caller output' shared '*'
T_EPOM="$(EX_POM '' '<dumpOnExit>true</dumpOnExit>')" \
  T_PARAMS='-Djacoco.dumpOnExit=false' \
  run 'dumpOnExit element beats caller dumpOnExit' shared '*'
# A configured value stands in for a caller -D where every live agent
# carries it. Here one execution keeps the default, so it follows the
# -D and overwrites the shared file: the configured sibling must not
# hide that.
T_EPOM="$(EX_POM '' '<append>true</append>' '          <execution>
            <id>plain</id>
            <goals>
              <goal>prepare-agent</goal>
            </goals>
          </execution>')" \
  T_PARAMS='-Djacoco.append=false' \
  run 'one defaulted agent still follows caller append' off ''

# A skip belongs to the execution carrying it. Binding prepare-agent and
# skipping a separate report execution is ordinary, and reading that as
# no agent would drop aggregation from a build that produces data.
TWO_EXEC="$(printf '%s\n' \
  '<project>' '  <build>' '    <plugins>' '      <plugin>' \
  '        <artifactId>jacoco-maven-plugin</artifactId>' \
  '        <executions>' \
  '          <execution>' '            <goals>' \
  '              <goal>prepare-agent</goal>' \
  '            </goals>' '          </execution>' \
  '          <execution>' '            <goals>' \
  '              <goal>report</goal>' '            </goals>' \
  '            <configuration><skip>true</skip></configuration>' \
  '          </execution>' \
  '        </executions>' '      </plugin>' \
  '    </plugins>' '  </build>' '</project>')"
T_EPOM="$TWO_EXEC" run 'report execution skipped -> shared' shared '*'

# The last value written is the one Maven honours.
T_MAVEN_ARGS='-Djacoco.append=false' T_PARAMS='-Djacoco.append=true' \
  run 'append turned back on -> shared' shared '*'
T_MAVEN_ARGS='-Djacoco.append=true' T_PARAMS='-Djacoco.append=false' \
  run 'append turned off last -> off' off ''

T_EPOM='<project><build/></project>' \
  run 'no JaCoCo plugin -> nothing to share'                        off ''
T_EPOM="$(epom '<destFile>x</destFile>')" \
  run 'JaCoCo plugin with destFile config'                          project ''
# --- an absolute path_prefix is not glued onto the workspace
T_PREFIX="$WS" run 'absolute path_prefix'                           shared "$WS/target/jacoco-aggregate.exec"

# --- a shared path holding whitespace cannot survive the build's expansion
T_PREFIX='/tmp/a b' run 'whitespace in path -> leave alone'          off ''
# --- an explicit shared is the caller deciding, not a hint to weigh
T_MODE=shared T_PARAMS='-Djacoco.dataFile=/w/j.exec' \
  run 'explicit shared beats a caller path'                          shared '*'

# Project mode reports on a file the caller owns, and the agents append
# to it, so one left by an earlier run in a reused workspace carries its
# records into this run's report. Timestamps cannot see that, so the
# resolver flags the file it found already in place.
STALE_FILE="$WS/stale.exec"
rm -f "$STALE_FILE"
T_PARAMS="-Djacoco.dataFile=$STALE_FILE" \
  T_STALE='' run 'absent caller data is not pre-existing' \
  project "$STALE_FILE"
: > "$STALE_FILE"
T_PARAMS="-Djacoco.dataFile=$STALE_FILE" \
  T_STALE='yes' run 'caller data left in place is flagged' \
  project "$STALE_FILE"
rm -f "$STALE_FILE"

# help:effective-pom prints inactive profiles too, plugin declarations
# and all. Settling the layout from a profile that never runs reads
# configuration the build never applied: here a profile unskips the
# agent while the caller skips JaCoCo outright.
T_EPOM="$(printf '%s\n' '<project>' '  <build>' '    <plugins>' \
  '      <plugin>' '        <artifactId>jacoco-maven-plugin</artifactId>' \
  '        <executions>' '          <execution>' '            <goals>' \
  '              <goal>prepare-agent</goal>' '            </goals>' \
  '          </execution>' '        </executions>' '      </plugin>' \
  '    </plugins>' '  </build>' '  <profiles>' '    <profile>' \
  '      <id>never-on</id>' '      <build>' '        <plugins>' \
  '          <plugin>' \
  '            <artifactId>jacoco-maven-plugin</artifactId>' \
  '            <executions>' '              <execution>' \
  '                <goals>' '                  <goal>prepare-agent</goal>' \
  '                </goals>' \
  '                <configuration>' '                  <skip>false</skip>' \
  '                </configuration>' \
  '              </execution>' '            </executions>' \
  '          </plugin>' '        </plugins>' '      </build>' \
  '    </profile>' '  </profiles>' '</project>')" \
  T_PARAMS='-Djacoco.skip=true' \
  run 'inactive profile does not unskip the agent' off ''

# The jacoco.skip property carries the same problem: read from anywhere
# in the effective POM, a profile that never activated turns coverage
# off for a build it took no part in. This is the fixture's own shape.
T_EPOM="$(printf '%s\n' '<project>' '  <build>' '    <plugins>' \
  '      <plugin>' '        <artifactId>jacoco-maven-plugin</artifactId>' \
  '        <executions>' '          <execution>' '            <goals>' \
  '              <goal>prepare-agent</goal>' '            </goals>' \
  '          </execution>' '        </executions>' '      </plugin>' \
  '    </plugins>' '  </build>' '  <profiles>' '    <profile>' \
  '      <id>never-on</id>' '      <properties>' \
  '        <jacoco.skip>true</jacoco.skip>' '      </properties>' \
  '    </profile>' '  </profiles>' '</project>')" \
  run 'profile jacoco.skip property does not apply' shared '*'

# A reactor effective POM carries one properties section per project.
# One child skipping its own agent says nothing about its siblings, and
# reading the property across the file would disable aggregation for a
# reactor that still produces plenty of data.
proj() {
  printf '%s\n' '  <project>' '    <properties>' "      $1" \
    '    </properties>' '    <build>' '      <plugins>' \
    '        <plugin>' \
    '          <artifactId>jacoco-maven-plugin</artifactId>' \
    '          <executions>' '            <execution>' \
    '              <goals>' '                <goal>prepare-agent</goal>' \
    '              </goals>' '            </execution>' \
    '          </executions>' '        </plugin>' '      </plugins>' \
    '    </build>' '  </project>'
}
T_EPOM="$(printf '%s\n' '<projects>'; proj '<jacoco.skip>true</jacoco.skip>'; \
  proj '<other>x</other>'; printf '%s\n' '</projects>')" \
  run 'one child skipping does not disable the reactor' shared '*'
# Every project skipping does mean no agent runs anywhere.
T_EPOM="$(printf '%s\n' '<projects>'; proj '<jacoco.skip>true</jacoco.skip>'; \
  proj '<jacoco.skip>true</jacoco.skip>'; printf '%s\n' '</projects>')" \
  run 'every child skipping leaves no agent' off ''

# The agent splits its option string at a comma that a name and an
# equals sign follow, so such a path is cut short and the data lands
# somewhere else. A plain comma is fine and must keep aggregating.
T_PREFIX='/tmp/od,append=false' \
  run 'comma reading as an agent option steps aside' off ''
T_PREFIX='/tmp/od,inary' \
  run 'plain comma in the path still aggregates' shared \
  '/tmp/od,inary/target/jacoco-aggregate.exec'

# The build expands a fixed list of workspace variables before Maven
# reads them, so the resolver has to read the same values. Reading the
# literal text would class this as relative and drop the report pass.
# Single quotes on purpose: the literal text is what a caller writes
# and what the resolver has to expand for itself.
# shellcheck disable=SC2016
GITHUB_WORKSPACE=/ws \
  T_PARAMS='-Djacoco.dataFile=${GITHUB_WORKSPACE}/target/j.exec' \
  run 'workspace variable in a caller path expands' project \
  '/ws/target/j.exec'
# shellcheck disable=SC2016
GITHUB_WORKSPACE=/ws \
  T_PARAMS='-Djacoco.dataFile=$GITHUB_WORKSPACE/target/j.exec' \
  run 'bare workspace variable expands too' project '/ws/target/j.exec'

# Each POM property is matched against the caller argument of the same
# name. A caller naming the output mode says nothing about whether the
# project appends, so it must not lift a jacoco.append the POM set.
T_EPOM="$(epom '' '' '' '    <jacoco.append>false</jacoco.append>')" \
  T_PARAMS='-Djacoco.output=file' \
  run 'POM append=false survives an unrelated caller -D' project ''
T_EPOM="$(epom '' '' '' '    <jacoco.append>false</jacoco.append>')" \
  T_PARAMS='-Djacoco.append=true' \
  run 'a caller -Djacoco.append=true lifts the property' shared '*'

printf '\n%d passed, %d failed\n' "$PASS" "$FAIL"
[ "$FAIL" -eq 0 ]
