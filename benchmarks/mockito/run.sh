#!/usr/bin/env bash
# Mockito: its Gradle build against the Jenesis build of the migration, staged with sources, documentation and
# coverage, as Gradle's build publishes the jars and runs every test under JaCoCo. Both leave out
# StubbingWithBadThrowablesTest, which fails on Java 25.

UPSTREAM=https://github.com/mockito/mockito.git
COMMIT=220c594adceebf92a0d06e2fb1e4398b25344d46
OLD=gradle
EDITED=mockito-core/src/main/java/org/mockito/internal/util/Checks.java
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"

edit() {
    replace "$EDITED" '        return checkNotNull(value, checkedValue, null);' "        String $1 = null;
        return checkNotNull(value, checkedValue, $1);"
}

jenesis() {
    java $JENESIS_MODE -Djenesis.make.profiles=release,coverage build/jenesis/Make.java stage
}

old() {
    if [ "$1" = full ]; then
        gradlew --init-script "$HERE/exclude.init.gradle" clean build --no-build-cache
    else
        gradlew --init-script "$HERE/exclude.init.gradle" build
    fi
}

. "$HERE/../common.sh"
