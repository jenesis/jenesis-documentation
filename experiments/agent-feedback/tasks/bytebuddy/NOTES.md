# bytebuddy: constructor exit advice and long/double parameters (raphw/byte-buddy#1941)

- Issue: https://github.com/raphw/byte-buddy/issues/1941, "Constructor exit advice rejects valid compact frames
  with long or double parameters", opened 2026-10-21, closed 2026-10-23.
- Fix: two commits on master, taken together (authored 2026-10-22, committed 2026-10-23):
  `2901502` "Compare constructor frame divergence in frame entries rather than slots." (Fixes #1941) and
  `d7bf69f` "Detect dropped uninitialized 'this' frame in constructors after full frames."
- Pre-state: `8ade117` ("Update ASM and bridge."), the parent of `2901502`; `d7bf69f`'s parent is `2901502`
  (checked with `git log` and `git merge-base --is-ancestor`).
- Main change: `byte-buddy-dep/src/main/java/net/bytebuddy/asm/Advice.java`, the stack map frame handler for
  copied arguments (`StackMapFrameHandler.Default.WithPreservedArguments.WithArgumentCopy`), 11 lines.
  Hidden test: `byte-buddy-dep/src/test/java/net/bytebuddy/asm/AdviceTest.java` (four tests added, two sample
  classes). One module; the cause lies in the interplay with ASM's frame model, not in another module.

## Why it qualifies, and what it should invite

The symptom is an `IllegalStateException("... dropped implicit 'this' frame")` from a check that compares a
count of stack-map frame *entries* with `getStackSize()`, a count of JVM *slots*. A `long` or `double` local is
one frame entry but two slots, so the check fires on valid code. Nothing in the failing assertion says so; seeing
it takes knowing how ASM reports frames (`visitFrame` with compressed `F_SAME1`/`F_APPEND`/`F_CHOP`/`F_FULL`
frames, where a long is one entry) and what javac actually emitted for the constructor. The second commit is in the
same method: after an `F_FULL` frame the divergence was set to the length of the translated frame (copied arguments
included), so a later `F_CHOP` of the uninitialized `this` went undetected and the class failed verification.

The tool use it should invite: `javap -v -p` on a compiled sample class to read its `StackMapTable` (javac
emits, for `Child(long)` with a conditional super argument, `same_locals_1_stack_item` with `stack=[this]` and a
`full_frame` with `locals=[this, long]`, while the method header says `locals=3`: entries against slots, the whole
bug in one listing), or a look inside ASM's jar (`javap` on `org.objectweb.asm.MethodVisitor` / `Frame`, or its
sources) to learn how frames are counted. Where those are after preparation:

- ASM: `~/.m2/repository/org/ow2/asm/asm/9.11.1/asm-9.11.1.jar` in the run's home for both arms (the harness's
  warm home is `work/cache/bytebuddy/home`); Jenesis also copies it to
  `target/build/maven/compose/module/build-module-byte-buddy-dep/dependencies/artifacts/resolve/output/resolved/org.objectweb.asm-9.11.1.jar`.
  No sources jar of ASM is in either cache.
- The agent's own sample or test class, Maven: `byte-buddy-dep/target/test-classes/net/bytebuddy/asm/...`;
  Jenesis: `target/build/maven/compose/module/build-testmodule-byte-buddy-dep/produce/assemble/binary/classes/output/classes/...`
  (also in `.../binary/artifacts/jar/output/artifacts/net.bytebuddy~byte-buddy-dep~1.18.16-SNAPSHOT-tests.jar`).
- The class under change, Maven: `byte-buddy-dep/target/classes/net/bytebuddy/asm/Advice$StackMapFrameHandler$Default$WithPreservedArguments$WithArgumentCopy.class`;
  Jenesis: `target/build/maven/compose/module/build-module-byte-buddy-dep/produce/assemble/binary/classes/output/classes/net/bytebuddy/asm/...`.

