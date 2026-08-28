// The Jenesis build-tool demos, grouped for the Demos page. Each demo is a self-contained project in the
// jenesis repository under demo/<slug>; `repo` builds the link to its folder on GitHub.
//
// Keep this in sync with the demo/ directory of raphw/jenesis (the list is stable and numbered). It is a
// committed data file rather than a build-time fetch so the docs build stays offline and can never be
// broken by a GitHub API hiccup.

export default {
  repo: "https://github.com/raphw/jenesis/tree/main/demo",
  groups: [
    {
      title: "Getting started",
      blurb: "The four foundational project shapes - start here.",
      demos: [
        { slug: "demo-01-java-pom", name: "Java (Maven layout)", blurb: "A single-module Java project in the classic Maven layout." },
        { slug: "demo-02-java-modular", name: "Java (modular layout)", blurb: "The same, as a real Java Module System module with a module-info." },
        { slug: "demo-03-java-pom-multi", name: "Multi-module (Maven)", blurb: "Several Maven-layout modules built together." },
        { slug: "demo-04-java-modular-multi", name: "Multi-module (modular)", blurb: "A multi-module modular project and its module graph." },
      ],
    },
    {
      title: "Executables & packaging",
      blurb: "Turning a project into something you can ship and run - and running what somebody else shipped.",
      demos: [
        { slug: "demo-05-java-pom-executable", name: "Executable (Maven)", blurb: "A runnable Maven project packaged with jpackage, plus bundle, launcher jar, and a container context." },
        { slug: "demo-06-java-modular-executable", name: "Executable (modular)", blurb: "The same for a module: an app image, a .jmod and jlink runtime, a bundle, a launcher jar, and a Dockerfile." },
        { slug: "demo-07-bundle", name: "Bundle", blurb: "Ship only the jars as a bundle.zip and run them on a stock JRE." },
        { slug: "demo-37-custom-jmod", name: "jlink & jpackage", blurb: "A custom .jmod carrying extra content, linked into a runtime and packaged into an app." },
        { slug: "demo-46-native-image", name: "Native image", blurb: "A GraalVM native binary built end to end, with reachability metadata captured from the tests." },
        { slug: "demo-45-publishing", name: "Publishing", blurb: "A Maven Central ready bundle - POM metadata, sources and javadoc jars - resolved back to prove it." },
        { slug: "demo-47-jpx", name: "Running a released program", blurb: "jpx installs and launches a published tool - named as a module and as a coordinate, pinned and hash-verified." },
      ],
    },
    {
      title: "JVM languages",
      blurb: "Kotlin, Scala and Groovy - alone, mixed with Java, and with quality tooling.",
      demos: [
        { slug: "demo-16-kotlin", name: "Kotlin", blurb: "A Kotlin (and mixed Java/Kotlin) project." },
        { slug: "demo-17-kotlin-quality", name: "Kotlin quality", blurb: "Kotlin with formatting and static-analysis checks." },
        { slug: "demo-18-kotlin-plugin", name: "Kotlin compiler plugin", blurb: "Enabling a Kotlin compiler plugin." },
        { slug: "demo-19-scala", name: "Scala", blurb: "A Scala (and mixed Java/Scala) project." },
        { slug: "demo-20-scala-quality", name: "Scala quality", blurb: "Scala with code-quality checks." },
        { slug: "demo-21-groovy", name: "Groovy", blurb: "A Groovy (and mixed Java/Groovy) project." },
        { slug: "demo-22-groovy-quality", name: "Groovy quality", blurb: "Groovy with code-quality checks." },
      ],
    },
    {
      title: "Quality & testing",
      blurb: "Keeping a codebase healthy and tests fast.",
      demos: [
        { slug: "demo-11-java-quality", name: "Code quality", blurb: "Formatting and static analysis for Java." },
        { slug: "demo-23-code-coverage", name: "Code coverage", blurb: "Measuring test coverage." },
        { slug: "demo-24-test-selection", name: "Test selection", blurb: "Running only the tests a change can affect." },
        { slug: "demo-25-pitest", name: "Mutation testing", blurb: "Mutation testing with PIT, switched on by its configuration file." },
      ],
    },
    {
      title: "Supply chain & security",
      blurb: "Knowing, pinning and governing what your build depends on.",
      demos: [
        { slug: "demo-12-sbom", name: "SBOM", blurb: "Generating a software bill of materials." },
        { slug: "demo-13-compliance", name: "Dependency licensing", blurb: "Checking dependency licences against policy." },
        { slug: "demo-14-vulnerabilities", name: "Vulnerabilities", blurb: "Scanning dependencies for known vulnerabilities." },
        { slug: "demo-28-bom", name: "Bills of materials", blurb: "Importing a Maven BOM and a local pin file, and publishing a BOM of the module's own closure." },
        { slug: "demo-44-supply-chain-security", name: "Supply-chain security", blurb: "Strict pinning and checksum verification, proven by getting both wrong on purpose." },
      ],
    },
    {
      title: "The module system",
      blurb: "Working with the Java Module System in earnest.",
      demos: [
        { slug: "demo-08-java-multi-release", name: "Multi-release JAR", blurb: "A multi-release jar that ships a Java 25 override of one class beside its Java 21 baseline." },
        { slug: "demo-29-module-layout", name: "Pure modular layout", blurb: "A strictly modular layout that resolves by module name and emits no POM." },
        { slug: "demo-30-module-classifier", name: "Module classifier", blurb: "Pinning a classified variant of a module." },
        { slug: "demo-31-module-alias", name: "Module alias", blurb: "Giving a plain jar a module name, then rewriting the closure into named modules so jlink accepts it." },
        { slug: "demo-33-module-override", name: "Module override", blurb: "Reading a shaded API under its own module name, so a modular library and Tomcat Embed share a module path." },
        { slug: "demo-34-platform-guard", name: "Platform guard", blurb: "Selecting a dependency variant per platform." },
        { slug: "demo-35-platform-guard-pom", name: "Platform guard (Maven)", blurb: "The platform guard in a Maven layout." },
      ],
    },
    {
      title: "Build customisation",
      blurb: "Reaching past the defaults.",
      demos: [
        { slug: "demo-09-javac-arguments", name: "Compiler arguments", blurb: "Passing custom arguments to javac." },
        { slug: "demo-10-annotations", name: "Annotation processing", blurb: "Running an annotation processor." },
        { slug: "demo-15-profiles", name: "Build profiles", blurb: "Switching configuration with profiles." },
        { slug: "demo-26-agents", name: "Java agents", blurb: "Attaching agents to the test run and to the application run." },
        { slug: "demo-27-maven-exclusions", name: "Exclusions", blurb: "Dropping an unwanted transitive, in a POM and with a tag." },
        { slug: "demo-36-custom-assembler", name: "Custom assembler", blurb: "Wrapping the stock assembler so sources are preprocessed before they compile." },
        { slug: "demo-40-custom-maven", name: "Custom Maven build", blurb: "Driving a multi-module Maven-layout build from your own entry point with the convenience factory." },
        { slug: "demo-41-custom-modular", name: "Custom modular build", blurb: "The same for a modular project." },
        { slug: "demo-42-custom-build", name: "Custom build", blurb: "A code-generating build graph wired entirely by hand." },
        { slug: "demo-38-internal-module", name: "Internal build module", blurb: "A reusable build plugin compiled from local source." },
        { slug: "demo-39-external-module", name: "External build module", blurb: "The same plugin resolved as a published coordinate." },
        { slug: "demo-43-docker-isolation", name: "Docker isolation", blurb: "Confining the build and the launched program in a throwaway container." },
        { slug: "demo-47-build-cache", name: "Build cache", blurb: "Sharing build outputs through a cache." },
      ],
    },
  ],
};
