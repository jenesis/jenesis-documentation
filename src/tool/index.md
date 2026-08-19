---
order: 1
title: Introduction
description: What Jenesis is, the problem it solves, and the path through the chapters.
---

**Jenesis is a build tool for Java, written in Java.** A build is an ordinary Java program - you
configure it by writing code against a small API, not by learning a new markup language, and you run it
with the JDK you already have. There is no plugin ecosystem to install: a build is composed from steps
that are just objects you can read, extend, and test.

Its companion tool **jpx** - resolving and running a published module's main class the way `npx` runs
a package - is a command of its own with [its own section](/jpx/).

## Why another build tool

Two convictions shape everything here:

- **Configuration is code.** A build is expressed in `Project.java`, a normal Java file the JDK launches
  directly. You get types, an IDE, and refactoring for your build the same as for your application.
- **The Java Module System is a feature, not a footnote.** `module-info.java` drives the build: Jenesis reads
  your declared modules, resolves the module path, and carries a real module graph all the way through to
  packaging - instead of flattening it into a class path and hoping.

<div class="tip">
  New to Jenesis? Read this page, then <strong>Getting started</strong> to install it and run your first
  build. Every later chapter assumes only what came before it. Prefer to learn by example? Every feature has a
  runnable project in <a href="/tool/demos/">Demos</a>.
</div>

## What's in this section

The chapters build up from zero knowledge:

1. **Introduction** - you are here.
2. **Getting started** - install via SDKMAN, build an example, and read the `Project.java` model.
3. **Core concepts** - build steps, the build graph, layouts, and the module-system specifics.
4. **Configuration** - `jenesis.properties`, per-module configuration, and profiles.
5. **Building & running** - compile, annotation processing, test, `Execute`, agents, and watch mode.
6. **Dependencies** - resolution, module-name lookup, exclusions, and module aliases.
7. **Pinning & bills of materials** - exact versions and checksums in your sources, shared and enforced.
8. **Code quality & testing** - formatting, coverage, test selection, and mutation testing.
9. **Other JVM languages** - Kotlin, Scala, and Groovy.
10. **Supply-chain features** - SBOM, dependency licensing, and vulnerability scanning.
11. **Packaging** - executables, bundles, jlink/jpackage, container contexts, native images, launcher jars.
12. **Publishing** - staging a release bundle, publishing it, and driving a release tool.
13. **Build performance & isolation** - Docker isolation and the build cache.
14. **Extending the build** - custom assemblers and build definitions.
15. **Reference** - the command line, configuration keys, and the built-in steps.
16. **Demos** - a runnable example project for every feature.
