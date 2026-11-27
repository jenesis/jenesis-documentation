# netty: a suspend request missed when the IoHandler drops the wakeup

- Fix: https://github.com/netty/netty/pull/18563, "Do not miss a suspend request when the IoHandler drops the
  wakeup", commit `79baf17ff5e6313b82a299bb16c454d6f9341367`, merged into `4.2` on 2026-11-26 (4.2.22.Final).
  No linked issue; `issue.md` is written from the PR's motivation as a user would see it.
- Pre-state: `9bd81544aa5a308d6b5a2efb7a33b0761d82713b`, the fix's only parent (checked with `git log -1 --format=%P`).
- Main change (`reference.patch`): `transport/.../SingleThreadIoEventLoop.java`, the `IoHandlerContext.canBlock()`
  of the loop also answers `false` when `canSuspend()` is true (4 lines incl. comment). The cause spans modules: the
  suspension state machine (`trySuspend`, `canSuspend`, `ST_SUSPENDING`, `isSuspended()`) is in
  `common/.../util/concurrent/SingleThreadEventExecutor.java`; `trySuspend()` only calls `wakeup()` and queues no
  task, and an IoHandler like epoll's drops a wakeup while the loop is awake.
- Hidden test: `transport/src/test/java/io/netty/channel/SingleThreadIoEventLoopTest.java` as after the fix (the
  class exists at the pre-state; the fix adds `testSuspendRequestedJustBeforeBlockingIsNotMissed` and the test double
  `DropsWakeupWhileAwakeIoHandler` inside the same file, so no support file is needed). The commit's other tests
  (`testsuite`'s `AbstractIoHandlerSuspendTest`/`NioIoHandlerSuspendTest`, epoll and kqueue variants) live in modules
  that are removed, and the NIO one passes with and without the fix anyway.

## What the prepared project is

`REMOVE` deletes every module folder but `dev-tools common buffer resolver transport testsuite-common jfr-stub
varhandle-stub ffm-stub`, the Maven wrapper, `AGENTS.md` and `.claude/` (Maven-specific agent guidance), docker /
devcontainer / scripts, and `NativeImageHandlerMetadataTest` (transport; asserts that the native-image metadata
committed under `src/main/resources` matches what a class-path scan of the build output generates - a check of the
build, and it scans the class path in a way Jenesis' layout does not give it).

`prepare.sh` (both arms):
- reactor reduced to the nine modules above. Left out: native transports (C via antrun/make), handler (needs
  transport-native-unix-common and an OS-classified tcnative), codec-http2 (`${os.detected.classifier}`), the
  packaging test suites, and every codec. `codec-base` (pure Java, depends on transport) was not added: the whole
  reduced build already takes about 4 min with Maven.
- root `<build>` loses revapi, enforcer, checkstyle, xml-maven-plugin, maven-bundle-plugin and the antrun
  execution that writes `META-INF/io.netty.versions.properties` from `git`; the jar plugin's `<manifestFile>` (the
  bundle plugin's output) is dropped so `mvn install` still works.
- `common`: the primitive collections (20 files) are generated once from `src/main/templates` /
  `src/test/templates` exactly as `codegen.groovy` does (output compared byte for byte with the Groovy plugin's)
  into `src/main/java` and `src/test/java`; templates, script, groovy and build-helper executions removed; shade
  (JCTools relocation), bundle and module-info plugins removed.
- `buffer`: bundle and module-info removed, and its JDK 24+ profile that runs every buffer test a second time
  with other JVM flags (a second surefire execution) removed. `resolver`, `transport`: module-info plugin removed.
  `dev-tools`: remote-resources bundle removed.
- Seven timing-sensitive test methods get `@Disabled("Timing-sensitive under load")` (they show as skipped in
  both tools):
  - `DefaultChannelPipelineTest.testRemoveOfHandlerReplacedConcurrently` (transport): 2000 rounds of two threads
    spinning on `Thread.yield()`, 10 s timeout; 1.3 s alone, timed out in 7 of 7 full Jenesis builds, where the
    four modules' test JVMs run side by side on four cores.
  - `SingleThreadEventLoopTest.scheduleTaskAtFixedRateA/B`, `scheduleLaggyTaskAtFixedRateA/B` (transport): assert
    fixed-rate jitter below 10 ms; in 7 full Jenesis builds `scheduleLaggyTaskAtFixedRateB` failed 4 times,
    `scheduleTaskAtFixedRateA` and `B` once each; `scheduleLaggyTaskAtFixedRateA` (same helper) is disabled with them.
  - `HashedWheelTimerTest.testExecutionOnTime` (common): wall-clock bound; failed in 1 of 7.
  - `AutoScalingEventExecutorChooserFactoryTest.testMetricsProvideCorrectUtilizationAndActiveExecutorCount`
    (common): utilization measured over wall time; failed in 1 of 7. (Same feature area as the bug; the other
    tests of that class stay.)
  None failed in five runs of the transport suite alone with either tool, nor in a full Maven build; they fail
  under load, which an agent's machine may well add, so they are off for both.

`MAVEN_ARGS_EXTRA` holds only `-Daether.enhancedLocalRepository.trackingFilename=_none`; nothing is skipped by flag.

`overlay-jenesis/` states what surefire's configuration does:
- `build.jenesis/process-test.properties` (root, reaches every module): surefire's `argLine`
  (`-server -dsa -da -ea:io.netty... -XX:+HeapDumpOnOutOfMemoryError
  -Djunit.jupiter.extensions.autodetection.enabled=true -Dio.netty.bootstrap.extensions=serviceload
  -Dio.netty.eventLoopThreads=2`) and its `systemPropertyVariables` `logback.configurationFile`, `logLevel`. The `:`
  is escaped (`-ea\:io.netty...`), as the file is read as properties. The two `nativeImage.handlerMetadata*`
  properties are left out: only the removed `NativeImageHandlerMetadataTest` reads them.
- `jenesis.properties`: `jenesis.process.directory=common` (surefire runs each module's tests in the module's
  folder; `NativeLibraryLoaderTest` in common opens `src/test/data/...` by a relative path, no other test of the
  reduced project depends on the folder, and the setting is build-wide only, so all test JVMs run in `common/`;
  the logback path is written relative to it); `jenesis.test.jars=false` (`HostsFileParserTest` in resolver turns
  a resource URL into a `File`, which fails from a jar); `jenesis.test.filter` / `jenesis.test.exclude` mirroring
  surefire's `includes` (`**/*Test*`, `**/*Benchmark*`) and `excludes` (`**/Abstract*`, `**/*TestUtil*`) -
  without them Jenesis ran four concrete `Abstract*Test` classes surefire skips and missed
  `LocalTransportThreadModelTest2/3` and the nested test classes of `LeakPresenceExtensionTest`. A filter on the
  command line replaces the file's, as an agent's single-class loop wants.

Test counts, prepared pre-state (Maven `Tests run` / Jenesis `tests found`), same test classes in every module
(compared class by class from the surefire reports and Jenesis' tree output):
common 1777 / 1782, testsuite-common 9 / 9, buffer 14052 / 14541, resolver 17 / 17, transport 448 / 448. The common
and buffer differences are how the two count parameterized/dynamic invocations, not different classes.

## What I ran (JDK 25.0.5, `JAVA_TOOL_OPTIONS` set with the proxy flags and `-Duser.home`, as the harness does)

Prepared tree = clone at the pre-state, `.git` removed, `REMOVE` deleted, `prepare.sh` run.

1. Maven full, plain `mvn -o -B test`: exit 0, 4m26s (first offline run on the prepared tree), 3m57s with nothing
   changed, 4m10s after a one-method edit of `SingleThreadIoEventLoop.java`. (Before the timing tests were disabled:
   5m10s online, exit 0.)
2. Jenesis full, plain `java build/jenesis/Make.java` with the overlay: exit 0 in 5 of 5 (122 s with warm
   dependency caches, then 108-112 s forced re-runs), 2 s with nothing changed, 95 s after the same edit (only
   transport recompiles and re-tests). Before the timing tests were disabled: exit 1 in 5 of 5 (see list above).
   Transport suite alone before that change: 5 of 5 green with each tool (Jenesis `+transport` 87 s, Maven
   `-pl transport test` 97 s).
3. Hidden test, Maven verifier (`mvn -o -B $MAVEN_ARGS_EXTRA -pl transport -am test -Dtest=SingleThreadIoEventLoopTest
   -Dsurefire.failIfNoSpecifiedTests=false`): without the fix 10 of 10 fail, always
   `testSuspendRequestedJustBeforeBlockingIsNotMissed` ("The event loop thread should have been suspended ==>
   expected: <false> but was: <true>", the test waits 10 s); with `reference.patch` 10 of 10 pass (9 run, 1 skipped,
   which is the class's existing `@Disabled` test).
4. Hidden test, Jenesis (`java -Djenesis.test.filter='.*SingleThreadIoEventLoopTest' -Djenesis.test.force=true
   build/jenesis/Make.java +transport`): 5 of 5 fail before (same test, same message), 5 of 5 pass after.

Loop after one edit to `SingleThreadIoEventLoop.java` (hidden test laid over, no fix, so the run includes the 10 s
the failing test waits), three timings each, warm:
- Maven `mvn -o -B -pl transport -am test -Dtest=SingleThreadIoEventLoopTest -Dsurefire.failIfNoSpecifiedTests=false`:
  20.9, 20.9, 21.9 s. With the upstream modules installed, `-pl transport` without `-am`: 21.0, 20.5, 21.1 s.
- Jenesis `java -Djenesis.print.progress=false -Djenesis.test.summary -Djenesis.test.filter='.*SingleThreadIoEventLoopTest'
  build/jenesis/Make.java +transport`: 15.2, 15.5, 15.2 s.
  With the fix the test itself takes about 1.3 s, so a passing loop is about 5 s (Maven) and 3-4 s (Jenesis).

Harness check: see the end of this file.

## What an engineer would look at outside the project's own sources

The bug is a race between two threads, so the behaviour to provoke is running the test repeatedly and looking at a
live JVM: the event-loop thread of a "suspended" loop is still alive, parked in the IoHandler. The test double parks
it in `Semaphore.tryAcquire(60 s)` inside `DropsWakeupWhileAwakeIoHandler.run`, called from
`SingleThreadIoEventLoop.run` -> `SingleThreadEventExecutor`'s loop; `jstack <pid>` / `jcmd <pid> Thread.print` of
the test JVM during the 10 s join shows it.
- Maven: the test JVM is surefire's forked booter (`surefirebooter*.jar`, found with `jps -l`); classes in
  `common/target/classes/io/netty/util/concurrent/SingleThreadEventExecutor.class` and
  `transport/target/classes/io/netty/channel/SingleThreadIoEventLoop.class`; reports in
  `transport/target/surefire-reports/`.
- Jenesis: the forked test JVM is started with `@.../build-testmodule-transport/produce/assemble/observed/test/executed~/supplement/java.args`
  (the command is printed on failure); classes in
  `target/build/maven/compose/module/build-module-common/produce/assemble/binary/classes/output/classes/io/netty/util/concurrent/SingleThreadEventExecutor.class`
  and `.../build-module-transport/.../classes/io/netty/channel/SingleThreadIoEventLoop.class`; test output in
  `target/build/maven/compose/module/build-testmodule-transport/produce/assemble/observed/test/executed{,~}/supplement/output`.
- The epoll handler the issue speaks of (`EpollIoHandler`, its `nextWakeupNanos`/`AWAKE` protocol) is not in the
  prepared project; neither the native modules nor a netty-transport-classes-epoll jar are present in either arm's
  repository. Its behaviour has to be inferred from the issue, or modelled in a test double as the fix does.

## What Jenesis could not do or needed

- No Maven plugin runs: the Groovy generation, shading, bundle manifests and module-info generation are gone from
  the project for both tools (above).
- Surefire's argLine, system properties, includes/excludes and working directory restated in the overlay; the
  working directory is build-wide only (`jenesis.process.directory`), which is fine here because only `common` needs it.
- Jenesis runs the modules' test JVMs concurrently; that exposed the load-sensitive tests listed above.

## Not verified

- A truly cold Jenesis build without any of the scout's cached artifacts (the harness check below is the cold
  measure for both tools).
- `issue.md` describes the epoll handler's behaviour in user terms; it does not name `canBlock`, the test, or the fix.

## Harness check

`WORK=<prep>/work JENESIS_SOURCES=/home/user/jenesis-agentout MAVEN_MIRROR=https://maven-central.storage-download.googleapis.com/maven2/ ./prepare.sh netty`
in a copy of the harness, JDK 25 first on PATH: ends with `Prepared netty` (8m49s in all). In its fresh home:
`maven.log` plain `mvn -B test` BUILD SUCCESS in 4m53s with downloads (common 1777, testsuite-common 9, buffer
14052, resolver 17, transport 448 tests, 0 failures); `maven-install.log` SUCCESS in 29 s; `before.log` fails on
`SingleThreadIoEventLoopTest` (1 failure), `after.log` passes; `jenesis.log` plain `java build/jenesis/Make.java`
`[COMPLETED]` in 120 s with downloads, 0 failures.
