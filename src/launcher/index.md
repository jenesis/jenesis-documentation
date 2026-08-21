---
order: 1
title: Introduction
description: What the Jenesis Launcher is, the problem it solves, and when a launcher jar is the right way to ship.
---

**The Jenesis Launcher turns a modular application into a single executable jar - without giving up its
module graph.** You run the jar with `java -jar app.jar`. The launcher then rebuilds, in process, what
`java -p modulepath -cp classpath -m module/main` would have set up: modular dependencies become real named
modules in a fresh `ModuleLayer`, and plain jars become the unnamed module of the same loader.

## The problem it solves

The usual single-jar answer is a **fat jar**: a tool such as Maven Shade unpacks every dependency and merges
all the classes into one flat jar. The merge is what costs you the modules. Every `module-info.class` lands at
the same path, `META-INF/services` files collide unless a transformer is configured to merge them, and at run
time there is no module graph left to rebuild.

A launcher jar keeps each dependency in a subfolder of its own instead - `modulepath/<jar>/…` for a module,
`classpath/<jar>/…` for a plain jar. Nothing collides: each dependency keeps its own descriptor, service files
and resources, and the launcher reads a class straight out of the outer jar when it is first needed. The
dependencies' class bytes are never copied into memory or unpacked to disk.
*[Comparison with a fat jar](/launcher/comparison-with-a-fat-jar/)* sets the two approaches side by side.

## When to use it

A launcher jar is the right form when you want **one file that runs on any Java 25 or newer** with nothing
installed beside it: a command-line tool, a service started with a plain `java -jar`, an artifact you hand to
someone else. It carries no Java runtime of its own. When the runtime should travel with the program, the
build tool's jpackage image and native image are the alternatives; its
[Packaging chapter](/tool/packaging/) compares the forms.

## What it is

The launcher is a small library, published to Maven Central as `build.jenesis:build.jenesis.launcher` and
compiled for Java 25. You never call it yourself. The Jenesis build tool resolves it, copies its classes into
the jar it produces, and names it as that jar's `Main-Class`. A single `launcher=true` line in
`packaging.properties` is the whole switch - *[Producing a launcher jar](/launcher/producing-a-launcher-jar/)*
shows it.

<div class="note">
  This section assumes the build tool's packaging basics: a module with a declared main class and a
  <code>packaging.properties</code> file in a configuration folder. If that is new to you, read the build
  tool's <a href="/tool/packaging/">Packaging chapter</a> first.
</div>

## What's in this section

1. **Introduction** - you are here.
2. **How it works** - the jar layout, the start-up sequence, one loader for named and unnamed modules, and
   reading on demand.
3. **Producing a launcher jar** - the `launcher=true` switch, what the build writes, where the jar lands, and
   how the launcher is pinned.
4. **Running & troubleshooting** - starting a launcher jar, what the single loader means for your code, and
   the pitfalls.
5. **Comparison with a fat jar** - what flattening destroys and what a launcher jar keeps.
6. **Reference** - every descriptor key and manifest attribute the launcher reads, and which of them the
   build tool writes.
