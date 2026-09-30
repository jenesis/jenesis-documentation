#!/usr/bin/env bash
set -uo pipefail
root="$(pwd -P)"
work="$root/target/tampering"
rm -rf "$work"
local_repository="$HOME/.m2/repository"
blocked=0
tamper() {
    local name="$1" file="$2" edit="$3" project="$work/$1"
    shift 3
    mkdir -p "$project"
    cp -r "$root/pom.xml" "$root/sigmund.yaml" "$root/.mvn" "$root/src" "$project/"
    mkdir -m 700 "$project/.gnupg"
    cp "$root/.gnupg/pubring.kbx" "$project/.gnupg/"
    [ -n "$file" ] && sed -i "$edit" "$project/$file"
    if (cd "$project" && mvn -B package "$@") > "$project.log" 2>&1; then
        echo "[built]   $name"
    else
        blocked=$((blocked + 1))
        echo "[blocked] $name: $(grep -m 1 -E '^\[ERROR\] .*(mismatch|Signer:)' "$project.log" | sed 's/^\[ERROR\] *//')"
    fi
}
tamper checksum .mvn/checksums/checksums.sha256 's#^f86e30fffd10d2b1#086e30fffd10d2b1#'
tamper key sigmund.yaml 's#AA417737BD805456DB3CBDDE6601E5C08DCCBB96#28118C070CB22A0175A2E8D43D12CA2AC19F3181#'
tamper identity sigmund.yaml 's#https://github.com/sigstore/protobuf-specs#https://github.com/sigstore/sigstore-java#'
head="$work/repository/info/picocli/picocli/4.7.7"
mkdir -p "$head"
cp "$local_repository"/info/picocli/picocli/4.7.7/picocli-4.7.7.{jar,pom} "$head/"
printf 'tampered' >> "$head/picocli-4.7.7.jar"
tamper jar '' '' "-Dmaven.repo.local=$work/repository" "-Dmaven.repo.local.tail=$local_repository"
echo "$blocked of 4 tampered builds failed"
