from lib import Case, call, rule


class Tariff(Case):
    def toll(self, tier="ordinary", **kw):
        r = self.quote(self.spec(tier=tier, **kw))["results"][0]
        self.assertIn("toll", r, "item should be priced: %r" % r)
        return r["toll"]

    @rule("R4.3")
    def test_length_factor_bands(self):
        self.assertEqual(self.fees(self.toll(lengthDm=210, locks=["K5", "K6"])), ["8.2450", "7.4800"])
        self.assertEqual(self.fees(self.toll(lengthDm=211, locks=["K5", "K6"])), ["9.4818", "8.6020"])
        t = self.toll(lengthDm=320, locks=["K5", "K6"])
        self.assertEqual(self.fees(t), ["10.8834", "9.8736"])
        self.assertEqual(t["total"], "21.28")

    @rule("R4.3")
    def test_second_occurrence_is_half_price(self):
        t = self.toll(locks=["K3", "K4", "K3"], cargo="NONE", ladenTonnes="0")
        self.assertEqual(self.fees(t), ["7.2550", "9.1900", "3.6275"])
        self.assertEqual((t["lockFeeTotal"], t["total"]), ("20.0725", "20.07"))

    @rule("R4.3")
    def test_narrow_locks_and_half_even_lock_fees(self):
        t = self.toll(locks=["K3", "W1", "W2", "W3", "W2"], lengthDm=220)
        self.assertEqual(self.fees(t), ["8.3432", "6.4802", "7.6188", "5.6005", "3.8094"])
        self.assertEqual((t["cargoSurcharge"], t["total"]), ("0.7963", "32.65"))

    @rule("R4.5")
    def test_weight_charge_starts_above_thirty_tonnes(self):
        t = self.toll(ladenTonnes="30.00", locks=["K1", "K2"])
        self.assertEqual((t["weightCharge"], t["total"]), ("0.0000", "17.04"))
        t = self.toll(ladenTonnes="31", locks=["K1", "K2"])
        self.assertEqual((t["weightCharge"], t["cargoSurcharge"], t["total"]), ("0.1450", "0.4192", "17.19"))

    @rule("R4.6")
    def test_cargo_rates(self):
        self.assertEqual(self.toll(cargo="LIV", ladenTonnes="20")["cargoSurcharge"], "1.7910")
        t = self.toll(vesselClass="DB", lengthDm=300, ladenTonnes="88", cargo="HAZ-A",
                      enteredAt="2026-03-19T23:59:59Z")
        self.assertEqual(self.fees(t), ["10.7640", "11.7760", "9.1080"])
        self.assertEqual([t[k] for k in ["weightCharge", "cargoSurcharge", "bandSurcharge", "total"]],
                         ["12.6150", "9.7379", "9.7202", "63.72"])

    @rule("R4.7")
    def test_night_band_edges(self):
        self.assertEqual(self.toll(enteredAt="2026-03-17T05:59:59Z")["bandSurcharge"], "4.4059")
        self.assertEqual(self.toll(enteredAt="2026-03-17T06:00:00Z")["bandSurcharge"], "0.0000")
        self.assertEqual(self.toll(enteredAt="2026-03-17T21:59:59Z")["bandSurcharge"], "0.0000")
        t = self.toll(enteredAt="2026-03-17T22:00:00Z")
        self.assertEqual((t["bandSurcharge"], t["total"]), ("4.4059", "28.88"))

    @rule("R4.7")
    def test_weekend_band_and_both(self):
        t = self.toll(enteredAt="2026-03-15T12:00:00Z")
        self.assertEqual((t["bandSurcharge"], t["total"]), ("1.4686", "25.95"))
        t = self.toll(vesselClass="TS", lengthDm=400, ladenTonnes="120.5", cargo="AGG",
                      locks=["K6", "K5", "K4", "K5"], enteredAt="2026-03-08T02:15:00Z")
        self.assertEqual(self.fees(t), ["11.7744", "14.1306", "17.0412", "7.0653"])
        self.assertEqual([t[k] for k in ["weightCharge", "cargoSurcharge", "bandSurcharge", "total"]],
                         ["26.2450", "3.0503", "19.8901", "99.20"])

    @rule("R4.8")
    def test_tier_discounts(self):
        t = self.toll("heritage")
        self.assertEqual((t["tierDiscount"], t["total"]), ("9.7908", "14.69"))
        t = self.toll("heritage", vesselClass="WB")
        self.assertEqual((t["tierDiscount"], t["total"]), ("0.0000", "26.88"))
        t = self.toll("contract")
        self.assertEqual((t["tierDiscount"], t["total"]), ("2.2029", "22.27"))

    @rule("R4.9")
    def test_total_rounds_half_up(self):
        t = self.toll(cargo="NONE", ladenTonnes="0", locks=["K1"])
        self.assertEqual((t["total"], t["minimumApplied"]), ("8.07", False))
        t = self.toll(cargo="NONE", ladenTonnes="0", locks=["K3", "K4"], tier="contract")
        self.assertEqual(t["total"], "14.97")

    @rule("R4.2")
    def test_lock_sequence_must_follow_the_network(self):
        for bad in [["K1", "K3"], ["K1", "K1"], ["W1", "K4"], ["K2", "K3", "K2", "K3", "K2"]]:
            self.assertEqual(self.quote(self.spec(locks=bad))["results"][0]["error"],
                             {"code": "LOCK_SEQUENCE_INVALID", "field": "locks"}, bad)
        self.assertIn("toll", self.quote(self.spec(locks=["K4", "K3", "W1", "W2", "W1", "K3"]))["results"][0])

    @rule("R4.2")
    def test_gauge_rules(self):
        self.assertIn("toll", self.quote(self.spec(locks=["W1"], lengthDm=220))["results"][0])
        for bad in [dict(lengthDm=221), dict(vesselClass="TS"), dict(vesselClass="DB")]:
            self.assertEqual(self.quote(self.spec(locks=["K3", "W1"], **bad))["results"][0]["error"],
                             {"code": "GAUGE_EXCEEDED", "field": "locks"})
        self.assertIn("toll", self.quote(self.spec(vesselClass="WB", lengthDm=450, locks=["K1"]))["results"][0])

    @rule("R4.2")
    def test_hazard_a_avoids_the_staircase(self):
        self.assertEqual(self.quote(self.spec(cargo="HAZ-A", locks=["K3", "K4"]))["results"][0]["error"],
                         {"code": "HAZARD_ROUTE", "field": "locks"})
        self.assertIn("toll", self.quote(self.spec(cargo="HAZ-B", locks=["K3", "K4"]))["results"][0])
        self.assertIn("toll", self.quote(self.spec(cargo="HAZ-A", locks=["K2", "K3"]))["results"][0])

    @rule("R4.2")
    def test_cargo_must_match_the_load(self):
        for bad in [dict(cargo="NONE", ladenTonnes="5"), dict(cargo="GEN", ladenTonnes="0.00")]:
            self.assertEqual(self.quote(self.spec(**bad))["results"][0]["error"],
                             {"code": "CARGO_MISMATCH", "field": "cargo"})
        self.assertIn("toll", self.quote(self.spec(cargo="NONE", ladenTonnes="0.0"))["results"][0])

    @rule("R4.2")
    def test_route_rules_are_checked_in_order(self):
        r = self.quote(self.spec(vesselClass="WB", cargo="NONE", locks=["K4", "W1"]),
                       self.spec(vesselClass="WB", cargo="HAZ-A", locks=["K4", "K3", "W1"]),
                       self.spec(cargo="HAZ-A", ladenTonnes="0", locks=["K4"]))
        self.assertEqual([x["error"]["code"] for x in r["results"]],
                         ["LOCK_SEQUENCE_INVALID", "GAUGE_EXCEEDED", "HAZARD_ROUTE"])

    @rule("R1.5")
    def test_specification_field_rules(self):
        cases = [(dict(ladenTonnes=12), "FIELD_TYPE", "ladenTonnes"),
                 (dict(ladenTonnes="1.234"), "FIELD_FORMAT", "ladenTonnes"),
                 (dict(ladenTonnes="400.01"), "FIELD_FORMAT", "ladenTonnes"),
                 (dict(ladenTonnes="-1"), "FIELD_FORMAT", "ladenTonnes"),
                 (dict(ladenTonnes=".5"), "FIELD_FORMAT", "ladenTonnes"),
                 (dict(lengthDm=39), "FIELD_FORMAT", "lengthDm"),
                 (dict(lengthDm=451), "FIELD_FORMAT", "lengthDm"),
                 (dict(locks=[]), "FIELD_FORMAT", "locks"),
                 (dict(locks=["K1", "K2"] * 6 + ["K1"]), "FIELD_FORMAT", "locks"),
                 (dict(locks=["K7"]), "FIELD_FORMAT", "locks"),
                 (dict(locks=["k1"]), "FIELD_FORMAT", "locks"),
                 (dict(locks="K1"), "FIELD_TYPE", "locks"),
                 (dict(locks=[1]), "FIELD_TYPE", "locks"),
                 (dict(cargo="HAZ"), "FIELD_FORMAT", "cargo")]
        r = self.quote(*[self.spec(**kw) for kw, _, _ in cases])
        self.assertEqual([x.get("error") for x in r["results"]], [{"code": c, "field": f} for _, c, f in cases])
        self.assertIn("toll", self.quote(self.spec(ladenTonnes="400", cargo="AGG"))["results"][0])


