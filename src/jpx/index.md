---
order: 1
title: Introduction
description: What jpx is and why it exists - run any published module or Maven artifact with one command.
---

**jpx runs an already-published module or Maven artifact with one command.** Point it at a target and it
resolves the dependency closure, installs it once under your home directory, and launches the main entry
point. It is `npx` for the module path: a way to run a released tool without cloning, building, or wiring up
its paths by hand.

```bash
jpx org.junit.platform.console --version
```

That resolves the JUnit console launcher and its dependencies, installs them, and runs the tool. The
`--version` is passed straight through to the launched program.

## Where jpx comes from

jpx ships inside the [Jenesis build tool](/tool/). Every project that carries the tool's sources under
`build/jenesis/` - whether they arrived through `jenesis-init`, the curl bootstrap, or the git submodule
described in the tool's [Getting started](/tool/getting-started/) - has jpx as a single-file program next to
`Project.java`. It needs a JDK, version 25 or newer, and nothing else:

```bash
java build/jenesis/Jpx.java org.junit.platform.console --version
```

The examples in this section abbreviate that command to `jpx`. A shell alias makes the abbreviation real:

```bash
alias jpx='java build/jenesis/Jpx.java'          # bash, zsh
function jpx { java build/jenesis/Jpx.java @args } # PowerShell
```

The same three steps - resolve, install, launch - are also a public API, so a program of your own can run a
published module too.

## What's in this section

1. **Introduction** - you are here.
2. **Choosing a target** - the target grammar: a module name or Maven coordinate, a version, an entry
   point.
3. **Installation & caching** - where installs live, what the descriptor records, and what makes an install
   safe to reuse.
4. **Isolation & verification** - running the launched program in a container and pinning it to a trusted
   digest.
5. **Using jpx from Java** - the same resolve, install, and launch sequence as an API.
6. **Reference** - every flag, the exit codes, and the API surface in one table.

<div class="tip">
  Prefer to read it running? The
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-47-jpx">jpx demo</a> is a single file that
  installs the JUnit console launcher, names it once as a module and once as a coordinate, and verifies both
  against a digest before launching them.
</div>
