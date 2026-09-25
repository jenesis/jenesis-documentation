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
module of the stock build and adds to it, or runs once over everything the build produced. A plugin never
replaces what the stock build does; a build that must - one that redirects what the compiler reads, or wires a
step between two stock ones - is an entry point of its own, and that comes last.

## Adding plugins to the stock build

A project names its plugins in `jenesis.plugins.properties`, beside `jenesis.properties` at its root, one per
line:

```properties
greeting+binary/generated=./plugin
signing+artifact=demo.signing
```

The key is `<name>+<slot>`. The **name** is the plugin's own, and holds neither `/` nor `+`. The **slot** is the
module of the stock build the plugin adds to, named as the build log shows it: `check`, `format`, `compliance`,
`binary`, `binary/generated`, `binary/compiled`, `binary/validate`, `artifact`, `observed`, `documentation`,
`documentation/generate` and `package`. A key without `+<slot>` adds the plugin to the module build itself, and an
unknown slot is refused; the eight slots that run once for the whole project - `preprocess`, `postprocess/transform`,
`postprocess/inspect`, `stage/transform`, `stage/inspect`, `export`, `release` and `plugin` - have a section of their
own below. The value says where the plugin comes from:

- a value starting with `./` is a folder of the project, compiled from source on every build, and
- anything else is a module name, resolved as `module/<name>` from the Jenesis module repository whatever the
  project's layout, with the local export (`~/.jenesis`) searched first. A value that is neither, such as a path
  starting with `../`, fails the build.

Either may end in `@<provider>`, which selects the provider annotated `@BuildModuleName("<provider>")` when the plugin
module provides several: `signing+artifact=demo.signing@jarsigner`. Without it, the module must provide exactly
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

`-Djenesis.plugin.<name>=false` leaves a plugin out, as the stock tools are switched off, without editing the
file, and `-Djenesis.project.plugins=false` leaves out every plugin the file names.

### Handing a plugin files of the project

A plugin reads only what the build hands it, so a file of the project reaches it as an **input**. Among a
plugin's values, a key starting with `@` binds a file or folder instead of naming a value:

```properties
# build.jenesis/plugin-greeting.properties
greeting=Hello from a generated source
@templates=templates
@templates/legal/HEADER.txt=legal/HEADER.txt
```

`@<input>=<path>` binds the path into an input named `<input>`, which the plugin reads as the folder
`../inputs/<input>`. A target after the input's name, `@<input>/<target>`, places what is bound at that path
inside the input rather than at its root, and one input takes one key per target, so it can gather several files
and folders. A single file keeps its name unless a target renames it. Editing a bound file runs the plugin again.
A value whose key really starts with `@` is written with two: `@@name=value` hands the plugin `@name=value`.

In a module's `plugin-<name>.properties`, a path is resolved against the module's own folder, the one holding its
`module-info.java` or `pom.xml`. It has
to stay within the project, symbolic links included, and a plugin folder named as `./<folder>` must lie within
the project as well. A path that leaves the project, does not exist, or shares a target with another binding of
the same input fails the build.

<div class="note">
  A plugin runs code the project chooses - compiled from its own sources, or resolved by a module name it
  names - and every Jenesis that builds the project runs it, the installed <code>jenesis</code> included. Before
  you build a project whose plugins you have not reviewed, run the build in a container with
  <code>-Djenesis.project.docker=true</code>: the plugins then run inside the container and never on your
  machine, and the project cannot switch Docker off (see
  <em><a href="/tool/build-performance-and-isolation/#what-runs-on-the-host">What runs on the host</a></em>).
</div>

{% demos 54, 55 %}

### Adding a package

A plugin under **`package`** joins the packaging of each module where its `plugin-<name>.properties` is found, as
`package/custom/<name>`. It is handed the module's jar and its runtime dependencies, together with whatever
`packaging.properties` asks Jenesis to build - a runtime image, a `jpackage` image, a launcher - so it can wrap or
sign one of them into a package of its own: an AppImage, an installer built with other tools, a distribution
zip. What it writes into a `packages/` folder is staged with the other packages in `stage/packages/`, and a
package whose name another packager, or `jpackage`, writes already fails the build rather than replacing it.

## Plugins for the whole project

