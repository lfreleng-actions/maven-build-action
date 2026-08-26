<!--
# SPDX-License-Identifier: Apache-2.0
# SPDX-FileCopyrightText: 2025 The Linux Foundation
-->

# ☕️ Build Maven Project

Setup Maven and build the Java project

## maven-build-action

This action used to be alongside other actions in the repository below:

<https://github.com/lfit/releng-reusable-workflows>

Go there to get the revision history and other details prior to Oct 29th 2025.

## Usage Example

<!-- markdownlint-disable MD046 -->

```yaml
steps:
  - name: "Maven Build"
    id: maven-build
    uses: lfreleng-actions/maven-build-action@main
    with:
      global-settings: |
        <settings>
          <servers>
            <server>
              <id>ossrh</id>
              <username>${env.OSSRH_USERNAME}</username>
              <password>${env.OSSRH_PASSWORD}</password>
            </server>
          </servers>
        </settings>
      java-version: "17"
      distribution: "temurin"
      mvn-version: "3.9.11"
      mvn-phases: "clean deploy"
      mvn-pom-file: "pom.xml"
```

<!-- markdownlint-enable MD046 -->

## Inputs

<!-- markdownlint-disable MD013 -->

| Name            | Required | Default        | Description                                                                                                               |
| --------------- | -------- | -------------- | ------------------------------------------------------------------------------------------------------------------------- |
| global-settings | False    | -              | Maven global settings file                                                                                                |
| path_prefix     | False    | `.`            | Directory location containing project code                                                                                |
| java-version    | False    | `21`           | OpenJDK version(s) installed                                                                                              |
| setup-java      | False    | `true`         | Enable or disable Java setup                                                                                              |
| distribution    | False    | `temurin`      | OpenJDK distribution                                                                                                      |
| mvn-version     | False    | `3.9.11`       | Maven version                                                                                                             |
| mvn-params      | False    | -              | Maven parameters to pass to the mvn command                                                                               |
| mvn-phases      | False    | `clean deploy` | Comma separated list of phases to execute                                                                                 |
| mvn-opts        | False    | See below      | Maven options                                                                                                             |
| mvn-pom-file    | False    | `pom.xml`      | Path to pom.xml file                                                                                                      |
| mvn-profiles    | False    | -              | Comma-delimited list of profiles to activate                                                                              |
| env-vars        | False    | `{}`           | Pass GitHub variables for export as environment variables via `toJSON(vars)` or specific variables encoded in JSON format |
| env-secrets     | False    | `{}`           | Pass GitHub secrets for export as environment variables via `toJSON(secrets)` or specific secrets encoded in JSON format  |
| run-jacoco      | False    | `true`         | Boolean defining whether to run Jacoco                                                                                    |
| jacoco-mode     | False    | `auto`         | Coverage across Maven subprojects: `auto`, `shared`, `project` or `off` (see below)                                       |
| artifact-upload | False    | `true`         | Upload the JaCoCo badges directory as a build artifact                                                                    |
| artifact-name   | False    | -              | Uploaded artifact name (default: `maven-build-<job>`)                                                                     |

<!-- markdownlint-enable MD013 -->

### Default Maven Options (mvn-opts)

```bash
-Dorg.slf4j.simpleLogger.log.org.apache.maven.cli.transfer.Slf4jMavenTransferListener=warn
-Dmaven.repo.local=/tmp/r
-Dorg.ops4j.pax.url.mvn.localRepository=/tmp/r
-DaltDeploymentRepository=staging::default::file:"${GITHUB_WORKSPACE}"/m2repo
```

### Workspace Variables in Maven Arguments

The `mvn-params` and `mvn-opts` inputs expand a fixed list of names
before Maven runs:

`GITHUB_WORKSPACE`, `GITHUB_REPOSITORY`, `GITHUB_REF_NAME`, `GITHUB_SHA`,
`GITHUB_RUN_ID`, `RUNNER_TEMP`, `RUNNER_OS`

Both the `${NAME}` and `$NAME` forms work:

```yaml
mvn-params: '-Djacoco.dataFile=${GITHUB_WORKSPACE}/target/jacoco.exec'
```

Maven itself interpolates `${...}` where a value reaches it through POM
interpolation, which leaves a user property a plugin reads directly, such
as `-Djacoco.dataFile`, holding the literal text. Expanding these names
first gives a caller the behaviour Jenkins had.

