---
order: 2
title: How it works
description: The layout of a launcher jar, the start-up sequence that rebuilds the module layer from it, the single loader behind named and unnamed modules, and how classes are read on demand.
---

The *Introduction* said the launcher reconstructs, in process, what `java -p modulepath -cp classpath -m
module/main` would have done. This chapter shows how: the shape of the jar it reads, the sequence it runs at
start-up, the one class loader it builds, and how it serves classes and resources without holding their
bytes.

## The executable-jar layout

A launcher jar is an ordinary jar whose `Main-Class` is the launcher, plus a fixed set of entries the
launcher knows how to read:

```
app.jar
├── META-INF/MANIFEST.MF                          Main-Class: build.jenesis.launcher.Launcher
├── build/jenesis/launcher/…                      the launcher's own classes
├── application.properties                        the descriptor: mainClass, mainModule, classpath
├── modulepath/
│   ├── classes.jar/…                             the application's own module, exploded
│   └── org.slf4j-2.0.16.jar/…                    a modular or automatic dependency, exploded
└── classpath/
    └── <group>%2F<artifact>%2F<version>.jar/…    a dependency that names no module, exploded
```

Each dependency is **exploded into its own subfolder**, so nothing is merged: every dependency keeps its own
`module-info`, `META-INF/services` files and resources. And because each class is then a **direct entry of
the outer jar**, the launcher can read it later with a plain `java.util.zip.ZipFile` - there is no nested-jar
addressing.

The subfolder name is the file name the dependency had when the build resolved it. The Jenesis build tool
names a resolved jar after the module it carries, at the version the closure resolved
(`org.slf4j-2.0.16.jar`), names an aliased jar `<alias>-<version>.jar`, keeps the application's own module as
`classes.jar`, and falls back to the URL-encoded coordinate (`<group>%2F<artifact>%2F<version>.jar`) for a jar
that declares no module at all. The name follows what the jar declares, not where it lands: a jar with an
`Automatic-Module-Name` is named for that module even when it goes on the class path. A jar goes under
`modulepath/` when the application is modular and the jar describes a module; everything else goes under
`classpath/`. A non-modular application therefore has every dependency under `classpath/` and no module
layer at all.

### The descriptor

`application.properties` is the small text file that tells the launcher what to run. The build tool writes
three keys:

| Key | Meaning |
| --- | --- |
| `mainClass` | the fully qualified class whose `main` is invoked |
| `mainModule` | the module owning `mainClass`, when the application is modular |
| `classpath` | the class-path subfolders in the order the launcher should search them |

The launcher understands a few more - bundled agents, module-access grants, and signer reconstruction -
which are for a jar you assemble yourself. The [*Reference*](/launcher/reference/) chapter lists them all.

## How a launch proceeds

Running `java -jar app.jar` starts the launcher's `main`, which then:

1. **finds itself** - it locates the running jar from its own `CodeSource` and opens it. A packaged jar and
   an exploded directory of the same layout both work.
2. **reads the descriptor and indexes the entries** - it loads `application.properties` and records the
   *entry names* under each `classpath/<jar>/` and `modulepath/<jar>/` subfolder. It also reads each
   dependency's manifest, and for a module-path jar its `module-info.class` and `META-INF/services` files,
   since those describe the module. Class bytes are not read here.
3. **builds one class loader** over the `classpath/` subfolders. This loader's unnamed module is the analogue
   of everything a `-cp` class path would carry. It holds no class bytes, only the index.
4. **reconstructs the module layer**, if there are `modulepath/` jars. An in-memory module finder resolves
   them and defines a **child `ModuleLayer`** against the boot layer, mapping every module to that *same*
   loader. When a `mainModule` is declared, the layer grants the launcher access to the main class's
   package, so `main` runs even if the package is not exported - exactly as `java -m module/Class` allows.
5. **invokes `main`** - it sets the thread context class loader, runs any bundled agents, and calls the main
   method.

