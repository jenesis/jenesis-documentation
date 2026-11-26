# struts: HTTP method annotations not enforced across action hierarchies and plugin stacks

- Fix: apache/struts PR #2120 "WW-5844 fix(core)!: enforce HTTP method annotations across action hierarchies and
  plugin stacks" (https://github.com/apache/struts/pull/2120), commit 38e3640220f5e194908c4dc168cb24101f989618,
  merged 2026-11-08 (one squashed commit).
- Issue: https://issues.apache.org/jira/browse/WW-5844 "HttpMethodInterceptor fails open for the implicit execute()
  method, ..." (reported 2026-11-07, fixed in 7.5.0). `issue.md` is written from the issue, the PR description and
  the review commit's message (both read through WebFetch summaries and from `git show`).
- Pre-state: 707457f584072113d5c03d5e32d0c481cb20f6a5 (parent of the fix), version 7.5.0-SNAPSHOT.

## Why it qualifies

- Merged after 2026-07-01. Main changes in three modules: `core`
  (`HttpMethodInterceptor.java`, +93/-6), `plugins/rest` and `plugins/bean-validation` (one `<interceptor-ref>`
  line each in `src/main/resources/struts-plugin.xml`; `RestActionMapper.java` gets Javadoc only).
- Tests in the same three modules: `HttpMethodInterceptorTest` (changed, 12 new methods),
  `HttpMethodHierarchyTest`, `HttpMethodDefaultStacksTest` (core), `RestStackHttpMethodEnforcementTest` (rest),
  `BeanValidationStackHttpMethodEnforcementTest` (bean-validation). With the hidden tests over the pre-state
  6 of 50 fail in core, 1 of 3 in bean-validation, 9 of 11 in rest; with `reference.patch` all 64 pass.
- Several independent causes (implicit `execute()`, superclass, overridden method, interface through a superclass,
  super-interface, two plugin stacks) and review-driven edge rules (private/static/package-private namesakes do not
  restrict, a missing implicit `execute()` must not throw, a missing explicit method still throws). A fix of core
  alone leaves the rest and bean-validation tests failing; a fix of the stacks alone leaves core failing. Checking a
  candidate needs core rebuilt and tests of three modules run.
- No network, no service; deterministic (in-process mocks).
- Weakness: the plugin half of the fix is two XML lines, and `issue.md` has to spell out the edge rules of the
  review for the hidden `HttpMethodInterceptorTest` to be passable, so it is longer than a user's report.

## What both arms get (task.env REMOVE and prepare.sh)

The whole reactor (31 Maven modules) builds with neither tool as it stands here; the prepared project keeps
18 (root, bom, parent, core, plugins and its 12 plugins async, bean-validation, convention, jasperreports,
javatemplates, jfreechart, json, junit, rest, spring, testng, xslt, and boot).

Removed modules (folder in `REMOVE`, `<module>` line taken out by `prepare.sh`):

| Removed | Why |
|---|---|
| `jakarta` (2 modules) | jars filled by `transformer-maven-plugin` from velocity-tools; Jenesis builds them empty |
| `plugins/velocity`, `plugins/tiles`, `plugins/config-browser` | compile against (or depend on a plugin compiling against) those transformed jars; tiles fails to compile with Jenesis, velocity fails a test |
| `apps` (showcase, rest-showcase, boot-hello) | two wars (Jenesis skips them), boot-hello inherits an antrun copy and a shade |
| `assembly` | distribution assembly (dependency, antrun, assembly plugins); active by default through `!skipAssembly` |
| `plugins/cdi` | all 6 tests fail with Jenesis under `jenesis.test.jars=false` (Weld finds no bean archive: classes and resources are separate folders); they pass with test jars, which core needs off |
| `plugins/jasperreports7` | Jenesis cannot fetch `com.github.librepdf:openpdf:1.3.43.jaspersoft.1` (not on Central; Maven resolves the module) unless Maven fetched the closure before, and its one test class writes beside its resources |

Removed test classes (in `REMOVE`), each failing with at least one tool on the otherwise prepared project:

| Removed | Fails with | Why |
|---|---|---|
| core `EnvsValueSubstitutorTest`, `XmlConfigurationProviderEnvsSubstitutionTest` | both | need the environment variable `USER`, unset on this machine; Jenesis hands a test JVM only the platform's variables anyway |
| core `XmlConfigurationProviderTest` | Jenesis | `testConfigsInJarFiles` needs surefire's `additionalClasspathElements` (xwork-jar.jar); 1 of its tests |
| core `FreemarkerResultMockedTest`, `DynAttribsTest` | Jenesis | turn a resource of core's main jar into a `File` ("URI is not hierarchical"): the module under test stays a jar |
| core `JarEntryRevisionTest` | Jenesis | writes a jar beside its test resources, which Jenesis refuses |
| convention `ConventionHttpMethodTest`, `ConventionJUnit4Test`, `ConventionScopedResultPathTest`, `DefaultResultMapBuilderTest`, `PackageBasedActionConfigBuilderTest` | Jenesis | 26 of 94 tests: class path scanning of the convention plugin does not find the actions in Jenesis' layout (not investigated further) |
| jasperreports `JasperReportsResultTest` | Jenesis | compiles reports beside its resources (with test jars: FileNotFoundException inside the jar) |

