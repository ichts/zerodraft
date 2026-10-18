// [INPUT] An existing or newly created local SQLite license database.
// [OUTPUT] A replay-hash column without inventing hashes for legacy receipts.
// [POS] Storage upgrade for the provisional callback event ledger.
// [PROTOCOL] Keep this header and AGENTS.md aligned with README.md.
package main

import "database/sql"

func migrateEventHash(db *sql.DB) error {
	var count int
	if err := db.QueryRow(`SELECT count(*) FROM pragma_table_info('webhook_events') WHERE name='payload_hash'`).Scan(&count); err != nil {
		return err
	}
	if count != 0 {
		return nil
	}
	// Legacy receipts have no hash and must not acknowledge an unproven duplicate.
	_, err := db.Exec(`ALTER TABLE webhook_events ADD COLUMN payload_hash TEXT NOT NULL DEFAULT ''`)
	return err
}
