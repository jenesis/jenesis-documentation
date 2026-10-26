#!/usr/bin/env bash
# Google Auto: its Maven build, without the invoker tests, the GWT serialisation test and the sources and
# documentation jars, against the Jenesis build of the migration.

UPSTREAM=https://github.com/google/auto.git
COMMIT=973d60f68d75ffe1b548e7892b358dee91c73753
OLD=maven
EDITED=value/processor/src/main/java/com/google/auto/value/processor/PropertyNames.java

edit() {
    replace "$EDITED" '    return Character.toLowerCase(propertyName.charAt(0)) + propertyName.substring(1);
' "    String $1 = propertyName.substring(1);
    return Character.toLowerCase(propertyName.charAt(0)) + $1;
"
}

jenesis() {
    java $JENESIS_MODE build/jenesis/Make.java
}

old() {
    local same=(-B verify -Dinvoker.skip=true -Dmaven.javadoc.skip=true -Dsource.skip=true -pl '!value/src/it/gwtserializer')
    if [ "$1" = full ]; then mvn clean "${same[@]}"; else mvn "${same[@]}"; fi
}

. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
