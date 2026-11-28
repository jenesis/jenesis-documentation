import json

from lib import Case, call, rule, NOW, ENTERED


class Passages(Case):
    @rule("R6.1")
    def test_time_in_future(self):
        self.error(call("POST", "/passages", self.body(enteredAt="2026-03-20T12:00:01Z")),
                   422, "TIME_IN_FUTURE", "enteredAt")
        self.passage(enteredAt=NOW)

    @rule("R6.1")
    def test_stale_declaration_edge(self):
        self.passage(enteredAt="2026-02-18T12:00:00Z")
        self.error(call("POST", "/passages", self.body(enteredAt="2026-02-18T11:59:59Z")),
                   422, "STALE_DECLARATION", "enteredAt")

    @rule("R6.1")
    def test_duplicate_passage(self):
        self.passage(vesselMark="BELLA7")
        self.error(call("POST", "/passages", self.body(vesselMark="BELLA7", cargo="AGG")),
                   409, "DUPLICATE_PASSAGE", "vesselMark")
        self.passage(vesselMark="BELLA7", enteredAt="2026-03-17T10:00:01Z")

    @rule("R6.1")
    def test_semantic_rules_in_order(self):
        self.error(call("POST", "/passages", self.body(operator="QD-737", locks=["K1", "K3"])),
                   422, "UNKNOWN_OPERATOR", "operator")
        self.error(call("POST", "/passages", self.body(locks=["K1", "K3"], enteredAt="2026-03-21T00:00:00Z")),
                   422, "LOCK_SEQUENCE_INVALID", "locks")
        self.passage(vesselMark="DUP1")
        self.error(call("POST", "/passages", self.body(vesselMark="DUP1", cargo="NONE")),
                   422, "CARGO_MISMATCH", "cargo")

    @rule("R6.1")
    def test_operator_check_digit_is_not_examined(self):
        self.error(call("POST", "/passages", self.body(operator="KV-205")), 422, "UNKNOWN_OPERATOR", "operator")
        self.error(call("POST", "/passages", self.body(operator="KV205")), 400, "FIELD_FORMAT", "operator")

    @rule("R6.1")
    def test_vessel_mark_pattern(self):
        for bad in ["ab123", "AB", "ABCDEFGHIJK", "AB-12"]:
            self.error(call("POST", "/passages", self.body(vesselMark=bad)), 400, "FIELD_FORMAT", "vesselMark")

    @rule("R6.2")
    def test_toll_uses_the_operators_tier(self):
        self.assertEqual(self.passage(operator="AB-102")["toll"]["total"], "22.27")
        p = self.passage(operator="MX-445")
        self.assertEqual((p["tier"], p["toll"]["total"]), ("heritage", "14.69"))

    @rule("R6.3")
    def test_rejected_requests_consume_no_number(self):
        self.error(call("POST", "/passages", self.body(operator="QD-737")), 422, "UNKNOWN_OPERATOR")
        self.error(call("POST", "/passages", self.body(lengthDm=1)), 400, "FIELD_FORMAT")
        self.assertEqual(self.passage()["id"], "PSG-000001")

    @rule("R6.4")
    def test_passage_representation(self):
        p = self.passage(vesselMark="BELLA7", ladenTonnes="7")
        self.assertEqual({k: v for k, v in p.items() if k != "toll"}, {
            "id": "PSG-000001", "operator": "KV-209", "tier": "ordinary", "vesselMark": "BELLA7",
            "vesselClass": "NB", "lengthDm": 180, "ladenTonnes": "7.00", "cargo": "GEN",
            "locks": ["K1", "K2", "K3"], "enteredAt": ENTERED, "recordedAt": NOW})
        self.assertEqual(self.passage(ladenTonnes="7.5")["ladenTonnes"], "7.50")

    @rule("R6.5")
    def test_get_passage(self):
        p = self.passage()
        self.assertEqual(self.ok(call("GET", "/passages/" + p["id"]), 200), p)
        self.error(call("GET", "/passages/PSG-000099"), 404, "NOT_FOUND", None)


