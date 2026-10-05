package main

import (
	"database/sql"
	"time"
)

func revoke(path, orderID string) error {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return err
	}
	defer db.Close()
	now := time.Now().Unix()
	_, err = db.Exec(`INSERT INTO licenses(id,order_id,status,created_at,revoked_at) VALUES(?,?,?,?,?)
		ON CONFLICT(order_id) DO UPDATE SET status='revoked',revoked_at=excluded.revoked_at`, randomID(), orderID, "revoked", now, now)
	return err
}
