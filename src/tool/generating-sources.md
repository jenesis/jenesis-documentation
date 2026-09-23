---
order: 9
title: Generating sources
description: Compiling a schema, a service contract or a grammar into Java as part of the build - XML Schema, protocol buffers, Avro, WSDL, OpenAPI and ANTLR - each turned on by its configuration file, with the contract kept out of the artifact unless you want it there.
---

Plenty of Java starts life as something that is not Java: an XML schema, a `.proto` file, an Avro record, a
WSDL, an OpenAPI document, a grammar. Jenesis compiles all six into sources and hands them to the compiler in
the same module, the same way it wires in the quality tools: **there is no plugin to register**. A generator
turns itself on when its configuration file is present, and stays off when it is not.

The generated package is compiled into the module like any hand-written one, so `module-info.java` may export
it, and what the generated code imports - `jakarta.xml.bind`, `protobuf-java`, `avro` - stays an ordinary
declared dependency of the module.

## The six generators

Each file below lives in a **configuration folder** (`build.jenesis/` by default); *[Configuration](/tool/configuration/)*
covers where those folders sit. The file's presence is the switch and its contents configure the tool.

| File | Tool | Compiles |
| --- | --- | --- |
| `xjc.properties` | JAXB binding compiler | `.xsd` schemas, with `.xjb` bindings |
| `protoc.properties` | protoc | `.proto` definitions |
| `avro.properties` | avro-tools | `.avsc` schemas and `.avpr` protocols |
| `wsimport.properties` | JAX-WS `wsimport` | `.wsdl` descriptions, with `.xjb` bindings |
| `openapi.properties` | OpenAPI Generator | an OpenAPI document (`.yaml`, `.yml`, `.json`) |
| `antlr.properties` | ANTLR | `.g4` grammars |

An empty file is a complete configuration. This is a working Avro setup:

```
demo/avro/build.jenesis/avro.properties          # empty
demo/avro/sources/META-INF/build.jenesis/user.avsc
```

Every generator resolves its tool in its own dependency group, named after the tool and kept apart from your
project's dependencies. The version floats `RELEASE` until you pin it - see *[Pinning &amp; bills of
materials](/tool/pinning/)*, which is also where the checksums for these tools belong.

{% demos 13, 14, 15 %}

## Where the contracts live

A generator does not search your project. It reads one folder, and the build fills that folder for it.

By default it collects everything from `META-INF/build.jenesis/`, under both the module's sources and its
resources. Files keep the path they had below that folder, so `META-INF/build.jenesis/user/user.avsc`
reaches the tool as `user/user.avsc`. Only the kinds a tool compiles are collected: a `.proto` sitting beside
`user.avsc` never reaches avro-tools.

`META-INF/build.jenesis/` is the default for a reason: **the compiler never copies that folder into the
artifact**. The contract shapes the build without shipping in the jar.

When a contract must ship, name its folder instead:

```properties
# avro/build.jenesis/avro.properties
folders=schemas
```

Now `schemas/user.avsc` is read by the generator *and* packaged, for code that also reads the schema at run
time. A JAX-WS client is the common case among the other generators, since it reads its WSDL when the
service class is constructed. `folders` takes a comma-separated list, and each entry is searched under both
sources and resources.

<div class="note">
  Moving a contract between folders does not re-run the generator. The build links each file under the name
  the tool expects, so the tool sees the same input whatever the project calls the folder it came from.
</div>

## Configuring each generator

Only the keys listed for a tool are accepted; anything else fails the build by name. Every generator takes
`folders`, described above, and `arguments`, a whitespace-separated line passed to the tool verbatim.

### XML Schema

```properties
# xml/build.jenesis/xjc.properties
package=demo.order
```

Every `.xsd` in the folders is compiled and every `.xjb` passed as a binding. `catalog=<file>` names a
catalog; `package=<name>` sets the generated package.

### Protocol buffers

```properties
# protobuf/build.jenesis/protoc.properties
plugins=grpc-java=io.grpc/protoc-gen-grpc-java
```

Every `.proto` in the folders is compiled, and the folders themselves are the include path, so an `import`
resolves as it is written.

protoc is a native executable rather than a jar, resolved per operating system and chipset from a Maven
classifier. **Each platform therefore needs its own checksum pin**, guarded by platform token - a build on
Linux and a build on macOS fetch different bytes. `plugins=<name>=<groupId>/<artifactId>` resolves a protoc
plugin the same way, in its own `protoc-<name>` group; `classifier=<value>` overrides the detected platform.

### Avro

```properties
# avro/build.jenesis/avro.properties
```

Schemas and protocols compile in separate steps, so a module may carry either or both.

### WSDL

```properties
# soap/build.jenesis/wsimport.properties
package=demo.greeter
folders=wsdl
location=/wsdl/greeter.wsdl
```

`location` is **required**, and states where the description is served at run time: a class-path path for a
description the module ships, an endpoint URL otherwise. Without it, `wsimport` would compile the path the
build happened to read the file from into the artifact, which then fails on any other machine.

### OpenAPI

```properties
# rest/build.jenesis/openapi.properties
package=demo.greeting
arguments=--library native --additional-properties useJakartaEe=true
```

A lone `.yaml`, `.yml` or `.json` in the folders is the specification; a module that offers several names one
with `specification=<file>`. `generator=<name>` selects the OpenAPI generator (default `java`).

The OpenAPI Generator writes a whole project - a POM, a README, documentation, test scaffolding. Jenesis
collects **only its source folder** and discards the rest, so no generated `pom.xml` can reach your build.
That folder is `src/main/java` by default; a generator that writes elsewhere is named with `sources=<path>`.

### Grammars

```properties
# calc/build.jenesis/antlr.properties
package=demo.antlr.calc
arguments=-visitor -no-listener
```

Every `.g4` in the folders is compiled into a lexer, a parser and, when asked for, a visitor or a listener.
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

## Turning one off

Each generator has a switch, on by default:

```
-Djenesis.generate.xjc=false
```

The same shape works for `protoc`, `avro`, `wsimport`, `openapi` and `antlr`. All configuration keys are listed in the
*[Reference](/tool/reference/)*.
