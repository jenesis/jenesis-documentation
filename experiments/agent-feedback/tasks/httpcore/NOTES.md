# httpcore: premature termination of incomplete chunked messages

- Project: https://github.com/apache/httpcomponents-core
- Fix: https://github.com/apache/httpcomponents-core/commit/efb46e4bf830d93547aa101bcecab382240cb4b9
  "Fix premature termination of incomplete chunked messages" (Arturo Bernal), authored 2026-11-09,
  committed to master 2026-11-10. Single commit, parent 428c959d5 = pre-state. The pull request number and text
  could not be read (GitHub API answers 403 for this repository in this session, no WebFetch used); issue.md is
  written from the commit message, the diff and the behaviour I observed at the pre-state.
- Changes: main `DefaultBHttpClientConnection.java`, `DefaultBHttpServerConnection.java` (httpcore5,
  package org.apache.hc.core5.http.impl.io); tests `TestDefaultBHttpClientConnection` (+2 methods),
  `TestDefaultBHttpServerConnection` (+1 method).

## Why it qualifies

- After 2026-07-01 (2026-11-10).
- Two main files, a client and a server side. The cause is not in the assertion: the failing assertions say
  "output ends with 0\r\n\r\n" / "connection still open" / "still consistent"; the cause is a try-with-resources
  around the content output stream, whose implicit close() makes ChunkedOutputStream write the last chunk even
  when writeTo threw or a ResponseOutOfOrderException aborted the body. The fix has to (a) not close the codec
  stream on failure, (b) close the connection immediately and mark the client inconsistent on IOException or
  RuntimeException, (c) keep the early-response path open and exception-free while marking it inconsistent for
  chunked bodies (`len > 0` -> `len != 0`, as chunked is a negative length constant). An agent may also look at
  ChunkedOutputStream / BHttpConnectionBase, which are plausible alternative places.
- Tests are Mockito mocks over ByteArray streams: no socket, no network, deterministic.
- Weakness: one module only (the cause and the symptom are both in httpcore5), and the fix is ~20 lines.

## Environment facts

- JDK 25.0.5+8, Maven 3.9.11, 4 cores, two other preparations running at the same time (durations are noisy).
- Maven was warmed through a `settings.xml` mirror (id `gcs`, mirrorOf central, the googleapis URL); I never
  tried repo1 directly. Consequence: `mvn -o` WITHOUT that settings file refuses every artifact
  ("present, but unavailable ... has not been downloaded from it before", first on
  httpcomponents-parent:pom:15), because ~/.m2 records the repository id `gcs`. Either run the harness and the
  Maven-arm agent with the same `-s settings.xml`, or pass
  `-Daether.enhancedLocalRepository.trackingFilename=_none`, which is in MAVEN_ARGS_EXTRA and which I verified.
  `-llr` is not accepted by this Maven, `-Dmaven.legacyLocalRepo=true` does not help.
- MAVEN_ARGS_EXTRA also skips checkstyle and animal-sniffer so that the verifier does not fail an agent's fix
  on style. Without those two flags the project also builds and passes (run below); the build runs
  checkstyle, enforcer, remote-resources, build-helper, animal-sniffer before compiling.

## Step 1: Maven at the pre-state (ran)

    mvn -B -s ../settings.xml -pl httpcore5 -am test                      cold, downloads   1m20s  2011 tests, 0 failures
    mvn -o -B -Daether...trackingFilename=_none -pl httpcore5 -am test      warm              36s    2011 tests, 0 failures
    mvn -o -B -Daether...=_none -pl httpcore5 -am test -Dtest=TestDefaultBHttpClientConnection,TestDefaultBHttpServerConnection -Dsurefire.failIfNoSpecifiedTests=false
                                                                            warm              28s    27 tests (15 + 12)
    the same with -Dcheckstyle.skip=true -Danimal.sniffer.skip=true         warm              16-17s

## Step 2: Jenesis at the pre-state (ran)

