#!/usr/bin/env bash
set -uo pipefail
root="$(pwd -P)"
work="$(mktemp -d)"
trap 'rm -rf "$work"' EXIT
blocked=0
tamper() {
    local name="$1" edit="$2" project="$work/$1"
    mkdir -p "$project"
    cp -r "$root"/{.bazelrc,.bazelversion,MODULE.bazel,BUILD.bazel,maven_install.json,trusted-keys.asc,signatures,src} "$project/"
    (cd "$project" && eval "$edit")
    if (cd "$project" && bazel build //:app) > "$project.log" 2>&1; then
        echo "[built]   $name"
    else
        blocked=$((blocked + 1))
        echo "[blocked] $name: $(grep -m 1 -E 'Checksum was|BAD signature|No public key|none of the expected identities|error verifying bundle|ERROR' "$project.log")"
    fi
    (cd "$project" && bazel shutdown) > /dev/null 2>&1
}
tamper checksum "sed -i 's#f86e30fffd10d2b13b8caa8d4b237a7ee61f2ffccf5b1941de718b765d235bf8#086e30fffd10d2b13b8caa8d4b237a7ee61f2ffccf5b1941de718b765d235bf8#' maven_install.json"
tamper key "export GNUPGHOME=\$(mktemp -d) && gpg --batch --quiet --import trusted-keys.asc && gpg --armor --export 60200AC4AE761F1614D6C46766D68DAA073BE985 28118C070CB22A0175A2E8D43D12CA2AC19F3181 41CD49B4EF5876F9E9F691DABAC30622339994C4 300B49C14DFA7E0AD9D8515400E008229F5DAF37 > trusted-keys.asc"
tamper signature "cp signatures/jspecify-1.0.1.jar.asc signatures/picocli-4.7.7.jar.asc"
tamper identity "sed -i 's#https://github.com/sigstore/protobuf-specs/#https://github.com/sigstore/sigstore-java/#' BUILD.bazel"
echo "$blocked of 4 tampered builds failed"
