---
order: 16
title: Extending the build
description: Adjust the stock build with a customizer, write the build steps it adds, package them as a plugin, or write an entry point of your own when one adjusted build is not enough.
---

Every chapter so far drove the stock pipeline: a layout auto-detects your modules, the default assembler
wires the conventional compile/jar/test flow, and you configure it by choosing among the options it offers.
This chapter is for the build that needs something the stock pipeline *does not* model - a preprocessing pass,
a code-generation step, a bespoke packaging step, an unusual dependency wiring.

Almost always, the answer is a **customizer**: a class that adjusts the project the stock build would run and
keeps everything else about it. Only a build that is more than one adjusted project - several builds whose
results are compared, one build feeding the next, a graph with no project at all - needs an entry point of
its own, and that comes last.

## Customizing the stock build

A customizer is a class in the project's `build/custom/` folder that adjusts the **assembler** - the callback
that wires each module's compile/jar/test sub-graph. It implements `Project.Customizer`, a functional interface
whose one method is handed the `InferredMultiProjectAssembler` the settings configured and returns the
`MultiProjectAssembler` to build with. This one,
`build/custom/Signing.java`, adds a `sign` step after the stock build:

```java
package build.custom;

public class Signing implements Project.Customizer {

    @Override
    public MultiProjectAssembler<? super ProjectModuleDescriptor> apply(InferredMultiProjectAssembler assembler) {
        return (descriptor, repositories, resolvers) -> assembler
                .apply(descriptor, repositories, resolvers)
                .mapBuild(stock -> (sub, inherited) -> {
                    sub.addModule("assemble", stock, inherited.sequencedKeySet().stream());
                    sub.addStep("sign", (executor, context, arguments) -> {
                        // read the jars in each argument's folder, write their signatures into context.next()
                        return CompletableFuture.completedStage(new BuildStepResult(true));
                    }, "assemble");
                });
    }
}
```

Name it in the project's `jenesis.properties`, so every build of the project applies it:

```properties
jenesis.project.customizer=build.custom.Signing
```

The same key works on the command line or in a profile, like any other setting.

Build a project with a customizer with `java build/jenesis/Make.java`, and run what it built with
`java build/jenesis/Execute.java`. They compile `build/custom/` with the engine; the installed `jenesis` command
runs the released engine, compiles nothing under `build/custom/`, and stops with an error naming the customizer
it cannot find.

The assembler the customizer returns is a lambda that calls the stock one for every module. `mapBuild`
decorates only the module's build phase - here registering the stock output under `assemble` and chaining the
`sign` step onto it. The build is otherwise the stock one: `jenesis.properties`, the profiles and the other
settings configure the assembler the customizer receives, and the build runs on the JDK, in the daemon or in
Docker as they ask. `java build/jenesis/Execute.java` reads the same settings and runs the program the
customized build produced.

- `jenesis.project.customizer` names one class. A build that signs, stamps licence headers and emits checksums
  does all of it in that one function, without reimplementing the toolchain.
- A program that builds the project itself hands the same function to `new Project(root, customizer)`, or to
  `Project.ofEnvironment(environment, root, customizer)` to start from the settings.
- `Make.java` compiles `build/custom/` with the engine once, into `.jenesis/classes`, and again only when a
  source there changes. A customizer needs a public constructor without arguments.
- `jenesis-validate` compares `build/jenesis` alone, so a customizer leaves the vendored engine valid.

<div class="note">
  A customizer runs the project's own code, just as its tests do. Before you build a project you do not
  trust, run the build in a container with <code>-Djenesis.project.docker=true</code>. The customizer is then
  applied inside the container and never on your machine, and the project cannot switch Docker off (see
  <em><a href="/tool/build-performance-and-isolation/#what-runs-on-the-host">What runs on the host</a></em>).
</div>

{% demos 50, 51 %}

### Adding modules beside the stock ones

Every module the stock assembler wires - the checks, the formatters, the compliance checks, the toolchain and
the modules it nests, the test observation, the documentation - and the assembler's own module build take
additional steps and modules through `custom`. They are wired next to the stock ones, inside a sub-module named
`custom`, and each reads what the module it is added to reads. No stock module is named `custom`, so an added
name never collides with a stock one, and nothing is wrapped or replaced:

