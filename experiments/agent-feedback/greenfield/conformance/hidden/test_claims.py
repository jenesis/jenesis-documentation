import threading

from lib import Case, call, rule, NOW


def lodge(pid, lock="K2", minutes=90, reason="MECHANICAL", headers=None):
    return call("POST", "/claims", {"passageId": pid, "lock": lock, "delayMinutes": minutes, "reason": reason},
                headers)


class Lodging(Case):
    @rule("R10.1")
    def test_actor_header_rules(self):
        p = self.passage()
        for bad in ["Clerk", "a", "x" * 33, "clerk ann", "9clerk"]:
            self.error(lodge(p["id"], headers={"X-Actor": bad}), 400, "FIELD_FORMAT", "X-Actor")
        self.error(lodge(p["id"], minutes=0, headers={"X-Actor": "BAD"}), 400, "FIELD_FORMAT", "delayMinutes")
        self.error(lodge("PSG-999999", headers={"X-Actor": "BAD"}), 400, "FIELD_FORMAT", "X-Actor")

    @rule("R10.1")
    def test_lodging_fields(self):
        p = self.passage()
        for kw, code, field in [(dict(pid="PSG-1"), "FIELD_FORMAT", "passageId"),
                                (dict(pid=p["id"], lock="K0"), "FIELD_FORMAT", "lock"),
                                (dict(pid=p["id"], minutes=1441), "FIELD_FORMAT", "delayMinutes"),
                                (dict(pid=p["id"], minutes="90"), "FIELD_TYPE", "delayMinutes"),
                                (dict(pid=p["id"], reason="FLOOD"), "FIELD_FORMAT", "reason")]:
            self.error(lodge(**kw), 400, code, field)

    @rule("R10.2")
    def test_unknown_passage_and_lock_not_on_route(self):
        p = self.passage()
        self.error(lodge("PSG-000002"), 422, "UNKNOWN_PASSAGE", "passageId")
        self.error(lodge(p["id"], lock="K4"), 422, "LOCK_NOT_ON_PASSAGE", "lock")

    @rule("R10.2")
    def test_claim_window_edge(self):
        p = self.passage()
        self.clock("2026-03-31T10:00:00Z")
        self.ok(lodge(p["id"], lock="K1"), 201)
        self.clock("2026-03-31T10:00:01Z")
        self.error(lodge(p["id"], lock="K2"), 422, "CLAIM_WINDOW_CLOSED", None)

    @rule("R10.2")
    def test_one_live_claim_per_passage_and_lock(self):
        p = self.passage()
        c = self.claim(p["id"])
        self.error(lodge(p["id"]), 409, "CLAIM_EXISTS", "lock")
        self.ok(lodge(p["id"], lock="K3"), 201)
        self.moved(c["id"], 1, "withdraw")
        self.assertEqual(self.claim(p["id"])["id"], "CLM-00003")

    @rule("R10.3")
    def test_rebate_bands(self):
        p = self.passage()
        expected = [(44, "0.00"), (45, "2.14"), (119, "2.14"), (120, "5.14"), (359, "5.14"), (360, "8.56"),
                    (389, "8.56"), (390, "8.91"), (420, "9.26"), (450, "9.61"), (480, "9.79"), (1440, "9.79")]
        got = []
        for minutes, _ in expected:
            c = self.claim(p["id"], minutes=minutes)
            got.append((minutes, c["eligibleRebate"]))
            self.moved(c["id"], 1, "withdraw")
        self.assertEqual(got, expected)

    @rule("R10.3")
    def test_water_level_halves_before_the_cap(self):
        p = self.passage()
        got = []
        for minutes in [90, 200, 600, 1440]:
            c = self.claim(p["id"], minutes=minutes, reason="WATER_LEVEL")
            got.append(c["eligibleRebate"])
            self.moved(c["id"], 1, "withdraw")
        self.assertEqual(got, ["1.07", "2.57", "5.68", "9.79"])

    @rule("R10.3")
    def test_rebate_uses_the_first_occurrence(self):
        p = self.passage(vesselClass="WB", lengthDm=250, ladenTonnes="47.35", cargo="HAZ-B", locks=["K2", "K3", "K2"],
                         enteredAt="2026-03-14T23:30:00Z", operator="AB-102")
        self.assertEqual(p["toll"]["total"], "37.61")
        self.assertEqual(self.claim(p["id"], lock="K2", minutes=400)["eligibleRebate"], "11.44")
        self.assertEqual(self.claim(p["id"], lock="K3", minutes=150)["eligibleRebate"], "5.30")

    @rule("R10.3")
    def test_cap_applies_to_the_minimum_toll(self):
        p = self.passage(lengthDm=220, ladenTonnes="0", cargo="NONE", locks=["W1"])
        self.assertEqual(self.claim(p["id"], lock="W1", minutes=360)["eligibleRebate"], "3.00")

    @rule("R10.4")
    def test_claim_identifiers(self):
        p = self.passage()
        self.error(lodge(p["id"], lock="K6"), 422, "LOCK_NOT_ON_PASSAGE")
        self.assertEqual(self.claim(p["id"], lock="K1")["id"], "CLM-00001")
        self.assertEqual(self.claim(p["id"], lock="K2")["id"], "CLM-00002")

    @rule("R10.6")
    def test_get_claim_carries_etag(self):
        c = self.claim(self.passage()["id"])
        self.moved(c["id"], 1, "withdraw")
        r = call("GET", "/claims/" + c["id"])
        self.assertEqual(self.ok(r, 200)["state"], "WITHDRAWN")
        self.assertEqual(r.header("ETag"), '"2"')
        self.error(call("GET", "/claims/CLM-00009"), 404, "NOT_FOUND", None)

    @rule("R10.7")
    def test_claim_replay_returns_the_stored_response(self):
        p = self.passage()
        body = {"passageId": p["id"], "lock": "K2", "delayMinutes": 90, "reason": "MECHANICAL"}
        first = call("POST", "/claims", body, {"Idempotency-Key": "claim-key-1", "X-Actor": "skipper.jo"})
        c = self.ok(first, 201)
        self.moved(c["id"], 1, "assess", assessedMinutes=60)
        again = call("POST", "/claims", body, {"Idempotency-Key": "claim-key-1", "X-Actor": "someone.else"})
        self.assertEqual(self.ok(again, 201), c)
        self.assertEqual((again.header("ETag"), again.header("Idempotent-Replay")), ('"1"', "true"))
        self.error(call("POST", "/claims", dict(body, delayMinutes=91), {"Idempotency-Key": "claim-key-1"}),
                   409, "IDEMPOTENCY_CONFLICT", "Idempotency-Key")
        self.assertEqual(len(self.ok(call("GET", "/claims/%s/audit" % c["id"]), 200)["entries"]), 2)


