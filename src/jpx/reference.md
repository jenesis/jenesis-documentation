---
order: 6
title: Reference
description: Every jpx flag, the exit codes, and the API surface in one table.
---

The whole surface of jpx is one target and a handful of flags:

```
jpx [--modular] [--docker[=<image>]] [--hash=<checksum>] <target> [argument...]
```

Flags come **before** the target; everything after the target is passed to the launched program. The target
grammar, `<name>[@<version>][/<main-class>]`, is covered in [Choosing a target](/jpx/targets/).

| Flag | What it does |
| --- | --- |
| `--modular` | Resolve purely over module descriptors, walking `requires` clauses like the [`modular` layout](/tool/core-concepts/), and place every jar on the module path. Every module must then be explicitly named; a Maven coordinate is refused. |
| `--docker[=<image>]` | Run the launched process in a container while resolution and installation stay on the host. Without an image, a minimal hardened image is built once and reused; a named image runs as is. An empty value is the same as naming no image. |
| `--hash=<prefix>` | Verify the installed jars against a known digest before launching. At least 32 hex characters, with or without a leading `SHA-256/`. |
| `--help` | Print the usage screen and exit. |

`--modular` is covered under [Choosing a target](/jpx/targets/); `--docker` and `--hash` under
[Isolation & verification](/jpx/isolation-and-verification/).

## Exit codes

| Code | When |
| --- | --- |
| the program's own | The launched program ran; jpx returns its exit code unchanged. |
| `0` | `--help`. |
| `64` | A usage error: no target, or an unknown option. The usage screen is printed to standard error. |
| `1` | Resolution failed, a checksum did not match, or the target declares no entry point - reported with the message of the underlying exception. |

## The API

Every flag has a counterpart in the API, which [Using jpx from Java](/jpx/programmatic/) walks through:

| Call | What it does |
| --- | --- |
| `new Jpx(placement)` | The command line's wiring: installs under `~/.jenesis/jpx`; `PathPlacement.MODULE_PATH` is `--modular`, `PathPlacement.INFERRED` the default. |
| `new Jpx(storage, repositories, resolvers, hashFunction, placement)` | The record itself: where installs land, where artifacts come from, how they are digested, and how a module name's jars are placed. |
| `jpx.install(target)` | Resolve and install `<name>[@<version>][/<main-class>]`, returning an `Installation`. |
| `Jpx.Command.parse(target)` / `jpx.install(command)` | The same, with the target's three parts in hand. |
| `jpx.latestInstalled(name)` | The newest install of a name already on disk, without resolving anything. |
| `installation.folder()` / `.properties()` | The installation folder and its `jpx.properties` descriptor. |
| `installation.verify(prefix)` | The `--hash` check; returns the installation, throws on a mismatch. |
| `installation.launch(arguments)` | Launch the installation's own entry point and return the exit code. |
| `installation.launch(mainClass, arguments)` | The same with an entry point of your choice (`null` for the installation's own). |
| `installation.launch(mainClass, arguments, docker)` | The same inside a container; `docker` is a `DockerizedJava`, the API behind `--docker`. |
| `installation.javaArguments(mainClass, arguments, file)` | Everything after `java`, to start the process yourself. |
