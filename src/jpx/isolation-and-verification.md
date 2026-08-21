---
order: 4
title: Isolation & verification
description: Launch-side hardening - run the program in a container with --docker, and pin the installation to a trusted digest with --hash.
---

A tool you run is code you trust. jpx keeps that trust cheap in both directions: the launched program can be
isolated in a container, and the installed jars can be verified against a digest you already know, before
every launch.

## Running in a container

`--docker` isolates only the launched program. Resolution and installation stay on the host:

```bash
jpx --docker org.junit.platform.console --version
```

The container runs the **host's own Java**: the host's Java home is mounted read-only at `/opt/java-home`
and the installation folder read-only at its host path, so the containerised run needs no credentials of its
own. The current working directory is mounted read-write at its host path, so the program can read its
input and write its output where you started it. Because the host's JDK runs inside the container, the
host and the Docker daemon have to share a platform - a Linux JDK inside a Linux container is the common
case.

With no image named, jpx builds a minimal image once (`debian:stable-slim`) and reuses it. That implicit
image runs **hardened**: all capabilities dropped, no privilege escalation, and your own user id. Pass
`--docker=<image>` to run on an image of your choice. A named image is used as is, without those hardening
flags, so choose one you trust. An empty value (`--docker=`), as a script substituting a variable produces,
means the same as naming no image.

<div class="note">
  The container keeps network access. <code>--docker</code> confines what the program can see on your
  machine - your home directory, its credentials, the rest of the file system - not what it can reach over
  the network.
</div>

## Verifying the installation

`--hash=<prefix>` re-checks the installed jars against a digest you already trust, before every launch:

```bash
jpx --hash=9b60dfc3d10f0b4fdf69050eec7b7332 org.junit.platform.console@6.1.3 --version
```

The prefix must be **at least 32 hex characters** of the target's SHA-256 digest - the `checksum` the
descriptor records, which you may pass with or without its `SHA-256/` prefix. Because that digest is taken
over every jar the installation lists, the check covers the whole closure rather than one artifact. And it
runs on every launch, not only on the run that downloaded it, so a jar swapped underneath an existing
installation is caught as readily as a tampered download. A mismatch aborts the launch.

A version and a hash together turn a convenience command into a reproducible one: the same two tokens fetch
the same bytes on any machine, which is what makes jpx usable in a pipeline and not only at a prompt. The
check is available to a program as well, as one call between install and launch - see
[Using jpx from Java](/jpx/programmatic/).
