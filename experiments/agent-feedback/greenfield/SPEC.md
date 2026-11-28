# Kestle & Wendle Navigation - Passage Tolls and Delay Rebates Service

You are to build the back-office service of the Kestle & Wendle Navigation, a canal authority. Barge and boat
operators register with the Navigation, declare their passages through its locks, pay a toll computed from the
rules below, and lodge claims for a rebate when a lock held them up. Clerks assess, approve and settle those
claims.

The service is an HTTP server speaking JSON. Everything is held in memory; nothing survives a restart. Every rule
is numbered (`R4.6`); the acceptance tests name the rule they check. Where this document gives a worked example,
the example is normative.

---

## 0. Delivery

- **R0.1** The project root holds two executable scripts. `./build` prepares everything the service needs
  (dependencies, compilation) and exits 0 on success. `PORT=<n> ./run` starts the service in the foreground,
  listening on `127.0.0.1:<n>` (listening on all interfaces is also acceptable), and runs until it receives
  `SIGTERM` or `SIGINT`. `./run` must not compile or download anything.
- **R0.2** The service makes no outbound network connection and needs no database or other server. All state is
  held in memory and is lost when the process ends.
- **R0.3** The service supports HTTP/1.1 persistent connections and serves concurrent requests. Requests must
  behave as if they were processed one at a time in some order (each request sees the complete effect of every
  request that finished before it started).
- **R0.4** Request bodies of up to 8 MiB are accepted.

## 1. General conventions

- **R1.1** Request and response bodies are UTF-8 JSON (`Content-Type: application/json`), except the body of
  `POST /passages/import` (§9) and responses with status 204, which have no body.
- **R1.2** Every error response has this body, and the status code the rule names:
  ```json
  {"error": {"code": "FIELD_FORMAT", "field": "lengthDm", "message": "free text"}}
  ```
  `field` names the offending field, header or query parameter where a rule says so, and is `null` otherwise.
  `message` is free text and is never checked.
- **R1.3** A request whose method and path match no endpoint of this document is answered `404` with code
  `ROUTE_NOT_FOUND` and `field` `null`. Path matching is exact and case-sensitive; a trailing slash does not match.
- **R1.4** A body that is not valid JSON, or valid JSON whose top-level value is not an object, where the endpoint
  expects an object, is answered `400` `MALFORMED_JSON`, `field` `null`. An empty body counts as invalid JSON.
- **R1.5** Field validation. Each request table below lists its fields in order. Fields are checked in that order
  and only the first failure is reported, with `field` set to the field's name and status `400`:
  - `FIELD_REQUIRED` - the field is absent or `null`;
  - `FIELD_TYPE` - the JSON type is wrong. *string* means a JSON string. *integer* means a JSON number written
    without a decimal point or exponent (`120` is an integer; `120.5`, `"120"` and `true` are not). *array of X*
    means a JSON array whose every element is X;
  - `FIELD_FORMAT` - the type is right but the value breaks the stated pattern, range, length or set of values.

  A field marked *optional* may be absent or `null`, which mean the same; if present it is checked as above.
- **R1.6** Fields not named in a table are ignored. Field names are case-sensitive.
- **R1.7** Only once every field has passed R1.5 are the semantic rules of the endpoint checked, in the order the
  endpoint lists them; again only the first failure is reported.
- **R1.8** Timestamps, in requests and responses, are written `YYYY-MM-DDTHH:MM:SSZ`: UTC, the literal `Z`,
  whole seconds, no fraction, no offset. A timestamp field holding any other string, or an impossible date or time
  (`2026-02-30T10:00:00Z`, `2026-03-01T24:00:00Z`), fails with `FIELD_FORMAT`.
- **R1.9** Money is written as a JSON string with exactly two decimals (`"24.48"`). Intermediate amounts that this
  document says are "4-place" are written as JSON strings with exactly four decimals (`"8.0650"`). Amounts are
  never written as JSON numbers.
- **R1.10** Two rounding modes are used, always on exact decimal values, never on binary floating point:
  - *half-even to 4 places* (`R4`): to the nearest 0.0001; an exact half goes to the even last digit
    (`8.83485` → `8.8348`, `9.27475` → `9.2748`);
  - *half-up to 2 places* (`U2`): to the nearest 0.01; an exact half goes away from zero (`24.465` → `24.47`).
- **R1.11** A response object carries exactly the fields this document shows for it, no more and no fewer; a field
  shown as `null` is present with the value `null`. Response field order is not significant. Arrays are significant in order wherever this document
  defines an order.

## 2. Clock and reset

The service never reads the machine's clock. It keeps a *service clock* that only changes when set.

