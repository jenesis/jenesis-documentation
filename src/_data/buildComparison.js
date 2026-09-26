// The build-tool landing page compares one build need at a time across four tools. Every file shown is read
// verbatim from src/_includes/build-comparison/<section>/<tool>/, where it was copied from a project that was built
// and run with that tool; nothing here is typed from memory. A section that extends the first build marks the
// lines it adds, and a file a command writes is shown collapsed, with its line count and the command.
import { readFileSync } from "node:fs";

const ROOT = new URL("../_includes/build-comparison/", import.meta.url);

function read(dir, path) {
  return readFileSync(new URL(`${dir}/${path}`, ROOT), "utf8").replace(/\s+$/, "");
}

// The lines of `lines` that a longest common subsequence with `base` does not cover. A blank line is never marked:
// it separates what was added, and is no addition of its own.
function additions(lines, base) {
  const table = Array.from({ length: lines.length + 1 }, () => new Array(base.length + 1).fill(0));
  for (let i = lines.length - 1; i >= 0; i--) {
    for (let j = base.length - 1; j >= 0; j--) {
      table[i][j] = lines[i] === base[j] ? table[i + 1][j + 1] + 1 : Math.max(table[i + 1][j], table[i][j + 1]);
    }
  }
  const added = new Array(lines.length).fill(true);
  for (let i = 0, j = 0; i < lines.length && j < base.length; ) {
    if (lines[i] === base[j]) {
      added[i] = false;
      i++;
      j++;
    } else if (table[i + 1][j] >= table[i][j + 1]) {
      i++;
    } else {
      j++;
    }
  }
  // The same addition can often be drawn a few lines higher or lower, when the lines around it repeat - a
  // </plugin> <plugin> pair, a closing brace. Of the positions an added run can slide to, take the one whose first
  // and last non-blank lines are the least indented, so a block is marked from its opening line to its closing one.
  const indent = (line) => (line.trim() === "" ? Infinity : line.length - line.trimStart().length);
  for (let first = 0; first < lines.length; first++) {
    if (!added[first] || (first > 0 && added[first - 1])) {
      continue;
    }
    let last = first;
    while (last + 1 < lines.length && added[last + 1]) {
      last++;
    }
    let up = 0, down = 0;
    while (first - up - 1 >= 0 && !added[first - up - 1] && lines[first - up - 1] === lines[last - up]) {
      up++;
    }
    while (last + down + 1 < lines.length && !added[last + down + 1] && lines[last + down + 1] === lines[first + down]) {
      down++;
    }
    let best = 0, score = Infinity;
    for (let shift = -up; shift <= down; shift++) {
      let top = first + shift, bottom = last + shift;
      while (top < bottom && lines[top].trim() === "") {
        top++;
      }
      while (bottom > top && lines[bottom].trim() === "") {
        bottom--;
      }
      const candidate = indent(lines[top]) + indent(lines[bottom]);
      if (candidate < score) {
        best = shift;
        score = candidate;
      }
    }
    for (let index = first; index <= last; index++) {
      added[index] = false;
    }
    for (let index = first + best; index <= last + best; index++) {
      added[index] = true;
    }
    first = last + Math.max(best, 0);
  }
  return added.map((mark, index) => mark && lines[index].trim() !== "");
}

// The lines strictly between a line containing `open` and the next line containing `close`, blank ones excepted:
// the entries of a block such as <dependencies> or deps = [...].
function between(lines, [open, close]) {
  let inside = false;
  return lines.map((line) => {
    if (inside && line.includes(close)) {
      inside = false;
    } else if (!inside && line.includes(open)) {
      inside = true;
      return false;
    }
    return inside && line.trim() !== "";
  });
}

// A file shown with its content. `base` names the section whose copy of the same file it extends; `mark` names the
// block whose entries are highlighted instead, such as the dependencies a build file declares a second time.
function file(dir, path, options = {}) {
  const text = read(dir, path);
  const lines = text.split("\n");
  const marks = options.base
    ? additions(lines, read(options.base, options.basePath ?? path).split("\n"))
    : options.mark
      ? between(lines, options.mark)
      : options.match
        ? lines.map((line) => line.includes(options.match))
        : lines.map(() => false);
  const marked = lines.map((line, index) => ({ text: line, added: marks[index] }));
  return {
    path,
    count: lines.length,
    lines: marked,
    segments: options.fold ? segments(marked, options.fold) : null,
    generated: options.generated,
    note: options.note,
  };
}

