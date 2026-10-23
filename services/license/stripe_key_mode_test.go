package main

import (
	"strings"
	"testing"
)

func stripeConfigureConfig(environment, key string) Config {
	return Config{
		Database:            "unused.db",
		ProductID:           "prod_fixture",
		Environment:         environment,
		StripeWebhookSecret: "local-webhook-fixture",
		StripeSecretKey:     key,
		StripePriceID:       "price_fixture",
	}
}

func TestStripeKeyModeDerivesModeFromAcceptedPrefixes(t *testing.T) {
	for _, tc := range []struct{ key, mode string }{
		{"sk_test_local_fixture", "test"},
		{"rk_test_local_fixture", "test"},
		{"sk_live_local_fixture", "live"},
		{"rk_live_local_fixture", "live"},
	} {
		if mode, ok := stripeKeyMode(tc.key); !ok || mode != tc.mode {
			t.Errorf("key mode for %s = %q, %v; want %q", tc.key, mode, ok, tc.mode)
		}
	}
	for _, key := range []string{"", "sk_test_", "rk_test_", "sk_live_", "rk_live_", "sk_live", "pk_live_fixture", "SK_LIVE_FIXTURE"} {
		if mode, ok := stripeKeyMode(key); ok || mode != "" {
			t.Errorf("unrecognised key %q accepted as %q", key, mode)
		}
	}
}

func TestStripeStartupAcceptsOnlyMatchingKeyMode(t *testing.T) {
	for _, tc := range []struct {
		name        string
		environment string
		key         string
		accepted    bool
	}{
		{"restricted test key in test", "test", "rk_test_local_fixture", true},
		{"restricted live key in live", "live", "rk_live_local_fixture", true},
		{"standard test key in test", "test", "sk_test_local_fixture", true},
		{"standard live key in live", "live", "sk_live_local_fixture", true},
		{"restricted test key in live", "live", "rk_test_local_fixture", false},
		{"restricted live key in test", "test", "rk_live_local_fixture", false},
		{"standard test key in live", "live", "sk_test_local_fixture", false},
		{"standard live key in test", "test", "sk_live_local_fixture", false},
		{"unknown prefix in live", "live", "pk_live_local_fixture", false},
		{"unknown prefix in test", "test", "pk_test_local_fixture", false},
		{"uppercase prefix in live", "live", "RK_LIVE_LOCAL_FIXTURE", false},
		{"prefix without trailing underscore in live", "live", "sk_live", false},
		{"bare standard prefix in live", "live", "sk_live_", false},
		{"bare restricted prefix in test", "test", "rk_test_", false},
		{"empty key in test", "test", "", false},
	} {
		t.Run(tc.name, func(t *testing.T) {
			cfg := stripeConfigureConfig(tc.environment, tc.key)
			err := configureStripe(&cfg)
			if tc.accepted && err != nil {
				t.Fatalf("matching key mode refused: %v", err)
			}
			if !tc.accepted && err == nil {
				t.Fatal("mismatched or unrecognised key mode accepted")
			}
		})
	}
}

func TestStripeKeyRefusalNeverEchoesTheKey(t *testing.T) {
	const body = "local_fixture_do_not_print_this"
	for _, tc := range []struct{ environment, key string }{
		{"live", "rk_test_" + body},
		{"test", "rk_live_" + body},
		{"live", "sk_test_" + body},
		{"test", "sk_live_" + body},
		{"live", "pk_live_" + body},
	} {
		cfg := stripeConfigureConfig(tc.environment, tc.key)
		err := configureStripe(&cfg)
		if err == nil {
			t.Fatalf("mismatched key started in %s mode", tc.environment)
		}
		if strings.Contains(err.Error(), tc.key) || strings.Contains(err.Error(), body) {
			t.Fatalf("refusal message echoed key material: %v", err)
		}
	}
}
