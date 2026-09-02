---
order: 3
title: Core concepts
description: Build steps, the build graph, the layouts that shape a project into one, and how Jenesis decides what to rebuild.
---

*[Getting started](/tool/getting-started/)* ran a build and toured `Project.java`. This chapter opens the box:
what a build actually *is*, how Jenesis shapes your project into one, and the rule that decides on every
run what recompiles and what is reused. Three ideas, and everything later in this section rests on them.

## A build is a graph of steps

Under the hood a Jenesis build is nothing more than a **graph of steps**. Each step takes one or more input
folders and produces one fresh output folder; a step downstream reads the folders its predecessors produced.
Compiling, packaging a jar, generating docs, resolving dependencies - each is a step, and the edges between
them are "this step's output is that step's input".

That is the whole model. There is no phase lifecycle to memorise and no plugin to bind into it: a build is
just steps wired to steps, and the engine walks them in dependency order.

### The build step

A single step is a **pure function of its input folders**. It reads files at well-known paths inside each
input - `sources/` for Java sources, `classes/` for compiled output, `artifacts/` for produced jars - and
writes its own output into one new folder. It never edits an input in place and never reaches outside the
folders it was handed.

Those folder names are conventions the built-in steps share, so steps compose without knowing how they were
wired together. The compile step, for example, reads each predecessor's `sources/` and writes `classes/`; the
jar step then reads `classes/` and writes `artifacts/classes.jar`. You will meet the individual steps in
later chapters. Here the point is only their shape: **folders in, a fresh folder out.**

<div class="note">
  Because every step writes a <em>new</em> output folder rather than mutating its inputs, the whole build tree
  is reproducible and safe to cache - the property the incremental engine at the end of this chapter is built
  on.
</div>

### The build graph and modules

Real projects have more than one line of steps, so the graph is organised into **modules**. A module is a
named subgraph - typically one compilable unit: its compile, test, jar, and documentation steps grouped under
one name. A multi-module project is a graph of these subgraphs, and Jenesis builds them in dependency order,
so a library module is built before the application module that depends on it.

The engine that owns and walks the graph collects every registered step and module, works out the order
from their declared inputs, and runs each one, reusing a cached output when it can (the last section of this
chapter). The same engine drives one level of the graph and each nested module, so a build of one module and
a build of fifty are the same machinery at different scales.

### Selectors: choosing what to run

*Getting started* showed that a positional argument after `Project.java` is a **selector**, and that with none
the default target (`build`) runs. A selector is really a path through the graph. Two things make that precise:

- A `+<module>` selector builds one module's subtree. `+greeter` builds the `greeter` module and whatever it
  depends on, and nothing unrelated. The name after `+` is the module's **folder** name. In a modular
  project the tests live in a separate module, which the next chapters show how to write. So `+greeter` runs
  *no* tests; you select the test module by its own folder, `+greeter-test`.
- Under the hood every selector is a slash-delimited path of `module/step` identities, with two wildcards:
  `:` matches a single path segment, and `::` matches any depth. So `::/jar` runs the `jar` step of every
  module wherever it sits in the tree.

```bash
java build/jenesis/Project.java +greeter        # one module's subtree
java build/jenesis/Project.java '::/test'        # the test step of every module
```

Wildcards are **lenient**: a branch that does not match is silently skipped. A *literal* path that does not
resolve fails the build with `Unknown selector: …`, so a typo in a name you spelled out is caught rather than
quietly doing nothing. Prefer literal paths when you know them. A module in a nested folder takes one `+`
per folder segment: the module in `foo/bar` is selected as `+foo+bar`.

## Layouts: how your project is shaped

A **layout** is what turns *your* directory of sources into that graph. It decides how modules are discovered,
how their dependencies resolve, and what artifacts come out. You met it as the `layout` field; here are the
four values in full.

`auto` (the default) inspects the project root and picks one of the concrete layouts for you:

| Layout | Input | Dependency resolution | Output |
| --- | --- | --- | --- |
| `maven` | a root `pom.xml` | Maven coordinates, from the POM | classic jar **+ `pom.xml`** |
| `modular_to_maven` | a `module-info.java`, no root `pom.xml` | each `requires` translated to a Maven coordinate | modular jar **+ generated `pom.xml`** |
| `modular` | a `module-info.java` (opt-in only) | purely by Java module name | modular jar, **no `pom.xml`** |

