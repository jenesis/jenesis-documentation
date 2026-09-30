# Examples

Every build shown on [jenesis.build/why/tool/](https://jenesis.build/why/tool/) is a complete project here, one
folder per section and tool: `examples/<section>/<tool>/`. The page shows their files verbatim, so what it
compares is what these projects build.

```
examples/verify.sh                   # every example
examples/verify.sh caching           # the four tools of one section
examples/verify.sh supply-chain/maven
```

`verify.sh` runs the command on the first line of each project's `.verify` in that project's folder and checks
that the output holds the line below it. Several projects prove a claim rather than only building: the caching
examples edit a class and check what ran again, the supply-chain examples tamper with a checksum, a key, an
identity and a jar and expect each build to fail, and the reproducible examples build twice and compare bytes.

It needs a JDK 25 on the `PATH` and, for the examples of each tool:

- Jenesis: `build/jenesis/` in the project, linked from `JENESIS_HOME` (a checkout's `sources/build/jenesis`)
  or installed from https://get.jenesis.build, which takes the release `JENESIS_REF` names;
- Maven 3.9.16 as `mvn` (Hello, world uses its wrapper);
- nothing for Gradle: each project's wrapper downloads Gradle 9.8.0;
- Bazelisk as `bazel`, which reads each project's `.bazelversion`;
- a Docker daemon for the container images.

On a restricted network, the Bazel examples need GitHub source archives (`github.com/.../archive/...`,
`codeload.github.com`): the Maven ruleset pulls in a toolchain for the bats test runner that none of these builds
uses. Where those are blocked, pointing that repository at an empty folder in `~/.bazelrc` lets the builds pass:

```
common --override_repository=bazel_lib++toolchains+bats_toolchains=/path/to/empty
common --override_repository=aspect_bazel_lib++toolchains+bats_toolchains=/path/to/empty
```

The empty folder holds an empty `REPO.bazel` and an empty `BUILD.bazel`. Maven Central also answers a burst of
requests with HTTP 429; the Bazel examples resolve through Coursier, which asks it directly, so they may take a
retry or two.
