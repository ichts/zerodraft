package main

import (
	"crypto/x509"
	"encoding/pem"
	"net/http"
	"net/http/httptest"
	"os"
	"path/filepath"
	"strings"
	"testing"
)

func TestCaptureEnvironmentAndServerLifecycle(t *testing.T) {
	f := setup(t)
	privateDER, err := x509.MarshalPKCS8PrivateKey(f.s.cfg.TokenKey)
	if err != nil {
		t.Fatal(err)
	}
	keys := t.TempDir()
	privatePath := filepath.Join(keys, "generated-token.pem")
	publicPath := filepath.Join(keys, "generated-webhook.pem")
	if err := os.WriteFile(privatePath, pem.EncodeToMemory(&pem.Block{Type: "PRIVATE KEY", Bytes: privateDER}), 0600); err != nil {
		t.Fatal(err)
	}
	if err := os.WriteFile(publicPath, f.s.cfg.TestPublicKey, 0600); err != nil {
		t.Fatal(err)
	}
	path := captureDirectory(t)
	t.Setenv("LICENSE_ENVIRONMENT", "test")
	t.Setenv("LICENSE_PRODUCT_ID", f.s.cfg.ProductID)
	t.Setenv("LICENSE_TOKEN_PRIVATE_KEY_FILE", privatePath)
	t.Setenv("WAFFO_TEST_PUBLIC_KEY_FILE", publicPath)
	t.Setenv("LICENSE_TRUST_LOOPBACK_PROXY", "false")
	t.Setenv("LICENSE_CALLBACK_CAPTURE_DIR", path)
	cfg, err := environmentConfig(filepath.Join(t.TempDir(), "licenses.db"))
	if err != nil {
		t.Fatal(err)
	}
	s, err := Open(cfg, f.s.now)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	w := httptest.NewRecorder()
	r := httptest.NewRequest(http.MethodPost, "/api/v1/webhooks/waffo", strings.NewReader("{}"))
	s.Handler().ServeHTTP(w, r)
	if w.Code != 401 || len(capturePaths(t, path)) != 1 {
		t.Fatal("environment capture configuration not applied")
	}
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	if err := s.Close(); err != nil {
		t.Fatal("server close is no longer idempotent", err)
	}
}
