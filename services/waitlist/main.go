// [INPUT]: environment WAITLIST_ADDR, WAITLIST_FILE, WAITLIST_RETURN_URL, WAITLIST_ORIGIN.
// [OUTPUT]: a loopback-only HTTP server for the Waitlist handler.
// [POS]: process configuration; waitlist.go owns behavior.
// [PROTOCOL]: keep README.md's environment table in sync.
package main

import (
	"fmt"
	"log"
	"net"
	"net/http"
	"os"
	"time"
)

func env(key, fallback string) string {
	if value := os.Getenv(key); value != "" {
		return value
	}
	return fallback
}

func main() {
	addr := env("WAITLIST_ADDR", "127.0.0.1:8091")
	if err := requireLoopback(addr); err != nil {
		log.Fatal(err)
	}
	waitlist, err := Open(Config{
		File:      env("WAITLIST_FILE", "/var/lib/writeitdown-waitlist/waitlist.tsv"),
		ReturnURL: env("WAITLIST_RETURN_URL", "https://writeitdown.app/mac.html"),
		Origin:    env("WAITLIST_ORIGIN", "https://writeitdown.app"),
		PerClient: 5,
		Global:    120,
		Window:    10 * time.Minute,
	})
	if err != nil {
		log.Fatal(err)
	}
	server := &http.Server{Addr: addr, Handler: waitlist, ReadHeaderTimeout: 5 * time.Second,
		ReadTimeout: 10 * time.Second, WriteTimeout: 10 * time.Second}
	log.Printf("waitlist listening on %s", addr)
	log.Fatal(server.ListenAndServe())
}

// requireLoopback keeps the X-Forwarded-For trust in clientAddress sound: only the local proxy can reach us.
func requireLoopback(addr string) error {
	host, _, err := net.SplitHostPort(addr)
	if err != nil {
		return err
	}
	if ip := net.ParseIP(host); host != "localhost" && (ip == nil || !ip.IsLoopback()) {
		return fmt.Errorf("WAITLIST_ADDR %q must be a loopback address behind the reverse proxy", addr)
	}
	return nil
}
