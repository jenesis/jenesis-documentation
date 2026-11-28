from lib import Case, call, rule, MISSING, NOW


class General(Case):
    @rule("R1.3")
    def test_trailing_slash_and_wrong_method_do_not_match(self):
        self.error(call("GET", "/passages/"), 404, "ROUTE_NOT_FOUND", None)
        self.error(call("DELETE", "/operators/KV-209"), 404, "ROUTE_NOT_FOUND", None)
        self.error(call("GET", "/Passages"), 404, "ROUTE_NOT_FOUND", None)

    @rule("R1.4")
    def test_array_and_empty_bodies_are_malformed(self):
        self.error(call("POST", "/passages", [self.body()]), 400, "MALFORMED_JSON", None)
        self.error(call("POST", "/passages", raw=b""), 400, "MALFORMED_JSON", None)
        self.error(call("PUT", "/admin/clock", "2026-03-01T00:00:00Z"), 400, "MALFORMED_JSON", None)

    @rule("R1.5")
    def test_integer_field_types(self):
        for bad in ["180", 180.5, True, [180]]:
            self.error(call("POST", "/passages", self.body(lengthDm=bad)), 400, "FIELD_TYPE", "lengthDm")

    @rule("R1.5")
    def test_absent_and_null_are_required(self):
        self.error(call("POST", "/passages", self.body(cargo=MISSING)), 400, "FIELD_REQUIRED", "cargo")
        self.error(call("POST", "/passages", self.body(cargo=None)), 400, "FIELD_REQUIRED", "cargo")

    @rule("R1.5")
    def test_first_failing_field_in_table_order_is_reported(self):
        self.error(call("POST", "/passages", self.body(locks="K1", vesselClass="XX", lengthDm=10)),
                   400, "FIELD_FORMAT", "vesselClass")
        self.error(call("POST", "/passages", self.body(enteredAt=5, lengthDm=10)), 400, "FIELD_FORMAT", "lengthDm")

    @rule("R1.6")
    def test_unknown_fields_are_ignored(self):
        p = self.ok(call("POST", "/passages", self.body(colour="green", Cargo="AGG")), 201)
        self.assertNotIn("colour", p)
        self.assertEqual(p["cargo"], "GEN")

    @rule("R1.7")
    def test_field_errors_precede_semantic_errors(self):
        self.error(call("POST", "/passages", self.body(operator="QD-737", lengthDm=500)),
                   400, "FIELD_FORMAT", "lengthDm")

    @rule("R1.8")
    def test_timestamps_must_be_exact_utc(self):
        for bad in ["2026-02-30T10:00:00Z", "2026-03-01T24:00:00Z", "2026-03-17T10:00:00+00:00",
                    "2026-03-17T10:00:00.000Z", "2026-03-17 10:00:00Z", "2026-03-17T10:00Z"]:
            self.error(call("POST", "/passages", self.body(enteredAt=bad)), 400, "FIELD_FORMAT", "enteredAt")

    @rule("R1.2")
    def test_error_body_shape(self):
        r = call("GET", "/operators/ZZ-999")
        self.assertEqual(r.status, 404)
        self.assertEqual(set(r.body.keys()), {"error"})
        self.assertIn("message", r.body["error"])
        self.assertIsNone(r.body["error"]["field"])
