#!/usr/bin/env bash
set -uo pipefail
root="$(pwd -P)"
work="$root/target/tampering"
rm -rf "$work"
blocked=0
project() {
    mkdir -p "$work/$1/build"
    cp -r "$root/sources" "$root/jenesis.properties" "$work/$1/"
    ln -s "$(cd "$root/build/jenesis" && pwd -P)" "$work/$1/build/jenesis"
}
tamper() {
    local name="$1" edit="$2"
    shift 2
    project "$name"
    sed -i "$edit" "$work/$name/sources/module-info.java"
    if (cd "$work/$name" && java "-Djenesis.openpgp.local=$root/.jenesis/keys" "$@" build/jenesis/Make.java) > "$work/$name.log" 2>&1; then
        echo "[built]   $name"
    else
        blocked=$((blocked + 1))
        echo "[blocked] $name: $(grep 'Caused by' "$work/$name.log" | tail -n 1 | sed 's/^Caused by: //')"
        grep -A 1 'Unverified dependency signatures' "$work/$name.log" | tail -n 1
    fi
}
tamper checksum 's#SHA-256/f86e30fffd10d2b1#SHA-256/086e30fffd10d2b1#g'
tamper key 's#OpenPGP/AA417737BD805456DB3CBDDE6601E5C08DCCBB96 info.picocli#OpenPGP/28118C070CB22A0175A2E8D43D12CA2AC19F3181 info.picocli#'
tamper identity 's#Sigstore/github.com/sigstore/protobuf-specs#Sigstore/github.com/sigstore/sigstore-java#'
project mirror
mkdir -p "$work/repository" "$work/downloads"
(cd "$work/mirror" && java "-Djenesis.maven.local=$work/repository" "-Djenesis.openpgp.local=$root/.jenesis/keys" build/jenesis/Make.java) > "$work/mirror.log" 2>&1
jar="$work/repository/info/picocli/picocli/4.7.7/picocli-4.7.7.jar"
printf 'tampered' >> "$jar"
sha512sum "$jar" | cut -d ' ' -f 1 | tr -d '\n' > "$jar.sha512"
tamper jar '' "-Djenesis.maven.uri=file://$work/repository" "-Djenesis.maven.local=$work/downloads"
echo "$blocked of 4 tampered builds failed"