- **R2.1** At start-up, and after a reset, the service clock reads `2026-01-01T00:00:00Z`.
- **R2.2** `PUT /admin/clock` with body `{"now": "<timestamp>"}` sets the clock and answers `200` with
  `{"now": "<timestamp>"}`. `now` is required, a string, a timestamp (R1.8). The clock may be moved backwards.
- **R2.3** `GET /admin/clock` answers `200` with `{"now": "<current service clock>"}`.
- **R2.4** Every "now" in this document - `registeredAt`, `recordedAt`, `lodgedAt`, the time of an audit entry,
  every window and expiry - is the service clock at the moment the request is processed.
- **R2.5** `POST /admin/reset` (any body is ignored) discards every operator, passage, claim, audit entry and
  stored idempotency key, restarts every identifier sequence at 1, resets the clock (R2.1) and answers `204`.

## 3. Operators

`POST /operators` registers an operator.

| Field | Type | Rule |
|---|---|---|
| `code` | string | Pattern: two capital letters `A`-`Z`, a hyphen, three digits (`KV-209`). |
| `name` | string | After removing leading and trailing spaces, 1 to 60 characters. |
| `tier` | string | One of `ordinary`, `contract`, `heritage`. |

- **R3.1** The last digit of `code` is a check digit. With the letters valued `A`=1 … `Z`=26, the first letter
  `L1`, the second `L2` and the first two digits `d1`, `d2`, the check digit is
  `(3×L1 + L2 + 7×d1 + d2) mod 10`. A code matching the pattern whose check digit is wrong fails with `400`
  `CHECK_DIGIT`, field `code`. This check belongs to the field check of `code` (it is reported before `name` is
  examined).
  *Example:* `KV-209`: K=11, V=22 → 33 + 22 + 14 + 0 = 69 → check digit 9, valid. `KV-205` fails. Other valid
  codes: `AB-102`, `MX-445`, `QD-737`.
- **R3.2** Semantic rule: a code already registered fails with `409` `DUPLICATE_OPERATOR`, field `code`.
- **R3.3** Success answers `201` with the operator:
  ```json
  {"code": "KV-209", "name": "Kestle Haulage", "tier": "ordinary", "registeredAt": "2026-03-20T12:00:00Z"}
  ```
  `name` is stored and returned trimmed.
- **R3.4** `GET /operators/{code}` answers `200` with the operator, or `404` `NOT_FOUND` (`field` `null`).

## 4. The network and the tariff

### 4.1 Locks

The Navigation has nine locks. The Kestle line runs `K1`-`K2`-`K3`-`K4`-`K5`-`K6`; the Wendle arm leaves the line
at `K3` and runs `W1`-`W2`-`W3`.

| Code | Name | Chamber | Lift (m) |
|---|---|---|---|
| `K1` | Ashby Fold | broad | 1.85 |
| `K2` | Brindle | broad | 2.40 |
| `K3` | Coldharbour | broad | 0.95 |
| `K4` | Drovers' Staircase | broad | 3.10 |
| `K5` | Eckford | broad | 2.05 |
| `K6` | Fallowmere | broad | 1.20 |
| `W1` | Wendle Junction | narrow | 1.65 |
| `W2` | Wendle Mill | narrow | 2.75 |
| `W3` | Wendle Head | narrow | 0.80 |

- **R4.1** Adjacent pairs (in either direction) are exactly: K1-K2, K2-K3, K3-K4, K4-K5, K5-K6, K3-W1, W1-W2,
  W2-W3. The order of the table above is the *table order* used for tie-breaks.

### 4.2 A passage specification

A passage specification describes one trip. Its fields, validated per R1.5:

| Field | Type | Rule |
|---|---|---|
| `vesselClass` | string | One of `NB` (narrowboat), `WB` (wide-beam), `DB` (dumb barge), `TS` (tug and string). |
| `lengthDm` | integer | Length in decimetres, 40 to 450 inclusive. |
| `ladenTonnes` | string | Pattern `^[0-9]{1,3}(\.[0-9]{1,2})?$`, value at most 400. |
| `cargo` | string | One of `NONE`, `GEN`, `AGG`, `LIV`, `HAZ-A`, `HAZ-B`. |
| `locks` | array of string | 1 to 12 elements, each one of the nine lock codes. |
| `enteredAt` | string | A timestamp (R1.8): when the vessel entered the first lock. |

