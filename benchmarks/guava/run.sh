#!/usr/bin/env bash
# Guava: its Maven build without guava-gwt, which stays with Maven, against the Jenesis build of the migration
# under the release profile. Both leave out MoreFilesTest, which needs a user other than root, and
# InetAddressesTest, which needs an IPv6 interface with a scope ID. A full build takes about ten minutes.

UPSTREAM=https://github.com/google/guava.git
COMMIT=7caa334327e2d6a6b75920ff939048db21cd5b72
OLD=maven
EDITED=guava/src/com/google/common/base/Strings.java

edit() {
    replace "$EDITED" '    return Platform.nullToEmpty(string);
' "    String $1 = string;
    return Platform.nullToEmpty($1);
"
}

jenesis() {
    java $JENESIS_MODE -Djenesis.make.profiles=release \
        '-Djenesis.test.exclude=.*PackageSanityTest,guava-tests/com.google.common.io.MoreFilesTest,guava-tests/com.google.common.net.InetAddressesTest' \
        build/jenesis/Make.java build stage
}

old() {
    printf '**/MoreFilesTest.java\n**/InetAddressesTest.java\n' >"$WORK/surefire-excludes.txt"
    local same=(-B verify -pl '!guava-gwt' "-Dsurefire.excludesFile=$WORK/surefire-excludes.txt")
    if [ "$1" = full ]; then mvn clean "${same[@]}"; else mvn "${same[@]}"; fi
}

. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
