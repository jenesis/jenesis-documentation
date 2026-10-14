---
order: 9
title: Generating sources
description: Compiling a schema, a service contract or a grammar into Java as part of the build - XML Schema, protocol buffers, Avro, WSDL, OpenAPI and ANTLR - and running Kotlin symbol processors, each a plugin that binds the contract it reads, kept out of the artifact unless you want it there.
---

Plenty of Java starts life as something that is not Java: an XML schema, a `.proto` file, an Avro record, a
WSDL, an OpenAPI document, a grammar. Plugins compile all six into sources and hand them to the compiler in
the same module. A line of `jenesis.plugins.properties` names each at the hook point `binary/generated`, whose
sources the module compiles with its own, and the plugin runs in a module where its `plugin-<name>.properties`
is found.

The generated package is compiled into the module like any hand-written one, so `module-info.java` may export
it, and what the generated code imports - `jakarta.xml.bind`, `protobuf-java`, `avro` - stays an ordinary
declared dependency of the module.

## The six generators

```properties
# jenesis.plugins.properties
avro+binary/generated=build.jenesis.plugin.avro
```

| Plugin | Tool | Compiles | Binds |
| --- | --- | --- | --- |
| `build.jenesis.plugin.xjc` | JAXB binding compiler | `.xsd` schemas, with `.xjb` bindings | `@schemas/xjc=<folder>` |
| `build.jenesis.plugin.protoc` | protoc | `.proto` definitions | `@definitions/protoc=<folder>` |
| `build.jenesis.plugin.avro` | avro-tools | `.avsc` schemas and `.avpr` protocols | `@schemas/avro=<folder>` |
| `build.jenesis.plugin.wsimport` | JAX-WS `wsimport` | `.wsdl` descriptions, with `.xjb` bindings | `@descriptions/wsimport=<folder>` |
| `build.jenesis.plugin.openapi` | OpenAPI Generator | an OpenAPI document | `@specification/openapi/openapi.yaml=<file>` |
| `build.jenesis.plugin.antlr` | ANTLR | `.g4` grammars | `@grammars/antlr=<folder>` |

A file that only binds the contracts is a complete configuration. This is a working Avro setup:

```
demo/avro/build.jenesis/plugin-avro.properties   # @schemas/avro=sources/META-INF/build.jenesis
demo/avro/sources/META-INF/build.jenesis/user.avsc
```

Every generator resolves its tool in its own dependency group, named after the plugin and kept apart from your
project's dependencies. The version floats `RELEASE` until you pin it - see *[Pinning &amp; bills of
materials](/tool/pinning/)*, which is also where the checksums for these tools belong.

{% demos 17, 18, 19 %}

## Where the contracts live

A generator does not search your project. It reads one folder, and the binding fills that folder for it:
`@schemas/avro=sources/META-INF/build.jenesis` places the folder, resolved against the module's own folder, as
`avro/` of the plugin's input `schemas`. Files keep the path they had below the bound folder, and only the kinds
a tool compiles are read: a `.proto` beside `user.avsc` never reaches avro-tools.

`META-INF/build.jenesis/` under the sources is a good home for a contract: **the compiler never copies that
folder into the artifact**. The contract shapes the build without shipping in the jar.

When a contract must ship, bind the folder it ships from instead:

```properties
# soap/META-INF/build.jenesis/plugin-wsimport.properties
@descriptions/wsimport=wsdl
```

A JAX-WS client is the common case, since it reads its WSDL when the service class is constructed. In a
`module-info.java` project a folder beside the sources ships as it stands, as `soap/wsdl/` does in the
service-contracts demo. In a `pom.xml` project the folder has to be in a resource directory to ship: as with
Maven, only what a compiler reads - `.java`, `.kt`, `.scala`, `.groovy` - is taken from a source directory,
and every other file there stays out of the jar.

<div class="note">
  Moving a contract between folders changes the binding, not what the generator is handed. A contract the
  tool identifies by name is bound under the name it expects, so renaming the file in the project does not
  re-run the generator either.
</div>

## Configuring each generator

Only the values listed for a tool are accepted; anything else fails the build by name. Every generator takes
`arguments`, a whitespace-separated line passed to the tool verbatim.

### XML Schema

```properties
# xml/build.jenesis/plugin-xjc.properties
package=demo.order
@schemas/xjc=sources/META-INF/build.jenesis
```

Every `.xsd` in the bound folder is compiled and every `.xjb` passed as a binding, and a file named `catalog`
is the catalog; `package=<name>` sets the generated package.

### Protocol buffers

```properties
# protobuf/build.jenesis/plugin-protoc.properties
plugins=grpc-java=io.grpc/protoc-gen-grpc-java
@definitions/protoc=sources/META-INF/build.jenesis
```

Every `.proto` in the bound folder is compiled, and the folder itself is the include path, so an `import`
resolves as it is written. Every `.proto` that a compile dependency carries is on the include path as well.
The `protoc` executable from Maven Central ships without the well-known types, but `protobuf-java`, which the
generated code needs anyway, carries them, so `import "google/protobuf/timestamp.proto";` resolves without
copying the file into the project.

