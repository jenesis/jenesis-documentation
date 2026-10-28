#!/usr/bin/env bash
# AssertJ: its Maven build against the Jenesis build of the migration, which builds from module-info.java; the tests
# of package-private code run with Maven only. Run as root, both builds leave out the tests that expect a file
# without read permission to be unreadable.

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
        local core=assertj-core/src/test/java/.* tests=assertj-tests/assertj-integration-tests/assertj-core-tests/src/test/java/.*
        excluded=("-Djenesis.test.exclude=$core[.]Files_assertHasDigest_.*_Test,$tests[.]Paths_(assertHasBinaryContent|assertHasDigest_with_.*|assertHasSameBinaryContentAs|assertHasSameTextualContentAs|assertHasTextualContent|assertIsReadable|assertIsWritable)_Test")
    fi
    java $JENESIS_MODE "${excluded[@]}" build/jenesis/Make.java
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
