#!/usr/bin/env bash
# Jackson Databind: its Maven build against the Jenesis build of the migration, which builds from the pom.xml and
# runs the tests on the class path, where Maven patches them into the main module.

UPSTREAM=https://github.com/FasterXML/jackson-databind.git
COMMIT=f2d5472325296497fc1c2a5ea53cc622cd071339
OLD=maven
EDITED=src/main/java/tools/jackson/databind/util/ClassUtil.java

edit() {
    replace "$EDITED" "return new StringBuilder(text.length()+2).append('\`').append(text).append('\`').toString();" \
        "String $1 = text; return new StringBuilder($1.length()+2).append('\`').append($1).append('\`').toString();"
}

jenesis() {
    java $JENESIS_MODE $MAKE
}

old() {
    if [ "$1" = full ]; then mvn -B clean verify; else mvn -B verify; fi
}

. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
