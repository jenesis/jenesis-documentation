---
order: 8
title: Rate limiting
description: Shedding a client's excess requests with 429 before they reach the repository - the per-credential token bucket, the shared anonymous bucket, what is never limited, and the one setting that turns it on.
---

A repository that faces more than one team, or the internet, needs a ceiling: one misbehaving client - a
build tool probing thousands of coordinates, a script in a loop, a brute-force attempt on keys - must not
be able to saturate it for everyone else. Jenesis Repository meters every request against a per-credential
ceiling and sheds the excess with `429 Too Many Requests` before the request costs the repository anything.

## Turning it on

One setting names the ceiling, in requests per minute:

```bash
JENREG_RATE_LIMIT=600
```

Unset, or `0`, means no limit at all, and the server says so: an unlimited deployment raises the
`jenreg.ratelimit.unset` advisory at `GET /api/posture`, because a public instance without a throttle is a
denial-of-service and brute-force vector. A few hundred requests per minute leaves normal build traffic
untouched while stopping abuse.

## How a request is metered

Each request is charged to a **token bucket**. A bucket refills at the configured rate and holds up to one
minute's worth of burst, so a build that resolves a large dependency graph in a quick burst gets through,
while a sustained flood is shed.

- The bucket is chosen by the **credential**: the tenant named in the `Jenesis-Repository-Key` header gets a
  bucket of its own. Only the key's checksum is inspected at this point, not its grants - the filter runs
  before authentication so that a flood never costs a store lookup.
- Every request without a well-formed key shares one **`anonymous`** bucket. A shed request is counted
  against the bucket it metered, so a flood arrives already attributed.
- A request over the ceiling is answered `429` with `Retry-After: 60`.
- The Actuator endpoints are never limited, so liveness probes and metric scrapes are unaffected.

Buckets live in the process that serves the request. Behind a load balancer each node keeps its own, so the
effective ceiling across a fleet is the setting times the number of nodes; a front door that pins a client
to one node keeps the number exact.

The limiter is a discovered module (`token-bucket`). Switching it off with `jenreg.token-bucket=false`, or
running without the module, leaves every request unmetered.

## Settings

| Key | Default | Effect |
|---|---|---|
| `jenreg.rate-limit` | *(unset - no limit)* | Requests per minute per credential; excess is shed with `429` and `Retry-After: 60`. Unset raises the `jenreg.ratelimit.unset` advisory. |
| `jenreg.token-bucket` | `true` | Switch the limiter module off with `false`. |
