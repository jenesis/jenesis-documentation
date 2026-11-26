# wicket: a resource served by a component is not authorized

- Project: https://github.com/apache/wicket (master, 11.0.0-SNAPSHOT)
- Fix: commit bc80f0b8d6bffc57f1ec5d098f15dd4956615bd4, 2026-09-10, "Ask IAuthorizationStrategy about a resource served
  by a component". Pre-state: its parent 0f93ccb46c0750d12c4d47cf5edd4768b31630bd. The commit names no pull request
  or issue; `issue.md` is written from the commit message. No pull request page was read.
- Why it qualifies: after 2026-07-01; a bug (a restricted resource is streamed), not a feature; the cause is in
  `wicket-core` (ResourceLink, LocalizedImageResource) and `wicket-extensions` (AjaxDownloadBehavior), the tests that
  show it are in `wicket-core-tests`, `wicket-extensions` and `wicket-auth-roles` (wicket-core has no tests of its
  own); the failing assertion (`expected: <403> but was: <200>`) names no cause.

## Does the fix change an interface the hidden tests compile against? No.

The fix touches `IAuthorizationStrategy`, `IResource` and `AuthorizeResource`, but in javadoc only: no signature is
added or changed ("needs no new API", says the commit). The hidden tests compile against the pre-state (proof 3,
"before", compiles and fails by assertion) and call only API that exists there. So the fallback fix ed359ab was not
needed. What the tests do pin down is behaviour, and `issue.md` states each as an expectation: the strategy is asked
once per served resource, with the instance the component holds and with empty, non-null `PageParameters`; a
refusal goes through the `IUnauthorizedResourceRequestListener` of the security settings (default: 403 and its
message "The request to resource '<r>' with parameters '' cannot be authorized."); a refused resource's `respond`
is not called and `ResourceLink#onClick()` does not run. An agent that asks the strategy with `null` parameters or
answers 403 by itself with another message fails two or three of the 25 hidden tests; the issue says so in words.

## The prepared project (both arms): task.env REMOVE and prepare.sh

- Modules dropped from the reactor, folders deleted: wicket-examples (war), archetypes/quickstart (maven-archetype),
  wicket-user-guide (asciidoctor), wicket-coverage (JaCoCo aggregate) - Jenesis builds nothing of them;
  testing/wicket-js-tests (frontend plugin, no Java tests); wicket-benchmarks (JMH annotation processor named in a
  compiler plugin block); wicket-velocity (Jenesis: `module not found: velocity.engine.core`);
  testing/wicket-common-tests (depends on wicket-velocity); wicket-migration (its OpenRewrite test looks for
  `rewrite-migrate-java*` jars by file name on the class path; fails under Jenesis). 21 jar modules remain.
  `testing/` also held wicket-arquillian and wicket-threadtest, which were never in the reactor.
- The `resources-optimizer-maven-plugin` block is removed from wicket-core/pom.xml and wicket-extensions/pom.xml
  (Jenesis does not minify; and with it a second `mvn test` without `clean` failed in wicket-extensions with
  JSC_NON_CONST_DEFINE on its own `*.min.js` - reproduced on the untouched project, raw-mvn-test2.log).
- Root pom properties `enforcer.skip`, `remoteresources.skip`, `japicmp.skip` = true (checks and generated
  LICENSE/NOTICE files Jenesis has no part in). KEPT for Maven although Jenesis does not do it: the
  maven-bundle-plugin `manifest` execution, because the jar plugin's `manifestFile` needs it and `mvn package` or
  `install` would break without it.
- Test files deleted because they pass only in the module's own folder (Jenesis runs tests in the project root and
  has no per-module working directory) or need the network: 5 x WellFormedXmlTest and 13 x ApacheLicenceHeaderTest
  (walk the working directory), FormTesterTest and MultiFileUploadFieldTest in wicket-core-tests (relative paths
  `src/test/...`, `target/test-classes/...`), wicket-util ConnectionsTest (fetches https://wicket.apache.org/...;
  it passes under Maven here only because the forked JVM inherits the proxy from JAVA_TOOL_OPTIONS).
- AGENTS.md and CLAUDE.md of the project are deleted. They tell an agent to build with Maven (`mvn clean verify`,
  `mvn install -DskipTests -Pfast` then `-pl wicket-core-tests -Dtest=...`, the `-am` plus
  `-Dsurefire.failIfNoSpecifiedTests=false` recipe) and describe the enforcer and wicket-migration, which the
  prepared project no longer has. MY DECISION, easily reverted by taking the two names out of REMOVE: with them the
  Maven arm gets the project's own loop advice and the Jenesis arm gets advice for a tool it does not have.

## overlay-jenesis

- `jenesis.properties`: `jenesis.test.exclude=.*(?<!Test)` (surefire `<include>**/*Test.java</include>`; without it
  Jenesis ran 2475 instead of 2452 tests in wicket-core-tests; a `jenesis.test.filter=.*Test` instead fails the
  test-less wicket-core with "No tests matched"), `jenesis.test.jars=false` (tests open resources as files:
  "URI is not hierarchical", FileSystemAlreadyExistsException otherwise; also needed by the Weld tests of
  wicket-cdi-tests).
- `build.jenesis/process-test.properties`: surefire's argLine (`--add-opens` x4, `--add-modules=ALL-SYSTEM`).

