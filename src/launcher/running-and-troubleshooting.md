---
order: 4
title: Running & troubleshooting
description: How to start a launcher jar, the consequences of its single class loader, the start-up errors you may meet, and the handful of run-time pitfalls to know before you ship one.
---

A launcher jar runs like any other executable jar. But because it reconstructs the module graph in process
rather than merging everything flat, a few of its behaviours differ from a plain application on a real class
path and module path. This chapter shows how to start one, what the single loader means for your code, and
the pitfalls worth knowing before you ship.

## Running a launcher jar

The jar names the launcher as its `Main-Class`, so you start it exactly as any executable jar:

```bash
java -jar app.jar [args...]
```

The launcher finds itself, reads `application.properties`, rebuilds the loader and module layer, and invokes
your real main class - the sequence covered in [*How it works*](/launcher/how-it-works/). Your arguments pass
straight through to `main`. Anything the launcher cannot resolve surfaces before `main` runs, as an exception
with a stack trace and exit code 1 - the same way a bad `java -p … -m …` command line fails.

## What the single loader means for your code

The launcher hosts both the named modules and the class path on **one** loader, exactly as `java -p
modulepath -cp classpath` does. That fidelity is deliberate, and it carries the JDK's own rules, which
occasionally surprise people coming from a fat jar:

- **An automatic module can read the class path; a strict named module cannot.** A dependency with a real
  `module-info` sees only what it `requires`. If it needs a type that lives on the class path, that read does
  not exist - just as it would not under a real module path. The fix is not to relax the layer but to give
  the class-path jar a name: declare a [module alias](/tool/dependencies/) for it, and it joins the module
  path as an automatic module the strict module can `requires`.
- **A package owned by a module shadows the same package on the class path.** When a bundled module and a
  class-path jar both contain package `com.foo`, the module's classes win and the class-path copy is hidden.
  Split packages resolve the JDK's way, not first-jar-wins.

<div class="note">
  These are not launcher quirks - they are what a faithful <code>java -p … -cp …</code> launch does. If your
  application relies on a strict module reaching class-path code, or on a split package resolving by class-path
  order, it was relying on fat-jar behaviour that a real module path never had.
</div>

## Start-up failures

A start-up failure is visible immediately, before your `main` runs. These are the messages the launcher
itself raises, and what each means:

| Message | Cause and fix |
| --- | --- |
| `No 'mainClass' declared in application.properties of …` | The descriptor has no entry point. A build-produced jar always has one; a hand-assembled jar is missing the key. |
| `Main module not found on the module path: <name>` | `mainModule` names a module that no `modulepath/` subfolder provides, or the jar that provides it derives a different name. |
| `Two bundled modules resolve to the same name: <name>` | Two `modulepath/` jars declare or derive the same module name - typically two versions of one library. A module path can carry a name only once; drop one. |
| `… is aliased as both <a> and <b>` | Two `Jenesis-Aliases` declarations claim one jar. A jar can carry one module name. |

One further failure comes from the JVM rather than the launcher. **A bundled module `requires` a JDK module
that is not resolved by default** - `jdk.incubator.*`, or a module reachable only through qualified exports.
The child layer is bound against the boot layer, and the boot layer contains only what the JVM resolved at
start-up, so the bundled module fails to resolve. Augment the boot layer from the command line:

```bash
java --add-modules jdk.incubator.vector -jar app.jar
```

<div class="warning">
  There is no in-jar way to pull in a JDK module that is not resolved by default. The boot layer is immutable,
  and the jar's module graph is fixed to the bundled modules plus the default boot modules, so an
  <code>--add-modules</code> flag at launch is the only way.
</div>

## Run-time pitfalls

The rest of the launcher's boundaries surface only at run time, and only for applications that do specific
things. Most launcher jars never touch them.

### Native libraries

A JNI library cannot be loaded straight from a jar, so the launcher extracts a requested library to a temp
file on demand and loads it from there. Two consequences follow:

- The temp file is deleted on a **normal** exit, but **leaks on an abrupt kill** (`kill -9`, a crash).
- A library that finds a *sibling* library by co-location - rather than through `java.library.path` - will
  not find it, because each library lands in its own temp file. Keep multi-file native bundles
  self-contained.

When two jars carry the same library, the class-path jars are searched first, in class-path order, then the
bundled modules; the first match wins.

### "Open my own jar file"

A class the launcher loads has a `CodeSource` whose location points **inside** the outer jar (for example
`jar:file:/…/app.jar!/classpath/dep.jar/`), so `Package.getImplementationVersion`, sealed packages, and
`getProtectionDomain().getCodeSource()` all report correctly. But a dependency is *not* a standalone jar on
disk, so the "open my own jar file and read its entries" idiom fails. Code that walks its own jar as a file
needs another approach.

### Resources in a non-open module package

A resource inside a package of a bundled module stays encapsulated unless that package is opened
**unconditionally** - by an `open module`, an automatic module, or an unqualified `opens`. Only then does
`contextClassLoader.getResourceAsStream("some/module/internal.txt")` find it; a qualified `opens` does not
widen the flat `getResource` API. That is exactly how a real `java -p … -cp …` launch encapsulates it.
Resources in no package (top-level entries, anything under `META-INF/`) and class-path resources are
always served.

### Directory entries are not resources

Only file entries are indexed, so `getResource("com/foo/")` for a package or directory returns `null`, where
a real exploded-directory class loader would hand back a directory URL. Class loading and file-resource
lookups are unaffected - this only bites code that enumerates a directory URL.

### The jar stays open

Reading on demand means the outer jar (a `ZipFile`), plus a cached `JarFile` once resource URLs are opened,
stays **open for the application's lifetime** - the trade for never holding the dependencies' bytes in the
heap. Under `java -jar` that is exactly right and needs no action.

It matters only when you embed the launcher in a program of your own. The public entry point is
`Launcher.run(Path, String[])`, which takes a jar or an exploded directory of the same layout and runs its
`main` in the current JVM. The loader it builds lives as long as the application it hosts; if you start
several in one process, expect one open handle per launch.

<div class="tip">
  JAR signatures are <strong>not cryptographically re-verified</strong>: a signed dependency's signature files
  are exploded as ordinary entries. A hand-assembled jar can record a class-path dependency's signer
  <em>identity</em> so <code>CodeSource.getCodeSigners</code> reports it, but that attests rather than
  re-verifies; see the <em>Reference</em> chapter for the descriptor key.
</div>