`mvnw`, `mvnw.cmd` and `.mvn` are removed so that no arm can fetch a Maven of its own.

`prepare.sh` also removes the `jshint-maven-plugin` block from `core/pom.xml` (a JavaScript lint only Maven would
run) and adds the fix's two test dependencies (`spring-test`, `spring-web`, test scope, versions managed by the
parent) to `plugins/bean-validation/pom.xml`, which the hidden test of that module needs. The agent is told not to
change build files and does not need to know.

Still Maven-only work on the prepared project, small and left in: `enforcer` (3 executions), `remote-resources`,
`bundle:manifest` per module.

`ExecuteAndWaitInterceptorTest.testOneWaitWithDelay` (core) failed once with Maven on the unprepared tree while
Jenesis ran beside it (timing: `expected:<success> but was:<wait>`); it passed in every later run of both tools,
several under load 8 to 13. Left in; a flake under load is possible.

## overlay-jenesis

- `jenesis.properties`: `jenesis.test.jars=false` (tests run against the module's class and resource folders, as
  surefire's do; with test jars 54 core tests fail) and `jenesis.test.exclude` with core's surefire `<excludes>`
  (`XWorkTestCase`, `TestBean`, `TestBean2`, `TestInterceptor`, `AnnotatedTestBean`, `DefaultFileManagerTest`).
  The exclusion is one setting for the build, so it applies to every module, where the poms apply all but
  `TestBean` to core alone; no other module has a class of these names that surefire runs (counts are equal).
- `build.jenesis/process-test.properties`: the root pom's surefire `argLine` (`--add-opens java.base/java.lang` and
  `java.base/java.util` to ALL-UNNAMED) and its `argLine` property (`-Duser.language=en -Duser.country=US
  -Duser.region=US`). Core's own surefire block resets `argLine` to the property alone, so with Jenesis core's
  tests get the two `--add-opens` that Maven does not give them; a root file reaches every module and a per-module
  file would have to be repeated in 13 folders.
- Not needed: `jenesis.process.directory` (no kept test depends on the module folder as working directory).

## What was run (JDK 25.0.5, Maven 3.9.x at /opt/maven, 4 cores shared with two other preparations: load 6 to 13 throughout)

All in `exp/prep/struts`; logs in `exp/prep/struts/logs`. Maven with a settings.xml mirroring central.

0. Unprepared pre-state, whole reactor
   - `mvn -B -ntp test`: FAILURE in core after 3m39 (3759 tests, 3 failures: the two `USER` tests and the
     `ExecuteAndWait` timing one); with `-Dmaven.test.failure.ignore=true` on the reduced reactor every module built.
   - `java build/jenesis/Make.java` (no overlay): FAILED after 4m58: jasperreports7 resolution, tiles javac, test
     failures in core (54), convention (25), jasperreports (12), rest (1, add-opens), velocity (1).
1. Maven on the prepared project (`mvn -o test`, `MAVEN_ARGS=-Daether.enhancedLocalRepository.trackingFilename=_none`)
   - clean tree, warm repository: BUILD SUCCESS, 4m28 (core 2m53).
   - again, nothing changed: BUILD SUCCESS, 2m32 (core 1m38; Maven runs every test again).
   - harness warm-up from an empty home, downloads included: 4m26.
   - Tests: core 3727 (2 skipped), async 2, bean-validation 23, spring 61, junit 12, convention 38,
     jasperreports 4, javatemplates 93, jfreechart 5, json 177, rest 242, testng 2, xslt 18, boot 52.
