#!/usr/bin/env bash
set -euo pipefail
bom=build/repo/demo/app/1.0.0/app-1.0.0-cyclonedx.json
gradle --no-daemon clean cyclonedxDirectBom publish
cmp build/reports/cyclonedx-direct/bom.json "$bom"
first="$(cat "$bom")"
sleep 2
gradle --no-daemon clean cyclonedxDirectBom publish
FIRST="$first" python3 - "$bom" <<'PY'
import json, os, sys
bom, first = json.load(open(sys.argv[1])), json.loads(os.environ["FIRST"])
metadata, application = bom["metadata"], bom["metadata"]["component"]
assert metadata["manufacturer"]["name"] == "Example Org"
assert metadata["licenses"][0]["license"]["id"] == "Apache-2.0"
assert not {"description", "publisher", "copyright", "authors", "licenses"} & application.keys()
assert metadata["timestamp"] != first["metadata"]["timestamp"]
print(f"{len(bom['components'])} components; timestamps {first['metadata']['timestamp']} and {metadata['timestamp']}")
PY
echo "The SBOM is published beside the jar and differs on every build"