A plugin in a module slot sees one module. Eight slots run a plugin once for the whole project instead:

```properties
# jenesis.plugins.properties
licence+preprocess=./licence
notice+postprocess/transform=./notice
audit+postprocess/inspect=./audit
checksums+stage/transform=./checksums
complete+stage/inspect=./complete
publish+export=./publish
announce+release=./announce
lines+plugin=./lines
```

| Slot | Runs as | Runs | Is handed |
| --- | --- | --- | --- |
| `preprocess` | `build/preprocess/custom/<name>` | before any module is built | only what it binds |
| `postprocess/transform` | `build/postprocess/transform/<name>` | after every module is built | every module's inventory |
| `postprocess/inspect` | `build/postprocess/inspect/<name>` | after the transforms | the same, plus what they added |
| `stage/transform` | `stage/transform/<name>` | after the stock staging | everything staged |
| `stage/inspect` | `stage/inspect/<name>` | after the transforms of stage | the staged trees with what they added |
| `export` | `export/custom/<name>` | with `export`, beside its stock steps | everything staged |
| `release` | `release/custom/<name>` | with `release`, beside its stock steps | everything staged |
| `plugin` | `plugin/<name>` | only when `plugin/<name>` is named | only what it binds |

Each keeps its plugins apart from its own steps, so a plugin may take any name. The line itself switches such a
plugin on, as no `plugin-<name>.properties` applies to it. Their names take no `/`, `.` or `+`, and a name used
for a module slot cannot also name one of them.

A **preprocessor** checks the project before anything is compiled: a licence header, a forbidden file, a policy
on what the repository holds. It hands the build nothing, so it can stop the build early but never feed it; a
file every module needs comes from a plugin in `binary/generated` instead.

A **transform** adds files to the modules - a notice, a report, a signature of your own - and an **inspection**
checks the result and fails the build when it is wrong. Both run as part of `build`, in `build/postprocess`, so
everything that builds on it - `stage`, `export`, `release`, `pin`, `dependencies`, `ide` and `Execute.java` -
sees what the transforms added and never runs past a failed inspection. Transforms run in the order the file
names them, each seeing what the ones before it added, and the inspections run after all of them.

A **transform of stage** runs once the stock staging is done and is handed every staged tree. What it writes into a
folder named after one - `maven/`, `modular/`, `packages/`, `project/` and the others under `target/stage/` - joins
that tree where it stands, so `export`, `release`, a `jreleaser.yml` and their plugins take it like anything else
staged: checksums or signatures beside every file, repository metadata, a manifest of what ships. A file the tree
holds already fails the build rather than being replaced. An **inspection of stage** then checks the staged trees
with what was added, and nothing is exported or released past one that fails.

An **exporter** and a **releaser** deliver what was staged - to an internal repository, a bucket, a registry, a
release page - and run only when `export` or `release` is asked for. Naming `export/custom` or `release/custom`
runs the plugins alone, without the steps Jenesis runs there itself. Such a step writes outside the build, so it
overrides `shouldRun` to run every time it is selected, as the stock export steps do, rather than only when
what it reads has changed.

A plugin under **`plugin`** belongs to no goal: nothing waits for it, it waits for nothing, and it runs only when its
own selector is named, as `java build/jenesis/Make.java plugin/lines`. It is handed only what it binds, so it starts
at once - a report over the project's own files, a task run by hand. What needs the built or staged result belongs
in one of the hooks that follow them. `plugin/` holds nothing but these plugins, so a name never collides with
anything of Jenesis.

### Configuring them

A plugin of the whole project reads its values from **`jenesis.plugins.arguments.properties`** beside
`jenesis.plugins.properties`, one line per value as `<plugin>.<key>`, and from nowhere else - never from the
command line:

```properties
# jenesis.plugins.arguments.properties
notice.holder=Example Corp.
notice.@legal=legal
```

The plugin `notice` then receives `holder=Example Corp.`, and `@legal` binds the project's `legal/` folder as its
input, resolved against the project root. A line that names no declared plugin fails the build. A profile brings
values of its own in `jenesis.plugins.arguments-<profile>.properties`, which win over the file without a
profile, and of two active profiles the one named first wins. That is why the plugin files are named with dots:
in a file name, a dash after a name always introduces a profile, as in `jenesis-<profile>.properties`.

