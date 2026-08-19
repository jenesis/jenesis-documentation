---
order: 5
title: Using jpx from Java
description: The same resolve-install-launch sequence as an API - install a target, read its descriptor, verify it, and launch it from your own program.
---

Everything the `jpx` command does is available to a Java program: `jpx` itself is a `main` method around a
small API, and that API is public. Reach for it when a tool of your own has to run a published module -
an IDE plug-in launching a formatter, a test harness driving a released version of the program under test,
or a script that resolves a tool once and then runs it many times.

## Where the class lives

The type is **`build.jenesis.Jpx`**, in the module `build.jenesis` - the same artifact the build tool
publishes, `build.jenesis:build.jenesis` on Maven Central. Declare it the way you declare any dependency:

```java
module demo.tooling {
    requires build.jenesis;
}
```

A project that already embeds Jenesis as source under `build/jenesis/` has the class in the tree, so a
launcher next to `Project.java` can call it with nothing resolved at all.

## Install, then launch

Both halves of a `jpx` invocation are one call each: install the target, launch what it installed.

```java
Jpx jpx = new Jpx(false);
int status = jpx.install("org.junit.platform.console@6.1.3").launch(List.of("--version"));
```

`install` takes the [target grammar](/jpx/targets/) the command line takes -
`<name>[@<version>][/<main-class>]` - performs the resolution and [installation](/jpx/installation/)
described earlier, reusing an existing install when there is one, and returns an **`Installation`**: a handle
on the folder it landed in. A malformed target throws `IllegalArgumentException` rather than resolving
something unexpected.

The constructor's flag is `--modular`: `false` resolves a module name through its published coordinates, and
`true` resolves purely over module descriptors. It belongs to the instance rather than to the call, because
it decides which repository and resolver that instance carries - so one `Jpx` answers one way, consistently,
for every target you hand it.

`launch` starts a `java` process with the installed paths and entry point, inherits the current process's
streams, waits for it, and returns the child's exit code. The single-argument form uses the installation's
own entry point; a `launch(mainClass, arguments)` overload names a different one, the way a `/<main-class>`
suffix does on the command line.

When you want the parts of a target separately - to log the version, or to route on the name - parse it
yourself and hand the result to the same method:

```java
Jpx.Command command = Jpx.Command.parse("org.junit.platform.console@6.1.3/org.junit.platform.console.ConsoleLauncher");
Jpx.Installation installation = jpx.install(command);
int status = installation.launch(command.mainClass(), List.of("--version"));
```

`Command` gives you `name()`, `version()`, and `mainClass()`, each `null` where the target left it out; the
string form of `install` is exactly `install(Command.parse(target))`.

<div class="note">
  Only the name and version decide what is installed - an entry point is a launch argument, so it is the
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
String digest = descriptor.getProperty("checksum");     // the SHA-256 over all jars
Path folder = installation.folder();
```

The `modulepath` and `classpath` entries are comma-separated file names, relative to that folder. A target
with no entry point at all is a legitimate install - `mainClass` is simply absent, and `launch` then fails
unless you name a class yourself.

To find an install that is already on disk without resolving anything, ask for the newest one by name:

```java
Optional<Jpx.Installation> installed = jpx.latestInstalled("org.junit.platform.console");
```

That is the same lookup an unversioned target performs first, and it is what makes an offline run possible.

## Verifying before you launch

`verify` is the API behind [`--hash`](/jpx/isolation-and-verification/). It recomputes the digest over the
installed jars and throws `IllegalStateException` when it does not start with the prefix you passed, so a
launch guarded by it never runs unvetted bytes:

```java
jpx.install("org.junit.platform.console@6.1.3")
        .verify("9b60dfc3d10f0b4fdf69050eec7b7332")
        .launch(List.of("--version"));
```

It returns the installation, so it chains between install and launch - which is the whole shape of a
reproducible run: a target that names a version, a digest that fixes its bytes, and a launch that only
happens if both hold. The prefix rules are the command line's: at least 32 hex characters, optionally written
with the leading `SHA-256/` the descriptor records.

## Launching in a container, or building the command yourself

To run the program in a container - resolution and installation still on the host - hand `launch` a
`DockerizedJava` from `build.jenesis.docker`:

```java
Path workingDirectory = Path.of("").toAbsolutePath();
installation.launch(command.mainClass(), List.of("--version"), new DockerizedJava(workingDirectory));
```

The single-argument constructor builds and reuses a minimal hardened image; `new DockerizedJava(directory,
"eclipse-temurin:25-jre")` names one instead.

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

`Jpx` is a record of four values - the storage folder, the repositories, the resolvers, and the hash
function - and each constructor leaves the rest at their defaults. A storage folder of your own keeps installs
out of `~/.jenesis/jpx`, which is what a test, a sandboxed tool, or a demo wants:

```java
Jpx jpx = new Jpx(Path.of("target", "jpx"));          // resolve by published coordinates
Jpx modular = new Jpx(Path.of("target", "jpx"), true); // resolve over module descriptors
```

The full constructor replaces the repositories and resolvers as well - the way to resolve from a private
mirror, or from a local folder with no network at all:

```java
URI mirror = URI.create("https://nexus.example.com/maven2/");
Jpx jpx = new Jpx(storage,
        Map.of("maven", new MavenDefaultRepository(mirror, local, Map.of("SHA256", mirror), _ -> { }, token)),
        Map.of("maven", new MavenPomResolver()),
        new HashDigestFunction("SHA-256"));
```

Repositories are keyed by the kind of coordinate they serve - `maven` for Maven coordinates and `module` for
module names - so a map that carries only `maven` supports only Maven coordinates, and a target that needs a
missing entry fails rather than silently reaching the public default.

<div class="note">
  The defaults are not hard-coded either: they are built from the same environment the build tool reads, so
  <code>MAVEN_REPOSITORY_URI</code> and <code>JENESIS_REPOSITORY_URI</code> - and their token and local-folder
  companions - already redirect a plain <code>new Jpx(false)</code> at a mirror. Construct the repositories
  yourself when the choice has to come from your program rather than from its environment.
</div>

<div class="tip">
  Installation is idempotent and safe to run from several processes at once, so a program does not have to
  track whether a target is present: call <code>install</code> every time and pay for the download only on the
  first run. The
  <a href="https://github.com/raphw/jenesis/tree/main/demo/demo-46-jpx">jpx demo</a> is this whole chapter as
  one runnable file - it installs the JUnit console launcher into its own <code>target/jpx/</code>, verifies
  it, and launches it.
</div>
