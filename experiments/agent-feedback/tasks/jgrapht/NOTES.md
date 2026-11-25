# jgrapht: HowardMinimumMeanCycle.getCycle() loops forever

- Pull request: https://github.com/jgrapht/jgrapht/pull/1397
  "Fix HowardMinimumMeanCycle looping forever while rebuilding the cycle", no linked issue.
- Merged 2026-10-28 as the squash commit ee9e7949d9f63d1b8949889afbed7ac53dbeac72;
  pre-state is its parent e35872f77d6372356ffcf59430e1a36c3a8e7466.
- Changes one main file (`jgrapht-core/.../alg/cycle/HowardMinimumMeanCycle.java`, +13 -10) and one test file
  (`HowardMinimumMeanCycleTest`, two new tests `testGraph8`, `testGraph9`, each under a 10 s `@Timeout`).

## Why it qualifies, and where it is weak

- After 2026-07-01, main and test change, no network, deterministic.
- The symptom is a hang / OutOfMemoryError, so the failing "assertion" is a timeout that says nothing about the
  cause. The cause is in the interplay of three methods: the cycle is rebuilt from the policy graph after the last
  `computeVertexDistance()` has already changed that graph (a sub-tolerance switch between two cycles of equal
  mean in graph 8, an iteration limit cutting in after a real improvement in graph 9).
- Weak points: one module only (`jgrapht-core`), one main file, about 20 changed lines. Every fix after 2026-07-01
  in this repository is confined to `jgrapht-core` and to one main file, except #1404 (two files, trivial). This
  one needs the most reasoning of them; #1391 (Steiner tree edges) and #1414 (delta stepping) were the runners-up.
- The hidden test compares the returned `GraphPath` with `equals`, so start vertex and edge order count. issue.md
  therefore states the expected cycles with their start vertex. A fix that returns the right cycle rotated fails.
- `testGraph9` also asserts the result under `maximumIterations = 1` (cycle 0->1->2->0, mean 11/3); issue.md says so.

## Module subset (both arms)

`jgrapht-io` generates its parsers with antlr4-maven-plugin; Jenesis reads no plugin block, so its javac fails
there (125 errors, `DOTEventDrivenImporter` ... "method does not override", command
`java -Djenesis.test.skip=true build/jenesis/Make.java` on the untouched tree). `jgrapht-osm`, `jgrapht-demo` and
`jgrapht-dist` depend on it. The bug needs none of them.

A module folder cannot be deleted, as the root pom lists it and Maven refuses a missing child. So
`REMOVE="jgrapht-io/src jgrapht-osm/src jgrapht-demo/src jgrapht-dist/src"` deletes their sources and leaves the
poms: Maven builds them as empty modules (ran: whole reactor `mvn test -Dtest=HowardMinimumMeanCycleTest
-Dsurefire.failIfNoSpecifiedTests=false`, BUILD SUCCESS, 31 s), Jenesis no longer sees them as modules (ran:
whole project with `-Djenesis.test.skip=true`, COMPLETED). What remains in both arms: core, opt, ext, guava,
unimi-dsi.

## overlay-jenesis/jenesis.properties (needed)

    jenesis.test.tag=-slow+-optional
    jenesis.test.exclude=org[.]jgrapht[.]perf[.].*
    jenesis.test.jars=false

- The poms set surefire `excludedGroups` slow,optional, exclude `**/perf/**` and include only `FastTestSuite`.
  Jenesis reads none of that. Without the first two lines a plain build of `jgrapht-core` runs the slow tests: it
  sat for over 21 minutes at 100 % of one core in `BrownBacktrackColoringTest.insertions2_3Test` before I killed it.
- Without the third, `GonAlgorithmTest.testKroA200FiveCenters` fails (`FileNotFoundException: file:/.../jar/...`,
  a test resource opened as a `java.io.File`), since Jenesis tests against the module's jar.
- Not configured, only reported by Jenesis: it compiles for release 25 because the poms set the release in the
  compiler plugin's block (`<release>${java.version}</release>`), not as `maven.compiler.release`. Harmless here.
