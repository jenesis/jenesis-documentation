---
order: 10
title: Code quality & testing
description: The linters, the compiler plugin, formatters, recipes, coverage, profiling, test selection, mutation testing and API-compatibility checks Jenesis runs for you - each turned on by its file in a configuration folder, with no build script.
---

A healthy codebase runs more than a compiler over its sources. Jenesis wires in the usual quality tools
(static analysis, formatters, coverage, profiling, mutation testing) and a faster inner test loop. Each tool
turns itself on when a configuration folder holds its file, and stays off when none does. A tool the build
downloads is an official plugin, which the build resolves by itself wherever it finds that file: no line of
`jenesis.plugins.properties` names it. This chapter is the set of tools and how each one behaves.

Every file below lives in a **configuration folder** (`build.jenesis/` by default). *[Configuration](/tool/configuration/)* covers
where those folders sit and how per-module and profile overrides work; here we only care about which file
switches on which tool.

## Static analysis

Each linter is switched on by a properties file named after it, such as `checkstyle.properties`. The file names
the tool's own configuration as `configuration=<path>`, resolved against the folder of the properties file, and
the build hands that file to the tool under the name the tool reads, whatever it is called. The other lines of
the file are the plugin's values:

```properties
# build.jenesis/checkstyle.properties
configuration=checkstyle.xml
checkstyle.severity=warning
```

Where no configuration folder holds the properties, the tool's own file under its conventional name switches
the tool on alone and is handed to it as it stands, as a `pmd.xml` in `build.jenesis/` runs PMD. A file at the
project root never switches a tool on.

| Properties file | Or, alone | Tool | Inspects |
| --- | --- | --- | --- |
| `checkstyle.properties` | `checkstyle.xml` | Checkstyle | Java sources |
| `pmd.properties` | `pmd.xml` | PMD | Java sources |
| `detekt.properties` | `detekt.yml` | detekt | Kotlin sources |
| `ktlint.properties` | `.editorconfig` | ktlint | Kotlin sources |
| `scalastyle.properties` | `scalastyle-config.xml` | Scalastyle | Scala sources |
| `scalafmt.properties` | `.scalafmt.conf` | scalafmt, as a check | Scala sources |
| `codenarc.properties` | `codenarc.xml` | CodeNarc | Groovy sources |
| `spotbugs.properties` | `spotbugs-exclude.xml` | SpotBugs | compiled classes |
| `forbiddenapis.properties` | | forbiddenapis | compiled classes |
| `jdeps.properties` | | the JDK's jdeps | compiled classes |
| `jdeprscan.properties` | | the JDK's jdeprscan | compiled classes |

Where a configuration folder holds the properties, the conventional file is never read in their place.
Properties that leave out `configuration` fail the build, naming the key to add:

```text
.../build.jenesis/checkstyle.properties names no configuration - add configuration=checkstyle.xml, the file relative to checkstyle.properties
```

A `configuration` naming a file that does not exist fails the build as well. SpotBugs runs without a filter, so
a `spotbugs.properties` may leave `configuration` out and report every finding.

Every check runs in its module's `verify` phase, once the module is built: the modules that depend on it build
and run their tests without waiting for its checks, and a failed check still fails the build. Each downloaded
tool resolves in the tool group of its plugin, such as `checkstyle:tool`, kept apart from your project's own
dependencies, floats a `RELEASE` version until pinned, and runs in a JVM of its own. A tool whose language is
not present skips itself: detekt in a pure-Java project does nothing.

### Reporting or failing on findings

A linter **reports** by default: it runs and records its findings, but never fails the build. That makes it
safe to turn a tool on across an existing codebase without an immediate red build. A linter that found
something says so in one line, with the number of findings and where its report is:

```text
[FINDINGS]  checkstyle found 2 findings, reported in target/build/.../reports/checkstyle/checkstyle-report.xml
```

`-Djenesis.print.findings=false` leaves that line out. To fail the build on a linter's findings, set its
`jenesis.strict.<tool>` to `true`, on the command line or in `jenesis.properties`, as
`-Djenesis.strict.checkstyle=true`. The setting exists for `checkstyle`, `pmd`, `detekt`, `ktlint`,
`scalastyle`, `scalafmt`, `codenarc`, `spotbugs`, `forbiddenapis`, `jdeps` and `jdeprscan`. Like every boolean
setting, it is `true` when named with no value, and any value other than `true` or `false` is refused.

Under a strict setting, Checkstyle, PMD, detekt, ktlint, Scalastyle and scalafmt fail as their own exit code
decides, so a Checkstyle finding at severity `warning` is reported but does not fail the build. SpotBugs,
CodeNarc, forbiddenapis, jdeps and jdeprscan fail on any finding their report holds.

Reporting covers findings, not a tool that never ran. A linter that fails on its own configuration, and so
writes no complete report, fails its step either way.

### Checkstyle and PMD

Checkstyle reads `${config_loc}` as the folder of its configuration, as the Maven and Gradle plugins define it.
A file the configuration names as `${config_loc}/<path>` beside or below it, such as a suppressions file, is
handed to Checkstyle along with the configuration, and changing that file runs the check again. A path that
leaves the folder fails the build.

Every other `${<property>}` the configuration names is a line of `checkstyle.properties`, which takes the place
of the Maven plugin's `propertyExpansion` and Gradle's `configProperties`. Without the line, Checkstyle fails to
load the configuration. `config_loc` is the one property the file cannot set. In the example above,
`checkstyle.xml` reads its severity as `<property name="severity" value="${checkstyle.severity}"/>`.