- **R4.2** Route rules, checked as semantic rules in this order:
  1. `LOCK_SEQUENCE_INVALID` (`422`, field `locks`): two consecutive elements of `locks` are not an adjacent pair
     (a lock is not adjacent to itself), or any lock occurs more than twice.
  2. `GAUGE_EXCEEDED` (`422`, field `locks`): the route contains a narrow lock and either `vesselClass` is not
     `NB` or `lengthDm` is greater than 220.
  3. `HAZARD_ROUTE` (`422`, field `locks`): `cargo` is `HAZ-A` and the route contains a lock whose lift exceeds
     3.00 m.
  4. `CARGO_MISMATCH` (`422`, field `cargo`): `cargo` is `NONE` and `ladenTonnes` is not zero, or `cargo` is not
     `NONE` and `ladenTonnes` is zero.

### 4.3 The toll

The toll of a passage depends on its specification and on a *tier* (§3). Let `n` be the number of elements of
`locks` (repeats included) and `t` the value of `ladenTonnes`.

- **R4.3** *Lock fee.* For the element at each position of `locks`, in order:
  `fee = R4((base + lift × liftRate) × lengthFactor × repeatFactor)` where
  - `base` is 6.40 for a broad chamber, 4.15 for a narrow one;
  - `liftRate` per metre: `NB` 0.90, `WB` 1.35, `DB` 1.60, `TS` 2.10;
  - `lengthFactor`: 1.00 for `lengthDm` ≤ 210, 1.15 for 211 to 300, 1.32 for 301 to 450;
  - `repeatFactor` is 0.50 for the second occurrence of a lock in `locks` and 1.00 otherwise.
- **R4.4** `lockFeeTotal = Σ fee`.
- **R4.5** *Weight charge.* `weightCharge = R4(max(0, t − 30) × 0.0725 × n)`.
- **R4.6** *Cargo surcharge.* `cargoSurcharge = R4((lockFeeTotal + weightCharge) × p)` with `p`: `NONE` 0,
  `GEN` 0.025, `AGG` 0.04, `LIV` 0.075, `HAZ-B` 0.13, `HAZ-A` 0.22. Let
  `P1 = lockFeeTotal + weightCharge + cargoSurcharge`.
- **R4.7** *Band surcharge*, from `enteredAt` read in UTC. The passage is *night* if the hour is 22, 23, or 0 to
  5 inclusive, and *weekend* if the date is a Saturday or a Sunday. The band rate `b` is 0 for neither, 0.18 for
  night only, 0.06 for weekend only, and 0.2508 for both. `bandSurcharge = R4(P1 × b)`.
  Let `P2 = P1 + bandSurcharge`.
- **R4.8** *Tier discount.* `tierDiscount = R4(P2 × d)` with `d`: `ordinary` 0; `contract` 0.09; `heritage`
  0.40 if `vesselClass` is `NB`, otherwise 0. Let `P3 = P2 − tierDiscount`.
- **R4.9** *Total.* `total = U2(P3)`; if that is less than 7.50, `total` is 7.50 and `minimumApplied` is `true`,
  otherwise `minimumApplied` is `false`.
- **R4.10** The toll is written as:
  ```json
  {
    "lockFees": [{"lock": "K1", "fee": "8.0650"}, {"lock": "K2", "fee": "8.5600"}, {"lock": "K3", "fee": "7.2550"}],
    "lockFeeTotal": "23.8800",
    "weightCharge": "0.0000",
    "cargoSurcharge": "0.5970",
    "bandSurcharge": "0.0000",
    "tierDiscount": "0.0000",
    "total": "24.48",
    "minimumApplied": false
  }
  ```
  `lockFees` has one element per element of `locks`, in the same order. All but `total` are 4-place amounts.

*Worked example 1* (the toll above): `NB`, `lengthDm` 180, `ladenTonnes` `"12.00"`, `GEN`, locks `K1`,`K2`,`K3`,
entered Tuesday `2026-03-17T10:00:00Z`, tier `ordinary`. K1: 6.40 + 1.85×0.90 = 8.065 → 8.0650; K2: 6.40 + 2.16 =
8.5600; K3: 6.40 + 0.855 = 7.2550; total 23.8800; no weight charge; cargo 23.88 × 0.025 = 0.5970; P1 = 24.4770; no
band, no discount; U2 → 24.48.

*Worked example 2:* `WB`, `lengthDm` 250, `ladenTonnes` `"47.35"`, `HAZ-B`, locks `K2`,`K3`,`K2`, entered Saturday
`2026-03-14T23:30:00Z`, tier `contract`.
- K2: (6.40 + 2.40×1.35) × 1.15 = 9.64 × 1.15 = 11.086 → 11.0860
- K3: (6.40 + 0.95×1.35) × 1.15 = 7.6825 × 1.15 = 8.834875 → 8.8349
- K2 again: 9.64 × 1.15 × 0.50 = 5.543 → 5.5430
- lockFeeTotal 25.4639; weightCharge = R4(17.35 × 0.0725 × 3) = R4(3.773625) = 3.7736
- cargoSurcharge = R4(29.2375 × 0.13) = R4(3.800875) = 3.8009; P1 = 33.0384
- night and weekend: bandSurcharge = R4(33.0384 × 0.2508) = R4(8.28603072) = 8.2860; P2 = 41.3244
- tierDiscount = R4(41.3244 × 0.09) = R4(3.719196) = 3.7192; P3 = 37.6052; total `"37.61"`.