class Idempotency(Case):
    @rule("R7.1")
    def test_key_format_is_checked_before_the_body(self):
        for bad in ["short", "x" * 65, "has space", "under_score"]:
            self.error(call("POST", "/passages", raw=b"{", headers={"Idempotency-Key": bad}),
                       400, "FIELD_FORMAT", "Idempotency-Key")

    @rule("R7.2")
    def test_keys_are_scoped_by_endpoint(self):
        p = self.ok(call("POST", "/passages", self.body(), {"Idempotency-Key": "shared-key-1"}), 201)
        r = call("POST", "/claims", {"passageId": p["id"], "lock": "K1", "delayMinutes": 50, "reason": "STAFFING"},
                 {"Idempotency-Key": "shared-key-1"})
        self.ok(r, 201)
        self.assertIsNone(r.header("Idempotent-Replay"))

    @rule("R7.3")
    def test_key_order_does_not_matter(self):
        body = self.body()
        reordered = dict(reversed(list(body.items())))
        first = self.ok(call("POST", "/passages", body, {"Idempotency-Key": "order-key-1"}), 201)
        r = call("POST", "/passages", reordered, {"Idempotency-Key": "order-key-1"})
        self.assertEqual(self.ok(r, 201), first)
        self.assertEqual(r.header("Idempotent-Replay"), "true")

    @rule("R7.3")
    def test_replay_skips_validation_and_clock(self):
        body = self.body()
        first = self.ok(call("POST", "/passages", body, {"Idempotency-Key": "clock-key-1"}), 201)
        self.clock("2026-03-21T11:00:00Z")
        r = call("POST", "/passages", body, {"Idempotency-Key": "clock-key-1"})
        self.assertEqual(self.ok(r, 201), first)
        self.assertEqual(first["recordedAt"], NOW)

    @rule("R7.4")
    def test_failed_request_stores_nothing(self):
        self.error(call("POST", "/passages", self.body(operator="QD-737"), {"Idempotency-Key": "fail-key-1"}),
                   422, "UNKNOWN_OPERATOR")
        p = self.ok(call("POST", "/passages", self.body(), {"Idempotency-Key": "fail-key-1"}), 201)
        self.assertEqual(p["id"], "PSG-000001")

    @rule("R7.5")
    def test_entries_expire_after_a_day(self):
        self.ok(call("POST", "/passages", self.body(), {"Idempotency-Key": "expiry-key"}), 201)
        self.clock("2026-03-21T11:59:59Z")
        self.error(call("POST", "/passages", self.body(), {"Idempotency-Key": "expiry-key"}),
                   409, "IDEMPOTENCY_CONFLICT", "Idempotency-Key")
        self.clock("2026-03-21T12:00:00Z")
        body = self.body()
        r = call("POST", "/passages", body, {"Idempotency-Key": "expiry-key"})
        self.assertEqual(self.ok(r, 201)["id"], "PSG-000002")
        self.assertIsNone(r.header("Idempotent-Replay"))
        again = call("POST", "/passages", body, {"Idempotency-Key": "expiry-key"})
        self.assertEqual(self.ok(again, 201)["id"], "PSG-000002")

    @rule("R7.6")
    def test_first_response_has_no_replay_header(self):
        r = call("POST", "/passages", self.body(), {"Idempotency-Key": "first-key-1"})
        self.ok(r, 201)
        self.assertIsNone(r.header("Idempotent-Replay"))


