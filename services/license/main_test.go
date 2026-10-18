package main

import (
	"os"
	"path/filepath"
	"testing"
)

func TestListenAddressMustBeLoopback(t *testing.T) {
	for _, address := range []string{"", "127.0.0.1:8060", "[::1]:8060"} {
		if _, err := listenAddress(address); err != nil {
			t.Errorf("loopback address rejected: %v", err)
		}
	}
	for _, address := range []string{":8060", "0.0.0.0:8060", "[::]:8060", "203.0.113.1:8060", "localhost:8060", "127.0.0.1:0", "127.0.0.1:65536"} {
		if _, err := listenAddress(address); err == nil {
			t.Errorf("unsafe address accepted: %s", address)
		}
	}
}

func TestPrivateKeyPermissions(t *testing.T) {
	path := filepath.Join(t.TempDir(), "key.pem")
	if err := os.WriteFile(path, []byte("not-a-real-key"), 0600); err != nil {
		t.Fatal(err)
	}
	if _, err := readKey(path, true); err != nil {
		t.Fatal(err)
	}
	if err := os.Chmod(path, 0644); err != nil {
		t.Fatal(err)
	}
	if _, err := readKey(path, true); err == nil {
		t.Fatal("world-readable private key accepted")
	}
	if _, err := readKey(path, false); err != nil {
		t.Fatal("public key does not need secret permissions", err)
	}
	if _, err := readKey(filepath.Dir(path), true); err == nil {
		t.Fatal("directory accepted as key file")
	}
}

func TestEnvironmentConfigRejectsProductionBeforeReadingKeys(t *testing.T) {
	t.Setenv("LICENSE_ENVIRONMENT", "production")
	if _, err := environmentConfig("unused.db"); err == nil || err.Error() != "LICENSE_ENVIRONMENT must be test" {
		t.Fatal("production configuration was not rejected", err)
	}
}
