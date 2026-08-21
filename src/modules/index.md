---
order: 1
title: Introduction
description: What the Jenesis Module Index is, and how it turns a module name into a download from Maven Central.
---

**The Jenesis Module Index turns a Java module name into a Maven Central download.** When a
`module-info.java` says `requires com.fasterxml.jackson.databind`, something has to know which artifact
publishes that name. The module index records the module name every artifact on Maven Central declares and
answers over HTTP at **[repo.jenesis.build](https://repo.jenesis.build/)**. Every answer is a 302 redirect
to the real file on Maven Central, so nothing is re-hosted.

## How you use it

The module index is an **HTTP service, not a file you download**. You ask for a module name and a file
name, and it redirects you to the jar on Maven Central. Anything that can follow a redirect is a client:

```bash
# Resolve a module name to its newest jar (follow the redirect with -L):
curl -L -O https://repo.jenesis.build/module/com.fasterxml.jackson.databind/com.fasterxml.jackson.databind.jar

# Pin a version:
curl -L -O https://repo.jenesis.build/module/com.fasterxml.jackson.databind/2.18.0/com.fasterxml.jackson.databind.jar
```

The last path segment always names the file you want, starting with the module name. There are two main
routes. `/module/…` resolves by the version a module declares in its `module-info` and serves **named**
modules - artifacts that ship a real `module-info.class`. `/artifact/…` resolves by the Maven version,
passes any file extension straight through, and covers automatic modules as well. The
[next chapter](/modules/resolving/) covers every route, versions, classifiers, and the redirect contract.

The Jenesis build tool points at `repo.jenesis.build` out of the box. When your `module-info.java` declares
a `requires`, the build resolves it through the module index automatically, so you rarely call the service
by hand. The URL shapes are the whole contract, which makes any deployment that serves the same shapes a
drop-in replacement.

<div class="note">
  A module can only be found if its jar carries a name - a real <code>module-info</code> or an
  <code>Automatic-Module-Name</code>. Artifacts that ship neither cannot be requested by module name; the
  <a href="/modules/reports/">reports</a> show how much of Maven Central is covered.
</div>

## What's in this section

1. **Introduction** - you are here.
2. **Resolving through repo.jenesis.build** - the URL shapes (`/module/…`, `/artifact/…`), versions and
   classifiers, the redirect contract, using it from the build tool and from `curl`, and pointing at a
   mirror.
3. **Reports** - the coverage summary, the per-year "top modules" reports, and the drift report that shows
   which names more than one publisher claims.
4. **How the index is produced** - a short overview, for trust: Maven Central is scanned twice a day, each
   artifact's real module name is read from the jar, and named and automatic modules are told apart.
5. **Crawling it yourself** - the crawler is a program you can run against a repository of your own, with
   companion tools that repair, extend, and report on the index it produces.
