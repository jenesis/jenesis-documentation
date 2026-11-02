#!/usr/bin/env bash
# Apache Commons IO: the Mill build that Mill's own examples keep for it against the Jenesis build of the migration,
# which builds from the project's pom.xml. The patch adds that Mill build, its launcher and version, with the tests in
# one JVM at a time, as Maven, Gradle and Jenesis run them by default where Mill spreads a module's test classes over
# several, and the Jenesis lines: the tests read their resources from folders, as Mill hands them, and see the
# machine's JAVA_TOOL_OPTIONS, as tests forked by Mill do. Both run the tests with byte-buddy's experimental support of
# the JDK, which Mockito 4.11 needs on Java 25, and leave out FileUtilsWaitForTest, whose interrupted wait races the
# thread it interrupts, and, run as root, the four test classes that expect a read-only file to refuse access. Mill's
# tests are handed the target folder they write to, which Maven would create.

UPSTREAM=https://github.com/apache/commons-io.git
COMMIT=b91a48074231ef813bc9b91a815d77f6343ff8f0
OLD=mill
EDITED=src/main/java/org/apache/commons/io/FilenameUtils.java

edit() {
    replace "$EDITED" '        return SYSTEM_NAME_SEPARATOR == WINDOWS_NAME_SEPARATOR;
' "        boolean $1 = SYSTEM_NAME_SEPARATOR == WINDOWS_NAME_SEPARATOR;
        return $1;
"
}

UNREADABLE=(FileUtilsTest FileUtilsCleanDirectoryTest FileUtilsDeleteDirectoryLinuxTest filefilter/FileFilterTest)

readable() {
    local test
    for test in FileUtilsWaitForTest $(root && echo "${UNREADABLE[@]}"); do
        rm -f "src/test/java/org/apache/commons/io/$test.java"
    done
}

jenesis() {
    readable
    java $JENESIS_MODE $MAKE
}

old() {
    readable
    mkdir -p target
    if [ "$1" = full ]; then mill clean + jar + test; else mill jar + test; fi
}

. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
