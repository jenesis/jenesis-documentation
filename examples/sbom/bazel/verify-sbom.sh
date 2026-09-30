#!/usr/bin/env bash
set -euo pipefail
bazel build //:app_cyclonedx
python3 - bazel-bin/app.cdx.json <<'PY'
import json, sys
bom = json.load(open(sys.argv[1]))
components = bom["components"]
assert components and all("purl" in component for component in components)
assert not any("hashes" in component or "licenses" in component for component in components)
print(bom["metadata"].get("component"))
PY
echo "The SBOM lists its components by purl, without hashes or licences"
