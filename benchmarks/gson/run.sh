#!/usr/bin/env bash
# Gson: its Maven build against the Jenesis build of the migration.

UPSTREAM=https://github.com/google/gson.git
COMMIT=e2292f9c9f2e07a4791827e8eea34aa7d80545d6
OLD=maven
EDITED=gson/src/main/java/com/google/gson/JsonNull.java

edit() {
    replace "$EDITED" '    return JsonNull.class.hashCode();' "    int $1 = JsonNull.class.hashCode();
    return $1;"
}

jenesis() {
    java $JENESIS_MODE $MAKE
}

old() {
    if [ "$1" = full ]; then mvn -B clean verify; else mvn -B verify; fi
}

. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
