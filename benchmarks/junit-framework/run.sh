#!/usr/bin/env bash
# JUnit 5: the build and tests of every published project and the two test projects with Gradle, against the
# Jenesis build of the migration under the release profile. Gradle runs without predictive test selection and
# without the checks that compare with the previous release.

UPSTREAM=https://github.com/junit-team/junit-framework.git
COMMIT=bf5b78f7aec4bef69240703e94d984ae04e1cafa
OLD=gradle
EDITED=junit-platform-commons/src/main/java/org/junit/platform/commons/util/StringUtils.java

edit() {
    replace "$EDITED" $'\t\treturn (str == null || str.isBlank());\n' $'\t\tboolean '"$1"$' = (str == null || str.isBlank());\n\t\treturn '"$1"$';\n'
}

jenesis() {
    java $JENESIS_MODE -Djenesis.make.profiles=release $MAKE
}

old() {
    local tasks=() project
    for project in junit-bom junit-jupiter junit-jupiter-api junit-jupiter-engine junit-jupiter-migrationsupport \
        junit-jupiter-params junit-platform-commons junit-platform-configuration-api \
        junit-platform-configuration-processor junit-platform-console junit-platform-console-standalone \
        junit-platform-engine junit-platform-launcher junit-platform-reporting junit-platform-suite \
        junit-platform-suite-api junit-platform-suite-engine junit-platform-testkit junit-start junit-vintage-engine \
        jupiter-tests platform-tests; do
        tasks+=(":$project:build")
    done
    tasks+=(:checkstyleNohttp -x roseau -x downloadPreviousReleaseJar -x checkBackwardCompatibility)
    local same=(-Pjunit.develocity.predictiveTestSelection.enabled=false "${tasks[@]}")
    if [ "$1" = full ]; then gradlew clean "${same[@]}" --no-build-cache; else gradlew "${same[@]}"; fi
}

. "$(dirname "${BASH_SOURCE[0]}")/../common.sh"
