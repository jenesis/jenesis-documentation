---
order: 14
title: Extending the build
description: Write your own build step, add it to the stock pipeline through a custom assembler, or wire the whole graph by hand - and the serialised-state rule a custom step must respect.
---

Every chapter so far drove the stock pipeline: a layout auto-detects your modules, the default assembler
wires the conventional compile/jar/test flow, and you configure it by choosing among the options it offers.
This chapter is for the build that needs something the templates *do not* model - a preprocessing pass, a
code-generation step, a bespoke packaging step, an unusual dependency wiring.

There are three levels of control, from least to most custom: wrap the stock assembler, drive the toolchain
from your own entry point, or wire the graph by hand. A fourth question is where an extension lives once more
than one project wants it. All of them share one primitive, the build step, so start there.

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

<div class="note">
  Treat a step as a <strong>pure function of its input folders</strong>: read from the argument folders, write
  to <code>next</code>, reach outside neither. That is what makes its output cacheable and safe to share
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

## Adding a step to the stock pipeline

The lightest way to extend a build is to keep the whole stock toolchain and **wrap the assembler** - the
callback that wires each module's compile/jar/test sub-graph. You drop a `.java` file next to `Project.java`
and pass your wrapper to `Project`. This one interposes a `sign` step after the stock build:

```java
MultiProjectAssembler<ProjectModuleDescriptor> base = new InferredMultiProjectAssembler();
MultiProjectAssembler<ProjectModuleDescriptor> withSign = (descriptor, repos, resolvers) ->
        base.apply(descriptor, repos, resolvers).mapBuild(delegate -> (sub, inherited) -> {
            sub.addModule("assemble", delegate, inherited.sequencedKeySet().stream());
            sub.addStep("sign", new Sign(), "assemble"); // Sign is your BuildStep
        });

new Project().assembler(withSign).build(args);
```

`apply` returns the module's build description; `mapBuild` decorates only its build phase - here registering
the stock output under `assemble` and chaining a `sign` step onto it. Wrappers compose freely: stack several
(sign, stamp licence headers, emit checksums) without ever reimplementing the Java toolchain.

### Redirecting a module's inputs

A wrapper can also change *what* the stock steps consume, because the module descriptor is immutable with a
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

## Packaging the extension as a plugin

A wrapper written next to `Project.java` belongs to one project. When the same pass - a code generator, a
source preprocessor - should serve several, package it as a **build module**: a named Java module that
`provides` a build-executor service, which Jenesis discovers through that declaration alone.

A build module comes from one of two places, and nothing else about it differs:

- an **internal** build module is compiled from local source in its own project folder, and
- an **external** build module is resolved from a repository coordinate, like any published artifact.

Either way you wire it in from an assembler wrapper, exactly like the `sign` step above, by adding it as a
module that the stock steps then read from. An internal module names its source folder; an external one
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

## Reusing the toolchain from your own entry point

When you want your own `main` but still the stock compile/jar/test flow, skip `Project` and call the
convenience factory `MavenProject.make` (or `ModularProject.make` for a Java Module System project). It
discovers the modules under a root, fills in sane defaults - a Maven Central repository, the right resolver, a
digest - and leaves only the assembler for you to supply:

```java
BuildExecutor root = BuildExecutor.of(Path.of("target"));
root.addModule("maven", MavenProject.make(Path.of("."),
        (descriptor, repositories, resolvers) -> new InferredMultiProjectAssembler().apply(
                new ProjectModuleDescriptor(
                        descriptor,                              // the discovered module
                        new LinkedHashSet<>(List.of(Path.of("."))), // its configuration folders
                        true,                                    // run its tests
                        false,                                   // no sources jar
                        false,                                   // no javadoc jar
                        null,                                    // pinning: lenient (or Pinning.STRICT, VERSIONS, IGNORE)
                        PathPlacement.CLASS_PATH),               // place dependencies on the class path
                repositories, resolvers)));
root.execute(args);
```

This is a middle ground: no layout, no goals, no `Project`, yet you did not wire every step by hand either.
`ModularProject.make` is the modular counterpart; its convenience form builds pure modules (a modular jar,
no generated POM). For full control - a custom repository, strict pinning, a different digest, or emitting a
POM as well - switch to the longer `make(...)` overload that `Project` itself uses.

## Wiring the graph by hand

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

<div class="tip">
  Six runnable projects cover this chapter:
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-35-custom-assembler">demo-35</a> wraps the
  assembler to preprocess sources before they compile,
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-37-internal-module">demo-37</a> and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-38-external-module">demo-38</a> move that
  same pass into a build module - one compiled from local source, one resolved as a published coordinate,
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-39-custom-maven">demo-39</a> and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-40-custom-modular">demo-40</a> drive a
  multi-module Maven and modular build from a convenience <code>make</code>, and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-41-custom-build">demo-41</a> wires a
  code-generating graph entirely by hand on the <code>BuildExecutor</code> API. See
  <a href="/tool/demos/">Demos</a>.
</div>
