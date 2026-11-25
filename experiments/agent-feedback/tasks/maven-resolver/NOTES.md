# maven-resolver: version-range candidates skipped by the breadth-first collector

- Fix: apache/maven-resolver PR #2208 "Fix BF skipper handling of version-range candidates"
  (https://github.com/apache/maven-resolver/pull/2208), commit 82f658779d0b24f2995738634a2345c8fc15d642
  "Fix skipping of version-range candidates (#2208)", merged 2026-10-20 (single squashed commit).
- Issue: https://github.com/apache/maven/issues/13430 "Maven 3.10 omits transitive dependencies of conflicting
  range-resolved dependencies", opened 2026-10-12. `issue.md` is written from it and from the PR description.
- Pre-state: bf02fa2a40974fba8bec5695d8de8f91c6c36deb (parent of the fix), version 2.0.25-SNAPSHOT.

## Why it qualifies

- Merged after 2026-07-01. Main change in `maven-resolver-impl/.../collect/bf/DependencyResolutionSkipper.java`
  (15 lines, two cooperating changes in the cache manager plus a helper); tests: one new method in each of
  `BfWithSkipperDependencyCollectorTest` and `DependencyResolutionSkipperTest`, and six new `.ini` descriptors.
- The symptom (a node of the collected graph has no children) shows in the collector; the cause is in the skipper
  the collector consults, in what it remembers per versionless key. The collector test assertion says only
  "expected true but was false".
- Half a fix fails: only stopping range nodes from being skipped passes the collector test, but the skipper test
  then fails, because the range node replaces the cached winner and a later plain occurrence of the first version
  is reported as a version conflict instead of a duplicate. `issue.md` states that requirement in words.
- No network, no service, deterministic (in-memory descriptor reader over `.ini` files).
- Weakness: one main file, the bug and its cause are in the same module. Other candidates read and rejected:
  8920b5be (#2238, three files, but one of its tests self-skips as root and one fix has no test), e8c0e574
  (#2217, hidden tests would be bound to a refactored API), 9e552940 (#2261, adds an SPI method).

## What was run (JDK 25.0.5, Maven 3.9.11, 4 cores shared with two other preparations)

Maven needs a settings.xml mirroring central to
`https://maven-central.storage-download.googleapis.com/maven2/` (used with `-s` for the warm-up).

1. Maven, pre-state
   - `mvn -B -s settings.xml -pl maven-resolver-impl -am test` : BUILD SUCCESS, 2m35s (downloads included; the
     shared ~/.m2 may already have held part). Tests: api 91, spi 35, test-util 23, util 467, named-locks 42,
     impl 599 (1 skipped).
   - `mvn -o -B -s settings.xml -pl maven-resolver-impl -am test` : BUILD SUCCESS, 1m52s, same counts.
2. Jenesis, pre-state, unchanged poms, `build/jenesis` copied, `overlay-jenesis/jenesis.properties`
   - `java build/jenesis/Make.java +maven-resolver-impl` without the overlay: 40s, FAILED with 1 of 599 tests,
     `PrefixesSourceTest.smoke`, which reads `src/test/resources/prefixes` relative to the working directory.
   - with the overlay (`jenesis.process.directory=maven-resolver-impl`): COMPLETED, 39s (test step 37s);
     599 tests found, 598 successful, 1 skipped, 0 failed: the same as Maven's impl module. The Maven local
     repository was already filled by step 1 and Jenesis reads `~/.m2/repository`, so this is not a cold download.
   - Only impl's tests run with this selector; api, spi, util, named-locks and test-util are compiled, not tested.
3. Hidden tests with Maven (verifier)
   - hidden/ copied over the pre-state:
     `mvn -o -B -s settings.xml -pl maven-resolver-impl -am test -Dtest=BfWithSkipperDependencyCollectorTest,DependencyResolutionSkipperTest -Dsurefire.failIfNoSpecifiedTests=false`
     : BUILD FAILURE, 40s, Tests run 28, Failures 2
     (`testVersionRangeCandidateDependenciesAreNotSkipped`, `testVersionRangeDoesNotReplaceVersionlessWinner`).
   - plus `git apply reference.patch`: BUILD SUCCESS, 36s, 28 tests, 0 failures.
   - the harness form, without `-s`, with `MAVEN_ARGS_EXTRA`: BUILD SUCCESS, 30s (post-fix state only).
4. Hidden tests with Jenesis
   - `java '-Djenesis.test.filter=.*(BfWithSkipperDependencyCollectorTest|DependencyResolutionSkipperTest)' -Djenesis.test.force=true -Djenesis.print.tests=true build/jenesis/Make.java +maven-resolver-impl`
     before the fix: exit 1, 5s, 28 found, 2 failed (the same two); after: exit 0, 5s, 28 successful.
   - full `+maven-resolver-impl` after the fix: COMPLETED, 36s, 601 found, 600 successful, 0 failed.

## What the harness author must know

- `MAVEN_ARGS_EXTRA=-Daether.enhancedLocalRepository.trackingFilename=_none` is required unless the verifier
  runs with the very settings.xml of the warm-up: artifacts fetched through the mirror are tracked for the mirror's
  id, and `mvn -o` without the mirror refuses them
  (`Non-resolvable import POM ... jetty-bom:pom:12.1.14 (present, but unavailable)`). `-llr` is rejected by
  Maven 3.9. With the flag the verifier passed offline without any settings.xml.
- Warm-up for the Maven arm must be `-pl maven-resolver-impl -am test` at least once online; the root pom imports
  BOMs (jetty-bom and others) even for this subset.
- Jenesis cannot build the whole reactor here: `java -Djenesis.test.skip=true build/jenesis/Make.java` FAILED after
  23s with `Failed to fetch maven/org.apache.maven.resolver/maven-resolver-transport-jdk/2.0.25-SNAPSHOT`:
  `maven-resolver-transport-jdk` has no sources of its own (a plugin assembles a multi-release jar from the
  jdk8/jdk11/jdk21 modules), Jenesis skips it and every module depending on it (demos, tools, ...) cannot resolve;
  `maven-resolver-demo-maven-plugin` (packaging maven-plugin) is skipped as well. None of this is needed for the
  bug. The Jenesis arm therefore has to be told to run `java build/jenesis/Make.java +maven-resolver-impl`
  (`JENESIS_SELECTOR` in task.env, an addition to the PREP.md format). `REMOVE` is empty because deleting module
  folders would break the root pom's `<modules>` for Maven.
- `jenesis.process.directory` is one setting for the whole build, not per module: with the overlay every forked
  process runs in `maven-resolver-impl/`, which is right only as long as impl is the one module tested.
- Jenesis runs in daemon mode by default: a JVM stays behind after each build.
- Jenesis leaves `.jenesis/`, `build/`, `jenesis.properties` and `target/` in the tree (the first three untracked
  in git status).

## Not verified

- A cold Jenesis run with an empty `~/.m2` and `~/.jenesis`.
- Jenesis running the tests of the upstream modules (api, spi, util, named-locks, test-util).
- That every alternative correct fix passes `testVersionRangeDoesNotReplaceVersionlessWinner`, which asserts the
  skipper's package-private result flags (`skippedAsDuplicate`, `skippedAsVersionConflict`).
- The Maven full impl test count after the fix (only the two hidden classes were run post-fix with Maven).
