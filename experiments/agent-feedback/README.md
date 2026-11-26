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
| `prepare.sh` | Changes to the project that both arms get, for a fault of the project that no setting of Jenesis covers |
| `overlay-jenesis/` | Settings of Jenesis for what the poms configure on a Maven plugin, such as the tests surefire leaves out or the folder they run in, where the project needs any |
| `NOTES.md` | Where the bug comes from, and what was run to qualify it |

`prepare.sh` clones the project at the commit before the fix and deletes its history. It then builds the project
once with each tool, so that both dependency caches are warm, and checks the task: the hidden tests fail on that
commit and pass once `reference.patch` is applied.

## A run

`run.sh <task> <maven|jenesis> <attempt>` copies the prepared project and the warm caches into a folder of its
own, with a home directory of its own, and starts the agent there (`claude -p`, the model and effort of `MODEL`
and `EFFORT`, the tools Bash, Read, Edit, Write, Grep and Glob, no settings of the user's). The prompt is the
bug report, the instruction to fix it and to prove the fix with a test, and the rule for stopping: every test of
every module the change reaches has run once and passed. It is the same in both arms, so both verify alike.

What differs is the tool, and the `AGENTS.md` the harness writes into the project root to name it. A project's
own instructions for agents are removed in preparation, as they would advise one arm only.

- **Maven arm:** `mvn` is on the path, `lib/agents-maven.md` is the project's `AGENTS.md`, and the project holds
  no Jenesis.
- **Jenesis arm:** the project holds the engine as `build/jenesis`, `mvn` answers that it is not installed, and
  `lib/agents-jenesis.md` is the project's `AGENTS.md`: it names the tool and the command that prints its briefing
  for an agent (`skill/start`). The model knows Maven from its training and Jenesis from nowhere, so that briefing
  is also appended to this arm's prompt, where the agent has it before the clock starts.

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

## The runs so far

Three tasks, five attempts per tool, `claude-opus-5-5` at medium effort, one run at a time on a four-core Linux
machine without a container. The Jenesis arm vendored the engine of jenesis/jenesis at commit `0339407`. Each cell
is the median over the five attempts; `results/` holds every record.

| Task | Tool | Passed | Wall s | Build s | Builds | Build output kB | Turns | Cost $ | Output tokens |
|---|---|---|---|---|---|---|---|---|---|
| httpcore | jenesis | 5/5 | 97 | 28 | 2 | 27 | 12 | 0.53 | 7813 |
| httpcore | maven | 5/5 | 93 | 26 | 2 | 12 | 13 | 0.50 | 7165 |
| jgrapht | jenesis | 5/5 | 62 | 19 | 1 | 23 | 7 | 0.34 | 4771 |
| jgrapht | maven | 5/5 | 66 | 14 | 1 | 2 | 7 | 0.36 | 4989 |
| maven-resolver | jenesis | 5/5 | 128 | 53 | 3 | 156 | 18 | 0.67 | 7935 |
| maven-resolver | maven | 4/5 | 130 | 60 | 5 | 184 | 15 | 0.64 | 8592 |

- The tools are level on all three tasks: no median differs by more than the attempts of one arm differ among
  themselves.
- One Maven attempt on maven-resolver did not pass the hidden tests; every other attempt did.
- The three bugs each have their cause and their tests in one module, and an agent fixed each in one to four
  minutes with one to five builds. A build of one module with a test filter takes either tool ten to thirty
  seconds here, so there is little for an incremental build to save.
- `pilot/httpcore` holds ten earlier runs of one task, made before the briefing of the Jenesis arm showed how to
  build one module and run one test class. There the Jenesis arm took a median of 142 seconds, 60 of them in the
  build tool, against 97 and 28 afterwards.

## What the agents ask Maven for

`calls.py maven` and `calls.py jenesis` summarise every recorded call of an arm's build tool. Over the 26 Maven
runs recorded so far, 86 calls, two per run at the median:

| Asked for | Share of calls |
|---|---|
| `test` as the goal | 91% |
| `-pl <modules>`, with `-am` in a third of all calls | 78% |
| `-Dtest=<classes>`, mostly with `-Dsurefire.failIfNoSpecifiedTests=false` | 72% |
| `-q` | 55% |
| a check switched off (`-Drat.skip`, `-Dcheckstyle.skip`) | about one call in eight |

- A run is usually one call that names a few test classes of one or a few modules, repeated until it passes, and
  then one call without `-Dtest` over the modules the change touched. Two calls in 86 ran the whole project.
- A call with `-q` printed 2 kB at the median, one without it 42 kB. The agents whose transcripts were read then
  cut the output further with `grep -E "Tests run:|FAIL|ERROR"` and `tail`, down to some thirty characters where
  the build passed.
- Every call carried `-o`. The prompts and the `AGENTS.md` of these runs said that the dependencies were already
  downloaded, and those of the second round named the flag, so this share is no evidence of what an agent does
  unprompted. The Maven arm's `AGENTS.md` names the tool and nothing else, so that the arm relies on what the
  model knows from its training.
