---
order: 6
title: Reference
description: Every application.properties key and manifest attribute the launcher reads, which of them the build tool writes, and the embedding API - in one place.
---

Two files drive a launcher jar: the `application.properties` **descriptor** that tells the launcher what to
run, and the jar **manifest** that tells the JVM to start the launcher. When the build tool
[produces the jar](/launcher/producing-a-launcher-jar/), it writes `mainClass`, `mainModule`, `classpath`,
`modulepath` and the keys of each [module layer](#module-layers) into the descriptor, and `Main-Class` into
the manifest - nothing else. Everything else on this page is what
the launcher itself understands, for a jar you assemble yourself with the same layout: by hand, with a
script, or with another tool.

## The descriptor: `application.properties`

A plain `key=value` properties file at the jar root. Every key is optional; a descriptor without `mainClass`
describes a [Java agent](#bundled-java-agents) rather than an application.

| Key | Value | Written by the build tool |
| --- | --- | --- |
| `mainClass` | Fully qualified class whose `main` the launcher invokes. Absent → the jar is an agent, not an application. | yes |
| `mainModule` | The module owning `mainClass`, when the application is modular. | yes, for a modular application |
| `classpath` | Comma-separated `jars/` entry names to read as the unnamed module, in the order to search them. | yes |
| `modulepath` | Comma-separated `jars/` entry names to resolve as modules. | yes, empty when nothing is modular |
| `modulepath.<layer>` | Comma-separated `jars/` entry names a [module layer](#module-layers) resolves. | yes, for a project that declares one |
| `classpath.<layer>` | The same layer's class path, for jars that carry no module identity. | yes, when the layer holds any |
| `agentClass` | Comma-separated [bundled agents](#bundled-java-agents) to run before `main`. | no |
| `addExports` | [`--add-exports` grants](#relaxing-module-access) applied to the bundled modules. | no |
| `addOpens` | [`--add-opens` grants](#relaxing-module-access). | no |
| `addReads` | [`--add-reads` grants](#relaxing-module-access). | no |
| `enableNativeAccess` | Comma-separated bundled modules granted [native access](#granting-native-access). | yes, for what the running module grants |
| `enableNativeAccess.<layer>` | The same for the modules of a [module layer](#module-layers). | yes, for what the running module grants in the layer, or a granted module in a layer of its own |
| `signature.<dep>` | [Base64 PKCS#7 chain](#emulating-a-signed-jar) restoring a class-path dependency's signer identity. | no |

### Every path is named

The jar keeps its dependencies in one `jars/` store, and the descriptor says what each path holds. A jar is
read because a key names it, never because of the folder it sits in:

```properties
mainClass=com.example.Main
classpath=dep1.jar,dep2.jar
modulepath=com.example.app.jar,org.slf4j.jar
```

That also makes a class path **ordered**, which it must be: when two jars carry the same class or resource,
the first named wins. A name the store does not hold is refused rather than skipped, and a descriptor that
names none of the jars it ships is refused too - silence would otherwise surface much later, as a missing
main class.

### Module layers
A `modulepath.<layer>` key names the jars of one [module layer](/tool/dependencies/#keeping-a-dependency-private):
a second copy of a library, resolved into a layer of its own so that two versions run in one JVM with no
package relocated. Its jars are stored among the application's, so a jar both need is stored once and simply
loaded twice, and what keeps a layer's modules off the application's own module path is that `modulepath`
does not name them.

```properties
modulepath=com.example.app.jar,com.example.spi.jar
modulepath.render=com.example.impl.jar,com.fasterxml.jackson.core-2.15.4.jar
classpath.render=commons-logging-1.2.jar
```

A layer is named on its own, so every module that asks for it uses the same name. It is defined once per
calling module, as a child of that caller's layer, through the [layer API](#the-layer-api). Outside a
launcher jar - a deployment that unpacked its dependencies - the same two lists arrive as
`jlayer.modulepath.<layer>` and `jlayer.classpath.<layer>` system properties instead.

<div class="warning">
  <p>A layer that is not bundled in a launcher jar is defined from the <code>jlayer.*</code> system properties
  when a module first asks for it. The JVM lets any code overwrite a system property at any time and offers no
  way to protect one, so code that runs earlier - in the application or in an outer layer - can change which
  jars that layer holds, and so place its own code in another module's layer, outside the encapsulation that
  layer was declared for. A layer bundled in a launcher jar is read from the jar and is not affected.</p>
  <p>The same holds for <code>jlayer.enableNativeAccess.&lt;layer&gt;</code>: code that rewrites it can grant
  native access to a module it placed in the layer. The grant is made on behalf of the module that asks for the
  layer, so it never reaches further than that module's own native access. The JDK also defaults to
  <code>--illegal-native-access=warn</code>, where a restricted method called without a grant still runs and
  only prints a warning, so on most JVMs today the rewrite gains nothing the placed code could not already do.
  It becomes an escalation where the JVM is started with <code>--illegal-native-access=deny</code>. We are
  considering alternative mechanisms, and hope that by the time the JDK switches that default, the JVM offers a
  way to read the system properties as they were given at start-up.</p>
</div>

## Bundled Java agents
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

## Relaxing module access
A bundled module sometimes needs reflective access that a framework expects but its `module-info` does not
declare. Three keys grant it - the in-jar equivalent of `--add-exports` / `--add-opens` / `--add-reads`,
applied to the bundled modules:

```properties
addExports=some.module/some.pkg=ALL-UNNAMED
addOpens=some.module/some.pkg=other.module,yet.another
addReads=some.module=java.sql
```

Directives within a property are separated by `;` and targets within a directive by `,`; a target is a module
name or `ALL-UNNAMED`, which here means the jar's own class path. The **source must be one of the bundled
modules** - only their encapsulation can be opened this way - while the targets may be bundled, boot, or the
unnamed module. The keys apply only when `modulepath` names at least one jar; without a module path there is
no bundled module to relax, and they are ignored. To open a *boot* module to
your code, use the JDK's own executable-jar manifest attributes (`Add-Opens`, `Add-Exports`), which the JVM
honours under `java -jar`.

## Granting native access
A module that calls native code needs native access, which `java` grants with `--enable-native-access`. A
launcher jar is started with `java -jar`, so the grant travels in the jar instead:

```properties
enableNativeAccess=com.example.ffm
enableNativeAccess.render=com.example.native.renderer
```

`enableNativeAccess` names bundled modules on the module path; `enableNativeAccess.<layer>` names modules of
that layer, which the launcher grants when it defines the layer - a module that exists only in a layer is out
of reach of any command-line option. Outside a launcher jar the layer's list arrives as the
`jlayer.enableNativeAccess.<layer>` system property. A name that is not among the modules is refused. The
class path has no module to name: the outer jar's `Enable-Native-Access: ALL-UNNAMED` attribute grants it, and
it also covers the launcher itself, which grants the application's modules. A layer's modules are granted
through the lookup the module asking for the layer passes, so the JDK checks that module instead: without
native access of its own, it is warned about or refused as if it had granted the layer itself. The build
tool writes all three from the `@jenesis.native` declarations of the module it packages, and of each module it
grants for that module's own layers - see
[*Building &amp; running*](/tool/building-and-running/#granting-native-access).

## Emulating a signed jar
A dependency that shipped as a *signed* jar loses its signer identity when exploded: its signature files
(`META-INF/*.SF`, `*.RSA`/`*.DSA`/`*.EC`) become ordinary entries, so a class-path class would otherwise
define with a `CodeSource` that has no signers. A `signature.<dependency>` key restores it. The key suffix is
the dependency's `jars/<name>/` entry name; the value is Base64 of the signer's PKCS#7 certificate
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
writes `Main-Class`, and `Enable-Native-Access` for an application that grants native access; the rest belong
to a jar you assemble yourself, and appear only when it carries agents.

| Attribute | Value | When it is used |
| --- | --- | --- |
| `Main-Class` | `build.jenesis.launcher.Launcher` | Always - makes `java -jar foo.jar` start the launcher. |
| `Launcher-Agent-Class` | `build.jenesis.launcher.LauncherAgent` | An application that bundles agents; captures an `Instrumentation` before `main` under `java -jar foo.jar`. |
| `Enable-Native-Access` | `ALL-UNNAMED` | An application that grants native access; the JVM reads it under `java -jar` for the class path and the launcher. |
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

## The layer API
A module that keeps a dependency private declares the layer, requires `build.jenesis.launcher`, and asks for
it by name, passing its own `MethodHandles.lookup()`: the layer belongs to the class of that lookup, which the
launcher refuses unless it has full privilege access. The declaration is a build-tool feature -
[Keeping a dependency private](/tool/dependencies/#keeping-a-dependency-private) covers it - and these three
calls are how the running application reaches what it declared.

| Call | What it does |
| --- | --- |
| `Launcher.instance(Lookup lookup, String name, Class<S> service)` | The one provider of `service` in the layer `name`, instantiated. Refuses a layer that provides none, and one that provides several. |
| `Launcher.load(Lookup lookup, String name, Class<S> service)` | The same layer's providers as a `ServiceLoader`, for the cases that expect more than one. |
| `Launcher.layer(Lookup lookup, String name)` | The `ModuleLayer` itself, for anything a service lookup does not cover. |

All three refuse a layer that neither the caller's jar bundles nor a `jlayer.modulepath.<layer>` property
names. They also refuse a layer that provides a service while holding the module that declares it: the
caller would look the service up against a different class of the same name and find no provider, so that
module belongs outside the layer, shared with the caller.

The calling module needs no `uses` clause: naming the service in the call is the declaration, and the
launcher adds the service dependence to its own module, which `ServiceLoader` otherwise refuses because it
checks `uses` against the caller and offers no overload that takes one.

A layer is a child of its caller's, so every module it does not itself hold - the API module above all -
resolves from the caller and is the very same class on both sides. That is what lets an instance cross the
boundary as an ordinary interface call. A caller on the class path, in the unnamed module, hangs its layers
from the application's instead, and reaches them by the same name and the same calls.

The jars come from the jar the caller was loaded from when it declares them, read on demand like every other
bundled class; otherwise from the files named by `jlayer.modulepath.<layer>` and `jlayer.classpath.<layer>`,
read the way `java -p … -cp …` reads any module graph. Each value is split on the platform path separator
(`:`, or `;` on Windows), and each entry is a jar or a folder; the class-path key is optional. Those keys
are deliberately not `jenesis.*` properties: a `jenesis.*` property configures a build, and these are read
by the application a build produced.