*Worked example 3* (half-even matters): `NB`, `lengthDm` 220, `ladenTonnes` `"0"`, `NONE`, locks `W1`, entered
`2026-03-17T10:00:00Z`, tier `ordinary`. W1: (4.15 + 1.65×0.90) × 1.15 = 5.635 × 1.15 = 6.48025 → `6.4802` (not
6.4803). Total U2(6.4802) = 6.48, below 7.50, so `total` is `"7.50"` and `minimumApplied` is `true`.

## 5. Quotes

`POST /tariff/quotes` prices many specifications at once and stores nothing.

Request: `{"items": [ ... ]}`. `items` is required and must be an array (R1.5, field `items`); otherwise any
element type is allowed and is judged per item.

- **R5.1** More than 5000 elements in `items` fails with `413` `BATCH_TOO_LARGE`, field `items`. An empty array
  is valid.
- **R5.2** Each item is a passage specification (§4.2) preceded by two further fields, validated in this order:
  `ref` (string, 1 to 40 characters), `tier` (string, one of the three tiers), then the six fields of §4.2. Then
  the route rules R4.2. The clock is not consulted: a quote may be for any time.
- **R5.3** An item that is not a JSON object fails with `FIELD_TYPE`, field `null`.
- **R5.4** The answer is `200`:
  ```json
  {
    "count": 3, "quoted": 2, "failed": 1, "grandTotal": "61.98",
    "results": [
      {"ref": "a", "toll": { ... }},
      {"ref": "b", "error": {"code": "GAUGE_EXCEEDED", "field": "locks"}},
      {"ref": "c", "toll": { ... }}
    ]
  }
  ```
  `results` has one element per item, in input order. A priced item carries `ref` and `toll` (R4.10); a failed one
  carries `ref` and `error` with the code and field the first failing rule names. `ref` in a failed result is the
  item's `ref` if that is a string of 1 to 40 characters, and `null` otherwise. `grandTotal` is the sum of the
  `total` of every priced item (`"0.00"` when none). `count` = `quoted` + `failed`.
- **R5.5** One item's failure never affects another item. `ref` values need not be unique.

## 6. Passages

`POST /passages` records a passage.

| Field | Type | Rule |
|---|---|---|
| `operator` | string | Operator code pattern of §3 (the check digit is not examined here). |
| `vesselMark` | string | Pattern `^[A-Z0-9]{3,10}$`. |
| (the six fields of §4.2, in their order) | | |

- **R6.1** Semantic rules, in order:
  1. `UNKNOWN_OPERATOR` (`422`, field `operator`): no operator has this code.
  2. The route rules R4.2, in their order.
  3. `TIME_IN_FUTURE` (`422`, field `enteredAt`): `enteredAt` is later than the clock.
  4. `STALE_DECLARATION` (`422`, field `enteredAt`): `enteredAt` is earlier than the clock minus 30 days
     (exactly 30 days before the clock is accepted).
  5. `DUPLICATE_PASSAGE` (`409`, field `vesselMark`): a recorded passage has the same `vesselMark` and the same
     `enteredAt`.
- **R6.2** The toll is computed with the operator's tier at the moment of recording, and never recomputed.
- **R6.3** Identifiers are `PSG-` followed by a six-digit, zero-padded sequence number starting at `PSG-000001`,
  allocated only to passages actually recorded (a rejected request consumes no number).
- **R6.4** Success answers `201` with the passage:
  ```json
  {
    "id": "PSG-000001", "operator": "KV-209", "tier": "ordinary", "vesselMark": "BELLA7",
    "vesselClass": "NB", "lengthDm": 180, "ladenTonnes": "12.00", "cargo": "GEN",
    "locks": ["K1", "K2", "K3"], "enteredAt": "2026-03-17T10:00:00Z", "recordedAt": "2026-03-20T12:00:00Z",
    "toll": { ... R4.10 ... }
  }
  ```
  `ladenTonnes` is returned with exactly two decimals (`"7"` → `"7.00"`, `"7.5"` → `"7.50"`).
- **R6.5** `GET /passages/{id}` answers `200` with the passage, or `404` `NOT_FOUND`.
- **R6.6** `POST /passages` supports idempotency keys (§7).

## 7. Idempotency keys