class Workflow(Case):
    def assessed(self, minutes=90, assessed=90, actor="clerk.ann", **kw):
        c = self.claim(self.passage(**kw)["id"], minutes=minutes)
        return self.moved(c["id"], 1, "assess", actor, assessedMinutes=assessed)

    @rule("R11.1")
    def test_header_checks_in_order(self):
        c = self.claim(self.passage()["id"])
        url = "/claims/%s/transitions" % c["id"]
        self.error(call("POST", "/claims/CLM-00099/transitions", {"action": "withdraw"}), 404, "NOT_FOUND")
        for bad in ["1", "W/\"1\"", "\"one\"", "\"\""]:
            self.error(call("POST", url, raw=b"{", headers={"If-Match": bad}), 400, "INVALID_HEADER", "If-Match")
        self.error(call("POST", url, raw=b"{", headers={"If-Match": '"2"'}), 412, "VERSION_MISMATCH", "If-Match")
        self.error(call("POST", url, raw=b"{", headers={"If-Match": '"1"'}), 400, "MALFORMED_JSON")

    @rule("R11.1")
    def test_body_checks_in_order(self):
        c = self.claim(self.passage()["id"])
        self.error(self.move(c["id"], 1, "dismiss", actor=None), 400, "FIELD_FORMAT", "action")
        self.error(call("POST", "/claims/%s/transitions" % c["id"], {}, {"If-Match": '"1"'}),
                   400, "FIELD_REQUIRED", "action")
        self.error(self.move(c["id"], 1, "withdraw", actor=None), 400, "FIELD_REQUIRED", "X-Actor")
        self.error(self.move(c["id"], 1, "withdraw", actor="Ann"), 400, "FIELD_FORMAT", "X-Actor")
        self.error(self.move(c["id"], 1, "settle", reference="bad"), 409, "TRANSITION_FORBIDDEN", "action")
        self.error(self.move(c["id"], 1, "assess", assessedMinutes=91), 400, "FIELD_FORMAT", "assessedMinutes")
        self.error(self.move(c["id"], 1, "assess"), 400, "FIELD_REQUIRED", "assessedMinutes")

    @rule("R11.1")
    def test_forbidden_transitions(self):
        c = self.claim(self.passage()["id"])
        for action in ["approve", "reject", "settle", "reopen"]:
            self.error(self.move(c["id"], 1, action), 409, "TRANSITION_FORBIDDEN", "action")
        self.moved(c["id"], 1, "withdraw")
        for action in ["assess", "withdraw", "reopen"]:
            self.error(self.move(c["id"], 2, action, assessedMinutes=1), 409, "TRANSITION_FORBIDDEN", "action")

    @rule("R11.2")
    def test_failed_transition_changes_nothing(self):
        c = self.claim(self.passage()["id"])
        self.error(self.move(c["id"], 1, "assess", assessedMinutes=-1), 400, "FIELD_FORMAT")
        r = call("GET", "/claims/" + c["id"])
        self.assertEqual(self.ok(r, 200), c)

    @rule("R11.2")
    def test_success_bumps_version_and_etag(self):
        c = self.claim(self.passage()["id"], minutes=400)
        self.clock("2026-03-20T15:00:00Z")
        r = self.move(c["id"], 1, "assess", assessedMinutes=130)
        a = self.ok(r, 200)
        self.assertEqual(r.header("ETag"), '"2"')
        self.assertEqual((a["version"], a["state"], a["updatedAt"], a["lodgedAt"]),
                         (2, "ASSESSED", "2026-03-20T15:00:00Z", NOW))
        self.assertEqual((a["assessedMinutes"], a["assessedRebate"], a["assessedBy"], a["eligibleRebate"]),
                         (130, "5.14", "clerk.ann", "8.91"))

    @rule("R11.4")
    def test_approval_amounts(self):
        a = self.assessed()
        self.error(self.move(a["id"], 2, "approve", "clerk.bob", amount="2.15"), 422, "AMOUNT_EXCEEDS", "amount")
        self.error(self.move(a["id"], 2, "approve", "clerk.bob", amount="0.00"), 400, "FIELD_FORMAT", "amount")
        self.error(self.move(a["id"], 2, "approve", "clerk.bob", amount="1.5"), 400, "FIELD_FORMAT", "amount")
        self.error(self.move(a["id"], 2, "approve", "clerk.bob", amount=1.5), 400, "FIELD_TYPE", "amount")
        self.clock("2026-03-20T16:00:00Z")
        ok = self.moved(a["id"], 2, "approve", "clerk.bob", amount="1.99")
        self.assertEqual((ok["approvedAmount"], ok["approvedBy"], ok["approvedAt"]),
                         ("1.99", "clerk.bob", "2026-03-20T16:00:00Z"))

    @rule("R11.4")
    def test_nothing_to_approve(self):
        a = self.assessed(assessed=44)
        self.assertEqual(a["assessedRebate"], "0.00")
        self.error(self.move(a["id"], 2, "approve", "clerk.bob"), 422, "NOTHING_TO_APPROVE", None)
        self.error(self.move(a["id"], 2, "approve", "clerk.ann"), 403, "SAME_ACTOR", "X-Actor")
        self.moved(a["id"], 2, "reject", "clerk.bob", note="Under threshold")

    @rule("R11.5")
    def test_settlement_waits_two_days(self):
        a = self.assessed()
        self.moved(a["id"], 2, "approve", "clerk.bob")
        self.clock("2026-03-22T11:59:59Z")
        self.error(self.move(a["id"], 3, "settle", reference="STL-00000001"), 422, "SETTLEMENT_TOO_EARLY", None)
        self.error(self.move(a["id"], 3, "settle", reference="STL-0000001"), 400, "FIELD_FORMAT", "reference")
        self.clock("2026-03-22T12:00:00Z")
        s = self.moved(a["id"], 3, "settle", reference="STL-00000001")
        self.assertEqual((s["state"], s["settlementReference"], s["version"]), ("SETTLED", "STL-00000001", 4))
        for action in ["withdraw", "reopen", "settle"]:
            self.error(self.move(a["id"], 4, action, reference="STL-00000002"), 409, "TRANSITION_FORBIDDEN")

    @rule("R11.6")
    def test_reject_and_reopen_once(self):
        a = self.assessed()
        self.error(self.move(a["id"], 2, "reject", note=""), 400, "FIELD_FORMAT", "note")
        self.error(self.move(a["id"], 2, "reject", note="n" * 201), 400, "FIELD_FORMAT", "note")
        r = self.moved(a["id"], 2, "reject", note="Lock log shows no stoppage")
        self.assertEqual((r["state"], r["rejectedAt"]), ("REJECTED", NOW))
        self.clock("2026-03-27T12:00:00Z")
        o = self.moved(a["id"], 3, "reopen", "clerk.cy")
        self.assertEqual((o["state"], o["reopenCount"], o["assessedMinutes"], o["assessedRebate"], o["assessedBy"],
                          o["rejectedAt"], o["eligibleRebate"]), ("LODGED", 1, None, None, None, None, "2.14"))
        self.moved(o["id"], 4, "assess", "clerk.cy", assessedMinutes=10)
        self.moved(o["id"], 5, "reject", "clerk.dee", note="Again")
        self.error(self.move(o["id"], 6, "reopen"), 409, "REOPEN_LIMIT", None)

    @rule("R11.6")
    def test_reopen_window(self):
        a = self.assessed()
        self.moved(a["id"], 2, "reject", note="No")
        self.clock("2026-03-27T12:00:01Z")
        self.error(self.move(a["id"], 3, "reopen"), 422, "CLAIM_WINDOW_CLOSED", None)

    @rule("R11.6")
    def test_reopen_refused_while_another_claim_is_live(self):
        a = self.assessed()
        self.moved(a["id"], 2, "reject", note="No")
        other = self.claim(a["passageId"], lock="K2", minutes=60)
        self.error(self.move(a["id"], 3, "reopen"), 409, "CLAIM_EXISTS", "lock")
        self.moved(other["id"], 1, "withdraw")
        self.moved(a["id"], 3, "reopen")

    @rule("R11.7")
    def test_withdraw_paths(self):
        a = self.assessed()
        w = self.moved(a["id"], 2, "withdraw", "skipper.jo")
        self.assertEqual((w["state"], w["assessedRebate"]), ("WITHDRAWN", "2.14"))
        b = self.claim(a["passageId"], lock="K1")
        self.moved(b["id"], 1, "assess", assessedMinutes=90)
        self.moved(b["id"], 2, "approve", "clerk.bob")
        self.error(self.move(b["id"], 3, "withdraw"), 409, "TRANSITION_FORBIDDEN", "action")

    @rule("R0.3")
    def test_concurrent_transitions_on_one_version(self):
        c = self.claim(self.passage()["id"])
        statuses = []
        barrier = threading.Barrier(8)

        def go(i):
            barrier.wait()
            statuses.append(self.move(c["id"], 1, "assess", "clerk.n%d" % i, assessedMinutes=i).status)
        threads = [threading.Thread(target=go, args=(i,)) for i in range(8)]
        for t in threads:
            t.start()
        for t in threads:
            t.join()
        self.assertEqual(sorted(statuses), [200] + [412] * 7)
        self.assertEqual(self.ok(call("GET", "/claims/" + c["id"]), 200)["version"], 2)