Tree: pre-state checkout + copy of /home/user/jenesis/sources/build/jenesis as build/jenesis + overlay-jenesis/.
MAVEN_REPOSITORY_URI set as PREP.md says.

    java build/jenesis/Make.java +httpcore5                                 no overlay: FAILS, see below
    java -Djenesis.print.tests=true build/jenesis/Make.java +httpcore5      target/ deleted, daemon and ~/.m2 warm  23s  2011 found, 2011 successful
    java build/jenesis/Make.java +httpcore5                                 nothing changed   4s (0.4s build)
    java -Djenesis.print.tests=true build/jenesis/Make.java                 whole project, httpcore5 cached  51s  exit 0;
                                                                            other test modules: 409, 425 (371 successful, rest skipped), 11 tests, 0 failed

Test count httpcore5: Maven 2011, Jenesis 2011. The very first Jenesis command in the tree (help) took 18s,
which is the engine compiling itself. I did not compare the other modules' counts with Maven and did not time a
Jenesis run with an empty ~/.m2 or without the daemon.

What Jenesis needed (overlay-jenesis/, two one-line files, no source or pom touched):

1. `build.jenesis/process-javac.properties` with `--source=8`. The poms set maven.compiler.source/target 1.8 and
   explicitly unset `<release>` because the code uses jdk.net.ExtendedSocketOptions / jdk.net.Sockets. Jenesis
   reads source/target as `--release 8`, and javac then fails with 34 errors
   ("cannot find symbol ... variable ExtendedSocketOptions / Sockets", RequestListener.java, ReflectionUtils.java).
   The tool's own migration text names this remedy.
2. `jenesis.properties` with `jenesis.process.directory=httpcore5`. Jenesis runs tests in the project root,
   Surefire in the module folder; without it 2 of 2011 tests fail
   (TestAsyncEntityProducers.testPathEntityProducer and ...WithTrailers: NoSuchFileException
   src/test/resources/test-ssl.txt). No other module has a test reading a relative path (grep), and the whole
   project passed with the setting.

Jenesis writes `target/` and `.jenesis/` into the project. Not carried over: checkstyle, animal-sniffer, enforcer,
RAT, `-ea` (Jenesis runs tests without assertions enabled; httpcore5 has 2 `assert` statements; all tests pass).

## Step 3: hidden tests with Maven (ran, the harness's verifier command with task.env's values)

    mvn -o -B $MAVEN_ARGS_EXTRA -pl httpcore5 -am test -Dtest=$TESTS -Dsurefire.failIfNoSpecifiedTests=false

- hidden/ copied over the pre-state: exit 1, BUILD FAILURE, 30 tests, 3 failures (16s):
  TestDefaultBHttpClientConnection.testChunkedEntityFailureDoesNotTerminateMessage:290,
  TestDefaultBHttpClientConnection.testEarlyResponseDoesNotAbortConnection:266,
  TestDefaultBHttpServerConnection.testChunkedEntityFailureDoesNotTerminateMessage:233,
  each "expected: <false> but was: <true>".
- plus `git apply reference.patch`: exit 0, 30 tests, 0 failures (17s).
- whole httpcore5 suite after the fix, checkstyle and animal-sniffer on: 2014 tests, 0 failures (38s).

## Step 4: hidden tests with Jenesis (ran)

    java '-Djenesis.test.filter=.*TestDefaultBHttp(Client|Server)Connection' -Djenesis.test.force=true -Djenesis.print.tests=true build/jenesis/Make.java +httpcore5

- hidden/ over the pre-state: exit 1, 30 found, 27 successful, 3 failed, the same three methods (10s).
- plus reference.patch: exit 0, 30 found, 30 successful (13s).
- `java build/jenesis/Make.java +httpcore5` after the fix: exit 0 (15s).

## Not verified

- The pull request's own text and number.
- Maven against repo1 directly; Jenesis with a cold ~/.m2 and without a running daemon.
- Other candidates considered and left: 3d3b9d2e9 (RouteSegmentedConnPool rewrite, a feature with a benchmark),
  e99e07816 (five one-line resets), 9983b0361 / 57428d2b8 (2-3 line fixes), d68d4f550 (one line).

## issue.md, what is observed and what is inferred

At the pre-state each hidden test stops at its first failing assertion: client entity failure and early response
at `assertFalse(conn.isConsistent())`, server entity failure at `assertFalse(conn.isOpen())`. That the output ends
with the terminating chunk after an entity failure is read from the code (try-with-resources closes the
ChunkedOutputStream) and stated by the commit message, not observed by a failing assertion of its own.
