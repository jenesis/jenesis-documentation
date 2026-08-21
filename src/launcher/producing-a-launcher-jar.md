---
order: 3
title: Producing a launcher jar
description: The build-tool switch that emits a launcher jar, what the build writes into it, where the jar lands, and how the launcher itself is pinned.
---

You never assemble a launcher jar by hand. The Jenesis build tool produces it from one switch in
`packaging.properties`: it resolves the launcher, copies its classes into the jar, lays out your dependencies
for it, and writes the descriptor and manifest that make `java -jar app.jar` start the launcher. This chapter
shows that switch, what the build writes, and where the result lands.

## Turning it on

The launcher jar is one of the build tool's [packaging options](/tool/packaging/). Enable it with
`launcher=true` in a `packaging.properties` file in the [configuration folder](/tool/configuration/):

```properties
# build.jenesis/packaging.properties
launcher=true
```

```bash
java build/jenesis/Project.java
```

Like every packaging feature, it only runs for a module that declares a main class - the same `@jenesis.main`
tag (or `<mainClass>` POM property) the other packaging steps key off. A module without one is skipped, so a
library is left alone and an application needs no launcher-specific configuration.

## What the build writes

The build resolves the published launcher artifact and produces the jar in four moves. Everything the
launcher needs at run time - the layout described in [*How it works*](/launcher/how-it-works/) - is put in
place here:

1. **The launcher's classes go into the jar root.** Only its `build/jenesis/launcher/*.class` files are
   copied; the launcher's own `module-info` and manifest are left out, so at run time those classes are the
   unnamed module that hosts your application.
2. **Each dependency is exploded into its own subfolder.** The resolved jar file name becomes the folder name:
   `modulepath/org.slf4j%2Fslf4j-api%2F2.0.16.jar/` for a modular or automatic dependency, `classpath/…/`
   for a plain one, and `classes.jar/` for the application's own module. The split follows the same rule as
   the build's `Execute` launcher and its `bundle.zip`: a jar is placed on the module path only when the
   application is modular and the jar describes a module. A `pom.xml` application without a module
   therefore gets everything under `classpath/`.
3. **`application.properties` is written** with `mainClass`, `mainModule` (modular applications only), and
   `classpath` - the class-path subfolders, listed in file-name order.
4. **The manifest gets one attribute**, `Main-Class: build.jenesis.launcher.Launcher`, so `java -jar` starts
   the launcher.

That is the complete set. The other descriptor keys and manifest attributes the launcher understands -
bundled agents, module-access grants, signer reconstruction - are for a jar you assemble yourself; the
[*Reference*](/launcher/reference/) chapter lists them.

<div class="note">
  A <a href="/tool/packaging/">bundle</a> (<code>bundle=true</code>) makes the same module-path / class-path
  split, but keeps each jar whole under <code>modulepath/</code> and <code>classpath/</code> for you to drop
  onto a JRE. The launcher jar explodes those same jars into subfolders and adds the launcher, so it needs no
  launch script.
</div>

## Where the jar lands

The jar is named after the module's artifact id - `demo.modular.executable.jar` for the modular demo - or
`application.jar` when the build knows no artifact id. It is written into the module's build output, under
the `launcher` module's `bundle` step:

```
target/build/…/launcher/bundle/output/launcher/<name>.jar
```

It is not collected into the `stage` tree. A build of your own can locate it as the jar under a `launcher/`
folder of the build output - `build/DemoLauncher.java` in the two executable demos does exactly that, then
runs the jar.

## The launcher is pinned like any dependency

The build resolves the launcher as a normal dependency, in its own `launcher` group, kept apart from your
application's dependencies. Until you pin it, it floats to the latest release. Run `pin` and the build records
the exact version and checksum next to your other pins - in a modular project:

```java
/**
 * @jenesis.main sample.Sample
 * @jenesis.pin launcher/maven/build.jenesis/build.jenesis.launcher 0.3.1 SHA-256/720f9c17…
 */
module demo.modular.executable {
    requires org.slf4j;

    exports sample;
}
```

A `pom.xml` project carries the same line in its `<!--jenesis.pin … -->` block, outside
`<dependencyManagement>`, since the launcher is not an application dependency. Either way the launcher bytes
shaded into your jar are [verified](/tool/pinning/) on every build, and the produced jar is reproducible:
the same sources yield the same bytes.

<div class="tip">
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-05-java-pom-executable">demo-05</a> (a
  <code>pom.xml</code> application) and
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-06-java-modular-executable">demo-06</a> (a
  modular one) each ship a <code>build/DemoLauncher.java</code> that switches the launcher on through a
  profile, builds the jar, and runs it: <code>java build/DemoLauncher.java Ada Lovelace</code>. Their pinned
  <code>module-info.java</code> and <code>pom.xml</code> show the pin line in both forms.
</div>

With the jar produced, the next chapter turns to running it: the start-up flow, what the single loader means
for your code, and the pitfalls to watch for.
