#!/usr/bin/env python3
"""Folds one run into a JSON record: the verdict, the agent's own usage report and the build tool log."""
import json
import os
import sys

task, arm, attempt, passed, started, ended, run, model, effort = sys.argv[1:]
try:
    with open(os.path.join(run, "agent.json")) as file:
        agent = json.load(file)
except (OSError, ValueError):
    agent = {}
# An agent that runs a build in the background ends several times, and "usage" and "num_turns" then cover the last
# stretch alone; "modelUsage" and the cost cover the run.
models = agent.get("modelUsage", {}).values()
usage = {key: sum(model.get(key, 0) for model in models) for key in (
    "inputTokens",
    "cacheCreationInputTokens",
    "cacheReadInputTokens",
    "outputTokens")} if models else {}
invocations = []
with open(os.path.join(run, "buildtool.tsv")) as file:
    for line in file:
        kind, at, seconds, code, written, arguments = line.rstrip("\n").split("\t", 5)
        invocations.append({"seconds": float(seconds), "exit": int(code), "bytes": int(written), "arguments": arguments})
json.dump({
    "task": task,
    "arm": arm,
    "attempt": int(attempt),
    "model": model,
    "effort": effort,
    "instructions": os.environ.get("INSTRUCTIONS", "3"),
    "engine": os.environ.get("ENGINE", ""),
    "passed": passed == "true",
    "agent_ended": agent.get("subtype", "no result"),
    "wall_seconds": round(float(ended) - float(started), 1),
    "build_seconds": round(sum(i["seconds"] for i in invocations), 1),
    "build_invocations": len(invocations),
    "build_failures": sum(1 for i in invocations if i["exit"] != 0),
    "build_output_bytes": sum(i["bytes"] for i in invocations),
    "turns": agent.get("num_turns") if agent.get("result_index", 0) == 0 else None,
    "agent_results": agent.get("result_index", 0) + 1,
    "cost_usd": agent.get("total_cost_usd"),
    "input_tokens": usage.get("inputTokens"),
    "cache_write_tokens": usage.get("cacheCreationInputTokens"),
    "cache_read_tokens": usage.get("cacheReadInputTokens"),
    "output_tokens": usage.get("outputTokens"),
    "prompt_bytes": os.path.getsize(os.path.join(run, "prompt.md")),
    "agents_bytes": os.path.getsize(os.path.join(run, "project", "AGENTS.md")),
}, sys.stdout, indent=2)
print()