// Splits a file into runs of lines, folding each run whose lines contain `fold.match` behind `fold.label`, so the
// lines a command wrote can be told at a glance from the ones a person wrote.
function segments(lines, fold) {
  const runs = [];
  for (const line of lines) {
    const folded = line.text.includes(fold.match);
    const last = runs.at(-1);
    if (last && last.folded === folded) {
      last.lines.push(line);
    } else {
      runs.push({ folded, lines: [line] });
    }
  }
  return runs.map((run) => ({ ...run, label: run.folded ? fold.label.replace("{n}", run.lines.length) : null }));
}

// A file that is part of the project but not worth reading on the page: a binary keyring, a lock file.
function listed(path, count, generated, note) {
  return { path, count, generated, note, lines: null };
}

const JENESIS = { key: "jenesis", name: "Jenesis", release: "Jenesis 0.15.2" };
const MAVEN = { key: "maven", name: "Maven", release: "Maven 3.9.16" };
const GRADLE = { key: "gradle", name: "Gradle", release: "Gradle 9.8.0" };
const BAZEL = { key: "bazel", name: "Bazel", release: "Bazel 9.2.0" };

export default {
  tools: [JENESIS, MAVEN, GRADLE, BAZEL],

  statuses: {
    built: "Built in",
    plugin: "Plugin",
    manual: "By hand",
    none: "Not possible",
  },
  sections: [
    {
      id: "a-modular-build-in-java",
      title: "A modular build in Java",
      lede: `<p>A Java 25 application with four dependencies, written as a module. Its <code>module-info.java</code>
        is the Java Module System's own descriptor: it names what the module reads, and <code>javac</code>
        compiles and checks it. Jenesis takes it as the build. Its <code>requires</code> are the dependencies, two
        Javadoc tags set the release and the main class, and versions are optional pins in the same file.</p>
        <p>The other tools compile the same descriptor, but each dependency must be declared again in their own
        format - highlighted in their tabs.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "The module descriptor is the build file.",
          files: [file("basic/jenesis", "sources/module-info.java")],
        },
        maven: {
          status: "manual",
          badge: "Declared twice",
          verdict: "Every <code>requires</code> again as a <code>&lt;dependency&gt;</code>.",
          files: [
            file("modular/maven", "src/main/java/module-info.java"),
            file("modular/maven", "pom.xml", { mark: ["<dependencies>", "</dependencies>"] }),
          ],
          notes: ["A third-party extension derives them from <code>requires</code>, but the published POM then lists no dependencies."],
        },
        gradle: {
          status: "manual",
          badge: "Declared twice",
          verdict: "Every <code>requires</code> again as <code>implementation(...)</code>.",
          files: [
            file("modular/gradle", "src/main/java/module-info.java"),
            file("modular/gradle", "build.gradle.kts", { mark: ["dependencies {", "}"] }),
            file("modular/gradle", "settings.gradle.kts"),
            file("modular/gradle", "gradle/wrapper/gradle-wrapper.properties", { generated: "gradle wrapper" }),
          ],
          notes: ["GradleX's third-party plugin derives them from <code>requires</code>; the versions then go into a version catalog."],
        },
        bazel: {
          status: "manual",
          badge: "Declared three times",
          verdict: "Every <code>requires</code> again as a coordinate and as a label. It runs on the class path.",
          files: [
            file("modular/bazel", "src/main/java/module-info.java"),
            file("basic/bazel", "MODULE.bazel", { mark: ["artifacts = [", "],"] }),
            file("basic/bazel", "BUILD.bazel", { mark: ["deps = [", "],"] }),
            file("basic/bazel", ".bazelrc", { note: "Without it rules_java compiles for Java 11." }),
            file("basic/bazel", ".bazelversion"),
            listed("MODULE.bazel.lock", 814, "Bazel, on every build"),
          ],
        },
      },
    },
    {
      id: "tests-with-junit-6",
      title: "Tests with JUnit 6",
      lede: `<p>A Jenesis test is a module of its own. It names the module it tests and requires the JUnit API;
        the engine and the console runner follow from that, so neither is declared. The module under test lets the
        tests in with a qualified export - <code>exports demo.app to demo.app.test</code> - and no other module
        can read the package.</p>`,
      extra: "tests",
      tools: {
        jenesis: {
          status: "built",
          verdict: "A test module that names the module it tests. The engine is inferred.",
          files: [
            file("tests/jenesis", "tests/module-info.java"),
            file("tests/jenesis", "sources/module-info.java", { base: "basic/jenesis" }),
          ],
          notes: ["Tests see what the module under test exports to them, and nothing else."],
        },
        maven: {
          status: "built",
          verdict: "One test dependency. Surefire runs JUnit 6 unchanged.",
          files: [file("tests/maven", "pom.xml", { base: "basic/maven" })],
          notes: ["Tests live in the same package, compiled on top of the main classes."],
        },
        gradle: {
          status: "built",
          verdict: "<code>useJUnitPlatform()</code> and an explicit launcher dependency.",
          files: [file("tests/gradle", "build.gradle.kts", { base: "basic/gradle" })],
          notes: ["Without <code>junit-platform-launcher</code> on the test runtime path, Gradle 9 cannot start the JUnit Platform."],
        },
        bazel: {
          status: "plugin",
          badge: "Community ruleset",
          verdict: "<code>java_test</code> runs JUnit 4 only. JUnit 6 takes <code>java_junit5_test</code> from contrib_rules_jvm.",
          files: [
            file("tests/bazel", "MODULE.bazel", { base: "basic/bazel" }),
            file("tests/bazel", "BUILD.bazel", { base: "basic/bazel" }),
          ],
          notes: [
            "A plain <code>java_test</code> with a Jupiter class fails with <em>No runnable methods</em>.",
            "Every JUnit artifact the runner needs is listed by hand in <code>MODULE.bazel</code>.",
          ],
        },
      },
    },
    {
      id: "several-modules-one-build",
      title: "Several modules, one build",
      lede: `<p>A library and the application that uses it, built together. In Jenesis the Java module name is how
        one module of the project refers to another: <code>requires demo.greeter</code> is all the wiring there
        is, and the sibling is built first and resolved from the build itself. There is no root file.</p>
        <p>The other tools know a module by a name of their own - an artifactId, a project path, a label - so each
        sibling is named twice, and the two names are kept in step by hand. The second one is highlighted in their
        tabs.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "The module name is the reference. No root file.",
          files: [file("modules/jenesis", "greeter/module-info.java"), file("modules/jenesis", "app/module-info.java")],
        },
        maven: {
          status: "manual",
          badge: "Named twice",
          verdict: "<code>requires demo.greeter</code>, and again as the artifactId <code>greeter</code>.",
          files: [
            file("modules/maven", "app/src/main/java/module-info.java"),
            file("modules/maven", "app/pom.xml", { match: "<artifactId>greeter</artifactId>" }),
            file("modules/maven", "greeter/src/main/java/module-info.java"),
            file("modules/maven", "greeter/pom.xml"),
            file("modules/maven", "pom.xml"),
          ],
        },
        gradle: {
          status: "manual",
          badge: "Named twice",
          verdict: "<code>requires demo.greeter</code>, and again as the project <code>:greeter</code>.",
          files: [
            file("modules/gradle", "app/src/main/java/module-info.java"),
            file("modules/gradle", "app/build.gradle.kts", { match: 'project(":greeter")' }),
            file("modules/gradle", "greeter/src/main/java/module-info.java"),
            file("modules/gradle", "greeter/build.gradle.kts"),
            file("modules/gradle", "settings.gradle.kts"),
            file("modules/gradle", "gradle.properties"),
          ],
          notes: ["GradleX's third-party plugin, applied in the settings, finds the project from <code>requires demo.greeter</code> by reading its descriptor."],
        },
        bazel: {
          status: "manual",
          badge: "Named twice",
          verdict: "<code>requires demo.greeter</code>, and again as the label <code>//greeter</code>.",
          files: [
            file("modules/bazel", "app/src/main/java/module-info.java"),
            file("modules/bazel", "app/BUILD.bazel", { match: '"//greeter"' }),
            file("modules/bazel", "greeter/src/main/java/module-info.java"),
            file("modules/bazel", "greeter/BUILD.bazel"),
            file("modules/bazel", "MODULE.bazel"),
          ],
        },
      },
    },
    {
      id: "one-jar-for-java-21-and-25",
      title: "One jar for Java 21 and Java 25",
      lede: `<p>A multi-release jar carries a Java 21 baseline and, for one class, a second implementation that only
        a Java 25 runtime loads. With Jenesis the additional sources go where they end up in the jar, under
        <code>META-INF/versions/25/</code>; the build compiles them for 25 in a second pass and marks the
        manifest.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "Sources under <code>META-INF/versions/25/</code> are the whole configuration.",
          files: [file("multi-release/jenesis", "sources/module-info.java")],
          layout: `sources/
├── module-info.java
├── demo/app/Main.java
├── demo/app/Platform.java                        compiled for Java 21
└── META-INF/versions/25/demo/app/Platform.java   compiled for Java 25`,
        },
        maven: {
          status: "built",
          verdict: "Built in, but configured: a second compiler execution and the manifest entry.",
          files: [file("multi-release/maven", "pom.xml")],
          notes: ["The Java 25 sources sit in <code>src/main/java25</code>, a folder the second execution names."],
        },
        gradle: {
          status: "manual",
          verdict: "No built-in support: a source set and the jar layout by hand.",
          files: [file("multi-release/gradle", "build.gradle.kts")],
          notes: ["The long-used <code>val java25 by sourceSets.creating</code> is deprecated in Gradle 9.8."],
        },
        bazel: {
          status: "manual",
          verdict: "No rule builds one: a genrule unpacks two jars and packs them again.",
          files: [file("multi-release/bazel", "BUILD.bazel")],
          notes: ["The genrule runs the host's <code>unzip</code>, which the build does not provide."],
        },
      },
    },
    {
      id: "kotlin-with-a-compiler-plugin",
      title: "Kotlin with a compiler plugin",
      lede: `<p>Kotlin sources and the kotlinx.serialization compiler plugin, targeting JVM 25. Jenesis sees the
        <code>.kt</code> files and runs the Kotlin compiler before <code>javac</code>; the plugin is one
        <code>@jenesis.plugin</code> line, resolved in the compiler's own dependency group. The compiler and the
        plugin are pinned here.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "The compiler is inferred; the plugin is one line.",
          files: [file("kotlin/jenesis", "sources/module-info.java")],
        },
        maven: {
          status: "plugin",
          badge: "Official plugin",
          verdict: "JetBrains' <code>kotlin-maven-plugin</code>, with the serialization plugin as its dependency.",
          files: [file("kotlin/maven", "pom.xml")],
          notes: ["As a build extension, the Kotlin plugin quietly replaces the compiler and Surefire plugins with older versions and runs kapt with nothing to process."],
        },
        gradle: {
          status: "plugin",
          badge: "Official plugin",
          verdict: "Two JetBrains plugins.",
          files: [file("kotlin/gradle", "build.gradle.kts")],
          notes: ["With a <code>module-info.java</code> the build fails until about six lines of hand-written <code>--patch-module</code> arguments are added."],
        },
        bazel: {
          status: "plugin",
          badge: "Community ruleset",
          verdict: "rules_kotlin, with a toolchain of your own for JVM 25.",
          files: [file("kotlin/bazel", "MODULE.bazel"), file("kotlin/bazel", "BUILD.bazel")],
          notes: ["The default Kotlin toolchain targets JVM 1.8; rules_kotlin accepts targets up to 25."],
        },
      },
    },
    {
      id: "classes-from-an-avro-schema",
      title: "Classes from an Avro schema",
      lede: `<p>A schema compiled into Java as part of the build, next to a hand-written class that uses it. With
        Jenesis the schema sits in the build's own folder beside the sources, and an empty
        <code>avro.properties</code> switches the generator on. The schema is an input to the build and is not
        copied into the jar.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "An empty file switches the generator on.",
          files: [
            file("avro/jenesis", "sources/module-info.java"),
            listed("sources/META-INF/build.jenesis/avro.properties", 0, null, "Empty."),
            file("avro/jenesis", "sources/META-INF/build.jenesis/user.avsc"),
          ],
        },
        maven: {
          status: "plugin",
          badge: "Official plugin",
          verdict: "Apache Avro's own <code>avro-maven-plugin</code>.",
          files: [file("avro/maven", "pom.xml"), file("avro/maven", "src/main/avro/user.avsc")],
        },
        gradle: {
          status: "plugin",
          badge: "Third-party plugin",
          verdict: "Apache Avro publishes no Gradle plugin; a community fork fills the gap.",
          files: [file("avro/gradle", "build.gradle.kts"), file("avro/gradle", "src/main/avro/user.avsc")],
          notes: ["<code>com.bakdata.gradle.avro</code> is a fork of the plugin most builds used, which was archived in 2023."],
        },
        bazel: {
          status: "manual",
          verdict: "No Avro ruleset works on Bazel 9: a genrule runs avro-tools.",
          files: [file("avro/bazel", "MODULE.bazel"), file("avro/bazel", "BUILD.bazel"), file("avro/bazel", "src/main/avro/user.avsc")],
          notes: ["The ruleset on offer fails to load on Bazel 9, and none is in the Bazel Central Registry."],
        },
      },
    },
    {
      id: "the-same-bytes-every-time",
      title: "The same bytes, every time",
      lede: `<p>Two clean checkouts, built a minute apart in different folders, with a different time zone and
        <code>umask</code>, should produce the same jar. Jenesis writes every archive with a fixed entry order,
        no Unix permissions and one date on every entry, so the jar, its POM and its SBOM come out byte-identical
        with nothing to configure.</p>
        <p>Checking it is a different matter. None of the four tools records a digest of its output and compares
        it on every build; the rows below say what each offers instead.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "Identical out of the box: delete <code>target</code>, build again, same digest.",
          files: [],
          terminal: [
            "$ java build/jenesis/Make.java stage",
            "$ find target/stage -type f -exec sha256sum {} + | sort -k 2 | sha256sum",
            "991d3151daab4f88b5f7be0f0589c1ce68913f63d862bdb16ba1e947fc801b61  -",
            "$ rm -rf target",
            "$ java build/jenesis/Make.java stage",
            "$ find target/stage -type f -exec sha256sum {} + | sort -k 2 | sha256sum",
            "991d3151daab4f88b5f7be0f0589c1ce68913f63d862bdb16ba1e947fc801b61  -",
          ],
          notes: ["<code>jenesis.archive.timestamp</code> sets another date, such as the last commit's."],
        },
        maven: {
          status: "manual",
          badge: "Opt-in",
          verdict: "Not by default: one property makes it identical; an Apache plugin compares a rebuild.",
          files: [file("reproducible/maven", "pom.xml", { base: "basic/maven" })],
          commands: "mvn clean verify org.apache.maven.plugins:maven-artifact-plugin:3.7.0:compare",
          notes: [
            "Without <code>project.build.outputTimestamp</code> every entry carries the build's local time, and two builds differ.",
            "<code>artifact:compare</code> checks a rebuild against a reference, by default the release on Maven Central, and fails when a byte differs. It runs when asked, not on every build.",
            "The manifest records the JDK's major version, so a build on another major version differs.",
          ],
        },
        gradle: {
          status: "built",
          verdict: "Identical out of the box since Gradle 9. Nothing checks it.",
          files: [file("basic/gradle", "build.gradle.kts", { note: "A plain Java 25 build, unchanged." })],
          notes: [
            "Gradle 9.8's archive defaults already fix the entry dates and order: <code>preserveFileTimestamps=false</code>, <code>reproducibleFileOrder=true</code>.",
            "Gradle records no digest of what it builds; the reproducibility plugins only change the settings.",
          ],
        },
        bazel: {
          status: "built",
          verdict: "Identical out of the box. Comparing two builds is up to you.",
          files: [
            file("basic/bazel", "BUILD.bazel", { note: "Section 1's build, unchanged." }),
            file("reproducible/bazel", "compare_execlogs.py", { note: "Hand-written: compares the output hashes in two execution logs." }),
          ],
          commands: "bazel build //:app_deploy.jar --execution_log_json_file=a.json\npython3 compare_execlogs.py a.json b.json",
          notes: [
            "Bazel caches by inputs and never compares outputs; its documentation points to execution logs.",
            "Both builds must be clean, since an incremental build logs only the actions it ran.",
          ],
        },
      },
    },
    {
      id: "verify-what-the-build-downloads",
      title: "Verify what the build downloads",
      lede: `<p>Three checks on every dependency: a SHA-256 checksum recorded in the project, an OpenPGP signature
        from a key you trust, and a Sigstore identity where the publisher signs that way. Jenesis has all three
        built in and does the bookkeeping: <code>java build/jenesis/Make.java pin</code> resolves every
        dependency and writes its version and checksum into the module descriptor.</p>
        <p>What you write is whom you trust - one line per signer, naming a key fingerprint or a repository for a
        group of artifacts, so it outlives version bumps - and two switches in <code>jenesis.properties</code> that
        make a missing checksum or signature an error.</p>`,
      extra: "supply-chain",
      tools: {
        jenesis: {
          status: "built",
          verdict: "<code>pin</code> writes every checksum; you name whom you trust.",
          files: [
            file("supply-chain/jenesis", "sources/module-info.java", {
              fold: { match: "@jenesis.pin ", label: "{n} lines written by pin - a version and SHA-256 checksum for every dependency" },
            }),
            file("supply-chain/jenesis", "jenesis.properties"),
          ],
          commands: "java build/jenesis/Make.java pin",
          notes: [
            "<code>pin</code> resolves the whole dependency tree and records each version with its SHA-256. With <code>-Djenesis.dependency.pin=ignore</code> it resolves again and rewrites them.",
            "OpenPGP signatures are checked by the system's <code>gpgv</code>, so it must be installed.",
            "Sigstore bundles are checked in process, with the JDK's own cryptography.",
          ],
        },
        maven: {
          status: "plugin",
          badge: "Third-party plugin",
          verdict: "Checksums built in; signatures only through third-party plugins.",
          files: [
            file("supply-chain/maven", "pom.xml", { base: "basic/maven" }),
            file("supply-chain/maven", ".mvn/maven.config"),
            file("supply-chain/maven", "sigmund.yaml"),
            file("supply-chain/maven", ".mvn/checksums/checksums.sha256", { generated: "mvn -Daether.artifactResolver.postProcessor.trustedChecksums.record=true" }),
            listed(".gnupg/pubring.kbx", null, null, "A keyring assembled by hand for two signers whose keys the plugin cannot fetch."),
          ],
          notes: [
            "Sigstore takes Sigmund 0.0.2; its generated configuration was wrong, so <code>sigmund.yaml</code> is written by hand.",
            "Sigmund needs a rule for every dependency, so adding Sigstore for one means OpenPGP entries for all.",
            "pgpverify-maven-plugin is the established choice for OpenPGP alone.",
          ],
        },
        gradle: {
          status: "manual",
          verdict: "Checksums and OpenPGP built in; Sigstore only as hand-written build code.",
          files: [
            file("supply-chain/gradle", "build.gradle.kts", { base: "basic/gradle" }),
            file("supply-chain/gradle", "gradle/verification-metadata.xml", { generated: "./gradlew --write-verification-metadata pgp,sha256 --export-keys" }),
            file("supply-chain/gradle", "gradle/verification-keyring.keys", { generated: "./gradlew --write-verification-metadata pgp,sha256 --export-keys" }),
          ],
          notes: [
            "When a signing key cannot be fetched from a key server, Gradle falls back to the checksum for that artifact and marks the key as ignored - slf4j's here.",
            "No Gradle plugin verifies Sigstore bundles; the ones that exist sign.",
          ],
        },
        bazel: {
          status: "manual",
          verdict: "Checksums built in; OpenPGP and Sigstore only as hand-written genrules.",
          files: [
            file("supply-chain/bazel", "MODULE.bazel", { base: "basic/bazel" }),
            file("supply-chain/bazel", "BUILD.bazel", { base: "basic/bazel" }),
            file("supply-chain/bazel", "maven_install.json", { generated: "REPIN=1 bazel run @maven//:pin" }),
            listed("trusted-keys.asc", 175, null, "The signers' public keys, exported by hand."),
            listed("signatures/*.asc, *.sigstore.json", null, null, "Eight signature files, downloaded by hand next to the build."),
          ],
          notes: [
            "The OpenPGP genrule runs the host's <code>gpg</code>; the Sigstore genrule a pinned <code>cosign</code> binary.",
            "A new dependency means a new signature file and a new line in <code>BUILD.bazel</code>.",
          ],
        },
      },
    },
    {
      id: "a-bill-of-materials",
      title: "A bill of materials",
      lede: `<p>A CycloneDX SBOM that says what the release is, who makes it, under which licence, and what it
        contains: every dependency, transitive ones included, with its checksum and its licence. Jenesis writes one
        into every jar and stages it beside the jar for publishing, with nothing to switch on.</p>
        <p>The project's metadata is declared once, in <code>project.properties</code>, and the same values fill
        the generated POM. Two clean builds give the same SBOM, byte for byte.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "On by default, inside the jar and beside it. The metadata is one file.",
          files: [
            file("sbom/jenesis", "project.properties"),
            file("sbom/jenesis", "jenesis.properties"),
            file("basic/jenesis", "sources/module-info.java", { note: "Section 1's descriptor, unchanged." }),
          ],
          commands: "java build/jenesis/Make.java stage",
          notes: [
            "The organisation becomes the supplier, beside the manufacturer, the publisher, the copyright, the licence and the links to the website and the repository.",
            "Each dependency is listed once, with its purl, the same SHA-256 <code>pin</code> records, and its licence.",
          ],
        },
        maven: {
          status: "plugin",
          badge: "CycloneDX plugin",
          verdict: "The CycloneDX plugin reads the pom. A copyright, supplier or manufacturer has no place in it.",
          files: [file("sbom/maven", "pom.xml", { base: "basic/maven" })],
          commands: "mvn install",
          notes: [
            "The organisation only becomes the publisher; the developers and the display name are dropped.",
            "The SBOM is attached and installed beside the jar.",
            "It is reproducible once <code>project.build.outputTimestamp</code> is set; without it, every build writes its own timestamp.",
          ],
        },
        gradle: {
          status: "plugin",
          badge: "CycloneDX plugin",
          verdict: "The CycloneDX plugin, with the metadata declared a second time. A new file on every build.",
          files: [file("sbom/gradle", "build.gradle.kts", { base: "basic/gradle" })],
          commands: "./gradlew cyclonedxDirectBom publish",
          notes: [
            "The plugin does not read the <code>pom { }</code> block, so the metadata goes there for the POM and again on the task.",
            "A description, publisher, copyright or developer cannot be expressed; the licence and organisation describe the document, not the application.",
            "Every build writes a new timestamp, and no setting fixes it.",
            "Publishing the SBOM beside the jar is a hand-written <code>artifact(...)</code> line.",
          ],
        },
        bazel: {
          status: "manual",
          badge: "Ruleset from Git",
          verdict: "Nothing built in. A ruleset pulled from Git writes a thin SBOM.",
          files: [
            file("sbom/bazel", "MODULE.bazel", { base: "basic/bazel" }),
            file("sbom/bazel", "BUILD.bazel", { base: "basic/bazel" }),
          ],
          commands: "bazel build //:app_cyclonedx",
          notes: [
            "The releases of bazel-contrib's supply-chain rules with a CycloneDX rule are not in the Bazel Central Registry, and the generator is Go, built from source.",
            "Components carry a purl but no hash and no licence, and the application carries no metadata beyond its purl.",
            "The dependencies come out in a different order on every clean build, so no two SBOMs are the same file.",
          ],
        },
      },
    },
    {
      id: "two-versions-of-one-library",
      title: "Two versions of one library",
      lede: `<p>The application uses jackson-core 2.22.3; a library it depends on needs 2.15.4. With Jenesis the
        library keeps its jackson-core in a module layer of its own: the application declares nothing and never
        learns that a second version exists. Both run in one JVM, under their own names, from jars nobody has
        rewritten. The other tools shade: they copy the library's jackson-core into its jar and rename every class
        in it.</p>`,
      extra: "layers",
      tools: {
        jenesis: {
          status: "built",
          verdict: "A module layer. Nothing is copied or renamed.",
          files: [
            file("layers/jenesis", "library/module-info.java"),
            file("layers/jenesis", "impl/module-info.java"),
            file("layers/jenesis", "api/module-info.java"),
            file("layers/jenesis", "app/module-info.java"),
          ],
          notes: [
            "The layer needs an API module that crosses its boundary and a provider module that holds the private dependency; the library looks the provider up through the Jenesis Launcher.",
            "It runs from the launcher jar, the bundle and the container image, and with plain <code>java</code> given <code>-Djlayer.modulepath.jackson</code>.",
          ],
        },
        maven: {
          status: "plugin",
          badge: "Official plugin",
          verdict: "The Apache <code>maven-shade-plugin</code> relocates jackson-core.",
          files: [file("layers/maven", "pom.xml"), file("layers/maven", "library/pom.xml"), file("layers/maven", "app/pom.xml")],
          notes: [
            "Before <code>package</code> - a multi-module <code>mvn compile</code>, a test run, the IDE - the library runs on the application's 2.22.3.",
          ],
        },
        gradle: {
          status: "plugin",
          badge: "Third-party plugin",
          verdict: "The community Shadow plugin relocates jackson-core.",
          files: [
            file("layers/gradle", "settings.gradle.kts"),
            file("layers/gradle", "build.gradle.kts"),
            file("layers/gradle", "gradle.properties"),
            file("layers/gradle", "library/build.gradle.kts"),
            file("layers/gradle", "app/build.gradle.kts"),
          ],
          notes: [
            "Without <code>mergeServiceFiles()</code> the shaded jar keeps a service file that names the original jackson class.",
            "The application has to ask for the <code>shadow</code> configuration of the library explicitly.",
          ],
        },
        bazel: {
          status: "plugin",
          badge: "Third-party ruleset",
          verdict: "No built-in relocation: <code>bazel_jar_jar</code>, after merging the jars.",
          files: [
            file("layers/bazel", "MODULE.bazel"),
            file("layers/bazel", "library/BUILD.bazel"),
            file("layers/bazel", "app/BUILD.bazel"),
          ],
          notes: ["Two versions of one artifact need two <code>maven.install</code> repositories."],
        },
      },
    },
    {
      id: "an-application-with-its-own-runtime",
      title: "An application with its own runtime",
      lede: `<p>The application as a native launcher with a Java runtime of its own, so it runs where no JDK is
        installed. Because the module descriptors say exactly which modules the application reads, jlink can link
        a runtime of just those: here 62 MB, against 303 MB for the JDK it came from. With Jenesis this is one line
        in <code>packaging.properties</code>, and the build runs <code>jmod</code> and <code>jpackage</code>
        itself.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "One line. The runtime is linked from the module graph.",
          files: [
            file("app-image/jenesis", "build.jenesis/packaging.properties"),
            file("basic/jenesis", "sources/module-info.java", { note: "Section 1's descriptor, unchanged." }),
          ],
          commands: "java build/jenesis/Make.java stage",
          notes: [
            "jlink refuses automatic modules. For a dependency that is one - Avro, say - an empty <code>build.jenesis/modules.properties</code> has <code>jdeps</code> work out what each jar reads and gives it a module descriptor; the Avro image then links and parses schemas like any other.",
          ],
        },
        maven: {
          status: "plugin",
          badge: "Third-party plugin",
          verdict: "Apache has no jpackage plugin: a community one, with the dependencies copied first.",
          files: [file("app-image/maven", "pom.xml", { base: "basic/maven" })],
          commands: "mvn package",
          notes: [
            "<code>org.panteleyev:jpackage-maven-plugin</code> is a community plugin by Petr Panteleyev. Apache's maven-jlink-plugin links a runtime, but makes no native launcher and needs a module of its own.",
            "A second build needs <code>mvn clean</code>, because jpackage will not write into an existing image.",
            "With an automatic module, jlink refuses too; the ways out are an untrimmed 136 MB runtime or the third-party ModiTect plugin, which took 53 lines here.",
          ],
        },
        gradle: {
          status: "plugin",
          badge: "Third-party plugin",
          verdict: "No jlink or jpackage task: the Badass JLink plugin.",
          files: [file("app-image/gradle", "build.gradle.kts", { base: "basic/gradle" })],
          commands: "./gradlew jpackageImage",
          notes: [
            "<code>org.beryx.jlink</code> is maintained by Serban Iordache, whose README asks for co-maintainers. Without it, jpackage is a hand-written <code>Exec</code> task.",
            "The plugin merges automatic modules into one generated module, so an image still builds where plain jlink refuses.",
          ],
        },
        bazel: {
          status: "manual",
          verdict: "No rule or ruleset: a genrule calls jpackage, with every module jar listed by hand.",
          files: [file("app-image/bazel", "BUILD.bazel", { base: "basic/bazel" })],
          commands: "bazel build //:app_image",
          notes: [
            "A genrule cannot read transitive jars, so jackson-core and jackson-annotations are named by hand.",
            "A genrule cannot output a folder, so the image comes out as a tar.",
            "Bazel names a jar without a module name after its own copy, so the descriptor must <code>requires header.javax.inject</code> - which jlink then cannot find.",
          ],
        },
      },
    },
    {
      id: "a-container-image",
      title: "A container image",
      lede: `<p>The application as an image on <code>eclipse-temurin:25-jre</code>. With Jenesis one line in
        <code>packaging.properties</code> names the base image, and the build writes a complete build context - a
        Dockerfile, the jars and the launch arguments. Because the module descriptor names the main module, the
        image starts it on the module path. <code>docker build</code> or <code>podman build</code> makes the
        image.</p>`,
      tools: {
        jenesis: {
          status: "built",
          verdict: "One line; the build writes the Dockerfile and its context.",
          files: [file("docker/jenesis", "build.jenesis/packaging.properties"), file("docker/jenesis", "sources/module-info.java")],
          commands: "java build/jenesis/Make.java stage\ndocker build -t demo/app target/stage/docker/output/module-sources",
        },
        maven: {
          status: "plugin",
          badge: "Official plugin",
          verdict: "Google's Jib builds the image without a Docker daemon.",
          files: [file("docker/maven", "pom.xml")],
          commands: "mvn compile jib:dockerBuild",
          notes: ["Jib is not bound to the lifecycle, so it runs as a goal of its own."],
        },
        gradle: {
          status: "plugin",
          badge: "Official plugin",
          verdict: "Google's Jib builds the image without a Docker daemon.",
          files: [file("docker/gradle", "build.gradle.kts", { base: "basic/gradle" })],
          commands: "./gradlew jibDockerBuild",
          notes: [
            "Jib fails with Gradle's configuration cache and warns that it will break in Gradle 10.",
            "The image runs the application on the class path, whatever its <code>module-info.java</code> says.",
          ],
        },
        bazel: {
          status: "plugin",
          badge: "Community ruleset",
          verdict: "rules_oci and rules_pkg build the image without a Docker daemon.",
          files: [file("docker/bazel", "MODULE.bazel", { base: "basic/bazel" }), file("docker/bazel", "BUILD.bazel", { base: "basic/bazel" })],
          commands: "bazel run //:load",
          notes: ["rules_oci warns on a tag, so the base image is pulled by digest."],
        },
      },
    },
  ],
};
