package main

import (
	"database/sql"
	"net/http"
	"path/filepath"
	"testing"
)

func TestLegacyEventMigration(t *testing.T) {
	f := setup(t)
	cfg := f.s.cfg
	cfg.Database = filepath.Join(t.TempDir(), "legacy.db")
	db, err := sql.Open("sqlite", cfg.Database)
	if err != nil {
		t.Fatal(err)
	}
	_, err = db.Exec(`CREATE TABLE webhook_events (event_id TEXT PRIMARY KEY, event_type TEXT NOT NULL, received_at INTEGER NOT NULL);
		INSERT INTO webhook_events VALUES ('legacy-event','order.completed',1);`)
	if err != nil {
		t.Fatal(err)
	}
	if err := db.Close(); err != nil {
		t.Fatal(err)
	}
	s, err := Open(cfg, f.s.now)
	if err != nil {
		t.Fatal(err)
	}
	f.s = s
	expect(t, f.event("legacy-event", "order.completed"), http.StatusConflict)
	expect(t, f.event("new-event", "order.completed"), http.StatusOK)
	if err := s.Close(); err != nil {
		t.Fatal(err)
	}
	s, err = Open(cfg, f.s.now)
	if err != nil {
		t.Fatal(err)
	}
	t.Cleanup(func() { s.Close() })
	f.s = s
	expect(t, f.event("new-event", "order.completed"), http.StatusOK)
	expect(t, f.event("new-event", "refund.succeeded"), http.StatusConflict)
}
