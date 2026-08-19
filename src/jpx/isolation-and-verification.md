---
order: 4
title: Isolation & verification
description: Launch-side hardening - run the program in a container with --docker, and pin the installation to a trusted digest with --hash.
---

A tool you run is code you trust. jpx keeps that trust cheap in both directions: the launched program can
be isolated in a container, and the installed jars can be verified against a digest you already know -
before every launch.

## Running in a container

`--docker` isolates only the launched program, not the resolution and installation, which stay on the host:

```bash
jpx --docker org.junit.platform.console --version
```

The installation folder and the host's Java home are mounted **read-only**, so the containerized run needs no
network and no credentials of its own. Pass `--docker=<image>` to choose the image; with none - or with an
empty value, as a script substituting a variable produces - a minimal hardened image is built once and reused.

## Verifying the installation

`--hash=<prefix>` re-checks the installed jars against a digest you already trust, before every launch:

```bash
jpx --hash=9b60dfc3d10f0b4fdf69050eec7b7332 org.junit.platform.console@6.1.3 --version
```

The prefix must be **at least 32 hex characters** of the target's SHA-256 digest - the digest recorded at
[installation](/jpx/installation/), which you may pass with or without the `SHA-256/` prefix the descriptor
writes it under. Because that digest is taken over every jar the installation lists, the check covers the
whole closure rather than one artifact, and it runs on every launch rather than only on the run that
downloaded it - so a jar swapped underneath an existing installation is caught as readily as a tampered
download. A mismatch aborts the launch.

A version and a hash together are what turn a convenience command into a reproducible one: the same two
tokens fetch the same bytes on any machine, which is what makes jpx usable in a pipeline and not only at a
prompt. The check is available to a program as well, as one call between install and launch - see
[Using jpx from Java](/jpx/programmatic/).