The cheapest way around it: the issue text says the parameter type matters, and reading `translateFrame` next to
`injectStartFrame` in `Advice.java` shows the two counts; an agent that knows the JVM's two-slot rule can fix the
first half by reading alone. The second half (full frame, then chop) is harder to see without writing a test.

## issue.md

Written from the issue's own text and reproducer (read through the GitHub API with WebFetch), less its last
paragraphs, which name the cause and the proposed fix (`getParameters().size() + 1` in place of `getStackSize()`).
The second commit has no issue of its own; its symptom is user-visible, so issue.md describes it in a section of
its own in plain words: a constructor whose bytecode has a full frame with `UNINITIALIZED_THIS` before the super
call and a later chop of that local is transformed without error and fails verification on loading; expected is the
same "dropped implicit 'this' frame" refusal, while dropping an initialized `this` keeps working. That symptom was
checked by running (a probe test at the pre-state, loading the transformed class: `java.lang.VerifyError:
Instruction type does not match stack map`). The section is needed: without it an agent fixing the first half only
fails `testDroppingOfThisFrameInConstructorAfterFullFrame`, and it states the expected refusal, which is the
behaviour that test asserts; it does not name the test or the code change.

## The prepared project (prepare.sh, REMOVE), for both arms

Following the project owner's guidance, build requirements unrelated to the bug are dropped for both tools.

| Change | Reason |
|---|---|
| reactor reduced to the parent, `byte-buddy-dep` and `byte-buddy-agent`; `byte-buddy`, `-benchmark`, `-android`, `-android-test`, `-maven-plugin`, `-gradle-plugin` and `-fuzz` (profile-only) deleted via REMOVE | shading, JMH, Android SDK, plugin packaging; `byte-buddy-dep`'s tests require `byte-buddy-agent` (test scope), so the agent stays |
| `mvnw`, `mvnw.cmd`, `.mvn`, `.clusterfuzzlite` deleted | wrapper and fuzzing config; `.mvn/maven.config` only set an Aether checksum option |
| `byte-buddy-maven-plugin` `transform` execution removed from `byte-buddy-dep` | Byte Buddy rewrites its own classes (equals/hashCode, cached returns, access-controller dispatch) with the released 1.18.14 plugin; Jenesis does not; tests pass without it in both tools (11,026 tests instead of 11,030 with it; the four I did not identify) |
| `<resource><directory>..</directory>` (LICENSE/NOTICE into META-INF) removed from both module poms | a resource outside the module |
| `maven-jar-plugin` manifest config, `maven-bundle-plugin` and `modulemaker-maven-plugin` removed from `byte-buddy-agent` | OSGi/agent manifest and `module-info.class` generation; the agent's 52 tests pass without them |
| `license-maven-plugin` (format at `package`, root) removed | rewrites source headers on `install` |
| 18 `java-<v>-precompile` / `java-<v>-no-precompile` profiles of `byte-buddy-dep` removed; the nine `src/test/precompiled-<v>` folders become plain `<testResources>` beside `src/test/resources`; the `src/test/java-<v>` folders only the precompile profiles compiled are in REMOVE | the default (no-precompile) behaviour made explicit, so neither tool depends on property-negated profile activation |
| the 21 `java<N>-compatibility` profiles of the root removed; `sourcecode/bytecode.main/test.version` set from 1.5/1.6 to 25 | Java 5 compatibility; on JDK 25 the `java25-compatibility` profile compiled at 8, Jenesis compiles at the JDK's level; now both compile at 25 |
| `<compilerArgument>-Xlint:all,-options,-processing</compilerArgument>` removed | hundreds of lint warnings Maven printed and Jenesis does not ask javac for |

Each edit checks itself (match counts, XML parse of the three poms, `grep` afterwards). The inactive profiles
(`extras`, `native-compile`, `multi-release`, `checks`, `analysis`, `java<N>` target profiles, ...) stay.

