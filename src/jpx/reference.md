---
order: 6
title: Reference
description: Every jpx flag, the usage screen, and the API surface in one table.
---

The whole surface of jpx is one target and a handful of flags. The target grammar is covered in
[Choosing a target](/jpx/targets/); the flags are these:

| Flag | What it does |
| --- | --- |
| `--modular` | Resolve purely over module descriptors, walking `requires` clauses like the [`modular` layout](/tool/core-concepts/) - every module must be explicitly named. |
| `--docker[=<image>]` | Run the launched process in a container while resolution and installation stay on the host. An empty value is the same as naming no image. |
| `--hash=<prefix>` | Verify the installed jars against a known digest before launching. At least 32 hex characters, with or without a leading `SHA-256/`. |
| `--help` | Print the usage screen and exit. |

`--modular` is covered in depth under [Choosing a target](/jpx/targets/); `--docker` and `--hash` under
[Isolation & verification](/jpx/isolation-and-verification/).

## Usage

Running `jpx` with no arguments - or with `--help` - prints the usage screen:

```bash
jpx --help
```

## The API

Every flag has a counterpart in the API, which [Using jpx from Java](/jpx/programmatic/) walks through:

| Call | What it does |
| --- | --- |
| `new Jpx(modular)` | The default wiring: installs under `~/.jenesis/jpx`; `modular` is `--modular`. |
| `new Jpx(storage[, modular])` | The same, with installs under a folder of your choosing. |
| `new Jpx(storage, repositories, resolvers, hashFunction)` | Full control over where artifacts come from and how they are digested. |
| `jpx.install(target)` | Resolve and install `<name>[@<version>][/<main-class>]`, returning an `Installation`. |
| `Jpx.Command.parse(target)` / `jpx.install(command)` | The same, with the target's three parts in hand. |
| `jpx.latestInstalled(name)` | The newest install of a name already on disk, without resolving anything. |
| `installation.folder()` / `.properties()` | The installation folder and its `jpx.properties` descriptor. |
| `installation.verify(prefix)` | The `--hash` check; returns the installation, throws on a mismatch. |
| `installation.launch([mainClass, ]arguments[, docker])` | Launch it and return the exit code; `docker` is `--docker`. |
| `installation.javaArguments(mainClass, arguments, file)` | Everything after `java`, to start the process yourself. |
