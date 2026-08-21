---
order: 5
title: Comparison with a fat jar
description: What flattening every dependency into one jar destroys - colliding module-info files, merged service files, and the lost module graph - set against the launcher jar's subfolders, fairly.
---

The usual way to ship a single runnable jar is a **fat jar** (or *uber jar*): a tool such as Maven Shade or
Gradle Shadow unpacks every dependency and merges all their class files into one **flat** jar. It runs with
`java -jar`, which is the appeal - but the flattening throws away exactly what Jenesis treats as a feature.
This chapter sets the two approaches side by side, so you can see what a launcher jar keeps that a fat jar
loses, and the one thing a fat jar can do that a launcher jar will not.

Both approaches explode their dependencies. The difference is *where the bytes land*: a fat jar merges them
into one namespace; a launcher jar gives each dependency [its own subfolder](/launcher/how-it-works/). Three
things follow from that single choice.

## `module-info` files collide

Every modular dependency carries a `module-info.class` at its jar root. Merge two of them into one flat jar
and they land at the **same path** - `module-info.class` can only exist once. The merging tool can keep one,
drop them all, or rename them into something the Java Module System no longer reads. Either way the
dependencies stop being modules: their descriptors are gone, so nothing at run time knows what each one
`requires`, `exports`, or `opens`.

A launcher jar never merges. Each dependency keeps its own `module-info.class` inside its own
`modulepath/<jar>/` subfolder, so every descriptor survives intact and is read back at start-up.

## `META-INF/services` must be merged

Service files are the other casualty of a flat namespace. Two dependencies that each provide, say, a
`java.sql.Driver` both ship `META-INF/services/java.sql.Driver` - again the *same path*. A plain merge keeps
one file, warns about the overlap, and drops the other's providers, so a `ServiceLoader` lookup that used to
find both now finds one. Fat-jar tooling solves this with a **resource transformer** (Shade's
`ServicesResourceTransformer`, Shadow's `mergeServiceFiles()`) that concatenates colliding service files.
It works well - but it is a step you have to know to configure, and other colliding resources need
transformers of their own.

Because a launcher jar keeps each dependency in its own subfolder, no two service files share a path.
Nothing is merged, nothing is dropped, and there is no transformer to configure: every provider file stays
where its dependency put it, and `ServiceLoader` sees them all.

## The module graph is lost

The deepest loss is the one no transformer can patch. Once every class sits in one flat namespace with the
descriptors gone, there is **no way to reconstruct a module graph at run time**. A fat jar runs as one big
class path: encapsulation is gone, `requires` edges are gone, strong module boundaries are gone. Modular
libraries silently degrade to running as unnamed-module code.

A launcher jar rebuilds the graph instead. At start-up it resolves the `modulepath/` subfolders into a fresh
`ModuleLayer`, so the modules come back as **real named modules** with their `requires` and `exports` edges
enforced - the faithful equivalent of a real `-p modulepath`. Non-modular dependencies become the unnamed
module of the same loader, the analogue of `-cp classpath`.

## What a fat jar can do that a launcher jar will not

Shading proper - **relocating** packages by rewriting class files - lets a fat jar carry two versions of the
same library side by side, each under a renamed package. A launcher jar keeps every class exactly as it was
compiled and every module under its declared name, so two versions of one module are an error at start-up
rather than something it reconciles. If you depend on relocation to resolve a version conflict, resolve it
in the build instead: the build tool's [dependency negotiation](/tool/dependencies/) picks one version, and
an exclusion prunes the other.

## Side by side

The two jars run the same way - `java -jar app.jar` - but rebuild very different worlds:

| | Fat jar (flat merge) | Launcher jar (subfolders) |
| --- | --- | --- |
| Dependency layout | merged into one namespace | each in its own `classpath/` or `modulepath/` subfolder |
| `module-info.class` | collides - kept once, dropped or renamed | kept, one per module subfolder |
| `META-INF/services` | collides - needs a merge transformer | kept, no merge needed |
| Module graph at run time | gone; everything is one class path | reconstructed into a real `ModuleLayer` |
| Class files | as compiled, or rewritten when relocated | as compiled, always |
| Two versions of one library | possible, by relocation | refused - one version per module name |

<div class="note">
  A launcher jar is not a fat jar with the rough edges filed off - it is a different reconstruction. Where a
  fat jar flattens the module system to fit one namespace, the launcher preserves each dependency whole and
  rebuilds, in process, exactly what <code>java -p modulepath -cp classpath -m module/main</code> would have
  done. See <a href="/launcher/how-it-works/"><em>How it works</em></a> for that reconstruction in detail.
</div>

Choosing a launcher jar therefore keeps your application exactly as the build resolved it: the module graph,
the service files, and each dependency's identity all survive into the shipped artifact, and non-modular
dependencies ride along as openly as they would on a real class path.