`configuration` may name a file outside the project, so that several projects share one configuration, and
Checkstyle still reads it as `checkstyle.xml`:

```properties
# build.jenesis/checkstyle.properties
configuration=../../shared/company.xml
```

A jar of custom checks or filters, a dependency of the Checkstyle plugin in Maven, joins Checkstyle's class path
when `@jenesis.plugin checkstyle:tool maven/<groupId>/<artifactId>` names it in `module-info.java`, or
`<!--jenesis.plugin checkstyle:tool maven/<groupId>/<artifactId>-->` in a `pom.xml`.

PMD runs the rules of every priority in its rule set. `jenesis.pmd.priority` names the lowest priority it
runs, from `1`, the highest, to `5`, the default, as the Maven plugin's `minimumPriority` does; any other
value is refused.

### Switching a tool off

A tool found by its file can be switched off without deleting the file. Every such setting is a boolean,
`true` by default, and `false` leaves the tool out. It is named after the part of the build the tool runs in:

| Setting | Covers |
| --- | --- |
| `jenesis.check.<tool>` | `checkstyle`, `pmd`, `detekt`, `ktlint`, `scalastyle`, `scalafmt`, `codenarc` |
| `jenesis.validate.<tool>` | `spotbugs`, `forbiddenapis`, `jdeps`, `jdeprscan` |

For example, `-Djenesis.check.checkstyle=false` keeps `checkstyle.properties` in place but skips Checkstyle,
while PMD and SpotBugs still run. Every other tool that a file of this chapter switches on has a setting of the
same kind, which its section names. A plugin of the project's own, which `jenesis.plugins.properties` names, is switched off by
`-Djenesis.plugin.<name>=false` instead, so it shares no setting with an official plugin, whatever it is named.

### Forbidden API calls

