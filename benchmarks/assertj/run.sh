#!/usr/bin/env bash
# AssertJ: its Maven build against the Jenesis build of the migration, which builds from the pom.xml files and runs
# the tests on the class path. The eleven test classes that rely on the Java Module System - module names in stack
# traces, a resource found through the test module, the Module_Test classes - run with Maven only, and Maven runs
# the OSGi tests inside Equinox where Jenesis runs them on JUnit alone. Run as root, both builds leave out the tests
# that expect a file without read permission to be unreadable.

UPSTREAM=https://github.com/assertj/assertj.git
COMMIT=170e64c0aaa3fcb1a1b371c29d499cc3472eda7a
OLD=maven
EDITED=assertj-core/src/main/java/org/assertj/core/util/Strings.java

edit() {
    replace "$EDITED" '    return s == null || s.isEmpty();
' "    boolean $1 = s == null || s.isEmpty();
    return $1;
"
}

UNREADABLE=(Files_assertHasDigest_.*_Test Paths_assertHasBinaryContent_Test 'Paths_assertHasDigest_with_.*_Test'
    Paths_assertHasSameBinaryContentAs_Test Paths_assertHasSameTextualContentAs_Test Paths_assertHasTextualContent_Test
    Paths_assertIsReadable_Test Paths_assertIsWritable_Test)

jenesis() {
    local excluded=()
    if root; then
        local declared core=assertj-core/org.assertj.core tests=assertj-tests/assertj-integration-tests/assertj-core-tests/org.assertj.tests.core
        declared="$(sed -n 's/^jenesis\.test\.exclude=//p' jenesis.properties)"
        excluded=("-Djenesis.test.exclude=${declared:+$declared,}$core.internal.files.Files_assertHasDigest_.*_Test,$tests.internal.paths.Paths_assert(HasBinaryContent|HasDigest_with_.*|HasSameBinaryContentAs|HasSameTextualContentAs|HasTextualContent|IsReadable|IsWritable)_Test")
    fi
    java $JENESIS_MODE "${excluded[@]}" $MAKE
}

old() {
    local excluded=()
    if root; then
        printf '**/%s.java\n' "${UNREADABLE[@]//.\*/*}" >"$WORK/surefire-excludes.txt"
        excluded=("-Dsurefire.excludesFile=$WORK/surefire-excludes.txt")
    fi
    if [ "$1" = full ]; then mvn -B clean verify "${excluded[@]}"; else mvn -B verify "${excluded[@]}"; fi
}

. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