class Quotes(Case):
    @rule("R5.1")
    def test_batch_limit(self):
        self.error(call("POST", "/tariff/quotes", {"items": [{}] * 5001}), 413, "BATCH_TOO_LARGE", "items")
        r = self.quote(*([self.spec()] * 5000))
        self.assertEqual((r["count"], r["quoted"], r["grandTotal"]), (5000, 5000, "122400.00"))

    @rule("R5.1")
    def test_empty_batch(self):
        self.assertEqual(self.quote(), {"count": 0, "quoted": 0, "failed": 0, "grandTotal": "0.00",
                                        "results": []})

    @rule("R5.2")
    def test_items_must_be_an_array(self):
        self.error(call("POST", "/tariff/quotes", {"items": {}}), 400, "FIELD_TYPE", "items")
        self.error(call("POST", "/tariff/quotes", {}), 400, "FIELD_REQUIRED", "items")

    @rule("R5.2")
    def test_quotes_ignore_the_clock(self):
        r = self.quote(self.spec(enteredAt="2031-07-05T23:00:00Z"), self.spec(enteredAt="1999-01-01T00:00:00Z"))
        self.assertEqual(r["quoted"], 2)

    @rule("R5.3")
    def test_non_object_items(self):
        r = self.quote(7, "x", None, [self.spec()])
        self.assertEqual(r["results"], [{"ref": None, "error": {"code": "FIELD_TYPE", "field": None}}] * 4)
        self.assertEqual((r["failed"], r["grandTotal"]), (4, "0.00"))

    @rule("R5.4")
    def test_failed_item_ref_rules(self):
        r = self.quote(self.spec(ref=""), self.spec(ref="r" * 41), self.spec(ref=5), self.spec(ref="ok", tier="x"),
                       self.spec(ref=None))
        self.assertEqual(r["results"], [
            {"ref": None, "error": {"code": "FIELD_FORMAT", "field": "ref"}},
            {"ref": None, "error": {"code": "FIELD_FORMAT", "field": "ref"}},
            {"ref": None, "error": {"code": "FIELD_TYPE", "field": "ref"}},
            {"ref": "ok", "error": {"code": "FIELD_FORMAT", "field": "tier"}},
            {"ref": None, "error": {"code": "FIELD_REQUIRED", "field": "ref"}}])

    @rule("R5.5")
    def test_refs_need_not_be_unique_and_order_is_kept(self):
        r = self.quote(self.spec(ref="x", tier="contract"), self.spec(ref="x", locks=["K9"]), self.spec(ref="x"))
        self.assertEqual([x["ref"] for x in r["results"]], ["x", "x", "x"])
        self.assertEqual([x.get("toll", {}).get("total") for x in r["results"]], ["22.27", None, "24.48"])
        self.assertEqual(r["grandTotal"], "46.75")
