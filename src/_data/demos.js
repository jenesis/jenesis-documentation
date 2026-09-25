// The Jenesis build-tool demos, grouped for the Demos page. Each demo is a self-contained project in the
// jenesis repository under demo/<slug>; `repo` builds the link to its folder on GitHub.
//
// Keep this in sync with the demo/ directory of jenesis/jenesis (the list is stable and numbered). It is a
// committed data file rather than a build-time fetch so the docs build stays offline and can never be
// broken by a GitHub API hiccup.

export default {
  repo: "https://github.com/jenesis/jenesis/tree/main/demo",
  groups: [
    {
      title: "Getting started",
      blurb: "The four project shapes, what a build costs to start, and the JDK it runs on - begin here.",
      demos: [
        { slug: "demo-01-java-pom", name: "Java (Maven project)", blurb: "A single-module Java project in the classic Maven layout." },
        { slug: "demo-02-java-modular", name: "Java (modular project)", blurb: "The same, as a real Java Module System module with a module-info." },
        { slug: "demo-03-java-pom-multi", name: "Multi-module (Maven)", blurb: "Several Maven-layout modules built together." },
        { slug: "demo-04-java-modular-multi", name: "Multi-module (modular)", blurb: "A multi-module modular project and its module graph." },
        { slug: "demo-05-startup", name: "Startup cost", blurb: "What a build pays to launch, and what a reused JVM saves on the calls after it." },
        { slug: "demo-06-toolchain", name: "The JDK a build runs on", blurb: "A project names its JDK, and a build started on JDK 25 runs again on 26 in CI on Linux, macOS and Windows." },
      ],
    },
    {
      title: "Executables & packaging",
      blurb: "Turning a build's output into something that runs on its own.",
      demos: [
        { slug: "demo-07-java-pom-executable", name: "Executable (Maven)", blurb: "A runnable Maven project packaged with jpackage, plus bundle, launcher jar, and a container context." },
        { slug: "demo-08-java-modular-executable", name: "Executable (modular)", blurb: "The same for a module: an app image, a .jmod and jlink runtime, a bundle, a launcher jar, and a Dockerfile." },
        { slug: "demo-09-bundle", name: "Bundle", blurb: "Ship only the jars as a bundle.zip and run them on a stock JRE." },
        { slug: "demo-10-java-multi-release", name: "Multi-release JAR", blurb: "A multi-release jar that ships a Java 25 override of one class beside its Java 21 baseline." },
      ],
    },
    {
      title: "Compiler control",
      blurb: "Reaching past the compiler defaults.",
      demos: [
        { slug: "demo-11-javac-arguments", name: "Compiler arguments", blurb: "Passing custom arguments to javac." },
        { slug: "demo-12-annotations", name: "Annotation processing", blurb: "Running an annotation processor." },
        { slug: "demo-13-error-prone", name: "Error Prone", blurb: "A static-analysis plugin running inside javac, catching a bug the compiler accepts." },
      ],
    },
    {
      title: "Generated sources",
      blurb: "Compiling a schema or a service contract into Java, as part of the build.",
      demos: [
        { slug: "demo-14-data-formats", name: "Data formats", blurb: "Three modules and three wire formats - XML Schema, protocol buffers and Avro - each compiled into Java by its own generator." },
        { slug: "demo-15-service-contracts", name: "Service contracts", blurb: "A SOAP and a REST client generated from a WSDL and an OpenAPI document." },
        { slug: "demo-16-antlr", name: "Parser from a grammar", blurb: "An ANTLR grammar compiled into a lexer, a parser and a visitor that the module uses." },
      ],
    },
    {
      title: "Dependencies",
      blurb: "Naming what a project depends on, and shaping the closure that arrives.",
      demos: [
        { slug: "demo-17-maven-exclusions", name: "Exclusions", blurb: "Dropping an unwanted transitive, in a POM and with a tag." },
        { slug: "demo-18-bom", name: "Bills of materials", blurb: "Importing a Maven BOM and a local pin file, and publishing a BOM of the module's own closure." },
        { slug: "demo-19-module-alias", name: "Module alias", blurb: "Giving a plain jar a module name, then rewriting the closure into named modules so jlink accepts it." },
        { slug: "demo-20-module-layout", name: "Pure modular layout", blurb: "A strictly modular layout that resolves by module name and emits no POM." },
        { slug: "demo-21-module-override", name: "Module override", blurb: "Reading a shaded API under its own module name, so a modular library and Tomcat Embed share a module path." },
        { slug: "demo-22-module-layers", name: "Module layers", blurb: "Keeping a dependency private, so two versions of one library run in one JVM with no package relocated." },
        { slug: "demo-23-module-layer-legacy", name: "Module layers over a legacy tree", blurb: "Isolating a library whose jars name themselves nowhere, by naming only the one the code calls." },
        { slug: "demo-24-platform-guard", name: "Platform guard", blurb: "Pinning a classified variant, and guarding which one each platform gets." },
        { slug: "demo-25-platform-guard-pom", name: "Platform guard (Maven)", blurb: "The same guards in a Maven layout." },
      ],
    },
    {
      title: "Supply chain & security",
      blurb: "Which bytes arrived, who produced them, and what they carry.",
      demos: [
        { slug: "demo-26-pinning", name: "Pinning", blurb: "A version and a checksum in your own sources, and the two ways a build refuses what does not match." },
        { slug: "demo-27-openpgp", name: "OpenPGP signatures", blurb: "Declaring the key that signs a dependency, checked against the signature its project published." },
        { slug: "demo-28-sigstore", name: "Sigstore identities", blurb: "Declaring the workflow that released a dependency, verified from the bundle beside it with no key at all." },
        { slug: "demo-29-sbom", name: "SBOM", blurb: "Generating a software bill of materials." },
        { slug: "demo-30-compliance", name: "Dependency licensing", blurb: "Checking dependency licences against policy." },
        { slug: "demo-31-vulnerabilities", name: "Vulnerabilities", blurb: "Scanning dependencies for known vulnerabilities." },
      ],
    },
    {
      title: "Quality & testing",
      blurb: "The gates a build can hold its own output to.",
      demos: [
        { slug: "demo-32-java-quality", name: "Code quality", blurb: "Formatting and static analysis for Java." },
        { slug: "demo-33-test-framework", name: "Test frameworks", blurb: "Tests whose module requires no engine: the framework they are written against is worked out and its engines resolved." },
        { slug: "demo-34-code-coverage", name: "Code coverage", blurb: "Measuring test coverage." },
        { slug: "demo-35-test-selection", name: "Test selection", blurb: "Running only the tests a change can affect." },
        { slug: "demo-36-pitest", name: "Mutation testing", blurb: "Mutation testing with PIT, switched on by its configuration file." },
        { slug: "demo-37-jmh", name: "Benchmarks", blurb: "A JMH benchmark the build generates, compiles and runs, printing its result table." },
        { slug: "demo-38-api-compatibility", name: "API compatibility", blurb: "japicmp compares the built jar's byte code against a released one, so a breaking change shows up before you publish it." },
      ],
    },
    {
      title: "JVM languages",
      blurb: "The same build, for Kotlin, Scala and Groovy.",
      demos: [
        { slug: "demo-39-kotlin", name: "Kotlin", blurb: "A Kotlin (and mixed Java/Kotlin) project." },
        { slug: "demo-40-kotlin-quality", name: "Kotlin quality", blurb: "Kotlin with formatting and static-analysis checks." },
        { slug: "demo-41-kotlin-plugin", name: "Kotlin compiler plugin", blurb: "Enabling a Kotlin compiler plugin." },
        { slug: "demo-42-scala", name: "Scala", blurb: "A Scala (and mixed Java/Scala) project." },
        { slug: "demo-43-scala-quality", name: "Scala quality", blurb: "Scala with code-quality checks." },
        { slug: "demo-44-groovy", name: "Groovy", blurb: "A Groovy (and mixed Java/Groovy) project." },
        { slug: "demo-45-groovy-quality", name: "Groovy quality", blurb: "Groovy with code-quality checks." },
      ],
    },
    {
      title: "Running the build",
      blurb: "How a build is configured, cached, confined and instrumented.",
      demos: [
        { slug: "demo-46-profiles", name: "Build profiles", blurb: "Switching a set of settings on with a named profile, and writing a whole run into an argument file." },
        { slug: "demo-47-build-cache", name: "Build cache", blurb: "Sharing build outputs through a cache." },
        { slug: "demo-48-docker-isolation", name: "Docker isolation", blurb: "Confining the build and the launched program in a throwaway container." },
        { slug: "demo-49-agents", name: "Java agents", blurb: "Attaching agents to the test run and to the application run." },
        { slug: "demo-50-native-access", name: "Native access", blurb: "Naming the module that needs native access, and granting it again in every module that runs it." },
        { slug: "demo-51-native-access-layer", name: "Native access in a layer", blurb: "Granting a library native access, which it passes on to the modules it keeps in its layer." },
      ],
    },
    {
      title: "Extending the build",
      blurb: "Wrapping the template, adding build modules, or replacing it entirely.",
      demos: [
        { slug: "demo-52-custom-assembler", name: "Custom assembler", blurb: "Wrapping the stock assembler so sources are preprocessed before they compile." },
        { slug: "demo-53-custom-jmod", name: "jlink & jpackage", blurb: "A custom .jmod carrying extra content, linked into a runtime and packaged into an app." },
        { slug: "demo-54-internal-module", name: "Internal build module", blurb: "A plugin named in jenesis.plugins.properties, compiled from local source and configured by its own properties file." },
        { slug: "demo-55-external-module", name: "External build module", blurb: "The same plugin resolved by its module name from a repository." },
        { slug: "demo-56-project-plugins", name: "Project plugins", blurb: "Plugins hooked into the build of the whole project: a licence check before anything compiles, a notice attached to every module and checked before staging, a distribution zip beside the stock packages, checksums added to the staged trees and checked before export, an exporter that delivers them, and a line count run on demand without a build." },
        { slug: "demo-57-custom-maven", name: "Custom Maven build", blurb: "Driving a multi-module Maven-layout build from your own entry point with the convenience factory." },
        { slug: "demo-58-custom-modular", name: "Custom modular build", blurb: "The same for a modular project." },
        { slug: "demo-59-custom-build", name: "Custom build", blurb: "A code-generating build graph wired entirely by hand." },
        { slug: "demo-60-tools-api", name: "Running a build in-process", blurb: "A build, and the program it produced, run inside another program's JVM through java.util.spi.ToolProvider." },
      ],
    },
    {
      title: "Delivery",
      blurb: "Publishing what a build produced, and running what somebody else published.",
      demos: [
        { slug: "demo-61-code-signing", name: "Code signing", blurb: "The produced jar signed with jarsigner, with the key named by the machine rather than by the project." },
        { slug: "demo-62-export", name: "Exporting to the local repositories", blurb: "A module exported into the local repositories and required from a second project by name, with both repositories in a temporary folder." },
        { slug: "demo-63-publishing", name: "Publishing", blurb: "A Maven Central ready bundle - POM metadata, sources and javadoc jars - resolved back to prove it." },
        { slug: "demo-64-module-convention", name: "Your own module repository", blurb: "Modules published to a plain Maven repository and resolved back by module name, with no registry to keep in sync." },
        { slug: "demo-65-reproducible", name: "Reproducible builds", blurb: "A jar checked against a SHA-256 recorded in the demo, on Linux, macOS and Windows in CI." },
        { slug: "demo-66-native-image", name: "Native image", blurb: "A GraalVM native binary built end to end, with reachability metadata captured from the tests." },
        { slug: "demo-67-jpx", name: "Running a released program", blurb: "jpx installs and launches a published tool - named as a module and as a coordinate, pinned and hash-verified." },
      ],
    },
  ],
};
