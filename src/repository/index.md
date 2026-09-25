---
order: 1
title: Introduction
description: What Jenesis Repository is, what it serves, and how this section follows the console.
---

**Jenesis Repository is a self-hosted artifact repository with no database.** One server hosts your own
packages and caches the public ones for more than twenty package ecosystems - Maven and Gradle, npm, PyPI,
container images, Go, Cargo, NuGet, RubyGems, Helm, Debian and RPM packages, and more - each served to its own
native client. It screens what comes in against vulnerability and malware feeds, holds back what fails your
policy for review, keeps a remote build cache for the Jenesis build tool, and runs a web console to look after
it all.

You run it from one Docker image, `jenesisbuild/jenesis-repository`, and everything it holds lives in one place:
a directory on a volume, or a bucket on S3, Google Cloud Storage or Azure Blob.

## Three things to know up front

- **The store is the only state.** Artifacts, indexes, settings and keys all live in the one directory or
  bucket. Back it up and you have backed up the repository; copy it and you have moved it. There is no database
  to install, tune or migrate.
- **Artifacts stream through, never into memory.** An upload or a download is copied between the network and the
  store without being held whole, so a small POM and a multi-gigabyte image layer cost the server the same
  small, fixed amount of memory.
- **Everything is a module.** Each format, storage backend, screening feed and console page is a Java module
  that plugs into the server through a service interface, and the server assembles itself from whichever modules
  it finds at startup. So a feature of your own is a module that implements that interface - a new package
  format, a storage backend, a screening source - added to a composition of your own; and a feature you do not
  want is left out of the composition, or switched off with a setting exactly as if it were absent. Adding or
  removing one never means changing the rest, which is what keeps the repository manager easy to extend and to
  maintain. [Compose a smaller server](/repository/from-source/#compose-a-smaller-server) shows how a composition
  is built.

## How this section is organised

The chapters follow the console. After the first two, each covers one of its sections, in the order they appear
across the top of the page:

1. **Getting started** - run the image, sign in, issue a key, and publish with Maven and npm.
2. **Finding your way around** - the console's two navigation levels, the pages of a repository, and who sees
   what.
3. **Repositories** - what a repository is here, and its overview, browse, staging and import pages.
4. **Connecting your build tools** - the URL and credential form for every client.
5. **Proxying upstreams** - serving Maven Central, Docker Hub and other registries through your repository.
6. **Screening what comes in** - the gate, the review queue, and the vulnerability, findings and signer
   pages.
7. **Retention, pins and cleanup** - how long a repository keeps what it holds, and reclaiming space.
8. **The build cache** - projects, and pointing the Jenesis build tool at them.
9. **Access** - signing people in, members and roles, credentials for build tools, and keyless CI.
10. **Operations** - metrics, the security posture, scheduled walks, manual uploads, webhooks and rate limits.
11. **Settings** - the first-run guide, the settings catalogue, modules, and backing settings up.
12. **Running in production** - object storage, the Helm chart, TLS and backups.
13. **Migrating in and out** - importing from Nexus, Artifactory and others, and taking everything out again.
14. **What it costs to run** - where an object store's bill comes from, and how to keep it small.
15. **Running from source** - for those who want to change the server itself.
16. **Configuration reference** - every setting in one place.

<div class="tip">
  Start with <strong>Getting started</strong>: it takes you from <code>docker run</code> to a published artifact
  in a few minutes, and shows the console's layout before anything else builds on it.
</div>