### Which modules are resolved

The module layer is resolved the way `java -m <mainModule>` resolves it: the main module is the root, and its
`requires` closure is pulled in, services included. That works only for a **self-contained** graph - a
modular main module over a module path of explicit named modules, with nothing on the class path.

An automatic module breaks that, because it declares no `requires`, so a named module it uses only
internally would never be resolved. A class path breaks it too. In either case the launcher roots *every*
bundled module instead, the in-jar equivalent of `--add-modules ALL-MODULE-PATH`. You never configure this;
the launcher decides from what the jar contains.

## One loader, two kinds of module

The reconstruction rebuilds a real module graph, but it deliberately uses a **single class loader** for
everything: the named modules in the child layer and the unnamed module over the class path. That is the
arrangement one application loader has under `java -p modulepath -cp classpath`, and it makes the launcher
faithful to the JDK's own rules:

- an **automatic module can read the class path**, while a **strict named module cannot**;
- a package **owned by a module shadows** the same package on the class path.

The in-memory module finder builds a descriptor for each `modulepath/` jar: from its `module-info.class`, or
derived for an automatic module from its `Automatic-Module-Name` or its file name, with the providers in
`META-INF/services` scanned in. A version behind the first dash in the file name is derived too, exactly as a
module path derives it, so a bundled automatic module reports the identity it would report under `java -p` -
in `Module::getDescriptor` and in stack traces alike. The boot layer is immutable, so a fresh child layer is the only way to add
modules at run time - and the right one, because they stay real named modules. What these rules mean in
practice is the subject of [*Running & troubleshooting*](/launcher/running-and-troubleshooting/).

### A jar that names no module

A dependency that declares neither a `module-info` nor an `Automatic-Module-Name` has no name to derive. The
build tool gives such a jar a name through a [module alias](/tool/dependencies/), and it renames the
resolved file to `<alias>-<version>.jar` before packaging. Inside the launcher jar the subfolder is then
`modulepath/<alias>-<version>.jar/`, and the automatic-module rule derives both the declared name and that
version from it. Nothing else is needed.

The launcher also understands a manifest header for a jar that kept its coordinate-encoded name. The module
that declared the alias carries, in its own manifest:

```
Jenesis-Aliases: org.kohsuke.args4j=args4j/args4j
```

Each entry maps a module name onto the `<groupId>/<artifactId>` it applies to, matched against the
coordinate in a bundled jar's file name. The launcher offers that jar as an automatic module under the
declared name, so a `requires` and a qualified `opens` naming it both resolve inside the layer. Only a jar
with no identity of its own is considered - a jar that names itself keeps its own name - and two names
claimed for one jar is an error rather than a choice the launcher makes for you.

## Reading the jar on demand

Because every class and resource is a direct entry of the outer jar, the launcher never merges anything into
memory or spills it to disk. It opens the outer jar once (a `ZipFile`) or the exploded directory, indexes the
entry names at start-up, and reads an entry's bytes **only when first needed**, discarding them afterwards.
Heap use is therefore roughly the size of the entry-name index rather than the dependencies' bytes.

Two details make this transparent to the application:

- **Resources come back as ordinary URLs.** The loader hands out standard `jar:` and `file:` URLs, so
  `ClassLoader.getResources` - and therefore `ServiceLoader` - works through the JDK's own handlers, with no
  custom URL scheme to configure.
- **Multi-release jars are honoured.** For a dependency whose manifest says `Multi-Release: true`, the
  launcher serves the highest `META-INF/versions/<n>/` entry the running JVM supports, just as the JDK does
  for a real jar.

<div class="tip">
  The one lasting cost of reading on demand is an open file handle for the process lifetime: the launcher's
  own <code>ZipFile</code> stays open while the application runs, as it must. That, and the rest of the
  launcher's boundaries, are covered in <em>Running &amp; troubleshooting</em>.
</div>
