---
order: 2
title: Choosing a target
description: The target grammar - a module name or Maven coordinate, an optional version, and an optional entry point - and where jpx resolves each from.
---

The first argument that does not start with `--` names what to run. Its full form is:

```
<name>[@<version>][/<main-class>]
```

Only the name is required. The three parts each answer one question: *what*, *which version*, and *which
entry point*. Flags such as `--docker` go before the target; everything after the target is handed to the
launched program untouched.

## The name - module or Maven coordinate

You can name what to run in two ways, and jpx tells them apart by a single rule: **a module name can never
contain a colon.**

- **A Java module name**, such as `org.junit.platform.console`. jpx looks the module up in the
  [Jenesis Module Index](/modules/) and downloads it, and everything it depends on, from Maven Central. This
  is the everyday form: you name the module, nothing else.
- **A `<groupId>:<artifactId>` pair**, such as `org.junit.platform:junit-platform-console`. The colon marks
  it as a Maven coordinate, resolved from Maven Central directly. Reach for this when you want a specific
  artifact, or one that carries no module name.

Both of these run the very same tool, the JUnit console launcher - one by its module name, the other by its
coordinate:

```bash
jpx org.junit.platform.console                  # by module name
jpx org.junit.platform:junit-platform-console   # by Maven coordinate
```

The name decides more than where jpx looks. It also decides how the program is run:

- **A module name runs as a module.** Every jar of the closure that describes a module is placed on the
  module path and any jar that does not on the class path. The entry point starts the way
  `java -m <module>/<main-class>` starts it.
- **A Maven coordinate runs on the class path.** A `<groupId>:<artifactId>` pair names an artifact rather
  than a module, so its closure is placed on the class path in full and the main class is named directly.

Named either way, the two install the same jars and verify against the same digest. What differs is the
paths recorded for the launch, which the next chapter shows.

### Resolving over module descriptors only

With `--modular`, jpx resolves purely over module names: it follows each module's `requires` clauses with no
POM involved, so every dependency must itself be an explicitly named module, and it places every jar of the
closure on the module path. This mirrors the build tool's
[`modular` layout](/tool/core-concepts/). Because it needs a module name to start from, `--modular` refuses
a Maven coordinate rather than resolving it another way.

### Where jpx looks

Either form reaches the same repositories a build does, and in the same order: your local module repository
(`~/.jenesis`) and local Maven repository (`~/.m2`) first, then the public ones. A module you just published
locally with `export` is therefore runnable immediately. `JENESIS_REPOSITORY_URI` and `MAVEN_REPOSITORY_URI`
point jpx at a mirror or an internal repository exactly as they point a build; the `jenesis.module.uri` and
`jenesis.maven.uri` system properties do the same and take precedence.

## The version - which release

Append `@<version>` to pin a release:

```bash
jpx org.junit.platform.console@6.1.3
```

Without a version, jpx prefers the **most recently installed** version of that target. Only when none is
installed does it resolve the **latest release**. So the first run pulls the current release, and later runs
reuse it until you ask for a newer one by naming it.

## The main class - which entry point

By default jpx launches the jar's **module main class**, or its `Main-Class` manifest attribute. Append
`/<main-class>` to choose a different entry point:

```bash
jpx org.junit.platform.console/org.junit.platform.console.ConsoleLauncher
```

This works exactly like `java -m <module>/<main-class>`. It also means a jar that declares **no** entry point
at all is still runnable - just name the class yourself.
