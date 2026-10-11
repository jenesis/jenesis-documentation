---
order: 10
title: Code quality & testing
description: The linters, the compiler plugin, formatters, coverage, test selection, mutation testing and API-compatibility checks Jenesis runs for you - each turned on by dropping its config file in place, no build script and no plugin to register.
---

A healthy codebase runs more than a compiler over its sources. Jenesis wires in the usual quality tools
(static analysis, formatters, coverage, mutation testing) and a faster inner test loop, and it does so the
same way it does everything else: **there is no plugin to register**. A tool turns itself on when its
configuration file is present, and stays off when it is not. This chapter is the set of tools and how each
one behaves.

Every file below lives in a **configuration folder** (`build.jenesis/` by default). *[Configuration](/tool/configuration/)* covers
where those folders sit and how per-module and profile overrides work; here we only care about which file
switches on which tool.

## Static analysis

Drop a tool's conventional configuration file into the configuration folder and the tool runs on the next
build. Nothing else is needed - the file's presence is the switch, and its contents are the tool's own rules.

| File | Tool | Inspects |
| --- | --- | --- |
| `checkstyle.xml` | Checkstyle | source files |
| `pmd.xml` | PMD | source files |
| `spotbugs-exclude.xml` | SpotBugs | compiled classes |
| `detekt.yml` | detekt (Kotlin) | source files |
| `.editorconfig` | ktlint (Kotlin) | source files |
| `scalastyle-config.xml` | Scalastyle | source files |
| `.scalafmt.conf` | scalafmt (as a linter) | source files |
| `codenarc.xml` | CodeNarc (Groovy) | source files |

