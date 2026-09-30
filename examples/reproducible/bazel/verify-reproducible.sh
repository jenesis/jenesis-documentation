#!/usr/bin/env bash
set -euo pipefail
for build in a b; do
    bazel clean
    bazel build //:app_deploy.jar --execution_log_json_file=bazel-execlog-$build.json
    sha256sum bazel-bin/app_deploy.jar
done
python3 compare_execlogs.py bazel-execlog-a.json bazel-execlog-b.json
