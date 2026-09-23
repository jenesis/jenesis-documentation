---
order: 16
title: Extending the build
description: Add plugins to the stock build, write the build steps and plugins they are made of, or write an entry point of your own when the build must change what the stock steps do.
---

Every chapter so far drove the stock pipeline: a layout auto-detects your modules, the default assembler
wires the conventional compile/jar/test flow, and you configure it by choosing among the options it offers.
This chapter is for the build that needs something the stock pipeline *does not* model - a preprocessing pass,
a code-generation step, a bespoke packaging step, an unusual dependency wiring.

Almost always, the answer is a **plugin**: a build module, named in one line of a properties file, that joins a
module of the stock build and adds to it. A plugin never replaces what the stock build does; a build that must -
one that redirects what the compiler reads, or wires a step between two stock ones - is an entry point of its
own, and that comes last.

## Adding plugins to the stock build

A project names its plugins in `jenesis-plugins.properties`, beside `jenesis.properties` at its root, one per
line:

```properties
binary/generated/greeting=./plugin
artifact/signing=demo.signing
```

The key is `<slot>/<name>`. The **slot** is the module of the stock build the plugin joins, named as the build
log shows it: `check`, `format`, `compliance`, `binary`, `binary/generated`, `binary/compiled`,
`binary/validate`, `artifact`, `observed`, `documentation` and `documentation/generate`. A key without a slot
adds the plugin to the module build itself, and an unknown slot is refused. The **name** is the plugin's own.
The value says where the plugin comes from:

- a value starting with `./` or `../` is a folder, compiled from source on every build, and
- anything else is a module name, resolved as `module/<name>` from the Jenesis module repository whatever the
  project's layout, with the local export (`~/.jenesis`) searched first.

Either may end in `@<name>`, which selects the provider annotated `@BuildModuleName("<name>")` when the plugin
module provides several: `artifact/signing=demo.signing@jarsigner`. Without it, the module must provide exactly
one unannotated provider.

A plugin reads what the module it joins reads, and its output belongs to that module like any of the stock
steps': a plugin in `binary/generated` that writes a `sources/` tree has it compiled with the project's own
sources, and a plugin in `artifact` reads the jars the build produced. The plugins of a slot are wired inside
a sub-module named `custom`, which no stock module uses, so a plugin's name never collides with a stock step.

A plugin runs in a module only where **`plugin-<name>.properties`** is found, looked up like any other
configuration file - in `build.jenesis/`, with the profiles first - so the same line can serve every module of
a project and still run only in those that configure it. The file's values are handed to the plugin when it
is created:

```properties
# build.jenesis/plugin-greeting.properties
greeting=Hello from a generated source
```

The plugin's dependencies are pinned like any other, in the dependency group named after the plugin,
`plugin-<name>`:

```java
/**
 * @jenesis.pin plugin-greeting/module/org.json 20260522 SHA-256/...
 */
```

A plugin found in the local export is built on your machine and is not checked against a pinned checksum.

<div class="note">
  A plugin runs code the project chooses - compiled from its own sources, or resolved by a module name it
  names - and every Jenesis that builds the project runs it, the installed <code>jenesis</code> included. Before
  you build a project whose plugins you have not reviewed, run the build in a container with
  <code>-Djenesis.project.docker=true</code>: the plugins then run inside the container and never on your
  machine, and the project cannot switch Docker off (see
  <em><a href="/tool/build-performance-and-isolation/#what-runs-on-the-host">What runs on the host</a></em>).
</div>

{% demos 53, 54 %}

## Writing a build step

A **build step** is the unit of work introduced in *[Core concepts](/tool/core-concepts/)*: it reads one or
more input folders and writes into one fresh output folder. When you write your own, that is the shape you
implement - a function handed its inputs and an output folder to fill:

```java
CompletionStage<BuildStepResult> apply(Executor executor,
                                       BuildStepContext context,
                                       SequencedMap<String, BuildStepArgument> arguments);
```

The `context` gives you three folder slots:

- **`next`** - the folder this run writes into. It is created fresh every time; your step writes here and
  nowhere else.
- **`previous`** - the same step's output from the prior run, or `null` on a first run. You may *read* it to
  hard-link or copy unchanged files instead of regenerating them, but never write into it.
- **`supplement`** - scratch space for intermediate files you do not want to publish in `next`.

The `arguments` map carries one entry per predecessor you wired in. Each exposes the folder to read
(`argument.folder()`) and a per-file change status - `ADDED`, `ALTERED`, `REMOVED`, or `RETAINED` - computed
against the previous run. The default behaviour re-runs your step whenever any input changed; override
`shouldRun(...)` if you want finer control.