## Commands run and outcomes (JDK 25.0.5, Maven from /opt/maven, 4 cores shared with two other preparations;
## load average 4 to 11 throughout, so every duration is noisy)

Untouched pre-state:
- `mvn -B -ntp test` whole reactor (34 modules): BUILD SUCCESS, 6m50 (raw-mvn-test.log); again with `-o`, no clean:
  BUILD FAILURE in wicket-extensions, resources-optimizer (raw-mvn-test2.log).
- `java build/jenesis/Make.java`, no settings: EXIT 1 after 5m20; javac of wicket-velocity and tests of 16 modules
  fail (raw-jen1.txt) for the reasons listed above.

Prepared project (work/base/wicket of the harness, identical to mk.sh's tree):
- Proof 1, `mvn -o -B -ntp test` (plain, whole project): BUILD SUCCESS, cold 230 s (pmc-cold.log; an earlier run
  292 s), again with nothing changed and no clean 186 s (pmc-warm.log; earlier 239 s) - Maven runs every test again.
- Proof 2, `java build/jenesis/Make.java` (plain, overlay applied): EXIT 0, cold target 393 s (pjc-cold.log, 367 s
  inside the build; includes compiling the engine and starting the daemon), nothing changed 7.6 s (pjc-warm.log, one
  step executed). In the harness's own run, with an empty dependency cache: 257 s (work/cache/wicket/jenesis.log).
- Test counts, Maven = Jenesis in every module: wicket-util 218, wicket-request 134, wicket-core-tests 2436,
  wicket-extensions 109, wicket-devutils 8, wicket-ioc 13, wicket-cdi-tests 17, wicket-spring 53,
  wicket-auth-roles 50, wicket-guice 6, websocket-core 6, websocket-javax 4, websocket-tester 11,
  wicket-bean-validation 11, wicket-extensions-tester 4 (pm-plain1.log; pj-2.log run, counts read from each
  module's test/executed/supplement/output).
- Proof 3, the verifier `mvn -o -B -pl wicket-core-tests,wicket-extensions,wicket-auth-roles -am test
  -Dtest=<the four> -Dsurefire.failIfNoSpecifiedTests=false` with hidden/ laid over: BUILD FAILURE, 28 s
  (pm-before.log; stops at wicket-core-tests, 8 of 14 fail). With `-fae` (pm-before-fae.log): 8/14, 1/2, 1/5 and 2/4
  fail, 12 of 25. With reference.patch: BUILD SUCCESS, 47 s, 14 + 7 + 4 = 25 pass (pm-after.log).
- Proof 4, `java '-Djenesis.test.filter=.*(ComponentResourceAuthorizationTest|AjaxDownloadResourceAuthorizationTest|ExportToolbarResourceAuthorizationTest|AnnotationsRoleResourceTest)'
  build/jenesis/Make.java +wicket-core-tests +wicket-extensions +wicket-auth-roles`: before EXIT 1, 29 s, 8/14,
  2/7, 2/4 fail (pj-before.log); with reference.patch EXIT 0, 37 s, 14 + 7 + 4 pass (pj-after.log).

The loop, reference fix applied, hidden tests laid over, after adding an empty private method to
`wicket-core/.../ResourceLink.java` each time (warm, three runs each, alternating; load 4 to 7 from the other
preparations):
- Maven, the verifier command above: 38.7 s, 42.4 s, 38.4 s (pm-loop1..3.log).
- Jenesis, the proof-4 command above: 23.6 s, 26.0 s, 20.2 s (pj-loop1..3.log; the same command with nothing
  changed: 9.1 s).
Not measured: a Maven loop over `-pl wicket-core,<the three>` without `-am`, which needs wicket-util, wicket-request
and wicket-tester installed first.

Harness: `WORK=... JENESIS_SOURCES=/home/user/jenesis-pomgaps MAVEN_MIRROR=... ./prepare.sh wicket` ended with
`Prepared wicket` after 672 s (harness2.log): maven.log BUILD SUCCESS 4m30, before.log BUILD FAILURE 49 s, after.log
BUILD SUCCESS 62 s, jenesis.log COMPLETED 257 s. A first attempt (harness1-oom.log) died because the kernel killed
the Jenesis build daemon for lack of memory while two other preparations ran; nothing in the task was changed
between the two.

## What the harness author must know

- The harness warms Maven with `-pl $MODULES -am test` only (98 MB of ~/.m2). With that cache a plain
  `mvn -o test` over the whole prepared project FAILS in the Maven arm (pmh.log: maven-jar-plugin 3.5.1 "has not been
  downloaded", at module `wicket`; the dependencies of the Spring, CDI, Guice and websocket modules are missing as
  well), and so would `mvn -o package` or `install`. The plain whole-project command works offline only from a
  cache warmed by a whole-project run (proof 1 used such a cache). The Jenesis arm is warmed by a whole-project
  build. The task was not changed to hide this; the harness's Maven warm-up needs a whole-project `mvn test`
  (and `install -DskipTests` if agents are to be allowed it).
- Jenesis' daemon and warm test JVMs stay alive after a build; with three preparations on 16 GB one was killed.
- Not verified: flakiness over many runs (each proof ran once or twice); the hidden tests against any fix other
  than the reference one; anything on a JDK other than 25.