[forbiddenapis](https://github.com/policeman-tools/forbidden-apis) finds calls that the compiled classes, the
tests' included, should not make: a method that depends on the default locale, a deprecated API, a JDK internal
or a call the project rules out. A `forbiddenapis.properties` switches it on and names the signatures to check:

```properties
# build.jenesis/forbiddenapis.properties
bundled=jdk-unsafe,jdk-deprecated,jdk-non-portable,jdk-system-out
signatures=forbidden-signatures.txt
```

`bundled` names signatures that forbiddenapis ships. `jdk-unsafe`, `jdk-deprecated` and `jdk-internal` are
written for one Java release, as `jdk-unsafe-25`, and the build appends the release the classes are compiled
for where the name leaves it out. `signatures` names files of the project's own signatures, relative to
`forbiddenapis.properties`, in the format forbiddenapis reads:

```text
@defaultMessage Name a thread: an unnamed one is hard to tell apart in a thread dump
java.lang.Thread#<init>(java.lang.Runnable)
```

| Key | Maven plugin parameter | Meaning |
| --- | --- | --- |
| `bundled` | `bundledSignatures` | bundled signatures, comma-separated |
| `signatures` | `signaturesFiles` | the project's own signature files, comma-separated |
| `suppress` | `suppressAnnotations` | annotations that silence a finding, as `**.SuppressForbidden` |
| `includes`, `excludes` | `includes`, `excludes` | patterns of the class files to check |
| `warn` | `signaturesWithSeverityWarn` | signatures reported as a warning rather than a finding |
| `allowmissingclasses` | `failOnMissingClasses=false` | `true` lets a class missing from the class path pass |
| `ignoresignaturesofmissingclasses` | `ignoreSignaturesOfMissingClasses` | `true` skips a signature whose class is missing |

At least one of `bundled` and `signatures` is required. Any other key fails the build, and so does a file named
under `signatures` that does not exist. The report, `reports/forbiddenapis/forbiddenapis.txt`, holds one line per
finding: the call, the reason and where it was made.

### JDK internals and removals

Two tools that ship with the JDK check what the compiled classes, the tests' included, ask of the JDK. They
resolve nothing, and each is switched on by its own file, which may be empty.

A `jdeps.properties` runs `jdeps --jdk-internals`. It reports every JDK internal API a class uses, with the
replacement jdeps suggests:

```text
sample.Legacy -> sun.misc.Unsafe: JDK internal API (jdk.unsupported), instead: See https://openjdk.org/jeps/260
```

Its one key, `accept`, names internal classes or packages that a project uses on purpose, as `accept=sun.misc`,
and these are then no finding. A multi-release dependency is read as the JDK running the build would load it.

A `jdeprscan.properties` runs `jdeprscan --for-removal`. It reports every use of an API that the JDK has
scheduled for removal:

```text
sample/Legacy uses deprecated method java/lang/Thread::stop()V (forRemoval=true)
```

`removal=false` reports every deprecated API instead, and `release=<n>` checks the deprecations of that Java
release. A class whose dependencies are not on the module's compile class path fails the check, naming them,
rather than going unscanned.

Both use the tool of the JDK the build runs on. Running a build on a newer JDK, as
`-Djenesis.toolchain.version=<n>` does, therefore shows what that JDK has encapsulated or scheduled for
removal before the code runs on it. Their reports are `reports/jdeps/jdeps.txt` and
`reports/jdeprscan/jdeprscan.txt`, one finding per line.

{% demos 37, 47, 51, 53 %}

## Analysis inside the compiler

The linters above read sources or classes beside the compiler. [Error Prone](https://errorprone.info) reads
neither: it is a `javac` plugin, so it sees the same typed syntax tree the compiler built and reports through
the compiler's own diagnostics. That is how it catches a mistake the compiler accepts, such as comparing two
strings with `==`.

Because it is a compiler plugin rather than a tool of its own, it is declared where compiler plugins are
declared - on the module, with the tag that also declares an annotation processor:

```java
/**
 * @jenesis.plugin javac maven/com.google.errorprone/error_prone_core
 */
module demo.errorprone {
    exports demo.errorprone;
}
```

`@jenesis.plugin <compiler> <coordinate>` resolves into the `plugin` scope of that compiler's own group, the
same shape a Kotlin compiler plugin uses, and `javac` reads that group into its processor path. An Error
Prone plugin such as NullAway is another line of exactly the same form. A coordinate written without a
version, as here, takes the newest release until `pin` records one.

What turns the plugin on are `javac`'s own options, in a `process-javac.properties` of the configuration
folder like any other compiler option. Each key is one option, so the `=`, `:` and space inside one are escaped:

```properties
# build.jenesis/process-javac.properties
-XDcompilePolicy\=simple
--should-stop\=ifError\=FLOW
-J--add-exports\=jdk.compiler/com.sun.tools.javac.api\=ALL-UNNAMED
-J--add-exports\=jdk.compiler/com.sun.tools.javac.file\=ALL-UNNAMED
-J--add-exports\=jdk.compiler/com.sun.tools.javac.main\=ALL-UNNAMED
-J--add-exports\=jdk.compiler/com.sun.tools.javac.model\=ALL-UNNAMED
-J--add-exports\=jdk.compiler/com.sun.tools.javac.parser\=ALL-UNNAMED
-J--add-exports\=jdk.compiler/com.sun.tools.javac.processing\=ALL-UNNAMED
-J--add-exports\=jdk.compiler/com.sun.tools.javac.tree\=ALL-UNNAMED
-J--add-exports\=jdk.compiler/com.sun.tools.javac.util\=ALL-UNNAMED
-J--add-opens\=jdk.compiler/com.sun.tools.javac.code\=ALL-UNNAMED
-J--add-opens\=jdk.compiler/com.sun.tools.javac.comp\=ALL-UNNAMED
-Xplugin\:ErrorProne\ -Xep\:ReferenceEquality\:ERROR
```

| Option | Why Error Prone needs it |
| --- | --- |
| `-Xplugin:ErrorProne` | Runs the plugin, which `javac` does only when an option names it. What follows the name are Error Prone's own flags: `-Xep:<Check>:OFF\|WARN\|ERROR`, `-XepAllErrorsAsWarnings`, `-XepDisableWarningsInGeneratedCode`. |
| `-XDcompilePolicy=simple` | Has `javac` analyse every class completely before it generates code, so the checks see the analysed code rather than code already partly lowered. |
| `--should-stop=ifError=FLOW` | Keeps `javac` going through its flow analysis after an error, so the plugin reports beside the compiler. |
| `-J--add-exports`, `-J--add-opens` | Grant the plugin the compiler's internal packages, which `jdk.compiler` does not export. They are options of the JVM that runs `javac`, so `javac` runs in a JVM of its own: one per compilation, or, in the daemon or under `jenesis.process.mode=daemon`, one that every compilation with the same options shares, side by side and kept warm. |

`javac` reads the first two when it starts, and the exports must be in place before it does, so neither the plugin
nor an annotation processor can supply them itself. Without the `-Xplugin` line the declared plugin resolves and
sits unused. A `pom.xml` project declares the plugin as a
`<!--jenesis.plugin javac maven/com.google.errorprone/error_prone_core-->` comment, in the module's POM or in a
parent POM in the project.

{% demos 15 %}

## Formatting

Formatters are the rewriting counterpart to the linters: where a linter reads your sources and writes a
report, a formatter reads them and can rewrite them in place. Each formatter is switched on by a properties file
named after it, whose lines are its values; an empty file formats with the defaults:

```properties
# build.jenesis/googlejavaformat.properties
reflow=false
```

A value the formatter does not take fails the build, naming the ones it takes, and a changed value verifies
every source again:

| File | Value | Meaning |
| --- | --- | --- |
| `googlejavaformat.properties` | `style` | `google`, the default, or `aosp` for the Android Open Source Project's four-space style |
| | `reflow` | `false` leaves long strings as they are written |
| | `javadoc` | `false` leaves Javadoc as it is written |
| | `imports` | what happens to the imports: `sort,remove`, the default, `sort`, `remove` or `none` |
| `palantir.properties` | `reflow`, `imports` | as for google-java-format |
| `eclipse.properties` | `configuration` | the formatter profile Eclipse exports, relative to the file; without it, the Eclipse formatter's defaults |
| `ktlint.properties` | `configuration` | the `.editorconfig` that drives ktlint |
| `ktfmt.properties` | `style` | `meta`, the default, `google` or `kotlinlang` |
| | `imports` | `sort` keeps unused imports; `sort,remove`, the default, removes them as well |
| `scalafmt.properties` | `configuration` | the `.scalafmt.conf` that drives scalafmt |

Where no configuration folder holds an `eclipse.properties`, an `eclipse-formatter.xml` in a configuration folder
switches the Eclipse formatter on alone, as its profile. The formatter runs from `org.eclipse.jdt.core` in a plain
JVM, with no Eclipse installation.

ktlint and scalafmt both check and format, and the one file of each, or its conventional `.editorconfig` or
`.scalafmt.conf`, switches on both. They are switched off apart: `jenesis.check.ktlint=false` leaves out the
linting and `jenesis.format.ktlint=false` the formatting, and the same holds for scalafmt.

Two formatters would fight over the same sources. A build that finds the files of two Java formatters fails,
naming them, and so does a `ktfmt.properties` beside a ktlint that formats the same Kotlin sources. A profile that
brings in one formatter therefore switches the other off in its `jenesis-<profile>.properties`, as
`jenesis.format.googlejavaformat=false` or `jenesis.format.ktlint=false`. Each formatter has its setting of
`jenesis.format.<tool>`: `googlejavaformat`, `palantir`, `eclipse`, `ktlint`, `ktfmt` and `scalafmt`.

### Verify mode, and how to reformat

Every formatter runs in **verify mode** by default, so a normal build never touches your sources. Instead it
**fails the build when a file is not already formatted**, which makes it a continuous-integration gate. Indent
a source file with a few spare spaces and rebuild: the `format` step fails.

To apply the formatter and rewrite your sources in place, run the build with the rewrite switch:

```bash
java -Djenesis.format.rewrite=true build/jenesis/Make.java
```

The switch flips every formatter from verifying to rewriting, and the same switch applies OpenRewrite's
recipes and writes the licence headers. After a rewrite, a plain build passes the verify gate again.

<div class="note">
  Groovy has no formatter: no suitable Maven-published formatter exists for it, so a Groovy
  project's <code>codenarc.xml</code> lints but nothing reformats.
</div>

### Rewriting with recipes

[OpenRewrite](https://docs.openrewrite.org) applies recipes to the Java sources: a method renamed, an API
migrated, an unused import removed. Its own file, a `rewrite.yml` in a configuration folder, switches it on and
declares the recipes the project runs:

```yaml
# build.jenesis/rewrite.yml
type: specs.openrewrite.org/v1beta/recipe
name: demo.Modernize
recipeList:
  - org.openrewrite.java.ChangeMethodName:
      methodPattern: java.lang.String trim()
      newMethodName: strip
```

OpenRewrite runs before the Java formatter, so what a recipe writes is formatted afterwards. Like a formatter
it verifies by default: a source a recipe would change fails the build, printing the change as a diff, and
`-Djenesis.format.rewrite=true` applies it.

```text
-    return name.trim();
+    return name.strip();
The recipes demo.Modernize change 1 file - run with -Djenesis.format.rewrite=true to apply them
```

An `openrewrite.properties` takes the place of the file where more is wanted:

| Key | Meaning |
| --- | --- |
| `configuration` | a `rewrite.yml`, relative to `openrewrite.properties`, every recipe of which runs |
| `recipes` | the recipes to run, comma-separated, instead of every recipe of the `rewrite.yml`: recipes of OpenRewrite, of a recipe library the module names, or of the `rewrite.yml` |

At least one of them is required, and any other key is refused. With `recipes` and no `configuration`,
OpenRewrite runs a recipe of its own, as `recipes=org.openrewrite.java.RemoveUnusedImports`.

A recipe of OpenRewrite's own Java module needs nothing more. A recipe library is named for the plugin to load
beside OpenRewrite, as `@jenesis.plugin openrewrite:tool maven/org.openrewrite.recipe/rewrite-static-analysis`
in `module-info.java`, and resolves with it in the group `openrewrite:tool`. The module's dependencies are
OpenRewrite's class path, so a recipe that matches a type of a library the module uses finds it. A recipe that
would add, delete or move a file fails the build, and `-Djenesis.format.openrewrite=false` switches OpenRewrite
off.

### Licence headers

A `licenseheader.properties` in a configuration folder holds, as its `text` key, the header every Java, Kotlin,
Scala and Groovy source of the module starts with, `module-info.java` and `package-info.java` included. A header
written as plain text starts a source as a block comment, and one written as a comment already starts it as it
stands. `\n` separates its lines, and a trailing `\` continues the value on the next line:

```properties
text=Copyright 2026 the original author or authors.\n\n\
  Licensed under the Apache License, Version 2.0.
```

The file takes no other key. The header is taken exactly as it stands, a year included: a source without it, or
with a different one, fails the build, naming the file. The header is checked or written before any formatter
runs. Under
`-Djenesis.format.rewrite=true` the header is inserted as it stands, or replaces a leading comment that names a
copyright or a licence, so a rewrite gives the same sources whenever it runs. Generated sources are not checked,
and `jenesis.format.license=false` switches the check off.

Without `text`, the header is derived from what the project declares: the one licence of its `pom.xml` or its
`project.properties`, named by its SPDX identifier, and its `copyright` where one is declared. An empty
`licenseheader.properties` beside a `project.properties` holding

```properties
license.apache_2_0.name=Apache License, Version 2.0
license.apache_2_0.url=https://www.apache.org/licenses/LICENSE-2.0.txt
copyright=2026 the original author or authors
```

starts every source with these two lines:

```java
// SPDX-FileCopyrightText: 2026 the original author or authors
// SPDX-License-Identifier: Apache-2.0
```

A project that declares no licence, more than one, or one without a known SPDX identifier fails the build, naming
what it found. An `alias/<licence name>=<id>` line in `spdx.properties` gives a licence its identifier.

{% demos 37, 47, 51 %}

## Where the reports land

Every tool writes its findings into a `reports/<kind>/` folder under its step's output, for example
`reports/checkstyle/checkstyle-report.xml`, `reports/pmd/`, `reports/spotbugs/`, `reports/forbiddenapis/`,
`reports/jdeps/`. You rarely need the exact path, because a **`stage` build collects every report from every module into one place**, each kind in its own
subfolder:

```
target/stage/reports/output/<kind>/<module>/
```

So `target/stage/reports/output/checkstyle/sources/checkstyle-report.xml` is the Checkstyle report for the
module under `sources/`, and coverage reports land under `target/stage/reports/output/jacoco/<module>/` the
same way.

## Code coverage

Coverage is a **test observation**: JaCoCo wraps the test run and records which code the tests touched. A
`jacoco.properties` in a configuration folder switches it on, in every test module where the file is found:

```properties
# build.jenesis/jacoco.properties
minimum.method=0.6
```

The project-wide `build.jenesis/` works for every layout; a `pom.xml` project can also scope the file to its tests
with `src/test/build.jenesis/`.

With coverage on, the test step is launched with the JaCoCo agent attached as a `-javaagent`. It
instruments the run without touching your sources and writes its execution data (`jacoco.exec`); a downstream
report step renders an HTML and XML report under `reports/jacoco/`, over the classes of the code under test,
never the compiled tests themselves. Open the `index.html` to browse coverage
line by line. JaCoCo's CLI resolves in the tool group of its plugin, `jacoco:tool`, apart from your
dependencies, and its agent in `jacoco:agent`. The agent writes the data the CLI reads, so it follows the release the tool group
pins for the CLI: a pin of `jacoco:tool/maven/org.jacoco/org.jacoco.cli` alone runs the tests under that
version's agent as well, until `pin` records both.

An empty `jacoco.properties` only reports: a method your tests never reach shows up as uncovered, and the
build stays green. Lines in the file set limits on the module's coverage, as the `check` goal of jacoco-maven-plugin
does for a bundle:

| Key | Limit |
| --- | --- |
| `minimum.<counter>` | the least covered ratio, from 0 to 1, such as `minimum.line=0.8` |
| `maximum.missed.<counter>` | the most items left uncovered, such as `maximum.missed.class=0` |

The counters are JaCoCo's: `instruction`, `branch`, `line`, `complexity`, `method` and `class`. A limit that is not
met fails the build once the report is rendered, naming the limit and what the tests reached:

```text
a covered ratio of 0.9 of methods is not met: 2 of 3 covered, a ratio of 0.6667
```

A counter with nothing to count, such as `branch` in code without a branch, meets every limit. An unknown key, or a
value that is no ratio or count, fails the build naming the valid ones. Set `-Djenesis.observe.jacoco=false` to
suppress coverage even when the file is present.

## Recording the tests with Java Flight Recorder

A `jfr.properties` file in a configuration folder records the test JVM with Java Flight Recorder, which ships
with the JDK, so nothing is resolved. Each line is an option of the recording, as `-XX:StartFlightRecording`
takes it:

```properties
# jfr.properties
settings=profile
maxsize=100m
```

The build names the file itself and writes it into the test step's reports, so it is staged with the others
under `target/stage/reports/output/jfr/<module>/tests.jfr`. Open it in JDK Mission Control or summarise it with
`jfr summary`. A `filename` line is refused, and so is a value holding a comma, which would split the options.

Because the file lives in a configuration folder, a profile switches the recording on for one build:
`build.jenesis/profiling/jfr.properties` records only under `-Djenesis.make.profiles=profiling`. Changing the
file runs the tests again. Set `-Djenesis.observe.jfr=false` to suppress the recording even when the file is
present.

## Profiling the tests with async-profiler

[async-profiler](https://github.com/async-profiler/async-profiler) samples what the test JVM spends its time on.
An `asyncprofiler.properties` in a configuration folder attaches it to the JVM the tests run in, in every test
module where the file is found. Each line is an option of the profiler, as `event=cpu` or `interval=1ms`, or an
option without a value, as `threads`:

```properties
# build.jenesis/profiling/asyncprofiler.properties
event=cpu
interval=1ms
threads
```

The build names the file the profile is written to, so a `file` line is refused, and so is a value holding a
comma. It writes `reports/asyncprofiler/tests.html`, a flame graph to open in a browser, staged under
`target/stage/reports/output/asyncprofiler/<module>/`. An option that selects another format writes
`tests.jfr`, `tests.collapsed`, `tests.txt` or `tests.otlp` instead (`jfr`, `collapsed`, `flat`, `traces`,
`summary`, `otlp`).

The agent, `tools.profiler:async-profiler`, carries the profiler's native library and resolves in the group
`asyncprofiler:agent`; the tests' JVM is granted native access for it. async-profiler ships its library for Linux
on x64 and arm64 and for macOS, and elsewhere the build fails. Kept in a profile folder, as above, the file
profiles only the builds run with `-Djenesis.make.profiles=profiling`, and `-Djenesis.observe.asyncprofiler=false`
switches it off.

{% demos 41 %}

## Narrowing a test run

While you are chasing one failure, running the whole suite each time is noise. Two properties narrow what the
test step executes:

```bash
java -Djenesis.test.filter='calc.*Test#addsTwo' build/jenesis/Make.java
java -Djenesis.test.tag=fast+-slow,io+-slow build/jenesis/Make.java
```

`jenesis.test.filter` takes a comma-separated list of `<classRegex>[#<method>]` entries and runs only what
matches. The expression matches the whole class name and takes the place of the default naming (`*Test`,
`*IT` and the rest), so `.*Check` runs classes that the naming would leave out. It also takes the place of the
naming's JUnit 4 check that a class holds tests, so under JUnit 4 every class it matches runs, a nested helper
included; where the default naming fits, leave classes out with `jenesis.test.exclude` instead, which keeps the
check. `jenesis.test.tag` selects by tag, in a syntax of its own described below.

An entry applies to every test module, and a test module where it matches no test fails the build. In a
project with several test modules, lead the entry with a module's folder and a `/` to keep it to that module's
tests:

```bash
java -Djenesis.test.filter='greeter-test/.*GreeterTest#prefix_is_a_greeting' build/jenesis/Make.java
```

The folder is the one a `+<module>` selector names, and a nested folder such as `libs/core/.*Test` works too.
In a `pom.xml` project it is the folder of the module's `pom.xml` relative to the root, so the root module's
entry is written `/<classRegex>`, with nothing before the slash.
A test module that no entry reaches runs no tests rather than failing, while one an entry does reach still
fails when nothing there matches.

`jenesis.test.exclude` leaves classes out instead. It takes the same entries without a `#<method>`, and the
default naming or the filter stays in force for everything else:

```bash
java -Djenesis.test.exclude='.*IntegrationTest' build/jenesis/Make.java
```

A test module whose every selected class is left out runs no tests.

### Selecting tests by tag

The tag selection is **framework neutral**: it is written the same way whatever the tests run on, and Jenesis
translates it into the framework's own mechanism, so a selection keeps working when a project moves from one
framework to another and nobody has to learn JUnit's tag expressions or TestNG's group lists. It is also **built
for the command line**: it uses three characters that no shell interprets - no `!`, `&`, `|`, parentheses or
spaces - so a selection is typed as it stands, never quoted, and reads the same in bash, zsh and a CI step.

| Write | Means |
|-------|-------|
| `,` | or: separates alternatives, and a test runs where it matches any of them |
| `+` | and: joins tags within an alternative, for the tests carrying all of them |
| `-` before a tag | not: the tests that do not carry that tag |

| Selection | Runs |
|-----------|------|
| `fast` | the tests tagged `fast` |
| `fast,io` | the tests tagged `fast` or `io` |
| `fast+io` | the tests tagged both `fast` and `io` |
| `-slow` | every test that is not tagged `slow` |
| `fast+-slow,io+-slow` | the tests tagged `fast` or `io` that are not tagged `slow` |
| `-container+-soak` | the tests tagged neither `container` nor `soak` |
| `-container,-soak` | every test that is not tagged both `container` and `soak` |
| `release,-container` | the tests tagged `release`, and every test that is not tagged `container` |

Every selection a tag expression can make can be written this way, as alternatives each joining tags and negated
tags. A hyphen inside a tag, as in `slow-io`, is part of its name; `-` negates only at the start of one. A selection
that uses anything else, or an alternative that asks for a tag and its negation at once, fails the build with the
form spelt out.

Jenesis translates the selection for the framework that runs the tests:

| Framework | A tag is | Translated into | Selections it can run |
|-----------|----------|-----------------|-----------------------|
| JUnit Platform | a `@Tag` value | one `--include-tag` expression | every selection |
| TestNG | a group | `-groups` and `-excludegroups` | alternatives of at most one group each, all leaving out the same groups |
| JUnit 4 | a `@Category` class, named in full as `com.example.Slow` | an `IncludeCategories` filter per tag and one `ExcludeCategories` filter | one alternative of any tags, or alternatives of at most one category each, all leaving out the same categories |

The framework is found for each module from the tests' own dependencies, so a project whose modules test with
different frameworks is selected with one expression: `-Djenesis.test.tag=slow` runs the tests tagged `slow` in a
JUnit Platform module and the group `slow` in a TestNG module alike. Under JUnit 4 a tag is a class name, and JUnit
fails the run when the class does not exist or when the selection matches no test of the module. A selection a framework cannot
run fails the build with the form it would accept. A framework plugged in through the `TestFramework` interface
translates the selection in its own `tags` method, and one that does not implement it refuses any selection. A
project declares such a framework as a plugin of the hook point `test` (see
*[Extending the build](/tool/extending-the-build/#running-the-tests-on-a-framework-of-your-own)*), and the frameworks it
declares are consulted before the built-in ones.

A narrowed run is still the same step, so its result is remembered together with **what it covered**, and every
later run adds to that memory until the tests or what they test change. A request runs only what no remembered
run covered: after `fast`, asking for `fast,io` runs the tests tagged `io` that are not tagged `fast`, asking for
`fast` again runs nothing, a run of `fast` covers a request for `fast+io`, and a run of every test covers any
request. A run that left tests out covers only an alternative that leaves them out too. The filter and the exclusion are compared as they are written, so a different
one runs the tests again and starts a new memory.

<div class="tip">
  To run the tests when nothing at all has changed - a flaky test, a debugging session - pass
  <code>-Djenesis.test.force=true</code>. It forgets what earlier runs covered and runs the whole selection. Narrowing belongs on a
  developer machine, though: a build that populates a
  <a href="/tool/build-performance-and-isolation/">shared cache</a> should run the full suite, or a narrowed
  result can be served to someone asking for more.
</div>

{% demos 3, 4, 38 %}

## Running only the tests a change affects

Jenesis already skips a module's whole test step when none of that module's inputs changed. **Test selection**
is the finer-grained companion: within a module that *did* change, it runs only the test classes the change
can reach and leaves the rest cached. Turn it on with `-Djenesis.test.mode=incremental`:

```bash
java -Djenesis.project.watch=true -Djenesis.test.mode=incremental build/jenesis/Make.java
```

`jenesis.test.mode` takes five values:

| Value | What runs |
|---|---|
| `alphabetic` (default) | Every test, the classes handed to the runner in order of their names. |
| `incremental` | Only the tests a change reaches. |
| `prioritized` | Every test, the ones a change reaches handed to the runner first and the rest after them. |
| `failed` | Only the classes that failed in the run before. |
| `failedfirst` | Every test, the classes that failed in the run before handed to the runner first and the rest after them. |

Any other value fails the build with the valid ones listed. The JUnit Platform runs the classes in the order
it is handed them, so under `prioritized` the results of the tests a change reaches appear before the rest
has run. A filter, an exclusion and a tag selection each switch `incremental` off, so such a run runs every
test it selects; `prioritized` and `failedfirst` still hand their classes over first.

`failed` and `failedfirst` turn on the reports of `jenesis.test.reporting` and read from them which test
methods failed, for the JUnit Platform and TestNG. They keep them for the module's next run, a failed run
included, as long as the module's test configuration is unchanged, and rerun whole classes. Where nothing
failed or nothing is recorded, both run every test. JUnit 4 writes no report they read, so under JUnit 4 both
run every test in order of their names.

On each run the test step builds a class-to-test dependency graph from the compiled bytecode and records a
per-class content hash. On the next run it diffs the hashes, takes the classes whose bytecode changed and
walks the graph to the tests that reach them. A change that reaches no test runs nothing under `incremental`,
and a run with no earlier record, or a non-class change (a resource, a dependency), runs every test in order
of their names.

Test selection is meant mainly for **watching** a project (see *[Building & running](/tool/building-and-running/)*), where the build re-runs
on every save and a narrowed test pass keeps the feedback loop tight.

<div class="warning">
  Test selection is a development-loop optimisation, <strong>not a correctness gate</strong>. Static selection
  cannot see reflection, resources or other indirect couplings, so continuous integration should keep running
  the whole suite - a plain <code>build</code>, or <code>prioritized</code> or <code>failedfirst</code>, which run
  every test.
</div>

{% demos 39 %}

## Mutation testing

Coverage tells you which lines a test *executed*; mutation testing tells you which behaviours a test actually
*checks*. [PIT](https://pitest.org) (`pitest`) seeds small faults into your code (a `+` becomes a `-`, a
return value is replaced with a constant), re-runs the tests against each mutant, and reports which mutants
the tests **killed** and which **survived**. A surviving mutant is a change to the program that no test
noticed.

A `pitest.properties` in a configuration folder switches PIT on, in every test module where the file is found:
the suite runs as usual *and* PIT then re-runs it against mutants of the code under test, to assess how good it
is. The file carries the options PIT needs:

```properties
# build.jenesis/pitest.properties
targetClasses=calc.Calculator   # which classes to mutate
targetTests=calctest.*          # which tests to run against the mutants
outputFormats=XML,HTML          # report formats (an optional `mutators` key selects a mutator set)
```

| Key | Meaning | Default |
| --- | --- | --- |
| `targetClasses` | globs of the classes to mutate | `*` |
| `targetTests` | globs of the tests to run against the mutants | `*` |
| `outputFormats` | the report formats, of `XML`, `HTML` and `CSV` | `XML` |
| `mutators` | the mutators or mutator groups PIT applies | PIT's own default |
| `failWhenNoMutations` | fail when PIT finds nothing to mutate | `false` |

An unknown key, or a format that is not one of the three, fails the build naming the ones that exist.

PIT and its JUnit 5 plugin resolve in the tool group of the PIT plugin, `pitest:tool`, apart from your
dependencies. PIT runs the tests with the JUnit Platform launcher of the version the test module pins or
resolved, so it lines up with the test framework you use. The report lands under `reports/pitest/`, and
`-Djenesis.observe.pitest=false` suppresses the run while keeping the file in place.

{% demos 42 %}

## API compatibility

Coverage and mutation testing ask whether your tests are any good. **API compatibility** asks whether the jar
you are about to publish still works for everyone who compiled against the last one.
[japicmp](https://siom79.github.io/japicmp/) answers by comparing byte code, which is the level that matters:
a caller linked against class files, so a removed method, a narrowed return type or a tightened modifier is
what breaks them.

A `japicmp.properties` in a configuration folder switches japicmp on, in every module but a test module where
the file is found. The file may be empty. Then japicmp compares the module's fresh jar
against the last release of **that module's own coordinate**, so the check follows your releases rather than
being re-pointed by hand. A `baseline` key names another artifact, read by how many slashes it carries:

```properties
baseline=com.example/library                           # the latest release
baseline=com.example/library/1.2.3                     # that version
baseline=<repository>/com.example/library/1.2.3       # that version, from the repository of that name
```

A module with no Maven coordinate has nothing to default to and says so. The file is read per module, so a
project-wide `japicmp.properties` without a `baseline` gives every module its own coordinate - a `baseline`
there would point them all at one artifact, so a per-module baseline belongs in that module's own
configuration folder. A test module, such as the tests of a `pom.xml` project, has no release of its own and is
never compared.

The remaining keys map onto japicmp's own options:

| Key | Effect | Default |
| --- | --- | --- |
| `access` | lowest visibility to compare (`public`, `protected`, `package`, `private`) | japicmp's own |
| `include` / `exclude` | comma-separated package or class filters | none |
| `format` | `xml`, `html`, or both | `xml` |
| `ignore-missing-classes` | tolerate types the baseline's own dependencies would have provided | `true` |
| `only-incompatible` / `only-modified` | narrow what the report lists | `false` |
| `semantic-versioning` | report the version increment the changes call for | `false` |
| `error-on-binary-incompatibility` | fail the build on a binary-incompatible change | `false` |
| `error-on-source-incompatibility` | fail the build on a source-incompatible change | `false` |
| `error-on-modifications` | fail the build on any change at all | `false` |
| `error-on-semantic-incompatibility` | fail the build on a semantic-versioning violation | `false` |

An unknown key fails the build and lists the ones that exist.

Like the linters, the check only **reports** by default: it writes `reports/japicmp/japicmp-report.xml` and
keeps the build green, so you see what changed before you decide to enforce it. Turning on a gate makes the
failure name the change that caused it:

```text
E: There is at least one incompatibility: library.Library.farewell(java.lang.String):METHOD_REMOVED
```

japicmp and the baseline artifact resolve in the tool group of the japicmp plugin, `japicmp:tool`, kept apart from the module's own
dependencies; the baseline resolves **without** its transitive dependencies, because only its own byte code
is compared. It is a released artifact like any other, so `pin` records it with a checksum alongside the
tool - one line, not a closure. The plugin resolves both with the project's repositories.
`-Djenesis.artifact.japicmp=false` suppresses the comparison while keeping the file in place.

### revapi beside japicmp

[revapi](https://revapi.org) compares the same two jars and classifies every difference by how severe it is for
a caller, binary and source alike. A `revapi.properties` switches it on, in every module but a test module where
the file is found, and revapi compares against the same baseline: its `baseline` key reads exactly as japicmp's, and without one it is the last release of the
module's own coordinate.

```properties
# build.jenesis/revapi.properties
severity=non-breaking
configuration=revapi.json
```

| Key | Effect | Default |
| --- | --- | --- |
| `baseline` | the artifact to compare against, as for japicmp | the module's own last release |
| `severity` | the least severe difference reported: `equivalent`, `non-breaking`, `potentially-breaking` or `breaking` | `potentially-breaking` |
| `configuration` | a JSON file holding revapi's own configuration, relative to `revapi.properties` | none |

That file is revapi's own, an array of `{"extension": ..., "configuration": ...}` objects, so the
differences a release accepts stay in revapi's notation, as a `revapi.differences` list:

```json
[{"extension": "revapi.differences", "configuration": {"ignore": true, "differences": [
    {"code": "java.method.removed", "old": "method java.lang.String library.Library::farewell(java.lang.String)",
     "justification": "Deprecated for two releases."}]}}]
```

Any other key fails the build, as does a `configuration` naming a file that is no JSON array. revapi reports like
a linter: `reports/revapi/revapi.json` holds one entry per difference, with its code and classification, and a
`[FINDINGS]` line counts them.

The build stays green on those findings unless `-Djenesis.strict.revapi=true` fails it on any difference
reported, and `-Djenesis.artifact.revapi=false` skips revapi. It resolves in the tool group of its plugin,
`revapi:tool`, with `revapi-java`, `revapi-basic-features` and `revapi-reporter-json` and what they depend on,
beside the baseline.

{% demos 45 %}

## Seeing every failure at once

A multi-module build fans out: each module's tests are their own branch of the graph, and those branches run
concurrently. By default the run reports the **first** failure and stops there, which is what you want when one
broken module means the rest is moot. When you would rather see the whole picture (a CI run, or a change that
touches every module), let the failures aggregate:

```bash
java -Djenesis.executor.aggregate=true build/jenesis/Make.java
```

Every independent branch then runs to completion and the build fails once, reporting every module that broke
rather than stopping at the first. A step whose input failed is still skipped either way: only *independent*
failures aggregate.

## Pinning the tool chain

Every tool above that the build downloads floats a `RELEASE` version in the tool group of its plugin until you
pin it, so a first build downloads the latest and later builds reuse the cache; a plugin's own jars are pinned
apart, in the group of its name. jdeps, jdeprscan, Java Flight Recorder and the licence header check resolve
nothing. For a reproducible, checksum-verified tool chain, run
`java build/jenesis/Make.java pin`: it records each resolved tool jar with its SHA-256 exactly as it pins
your compilers and dependencies (see *[Pinning & bills of materials](/tool/pinning/)*). Expect a long list -
a linter's own closure can run to a hundred artifacts - which is what makes the tool chain reproducible. A
tool that only a profile turns on is pinned by running `pin` with that profile active.