2. Jenesis on the prepared project plus overlay (`java build/jenesis/Make.java`, engine of /home/user/jenesis-pomgaps)
   - clean tree, warm repository: COMPLETED, exit 0, 3m05 (171 s build, core's tests 138 s).
   - again, nothing changed: COMPLETED, 6 s (2.6 s build).
   - harness run from the home Maven had filled: 203 s.
   - Tests: the same count as Maven in each of the 14 modules (core 3727, ..., boot 52).
3. Hidden tests with Maven, three modules (`-pl core,plugins/bean-validation,plugins/rest -am test -Dtest=<TESTS>
   -Dsurefire.failIfNoSpecifiedTests=false`, offline)
   - hidden/ over the prepared pre-state: BUILD FAILURE, 41 s, core 50 run / 6 failed (reactor stops there);
     with `-Dmaven.test.failure.ignore=true`: core 6/50, bean-validation 1/3, rest 9/11 failed.
   - plus `patch -p1 < reference.patch`: BUILD SUCCESS, 48 s, 50 + 3 + 11 tests, 0 failures.
   - the verifier as task.env has it (`-pl` all 14 leaf modules): after the fix BUILD SUCCESS, 66 s; in the harness
     before 19 s (FAILURE), after 35 s (SUCCESS).
4. Hidden tests with Jenesis:
   `java '-Djenesis.test.filter=.*(HttpMethodInterceptorTest|HttpMethodHierarchyTest|HttpMethodDefaultStacksTest|RestStackHttpMethodEnforcementTest|BeanValidationStackHttpMethodEnforcementTest)' -Djenesis.test.force=true -Djenesis.print.tests=true build/jenesis/Make.java +core +plugins+bean-validation +plugins+rest`
   - before the fix: exit 1, 19 s, the same failures (core 6/50, bean-validation 1/3, rest 9/11).
   - after: exit 0, 25 s, OK (50), OK (3), OK (11).
5. Harness: `WORK=.../prep/struts/work JENESIS_SOURCES=/home/user/jenesis-pomgaps MAVEN_MIRROR=... ./prepare.sh struts`
   ended with `Prepared struts` for the final task.env, 10m08 from an empty home: maven.log BUILD SUCCESS 4m34
   (the 14 test counts of step 1), before.log BUILD FAILURE 37 s (core 6 of 50), after.log BUILD SUCCESS 67 s
   (50 + 3 + 11), jenesis.log COMPLETED in 190 s.

## The loop: one edit in core, then the hidden tests

On the prepared project with hidden/ and the reference fix in place, a private method added to
`core/.../HttpMethodInterceptor.java` before each run (`exp/prep/struts/loop.sh`). The machine was never quiet
(two other preparations building), so these are loaded numbers; the load average is beside each.

- Maven: `mvn -o -B -Daether.enhancedLocalRepository.trackingFilename=_none -pl core,plugins/bean-validation,plugins/rest -am test -Dtest=HttpMethodInterceptorTest,HttpMethodHierarchyTest,HttpMethodDefaultStacksTest,RestStackHttpMethodEnforcementTest,BeanValidationStackHttpMethodEnforcementTest -Dsurefire.failIfNoSpecifiedTests=false`
  - round a (load 8 to 9): 56.4 s, 60.8 s, 45.7 s
  - round b (load 13 to 17): 68.9 s, 74.0 s, 51.9 s
  - round c (load 11 to 17): 140.9 s (the tree's `target` folders were gone, so a full compile), 80.8 s, 64.2 s
- Jenesis: the command of step 4
  - round a (load 8): 21.4 s, 18.2 s, 21.9 s
  - round b (load 12 to 14): 46.4 s, 35.3 s, 30.5 s
  - round c (load 10): 43.4 s (first build after the daemon was gone), 26.9 s, 25.3 s

Maven recompiles all of core's main and test sources after the edit (about 900 and 540 files) and starts three
surefire JVMs one after another. A loop on core alone (`-pl core -am`, the three core classes) was not timed.

## What the harness author must know

- `MODULES` lists all 14 leaf modules although the bug needs three: the harness warms Maven with
  `-pl $MODULES -am test`, and only this makes a plain `mvn test` of the Maven arm find every dependency at hand,
  as the Jenesis arm's warm-up (a plain build) does. The verifier therefore compiles all 14 modules (35 to 66 s
  here). With a warm-up of the whole reactor in the harness, `MODULES` could shrink to
  `core,plugins/bean-validation,plugins/rest`.
- `MAVEN_ARGS_EXTRA=-Daether.enhancedLocalRepository.trackingFilename=_none` as in the other tasks.
- The project carries its own `CLAUDE.md`, `AGENTS.md` and `.claude/` (skills, settings.json); `CLAUDE.md` names
  `mvn test -DskipAssembly` and `mvn test -DskipAssembly -pl core -Dtest=...` as the build commands. Left in for
  both arms; in the Jenesis arm they point at a tool that is not there.
- Tests of `plugins/testng` write a `test-output/` folder into their working directory: `plugins/testng/` with
  Maven, the project root with Jenesis (git-ignored by the project). It will show up in `agent.patch`.
- Jenesis leaves `target/` in every arm's root and its daemon running; `jenesis.properties` and `build.jenesis/`
  of the overlay sit in the project root.
- The first Jenesis build of the unprepared project printed nothing about `assembly`; the prepared one has no
  `[SKIPPED]`/`[EMPTY]` module line.

## Not verified

- Timings on a quiet machine.
- That every correct fix passes the hidden `HttpMethodInterceptorTest`: it pins the lookup order (class before its
  interfaces before the superclass) and the non-public/static rule, which `issue.md` states in words.
- `HttpMethodDefaultStacksTest` passes before the fix already (a guard for struts-default); it fails only if a
  core stack loses `httpMethod`.
- Jenesis with an empty `~/.m2` (the harness always runs Maven first into the same home).
- Whether the convention plugin's 26 failures under Jenesis have a setting that cures them.
