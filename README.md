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

<!-- markdownlint-disable MD013 -->

| Name            | Description                                                                                         |
| --------------- | --------------------------------------------------------------------------------------------------- |
| m2repo_path     | Absolute path to the Maven file deployment repository (m2repo) for downstream publish/stage actions |
| m2repo_exists   | Whether the build produced the m2repo directory (`true`/`false`)                                    |
| artifact_count  | Number of jar/pom/war files found in the m2repo                                                     |
| coverage        | JaCoCo line coverage percentage (empty when JaCoCo did not run)                                     |
| branch_coverage | JaCoCo branch coverage percentage (empty when JaCoCo did not run)                                   |
| artifact_name   | Name of the uploaded JaCoCo badges artifact (empty when artifact upload disabled)                   |

<!-- markdownlint-enable MD013 -->

The action also:

- Builds the Java project using Maven
- Generates JaCoCo coverage reports and badges (if enabled)
- Deploys artifacts to the file-based staging repository (`m2repo`)
- Writes a build summary to `GITHUB_STEP_SUMMARY`

Downstream publish/stage actions consume the built `m2repo` via the
`m2repo_path` output; the calling workflow typically uploads it between jobs.

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