The source linters run **in parallel with compilation**, since they read sources rather than classes;
SpotBugs runs once the classes exist. Each tool resolves in its own dependency group (named after the tool,
kept apart from your project's own dependencies), floats a `RELEASE` version until pinned, and runs in a
forked JVM. A tool whose language is not present skips itself: a stray `detekt.yml` in a pure-Java
project does nothing.

### Report, strict or ignore

Each linter has one setting that says what its findings do: `jenesis.source.<tool>` for the source linters and
`jenesis.validator.spotbugs` for SpotBugs, set on the command line or in `jenesis.properties`.

| Value | The linter |
| --- | --- |
| `report` *(the default)* | runs and records its findings, but never fails the build |
| `strict` | runs and fails the build on its findings |
| `ignore` | does not run, though its configuration file is in place |

Any other value is refused, naming these three. Reporting by default makes it safe to turn a tool on across an
existing codebase without an immediate red build. A linter that found something says so in one line, with the
number of findings and where its report is:

```text
[FINDINGS]  checkstyle found 2 findings, reported in target/build/.../reports/checkstyle/checkstyle-report.xml
```

`-Djenesis.print.findings=false` leaves that line out, whatever the linter's setting. Under `strict`, as
`-Djenesis.source.checkstyle=strict`, Checkstyle, PMD, detekt, ktlint, Scalastyle and scalafmt fail as their own
exit code decides, so a Checkstyle finding at severity `warning` is reported but does not fail the build.
SpotBugs and CodeNarc fail on any finding their report holds.

Reporting covers findings, not a tool that never ran. A linter that fails on its own configuration, and so
writes no complete report, fails its step either way.

Checkstyle reads `${config_loc}` as the folder of `checkstyle.xml`, as the Maven and Gradle plugins define
it. A file the configuration names as `${config_loc}/<path>`, such as a suppressions file beside it, is handed
to Checkstyle with it, and changing that file runs the check again. A path that leaves the folder of
`checkstyle.xml` is refused.

Every other `${<property>}` the configuration names is a line of a `checkstyle.properties` beside it, which
takes the place of the Maven plugin's `propertyExpansion` and Gradle's `configProperties`. Without the line,
Checkstyle fails to load the configuration. `config_loc` is the one property the file cannot set:

```properties
# build.jenesis/checkstyle.properties  →  read by <property name="severity" value="${checkstyle.severity}"/>
checkstyle.severity=warning
```

A jar of custom checks or filters, a dependency of the Checkstyle plugin in Maven, joins Checkstyle's class path
when `@jenesis.plugin checkstyle maven/<groupId>/<artifactId>` names it in `module-info.java`, or
`<!--jenesis.plugin checkstyle maven/<groupId>/<artifactId>-->` in a `pom.xml`.

PMD runs the rules of every priority in `pmd.xml`. `jenesis.source.pmd.priority` names the lowest priority it
runs, from `1`, the highest, to `5`, the default, as the Maven plugin's `minimumPriority` does; any other
value is refused.

### Switching a tool off

File discovery alone decides which linters run until a setting says otherwise. `ignore` skips one without
deleting its configuration file:

| Property | Covers |
| --- | --- |
| `jenesis.source.<tool>` | `checkstyle`, `pmd`, `detekt`, `ktlint`, `scalastyle`, `scalafmt`, `codenarc` |
| `jenesis.validator.spotbugs` | SpotBugs |

For example, `-Djenesis.source.checkstyle=ignore` keeps `checkstyle.xml` in place but skips Checkstyle, while
PMD and SpotBugs still run.

{% demos 34, 42, 45, 47 %}

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

An `errorprone.properties` in the configuration folder is what turns the plugin on, and carries its flags:

```properties
# build.jenesis/errorprone.properties
arguments=-Xep:ReferenceEquality:ERROR
```

`arguments` is appended to the `-Xplugin:ErrorProne` option, so every Error Prone flag applies -
`-Xep:<Check>:OFF|WARN|ERROR` to set one check's severity, `-XepAllErrorsAsWarnings`,
`-XepDisableWarningsInGeneratedCode`. An empty file runs the default set of checks, where most findings are
warnings and a handful are errors.

The two halves are independent on purpose, and each fails loudly without the other: with the tag but no
configuration file the plugin resolves and sits unused, because `javac` runs a plugin only when it is named;
with the file but no tag the build stops and names the `@jenesis.plugin` line that is missing. A `pom.xml`
project declares the plugin as a `<!--jenesis.plugin javac maven/com.google.errorprone/error_prone_core-->`
comment, in the module's POM or in a parent POM in the project, and the build names that comment instead.

<div class="note">
  Error Prone reads <code>com.sun.tools.javac</code> internals that <code>jdk.compiler</code> does not
  export. Only the JVM that runs the compiler can grant them, through <code>-J</code> options that exist
  only for a <code>javac</code> of its own, so the compile step forks while Error Prone is active whatever
  <code>jenesis.process.factory</code> says. Every processor also stays on the processor class path, where
  <code>--add-exports ...=ALL-UNNAMED</code> can reach the plugin.
</div>

`-Djenesis.compile.errorprone=false` keeps the file and the declaration in place but compiles without the
plugin.

{% demos 14 %}

## Formatting

Formatters are the rewriting counterpart to the linters: where a linter reads your sources and writes a
report, a formatter reads them and can rewrite them in place. The Java formatter is selected by a
`javaformat.properties` file naming the formatter:

```properties
formatter=google
```

`formatter=palantir` selects the Palantir formatter instead, and `formatter=eclipse` the Eclipse formatter; with no
file, no Java formatter runs. The same file takes the formatter's options, and an option the selected formatter
does not have fails the build, naming the ones it has:

| Key | Formatter | Value |
| --- | --- | --- |
| `style` | google | `google`, the default, or `aosp` for the Android Open Source Project's four-space style |
| `reflow` | google, palantir | `false` leaves long strings as they are written |
| `javadoc` | google | `false` leaves Javadoc as it is written |
| `imports` | google, palantir | what happens to the imports: `sort,remove`, the default, `sort`, `remove` or `none` |
| `profile` | eclipse | the formatter profile Eclipse exports, a file beside or below `javaformat.properties` |

Kotlin formatting is `ktlint -F`, activated by the same `.editorconfig` that drives the ktlint linter, or ktfmt,
activated by a `ktfmt.properties` whose `style` is `meta`, the default, `google` or `kotlinlang`, and whose
`imports=sort` keeps unused imports. The two cannot format the same sources, so a `ktfmt.properties` beside an
`.editorconfig` needs `jenesis.format.ktlint=false`. Scala formatting is `scalafmt`, activated by `.scalafmt.conf`.
Each switches off with `jenesis.format.java`, `jenesis.format.ktlint`, `jenesis.format.ktfmt` and
`jenesis.format.scalafmt` (each defaulting to `true`).

### Licence headers

A `licenseheader.properties` in a configuration folder holds, as its `text` key, the header every Java, Kotlin,
Scala and Groovy source of the module starts with, written as plain text or already as a comment. `\n` separates
its lines, and a trailing `\` continues the value on the next line:

```properties
text=Copyright 2026 the original author or authors.\n\n\
  Licensed under the Apache License, Version 2.0.
```

The file takes no other key. The header is taken exactly as it stands, a year included: a source without it, or with a different one, fails the build, as a formatter does. Under
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

### Verify mode, and how to reformat

Every formatter runs in **verify mode** by default, so a normal build never touches your sources. Instead it
**fails the build when a file is not already formatted**, which makes it a continuous-integration gate. Indent
a source file with a few spare spaces and rebuild: the `format` step fails.

To apply the formatter and rewrite your sources in place, run the build with the rewrite switch:

```bash
java -Djenesis.format.rewrite=true build/jenesis/Make.java
```

The switch flips the whole chain - the licence headers, the Java formatter, ktlint or ktfmt, and scalafmt - from
verifying to rewriting.
After a rewrite, a plain build passes the verify gate again.

<div class="note">
  Groovy has no formatter: no suitable Maven-published formatter exists for it, so a Groovy
  project's <code>codenarc.xml</code> lints but nothing reformats.
</div>

{% demos 34, 42 %}

## Where the reports land

Every tool writes its findings into a `reports/<kind>/` folder under its step's output, for example
`reports/checkstyle/checkstyle-report.xml`, `reports/pmd/`, `reports/spotbugs/`. You rarely need the exact
path, because a **`stage` build collects every report from every module into one place**, each kind in its own
subfolder:

```
target/stage/reports/output/<kind>/<module>/
```

So `target/stage/reports/output/checkstyle/sources/checkstyle-report.xml` is the Checkstyle report for the
module under `sources/`, and coverage reports land under `target/stage/reports/output/jacoco/<module>/` the
same way.

## Code coverage

Coverage is a **test observation**: JaCoCo wraps the test run and records which code the tests touched. Turn
it on by placing a `jacoco.properties` file in the configuration folder. The project-wide `build.jenesis/`
works for every layout; a `pom.xml` project can also scope it to its tests with `src/test/build.jenesis/`.

With the file present, the test step is launched with the JaCoCo agent attached as a `-javaagent`. It
instruments the run without touching your sources and writes its execution data (`jacoco.exec`); a downstream
report step renders an HTML and XML report under `reports/jacoco/`, over the classes of the code under test,
never the compiled tests themselves. Open the `index.html` to browse coverage
line by line. JaCoCo, like every tool here, resolves in its own group (`jacoco`) apart from your dependencies.
The agent writes the data the CLI reads, so it follows the release the group pins for the CLI: a pin of
`jacoco/maven/org.jacoco/org.jacoco.cli` alone runs the tests under that version's agent as well, until `pin`
records both.

An empty `jacoco.properties` only reports: a method your tests never reach shows up as uncovered, and the build
stays green. Lines in the file set limits on the module's coverage, as the `check` goal of jacoco-maven-plugin
does for a bundle:

| Key | Limit |
| --- | --- |
| `minimum.<counter>` | the least covered ratio, from 0 to 1, such as `minimum.line=0.8` |
| `maximum.missed.<counter>` | the most items left uncovered, such as `maximum.missed.class=0` |

The counters are JaCoCo's: `instruction`, `branch`, `line`, `complexity`, `method` and `class`. A limit that is not
met fails the build once the report is rendered, naming the limit and what the tests reached:

```text
minimum.method=0.9 is not met: 2 of 3 covered, a ratio of 0.6667
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

{% demos 36 %}

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
translates the selection in its own `tags` method, and one that does not implement it refuses any selection.

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

{% demos 3, 4, 35 %}

## Running only the tests a change affects

Jenesis already skips a module's whole test step when none of that module's inputs changed. **Test selection**
is the finer-grained companion: within a module that *did* change, it runs only the test classes the change
can reach and leaves the rest cached. Turn it on with `-Djenesis.test.incremental`:

```bash
java -Djenesis.project.watch=true -Djenesis.test.incremental build/jenesis/Make.java
```

`true`, or the setting named with no value, detects changes with `MD5`; the name of another message digest
the JDK provides detects them with that one, and `false` or leaving it unset disables selection. Any other value
fails the build with the valid ones listed. A filter, an exclusion and a tag selection each switch it off, so
such a run runs every test it selects rather than only those a change reaches. On each run the test step builds a class-to-test dependency graph from the
compiled bytecode and records a per-class content hash. On the next run it diffs the hashes, takes the classes
whose bytecode changed, walks the graph to the tests that reach them, and passes only those to the runner. A
change that reaches no test runs nothing; any non-class change (a resource, a dependency) falls back to the
full suite.

Test selection is meant mainly for **watching** a project (see *[Building & running](/tool/building-and-running/)*), where the build re-runs
on every save and a narrowed test pass keeps the feedback loop tight.

<div class="warning">
  Test selection is a development-loop optimisation, <strong>not a correctness gate</strong>. Static selection
  cannot see reflection, resources or other indirect couplings, so continuous integration should keep running
  the whole suite - a plain <code>build</code> with selection off.
</div>

{% demos 37 %}

## Mutation testing

Coverage tells you which lines a test *executed*; mutation testing tells you which behaviours a test actually
*checks*. [PIT](https://pitest.org) (`pitest`) seeds small faults into your code (a `+` becomes a `-`, a
return value is replaced with a constant), re-runs the tests against each mutant, and reports which mutants
the tests **killed** and which **survived**. A surviving mutant is a change to the program that no test
noticed.

Like the linters, PIT is discovered from a config file: a `pitest.properties` in a tested module wires a
`mutate` step alongside the normal test run, so the suite runs as usual *and* PIT then assesses how good it is.
Unlike a bare marker, this file carries real configuration - the options PIT needs:

```properties
targetClasses=calc.Calculator   # which classes to mutate
targetTests=calctest.*          # which tests to run against the mutants
outputFormats=XML,HTML          # report formats (an optional `mutators` key selects a mutator set)
```

PIT and its JUnit 5 plugin resolve in their own `pitest` group; the plugin's version is taken from the
project's own resolved `junit-platform`, so it always lines up with the test framework you use. The report
lands under `reports/pitest/`, and `-Djenesis.mutate.pitest=false` suppresses the run while keeping the file in
place.

{% demos 38 %}

## API compatibility

Coverage and mutation testing ask whether your tests are any good. **API compatibility** asks whether the jar
you are about to publish still works for everyone who compiled against the last one.
[japicmp](https://siom79.github.io/japicmp/) answers by comparing byte code, which is the level that matters:
a caller linked against class files, so a removed method, a narrowed return type or a tightened modifier is
what breaks them.

A `japicmp.properties` in a configuration folder switches it on. Empty, it compares the module's fresh jar
against the last release of **that module's own coordinate**, so the check follows your releases rather than
being re-pointed by hand. A `baseline` key names another artifact, read by how many slashes it carries:

```properties
baseline=com.example/library                           # the latest release
baseline=com.example/library/1.2.3                     # that version
baseline=modular/com.example/library/1.2.3             # served from a named repository
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

An unknown key fails the build and lists the ones that exist; anything japicmp accepts that the file does not
model can be appended with a `process-japicmp.properties`, like for every other forked tool.

Like the linters, the check only **reports** by default: it writes `reports/japicmp/japicmp-report.xml` and
keeps the build green, so you see what changed before you decide to enforce it. Turning on a gate makes the
failure name the change that caused it:

```
E: There is at least one incompatibility:
   library.Library.farewell(java.lang.String):METHOD_REMOVED
```

japicmp and the baseline artifact resolve in their own `japicmp` group, kept apart from the module's own
dependencies; the baseline resolves **without** its transitive dependencies, because only its own byte code
is compared. It is a released artifact like any other, so `pin` records it with a checksum alongside the
tool - one line, not a closure. `-Djenesis.artifact.japicmp=false` suppresses the comparison while keeping
the file in place.

{% demos 40 %}

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

Every tool above floats a `RELEASE` version in its own dependency group until you pin it, so a first build
downloads the latest and later builds reuse the cache. For a reproducible, checksum-verified tool chain, run
`java build/jenesis/Make.java pin`: it records each resolved tool jar with its SHA-256 exactly as it pins
your compilers and dependencies (see *[Pinning & bills of materials](/tool/pinning/)*). Expect a long list -
a linter's own closure can run to a hundred artifacts - which is what makes the tool chain reproducible.