`POST /passages` and `POST /claims` accept an optional `Idempotency-Key` header.

- **R7.1** The key is 8 to 64 characters from `A`-`Z`, `a`-`z`, `0`-`9` and `-`. Any other value fails with `400`
  `FIELD_FORMAT`, field `Idempotency-Key`. This is checked before the body is parsed.
- **R7.2** Keys are scoped by endpoint: the same key on `/passages` and on `/claims` are unrelated.
- **R7.3** After the body has been parsed (R1.4 still applies first), if a stored, unexpired entry exists for the
  endpoint and key:
  - if the request body is *structurally equal* to the stored one (same JSON value: objects compare by key set
    and values regardless of key order, arrays element-wise, strings and numbers by value), the stored response is
    returned again - same status, same body - with the header `Idempotent-Replay: true`, and nothing else happens
    (no new resource, no audit entry, no sequence number consumed, no validation, the clock is not compared);
  - otherwise the request fails with `409` `IDEMPOTENCY_CONFLICT`, field `Idempotency-Key`.
- **R7.4** An entry is stored only when the request succeeds (`201`); a request that fails leaves no entry, so the
  key may then be used again with any body.
- **R7.5** An entry expires 24 hours after it was stored (by the clock): from that instant on the key behaves as
  never seen, and a new success with it stores a new entry.
- **R7.6** A response produced without replay never carries `Idempotent-Replay`.

## 8. Listing passages

`GET /passages` lists recorded passages.

| Parameter | Rule |
|---|---|
| `operator` | Exact operator code. |
| `vesselClass` | One of the four classes. |
| `cargo` | One of the six cargo codes. |
| `from` | Timestamp; only passages with `enteredAt` ≥ `from`. |
| `to` | Timestamp; only passages with `enteredAt` < `to`. |
| `minTotal` | Pattern `^[0-9]+(\.[0-9]{1,2})?$`; only passages whose toll `total` ≥ `minTotal`. |
| `offset` | Decimal digits only, default 0. |
| `limit` | Decimal digits only, 1 to 200, default 50. |

- **R8.1** A parameter given with a value that breaks its rule - including an empty value - fails with `400`
  `INVALID_QUERY`, field the parameter name. Parameters are checked in the table's order. When both `from` and
  `to` are given and `from` is not earlier than `to`, the request fails with `INVALID_QUERY`, field `to`.
  Unknown parameters are ignored. If a parameter is repeated, its first occurrence is used.
- **R8.2** All given filters apply together.
- **R8.3** The matching passages are ordered by `enteredAt` **descending**, and passages with equal `enteredAt` by
  `id` **ascending**.
- **R8.4** The answer is `200`:
  ```json
  {"items": [ ...passages as R6.4... ], "total": 137, "offset": 50, "limit": 50, "nextOffset": 100}
  ```
  `total` is the number of matching passages, `items` those at positions `offset` to `offset + limit − 1` of the
  ordered matches, and `nextOffset` is `offset + limit` when that is less than `total`, and `null` otherwise. An
  `offset` at or beyond `total` gives an empty `items`.

## 9. Bulk import

`POST /passages/import` records many passages from a body in JSON Lines form: lines are separated by `\n`, a
`\r` immediately before a `\n` is ignored, and each line holds one JSON value. Lines are numbered from 1, counting
every line. A line that is empty or holds only spaces and tabs is *blank* and is skipped (it keeps its number).
A trailing `\n` at the end of the body does not start another line. The request's `Content-Type` is not examined.

- **R9.1** More than 10000 non-blank lines fails with `413` `BATCH_TOO_LARGE`, field `null`, and records nothing.
- **R9.2** Each non-blank line is processed in order as if it were the body of its own `POST /passages` without
  an idempotency key: a line that is not valid JSON or not an object fails with `MALFORMED_JSON`; otherwise the
  field and semantic rules of §6 apply. `DUPLICATE_PASSAGE` compares with passages recorded before the import and
  with those recorded by earlier lines of the same import.
- **R9.3** The query parameter `atomic` is `true` or `false` (default `false`); any other value fails with `400`
  `INVALID_QUERY`, field `atomic`.
- **R9.4** With `atomic=false`, every line that passes is recorded (identifiers allocated in line order) and the
  answer is `200`:
  ```json
  {"accepted": 2, "rejected": 1, "results": [
    {"line": 1, "id": "PSG-000004"},
    {"line": 3, "error": {"code": "UNKNOWN_OPERATOR", "field": "operator"}},
    {"line": 4, "id": "PSG-000005"}
  ]}
  ```
  `results` has one element per non-blank line in line order. An empty body answers `200` with zero counts and an
  empty `results`.