class Listing(Case):
    def seed(self):
        self.passage(enteredAt="2026-03-10T08:00:00Z")
        self.passage(enteredAt="2026-03-11T08:00:00Z", operator="AB-102", cargo="AGG")
        self.passage(enteredAt="2026-03-12T08:00:00Z", vesselClass="WB", locks=["K5"], cargo="AGG")
        self.passage(enteredAt="2026-03-13T08:00:00Z", operator="AB-102")

    def ids(self, query):
        return [p["id"] for p in self.ok(call("GET", "/passages" + query), 200)["items"]]

    @rule("R8.1")
    def test_invalid_parameters(self):
        for q, field in [("limit=0", "limit"), ("limit=201", "limit"), ("limit=", "limit"), ("offset=-1", "offset"),
                         ("offset=1.5", "offset"), ("cargo=gen", "cargo"), ("vesselClass=XX", "vesselClass"),
                         ("operator=", "operator"), ("from=2026-03-10", "from"), ("minTotal=1.234", "minTotal"),
                         ("minTotal=-1", "minTotal"), ("cargo=XX&limit=0", "cargo")]:
            self.error(call("GET", "/passages?" + q), 400, "INVALID_QUERY", field)

    @rule("R8.1")
    def test_from_must_precede_to(self):
        t = "2026-03-10T00:00:00Z"
        self.error(call("GET", "/passages?from=%s&to=%s" % (t, t)), 400, "INVALID_QUERY", "to")
        self.ok(call("GET", "/passages?limit=200&colour=red"), 200)

    @rule("R8.2")
    def test_filters_combine(self):
        self.seed()
        self.assertEqual(self.ids("?operator=AB-102"), ["PSG-000004", "PSG-000002"])
        self.assertEqual(self.ids("?operator=AB-102&cargo=AGG"), ["PSG-000002"])
        self.assertEqual(self.ids("?vesselClass=WB"), ["PSG-000003"])
        self.assertEqual(self.ids("?operator=KV-205"), [])

    @rule("R8.2")
    def test_time_range_is_half_open(self):
        self.seed()
        self.assertEqual(self.ids("?from=2026-03-11T08:00:00Z&to=2026-03-13T08:00:00Z"),
                         ["PSG-000003", "PSG-000002"])

    @rule("R8.2")
    def test_min_total(self):
        self.seed()
        totals = {p["id"]: p["toll"]["total"] for p in self.ok(call("GET", "/passages"), 200)["items"]}
        self.assertEqual(totals["PSG-000004"], "22.27")
        self.assertEqual(self.ids("?minTotal=22.27&operator=AB-102"), ["PSG-000004", "PSG-000002"])
        self.assertEqual(self.ids("?minTotal=22.28&operator=AB-102"), ["PSG-000002"])
        self.assertEqual(self.ids("?minTotal=1000"), [])

    @rule("R8.4")
    def test_defaults_and_offset_beyond_total(self):
        self.seed()
        r = self.ok(call("GET", "/passages"), 200)
        self.assertEqual((r["total"], r["offset"], r["limit"], r["nextOffset"]), (4, 0, 50, None))
        r = self.ok(call("GET", "/passages?offset=9"), 200)
        self.assertEqual((r["items"], r["total"], r["nextOffset"]), ([], 4, None))

    @rule("R8.4")
    def test_full_passages_are_listed(self):
        p = self.passage()
        self.assertEqual(self.ok(call("GET", "/passages"), 200)["items"], [p])

    @rule("R8.3")
    def test_order_across_pages(self):
        for i in range(7):
            self.passage(enteredAt="2026-03-1%dT08:00:00Z" % (i % 3))
        seen = []
        offset = 0
        while offset is not None:
            r = self.ok(call("GET", "/passages?limit=3&offset=%d" % offset), 200)
            seen += [p["id"] for p in r["items"]]
            offset = r["nextOffset"]
        self.assertEqual(seen, ["PSG-000003", "PSG-000006", "PSG-000002", "PSG-000005", "PSG-000001",
                                "PSG-000004", "PSG-000007"])


