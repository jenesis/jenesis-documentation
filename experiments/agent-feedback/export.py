#!/usr/bin/env python3
"""Writes every recorded run as runs.csv and every build tool call as calls.csv, into the folder given."""
import csv, glob, json, os, sys

RUN = ["task", "tool", "variant", "attempt", "model", "effort", "engine", "passed", "agent_ended", "wall_seconds",
       "build_seconds", "build_invocations", "build_failures", "build_output_bytes", "turns", "cost_usd",
       "input_tokens", "cache_write_tokens", "cache_read_tokens", "output_tokens", "prompt_bytes", "agents_bytes"]
here = os.path.dirname(os.path.abspath(__file__))
out = sys.argv[1] if len(sys.argv) > 1 else "."
records = sorted(glob.glob(os.path.join(here, "results", "*", "*.json")))
with open(os.path.join(out, "runs.csv"), "w", newline="") as runs, \
        open(os.path.join(out, "calls.csv"), "w", newline="") as calls:
    run, call = csv.writer(runs), csv.writer(calls)
    run.writerow(RUN)
    call.writerow(["task", "tool", "variant", "attempt", "call", "seconds", "exit_code", "output_bytes", "arguments"])
    for record in records:
        value = json.load(open(record))
        tool, _, variant = value["arm"].partition("+")
        value.update(tool=tool, variant=variant or "baseline")
        run.writerow([value.get(key, "") for key in RUN])
        lines = record[:-len(".json")] + ".buildtool.tsv"
        if os.path.exists(lines):
            for index, line in enumerate(open(lines), 1):
                field = line.rstrip("\n").split("\t", 5)
                call.writerow([value["task"], tool, value["variant"], value["attempt"], index, field[2], field[3],
                               field[4], field[5] if len(field) > 5 else ""])