```java
return assembler.check(check -> check.custom("placeholders", (executor, context, arguments) -> {
    // fail when a source in any argument's folder still holds a ${ placeholder
    return CompletableFuture.completedStage(new BuildStepResult(true));
}));
```

The step answers for `check/custom/placeholders`, next to the stock checks, on the sources they check.

- `custom(name, step)` adds one step and `custom(name, module)` one module, after those added before; either
  refuses a name that is taken already.
- `custom(map)` sets every added module at once, a `SequencedMap<String, BuildExecutorModule>` in the order
  they are wired.

### Redirecting a module's inputs

A customizer can also change *what* the stock steps consume, because the module descriptor is immutable with a
**wither per property**. Every reference accessor (`sources`, `resources`, `manifests`, `dependencies`,
`artifacts`, `content`, `coordinates`, `spdx`) returns a `SequencedSet<String>`, so you can add or replace
inputs in one line:

```java
descriptor.sources("preprocess")   // stock compile now reads the preprocess step's output, not sources/
```

That is the whole trick behind a preprocessing assembler: add a `preprocess` step that reads the module's
`sources/`, rewrites it into its own output, then hand the stock assembler a descriptor whose `sources()`
points at `preprocess`. `javac`, the jar step, and the tests all consume the transformed tree, and the rest
of the build is untouched. Any pass that produces a `sources/` tree - template expansion, code generation,
licence-header stamping - fits the same shape.

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
  class inside a customizer's method captures the customizer, which then implements `Serializable` too.
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

## Packaging the extension as a plugin

A customizer in a project's `build/custom/` folder belongs to that project. When the same pass - a code generator, a
source preprocessor - should serve several, package it as a **build module**: a named Java module that
`provides` a build-executor service, which Jenesis discovers through that declaration alone.

A build module comes from one of two places, and nothing else about it differs:

- an **internal** build module is compiled from local source in its own project folder, and
- an **external** build module is resolved from a repository coordinate, like any published artifact.

Either way a customizer wires it in, exactly like the `sign` step above, by adding it as a module that the
stock steps then read from. An internal module names its source folder; an external one
names the coordinate to resolve and where to resolve it:

```java
// compiled from ./plugin on every build; "module" is the prefix its requires resolve under,
// "tool" the dependency group its closure is pinned in
sub.addModule("preprocess", new InternalModule("module", "tool", Path.of("plugin")), inputs);

// resolved from a repository as module/demo.plugin
sub.addModule("preprocess", new ExternalModule("module/demo.plugin", "tool", repositories, resolvers), inputs);
```

The `inputs` are the steps the build module reads - the project's `sources/` to preprocess, and its
manifests so the module's own dependencies resolve against the project's pins. A local `plugin/` folder
also carries an empty **`.jenesis.skip`** marker, so the project's module discovery does not mistake it for
a second project module.

<div class="note">
  A plugin usually carries a different version of the Jenesis build API than the build running it. Each build
  module is therefore loaded into its own <code>ModuleLayer</code> with its own class loader, and calls are
  bridged across the boundary - so the two copies never clash and a plugin may pin its own Jenesis version,
  as long as the API it uses lines up. The plugin itself must be an explicit named module; its
  <em>dependencies</em> need not be, since a module layer admits automatic modules too.
</div>

{% demos 52, 53 %}

## Writing an entry point of your own

A build that a customizer cannot express - several builds compared, one staged build feeding the next, a
graph with no project at all - is a program of its own, run as `java build/Demo.java`. Where it builds the
project, it calls `Make`, which reads `jenesis.properties`, the profiles and the `-Djenesis.*` properties the
JVM was started with, and returns what the build produced:

```java
Make.Result staged = new Make("build.jenesis.Project").build("stage");
Path packages = staged.outputs().get("stage/packages");
```

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

{% demos 54, 55 %}

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

{% demos 56 %}

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

{% demos 57 %}

