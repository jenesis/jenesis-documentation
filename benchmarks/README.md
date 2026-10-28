# Benchmarks

The build times under *Builds an agent has moved* on [jenesis.build/why/tool/](https://jenesis.build/why/tool/#migrations)
come from these folders, one per project: `migration.patch` is the agent's migration of that project, and `run.sh`
measures it against the project's own build.

```
benchmarks/gson/run.sh
ROUNDS=1 benchmarks/mockito/run.sh
PAIRINGS=daemon benchmarks/junit-framework/run.sh
```

A run clones the project at the commit the migration started from into a temporary folder, applies the patch and
installs Jenesis into it with https://get.jenesis.build. The original build runs in a second worktree of the same
commit, so neither tool reads what the other wrote. Each tool gets one unmeasured warm-up build, then three rounds
of:

- a full build from scratch - Jenesis after `rm -rf target`, Maven with `clean`, Gradle with `clean` and
  `--no-build-cache`;
- the same build again, with nothing changed;
- the build after one method body in a main source file was edited, a module others depend on. Each edit names a
  variable no earlier build saw, so no build cache holds its result, and it is reverted afterwards.

Each tool runs twice over, without a daemon and with one: Maven as the Maven Daemon, `mvnd`, Gradle with `--daemon`
and Jenesis under `jenesis.make.mode=daemon`. The warm-up starts the daemons, so every measured build of that pairing
runs against a warm one, and they are stopped once it is done. `mvnd` builds as it does by default, the modules of a
project side by side.

A parallel reactor orders modules only by the dependencies they declare, so a build that works with `mvn` can fail
with `mvnd`. AssertJ does: its Spring Boot integration tests reach `assertj-core` only through Spring Boot's test
starter, and `mvnd` started them before `assertj-core` was packaged. Its migration patch declares the dependency so
that `mvnd` builds the project at all; `mvn` and Jenesis resolve the same dependency without it.

Downloaded dependencies stay where each tool keeps them (`~/.m2`, `~/.gradle`, `~/.jenesis`), as on a developer's
machine. Neither build reads a remote build cache, and Jenesis runs with `-Djenesis.make.global=`, so the
`~/.jenesis/jenesis.properties` of the machine cannot replace what the migration declares. The script prints the median of each measurement and leaves every
run in `results.tsv` and every build's output in `logs/` of its temporary folder; the clone itself is removed.

The numbers say most where nothing else runs on the machine. The published ones were measured on four cores and
15 GB, one project at a time.

## What it needs

- a JDK 25 or newer as `java`, `git`, `curl` and `python3`;
- Maven 3.9 as `mvn` and the Maven Daemon 1.x as `mvnd` for the Maven projects; the Gradle projects bring their
  wrapper;
- about 5 GB of free disk for Guava, less for the others.

## Settings

| Variable | Default | Effect |
|---|---|---|
| `JENESIS_REF` | the commit the published numbers used | the Jenesis commit, tag or branch to install |
| `ROUNDS` | 3; 1 for Guava | rounds per tool |
| `PAIRINGS` | `nodaemon daemon` | `daemon` runs Maven as `mvnd`, Gradle with `--daemon` and Jenesis under `jenesis.make.mode=daemon` |
| `MAVEN_MIRROR` | none | a Maven Central mirror for all three tools, where repo.maven.apache.org is rate-limited |
| `BENCHMARK_FOLDER` | a new temporary folder | where to clone, log and record |

## The projects

| Folder | Project | Built with | Jenesis builds from |
|---|---|---|---|
| `guava` | Guava | Maven | `pom.xml` |
| `junit-framework` | JUnit 5 | Gradle | `pom.xml` |
| `mockito` | Mockito | Gradle | `pom.xml` |
| `assertj` | AssertJ | Maven | `pom.xml` |
| `auto` | Google Auto | Maven | `pom.xml` |
| `jackson-databind` | Jackson Databind | Maven | `module-info.java` |
| `gson` | Gson | Maven | `pom.xml` |
| `jsoup` | jsoup | Maven | `pom.xml` |

Each `run.sh` names the commands of both builds and what one leaves out that the other runs.
