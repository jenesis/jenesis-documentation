---
order: 5
title: Building & running
description: What the compile, test, and jar phases do; feeding the compiler extra arguments and annotation processors; running a module's main with Execute.java; and rebuilding on every change with watch mode.
---

The default `build` target compiles, tests, and jars every module - you saw it run in
*[Getting started](/tool/getting-started/)*, and *[Core concepts](/tool/core-concepts/)* explained the step
graph underneath. This chapter is about the everyday loop that graph
drives: what each of those phases actually does, how to hand the compiler an extra flag or an annotation
processor, how to run a module's `main`, and how to keep rebuilding as you edit.

## The build pipeline

For each module, the inferred build wires the same short chain of steps: **compile → test → jar**. Running
`build` (or just `java build/jenesis/Project.java` with no selector) walks that chain for every discovered
module in dependency order.

- **Compile** runs `javac` over the module's sources, resolving its dependencies onto the class or module
  path, and writes the `.class` files. Other-language compiles (Kotlin, Scala, Groovy) slot into the same
  chain - see *[Other JVM languages](/tool/other-jvm-languages/)*.
- **Test** compiles and runs the module's tests. Jenesis **auto-detects the test framework** from the test
  dependencies you already declare - JUnit Platform (JUnit 5/6), JUnit 4, or TestNG - and resolves the
  matching console runner for you, so you never add it as an explicit dependency. In the modular layouts the
  tests live in their own `@jenesis.test` module, built after the module under test.
- **Jar** packages the compiled classes into the module's jar under `target/`. When the module declares a
  main class (below), the jar's manifest gets a `Main-Class` entry and its `module-info` a `ModuleMainClass`
  attribute, so the artifact is directly launchable.

<div class="note">
  Every phase is cached the way <em>Core concepts</em> described: a second <code>build</code> recompiles and
  re-tests nothing until an input actually changes. A test step in particular re-runs only when the classes it
  covers change - not on every build.
</div>

### Skipping the tests

To compile and package without running the test suite - a fast inner loop, or a machine that only builds
artifacts - set `jenesis.test.skip`:

```bash
java -Djenesis.test.skip=true build/jenesis/Project.java
```

The bare flag (`-Djenesis.test.skip`) works too. Tests still *compile*; they just do not run.

### Choosing the Java version

An `@jenesis.release <N>` tag on the module declaration pins the compile to a specific Java release - Jenesis
turns it into `javac --release <N>`, so the module compiles against exactly that platform API regardless of
the JDK running the build:

```java
/**
 * @jenesis.release 21
 */
module demo.app {
    exports sample;
}
```

A `pom.xml` project sets the same thing through its usual `maven.compiler.release` / `<release>`
configuration.

### One jar, several Java versions

A jar can also carry different bytecode for different Java versions, with the JVM loading the copy that
matches its own version at launch. You get one from a source convention: anything under
`sources/META-INF/versions/<N>/` is compiled in its own pass with `--release <N>`.

```
sources/
├── module-info.java                           @jenesis.release 21
├── sample/Platform.java                        the Java 21 baseline
└── META-INF/versions/25/sample/Platform.java   the Java 25 override
```

The jar that comes out runs the baseline on a Java 21 runtime and the override on Java 25 - one artifact, two
implementations, selected by the JVM. Nothing else is needed: producing an overlay is what marks the jar
`Multi-Release: true`, the flag that tells the JVM to look in the versioned directory at all.

### Source and API-documentation jars

A normal `build` produces just the binary jar. Two flags add the companion artifacts a repository like Maven
Central expects:

```bash
java -Djenesis.project.sources=true \
     -Djenesis.project.documentation=true \
     build/jenesis/Project.java
```

`jenesis.project.sources` adds a per-module `-sources.jar`, and `jenesis.project.documentation` runs the
documentation tool (`javadoc` for Java) and adds a `-javadoc.jar`. Both are off by default because they cost
build time you do not want on every inner-loop run; turn them on for a release (or record them in a profile -
see *[Configuration](/tool/configuration/)*).

