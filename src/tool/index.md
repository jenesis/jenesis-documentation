---
order: 1
title: Introduction
description: What Jenesis is, the problem it solves, and the path through the chapters.
---

**Jenesis is a build tool for Java, written in Java.** Most projects need no build script at all. What a
project already declares - its source layout, the dependencies it names, a `module-info.java` where it has
one - is what the build is inferred from, so `java build/jenesis/Make.java` compiles, tests and packages it
with the JDK you already have and nothing else installed. Where a convention does not cover what a project needs, the
extension is a small Java function or module describing one step, read, tested and refactored like the rest
of your code.

A project does not have to be modular to be built. Jenesis reads a `pom.xml` as the description of what to
build, which is the quickest way to try it on a project you already have, and the way to keep building one
that is not ready for the Java Module System yet.

## Why another build tool

Two convictions shape everything here:

- **Convention first, Java where it runs out.** There is no build language to learn and no plugin ecosystem
  to install. What a convention cannot express is a few lines of Java, launched by the JDK directly with
  `java build/jenesis/Make.java`, so the build that does need code gets types, an IDE and refactoring, the
  same as your application.
- **The Java Module System is a feature, never a requirement.** A `module-info.java` already describes a
  module - what it is called, what it requires, what it exports - so Jenesis reads the one a project has
  rather than asking for a second descriptor to keep in sync with it. Where a project declares modules they
  drive the build, resolving dependencies, filling the module path and carrying a real module graph through
  to packaging instead of flattening it into a class path. Where a project declares none, nothing is asked
  of it: its jars resolve by coordinate and compile on the class path, and every chapter here applies the
  same.

And three properties are built in rather than added on:

- **Incremental.** Each step is keyed by its inputs, so a second build redoes only what changed, and a
  shared cache extends that across machines.
- **Reproducible.** The same sources produce the same bytes, on every machine and in CI, checked against a
  digest the project records.
- **A supply chain that is accounted for.** Dependencies can be pinned to a version and a checksum, verified
  against OpenPGP signatures or Sigstore identities, held to a licence policy, checked against known
  vulnerabilities, and described in an SBOM the build emits.

<div class="tip">
  New to Jenesis? Read this page, then <strong>Getting started</strong> to install it and run your first
  build. Every later chapter assumes only what came before it. Prefer to learn by example? Every feature has a
  runnable project in <a href="/tool/demos/">Demos</a>.
</div>

## What's in this section

The chapters build up from zero knowledge:

1. **Introduction** - you are here.
2. **Getting started** - install Jenesis, build an example, and read the `Project` model.
3. **Core concepts** - build steps, the build graph, layouts, and the module-system specifics.
4. **Configuration** - `jenesis.properties`, per-module configuration, and profiles.
5. **Building & running** - compile, test, annotation processing, `Execute`, agents, and watch mode.
6. **Dependencies** - resolution, module-name lookup, exclusions, and module aliases.
7. **Pinning & bills of materials** - exact versions and checksums in your sources, shared and enforced.
8. **Code quality & testing** - formatting, coverage, test selection, and mutation testing.
9. **Generating sources** - compiling a schema or a service contract into Java as part of the build.
10. **Other JVM languages** - Kotlin, Scala, and Groovy.
11. **Supply-chain features** - SBOM, dependency licensing, and vulnerability scanning.
12. **Packaging** - executables, bundles, jlink/jpackage, container contexts, native images, launcher jars.
13. **Publishing** - staging a release bundle, publishing it, and driving a release tool.
14. **Build performance & isolation** - Docker isolation and the build cache.
15. **Extending the build** - custom assemblers and build definitions.
16. **Reference** - the command line, configuration keys, and the built-in steps.
17. **Demos** - a runnable example project for every feature.