- Jenesis runs the tests sequentially; the poms' `junit.jupiter.execution.parallel.enabled=true` is not read.

## What I ran (JDK 25.0.5, Maven 3.9.11, 4 cores shared with two other preparations)

Maven used `-s settings.xml` with a mirror of central on the Google bucket in every run. A `-o` run WITHOUT that
settings file fails ("Cannot access central ... in offline mode and the artifact
org.apache.maven.plugins:maven-javadoc-plugin:jar:3.12.0 has not been downloaded from it before"): Maven 3.9 keys
the local repository on the repository id, so the warm run and the verifier need the same settings.

1. Maven, pre-state
   - `mvn -B -s .. -pl jgrapht-core -am test -Dtest=HowardMinimumMeanCycleTest -Dsurefire.failIfNoSpecifiedTests=false`
     first run, online: SUCCESS, 7 tests, 45.7 s (41 s of it compiling core).
   - `mvn -o -B -s .. -pl jgrapht-core -am test`: SUCCESS, 4 min 49 s, Tests run: 7008, Skipped: 15.
   - the verifier with nothing changed, warm: 4.9 s.
2. Jenesis, pre-state, copied `build/jenesis`, REMOVE applied, overlay in place
   - `java -Djenesis.test.filter='.*HowardMinimumMeanCycleTest' -Djenesis.test.force=true -Djenesis.print.tests=true
     build/jenesis/Make.java +jgrapht-core`, cold (before the overlay existed): COMPLETED, 7 tests, 33 s wall
     (29.9 s build). Warm, nothing changed: 4.0 s.
   - `java -Djenesis.make.mode=compiled -Djenesis.print.tests=true build/jenesis/Make.java +jgrapht-core`:
     COMPLETED, 3 min 43 s, 7008 tests found, 6993 successful, 15 aborted (assumptions), 0 failed.
   - Count: Maven 7008 run / 15 skipped, Jenesis 7008 found / 15 aborted. Equal.
3. Hidden tests with Maven (tree at pre-state with REMOVE applied)
   - hidden test copied: verifier exit 1, BUILD FAILURE, Tests run: 9, Errors: 2
     (`testGraph8`, `testGraph9` "timed out after 10 seconds"), 32 s (38.6 s in a second tree).
   - plus `git apply reference.patch`: exit 0, BUILD SUCCESS, Tests run: 9, 15.8 s (28.7 s in the second tree).
4. Hidden tests with Jenesis (the filter command of step 2)
   - hidden test copied: exit 1, 9 found, 7 successful, 2 failed (the same two, same timeout), 35.7 s
     (53 s in the earlier daemon-mode run).
   - plus the patch: exit 0, 9 successful, 13.4 s (22.7 s in daemon mode). A following full
     `+jgrapht-core` run with the fix: COMPLETED in 3 min 17 s.

## Obstacles

- The Jenesis build daemon died in the middle of my first full test run ("The build daemon died while the build
  was running", after 7 minutes). `~/.jenesis/daemons` is shared by every build on the machine and
  `jenesis.daemon.limit` is 3: a build that starts a fourth daemon stops the least recently used one, and the other
  preparations were starting daemons at that time. I read that in `DaemonClient.start`; I did not prove it was the
  cause. Every long Jenesis run after that used `-Djenesis.make.mode=compiled`, which ran through. Experiments that
  run several Jenesis builds of different projects at once on one machine should raise `jenesis.daemon.limit` or
  set `jenesis.make.mode=compiled`; I left JENESIS_ARGS_EXTRA empty because that is the harness's decision.
- A filter run and a full run are different selections, so after a source change the full run executes all 7008
  tests again (about 3.5 minutes sequentially, against Maven's 4 min 49 s in parallel under the same load).

## Not verified

- The tests of opt, ext, guava and unimi-dsi under Jenesis (compiled only), and under Maven on the REMOVEd tree
  beyond compiling.
- A complete full-test run in Jenesis daemon mode.
- The pull request text: read through a summarising fetch, not verbatim; issue.md is written from the commit
  message and the test data.