- **R9.5** With `atomic=true`, if every line passes the effect and answer are as R9.4. If any line fails, nothing
  is recorded, no identifier is consumed, and the answer is `422` with `accepted` 0, `rejected` the number of
  failing lines and `results` holding only the failing lines' elements, in line order. (Lines are still judged in
  order as in R9.2, as if the earlier passing lines had been recorded.)

## 10. Delay claims

`POST /claims` lodges a claim for a rebate on one lock of a recorded passage. The optional header `X-Actor` names
who lodges it.

| Field | Type | Rule |
|---|---|---|
| `passageId` | string | Pattern `^PSG-[0-9]{6}$`. |
| `lock` | string | One of the nine lock codes. |
| `delayMinutes` | integer | 1 to 1440. |
| `reason` | string | One of `MECHANICAL`, `WATER_LEVEL`, `STAFFING`, `OBSTRUCTION`. |

- **R10.1** An actor is a string matching `^[a-z][a-z0-9.]{1,31}$`. If `X-Actor` is present and not an actor,
  the request fails with `400` `FIELD_FORMAT`, field `X-Actor`; this is checked after the body fields. Without the
  header the lodging actor is `anonymous`.
- **R10.2** Semantic rules, in order:
  1. `UNKNOWN_PASSAGE` (`422`, field `passageId`): no passage has this identifier.
  2. `LOCK_NOT_ON_PASSAGE` (`422`, field `lock`): the lock is not in the passage's `locks`.
  3. `CLAIM_WINDOW_CLOSED` (`422`, field `null`): the clock is later than the passage's `enteredAt` plus 14 days
     (exactly 14 days is still open).
  4. `CLAIM_EXISTS` (`409`, field `lock`): a claim for the same passage and lock exists whose state is neither
     `REJECTED` nor `WITHDRAWN`.
- **R10.3** *Rebate.* For a number of minutes `m`, the rebate on a claim is computed from `F`, the fee of the
  **first** occurrence of the claimed lock in the passage's `lockFees` (a 4-place amount), and `T`, the passage's
  toll `total`:
  1. `m` < 45: `R` = 0; 45 ≤ `m` < 120: `R = F × 0.25`; 120 ≤ `m` < 360: `R = F × 0.60`;
     `m` ≥ 360: `R = F + 0.35 × floor((m − 360) / 30)`;
  2. if `reason` is `WATER_LEVEL`, `R = R × 0.5`;
  3. `R = min(R, T × 0.40)`;
  4. the rebate is `U2(R)`.

  No rounding happens before step 4.
  *Example:* `F` = 8.5600 (K2 of worked example 1, `T` = 24.48), `MECHANICAL`: 30 min → `"0.00"`; 90 min → 2.14 →
  `"2.14"`; 400 min → 8.56 + 0.35 = 8.91 → `"8.91"`; 600 min → 8.56 + 0.35 × 8 = 11.36, capped at 9.792 → `"9.79"`;
  `WATER_LEVEL` 200 min → 8.56 × 0.60 × 0.5 = 2.568 → `"2.57"`.
- **R10.4** Identifiers are `CLM-` followed by a five-digit, zero-padded sequence starting at `CLM-00001`, consumed
  only by claims actually lodged.
- **R10.5** Success answers `201` with the claim and the header `ETag: "1"`. A lodged claim is in state `LODGED`,
  version 1, and `eligibleRebate` is the rebate (R10.3) for `delayMinutes`:
  ```json
  {
    "id": "CLM-00001", "passageId": "PSG-000001", "operator": "KV-209", "lock": "K2",
    "delayMinutes": 90, "reason": "MECHANICAL", "state": "LODGED", "version": 1,
    "lodgedAt": "2026-03-20T12:00:00Z", "updatedAt": "2026-03-20T12:00:00Z",
    "eligibleRebate": "2.14",
    "assessedMinutes": null, "assessedRebate": null, "assessedBy": null,
    "approvedAmount": null, "approvedBy": null, "approvedAt": null,
    "settlementReference": null, "rejectedAt": null, "reopenCount": 0
  }
  ```
  `operator` is the passage's operator.
- **R10.6** `GET /claims/{id}` answers `200` with the claim and the header `ETag: "<version>"`, or `404`
  `NOT_FOUND`.
- **R10.7** `POST /claims` supports idempotency keys (§7). `X-Actor` is not part of the comparison; a replay
  returns the stored body and `ETag` even if the claim has since changed.

## 11. The claim workflow

`POST /claims/{id}/transitions` moves a claim. Body: `{"action": "<action>", ...}`. Headers: `If-Match`
(required) and `X-Actor` (required).

