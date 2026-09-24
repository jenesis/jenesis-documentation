---
order: 16
title: Running from source
description: For changing the server itself - running it from a clone, building your own image, and composing a server with only the modules you want.
---

The published image is the way to run Jenesis Repository. Running it from source is for changing it: adding a
format of your own, trying a fix, or composing a server that carries only the modules you want. The server is
itself a Jenesis build, so a JDK is all it needs.

## Run a clone

You need **a JDK, version 25 or newer**. Clone the project with its submodule - the build tool is pinned inside
it - and start the server:

```bash
git clone --recurse-submodules https://github.com/jenesis/jenesis-repository.git
cd jenesis-repository
JENREG_FILESYSTEM_ROOT=/tmp/jenesis-repository \
JENREG_KEY_LOGIN=true JENREG_UI_ADMIN_KEY=a-long-local-key \
  java -Djenesis.execute.module=source+bundle build/jenesis/Execute.java
```

The first run builds the modules it needs, then serves on port 8080 exactly as the image does - the same
settings, the same console. `source/bundle` is the image's own module: it carries every format, store and console
page, and every setting in this section applies to it.

## Build your own image

The image is produced by the build, not by a hand-written `Dockerfile`. The `stage` step writes a ready-to-build
context, and `docker build` turns it into the image:

```bash
java -Djenesis.test.skip=true build/jenesis/Make.java stage
docker build -t my-repository 'target/stage/docker/output/module-source+bundle'
```

## Compose a smaller server

Every capability is a Java module, and the image carries whatever `source/bundle` requires. A module of your own
that requires only the formats and stores you want is a server with nothing else in it - a smaller image, and a
smaller surface. To shape a deployment without rebuilding, switch modules off instead: `JENREG_<MODULE>=false`
does exactly what leaving the module out would.

<div class="tip">
  The project's own README describes its module layout, the extension points a new module implements, and how to
  run its tests.
</div>
