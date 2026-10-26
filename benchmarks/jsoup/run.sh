#!/usr/bin/env bash
# jsoup: its Maven build against the Jenesis build of the migration, under the release profile, which adds the
# sources and documentation jars Maven writes.

UPSTREAM=https://github.com/jhy/jsoup.git
COMMIT=6feca03b300096c07ef60b9d771e4e094d63ba3b
OLD=maven
EDITED=src/main/java/org/jsoup/internal/StringUtil.java

edit() {
    replace "$EDITED" '        int l = string.length();
' "        int l = string.length();
        int $1 = l;
"
}

jenesis() {
    java $JENESIS_MODE -Djenesis.make.profiles=release build/jenesis/Make.java
}

old() {
    if [ "$1" = full ]; then mvn -B clean verify; else mvn -B verify; fi
}

. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
