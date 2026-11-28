from lib import Case, call, rule, NOW, ENTERED


class General(Case):
    @rule("R1.3")
    def test_unknown_route_is_route_not_found(self):
        self.error(call("GET", "/vessels"), 404, "ROUTE_NOT_FOUND", None)

    @rule("R1.4")
    def test_malformed_json_is_rejected(self):
        self.error(call("POST", "/operators", raw=b'{"code": "KV-209",'), 400, "MALFORMED_JSON", None)

    @rule("R2.2")
    def test_clock_is_set_and_read_back(self):
        self.assertEqual(self.ok(call("PUT", "/admin/clock", {"now": "2026-04-01T08:30:00Z"}), 200),
                         {"now": "2026-04-01T08:30:00Z"})
        self.assertEqual(self.ok(call("GET", "/admin/clock"), 200), {"now": "2026-04-01T08:30:00Z"})

    @rule("R2.5")
    def test_reset_clears_state_and_sequences(self):
        self.passage()
        self.ok(call("POST", "/admin/reset", {}), 204)
        self.error(call("GET", "/operators/KV-209"), 404, "NOT_FOUND")
        self.clock(NOW)
        self.ok(call("POST", "/operators", {"code": "KV-209", "name": "K", "tier": "ordinary"}), 201)
        self.assertEqual(self.passage()["id"], "PSG-000001")


class Operators(Case):
    @rule("R3.3")
    def test_operator_is_registered_with_trimmed_name(self):
        body = self.ok(call("POST", "/operators", {"code": "QD-737", "name": "  Quay Dredging  ",
                                                   "tier": "contract"}), 201)
        self.assertEqual(body, {"code": "QD-737", "name": "Quay Dredging", "tier": "contract",
                                "registeredAt": NOW})
        self.assertEqual(self.ok(call("GET", "/operators/QD-737"), 200), body)

    @rule("R3.1")
    def test_wrong_check_digit_is_refused(self):
        self.error(call("POST", "/operators", {"code": "KV-205", "name": "X", "tier": "ordinary"}),
                   400, "CHECK_DIGIT", "code")

    @rule("R3.2")
    def test_duplicate_operator_is_refused(self):
        self.error(call("POST", "/operators", {"code": "KV-209", "name": "Again", "tier": "ordinary"}),
                   409, "DUPLICATE_OPERATOR", "code")


class Tariff(Case):
    @rule("R4.10")
    def test_worked_example_one(self):
        p = self.passage()
        self.assertEqual(p["toll"], {
            "lockFees": [{"lock": "K1", "fee": "8.0650"}, {"lock": "K2", "fee": "8.5600"},
                         {"lock": "K3", "fee": "7.2550"}],
            "lockFeeTotal": "23.8800", "weightCharge": "0.0000", "cargoSurcharge": "0.5970",
            "bandSurcharge": "0.0000", "tierDiscount": "0.0000", "total": "24.48", "minimumApplied": False})

    @rule("R4.7")
    def test_worked_example_two(self):
        r = self.quote(self.spec(vesselClass="WB", lengthDm=250, ladenTonnes="47.35", cargo="HAZ-B",
                                 locks=["K2", "K3", "K2"], enteredAt="2026-03-14T23:30:00Z", tier="contract"))
        toll = r["results"][0]["toll"]
        self.assertEqual(self.fees(toll), ["11.0860", "8.8349", "5.5430"])
        self.assertEqual([toll[k] for k in ["lockFeeTotal", "weightCharge", "cargoSurcharge", "bandSurcharge",
                                            "tierDiscount", "total"]],
                         ["25.4639", "3.7736", "3.8009", "8.2860", "3.7192", "37.61"])

    @rule("R4.9")
    def test_worked_example_three_minimum_and_half_even(self):
        toll = self.passage(lengthDm=220, ladenTonnes="0", cargo="NONE", locks=["W1"])["toll"]
        self.assertEqual(self.fees(toll), ["6.4802"])
        self.assertEqual(toll["total"], "7.50")
        self.assertIs(toll["minimumApplied"], True)

    @rule("R4.2")
    def test_wide_beam_may_not_enter_a_narrow_lock(self):
        self.error(call("POST", "/passages", self.body(vesselClass="WB", locks=["K3", "W1"])),
                   422, "GAUGE_EXCEEDED", "locks")