## Passing extra arguments to a tool

Jenesis picks sensible flags for `javac` and the other tools it forks, but sometimes you need one more. You
add it with a **`process-<command>.properties`** file in a configuration location (a `build.jenesis/` folder,
as covered in *Configuration*) - no build script required. The file is named after the tool, and each entry
is a flag with its argument:

```properties
# process-javac.properties  →  compile with -parameters
-parameters=
```

Each key is a flag and its value the flag's argument. An **empty value emits a bare flag** (as above); a value
with embedded newlines repeats the flag once per line. The file merges over the arguments Jenesis already
generates - so `javac` here receives both the build's own `--release` and your `-parameters`.

The same mechanism works for every tool the build forks: `javac`, `kotlinc`, `scalac`, `jar`, `jmod`, `jlink`,
`jpackage`, and `native-image`. Two names address the forked JVMs specifically: **`process-java.properties`**
applies to *every* forked `java` process, while **`process-test.properties`** targets only the test JVM
(merged over the `java` file, with test keys winning).

<div class="tip">
  Because the file lives in a configuration location, it is profile-aware and resolved by first match - so a
  profile can add a flag for one build, and an empty <code>process-javac.properties</code> in a more specific
  location switches an inherited flag back off. This is the profile-aware way to compile a single module with
  extra <code>javac</code> flags.
</div>

## Annotation processing

A Java annotation processor (JSR-269) is turned on with a single `@jenesis.plugin` tag on the module
declaration, naming the processor **by module name** (or `<repository>/<coordinate>`):

```java
/**
 * @jenesis.plugin org.immutables.value
 */
module demo.annotations {
    requires static org.immutables.value;
}
```

Jenesis resolves the processor, places it on `javac`'s **processor path** (`--processor-module-path`), and the
compiler runs it. The version is pinned the usual way - the `pin` step writes back the `@jenesis.pin` line for
you (pinning is covered in *[Pinning & bills of materials](/tool/pinning/)*).

<div class="warning">
  Processors are run <strong>only from what you declare</strong>. A dependency that happens to bundle a
  processor - even one that is also a <code>requires</code> of your module, and so already on the module path -
  never runs unless a <code>@jenesis.plugin</code> tag places it on the processor path. Delete the tag and the
  processor silently stops running; the class it generates is never produced and the build fails to compile.
</div>

The same tag, with a compiler name in front (`@jenesis.plugin kotlinc <coordinate>`), declares a compiler
plugin for another language - covered in *Other JVM languages*.

## Running a module's main

To *run* a module rather than just build it, declare its entry point and launch it with **`Execute.java`**, the
companion launcher next to `Project.java`. Declaring the main class differs by layout but converges on the same
result:

- a **modular** project uses a `@jenesis.main` tag on `module-info.java`:

  ```java
  /**
   * @jenesis.main sample.Sample
   */
  module demo.app {
      exports sample;
  }
  ```

- a **`pom.xml`** project sets a `<mainClass>` property instead:

  ```xml
  <properties>
      <mainClass>sample.Sample</mainClass>
  </properties>
  ```

`Execute.java` **builds the project first**, then launches the main class in a fresh `java` process, forwarding
any trailing arguments to your program:

```bash
java build/jenesis/Execute.java ada lovelace
```

### Implicit vs. explicit main

If exactly one module declares a main class, `Execute` selects it **implicitly** - you pass nothing. If several
do, it stops and lists the candidates; name the one you want **explicitly** with two properties, which also
narrows the build to that module's subtree:

```bash
java -Djenesis.execute.module=tools \
     -Djenesis.execute.mainClass=org.example.tools.Cli \
     build/jenesis/Execute.java --help
```

`jenesis.execute.module` takes the same module path you would write after `+` in a build selector.