Every other `${...}` reaches Maven as written, so Maven's own
`${project.*}` and `${settings.*}` still resolve. A name outside the list
stays literal even where the environment holds a value for it, which
keeps a caller's `env-secrets` off the command line. Nothing in the
expansion executes, so `$(...)`, backticks and `$((...))` reach Maven as
written too.

Both inputs split on whitespace, so a value carrying a space becomes more
than one argument. The action names that case in the log rather than
leaving Maven to fail on an argument nobody wrote.

### Using More Than One Java Version

To install more than one JDK version, use the pipe `|` syntax, as described in
the setup-java documentation:

<https://github.com/actions/setup-java?tab=readme-ov-file#install-multiple-jdks>

The last version becomes the default:

```yaml
java-version: |
  17
  21
```

<!-- markdownlint-enable MD013 -->

## Outputs

<!-- markdownlint-disable MD013 MD060 -->

| Name            | Description                                                                                         |
| --------------- | --------------------------------------------------------------------------------------------------- |
| m2repo_path     | Absolute path to the Maven file deployment repository (m2repo) for downstream publish/stage actions |
| m2repo_exists   | Whether the build produced the m2repo directory (`true`/`false`)                                    |
| artifact_count  | Number of jar/pom/war files found in the m2repo                                                     |
| coverage        | JaCoCo line coverage percentage (empty when JaCoCo did not run)                                     |
| branch_coverage | JaCoCo branch coverage percentage (empty when JaCoCo did not run)                                   |
| artifact_name   | Name of the uploaded JaCoCo badges artifact (empty when artifact upload disabled)                   |
| coverage_report_paths | Value for `sonar.coverage.jacoco.xmlReportPaths`, listing the XML the report pass wrote (empty when it wrote none) |
| jacoco_data_file | Path of the JaCoCo execution data every subproject reported against (empty when each subproject kept its own)          |

<!-- markdownlint-enable MD013 MD060 -->

The action also:

- Builds the Java project using Maven
- Generates JaCoCo coverage reports and badges (if enabled)
- Deploys artifacts to the file-based staging repository (`m2repo`)
- Writes a build summary to `GITHUB_STEP_SUMMARY`

Downstream publish/stage actions consume the built `m2repo` via the
`m2repo_path` output; the calling workflow typically uploads it between jobs.

### Coverage across Maven subprojects (jacoco-mode)

A Maven build with subprojects runs the JaCoCo agent once per subproject, and
each subproject writes its own execution data. A report built from one of those
files carries the lines that subproject's own tests reached and drops the lines
another subproject's tests reached, which reads downstream as missing coverage.

A project that binds no JaCoCo agent gets no aggregation and no failure: with no
agent there is no execution data to share. This setting places execution data; it
does not switch coverage on. The JaCoCo agent runs because the project binds
`jacoco:prepare-agent`, in most cases through a parent POM. A project with no
such binding produces no execution data, and no value of `jacoco-mode` changes
that.

Declaring the plugin is not the same as running it. The action reads the
effective POM for a live `prepare-agent` binding outside `pluginManagement`,
scoping configuration the way Maven scopes it: an execution's settings apply to
that execution and merge over the plugin-level default, so a `report` execution
naming a `dataFile` says nothing about where the agent writes, and an
execution's `<skip>false</skip>` overrides a plugin-level `<skip>true</skip>`.
A parent that declares a version without binding it, a project that binds
`report` and nothing else, and a build run with `-Djacoco.skip=true` each keep
the layout they had. A skip counts against the execution that carries it, so
binding the agent and skipping a separate `report` execution still aggregates.

The effective POM also decides who places the execution data, because it
carries every project in the reactor. A subproject that sets
`jacoco.destFile`, `jacoco.dataFile`, a `destFile` or `dataFile` configuration
element, or turns appending off through either `jacoco.append` or an `append`
configuration element takes the layout for the whole build. Where a value
arrives more than once, the one Maven ends up using is the one that counts, and
a bare `-Djacoco.skip` reads as `true` the way Maven reads it.

`jacoco-mode` decides where the execution data lands:

<!-- markdownlint-disable MD013 MD060 -->

| Value     | Behaviour                                                          |
| --------- | ------------------------------------------------------------------ |
| `auto`    | Default. Picks `shared` or `project` from what the build declares. |
| `shared`  | Points every subproject at one execution file, then reports each subproject against it after the reactor finishes. |
| `project` | Leaves the layout to the project. Reports against a caller-supplied `jacoco.dataFile` once the reactor finishes.    |
| `off`     | Changes nothing.                                                   |