class Audit(Case):
    @rule("R12.2")
    def test_full_trail(self):
        c = self.claim(self.passage()["id"])
        self.moved(c["id"], 1, "assess", "clerk.ann", assessedMinutes=90)
        self.moved(c["id"], 2, "reject", "clerk.bob", note="Not our fault")
        self.clock("2026-03-21T09:00:00Z")
        self.moved(c["id"], 3, "reopen", "skipper.jo")
        r = self.ok(call("GET", "/claims/%s/audit" % c["id"]), 200)
        self.assertEqual([(e["seq"], e["actor"], e["action"], e["fromState"], e["toState"], e["version"], e["note"])
                          for e in r["entries"]], [
            (1, "anonymous", "lodge", None, "LODGED", 1, None),
            (2, "clerk.ann", "assess", "LODGED", "ASSESSED", 2, None),
            (3, "clerk.bob", "reject", "ASSESSED", "REJECTED", 3, "Not our fault"),
            (4, "skipper.jo", "reopen", "REJECTED", "LODGED", 4, None)])
        self.assertEqual(r["entries"][3]["at"], "2026-03-21T09:00:00Z")

    @rule("R12.3")
    def test_failures_and_replays_add_nothing(self):
        p = self.passage()
        body = {"passageId": p["id"], "lock": "K2", "delayMinutes": 90, "reason": "MECHANICAL"}
        c = self.ok(call("POST", "/claims", body, {"Idempotency-Key": "audit-key-1"}), 201)
        self.ok(call("POST", "/claims", body, {"Idempotency-Key": "audit-key-1"}), 201)
        self.error(self.move(c["id"], 1, "approve"), 409, "TRANSITION_FORBIDDEN")
        self.error(self.move(c["id"], 7, "withdraw"), 412, "VERSION_MISMATCH")
        self.assertEqual(len(self.ok(call("GET", "/claims/%s/audit" % c["id"]), 200)["entries"]), 1)

    @rule("R12.1")
    def test_audit_of_unknown_claim(self):
        self.error(call("GET", "/claims/CLM-00001/audit"), 404, "NOT_FOUND", None)


