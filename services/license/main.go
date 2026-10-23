// [INPUT] Environment, restricted key files, optional capture directory and shutdown signals.
// [OUTPUT] A mode-gated loopback HTTP server or offline administrative revocation.
// [POS] Process entry point; deployment configuration stays outside source.
// [PROTOCOL] Keep this header and AGENTS.md aligned with README.md.
package main

import (
	"context"
	"crypto/ed25519"
	"crypto/x509"
	"encoding/pem"
	"errors"
	"fmt"
	"io"
	"log"
	"net"
	"net/http"
	"os"
	"os/signal"
	"strconv"
	"syscall"
	"time"
)

func readKey(path string, private bool) ([]byte, error) {
	if path == "" {
		return nil, errors.New("key file path required")
	}
	file, err := os.Open(path)
	if err != nil {
		return nil, errors.New("cannot open key file")
	}
	defer file.Close()
	info, err := file.Stat()
	if err != nil || !info.Mode().IsRegular() || info.Size() > 16<<10 {
		return nil, errors.New("key must be a regular file smaller than 16 KiB")
	}
	if private && info.Mode().Perm()&0077 != 0 {
		return nil, errors.New("private key file must not allow group or other access")
	}
	data, err := io.ReadAll(io.LimitReader(file, (16<<10)+1))
	if err != nil || len(data) > 16<<10 {
		return nil, errors.New("cannot read key file within size limit")
	}
	return data, nil
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
		return revoke(dbPath, orderID)
	}
	cfg, err := environmentConfig(dbPath)
	if err != nil {
		return err
	}
	addr, err := listenAddress(os.Getenv("LICENSE_LISTEN_ADDR"))
	if err != nil {
		return err
	}
	s, err := Open(cfg, time.Now)
	if err != nil {
		return err
	}
	defer s.Close()
	server := &http.Server{Addr: addr, Handler: s.Handler(), ReadHeaderTimeout: 5 * time.Second, ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second, IdleTimeout: 30 * time.Second, MaxHeaderBytes: 8 << 10}
	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGINT, syscall.SIGTERM)
	defer stop()
	return serve(ctx, server)
}

func environmentConfig(dbPath string) (Config, error) {
	cfg := Config{Database: dbPath, ProductID: os.Getenv("LICENSE_PRODUCT_ID"), Environment: os.Getenv("LICENSE_ENVIRONMENT"), CaptureDirectory: os.Getenv("LICENSE_CALLBACK_CAPTURE_DIR")}
	cfg.Provider = os.Getenv("LICENSE_PROVIDER")
	if cfg.Environment != "test" && !(cfg.Provider == "stripe" && cfg.Environment == "live") {
		return cfg, errors.New("LICENSE_ENVIRONMENT must be test, or live with Stripe")
	}
	if value := os.Getenv("LICENSE_TRUST_LOOPBACK_PROXY"); value != "" {
		var err error
		cfg.TrustLoopbackProxy, err = strconv.ParseBool(value)
		if err != nil {
			return cfg, errors.New("LICENSE_TRUST_LOOPBACK_PROXY must be a boolean")
		}
	}
	pemBytes, err := readKey(os.Getenv("LICENSE_TOKEN_PRIVATE_KEY_FILE"), true)
	if err != nil {
		return cfg, err
	}
	block, _ := pem.Decode(pemBytes)
	if block == nil {
		return cfg, errors.New("invalid Ed25519 key PEM")
	}
	parsed, err := x509.ParsePKCS8PrivateKey(block.Bytes)
	if err != nil {
		return cfg, errors.New("invalid Ed25519 private key")
	}
	key, ok := parsed.(ed25519.PrivateKey)
	if !ok {
		return cfg, errors.New("Ed25519 private key required")
	}
	cfg.TokenKey = key
	if cfg.Provider == "stripe" {
		cfg.StripeWebhookSecret = os.Getenv("STRIPE_WEBHOOK_SECRET")
		cfg.StripeSecretKey = os.Getenv("STRIPE_SECRET_KEY")
		cfg.StripePriceID = os.Getenv("STRIPE_PRICE_ID")
		cfg.StripeAPIBase = os.Getenv("STRIPE_API_BASE")
		if cfg.ProductID == "" {
			cfg.ProductID = os.Getenv("STRIPE_PRODUCT_ID")
		}
		err = configureStripe(&cfg)
		return cfg, err
	}
	cfg.TestPublicKey, err = readKey(os.Getenv("WAFFO_TEST_PUBLIC_KEY_FILE"), false)
	return cfg, err
}

func listenAddress(value string) (string, error) {
	if value == "" {
		return "127.0.0.1:8060", nil
	}
	host, port, err := net.SplitHostPort(value)
	ip := net.ParseIP(host)
	number, portErr := strconv.Atoi(port)
	if err != nil || ip == nil || !ip.IsLoopback() || portErr != nil || number < 1 || number > 65535 {
		return "", errors.New("LICENSE_LISTEN_ADDR must be a loopback IP and valid port")
	}
	return value, nil
}

func serve(ctx context.Context, server *http.Server) error {
	listener, err := net.Listen("tcp", server.Addr)
	if err != nil {
		return err
	}
	defer listener.Close()
	result := make(chan error, 1)
	go func() { result <- server.Serve(listener) }()
	fmt.Printf("license server listening on %s\n", listener.Addr())
	select {
	case err := <-result:
		return err
	case <-ctx.Done():
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 15*time.Second)
		defer cancel()
		if err := server.Shutdown(shutdownCtx); err != nil {
			server.Close()
			return err
		}
		return nil
	}
}