<!-- markdownlint-enable MD013 MD060 -->

`auto` picks `project` when the caller passes `jacoco.destFile` or
`jacoco.dataFile`, when the project's own POM resolves either property, or when
the effective POM configures the JaCoCo plugin with a `destFile` or `dataFile`
element. It reads the effective POM under the same profiles, settings and
arguments the build runs with, since a `-D` can activate a profile that
configures JaCoCo. That last case matters because an explicit `<configuration>`
element beats an injected `-D`, and no property lookup can see it.

Otherwise it picks `shared`. A project that already
merges its subprojects' execution data therefore keeps its own layout, and an
injected `-D` never moves the agent output away from the place that merge step
reads.

`auto` steps aside for a caller path Maven resolves per subproject. An absolute
`jacoco.dataFile` names one file for the whole reactor. A relative one names a
separate file under each subproject, so the report pass leaves it to the
project.

`auto` steps aside where the project directory holds whitespace, since the shared
path could not reach Maven as one argument.

`auto` steps aside for `-Djacoco.append=false` as well. The shared file works
because every subproject's agent appends to it; turn appending off and each
subproject overwrites the last, leaving the file holding whichever subproject
ran last.

`auto` also steps aside for a parallel reactor. Agents appending to one file at
once overwrite each other's records, so a build carrying `-T` or
`--threads` — in `mvn-params`, in `mvn-opts`, in `MAVEN_ARGS`, or in a
checked-in `.mvn/maven.config` — keeps coverage per subproject. The scan
skips comment lines in that file, and walks upward from the POM directory to the
first `.mvn` it finds, matching how Maven reads it.

It steps aside again where the agent writes no file to share: `jacoco.output`
set to `tcpserver`, `tcpclient` or `none`, or `jacoco.dumpOnExit` set to
`false`, whether those arrive as arguments, as POM properties, or as
`<output>`/`<dumpOnExit>` configuration elements. Injecting a shared file there
would name one nothing ever writes, and the report pass would then fail a build
whose tests ran. Maven merges an execution's configuration over the plugin-level
default, so a plugin default of `<append>false</append>` that a live
`prepare-agent` execution sets back to `true` still aggregates, the same way an
execution `<skip>false</skip>` overrides a plugin `<skip>true</skip>`. Each of
these settings, the skip included, resolves in Maven's own order: an explicit
configuration element beats a `-D`, a `-D` beats a POM property, and a later
`-D` beats an earlier one.

Every one of these reads the merged build that `help:effective-pom` prints and
ignores the profiles it lists alongside. Verified against Maven 3.9.9: an
inactive profile appears there in full, and an active one appears both there
and merged into the build, so reading the listing would settle coverage from
configuration that never ran. The `jacoco.skip` property resolves per project
for the same reason: one subproject skipping its own agent leaves its siblings
producing data as before.

A plugin-level `<skip>` element steps `auto` aside even where an execution
sets `<skip>false</skip>` and the agent duly writes. The report this action
runs after the reactor lands in a `default-cli` execution, which inherits the
plugin-level configuration and none of the executions, so that skip silences
the report: it exits zero having written no XML, which reaches Sonar as a
coverage figure of zero. An element beats a `-D`, so nothing on the command
line lifts it. Write the skip as a `jacoco.skip` property instead, and the
report pass passes `-Djacoco.skip=false` to lift it for its own run.

Each of these step-asides belongs to `auto`, which is inferring. An explicit
`shared` or `project` is the caller stating what their build does, so those
keep the behaviour they name; `shared` warns where the combination looks unsafe
rather than overriding the request.

In `project` mode the execution data belongs to the caller, so this action
leaves whatever it finds in place: a workflow may be accumulating across two
invocations on purpose. Where that file already existed before the build, the
agents append this run's records to the earlier run's, and the report covers
both. Timestamps cannot see inside the file, so the report pass warns instead.
Remove the file before the build, or use `jacoco-mode: shared`, which clears
its own file first, to report on one run alone.

The report pass carries the same profiles, `global-settings`, `mvn-opts` and
`mvn-params` the build ran with, so it resolves against the same repository and
the same set of subprojects. A report pass without them can fail to download the
plugin on a restricted build that succeeded moments earlier, or report on a
different reactor than the one that ran.

