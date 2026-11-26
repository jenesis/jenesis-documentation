# guava: filtered NavigableMap views return the backing map's live entries

- Fix: https://github.com/google/guava/commit/a279b884fe9890a3869142919352156f2a67a705
  "Make filtered `NavigableMap` views return snapshot entries from `pollFirstEntry()`, etc. (and similarly for
  `ForwardingNavigableMap.standard*Entry`)", committed 2026-09-26, "Fixes https://github.com/google/guava/pull/8692".
  Pre-state is its parent 4d41665af1b05bad09039b82cb2a1a474a7bceaf (2026-09-24). The pull request page was not
  read; issue.md is written from the commit message.
- Main change, module `guava` (the cause): `Maps.java` (+68), `Sets.java`, `Iterables.java`,
  `AbstractNavigableMap.java`, `ForwardingNavigableMap.java` - reference.patch, 275 lines.
- Contract change, module `guava-testlib`, MAIN sources: `NavigableMapNavigationTester` now requires the entries
  of the navigation methods to refuse `setValue`. It is in `hidden/` although it is a main-source file, as the
  second-round rules allow for a test-support module; no file of `guava` is in `hidden/`.
- Tests, module `guava-tests`: `MapsTest` (5 new tests), `ForwardingNavigableMapTest` (2 new, 1 extended);
  `MapsCollectionTest` is unchanged by the fix but is where the tightened tester meets the filtered maps, so it is
  in `TESTS` and not in `hidden/`.

## Why it qualifies

After 2026-07-01; main and test change; no network; deterministic. Cause and symptom are in different modules
(cause `guava`, contract `guava-testlib`, failures `guava-tests`). The wrong entry of `pollFirstEntry()` comes
from `TreeMap` reusing the node object of a removed entry with two children, which the failing assertion
(`expected 2=two but was 3=three`) does not say; the snapshot requirement touches five files, a `final` that has
to go from `AbstractNavigableMap`, and must keep `entrySet()` live. 1029 of 268415 tests fail before the fix.

## What both arms get: REMOVE and prepare.sh

REMOVE deletes `android` (the second reactor, which holds a copy of every changed file), `guava-gwt`, `guava-bom`,
`guava-tests/benchmark`, `mvnw`, `mvnw.cmd`, `.mvn` (the wrapper would download a Maven of its own) and two test
classes that fail in this sandbox with both tools: `MoreFilesTest` (`testCreateParentDirectories_noPermission`
expects an IOException the root user does not get) and `InetAddressesTest` (`testIPv6AddressWithScopeId` needs a
named IPv6 interface). Seen in the first plain `mvn test`: `Tests run: 865599, Failures: 2`.

prepare.sh edits the four poms, each edit checked by its match count and by a grep afterwards:

- root: `<module>guava-bom</module>` and `<module>guava-gwt</module>` out; the `<resources>` block with
  `<directory>..</directory>` (LICENSE into META-INF) out; Error Prone out (`-Xplugin:ErrorProne`,
  `-XDcompilePolicy=simple`, `--should-stop`, the `-J--add-exports/--add-opens` arguments,
  `<annotationProcessorPaths>`, `<fork>true</fork>`); surefire's `<jdkToolchain>` out;
  `<animal.sniffer.skip>true</animal.sniffer.skip>` in; three surefire excludes in (below).
