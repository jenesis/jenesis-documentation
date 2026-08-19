---
order: 3
title: Installation & caching
description: Where resolved targets install, what the descriptor records, and how an install stays consistent under crashes and concurrency.
---

jpx installs every resolved target once and reuses it across runs. Each target lives under:

```
~/.jenesis/jpx/<name>@<version>/
```

The folder holds the closure's jars in one flat directory beside a `jpx.properties` descriptor that records
the module path, the class path, the entry point, and a deterministic **SHA-256 digest over all the jars** -
the same digest [`--hash`](/jpx/isolation-and-verification/) checks against:

```properties
name=org.junit.platform.console
version=6.1.3
mainModule=org.junit.platform.console
mainClass=org.junit.platform.console.ConsoleLauncher
modulepath=apiguardian-api-1.1.2.jar,junit-platform-commons-6.1.3.jar,…
checksum=SHA-256/9b60dfc3d10f0b4fdf69050eec7b7332f5c395f7e36fad5747ff421e01cfd3e8
```

The folder is named for what you asked for, not for what it resolved to, so the same tool named as a module
and as a coordinate installs twice, side by side - the second under
`org.junit.platform--junit-platform-console@6.1.3`, since a folder name cannot carry the coordinate's colon.
The jars, and therefore the digest, are the same.

This is also what makes an unpinned target fast: the most recently installed version is preferred over a
fresh resolution, so only the first run pays for a download - see
[Choosing a target](/jpx/targets/).

Downloads land in the installation folder directly rather than by way of your local Maven repository, so a
machine that has never run a build - and has no `~/.m2` at all - installs a target just the same.

## An incomplete install never launches

The descriptor is written **last**, on purpose: a download that crashes mid-way leaves no descriptor, so jpx
recognizes the install as incomplete and redoes it rather than launching a half-populated folder. Two
processes installing the same target coordinate through a **file lock**, so concurrent `jpx` invocations do
not collide.
