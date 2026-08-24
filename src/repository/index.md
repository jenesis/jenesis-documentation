---
order: 1
title: Introduction
description: What Jenesis Repository is, who it is for, and the path through the chapters.
---

**Jenesis Repository is a self-hosted artifact repository with no database.** It serves the Maven layout,
the Jenesis module layout, an OCI/Docker registry and plain files, all from one store - a directory on disk,
an S3-compatible bucket, Google Cloud Storage or Azure Blob. Publish a jar once and every Maven, Gradle or
Jenesis build can resolve it; publish a modular jar and a Jenesis build can resolve it by module name too.

It is built for a team that wants a small repository it can run itself, and for a company that wants to
see exactly what it would be running before it commits. The whole server is a handful of Java modules on a
JDK: clone it, start it against a folder, and you have a repository. Importing from Nexus, Artifactory or any
Maven repository is built in, and a web console lets you browse what the server holds.

## Three things to know up front

- **The store is the only state.** Artifacts, checksums, indexes and settings all live in one place - a
  directory, or a bucket. Back that up and you have backed up the repository; copy it and you have moved
  the repository. There is no database to install, tune or migrate.
- **Artifacts stream through, never into memory.** An upload or a download is copied from the network to
  the store and back without being held whole, so a 4 KB POM and a 4 GB image layer cost the server the same
  fixed amount of heap.
- **Every capability is a module you can switch off.** Each format, storage backend and import connector is
  a Java module the server discovers at startup. `JENREG_MAVEN=false` turns the Maven layout off exactly as
  if its module were absent; `JENREG_STORE=s3` selects a backend. You shape a deployment with configuration,
  not by rebuilding it.

<div class="tip">
  Start with <strong>Getting started</strong>: it takes you from a clone to a running repository, a published
  artifact, and the console, and it shows how configuration works before anything else builds on it.
</div>

## What's in this section

1. **Introduction** - you are here.
2. **Getting started** - run the server from source, configure it the Spring Boot way, publish and resolve
   an artifact, open the console, and see the alternatives: a local container image and the cloud stores.
3. **Architecture** - the plugin model, the content-addressed store, and the path an upload takes.
4. **Storage** - the filesystem, S3-compatible, Google Cloud Storage and Azure Blob backends, their
   settings, and the storage quota.
5. **Formats** - the Maven layout, the Jenesis module layout, the OCI/Docker registry and the raw layout,
   and the settings that switch each on or off.
6. **Proxying** - pull-through caching of an upstream such as Maven Central, revalidation, and the negative
   cache.
7. **Authentication & access** - the bootstrap key, issuing and revoking keys and their grants, running
   open or read-only, anonymous read rights, and signing in to the console.
8. **Rate limiting** - the per-tenant request ceiling and what it sheds.
9. **Migration & import** - importing from Nexus, Artifactory, a Maven repository or another Jenesis
   Repository, batch uploads, and listing everything the server holds so you can leave with it.
10. **Observability** - logs, metrics, the security-posture report, and the multi-node consistency check.
11. **The console** - running the web console, signing in, and browsing repositories and artifacts.
12. **Configuration reference** - every setting in one place, with its default.