class Quotes(Case):
    @rule("R5.4")
    def test_quote_batch_reports_each_item(self):
        r = self.quote(self.spec(ref="a"), self.spec(ref="b", vesselClass="DB", locks=["W1"]),
                       self.spec(ref="c", tier="contract"))
        self.assertEqual((r["count"], r["quoted"], r["failed"]), (3, 2, 1))
        self.assertEqual(r["results"][0]["toll"]["total"], "24.48")
        self.assertEqual(r["results"][1], {"ref": "b", "error": {"code": "GAUGE_EXCEEDED", "field": "locks"}})
        self.assertEqual(r["results"][2]["toll"]["total"], "22.27")
        self.assertEqual(r["grandTotal"], "46.75")


class Passages(Case):
    @rule("R6.1")
    def test_unknown_operator_is_refused(self):
        self.error(call("POST", "/passages", self.body(operator="QD-737")), 422, "UNKNOWN_OPERATOR", "operator")

    @rule("R6.3")
    def test_identifiers_are_sequential(self):
        self.assertEqual(self.passage()["id"], "PSG-000001")
        self.assertEqual(self.passage()["id"], "PSG-000002")


class Idempotency(Case):
    @rule("R7.3")
    def test_same_key_and_body_replays_the_response(self):
        body = self.body()
        first = call("POST", "/passages", body, {"Idempotency-Key": "abc-12345"})
        second = call("POST", "/passages", body, {"Idempotency-Key": "abc-12345"})
        self.assertEqual(self.ok(second, 201), self.ok(first, 201))
        self.assertEqual(second.header("Idempotent-Replay"), "true")
        self.assertEqual(self.passage()["id"], "PSG-000002")

    @rule("R7.3")
    def test_same_key_with_another_body_conflicts(self):
        self.ok(call("POST", "/passages", self.body(), {"Idempotency-Key": "abc-12345"}), 201)
        self.error(call("POST", "/passages", self.body(), {"Idempotency-Key": "abc-12345"}),
                   409, "IDEMPOTENCY_CONFLICT", "Idempotency-Key")


class Listing(Case):
    @rule("R8.3")
    def test_order_is_entered_descending_then_id_ascending(self):
        a = self.passage(enteredAt="2026-03-10T08:00:00Z")["id"]
        b = self.passage(enteredAt="2026-03-12T08:00:00Z")["id"]
        c = self.passage(enteredAt="2026-03-10T08:00:00Z")["id"]
        r = self.ok(call("GET", "/passages"), 200)
        self.assertEqual([p["id"] for p in r["items"]], [b, a, c])

    @rule("R8.4")
    def test_pagination_reports_next_offset(self):
        for i in range(5):
            self.passage(enteredAt="2026-03-1%dT08:00:00Z" % i)
        r = self.ok(call("GET", "/passages?limit=2&offset=2"), 200)
        self.assertEqual((r["total"], r["offset"], r["limit"], r["nextOffset"]), (5, 2, 2, 4))
        self.assertEqual([p["enteredAt"] for p in r["items"]], ["2026-03-12T08:00:00Z", "2026-03-11T08:00:00Z"])
        r = self.ok(call("GET", "/passages?limit=2&offset=4"), 200)
        self.assertIsNone(r["nextOffset"])


class Import(Case):
    @rule("R9.4")
    def test_import_records_good_lines_and_reports_bad_ones(self):
        import json
        lines = [json.dumps(self.body()), "", json.dumps(self.body(operator="QD-737")), json.dumps(self.body())]
        r = self.ok(call("POST", "/passages/import", raw="\n".join(lines).encode()), 200)
        self.assertEqual(r, {"accepted": 2, "rejected": 1, "results": [
            {"line": 1, "id": "PSG-000001"},
            {"line": 3, "error": {"code": "UNKNOWN_OPERATOR", "field": "operator"}},
            {"line": 4, "id": "PSG-000002"}]})