protoc is a native executable rather than a jar, resolved per operating system and chipset from a Maven
classifier. **Each platform therefore needs its own checksum pin**, guarded by platform token - a build on
Linux and a build on macOS fetch different bytes. `plugins=<name>=<groupId>/<artifactId>` resolves a protoc
plugin the same way, in its own `protoc-<name>` group; `classifier=<value>` overrides the detected platform.

A version pinned for the artifact itself, `protoc/maven/com.google.protobuf/protoc <version>`, sets the version of
every platform's executable, but its checksum is that of another file, so each platform still pins its own.

`pin` refreshes only the line of the platform it runs on. To add another platform from one machine, write its
line yourself, guarded by that platform's tokens, with the SHA-256 of the executable Maven Central publishes
for its classifier, `protoc-<version>-<classifier>.exe`:

```text
@jenesis.pin protoc/maven/com.google.protobuf/protoc/exe/osx-aarch_64 <version> SHA-256/<hash> (macos,aarch64)
```

### Avro

```properties
# avro/build.jenesis/plugin-avro.properties
@schemas/avro=sources/META-INF/build.jenesis
```

Schemas and protocols compile in separate steps, so a module may carry either or both.

### WSDL

```properties
# soap/META-INF/build.jenesis/plugin-wsimport.properties
package=demo.greeter
location=/wsdl/greeter.wsdl
@descriptions/wsimport=wsdl
```

`location` is **required**, and states where the description is served at run time: a class-path path for a
description the module ships, an endpoint URL otherwise. Without it, `wsimport` would compile the path the
build happened to read the file from into the artifact, which then fails on any other machine.

### OpenAPI

```properties
# rest/META-INF/build.jenesis/plugin-openapi.properties
package=demo.greeting
arguments=--library native --additional-properties useJakartaEe=true
@specification/openapi/openapi.yaml=META-INF/build.jenesis/greeting.yaml
```

The specification is bound as `openapi.yaml`, or `openapi.yml` or `openapi.json`, whatever the file is called in
the project. `generator=<name>` selects the OpenAPI generator (default `java`).

The OpenAPI Generator writes a whole project - a POM, a README, documentation, test scaffolding. Jenesis
collects **only its source folder** and discards the rest, so no generated `pom.xml` can reach your build.
That folder is `src/main/java` by default; a generator that writes elsewhere is named with `sources=<path>`.

### Grammars

```properties
# calc/build.jenesis/plugin-antlr.properties
package=demo.antlr.calc
arguments=-visitor -no-listener
@grammars/antlr=META-INF/build.jenesis
```

Every `.g4` in the bound folder is compiled into a lexer, a parser and, when asked for, a visitor or a listener.
`arguments` reaches the tool verbatim, so every ANTLR flag applies.

`package=<name>` does double duty. ANTLR takes it as `-package`, which decides the package the generated
code declares, and the build takes it as the directory the sources are written to - so `package=demo.antlr.calc`
generates `demo/antlr/calc/CalcParser.java` and it compiles like any other source of the module. Without the
key the sources land in the default package, which a module declaration cannot export.

ANTLR writes `.tokens` and `.interp` files beside its sources while it runs. **Only the `.java` files survive
the step**, so nothing but sources reaches the jar.

As with every generator, the tool is not a dependency of your module. ANTLR resolves in its own `antlr`
group, and what the generated code calls into - `org.antlr.antlr4.runtime` - stays an ordinary `requires` of
the module, pinned separately. Upgrading the parser generator never moves the runtime your program links
against.

## Kotlin symbol processing

KSP is Kotlin's counterpart of annotation processing: a processor reads the module's own Kotlin and Java
sources and writes new ones beside them, as Moshi's code generator writes a JSON adapter for each class
annotated `@JsonClass(generateAdapter = true)`. The KSP plugin, `ksp+binary/generated=build.jenesis.plugin.ksp`,
runs where its `plugin-ksp.properties` is found, and the processors are declared like `javac`'s, by coordinate
in the group of the plugin's name:

```java
/**
 * @jenesis.plugin ksp maven/com.squareup.moshi/moshi-kotlin-codegen
 */
module demo.json { ... }
```

or, in a `pom.xml`, as the comment `<!--jenesis.plugin ksp maven/com.squareup.moshi/moshi-kotlin-codegen-->`.
Each line of `plugin-ksp.properties` is an option handed to the processors, the `arg(...)` of Gradle's `ksp { }`
block; an empty file runs them without any:

```properties
# build.jenesis/plugin-ksp.properties
moshi.generated=javax.annotation.processing.Generated
```

Unlike the six generators above, KSP binds no contract and reads the module's sources and its compile
dependencies, which is what lets a processor resolve the types the code uses. It runs before the compilers,
so the sources it writes are compiled with the module's own and the resources it writes, as a service file
or ProGuard rules, join the jar. KSP itself resolves in the group `ksp-runtime`, apart from the processors in
`ksp`, because a processor brings a Kotlin standard library of its own that KSP does not use. Its arguments
go in `process-ksp.properties`.

## Turning one off

Each generator is switched off by the plugin switch, which keeps its configuration in place:

```
-Djenesis.plugin.xjc=false
```

The same shape works for every plugin `jenesis.plugins.properties` names.
