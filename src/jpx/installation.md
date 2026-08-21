---
order: 3
title: Installation & caching
description: Where resolved targets install, what the descriptor records, and how an install stays consistent under crashes and concurrency.
---

jpx installs every resolved target once and reuses it across runs. Each target lives under:

```
~/.jenesis/jpx/<name>@<version>/
```

The folder holds the closure's jars in one flat directory beside a `jpx.properties` **descriptor**. The
descriptor records the module path, the class path, the entry point, and a deterministic **SHA-256 digest
over all the jars**:

```properties
name=org.junit.platform.console
version=6.1.3
mainClass=org.junit.platform.console.ConsoleLauncher
mainModule=org.junit.platform.console
modulepath=apiguardian-api-1.1.2.jar,jspecify-1.0.0.jar,junit-platform-commons-6.1.3.jar,…
checksum=SHA-256/9b60dfc3d10f0b4fdf69050eec7b7332f5c395f7e36fad5747ff421e01cfd3e8
```

One more key, `javaOptions`, appears when the module path is not self-contained - when it carries an
automatic module, or a class-path jar sits beside it. It then holds `--add-modules=ALL-MODULE-PATH,ALL-DEFAULT`,
the flag the launch needs to root the whole path, and jpx passes it to `java` for you.

The digest is what a later launch checks an installation against; the next chapter shows how.

## Named for what you asked, not what resolved

The folder is named for what you asked for, so the same tool named as a module and as a coordinate installs
twice, side by side. The second lands under `org.junit.platform--junit-platform-console@6.1.3`, since a
folder name cannot carry the coordinate's colon. The jars, and therefore the digest, are the same.

The paths are not. The `modulepath` above is what a module name produces: each jar placed as it describes a
module. The coordinate's descriptor lists those same jars as a `classpath` and records no `mainModule`,
because a coordinate names an artifact rather than a module.

Because the most recently installed version of a name is preferred over a fresh resolution, an unpinned
target pays for a download only on its first run.

## No build required

jpx does not need a local Maven repository. Where `~/.m2/repository` exists, downloads pass through it and
are hard-linked into the installation folder; where it does not exist, they land in the installation folder
directly. A machine that has never run a build, and has no `~/.m2` at all, installs a target just the same.

## An incomplete install never launches

The descriptor is written **last**, on purpose. A download that crashes midway leaves no descriptor, so jpx
recognises the install as incomplete and redoes it rather than launching a half-populated folder. Two
processes installing the same target coordinate through a **file lock**, so concurrent `jpx` invocations do
not collide.
