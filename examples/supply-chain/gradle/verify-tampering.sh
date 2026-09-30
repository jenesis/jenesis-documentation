#!/usr/bin/env bash
set -uo pipefail
root="$(pwd -P)"
work="$root/build/tampering"
rm -rf "$work"
blocked=0
tamper() {
    local name="$1" file="$2" edit="$3" project="$work/$1"
    mkdir -p "$project"
    cp -r "$root/build.gradle.kts" "$root/settings.gradle.kts" "$root/gradle" "$root/src" "$project/"
    sed -i "$edit" "$project/$file"
    if (cd "$project" && gradle --no-daemon build) > "$project.log" 2>&1; then
        echo "[built]   $name"
    else
        blocked=$((blocked + 1))
        echo "[blocked] $name: $(grep -m 1 -E 'Dependency verification failed|signed with key|expected a|KeylessVerificationException|Certificate' "$project.log" | sed 's/^ *//')"
    fi
}
tamper checksum gradle/verification-metadata.xml 's#7e1446499b359675d8aabe6af2de86b85e72ae8a2a932c0b40d0e5ba57097439#0e1446499b359675d8aabe6af2de86b85e72ae8a2a932c0b40d0e5ba57097439#'
tamper key gradle/verification-metadata.xml 's#AA417737BD805456DB3CBDDE6601E5C08DCCBB96" group="info.picocli"#28118C070CB22A0175A2E8D43D12CA2AC19F3181" group="info.picocli"#'
tamper identity build.gradle.kts 's#https://github.com/sigstore/protobuf-specs/#https://github.com/sigstore/sigstore-java/#'
repository="$work/repository/info/picocli/picocli/4.7.7"
mkdir -p "$repository"
cache="${GRADLE_USER_HOME:-$HOME/.gradle}/caches/modules-2/files-2.1/info.picocli/picocli/4.7.7"
cp "$cache"/*/picocli-4.7.7.{pom,pom.asc,jar,jar.asc} "$repository/"
printf 'tampered' >> "$repository/picocli-4.7.7.jar"
tamper jar build.gradle.kts "s#^    mavenCentral()\$#    maven { url = uri(\"file://$work/repository\") }\n    mavenCentral()#"
echo "$blocked of 4 tampered builds failed"
