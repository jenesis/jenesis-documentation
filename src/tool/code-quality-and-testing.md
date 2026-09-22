---
order: 8
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

### Report-only by default

By default every linter is **report-only**: it records its findings but never fails the build. That makes it
safe to turn a tool on across an existing codebase without an immediate red build. A build can also wire a
tool in strict mode, where a non-zero tool exit fails the build; that takes a few lines of build code, which
*Extending the build* introduces.

### Switching a tool off

To skip a discovered tool without deleting its configuration file, set its property to `false`. Every property
defaults to `true`, so file discovery alone normally decides; the property is an opt-out:

| Property | Covers |
| --- | --- |
| `jenesis.source.<tool>` | Checkstyle, PMD, detekt, ktlint, Scalastyle, scalafmt, CodeNarc |
| `jenesis.validator.spotbugs` | SpotBugs |

For example, `-Djenesis.source.checkstyle=false` keeps `checkstyle.xml` in place but skips Checkstyle, while
PMD and SpotBugs still run.

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
Prone plugin such as NullAway is another line of exactly the same form.

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
with the file but no tag the build stops and names the `@jenesis.plugin` line that is missing.

<div class="note">
  Error Prone reads <code>com.sun.tools.javac</code> internals that <code>jdk.compiler</code> does not
  export. Only the JVM that runs the compiler can grant them, through <code>-J</code> options that exist
  only for a <code>javac</code> of its own, so the compile step forks while Error Prone is active whatever
  <code>jenesis.process.factory</code> says. Every processor also stays on the processor class path, where
  <code>--add-exports ...=ALL-UNNAMED</code> can reach the plugin.
</div>

`-Djenesis.compile.errorprone=false` keeps the file and the declaration in place but compiles without the
plugin.

## Formatting

Formatters are the rewriting counterpart to the linters: where a linter reads your sources and writes a
report, a formatter reads them and can rewrite them in place. The Java formatter is selected by a
`javaformat.properties` file naming the formatter:

```properties
formatter=google
```

`formatter=palantir` selects the Palantir formatter instead; with no file, no Java formatter runs. Kotlin
formatting is `ktlint -F`, activated by the same `.editorconfig` that drives the ktlint linter, and Scala
formatting is `scalafmt`, activated by `.scalafmt.conf`. Each of the three switches off with
`jenesis.format.java`, `jenesis.format.ktlint` and `jenesis.format.scalafmt` (each defaulting to `true`).

### Verify mode, and how to reformat

Every formatter runs in **verify mode** by default, so a normal build never touches your sources. Instead it
**fails the build when a file is not already formatted**, which makes it a continuous-integration gate. Indent
a source file with a few spare spaces and rebuild: the `format` step fails.

To apply the formatter and rewrite your sources in place, run the build with the rewrite switch:

```bash
java -Djenesis.format.rewrite=true build/jenesis/Make.java
```

The switch flips the whole chain - the Java formatter, ktlint and scalafmt - from verifying to rewriting.
After a rewrite, a plain build passes the verify gate again.

<div class="note">
  Groovy has no formatter: no suitable Maven-published formatter exists for it, so a Groovy
  project's <code>codenarc.xml</code> lints but nothing reformats.
</div>

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
report step renders an HTML and XML report under `reports/jacoco/`. Open the `index.html` to browse coverage
line by line. JaCoCo, like every tool here, resolves in its own group (`jacoco`) apart from your dependencies.

<div class="note">
  Coverage is <strong>reported, not enforced</strong>. A method your tests never reach shows up as uncovered
  in the report, but the build stays green - coverage tells you where you stand, it does not gate the build.
  Set <code>-Djenesis.observe.jacoco=false</code> to suppress it even when the file is present.
</div>

## Narrowing a test run

While you are chasing one failure, running the whole suite each time is noise. Two properties narrow what the
test step executes:

```bash
java -Djenesis.test.filter='calc.*Test#addsTwo' build/jenesis/Make.java
java -Djenesis.test.tag='!(slow)' build/jenesis/Make.java
```

`jenesis.test.filter` takes a comma-separated list of `<classRegex>[#<method>]` entries and runs only what
matches. `jenesis.test.tag` selects by the tags or groups your test framework already understands. On the
JUnit Platform that is a tag expression, so `!(slow)` excludes; TestNG takes plain group names; JUnit 4
cannot select categories through its console runner and rejects the property.

A narrowed run is still the same step, so its result is remembered together with **what it covered**. A later
run is skipped only when nothing changed *and* the recorded scope covers the request: the same filter, or a
tag selection the last run already included. Asking for anything else runs the tests again, and so does
anything the comparison cannot decide, because a skipped test is not a passed test.

<div class="tip">
  To run the tests when nothing at all has changed - a flaky test, a debugging session - pass
  <code>-Djenesis.test.force=true</code>. It drops the comparison for that run only. Narrowing belongs on a
  developer machine, though: a build that populates a
  <a href="/tool/build-performance-and-isolation/">shared cache</a> should run the full suite, or a narrowed
  result can be served to someone asking for more.
</div>

## Running only the tests a change affects

Jenesis already skips a module's whole test step when none of that module's inputs changed. **Test selection**
is the finer-grained companion: within a module that *did* change, it runs only the test classes the change
can reach and leaves the rest cached. Turn it on with `-Djenesis.test.incremental`:

```bash
java -Djenesis.project.watch=true -Djenesis.test.incremental build/jenesis/Make.java
```

The value names the digest algorithm used to detect changes; passing the flag bare picks `MD5`, and leaving
it unset disables selection. On each run the test step builds a class-to-test dependency graph from the
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

## API compatibility

Coverage and mutation testing ask whether your tests are any good. **API compatibility** asks a different
question: does the jar you are about to publish still work for everyone who compiled against the last one?
[japicmp](https://siom79.github.io/japicmp/) answers it by comparing byte code, which is the level that
matters - a caller linked against class files, not against your sources, so a removed method, a narrowed
return type or a tightened modifier is what breaks them.

A `japicmp.properties` in a configuration folder switches it on. With no keys at all, japicmp compares the
module's freshly built jar against the last release of **that module's own coordinate**:

```properties
# empty: compare against <this module's groupId>:<its artifactId> at RELEASE
```

The version floats, so the check follows your releases rather than being re-pointed by hand. A `baseline`
key names a different artifact, read by how many slashes it carries rather than by any suffix:

```properties
baseline=com.example/library                           # the latest release
baseline=com.example/library/1.2.3                     # that version
baseline=modular/com.example/library/1.2.3             # served from a named repository
```

A module with no Maven coordinate has nothing to default to, so leaving the key out there fails with a
message naming it. In a multi-module project the file is read per module, so a `japicmp.properties` in the
project-wide configuration folder with no `baseline` gives every module its own coordinate - which is what
you want. A `baseline` there would point every module at the same artifact, so a per-module baseline belongs
in that module's own configuration location.

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

Like the linters, the check is **report-only** by default: it writes `reports/japicmp/japicmp-report.xml` and
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

<div class="demo">
  Five runnable demos exercise this chapter:
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-32-java-quality">demo-32</a> wires Checkstyle,
  PMD, SpotBugs and the Java formatter into one project;
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-33-code-coverage">demo-33</a> measures
  coverage with JaCoCo;
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-34-test-selection">demo-34</a> edits one class
  and re-runs only that class's test;
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-35-pitest">demo-35</a> runs pitest, killing
  both mutants of a covered method; and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-37-api-compatibility">demo-37</a> compares a
  built jar against a released one with japicmp. See <a href="/tool/demos/">Demos</a>.
</div>