| Action | From | To | Further fields |
|---|---|---|---|
| `assess` | `LODGED` | `ASSESSED` | `assessedMinutes`: integer, 0 to the claim's `delayMinutes` |
| `reject` | `ASSESSED` | `REJECTED` | `note`: string, 1 to 200 characters |
| `approve` | `ASSESSED` | `APPROVED` | `amount`: optional string, money pattern `^[0-9]+\.[0-9]{2}$`, greater than 0 |
| `settle` | `APPROVED` | `SETTLED` | `reference`: string, pattern `^STL-[0-9]{8}$` |
| `withdraw` | `LODGED` or `ASSESSED` | `WITHDRAWN` | none |
| `reopen` | `REJECTED` | `LODGED` | none |

`SETTLED` and `WITHDRAWN` are final. Every pair of state and action not in the table is forbidden.

- **R11.1** Checks, in this order; the first failure is answered:
  1. no such claim: `404` `NOT_FOUND`;
  2. `If-Match` absent: `428` `VERSION_REQUIRED`, field `If-Match`;
  3. `If-Match` is not a double-quoted decimal integer (`"3"`): `400` `INVALID_HEADER`, field `If-Match`;
  4. the integer differs from the claim's `version`: `412` `VERSION_MISMATCH`, field `If-Match`;
  5. the body per R1.4;
  6. `action`: required string, one of the six actions (R1.5, field `action`);
  7. `X-Actor`: absent is `400` `FIELD_REQUIRED`, not an actor (R10.1) is `400` `FIELD_FORMAT`, field `X-Actor`;
  8. the action is forbidden from the current state: `409` `TRANSITION_FORBIDDEN`, field `action`;
  9. the action's further fields (R1.5);
  10. the action's semantic rules (R11.3 to R11.6).
- **R11.2** A transition that succeeds increments `version` by one, sets `updatedAt` to the clock, appends an
  audit entry (§12) and answers `200` with the claim and `ETag: "<new version>"`. A failed transition changes
  nothing.
- **R11.3** `assess` sets `assessedMinutes`, `assessedBy` to the actor, and `assessedRebate` to the rebate
  (R10.3) for `assessedMinutes`.
- **R11.4** `approve`:
  1. the actor equals `assessedBy`: `403` `SAME_ACTOR`, field `X-Actor`;
  2. `assessedRebate` is `"0.00"`: `422` `NOTHING_TO_APPROVE`, field `null`;
  3. `amount` greater than `assessedRebate`: `422` `AMOUNT_EXCEEDS`, field `amount`.

  On success `approvedAmount` is `amount`, or `assessedRebate` when `amount` is absent; `approvedBy` is the actor
  and `approvedAt` the clock.
- **R11.5** `settle`: if the clock is earlier than `approvedAt` plus 48 hours: `422` `SETTLEMENT_TOO_EARLY`, field
  `null`. On success `settlementReference` is `reference`.
- **R11.6** `reject` sets `rejectedAt` to the clock (the note is recorded only in the audit trail). `reopen`:
  1. `reopenCount` is already 1: `409` `REOPEN_LIMIT`, field `null`;
  2. the clock is later than `rejectedAt` plus 7 days: `422` `CLAIM_WINDOW_CLOSED`, field `null`;
  3. another claim for the same passage and lock is in a state other than `REJECTED` and `WITHDRAWN`: `409`
     `CLAIM_EXISTS`, field `lock`.

  On success `reopenCount` becomes 1 and `assessedMinutes`, `assessedRebate`, `assessedBy` and `rejectedAt`
  become `null`.
- **R11.7** `withdraw` changes only the state.

## 12. Audit trail

- **R12.1** `GET /claims/{id}/audit` answers `200` with every entry of the claim in order, or `404` `NOT_FOUND`:
  ```json
  {"claimId": "CLM-00001", "entries": [
    {"seq": 1, "at": "2026-03-20T12:00:00Z", "actor": "anonymous", "action": "lodge",
     "fromState": null, "toState": "LODGED", "version": 1, "note": null},
    {"seq": 2, "at": "2026-03-20T13:00:00Z", "actor": "clerk.ann", "action": "assess",
     "fromState": "LODGED", "toState": "ASSESSED", "version": 2, "note": null}
  ]}
  ```
- **R12.2** Lodging appends the entry with `seq` 1, action `lodge`. Each successful transition appends one entry:
  `seq` one more than the last, `action` the action, the states before and after, the claim's new `version`.
  `note` is the note of a `reject` and `null` otherwise.
- **R12.3** Failed requests and idempotent replays append nothing.

## 13. Operator statement

`GET /reports/operator-statement?operator=<code>&month=<YYYY-MM>` reports one operator's month.