`auto` resolves to `maven` when it finds a root `pom.xml`, and otherwise to `modular_to_maven` when it finds a
`module-info.java`. It never chooses `modular` for you - you ask for it explicitly.

<div class="note">
  Discovery walks the project tree, so a repository that holds more than one project needs a way to say where
  one stops. An empty <strong><code>.jenesis.skip</code></strong> file marks a subtree as none of this build's
  business - the scan does not descend into it. That is how a sample project, a build plugin, or a vendored build
  can sit inside a repository without being built as part of it.
</div>

### maven vs. the two modular layouts

`maven` is the classic path: Jenesis reads the declarative parts of your `pom.xml` (coordinates, dependencies,
source folders) and builds one module per POM, emitting an ordinary jar plus its POM.

The two modular layouts both take a `module-info.java` and both produce a genuine modular jar. They differ in
how a `requires` is satisfied:

- **`modular_to_maven`** translates each `requires` into the declaring module's **Maven coordinate**, then
  resolves the transitive closure through Maven - nearest-wins versions and Maven scopes, exactly as if your
  project had listed those coordinates in a `pom.xml`. It emits the modular jar **plus a generated `pom.xml`**,
  so the artifact is publishable to Maven Central and consumable by Maven projects. Because it reaches
  dependencies by coordinate, it can also pull in plain class-path and *automatic*-module libraries.
- **`modular`** resolves dependencies **purely by Java module name** through the Jenesis Module Index, with
  no Maven coordinates anywhere, and emits **only the modular jar - no `pom.xml`**. Every dependency resolved
  this way is a named module, so the closure is provably consumable on the module path.

That difference is why `auto` picks `modular_to_maven`: reaching dependencies by coordinate makes it open to
everything already published, including a library that carries no module name of its own. `modular` is the
layout for a project whose whole closure is already modular. It guarantees that every dependency is a named
module and that no Maven coordinate appears anywhere, so it is a statement about the project, and you make it
deliberately rather than having it made for you.

You can force a layout for one run with a system property, or record it in a project file (covered in
*[Configuration](/tool/configuration/)*):

```bash
java -Djenesis.project.layout=modular build/jenesis/Project.java
```

The property accepts `auto`, `maven`, `modular`, and `modular_to_maven`.

### Seeing the difference

The `dependencies` selector prints each module's resolved graph, and it makes the layout choice concrete. The
same `requires org.slf4j` shows up two ways. Under `modular` it is a Java module name resolved through the
module index:

```
main/compile (module-sources)
module/org.slf4j 2.0.16 (module org.slf4j)
```

Under `modular_to_maven` it is translated to a Maven coordinate and resolved through Maven, so it carries a
Maven scope and expands the full nearest-wins Maven closure:

```
main/compile (module-sources)
maven/org.slf4j/slf4j-api 2.0.16 [compile] (module org.slf4j)
```

## Incremental change detection

The last core concept is the one you feel on every run: Jenesis only redoes work that actually changed. In
*Getting started* a second build recompiled nothing. Here is the rule behind that.

Every step's output is cached, keyed by a content hash. A step is **reused** only when three things all match
what the previous run recorded:

1. its **input checksums** - the bytes its predecessors produced;
2. its own **output folder** - re-hashed, so a tampered-with output is detected; and
3. its **configuration hash** - a digest of the step's own *serialised form*.

That third point is the one to internalise. Jenesis hashes each step's **serialised state**, not just its
inputs. So a step re-runs when its inputs change **or when its own configuration changes**: editing a knob on
a step (say a test filter) alters its serialised form, its hash changes, and it re-runs, even though not one
input byte moved.

<div class="note">
  For the built-in steps this is invisible - they are written so that every knob worth rebuilding for is part
  of that serialised state. It becomes a rule you have to respect only when you write a step of your own,
  which <em>Extending the build</em> covers in full.
</div>

Selectors are deliberately *not* part of the hash - they only gate which steps get scheduled. So a step that
runs under a selector produces exactly the output a full build would have, and a later unselected run hits the
cache as expected.

<div class="tip">
  Two runnable projects show this chapter end to end:
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-04-java-modular-multi">demo-04</a> builds a
  multi-module modular project and prints its module graph, and
  <a href="https://github.com/jenesis/jenesis/tree/main/demo/demo-32-module-layout">demo-32</a> is a
  single-module project under the pure <code>modular</code> layout. See <a href="/tool/demos/">Demos</a>.
</div>