<div class="note">
  <code>Execute</code> can also run the launched program inside a container, independently of the build - see
  <em>Build performance &amp; isolation</em>. Running an <em>already-published</em> module instead of the
  current project is the job of <a href="/jpx/">jpx</a>.
</div>

## Attaching a Java agent

Some libraries have to run as a `-javaagent` rather than be called through an API - a tracer that instruments
classes as they load, a mocking library that redefines them. A `@jenesis.attach` tag on the module declaration
adds one to the `java` commands that module owns: its test run, and the `Execute` run of its `@jenesis.main`.

```java
/**
 * @jenesis.main demo.agents.Application
 * @jenesis.attach io.opentelemetry.javaagent/opentelemetry-javaagent
 */
module demo.agents {
    exports demo.agents;
}
```

The token is a module name or a `<groupId>/<artifactId>`, and everything after it is passed to the agent
verbatim as its option string. There is no version slot: the version comes from a dependency you already
declare, from a pin, or floats to the latest without one. A `pom.xml` project declares the same lines in a
project-level `<!--jenesis.attach ... -->` comment block.

One tag covers both shapes an agent takes. The OpenTelemetry agent above is **agent-only**: required by
nothing, compiled against nothing, never on a compile or runtime path - attached, and that is all. Mockito is
the other shape, a **dependency that also attaches**, named by a `requires` *and* by an attach declaration;
both resolve to the identical artifact, so the jar on the module path and the jar passed as `-javaagent:` are
the same file.

An attachment belongs to the module that declares it and never propagates to a dependent, so a test module
attaches to its own test run:

```java
/**
 * @jenesis.test demo.agents
 * @jenesis.attach org.mockito
 */
open module demo.agents.test {
    requires demo.agents;
    requires org.mockito;
}
```

<div class="note">
  The resolved jar has to carry a <code>Premain-Class</code> manifest attribute - that is what makes it an
  agent - and the build says so with a clear error before the launch rather than letting the JVM fail. Agents
  are ordinary dependencies otherwise: they resolve, pin, and appear in the bill of materials like any other.
</div>

## Watch mode

While you are editing, keep the build process alive and let it rebuild on every save. Set
`jenesis.project.watch`:

```bash
java -Djenesis.project.watch=true build/jenesis/Project.java
```

The first build runs as usual; Jenesis then watches the project root and re-runs the requested target whenever
a file changes, reusing the content-hash cache so each rebuild only re-executes the steps whose inputs actually
moved - a no-op change settles in well under a second. The output folders (`target/` and the cache) and
dot-directories are excluded, so the build's own writes never trigger a rebuild. Press Ctrl+C to stop.

Module selectors still apply, so you can watch just one module's subgraph:

```bash
java -Djenesis.project.watch=true build/jenesis/Project.java +mymodule
```

Setting `jenesis.project.watch=true` in a `jenesis.properties` file makes watch a project's default. Watch mode
already skips a module's tests when none of its inputs changed; it can go finer and re-run only the tests a
change can reach - a development-loop optimisation covered in *[Code quality & testing](/tool/code-quality-and-testing/)*.

<div class="tip">
  Executable projects with a declared entry point are
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-05-java-pom-executable">demo-05</a> (a
  <code>pom.xml</code> app with <code>&lt;mainClass&gt;</code>) and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-06-java-modular-executable">demo-06</a> (a
  modular app with <code>@jenesis.main</code>);
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-08-java-multi-release">demo-08</a> builds a
  multi-release jar with a Java 25 override of one class;
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-09-javac-arguments">demo-09</a> hands
  <code>javac</code> a <code>-parameters</code> flag through <code>process-javac.properties</code>;
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-10-annotations">demo-10</a> runs an annotation
  processor (Immutables); and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-26-agents">demo-26</a> attaches Mockito to
  its tests and the OpenTelemetry agent to its application run. Each is a runnable project - see
  <a href="/tool/demos/">Demos</a>.
</div>
