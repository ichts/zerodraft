package main

import (
	"encoding/json"
	"strings"
	"testing"
	"time"
)

func TestStripeHeaderRotationCompatibility(t *testing.T) {
	cases := []struct {
		name   string
		header func(string, *Server, []byte) string
		status int
	}{
		{"bad v1 good v1 and v0", func(h string, _ *Server, _ []byte) string {
			p := strings.Split(h, ",")
			return p[0] + ",v1=" + strings.Repeat("0", 64) + "," + p[1] + ",v0=x"
		}, 200},
		{"v0 before valid signature", func(h string, _ *Server, _ []byte) string { return "v0=bad," + h }, 200},
		{"unknown key with valid signature", func(h string, _ *Server, _ []byte) string { return h + ",future_scheme=unknown" }, 200},
		{"only bad v1", func(h string, _ *Server, _ []byte) string {
			return strings.Split(h, ",")[0] + ",v1=" + strings.Repeat("0", 64)
		}, 401},
		{"no v1", func(h string, _ *Server, _ []byte) string { return strings.Split(h, ",")[0] + ",v0=bad" }, 401},
		{"duplicate t", func(h string, _ *Server, _ []byte) string { return h + "," + strings.Split(h, ",")[0] }, 401},
		{"stale t", func(_ string, s *Server, b []byte) string {
			return stripeHeader(s.cfg.StripeWebhookSecret, b, s.now().Add(-301*time.Second))
		}, 401},
		{"malformed v1 hex", func(h string, _ *Server, _ []byte) string { return h + ",v1=" + strings.Repeat("z", 64) }, 401},
	}
	for _, c := range cases {
		t.Run(c.name, func(t *testing.T) {
			s := stripeServer(t)
			body, _ := json.Marshal(stripeFixture("checkout.session.completed"))
			header := c.header(stripeHeader(s.cfg.StripeWebhookSecret, body, s.now()), s, body)
			w := stripeRawRequest(s, body, header)
			expect(t, w, c.status)
			wantRows := 0
			if c.status == 200 {
				wantRows = 1
			} else if w.Body.String() != "invalid signature\n" {
				t.Fatal("non-generic signature rejection")
			}
			if stripeRows(t, s, "licenses") != wantRows {
				t.Fatal("signature gate did not protect issuance")
			}
		})
	}
}