- guava, guava-testlib, guava-tests: the `toolchains-maven-plugin` and `maven-toolchains-plugin` references out
  (no JDK 26 download, the JDK on the PATH compiles and tests); guava also loses its `..` resources block
  (LICENSE, proguard/*); guava and guava-testlib lose `-XDcompilePolicy=simple` of the java9 execution;
  guava-tests loses the build-helper execution adding `benchmark` as a test source root.

Why each: Jenesis reads no plugin block, so it runs no Error Prone, no Animal Sniffer, no toolchain and does not
see the `benchmark` root; it refuses a resource directory that contains the build's own folders (`..`); it does
not build `guava-gwt` (the scout's finding, not re-run by me). `guava-bom` was removed on instruction, I did not
try it with Jenesis.

Test selection made equal. The root pom's surefire includes EVERY class (`%regex[.*.class]`, nested ones too) and
excludes `.*PackageSanityTest`, `.*Tester`, `.*$\d+`. Jenesis takes the default naming (Test*, *Test, *Tests,
*TestCase, never a nested class). Comparing the class lists of both tools on the prepared project left
- three classes only Maven ran: `TableCollectionTestSuite` (5918 tests), `ContiguousSetTest$BuiltTests` (915) and
  `AbstractPackageSanityTestsTest$ConcretePackageSanityTests` (3, guava-testlib). prepare.sh adds them to
  surefire's excludes, as `jenesis.test.filter` cannot add to the default naming without dropping its JUnit 4
  check. Maven therefore runs 6836 tests fewer than upstream would.
- the `PackageSanityTest` classes only Jenesis ran: the overlay excludes them, as the pom does.

Left unequal, on purpose: Maven compiles with `-source 1.8 -target 1.8` plus a second `release 9` execution for
`module-info.java` and writes the OSGi manifest (maven-bundle-plugin); Jenesis compiles everything for release 25
([RELEASE] lines in its log) and needs the `--add-exports` below for it. Maven runs the tests in the module's
folder, Jenesis in the project root; no test noticed.

## overlay-jenesis

- `jenesis.properties`: `jenesis.test.exclude=.*PackageSanityTest` (surefire's exclude).
- `build.jenesis/process-test.properties`: surefire's argLine, `-Xmx1536M -Duser.language=hi -Duser.country=IN`
  and the three `--add-opens` of `test.add.opens`, for every module.
- `guava-tests/build.jenesis/process-javac.properties`: `--add-exports=java.base/sun.security.jca=ALL-UNNAMED`,
  which Maven does not need under `-source 8` and javac needs for release 25.

## What was run (JDK 25.0.5, Maven at /opt/maven, 4 cores shared with two other preparations)

Logs: `prep/guava/logs/`, the harness's under `prep/guava/work/cache/guava/`.

Test counts, prepared project, both tools equal:

| module | Maven | Jenesis |
|---|---|---|
| guava-testlib | 860807 | 860807 |
| guava-tests | 857570 (519 skipped) | 857570 |
| the three verifier classes | 268415 | 268415 |

**Both plain whole-project commands take 12 to 16 minutes - well over ten.** About 1.7 million generated
collection tests run in two forked JVMs; compiling is under a minute of it.

| command | first run | nothing changed |
|---|---|---|
| `mvn -o -B -ntp test` (fresh tree, warm repository) | 763.6 s, exit 0 | 699.9 s, exit 0 (runs every test again) |
| `java build/jenesis/Make.java` (fresh tree, warm cache) | 807.0 s, exit 0 (tests 187 s + 706 s, in parallel) | 3.2 s, exit 0 |
| harness, with downloads: `mvn -B -pl guava-tests -am test` | 16:17 min, then 12:59 min on a quieter machine | |
| harness, with downloads: `java build/jenesis/Make.java` | 881.8 s, then 616.1 s on a quieter machine | |

1. Maven at the pre-state: above, BUILD SUCCESS on JDK 25 with no toolchain (`~/.m2/jdks`, `toolchains.xml`
   absent) and offline after one warm run.
2. Jenesis at the pre-state: above, COMPLETED, same counts.
3. Hidden tests with Maven (harness, the verifier
   `mvn -o -B -pl guava-tests -am test -Dtest=MapsTest,ForwardingNavigableMapTest,MapsCollectionTest -Dsurefire.failIfNoSpecifiedTests=false`):
   before the fix `Tests run: 268415, Failures: 1029`, BUILD FAILURE, 1:45 min; with reference.patch
   `Tests run: 268415, Failures: 0`, BUILD SUCCESS, 1:41 min.
4. Hidden tests with Jenesis
   (`java -Djenesis.test.filter='.*[.](MapsTest|ForwardingNavigableMapTest|MapsCollectionTest)' build/jenesis/Make.java +guava-tests`):
   before `Tests run: 268415, Failures: 1029`, exit 1, 53 s; with reference.patch `OK (268415 tests)`, exit 0, 63 s.

Harness: `./prepare.sh guava` ended with `Prepared guava` twice: in 37.5 min on the task as it was before the
third surefire exclude, and in 29.3 min on the final folder (`prep/guava/logs/harness-2.log`; before.log 1029
failures of 268415, after.log 0, maven.log 860807 + 857570 tests, jenesis.log COMPLETED). A run between the two
died in `git clone` with "No space left on device": the scratch disk had 1.4 GB free.

## The loop, measured

Prepared project, hidden tests laid over it, pre-fix (so the run fails, 1029 failures), one private method added
to `guava/src/com/google/common/collect/Maps.java` before each run, reverted after; one warm-up run before the
three. Sequential, but two other preparations used the machine (load 2 to 3).

| tool | command | run 1 | run 2 | run 3 |
|---|---|---|---|---|
| Maven | the verifier command above (`-pl guava-tests -am`) | 65.7 s | 69.2 s | 67.3 s |
| Jenesis | the filter command of step 4 with `+guava-tests` | 46.0 s | 45.0 s | 41.9 s |

Maven: recompiles guava (610 files, 12 s), guava-testlib (5 s), all 605 test files of guava-tests, tests about
35 s. Jenesis: javac guava 4 s, guava-testlib 1.5 s, guava-tests tests 10 s, test JVM about 25 s. Most of either
loop is `MapsCollectionTest` (some 265000 generated tests); a loop over `MapsTest` alone would be far shorter with
both tools, and an agent is free to choose it.

## Not verified, and what the harness author should know

- `guava-gwt` and `guava-bom` under Jenesis: not tried by me.
- The plain and loop timings in the tables were made on a base without the third exclude (3 tests of 860810);
  the final harness run has it.
- The scratch disk is nearly full (about 2 GB free at the end); each run copies the project and a home.
- The agent's own `mvn test` or plain `java build/jenesis/Make.java` costs 12 to 16 minutes each time (Jenesis
  only when something changed); with TIMEOUT=2700 two or three such runs end the attempt.
- The hidden tester is stricter for EVERY navigable map the test suites build; the verifier runs three classes
  only. The reference fix was not run against the whole suite with the hidden tester in place.
- The two removed test classes fail for the sandbox's sake (root user, no named IPv6 interface); on another
  machine they could stay.
