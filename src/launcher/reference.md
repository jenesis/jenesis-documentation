---
order: 6
title: Reference
description: Every application.properties key and manifest attribute the launcher reads, which of them the build tool writes, and the embedding API - in one place.
---

Two files drive a launcher jar: the `application.properties` **descriptor** that tells the launcher what to
run, and the jar **manifest** that tells the JVM to start the launcher. When the build tool
[produces the jar](/launcher/producing-a-launcher-jar/), it writes `mainClass`, `mainModule` and `classpath`
into the descriptor and `Main-Class` into the manifest - nothing else. Everything else on this page is what
the launcher itself understands, for a jar you assemble yourself with the same layout: by hand, with a
script, or with another tool.

## The descriptor: `application.properties`

A plain `key=value` properties file at the jar root. Every key is optional; a descriptor without `mainClass`
describes a [Java agent](#bundled-java-agents) rather than an application.

| Key | Value | Written by the build tool |
| --- | --- | --- |
| `mainClass` | Fully qualified class whose `main` the launcher invokes. Absent → the jar is an agent, not an application. | yes |
| `mainModule` | The module owning `mainClass`, when the application is modular. | yes, for a modular application |
| `classpath` | Comma-separated `classpath/` subfolder names, in the order to search them. | yes |
| `agentClass` | Comma-separated [bundled agents](#bundled-java-agents) to run before `main`. | no |
| `addExports` | [`--add-exports` grants](#relaxing-module-access) applied to the bundled modules. | no |
| `addOpens` | [`--add-opens` grants](#relaxing-module-access). | no |
| `addReads` | [`--add-reads` grants](#relaxing-module-access). | no |
| `signature.<dep>` | [Base64 PKCS#7 chain](#emulating-a-signed-jar) restoring a class-path dependency's signer identity. | no |

### Class-path order

A class path is **ordered**: when two jars carry the same class or resource, the first wins. Exploding the
dependencies into subfolders would lose that order, so the descriptor records it:

```properties
mainClass=com.example.Main
classpath=dep1.jar,dep2.jar
```

The launcher searches its class path in this order; any `classpath/` subfolder the property does not name
follows, in name order. The build tool lists the subfolders in file-name order.

## <span id="bundled-java-agents">Bundled Java agents</span>

A launcher jar can carry its own Java agents. `agentClass` is a comma-separated list of fully qualified agent
class names, each optionally followed by `=<arguments>`, mirroring `-javaagent:<jar>=<arguments>`:

```properties
mainClass=com.example.Main
agentClass=net.bytebuddy.agent.Installer,com.example.Tracing=verbose
```

Entries are split on `,` first, so an agent's arguments cannot contain a comma. The launcher invokes each
agent's `premain` in declaration order **before the main class is loaded**, so a `ClassFileTransformer`
registered in `premain` still sees the main class being defined - exactly what `-javaagent` guarantees. As
the JVM does, it prefers `premain(String, Instrumentation)` and falls back to `premain(String)`. Agents are
loaded from the application's own loader, so they may live on the class path or the module path.

### Capturing an `Instrumentation`

There is a catch. `-javaagent:foo.jar` resolves a `Premain-Class` from the agent jar's *own* class path,
which never includes the exploded dependencies, so a bundled agent cannot obtain an `Instrumentation` that
way. The launcher ships one agent the JVM knows about, `build.jenesis.launcher.LauncherAgent`. Naming it in
the manifest captures a real `Instrumentation`, which the launcher hands to every bundled agent.

<div class="warning">
  Without one of the manifest attributes below, no <code>Instrumentation</code> is captured, and only agents
  that declare <code>premain(String)</code> can run. The launcher says so in its error message when an agent
  offers only the two-argument form.
</div>

### Agent jars

A launcher jar that declares **no** `mainClass` is itself a Java agent. Its manifest names `LauncherAgent`
as `Premain-Class` (for `-javaagent:foo.jar`) and/or `Agent-Class` (for dynamic attach), and you use it on a
*host* application:

```bash
java -javaagent:foo.jar=args -jar your-app.jar
```

The launcher builds the jar's own loader and runs its `agentClass` agents against the host's
`Instrumentation`, so the agent and its dependencies stay in their own isolated loader, off the host's class
path. The `=args` from the command line reach each agent that declares no `=<arguments>` of its own.

<div class="note">
  <strong>Several agent jars in one JVM.</strong> The JVM loads a <code>Premain-Class</code> by binary name
  only once, so two jars that both name <code>LauncherAgent</code> collide: the class resolves to the first
  jar, and both invocations run that jar's agents. For agent jars that must coexist, give each a
  <code>Premain-Class</code> of its own - a small class whose <code>premain</code> and <code>agentmain</code>
  call <code>Launcher.runAgents(MyPremain.class, attach, arguments, instrumentation)</code>. The launcher
  then resolves that class's own jar, with its own descriptor and dependencies.
</div>

## <span id="relaxing-module-access">Relaxing module access</span>

A bundled module sometimes needs reflective access that a framework expects but its `module-info` does not
declare. Three keys grant it - the in-jar equivalent of `--add-exports` / `--add-opens` / `--add-reads`,
applied to the bundled modules:

```properties
addExports=some.module/some.pkg=ALL-UNNAMED
addOpens=some.module/some.pkg=other.module,yet.another
addReads=some.module=java.sql
```

Directives within a property are separated by `;` and targets within a directive by `,`; a target is a module
name or `ALL-UNNAMED`. The **source must be one of the bundled modules** - only their encapsulation can be
opened this way - while the targets may be bundled, boot, or the unnamed module. To open a *boot* module to
your code, use the JDK's own executable-jar manifest attributes (`Add-Opens`, `Add-Exports`), which the JVM
honours under `java -jar`.

## <span id="emulating-a-signed-jar">Emulating a signed jar</span>

A dependency that shipped as a *signed* jar loses its signer identity when exploded: its signature files
(`META-INF/*.SF`, `*.RSA`/`*.DSA`/`*.EC`) become ordinary entries, so a class-path class would otherwise
define with a `CodeSource` that has no signers. A `signature.<dependency>` key restores it. The key suffix is
the dependency's `classpath/<name>/` folder name; the value is Base64 of the signer's PKCS#7 certificate
chain:

```properties
mainClass=com.example.Main
# Base64 of the signer's certificate chain (PKCS#7):
signature.guava.jar=MIIF...
```

For each such class-path dependency the launcher reconstructs a `CodeSigner` and attaches it to that
dependency's `CodeSource`, so `getCodeSigners()` and `getCertificates()` report the original signer.

<div class="warning">
  This <strong>attests</strong> a signer recorded when the jar was assembled - it is <strong>not</strong> a
  cryptographic re-verification of the bundled bytes. It applies only to class-path dependencies; a
  module-path class carries no signers, as on a real module path. Dependencies without an entry are
  unaffected.
</div>

## Manifest attributes

The outer jar's manifest is what connects `java -jar` (or `-javaagent:`) to the launcher. The build tool
writes `Main-Class`; the rest belong to a jar you assemble yourself, and appear only when it carries agents.

| Attribute | Value | When it is used |
| --- | --- | --- |
| `Main-Class` | `build.jenesis.launcher.Launcher` | Always - makes `java -jar foo.jar` start the launcher. |
| `Launcher-Agent-Class` | `build.jenesis.launcher.LauncherAgent` | An application that bundles agents; captures an `Instrumentation` before `main` under `java -jar foo.jar`. |
| `Premain-Class` | `build.jenesis.launcher.LauncherAgent` (or your own delegating class) | An agent jar attached with `java -javaagent:foo.jar`. |
| `Agent-Class` | `build.jenesis.launcher.LauncherAgent` (or your own delegating class) | An agent jar attached dynamically at run time. |
| `Can-Redefine-Classes` / `Can-Retransform-Classes` | `true` | Standard JVM agent attributes; set them when a bundled agent redefines or retransforms classes. The JVM reads them, not the launcher. |

One header is read from a **bundled** jar's own manifest rather than from the outer one:

| Header | Value | Meaning |
| --- | --- | --- |
| `Jenesis-Aliases` | `<module>=<groupId>/<artifactId>[,…]` | Written by the build tool into the manifest of a module that declared a [module alias](/tool/dependencies/). A bundled jar that declares no module identity of its own and whose file name encodes that coordinate is offered as an automatic module under the named module name - see [*How it works*](/launcher/how-it-works/). |

## Embedding the launcher

The launcher can be driven from a program of your own; both entry points take a jar file or an exploded
directory of the same layout.

| Call | What it does |
| --- | --- |
| `Launcher.run(Path location, String[] args)` | Runs the application at `location` in the current JVM: builds its loader and layer, runs its bundled agents, and invokes `main` with `args`. |
| `Launcher.runAgents(Path location, boolean attach, String arguments, Instrumentation instrumentation)` | Runs an agent jar's agents against the given `Instrumentation` - `premain` when `attach` is false, `agentmain` when true. Does nothing for an application jar. |
| `Launcher.runAgents(Class<?> premainClass, …)` | The same, locating the jar from `premainClass`'s code source - the form a delegating `Premain-Class` calls. |