class Import(Case):
    def post(self, lines, query="", raw=None):
        data = raw if raw is not None else "\n".join(lines).encode()
        return call("POST", "/passages/import" + query, raw=data)

    @rule("R9.1")
    def test_too_many_lines(self):
        self.error(self.post(["{}"] * 10001), 413, "BATCH_TOO_LARGE", None)
        r = self.ok(self.post(["{}"] * 10000 + ["", "  "]), 200)
        self.assertEqual((r["accepted"], r["rejected"]), (0, 10000))

    @rule("R9.2")
    def test_line_numbering_blank_lines_and_crlf(self):
        raw = ("\r\n" + json.dumps(self.body()) + "\r\n \t\r\n[1]\r\nnot json\r\n" + json.dumps(self.body())
               + "\r\n").encode()
        r = self.ok(self.post(None, raw=raw), 200)
        self.assertEqual(r["results"], [
            {"line": 2, "id": "PSG-000001"},
            {"line": 4, "error": {"code": "MALFORMED_JSON", "field": None}},
            {"line": 5, "error": {"code": "MALFORMED_JSON", "field": None}},
            {"line": 6, "id": "PSG-000002"}])

    @rule("R9.2")
    def test_field_rules_apply_per_line(self):
        r = self.ok(self.post([json.dumps(self.body(lengthDm="1")), json.dumps(self.body(locks=["K1", "W1"])),
                               json.dumps(self.body(enteredAt="2027-01-01T00:00:00Z"))]), 200)
        self.assertEqual([x["error"] for x in r["results"]], [
            {"code": "FIELD_TYPE", "field": "lengthDm"}, {"code": "LOCK_SEQUENCE_INVALID", "field": "locks"},
            {"code": "TIME_IN_FUTURE", "field": "enteredAt"}])

    @rule("R9.2")
    def test_duplicates_within_and_before_the_import(self):
        self.passage(vesselMark="OLD1")
        r = self.ok(self.post([json.dumps(self.body(vesselMark="OLD1")), json.dumps(self.body(vesselMark="NEW1")),
                               json.dumps(self.body(vesselMark="NEW1", cargo="AGG"))]), 200)
        self.assertEqual(r["results"], [
            {"line": 1, "error": {"code": "DUPLICATE_PASSAGE", "field": "vesselMark"}},
            {"line": 2, "id": "PSG-000002"},
            {"line": 3, "error": {"code": "DUPLICATE_PASSAGE", "field": "vesselMark"}}])

    @rule("R9.3")
    def test_atomic_parameter(self):
        self.error(self.post([], "?atomic=yes"), 400, "INVALID_QUERY", "atomic")
        self.error(self.post([], "?atomic="), 400, "INVALID_QUERY", "atomic")

    @rule("R9.4")
    def test_empty_body(self):
        self.assertEqual(self.ok(self.post([]), 200), {"accepted": 0, "rejected": 0, "results": []})

    @rule("R9.4")
    def test_imported_passages_are_complete(self):
        r = self.ok(self.post([json.dumps(self.body(operator="MX-445"))], "?atomic=false"), 200)
        p = self.ok(call("GET", "/passages/" + r["results"][0]["id"]), 200)
        self.assertEqual((p["tier"], p["toll"]["total"], p["recordedAt"]), ("heritage", "14.69", NOW))

    @rule("R9.5")
    def test_atomic_failure_records_nothing(self):
        lines = [json.dumps(self.body()), json.dumps(self.body(operator="QD-737")), json.dumps(self.body()),
                 "{"]
        r = self.post(lines, "?atomic=true")
        self.assertEqual(r.status, 422, r)
        self.assertEqual(r.body, {"accepted": 0, "rejected": 2, "results": [
            {"line": 2, "error": {"code": "UNKNOWN_OPERATOR", "field": "operator"}},
            {"line": 4, "error": {"code": "MALFORMED_JSON", "field": None}}]})
        self.assertEqual(self.ok(call("GET", "/passages"), 200)["total"], 0)
        self.assertEqual(self.passage()["id"], "PSG-000001")

    @rule("R9.5")
    def test_atomic_success_and_duplicates_judged_in_order(self):
        r = self.post([json.dumps(self.body(vesselMark="SAME1")), json.dumps(self.body(vesselMark="SAME1"))],
                      "?atomic=true")
        self.assertEqual(r.status, 422, r)
        self.assertEqual(r.body["results"], [{"line": 2, "error": {"code": "DUPLICATE_PASSAGE",
                                                                    "field": "vesselMark"}}])
        r = self.ok(self.post([json.dumps(self.body()), json.dumps(self.body())], "?atomic=true"), 200)
        self.assertEqual(r, {"accepted": 2, "rejected": 0, "results": [{"line": 1, "id": "PSG-000001"},
                                                                         {"line": 2, "id": "PSG-000002"}]})