class Claims(Case):
    @rule("R10.5")
    def test_claim_is_lodged_with_eligible_rebate(self):
        p = self.passage()
        r = call("POST", "/claims", {"passageId": p["id"], "lock": "K2", "delayMinutes": 90,
                                     "reason": "MECHANICAL"})
        c = self.ok(r, 201)
        self.assertEqual(r.header("ETag"), '"1"')
        self.assertEqual(c, {"id": "CLM-00001", "passageId": p["id"], "operator": "KV-209", "lock": "K2",
                             "delayMinutes": 90, "reason": "MECHANICAL", "state": "LODGED", "version": 1,
                             "lodgedAt": NOW, "updatedAt": NOW, "eligibleRebate": "2.14", "assessedMinutes": None,
                             "assessedRebate": None, "assessedBy": None, "approvedAmount": None,
                             "approvedBy": None, "approvedAt": None, "settlementReference": None,
                             "rejectedAt": None, "reopenCount": 0})

    @rule("R11.1")
    def test_transition_without_if_match_is_refused(self):
        c = self.claim(self.passage()["id"])
        r = call("POST", "/claims/%s/transitions" % c["id"], {"action": "withdraw"}, {"X-Actor": "clerk.ann"})
        self.error(r, 428, "VERSION_REQUIRED", "If-Match")

    @rule("R11.4")
    def test_assessor_may_not_approve(self):
        c = self.claim(self.passage()["id"])
        self.moved(c["id"], 1, "assess", "clerk.ann", assessedMinutes=90)
        self.error(self.move(c["id"], 2, "approve", "clerk.ann"), 403, "SAME_ACTOR", "X-Actor")
        approved = self.moved(c["id"], 2, "approve", "clerk.bob")
        self.assertEqual((approved["state"], approved["approvedAmount"], approved["version"]),
                         ("APPROVED", "2.14", 3))

    @rule("R12.1")
    def test_audit_lists_lodge_and_assess(self):
        c = self.claim(self.passage()["id"], headers={"X-Actor": "skipper.jo"})
        self.clock("2026-03-20T13:00:00Z")
        self.moved(c["id"], 1, "assess", "clerk.ann", assessedMinutes=60)
        r = self.ok(call("GET", "/claims/%s/audit" % c["id"]), 200)
        self.assertEqual(r, {"claimId": c["id"], "entries": [
            {"seq": 1, "at": NOW, "actor": "skipper.jo", "action": "lodge", "fromState": None,
             "toState": "LODGED", "version": 1, "note": None},
            {"seq": 2, "at": "2026-03-20T13:00:00Z", "actor": "clerk.ann", "action": "assess",
             "fromState": "LODGED", "toState": "ASSESSED", "version": 2, "note": None}]})


class Report(Case):
    @rule("R13.3")
    def test_statement_sums_the_month(self):
        self.passage()
        self.passage(enteredAt="2026-03-15T12:00:00Z")
        self.passage(enteredAt="2026-02-27T12:00:00Z")
        r = self.ok(call("GET", "/reports/operator-statement?operator=KV-209&month=2026-03"), 200)
        self.assertEqual(r, {"operator": "KV-209", "month": "2026-03", "passages": 2, "tollTotal": "50.43",
                             "byCargo": [{"cargo": "GEN", "passages": 2, "tollTotal": "50.43"}],
                             "busiestLock": {"lock": "K1", "passages": 2},
                             "claims": {"LODGED": 0, "ASSESSED": 0, "APPROVED": 0, "SETTLED": 0, "REJECTED": 0,
                                        "WITHDRAWN": 0},
                             "rebatesApproved": "0.00", "rebatesSettled": "0.00", "net": "50.43"})