A step can also say that its output is not worth sending to a cache server. Override `shouldCacheRemotely()`
to return `false` when the output is large against what it costs to produce, or when it is re-derivable from
something the machine already has. The output is still cached locally, so a rebuild on this machine still
skips the work. See *[the build cache](/tool/build-performance-and-isolation/#the-build-cache)*.

<div class="note">
  Treat a step as a <strong>pure function of its input folders and its identity</strong>, its name in the graph
  and its serialised state: read from the argument folders, write to <code>next</code>, reach outside neither. That is what makes its output cacheable and safe to share
  between builds - the incremental engine relies on it.
</div>

### Talk through folders, not step names

Steps compose by **file and folder conventions**, not by knowing who wired them. A step discovers what to
read by looking for well-known paths inside each input folder - `sources/` for Java sources, `classes/` for
compiled output, `artifacts/` for jars - and writes its output under names its consumers look up the same
way. Do not inspect the *names* of your predecessors to guess which input is which; read the folders. This is
what lets you splice a custom step between two stock ones without either noticing.

## The serialised-state rule

*Core concepts* flagged that a step re-runs when its **serialised state** changes, and left the details here.
This is the one rule a custom step must get right.

Jenesis content-hashes each step's serialised form and folds that hash into its cache key. So a step re-runs
when its inputs change **or when its own configuration changes**, and "configuration" means *the values of
its serialised fields*. The practical rule follows directly:

> **Put every knob that should trigger a rebuild into a serialised field.** A greeting to substitute, a flag,
> a target version - if changing it should re-run the step, it has to be a (non-`transient`) field, because
> that field's value is exactly what the cache hashes.

<div class="warning">
  The flip side is the trap. Change detection keys off the step's <strong>serialised state, not its
  bytecode</strong>. If you change a step's <em>logic</em> - rewrite the body of its <code>apply</code>, fix a
  bug in a helper - without changing any serialised field, its hash is identical and Jenesis <strong>reuses
  the stale output</strong>. Example: a <code>preprocess</code> step whose substitution string lives in a
  field re-runs the moment you edit that string; but if you instead hard-code the string in the method body
  and edit it there, nothing re-runs until an input changes. Keep behaviour-affecting values in fields, or
  bump the step's <code>serialVersionUID</code> (below) when you have changed only code.
</div>

### State must be serialisable

Because the step is serialised to be hashed, **all of its state must be serialisable**. This is checked on
the first run, at hash time, not lazily. Two things make the common cases work:

- A **step written as a lambda** serialises with what it captures, because `BuildStep` is itself
  `Serializable`. A lambda that uses only its parameters captures nothing; one that creates an anonymous
  class inside an instance method captures that instance, which then has to be `Serializable` too.
- A **lambda** field serialises only if its declared type does. Declare the field as a serialisable
  functional interface, or cast the lambda to `Function<…> & Serializable` where you store it, and a lambda
  that closes over, say, a `Path` serialises cleanly. The stock steps do this at their constructors, which is
  why you can hand them a plain lambda.
- A **`Path`** field is hashed by its string form, even though the JDK's `Path` is not itself `Serializable`.
  So `Path`-typed configuration is first-class.

Genuinely non-serialisable state - an open socket, a database handle, a live `Context` object - throws
`NotSerializableException` at hash time, **on the first run**. That is deliberate: the error surfaces the bug
immediately rather than silently breaking cache invalidation. If you see it, hold the serialisable
*description* of the resource (a URL, a path, coordinates) as the field and open the resource inside
`apply`, or mark truly incidental state `transient` so it never reaches the digest.

<div class="note">
  The hash also folds in the class's <code>serialVersionUID</code>, which is the lever for a code-only change.
  Without an explicit one, the JVM derives it from the class structure, so adding a field or changing a method
  signature already changes the hash - but editing a method body does not. Declare a
  <code>serialVersionUID</code> and bump it whenever you change a step's behaviour without touching its
  fields. Once you declare one, structural changes no longer shift the hash on their own, so bumping it is
  your job from then on.
</div>

## Writing a plugin

A plugin is a **build module**: a named Java module that `provides` a build-executor service, which Jenesis
discovers through that declaration alone:

```java
module demo.plugin {
    requires build.jenesis;
    requires org.json;
    provides build.jenesis.BuildExecutorModule with demo.plugin.GreetingModule;
}
```

Its `BuildExecutorModule` adds the steps it contributes, as a stock module does. The values of its
`plugin-<name>.properties` reach it through a public constructor taking a `SequencedMap<String, String>` of
them, in the file's order. `javac` requires every service provider to keep a public constructor without
arguments as well, which the build uses when the file is empty. A file with values for a provider that takes
none fails the build, rather than the values being dropped:

```java
public GreetingModule() {
    this(Collections.emptyNavigableMap());
}

public GreetingModule(SequencedMap<String, String> properties) {
    greeting = properties.getOrDefault("greeting", "Hello from a generated source!");
}
```

A plugin compiled from source lives in a project folder of its own, which carries an empty **`.jenesis.skip`**
marker so the project's module discovery does not mistake it for a second project module. A published plugin
is built and exported like any other module, and resolved by its module name.

<div class="note">
  A plugin usually carries a different version of the Jenesis build API than the build running it. Each build
  module is therefore loaded into its own <code>ModuleLayer</code> with its own class loader, and calls are
  bridged across the boundary - so the two copies never clash and a plugin may pin its own Jenesis version,
  as long as the API it uses lines up. The plugin itself must be an explicit named module; its
  <em>dependencies</em> need not be, since a module layer admits automatic modules too.
</div>

## Writing an entry point of your own

A build that plugins cannot express - one that changes what the stock steps do, several builds compared, one
staged build feeding the next, a graph with no project at all - is a program of its own, run as
`java build/Demo.java`. Where it builds the
project, it calls `Make`, which reads `jenesis.properties`, the profiles and the `-Djenesis.*` properties the
JVM was started with, and returns what the build produced:

```java
Make.Result staged = new Make("build.jenesis.Project").build("stage");
Path packages = staged.outputs().get("stage/packages");
```

### Changing the stock build

An entry point that keeps the stock build but changes it builds the project from the settings, as `Make` does,
and replaces its **assembler** - the callback that wires each module's compile/jar/test sub-graph - with one
that wraps the stock `InferredMultiProjectAssembler`:

```java
Environment environment = new Environment(Make.settings(Path.of(".")).keys());
InferredMultiProjectAssembler stock = InferredMultiProjectAssembler.ofEnvironment(environment);
Project project = Project.ofEnvironment(environment, Path.of("."))
        .assembler((descriptor, repositories, resolvers) -> stock
                .apply(descriptor, repositories, resolvers)
                .mapBuild(build -> (sub, inherited) -> {
                    sub.addModule("assemble", build, inherited.sequencedKeySet().stream());
                    sub.addStep("sign", (executor, context, arguments) -> {
                        // read the jars in each argument's folder, write their signatures into context.next()
                        return CompletableFuture.completedStage(new BuildStepResult(true));
                    }, "assemble");
                }));
System.exit(new Execution(project).execute(args));
```

`mapBuild` decorates only the module's build phase - here registering the stock output under `assemble` and
chaining a `sign` step onto it. `Execution` builds the project and runs the module that declares a main class,
as `build/jenesis/Execute.java` does for the stock build.

The stock modules take additional steps and modules in code as well, through the same `custom` slot a plugin is
wired into:

```java
InferredMultiProjectAssembler checked = stock.check(check -> check.custom("placeholders", (executor, context, arguments) -> {
    // fail when a source in any argument's folder still holds a ${ placeholder
    return CompletableFuture.completedStage(new BuildStepResult(true));
}));
```

- `custom(name, step)` adds one step and `custom(name, module)` one module, after those added before; either
  refuses a name that is taken already.
- `custom(map)` sets every added module at once, a `SequencedMap<String, BuildExecutorModule>` in the order
  they are wired.

#### Redirecting a module's inputs

An entry point can also change *what* the stock steps consume, because the module descriptor is immutable with a
**wither per property**. Every reference accessor (`sources`, `resources`, `manifests`, `dependencies`,
`artifacts`, `content`, `coordinates`, `spdx`) returns a `SequencedSet<String>`, so you can add or replace
inputs in one line:

```java
descriptor.sources("preprocess")   // stock compile now reads the preprocess step's output, not sources/
```

That is the whole trick behind a preprocessing build: add a `preprocess` step that reads the module's
`sources/`, rewrites it into its own output, then hand the stock assembler a descriptor whose `sources()`
points at `preprocess`. `javac`, the jar step, and the tests all consume the transformed tree, and the rest
of the build is untouched. Any pass that produces a `sources/` tree - template expansion, code generation,
licence-header stamping - fits the same shape.

{% demos 51, 52 %}

### Starting on the selected JDK

Such an entry point starts on whichever JDK runs it. To honour `jenesis.toolchain.version`, as `Make.java`
does, ask `Toolchain` from `build.jenesis`: `new Toolchain().home()` answers the JDK the version selects, and
`launch(Demo.class, options, arguments)` starts the entry point again on it and returns its exit code.

A file that names `Project` or the steps is compiled by the JDK's source launcher on every run, engine
included. Compile it once when that matters - `javac -d .jenesis/tool $(find build/ -name '*.java')`, then
`java -cp .jenesis/tool build.Demo` - and keep `java build/Demo.java` as the documented command.

### Reusing the toolchain without `Project`

When the stock compile/jar/test flow fits but `Project` does not, call the convenience factory
`MavenProject.make` (or `ModularProject.make` for a Java Module System project). It
discovers the modules under a root, fills in sane defaults - a Maven Central repository, the right resolver, a
digest - and leaves only the environment those defaults read their settings from and the assembler for you to
supply:

```java
Environment environment = new Environment(Make.settings(Path.of(".")).keys());
BuildExecutor root = BuildExecutor.of(Path.of("target"));
root.addModule("maven", MavenProject.make(environment,
        Path.of("."),
        (descriptor, repositories, resolvers) -> new InferredMultiProjectAssembler().apply(
                new ProjectModuleDescriptor(descriptor)            // the discovered module
                        .configuration(Path.of("."))               // its configuration folders
                        .pathPlacement(PathPlacement.CLASS_PATH),  // place dependencies on the class path
                repositories, resolvers)));
root.execute(args);
```

The descriptor runs the module's tests, attaches no sources or javadoc jar and pins leniently unless told
otherwise; `test(false)`, `source(true)`, `documentation(true)` and `pinning(Pinning.STRICT)` change one of
those each.

This is a middle ground: no layout, no goals, no `Project`, yet you did not wire every step by hand either.
`ModularProject.make` is the modular counterpart; its convenience form builds pure modules (a modular jar,
no generated POM). For full control - a custom repository, strict pinning, a different digest, or emitting a
POM as well - switch to the longer `make(...)` overload that `Project` itself uses.

{% demos 55, 56 %}

### Wiring the graph by hand

When auto-detection is the wrong starting point entirely - a non-Java pipeline, code generation, a wildly
custom graph - drop to the `BuildExecutor` primitives and build exactly the graph you want:

```java
BuildExecutor root = BuildExecutor.of(Path.of("target"));
root.addSource("sources", Bind.asSources(), Path.of("sources"));
root.addStep("generate", new GenerateSource(), "sources"); // writes sources/sample/Generated.java
root.addStep("classes", new Javac(ProcessHandler.Factory.of()), "sources", "generate");
root.addStep("artifacts", new Jar(ProcessHandler.Factory.of(), Jar.Sort.CLASSES), "classes");
root.execute(args);
```

`BuildExecutor.of(...)` is the root and writes everything under `target/`. `addSource` binds a directory so
changes to it invalidate downstream caches. `addStep(name, step, predecessors…)` chains a step whose
arguments come from the named predecessors. `execute` runs the graph (or a selector's subtree), reusing
cached outputs whose inputs are unchanged. The `generate` step above synthesises a Java source on the fly and
`Javac`, which reads the `sources/` of *every* predecessor, compiles it next to the hand-written ones.
There is no phase lifecycle to fit into: a build is just steps wired to steps, and here you wire them
yourself.

{% demos 57 %}

## Running a build inside another program

An entry point of your own is still a process. A program that already runs - an IDE, a test harness, a
server that builds what it serves - can run a build **in its own JVM** instead, through
`java.util.spi.ToolProvider`, the JDK's interface for a tool that runs in-process the way `javac` and `jlink`
do. `build.jenesis` publishes three, named after the commands they answer to:

| Tool | What it does | What follows the settings |
| --- | --- | --- |
| `jenesis-make` | Builds the project | Selectors, as on a command line |
| `jenesis-exec` | Builds, then runs what it built | The program's own arguments |
| `jpx` | Runs a published program | The target and jpx's options |

```java
StringWriter log = new StringWriter();
int code = ToolProvider.findFirst("jenesis-make").orElseThrow().run(
        new PrintWriter(log), new PrintWriter(log),
        "-Djenesis.project.version=1.0.0", "build");
```

The leading `-Djenesis.*` arguments configure **that run** and nothing else: they are never written to the
JVM's properties, and the run never reads them from there, so two builds in one program can be configured
differently and neither leaves anything behind. Everything the build prints arrives on the writers you
passed, which the tool does not flush - they are yours, and an autoflushing `PrintWriter` already drains
itself. An `@<file>` argument works here as on a command line.

A setting that would replace the process a build runs in cannot be honoured in-process, and is refused by
name rather than ignored: `jenesis.toolchain.version` and `jenesis.project.docker` for all three, and
`jenesis.execute.docker` for the program `jenesis-exec` runs. The refusal arrives on `err` with a non-zero
code rather than as an exception. `jenesis-exec` forks the program it runs, as its command does, so that
program writes to the JVM's own streams while the build's output goes to the writers.

The tools are found by name when `build.jenesis` is a resolved module or a jar on the class path. Source
mode registers no service, so a program there constructs `new MakeTool()`, `new ExecuteTool()` or
`new JpxTool()` itself; the contract is the same.

{% demos 58 %}

