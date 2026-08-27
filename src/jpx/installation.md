---
order: 3
title: Installation & caching
description: Where resolved targets install, what the descriptor records, and how an install stays consistent under crashes and concurrency.
---

jpx installs every resolved target once and reuses it across runs. Each target lives under:

```
~/.jenesis/jpx/<layout>/<name>@<version>/
```

The layout is how the target was resolved: `modular_to_maven` for a module name resolved through poms,
`modular` for `--modular`, which resolves over module descriptors, and `maven` for a coordinate. Each keeps
its own installations, so the same target asked for in two ways never hands one resolution's jars to the
other.

The folder holds the closure's jars in one flat directory beside a `jpx.properties` **descriptor**. The
descriptor records the module path, the class path, the entry point, and a deterministic **SHA-256 digest
over all the jars**:

```properties
name=org.junit.platform.console
version=6.1.3
mainClass=org.junit.platform.console.ConsoleLauncher
mainModule=org.junit.platform.console
modulepath=org.apiguardian.api-1.1.2.jar,org.jspecify-1.0.0.jar,org.junit.platform.commons-6.1.3.jar,…
checksum=SHA-256/ed5600ef861c7e86cab68c134c6ca0cf3b5265e5f2697c16576281452aa1e2dd
```

One more key, `javaOptions`, appears when the module path is not self-contained - when it carries an
automatic module, or a class-path jar sits beside it. It then holds `--add-modules=ALL-MODULE-PATH,ALL-DEFAULT`,
the flag the launch needs to root the whole path, and jpx passes it to `java` for you.

The digest is what a later launch checks an installation against; the next chapter shows how.

## Named for what you asked, not what resolved

The folder is named for what you asked for, so the same tool named as a module and as a coordinate installs
twice, under the layout each was resolved by. The second lands under
`maven/org.junit.platform--junit-platform-console@6.1.3`, since a folder name cannot carry the coordinate's
colon. The jars, and therefore the digest, are the same: a jar is named for the module it carries, whichever
way you asked for it.

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
