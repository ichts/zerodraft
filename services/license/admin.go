package main

import (
	"database/sql"
	"errors"
	"time"
)

func revoke(path, orderID string) error {
	db, err := sql.Open("sqlite", path)
	if err != nil {
		return err
	}
	defer db.Close()
	result, err := db.Exec("UPDATE licenses SET status='revoked',revoked_at=? WHERE order_id=?", time.Now().Unix(), orderID)
	if err != nil {
		return err
	}
	n, err := result.RowsAffected()
	if err != nil {
		return err
	}
	if n != 1 {
		return errors.New("order not found")
	}
	return nil
}
