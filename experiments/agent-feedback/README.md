# Agent feedback experiment

How fast and how cheaply does a coding agent fix a bug when the only build tool it has is Maven, and when it is
Jenesis? One run is one agent, one real bug of a multi-module `pom.xml` project and one build tool. The harness
measures what the agent spent - tokens, cost, wall time - and how much of that time the build tool took.

```
experiments/agent-feedback/prepare.sh maven-resolver
experiments/agent-feedback/run.sh maven-resolver maven 1
experiments/agent-feedback/run.sh maven-resolver jenesis 1
experiments/agent-feedback/report.py
```

## A task

A task is a folder under `tasks/`, made from a bug fix the project merged after the model's training data ends:

| File | Holds |
|---|---|
| `task.env` | The repository, the commit before the fix, the modules and test classes the verdict is taken on, and the selector of the Jenesis build where the project needs one |
| `issue.md` | The bug as a user reports it. The agent is given this text and nothing else about the bug |
| `hidden/` | The test files of the fix. The agent never sees them; they decide the verdict |
| `reference.patch` | The fix's change to the main sources, which `prepare.sh` checks the task with |
| `overlay-jenesis/` | Configuration the Jenesis arm needs beside the unchanged `pom.xml` files, where it needs any |
| `NOTES.md` | Where the bug comes from, and what was run to qualify it |

`prepare.sh` clones the project at the commit before the fix and deletes its history. It then builds the project
once with each tool, so that both dependency caches are warm, and checks the task: the hidden tests fail on that
commit and pass once `reference.patch` is applied.

## A run

`run.sh <task> <maven|jenesis> <attempt>` copies the prepared project and the warm caches into a folder of its
own, with a home directory of its own, and starts the agent there (`claude -p`, the model and effort of `MODEL`
and `EFFORT`, the tools Bash, Read, Edit, Write, Grep and Glob, no settings of the user's). The prompt is the
bug report, the instruction to fix it and to prove the fix with a test, and one paragraph naming the build tool.

- **Maven arm:** `mvn` is on the path. The project holds no Jenesis.
- **Jenesis arm:** the project holds the engine as `build/jenesis`, and `mvn` answers that it is not installed.
  The agent knows Maven from its training and Jenesis from nowhere, so this arm's prompt ends with the briefing
  Jenesis prints for an agent (`skill/start`). The briefing costs tokens, which this arm pays in every run;
  `prompt_bytes` in a record shows the size of both prompts.

When the agent stops, the harness copies its tree without build output, lays the hidden tests over it and runs
them with Maven - in both arms, so the verdict never depends on the tool the agent had.

## What a record holds

`results/<task>/<arm>-<attempt>.json`, beside the agent's change as a patch and the log of its build tool calls:

| Field | Meaning |
|---|---|
| `passed` | The hidden tests pass on the agent's tree |
| `wall_seconds` | From the start of the agent to its end |
| `build_seconds`, `build_invocations`, `build_failures` | Every call of `mvn`, or of `java build/jenesis/Make.java` and `Execute.java`, timed by a wrapper around the command; a call that exits with another code than 0 counts as a failure |
| `build_output_bytes` | What those calls printed, which is what an agent reads unless it filters it |
| `cost_usd`, `input_tokens`, `cache_write_tokens`, `cache_read_tokens`, `output_tokens`, `turns` | The agent's own usage report |

`report.py` prints the median of each over the attempts of a task and arm.

## What the numbers do and do not say

- **Jenesis runs with its daemon, Maven without one.** Both are each tool's default. The first Jenesis build of a
  run starts the daemon, and the harness ends it with the run. `MAVEN` can name a Maven Daemon instead.
- **The caches are warm, the network is not cut.** The agent needs it for the model, so neither tool is forced
  offline; a goal the warm-up did not resolve downloads what it needs, in either arm.
- **A run is not confined by the harness.** Each run has its own folder and home, and the Jenesis arm's `mvn`
  refuses, but an agent can still reach a tool by its absolute path. Start `run.sh` inside a container that holds
  a JDK, Maven and the agent for a confined run.
- **Agents vary.** Two attempts of one task differ more than the two tools may, so read the spread of the
  attempts beside a median, and the verdict beside the cost: a cheap run that fixed nothing is not cheap.
- **One bug is one bug.** A task shows how the tools compare on that change in that project. The share of a
  project a change invalidates decides how much an incremental build saves, and three tasks sample it thinly.
