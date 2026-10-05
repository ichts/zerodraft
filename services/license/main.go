package main

import (
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"log"
	"net/http"
	"os"
	"time"
)

func readKey(path string) ([]byte, error) {
	if path == "" {
		return nil, errors.New("key file path required")
	}
	return os.ReadFile(path)
}
func main() {
	if err := run(os.Args[1:]); err != nil {
		log.Fatal(err)
	}
}
func run(args []string) error {
	if len(args) > 1 || len(args) == 1 && args[0] != "serve" && args[0] != "revoke" {
		return errors.New("usage: license [serve|revoke]; revoke takes LICENSE_ORDER_ID from environment")
	}
	dbPath := os.Getenv("LICENSE_DB")
	if dbPath == "" {
		return errors.New("LICENSE_DB required")
	}
	if len(args) == 1 && args[0] == "revoke" {
		orderID := os.Getenv("LICENSE_ORDER_ID")
		if orderID == "" {
			return errors.New("LICENSE_ORDER_ID required")
		}
		// Administrative revocation is offline and never exposed via HTTP.
		return revoke(dbPath, orderID)
	}
	pemBytes, err := readKey(os.Getenv("LICENSE_TOKEN_PRIVATE_KEY_FILE"))
	if err != nil {
		return err
	}
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return errors.New("invalid Ed25519 key PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return err
	}
	key, ok := parsed.(ed25519.PrivateKey)
	if !ok {
		return errors.New("Ed25519 private key required")
	}
	var testKey, productionKey []byte
	if os.Getenv("LICENSE_ENVIRONMENT") == "production" {
		productionKey, err = readKey(os.Getenv("WAFFO_PRODUCTION_PUBLIC_KEY_FILE"))
	} else {
		testKey, err = readKey(os.Getenv("WAFFO_TEST_PUBLIC_KEY_FILE"))
	}
	if err != nil {
		return err
	}
	s, err := Open(Config{Database: dbPath, ProductID: os.Getenv("LICENSE_PRODUCT_ID"), Environment: os.Getenv("LICENSE_ENVIRONMENT"), TestPublicKey: testKey, ProductionPublicKey: productionKey, TokenKey: key}, time.Now)
	if err != nil {
		return err
	}
	defer s.Close()
	addr := os.Getenv("LICENSE_LISTEN_ADDR")
	if addr == "" {
		addr = "127.0.0.1:8060"
	}
	server := &http.Server{Addr: addr, Handler: s.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, MaxHeaderBytes: 8 << 10}
	fmt.Printf("license server listening on %s\n", addr)
	return server.ListenAndServe()
}