`overlay-jenesis/` states what surefire passes and Jenesis does not read from the plugin block:
`build.jenesis/process-test.properties` (`-XX:+EnableDynamicAgentLoading` from the root's
`surefire-enable-dynamic-attach` profile for JDK >= 21, and `systemPropertyVariables`
`net.bytebuddy.experimental=true`, `net.bytebuddy.test.integration=false`), and
`byte-buddy-agent/build.jenesis/process-test.properties` with the same plus the agent's `-Djna.library.path=`
(a module's file replaces the root's, so it repeats them). Checked in the test step's `command` file.

## What was run (JDK 25.0.5, Maven 3 at /opt/maven, JAVA_TOOL_OPTIONS set; engine /home/user/jenesis-agentout)

Over the prepared project:

| | Maven | Jenesis |
|---|---|---|
| plain full build, cold (warm dependency cache) | `mvn -B test`: exit 0, 58 s (harness: 1:07 min) | `java build/jenesis/Make.java`: exit 0, 59 s wall, "Finished in 47 s" (harness: 45 s) |
| plain, nothing changed | `mvn -o -B test`: exit 0, 35 s | exit 0, 3 s |
| plain, after one edit to `Advice.java` | exit 0, 78 s | exit 0, 57 s |
| tests | agent 52, dep 11,026 | agent 52, dep 11,026 |

Proof 3 (verifier `mvn -o -B -pl byte-buddy-dep -am test -Dtest=AdviceTest -Dsurefire.failIfNoSpecifiedTests=false`,
hidden test laid over): before the fix exit 1, 27 s, 212 run, 1 failure + 2 errors
(`testDroppingOfThisFrameInConstructorAfterFullFrame` expected `IllegalStateException`;
`testConstructorWith{Long,Double}ParameterAndCompactFrame` throw "dropped implicit 'this' frame"); with
`reference.patch` exit 0, 31 s, 212 run.

Proof 4 (`java -Djenesis.print.progress=false -Djenesis.test.summary -Djenesis.test.filter='.*AdviceTest'
build/jenesis/Make.java +byte-buddy-dep`): before exit 1, 25 s, 242 found, the same 3 failed; after exit 0, 16 s,
242 passed. The regex also matches other classes whose names end in `AdviceTest` (242 against Maven's 212).

Harness check (`WORK=.../prep3/bytebuddy/work JENESIS_SOURCES=/home/user/jenesis-agentout MAVEN_MIRROR=...
./prepare.sh bytebuddy` in a copy of the harness): ended with `Prepared bytebuddy` after 309 s; `maven.log`
52 + 11,026 green, `maven-install.log` BUILD SUCCESS, `before.log` the 3 failures, `after.log` 212 green,
`jenesis.log` 52 + 11,026 green. The uninstall left no 1.18.16-SNAPSHOT in the warm repository.

Loop, hidden test laid over and the fix applied (one string in `Advice.java` toggled before each run; three runs):

| command | runs |
|---|---|
| `mvn -o -q -pl byte-buddy-dep -am test -Dtest=AdviceTest -Dsurefire.failIfNoSpecifiedTests=false` | 40.8 s, 31.4 s, 38.9 s |
| same without `-am`, after one `mvn install -DskipTests` | 22.3 s, 22.5 s, 23.9 s |
| `java -Djenesis.print.progress=false -Djenesis.test.summary -Djenesis.test.filter='.*AdviceTest' build/jenesis/Make.java +byte-buddy-dep` | 21.0 s, 17.4 s, 16.3 s |

Maven runs 212 tests per loop, Jenesis 242 (see proof 4). I did not break down where either spends its time.

## Not verified

- Which four tests disappear without the self-transform (11,030 to 11,026); both tools agree on 11,026.
- No timings on an idle machine could be guaranteed; other scouts may have shared the four cores.
