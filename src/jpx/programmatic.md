---
order: 5
title: Using jpx from Java
description: The same resolve-install-launch sequence as an API - install a target, read its descriptor, verify it, and launch it from your own program.
---

Everything the `jpx` command does is available to a Java program: `jpx` itself is a `main` method around a
small API, and that API is public. Reach for it when a tool of your own has to run a published module - an
IDE plugin launching a formatter, a test harness driving a released version of the program under test, or a
script that resolves a tool once and then runs it many times.

## Where the class lives

The type is **`build.jenesis.Jpx`**, in the module `build.jenesis` - the same artifact the build tool
publishes, `build.jenesis:build.jenesis` on Maven Central. Declare it the way you declare any dependency:

```java
module demo.tooling {
    requires build.jenesis;
}
```

A project that already embeds Jenesis as source under `build/jenesis/` has the class in the tree, so an entry
point next to `Project.java` can call it with nothing resolved at all.

## Install, then launch

Both halves of a `jpx` invocation are one call each: install the target, launch what it installed.

```java
Jpx jpx = new Jpx(PathPlacement.INFERRED);
int status = jpx.install("org.junit.platform.console@6.1.3").launch(List.of("--version"));
```

`install` takes the [target grammar](/jpx/targets/) the command line takes, `<name>[@<version>][/<main-class>]`.
It performs the resolution and [installation](/jpx/installation/) described earlier, reuses an existing
install when there is one, and returns an **`Installation`**: a handle on the folder it landed in. A
malformed target throws `IllegalArgumentException` rather than resolving something unexpected.

The constructor's argument is the **placement**, which is what `--modular` selects on the command line.
`PathPlacement.INFERRED` resolves a module name through its published coordinates and places each jar as it
describes a module. `PathPlacement.MODULE_PATH` resolves purely over module descriptors and places every
jar of the closure on the module path. The placement belongs to the instance rather than to the call because
it also decides which repository and resolver the instance carries, so one `Jpx` answers one way for every
target you hand it. A Maven coordinate is the one target it does not govern: it names an artifact rather
than a module, and runs on the class path whichever placement the instance was built with.

`launch` starts a `java` process from the JVM that runs your program, with the installed paths and entry
point. It inherits the current process's streams, waits, and returns the child's exit code. The
single-argument form uses the installation's own entry point; a `launch(mainClass, arguments)` overload
names a different one, the way a `/<main-class>` suffix does on the command line.

When you want the parts of a target separately - to log the version, or to route on the name - parse it
yourself and hand the result to the same method:

```java
Jpx.Command command = Jpx.Command.parse("org.junit.platform.console@6.1.3/org.junit.platform.console.ConsoleLauncher");
Jpx.Installation installation = jpx.install(command);
int status = installation.launch(command.mainClass(), List.of("--version"));
```

`Command` gives you `name()`, `version()`, and `mainClass()`. The name is always present; the other two are
`null` where the target left them out. The string form of `install` is exactly `install(Command.parse(target))`.

<div class="note">
  Only the name and version decide what is installed. An entry point is a launch argument, so it is the
  <code>launch</code> call that has to receive it. A <code>/&lt;main-class&gt;</code> written into a target
  string therefore parses fine and then goes unused unless you pass <code>command.mainClass()</code> along, as
  above.
</div>

## Reading what was installed

An `Installation` exposes its folder and the descriptor written beside the jars, so you can inspect a target
without running it:

```java
SequencedProperties descriptor = installation.properties();
String module = descriptor.getProperty("mainModule");   // null for a class-path target
String entry = descriptor.getProperty("mainClass");     // null when the target declares none
String digest = descriptor.getProperty("checksum");     // "SHA-256/…" over all jars
Path folder = installation.folder();
```

The `modulepath` and `classpath` entries are comma-separated file names, relative to that folder. Which of
the two a jar lands in follows from how the target was named: a module name is placed jar by jar as each
describes a module, a Maven coordinate on the class path in full. So `mainModule` is absent for a coordinate,
as it is for a module name whose jars declare none. A target with no entry point at all is a legitimate
install too: `mainClass` is simply absent, and `launch` then fails unless you name a class yourself.

To find an install that is already on disk without resolving anything, ask for the newest one by name:

```java
Optional<Jpx.Installation> installed = jpx.latestInstalled("org.junit.platform.console");
```

That is the same lookup an unversioned target performs first, and it is what makes an offline run possible.

## Verifying before you launch

`verify` is the API behind [`--hash`](/jpx/isolation-and-verification/). It recomputes the digest over the
installed jars and throws `IllegalStateException` when the result does not start with the prefix you passed,
so a launch guarded by it never runs unvetted bytes:

```java
jpx.install("org.junit.platform.console@6.1.3")
        .verify("9b60dfc3d10f0b4fdf69050eec7b7332")
        .launch(List.of("--version"));
```