- **R13.1** Unknown and repeated parameters are treated as in R8.1. `operator` and `month` are required; absent or empty fails with `400` `INVALID_QUERY`, field the
  parameter name, `operator` checked first. `month` is `YYYY-MM` with a month from 01 to 12, else
  `INVALID_QUERY`. An operator that is not registered answers `404` `NOT_FOUND`.
- **R13.2** The report covers the operator's passages whose `enteredAt` lies in that calendar month (UTC), and the
  claims on those passages, whatever their dates.
- **R13.3** The answer is `200` (the figures below show the shape and are not a worked example):
  ```json
  {
    "operator": "KV-209", "month": "2026-03",
    "passages": 3, "tollTotal": "86.57",
    "byCargo": [{"cargo": "GEN", "passages": 2, "tollTotal": "48.96"}, {"cargo": "AGG", "passages": 1, "tollTotal": "37.61"}],
    "busiestLock": {"lock": "K2", "passages": 3},
    "claims": {"LODGED": 0, "ASSESSED": 1, "APPROVED": 0, "SETTLED": 1, "REJECTED": 0, "WITHDRAWN": 0},
    "rebatesApproved": "0.00", "rebatesSettled": "2.14", "net": "84.43"
  }
  ```
  - `tollTotal` is the sum of the passages' toll `total`s.
  - `byCargo` holds one element per cargo code that occurs, ordered by `tollTotal` descending, then by cargo code
    ascending (by character code: `AGG` < `GEN` < `HAZ-A` < `HAZ-B` < `LIV` < `NONE`).
  - `busiestLock` is the lock contained in the greatest number of the passages (a passage counts once per lock
    however often it passes it); ties go to the lock earliest in table order (R4.1). `null` when there are no
    passages.
  - `claims` always holds all six states.
  - `rebatesApproved` is the sum of `approvedAmount` of claims in `APPROVED`; `rebatesSettled` the sum of
    `approvedAmount` of claims in `SETTLED`; `net` = `tollTotal` − `rebatesSettled`.
- **R13.4** With no passages the report has `passages` 0, `"0.00"` amounts, an empty `byCargo`, `busiestLock`
  `null` and zero claim counts.

## 14. Summary of error codes

| Code | Status |
|---|---|
| `MALFORMED_JSON` | 400 |
| `FIELD_REQUIRED`, `FIELD_TYPE`, `FIELD_FORMAT`, `CHECK_DIGIT`, `INVALID_QUERY`, `INVALID_HEADER` | 400 |
| `SAME_ACTOR` | 403 |
| `NOT_FOUND`, `ROUTE_NOT_FOUND` | 404 |
| `DUPLICATE_OPERATOR`, `DUPLICATE_PASSAGE`, `IDEMPOTENCY_CONFLICT`, `CLAIM_EXISTS`, `TRANSITION_FORBIDDEN`, `REOPEN_LIMIT` | 409 |
| `VERSION_MISMATCH` | 412 |
| `BATCH_TOO_LARGE` | 413 |
| `UNKNOWN_OPERATOR`, `UNKNOWN_PASSAGE`, `LOCK_SEQUENCE_INVALID`, `GAUGE_EXCEEDED`, `HAZARD_ROUTE`, `CARGO_MISMATCH`, `TIME_IN_FUTURE`, `STALE_DECLARATION`, `LOCK_NOT_ON_PASSAGE`, `CLAIM_WINDOW_CLOSED`, `NOTHING_TO_APPROVE`, `AMOUNT_EXCEEDS`, `SETTLEMENT_TOO_EARLY` | 422 |
| `VERSION_REQUIRED` | 428 |

## 15. Endpoints

| # | Method and path | Section |
|---|---|---|
| 1 | `GET /admin/clock`, `PUT /admin/clock` | §2 |
| 2 | `POST /admin/reset` | §2 |
| 3 | `POST /operators` | §3 |
| 4 | `GET /operators/{code}` | §3 |
| 5 | `POST /tariff/quotes` | §5 |
| 6 | `POST /passages` | §6 |
| 7 | `GET /passages/{id}` | §6 |
| 8 | `GET /passages` | §8 |
| 9 | `POST /passages/import` | §9 |
| 10 | `POST /claims` | §10 |
| 11 | `GET /claims/{id}` | §10 |
| 12 | `POST /claims/{id}/transitions` | §11 |
| 13 | `GET /claims/{id}/audit` | §12 |
| 14 | `GET /reports/operator-statement` | §13 |

## 16. Acceptance

A set of black-box tests runs against the service as `python3 conformance/run.py http://localhost:<port>`. A part
of them is handed to you in `conformance/visible/`; the rest are held back and decide the verdict. Each test
resets the service (`POST /admin/reset`) and sets the clock before it starts, so tests are independent.
