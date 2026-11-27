# blackbird: Blackbird setter-failure messages after a databind change

- Project: https://github.com/FasterXML/jackson-modules-base (branch 3.x)
- Fix: `7638c9d` "Fix Blackbird setter-failure messages after databind#6303 (#382)", Tatu Saloranta, 2026-11-12,
  directly on the branch. Pre-state: its parent `c056b52` ("Create 3.4 branch; 3.x -> 3.4.0-SNAPSHOT"), verified.
- Main change: `blackbird/src/main/java/tools/jackson/module/blackbird/internal/ReaderSupport.java` (one method,
  `storeException`, 3 lines + javadoc). Test change: `blackbird-tests/.../diff/ReaderErrorsDiffTest.java` (one
  assertion's expected message).

## Why it qualifies

Blackbird generates bean deserializers and, when a setter throws, builds the exception by calling stock databind's
`SettableBeanProperty._throwAsJacksonE(p, t, value)` through a probe, handing it a *stand-in* for the value it no
longer has (the wrapper `Class` object for a primitive, `String.class` for a String). The jackson-databind
3.4.0-SNAPSHOT the pre-state builds against (databind#6303) now routes that call through
`SettableBeanProperty._wrapSetterProblem`, which checks whether the value is an instance of the property type and,
if not, reports "Problem setting property 'x' (expected type: ...; actual type: ...)". A `Class` object is never an
instance of `int`/`Integer`/`String`, so Blackbird's messages claim a type mismatch; stock passes the real value
and reports "Problem setting property 'x': <setter message>" for an `IllegalArgumentException`, or the setter's
exception unwrapped otherwise. The fix passes a value of the property type (`ClassUtil.defaultValue(raw)`, `""`).

The rule exists only in databind: nothing in the project's own sources says what the probe's `value` argument is
used for. The cause is in `blackbird`, the symptom also in `blackbird-tests` (differential tests against stock).
Seven of Blackbird's own tests and three of `blackbird-tests` fail at the pre-state, all from this one cause.

## What an engineer looks at outside the project (for reading the session logs)

`tools.jackson.databind.deser.SettableBeanProperty` - `_throwAsJacksonE(JsonParser, Throwable, Object)`,
`_wrapSetterProblem(...)`, `_isValueTypeMismatch(Object, JavaType)` - in jackson-databind 3.4.0-SNAPSHOT,
timestamped build `3.4.0-20261126.044118-39`, jar SHA-256
`8688cbfd8bc7be1f0b5f18d7328cd67f8e9d6bcf93b1e441233ce5a3dc26d374`. Where it is after `prepare.sh` of the harness
(`$HOME` being the run's home):

- both arms: `$HOME/.m2/repository/tools/jackson/core/jackson-databind/3.4.0-SNAPSHOT/jackson-databind-3.4.0-SNAPSHOT.jar`
  (and the same bytes as `jackson-databind-3.4.0-20261126.044118-39.jar` beside it). `javap -p -c -cp <jar>
  tools.jackson.databind.deser.SettableBeanProperty` shows the three methods.
- Jenesis arm, after a build: a copy per module under
  `target/build/maven/compose/module/build-module-blackbird/dependencies/artifacts/resolve/output/resolved/tools.jackson.databind-3.4.0-SNAPSHOT.jar`
  (same SHA-256), read from the warm `~/.m2` above (Jenesis reads a `-SNAPSHOT` from the local Maven repository
  when it holds one, and asks no remote).
- Maven arm: `blackbird/target/classes/.../internal/ReaderSupport.class` and `PropertyProbe.class` for the probe.
- Sources jar: published (`jackson-databind-3.4.0-20261126.044118-39-sources.jar`, 1.45 MB) and fetched by
  `mvn dependency:sources` into `~/.m2/.../jackson-databind-3.4.0-SNAPSHOT-sources.jar`; the javadoc of
  `_wrapSetterProblem` there names the rule. **The harness's warm-up does not fetch it** (see Harness), so after
  preparation neither arm has it on disk; Jenesis has no command that fetches dependency sources (none found in
  `help`/sources; its IDE support adds project folders only). The offline Maven arm also lacks
  `maven-dependency-plugin`, so `mvn -o dependency:tree` / `dependency:sources` fail offline.

## Dependency pinning (the moving SNAPSHOT)

The pre-state depends on 3.4.0-SNAPSHOTs from `https://central.sonatype.com/repository/maven-snapshots`
(`tools.jackson:jackson-base`/`jackson-bom`, `tools.jackson.core:jackson-core`/`jackson-databind`,
`com.fasterxml.jackson.core:jackson-annotations:2.24-SNAPSHOT`, `com.fasterxml.jackson:jackson-parent:2.24-SNAPSHOT`).
No released databind carries #6303 (3.3.0 does not; checked its sources jar), so the snapshot is needed.

- Timestamped versions in the poms are NOT an option: Jenesis fetches `<version>/<artifactId>-<version>.jar`, so
  `3.4.0-20261126.044118-39` would be looked up in a folder of that name (read in
  `maven/MavenDefaultRepository.fetch`); only `-SNAPSHOT` is mapped to a timestamp, via remote metadata.
- What the task does instead: the warm cache is the anchor. `prepare.sh` sets `<updatePolicy>never</updatePolicy>`
  on the pom's `central-snapshots` repository, so Maven, online or offline, never replaces a snapshot it has
  (only `-U` would). Jenesis prefers the `-SNAPSHOT` file in `~/.m2/repository` when it exists, and the harness
  builds the Maven arm first, so both arms use the same files.
- Proven: after preparation, with the proxy port broken (no network at all), a plain online `mvn test` and a plain
  `java build/jenesis/Make.java` both built and ran the same tests with the same results; both used databind
  `8688cbfd…` and jackson-core `4ac745db…` (core `3.4.0-20261126.230609-15`); runs added nothing to `~/.m2`.
- What is NOT pinned: what the warm-up fetches. Preparing again later takes whatever snapshot is then newest
  (and the snapshot repository deletes old builds after a while). The harness's before/after check catches a
  snapshot that no longer shows the bug or no longer builds; if that happens the task needs a re-check, not a fix.
- Jenesis reaches the snapshot repository only through `overlay-jenesis/jenesis.properties`
  (`jenesis.maven.uri=https://central.sonatype.com/repository/maven-snapshots/|tools.jackson|com.fasterxml.jackson,@`;
  `@` splices `MAVEN_REPOSITORY_URI`, i.e. the harness's mirror and repo1). The snapshot repository comes first,
  limited to the Jackson groups: with it after `@`, a cold Jenesis build failed on repo1's 429 for
  `jackson-base/3.4.0-SNAPSHOT/maven-metadata.xml` instead of moving on. A cold Jenesis build with an empty home
  and only this overlay resolved the same databind `-39`.

## Simplifications (prepare.sh, both arms)

1. Reactor: parent + `blackbird`, `blackbird-tests`, `blackbird-jpms-tests`; they were in a `<jdk>[25,)` profile,
   now in `<modules>`; the other ten modules and `blackbird/benchmarks` (a separate project) are in `REMOVE`, with
   `mvnw*`, `.mvn`, `CLAUDE.md`.
2. Release 25 everywhere (root `maven.compiler.release`, `javac.src/target.version` 17 -> 25); the two
   `src/main/java25` generators move into `src/main/java`; the second compiler execution, the build-helper source,
   the class copy, the jar excludes, Blackbird's bundle settings, javadoc release, cyclonedx and gradle-module-metadata
   plugins go. The parent's bnd `bundle:manifest` still runs (the parent's jar plugin reads its MANIFEST.MF;
   disabling it broke `mvn install`) - Maven work Jenesis does not do, small.
3. `PackageVersion.java` written from its template; replacer plugin removed (root pluginManagement and blackbird).
4. Blackbird's test `module-info.java` (names the main module; surefire patched tests into it) removed, and its
   `--patch-module` argLine replaced by `<useModulePath>false</useModulePath>`: Jenesis does not support the
   patch-module idiom (javac fails on every main class). On the class path, all 549 Blackbird tests behave as on the
   module path in Maven except none (the 7 bug failures are the same; without `useModulePath=false` Maven patched
   tests into the module and 23 module-dependent tests failed once the descriptor was gone).
5. Tests about packaging: `JdkCompatibilityTest` (whole class; runs the packaged multi-release jar on older JDKs,
   none configured; Maven's test phase skipped all 8, Jenesis ran 6 against its jar) and
   `PackagingTest.bundleExportsOnlyTheModulePackage` removed; `PackagingTest.releaseProfileRequiresJdk25` removed
   (reads the root pom from the test's working directory: Maven's is the module, Jenesis's the root, so it aborted).
6. `jacoco.skip=true` (the parent attaches JaCoCo to every test JVM).
7. `updatePolicy never` on the snapshot repository (above).

`overlay-jenesis/`: `jenesis.properties` (the repository chain above) and `process-test.properties` in each module
with the surefire `systemPropertyVariables` (`tools.jackson.module.blackbird.failOnCodegenError=true` in all three,
`blackbird.debug.codegen=true` in jpms-tests, `blackbird.test.oldJdks=` in blackbird-tests).

## Hidden tests

`TESTS="ReaderErrorsDiffTest,BBCodecStockChecksTest,TestBuilders,TestSetterFailures"`, `MODULES=blackbird-tests`
(`-am` adds blackbird). `hidden/` holds the fix's `ReaderErrorsDiffTest` and, unchanged (identical at both commits),
Blackbird's three tests that fail before the fix for the same cause - so an agent cannot pass by editing them.

## Runs (JDK 25.0.5, Maven /opt/maven, Jenesis /home/user/jenesis-agentout, JAVA_TOOL_OPTIONS set as the harness
sets it; the machine was shared, load average 10-24, so times are noisy)

| what | Maven | Jenesis |
|---|---|---|
| pre-state, plain full build | exit 1: blackbird 549 run, 7 failed (BBCodecStockChecksTest 4, TestBuilders 2, TestSetterFailures 1); reactor stops | exit 1: blackbird 549/7 failed (same 7), blackbird-tests 63/3 failed (ReaderErrorsDiffTest), jpms 2/0 |
| with fix + hidden, plain full build | exit 0: 549 / 63 / 2, 0 skipped | exit 0: 549 / 63 / 2, 0 aborted |
| verifier before fix (hidden laid over) | fails: blackbird 43 run, 7 failed; reactor stops | filter on the four classes: blackbird 43/7 failed, blackbird-tests 8/3 failed |
| verifier after fix | passes: 43 + 8 | 43/0 and 8/0 failed |
| ReaderErrorsDiffTest alone, hidden version, before fix | 8 run, 3 failed | (in the row above) |
| full, cold `target/` (pre-state, warm repo) | 28.7 s (stops at blackbird) | 38.2 s |
| full after one edit (the fix) | 18.6 s | 12.4 s |
| full, nothing changed | 12.1 s | 1.8 s |
| harness warm-up `mvn -B test` (online) | 50 s | - |

Loop after adding a private method to `ReaderSupport.java`, hidden tests laid over the fixed tree, three runs each:

- Maven `mvn -o -q -B -pl blackbird-tests -am test -Dtest=ReaderErrorsDiffTest -Dsurefire.failIfNoSpecifiedTests=false`:
  16.7 s, 17.8 s, 16.0 s
- Jenesis `java -Djenesis.print.progress=false -Djenesis.test.summary -Djenesis.test.filter='.*ReaderErrorsDiffTest' build/jenesis/Make.java +blackbird-tests`:
  6.7 s, 6.3 s, 5.6 s

Harness: copied to `prep3/blackbird/harness`, `WORK=prep3/blackbird/work JENESIS_SOURCES=/home/user/jenesis-agentout
MAVEN_MIRROR=… ./prepare.sh blackbird` ended with `Prepared blackbird` in 165 s; before.log fails (7), after.log
passes (43 + 8), maven-install.log BUILD SUCCESS, jenesis.log the pre-state result above.

## Harness notes

- Jenesis with `-Djenesis.test.filter` over the whole project fails a module where the filter matches no class
  ("No tests matched the requested selection" in blackbird-jpms-tests); with `+blackbird +blackbird-tests` it does
  not. Maven's verifier has `-Dsurefire.failIfNoSpecifiedTests=false` for the same reason.

- The warm-up `mvn -B test` exits 1 at the pre-state (the bug's own tests) and stops the reactor after blackbird;
  the harness ignores the code, and `install -DskipTests` then resolves everything blackbird-tests needs - the
  offline verifier and full offline builds of all three modules worked from the cache.
- For the intended tool use, the warm-up would need `mvn -B dependency:sources` (or
  `dependency:resolve -Dclassifier=sources`) after the install, which puts the databind sources jar into the shared
  `~/.m2` for both arms and `maven-dependency-plugin` into the Maven arm's offline repository. Not added to the
  harness; without it an agent has the binary jar (javap) in both arms and the sources only online.

## Could not verify

- That the snapshot repository keeps `-39`; nothing here depends on it once the cache is warm.
- Jenesis's daemon mode was in use for all Jenesis timings (the default); no other mode measured.