The report runs as a second Maven invocation once the reactor finishes. The
report bound inside the build runs as each subproject reaches its own report
phase, when the later subprojects have yet to run a test.

Sonar reads `**/target/site/jacoco/jacoco.xml` by default, which is where the
report lands under stock settings. `jacoco:report` honours the project's own
`outputDirectory` and `formats`, so the `coverage_report_paths` output lists the
XML the pass wrote rather than the place it tends to appear. It stays empty,
with a warning, when the pass wrote no XML at all.

The report pass names the plugin as `org.jacoco:jacoco-maven-plugin:report`,
with no version. Maven takes the version from the project's own
pluginManagement, so the report comes from the same JaCoCo that wrote the
execution data. Naming the plugin in full also means the pass works against an
aggregator POM that declares no JaCoCo plugin of its own, where the short
`jacoco:report` prefix would fail to resolve.

The probe reads both `jacoco.destFile` and `jacoco.dataFile`, under the same
profiles the build runs with, and keeps the two names apart: `-D` outranks the
POM property of the same name and no other. A caller who passes
`jacoco.dataFile` leaves a POM `jacoco.destFile` in charge of where the agent
writes, so the report pass is not scheduled against a path nothing writes. It
reads `.mvn/maven.config` the way Maven does, walking up from the directory of
the POM named by `mvn-pom-file` and taking the first one it meets, so a config
in an ancestor directory counts. The scan follows Maven's own order of
precedence — `.mvn/maven.config`, then `MAVEN_ARGS`, then the arguments this
action passes — and lands on the value Maven uses. A probe
that fails rather than answers counts as the project owning the layout, since
moving the agent output of a project whose configuration went unread is the one
outcome that turns working coverage into none.

The report pass also feeds its CSV reports to the badge generator. A reactor
root is packaging `pom` and writes no `target/site/jacoco/jacoco.csv`, so the
default would leave `coverage`, `branch_coverage` and the badges empty beside
sound subproject reports. Those paths are workspace-relative, unlike
`coverage_report_paths`: the badge generator runs as a Docker action with the
workspace mounted at `/github/workspace`, where a runner-absolute path names
nothing.

`shared` mode removes the aggregate file before the build. The agents append, so
a file left from an earlier run in the same workspace, or from a build without
`clean`, would otherwise merge stale coverage into this one. In `project` mode
the file belongs to the caller and this action does not remove it, so execution
data older than the build counts as absent rather than as coverage.

In `shared` mode, a build that ran tests and wrote no execution data fails.
"Ran tests" means test output newer than a marker this action writes before the
build, so report directories left by an earlier run in the same workspace do not
count. That
combination means the agent never reached the file the report reads,
which reaches Sonar as a coverage figure of zero. A build that ran no test at
all — `-DskipTests`, say — writes no execution data by design, and passes with a
note. Surefire and Failsafe report directories both count as evidence that tests
ran.

## Implementation Details

This action performs the following steps:

1. **Setup Java**: Configures the specified JDK version and distribution using `actions/setup-java`
2. **Setup Maven**: Installs the specified Maven version using `s4u/setup-maven-action`
3. **Export Environment Variables**: Exports GitHub variables as environment
   variables using `infovista-opensource/vars-to-env-action`
4. **Export Environment Secrets**: Exports GitHub secrets as environment
   variables using `infovista-opensource/vars-to-env-action`
5. **Build with Maven**: Executes the Maven build with the specified phases,
   options, and parameters
6. **Generate JaCoCo Badge**: Creates coverage badges and summary (if JaCoCo
   runs and not executing locally)
7. **Generate build summary and outputs**: Publishes action outputs (m2repo
   path, artifact count, coverage) and writes a `GITHUB_STEP_SUMMARY` table
8. **Upload build artifacts**: Uploads the JaCoCo badges as a workflow
   artifact (when `artifact-upload` enabled)

The action uses pinned SHA versions for all external actions to ensure security
and reproducibility.

## Notes

- The action automatically configures Maven to use a local repository at
  `/tmp/r` and deploys artifacts to `${GITHUB_WORKSPACE}/m2repo`
- JaCoCo badge generation skips during local testing (when `ACT` environment
  variable exists)
- Coverage badges generate in the `badges` directory if JaCoCo runs
- The global settings file (if provided) must contain your Maven repository
  configuration