It returns the installation, so it chains between install and launch. The prefix rules are the command
line's: at least 32 hex characters, optionally written with the leading `SHA-256/` the descriptor records.

## Launching in a container, or building the command yourself

To run the program in a container, with resolution and installation still on the host, hand `launch` a
`DockerizedJava` from `build.jenesis.docker`:

```java
Path workingDirectory = Path.of("").toAbsolutePath();
installation.launch(command.mainClass(), List.of("--version"), new DockerizedJava(workingDirectory));
```

The single-argument constructor builds and reuses the minimal hardened image that `--docker` uses;
`new DockerizedJava(directory, "<image>")` names an image of your own, which then runs without the
hardening flags. Either way the container runs the host's Java home, mounted read-only, so the image only
has to provide a compatible operating system, not a JDK. The working directory is mounted read-write at its
host path.

When you would rather start the process yourself - a different working directory, a redirected stream, an
extra JVM flag - ask for the argument list instead of a launch. `javaArguments` returns everything that
follows `java`, given a file it may spill long paths into:

```java
Path arguments = Files.createTempFile("jpx.", ".args");
try {
    List<String> command = new ArrayList<>();
    command.add(Path.of(System.getProperty("java.home"), "bin", "java").toString());
    command.addAll(installation.javaArguments(null, List.of("--version"), arguments));
    new ProcessBuilder(command).inheritIO().start().waitFor();
} finally {
    Files.deleteIfExists(arguments);
}
```

<div class="note">
  The argument file is how a launch survives a long module path on every platform, so it is a parameter
  rather than a detail: the returned list refers to the file, which therefore has to outlive the process you
  start with it.
</div>

## Choosing where things come from

`Jpx` is a record of five values - the storage folder, the repositories, the resolvers, the hash function,
and the placement - and it has two constructors. The short one takes a placement and fills the rest in the
way the command does, installing under `~/.jenesis/jpx`:

```java
Jpx jpx = new Jpx(PathPlacement.INFERRED);        // resolve by published coordinates
Jpx modular = new Jpx(PathPlacement.MODULE_PATH); // resolve over module descriptors
```

`PathPlacement.CLASS_PATH` is the third value, and the one a Maven coordinate runs under however the instance
was built.

The long constructor names all five. A storage folder of your own keeps installs out of `~/.jenesis/jpx`,
which is what a test, a sandboxed tool, or a demo wants. Here are the defaults spelled out, with
`target/jpx` as the storage folder:

```java
MavenPomResolver maven = new MavenPomResolver();
Repository modules = JenesisModuleRepository.of(JenesisRepository.Scope.ARTIFACT);
Jpx jpx = new Jpx(Path.of("target", "jpx"),
        Map.of("maven", MavenDefaultRepository.of(), "module", modules),
        Map.<String, Resolver>of("maven", maven, "module", new MavenModuleResolver("maven", maven, modules)),
        new HashDigestFunction("SHA-256"),
        PathPlacement.INFERRED);
```

Replacing the repositories is the way to resolve from a private mirror, or from a local folder with no
network at all. `MavenDefaultRepository` takes the mirror's URI, a local folder to cache downloads in (`null`
for none), the checksum URIs to validate against, a callback for each fetch, and an optional token sent as
the `Authorization` header:

```java
URI mirror = URI.create("https://nexus.example.com/maven2/");
Jpx jpx = new Jpx(storage,
        Map.of("maven", new MavenDefaultRepository(mirror, local, Map.of("SHA256", mirror), _ -> { }, token)),
        Map.of("maven", new MavenPomResolver()),
        new HashDigestFunction("SHA-256"),
        PathPlacement.INFERRED);
```

Repositories are keyed by the kind of coordinate they serve: `maven` for Maven coordinates and `module` for
module names. A map that carries only `maven`, as above, supports only Maven coordinates. Resolving a module
name under `PathPlacement.INFERRED` needs **both** entries, because the module index discovers the
coordinates and the Maven repository supplies the jars. A target that needs a missing entry fails rather than
silently reaching the public default.

<div class="note">
  The defaults are not hard-coded either: they are built from the same environment the build tool reads, so
  <code>MAVEN_REPOSITORY_URI</code> and <code>JENESIS_REPOSITORY_URI</code> - and their token and local-folder
  companions - already redirect a plain <code>new Jpx(PathPlacement.INFERRED)</code> at a mirror. Construct
  the repositories yourself when the choice has to come from your program rather than from its environment.
</div>

<div class="tip">
  Installation is idempotent and safe to run from several processes at once, so a program does not have to
  track whether a target is present: call <code>install</code> every time and pay for the download only on the
  first run. The
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-46-jpx">jpx demo</a> is this whole chapter as
  one runnable file - it installs the JUnit console launcher into its own <code>target/jpx/</code>, verifies
  it, and launches it.
</div>
