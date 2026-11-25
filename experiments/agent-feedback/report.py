#!/usr/bin/env python3
"""report.py [results]: one line per task and arm with the medians over its attempts, as a Markdown table."""
import glob
import json
import os
import statistics
import sys

results = sys.argv[1] if len(sys.argv) > 1 else os.path.join(os.path.dirname(os.path.abspath(__file__)), "results")
runs = {}
for path in sorted(glob.glob(os.path.join(results, "*", "*.json"))):
    with open(path) as file:
        record = json.load(file)
    runs.setdefault((record["task"], record["arm"]), []).append(record)


def median(records, key):
    values = [record[key] for record in records if record.get(key) is not None]
    return statistics.median(values) if values else float("nan")


print("| Task | Tool | Passed | Wall s | Build s | Builds | Build output kB | Turns | Cost $ | Output tokens |")
print("|---|---|---|---|---|---|---|---|---|---|")
for (task, arm), records in sorted(runs.items()):
    print("| %s | %s | %d/%d | %.0f | %.0f | %.0f | %.0f | %.0f | %.2f | %.0f |" % (
        task, arm, sum(1 for record in records if record["passed"]), len(records),
        median(records, "wall_seconds"), median(records, "build_seconds"), median(records, "build_invocations"),
        median(records, "build_output_bytes") / 1000, median(records, "turns"), median(records, "cost_usd"),
        median(records, "output_tokens")))