class Statement(Case):
    URL = "/reports/operator-statement?operator=%s&month=%s"

    @rule("R13.1")
    def test_parameters(self):
        self.error(call("GET", "/reports/operator-statement?month=2026-03"), 400, "INVALID_QUERY", "operator")
        self.error(call("GET", "/reports/operator-statement"), 400, "INVALID_QUERY", "operator")
        for m in ["2026-13", "2026-00", "2026-3", "", "202603"]:
            self.error(call("GET", self.URL % ("KV-209", m)), 400, "INVALID_QUERY", "month")
        self.error(call("GET", self.URL % ("QD-737", "2026-03")), 404, "NOT_FOUND")

    @rule("R13.3")
    def test_cargo_order_and_busiest_lock(self):
        self.passage(cargo="AGG", locks=["K4", "K5"])
        self.passage(cargo="LIV", locks=["K4", "K5"])
        self.passage(cargo="GEN", locks=["K1", "K2", "K1", "K2"])
        self.passage(cargo="GEN", locks=["K6", "K5"])
        self.passage(operator="AB-102", cargo="HAZ-B", locks=["K1"])
        r = self.ok(call("GET", self.URL % ("KV-209", "2026-03")), 200)
        totals = [p["toll"]["total"] for p in self.ok(call("GET", "/passages?operator=KV-209"), 200)["items"]]
        self.assertEqual(r["passages"], 4)
        self.assertEqual(r["byCargo"], [{"cargo": "GEN", "passages": 2, "tollTotal": "41.68"},
                                        {"cargo": "LIV", "passages": 1, "tollTotal": "18.74"},
                                        {"cargo": "AGG", "passages": 1, "tollTotal": "18.13"}])
        self.assertEqual(r["tollTotal"], "78.55")
        self.assertEqual(len(totals), 4)
        self.assertEqual(r["busiestLock"], {"lock": "K5", "passages": 3})

    @rule("R13.3")
    def test_ties_break_by_cargo_code_and_table_order(self):
        self.passage(cargo="LIV", ladenTonnes="1", locks=["W3"])
        self.passage(cargo="AGG", ladenTonnes="1", locks=["W2"])
        r = self.ok(call("GET", self.URL % ("KV-209", "2026-03")), 200)
        self.assertEqual(r["byCargo"], [{"cargo": "AGG", "passages": 1, "tollTotal": "7.50"},
                                        {"cargo": "LIV", "passages": 1, "tollTotal": "7.50"}])
        self.assertEqual(r["busiestLock"], {"lock": "W2", "passages": 1})

    @rule("R13.3")
    def test_claims_and_rebates(self):
        p1, p2 = self.passage(), self.passage()
        settled = self.claim(p1["id"], lock="K2", minutes=90)
        self.moved(settled["id"], 1, "assess", assessedMinutes=90)
        self.moved(settled["id"], 2, "approve", "clerk.bob")
        approved = self.claim(p1["id"], lock="K1", minutes=400)
        self.moved(approved["id"], 1, "assess", assessedMinutes=400)
        self.moved(approved["id"], 2, "approve", "clerk.bob", amount="5.00")
        self.claim(p2["id"], lock="K3")
        w = self.claim(p2["id"], lock="K1")
        self.moved(w["id"], 1, "withdraw")
        self.clock("2026-03-23T12:00:00Z")
        self.moved(settled["id"], 3, "settle", reference="STL-12345678")
        r = self.ok(call("GET", self.URL % ("KV-209", "2026-03")), 200)
        self.assertEqual(r["claims"], {"LODGED": 1, "ASSESSED": 0, "APPROVED": 1, "SETTLED": 1, "REJECTED": 0,
                                       "WITHDRAWN": 1})
        self.assertEqual((r["tollTotal"], r["rebatesApproved"], r["rebatesSettled"], r["net"]),
                         ("48.96", "5.00", "2.14", "46.82"))

    @rule("R13.2")
    def test_claims_follow_their_passage_month(self):
        p = self.passage(enteredAt="2026-02-28T23:59:59Z")
        self.passage(enteredAt="2026-03-01T00:00:00Z")
        self.clock("2026-03-05T00:00:00Z")
        self.claim(p["id"])
        feb = self.ok(call("GET", self.URL % ("KV-209", "2026-02")), 200)
        mar = self.ok(call("GET", self.URL % ("KV-209", "2026-03")), 200)
        self.assertEqual((feb["passages"], feb["claims"]["LODGED"]), (1, 1))
        self.assertEqual((mar["passages"], mar["claims"]["LODGED"]), (1, 0))

    @rule("R13.4")
    def test_empty_month(self):
        self.passage()
        r = self.ok(call("GET", self.URL % ("KV-209", "2025-11")), 200)
        self.assertEqual(r, {"operator": "KV-209", "month": "2025-11", "passages": 0, "tollTotal": "0.00",
                             "byCargo": [], "busiestLock": None,
                             "claims": {"LODGED": 0, "ASSESSED": 0, "APPROVED": 0, "SETTLED": 0, "REJECTED": 0,
                                        "WITHDRAWN": 0},
                             "rebatesApproved": "0.00", "rebatesSettled": "0.00", "net": "0.00"})