Since these plugins run with every build, one that takes long is best switched off in `jenesis.properties` with
`jenesis.plugin.<name>=false` and switched back on in the profile that ships. `-Djenesis.project.plugins=false`
leaves out every plugin at once, those of the module slots included.

### What a transform and an inspection see, and what they may add

Each of them is handed the inventory of every module: its jar, sources and documentation, its POM, and every
dependency it resolved, each with the jar it resolved to. A transform adds to a module by writing files into its
own output and naming them in an `inventory.properties` there, under the prefix the inventory gives the module
(its build identity, such as `module-sources`):

```properties
module-sources.attachment.notice=notices/module-sources/NOTICE.txt
```

The key after the prefix is any key the module's inventory knows, read by the stages as the module's own:

- **`<module>.attachment.<classifier>`** is staged beside the module's jar under that classifier:
  `<artifact>-<version>-<classifier>.<extension>` in the Maven tree, `<module>-<classifier>.<extension>` in the
  modular tree.
- **`<module>.report.<name>`** is staged with the module's reports under `stage/reports/`.

What a transform adds is its author's responsibility. A module the build does not have fails the build, and so
does a key two transforms add, or an attachment whose file name the build stages already.

What belongs to no module - an aggregated report, a site, a distribution of every module - a transform writes into
a **`project/`** folder of its own output, laid out as it sees fit. `stage` copies it as it stands into
`target/stage/project/output/`, where exporters and releasers find it with the rest, and a file two transforms
place at the same path fails the build. A transform that brings
its own SBOM, say, attaches it as `cyclonedx` once `-Djenesis.sbom.cyclonedx=false` has switched off the stock
one. An inspection reads the same inventories plus what the transforms added, and fails the build by throwing.
It writes only into its own output: an inspection that changes a file it was handed fails the build as well.

### Pinning them

These plugins belong to no module, so their pins live beside the file that names them, in
**`jenesis.plugins.pin.properties`**, one line for each module in each plugin's closure:

```properties
plugin-audit/module/build.jenesis=0.14.0 SHA-256/...
plugin-notice/module/build.jenesis=0.14.0 SHA-256/...
```

`pin` writes the file and pins every plugin of the whole project the file names, including one a setting
switches off, so a plugin that only a profile switches on is pinned all the same. The plugins run with
everything that builds, `pin` among it, so an inspection that fails stops `pin` too. This pins without running
any plugin:

```bash
java -Djenesis.project.plugins=false build/jenesis/Make.java pin
```

{% demos 56 %}

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
`plugin-<name>.properties`, or its lines of `jenesis.plugins.arguments.properties`, reach it through a public
constructor taking a `SequencedMap<String, String>` of them, in the file's order. `javac` requires every service provider to keep a public constructor without
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

The steps a plugin adds are handed their inputs as arguments. An input bound with `@<input>` arrives as the
argument `../inputs/<input>`, and a transform or an inspection finds each module's inventory as an
`inventory.properties` in the folders of its arguments:

```java
BuildStepArgument legal = arguments.get("../inputs/legal");
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

The plugins of the whole project are a value of the project rather than of the assembler: `plugins()`
answers the `ProjectPlugins` that `jenesis.plugins.properties` declared, and `preprocess(name, step)`,
`transform(name, step)`, `inspect(name, step)`, `stageTransform(name, step)`, `stageInspect(name, step)`,
`export(name, step)`, `release(name, step)` and `goal(name, step)` add one more, a
step or a module, refusing a name that is taken already. Here
`ReleaseAudit` is a `BuildStep` of the project that throws when a module's inventory lacks what every release must
carry:

```java
Project project = Project.ofEnvironment(environment, Path.of("."));
project = project.plugins(project.plugins().inspect("audit", new ReleaseAudit()));
```

A plugin that `pin` should pin also needs its `resolution()`, the part of an `InternalModule` or `ExternalModule`
that resolves the plugin's closure without building it; `ProjectPlugins` takes those by name beside the
plugins themselves.

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

{% demos 52, 53 %}

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

{% demos 57, 58 %}

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

{% demos 59 %}

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

{% demos 60 %}

