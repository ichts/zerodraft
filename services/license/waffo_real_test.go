//go:build wafforeal

package main

import (
	"crypto/sha256"
	"crypto/x509"
	"encoding/base64"
	"encoding/hex"
	"encoding/json"
	"io"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"testing"
	"time"
)

type realVectorHash struct {
	BodySHA256     string `json:"bodySHA256"`
	MetadataSHA256 string `json:"metadataSHA256"`
}

type realVectorManifest struct {
	Version             int              `json:"version"`
	PublicKeyFileSHA256 string           `json:"publicKeyFileSHA256"`
	PublicKeySPKISHA256 string           `json:"publicKeySPKISHA256"`
	Records             []realVectorHash `json:"records"`
}

type realVector struct {
	body     []byte
	metadata captureMetadata
}

func vectorDigest(value []byte) string {
	hash := sha256.Sum256(value)
	return hex.EncodeToString(hash[:])
}

func privateVectorFile(t *testing.T, root *os.Root, name string, limit int64) []byte {
	t.Helper()
	info, err := root.Lstat(name)
	if err != nil || !info.Mode().IsRegular() || info.Mode().Perm() != 0600 || info.Size() > limit {
		t.Fatal("private fixture file missing, unsafe or oversized")
	}
	file, err := root.Open(name)
	if err != nil {
		t.Fatal("private fixture file unreadable")
	}
	defer file.Close()
	opened, err := file.Stat()
	if err != nil || !os.SameFile(info, opened) {
		t.Fatal("private fixture file changed")
	}
	data, err := io.ReadAll(io.LimitReader(file, limit+1))
	if err != nil || int64(len(data)) > limit {
		t.Fatal("private fixture read limit exceeded")
	}
	return data
}

func readRealVectors(t *testing.T, path string, manifest realVectorManifest) map[string]realVector {
	t.Helper()
	if !filepath.IsAbs(path) {
		t.Fatal("WAFFO_REAL_CAPTURE_DIR must explicitly name a private absolute fixture path")
	}
	root, err := os.OpenRoot(path)
	if err != nil {
		t.Fatal("private real fixture directory unavailable")
	}
	defer root.Close()
	dir, err := root.Open(".")
	if err != nil {
		t.Fatal("private fixture inventory unavailable")
	}
	defer dir.Close()
	entries, err := dir.ReadDir(captureCountLimit + 4)
	if err != nil && err != io.EOF || len(entries) > captureCountLimit+3 {
		t.Fatal("private fixture inventory exceeds the bounded input contract")
	}
	wanted := make(map[string]string)
	for _, item := range manifest.Records {
		wanted[item.MetadataSHA256] = item.BodySHA256
	}
	found := make(map[string]realVector)
	for _, entry := range entries {
		if _, ok := captureTime(entry.Name()); !ok {
			continue
		}
		info, err := root.Lstat(entry.Name())
		if err != nil || !info.IsDir() || info.Mode().Perm() != 0700 {
			t.Fatal("private capture record must be a real directory with mode 0700")
		}
		record, err := root.OpenRoot(entry.Name())
		if err != nil {
			t.Fatal("private capture record unavailable")
		}
		raw := privateVectorFile(t, record, "request.json", captureHeaderLimit)
		metadataHash := vectorDigest(raw)
		bodyHash, needed := wanted[metadataHash]
		if !needed {
			record.Close()
			continue
		}
		body := privateVectorFile(t, record, "body.bin", callbackBodyLimit)
		record.Close()
		var metadata captureMetadata
		if vectorDigest(body) != bodyHash || json.Unmarshal(raw, &metadata) != nil || metadata.ReceivedAt.IsZero() {
			t.Fatal("private vector differs from its committed hash manifest")
		}
		if _, exists := found[metadataHash]; exists {
			t.Fatal("duplicate private vector metadata")
		}
		found[metadataHash] = realVector{body: body, metadata: metadata}
	}
	if len(found) != 9 || len(wanted) != 9 || len(manifest.Records) != 9 {
		t.Fatal("all nine approved private real vectors are required; no silent skips")
	}
	return found
}

// Raw buyer data stays outside Git. The committed manifest owns only evidence hashes.
func TestWaffoRealCallbackVectors(t *testing.T) {
	raw, err := os.ReadFile("testdata/waffo-real-vector-hashes.json")
	var manifest realVectorManifest
	if err != nil || json.Unmarshal(raw, &manifest) != nil || manifest.Version != 1 {
		t.Fatal("real-vector hash manifest unavailable")
	}
	keyPEM, err := readKey(os.Getenv("WAFFO_REAL_TEST_PUBLIC_KEY_FILE"), false)
	if err != nil || vectorDigest(keyPEM) != manifest.PublicKeyFileSHA256 {
		t.Fatal("explicit deployed TEST public-key copy does not match the evidence manifest")
	}
	key, err := webhookKey(Config{TestPublicKey: keyPEM})
	if err != nil {
		t.Fatal("deployed TEST public key is invalid")
	}
	der, err := x509.MarshalPKIXPublicKey(key)
	if err != nil || vectorDigest(der) != manifest.PublicKeySPKISHA256 {
		t.Fatal("deployed TEST SPKI fingerprint does not match the manifest")
	}
	vectors := readRealVectors(t, os.Getenv("WAFFO_REAL_CAPTURE_DIR"), manifest)
	for _, item := range manifest.Records {
		t.Run(item.MetadataSHA256[:12], func(t *testing.T) {
			vector := vectors[item.MetadataSHA256]
			var header http.Header = make(http.Header)
			for name, values := range vector.metadata.Headers {
				if strings.EqualFold(name, "X-Waffo-Signature") {
					for _, value := range values {
						header.Add(name, string(value))
					}
				}
			}
			headers := header.Values("X-Waffo-Signature")
			atReceipt := vector.metadata.ReceivedAt
			if !verifyWaffoSignature(key, headers, vector.body, atReceipt) {
				t.Fatal("documented signature rejected at the fixed receipt clock")
			}
			f := setup(t)
			wrongKey := f.s.webhookKey
			f.s.webhookKey = key
			f.s.now = func() time.Time { return atReceipt }
			response := callbackResponse(f.s, vector.body, headers)
			// The transport fix must not silently invent the remaining mode/product adapter.
			if response.Code != http.StatusUnauthorized || strings.TrimSpace(response.Body.String()) != "invalid environment or event" {
				t.Fatal("real signature did not reach the unchanged business-envelope gate")
			}
			tampered := append(append([]byte{}, vector.body...), ' ')
			expectWaffoSignatureRejection(t, f.s, tampered, headers)
			parsed, ok := parseWaffoSignature(headers[0])
			if !ok {
				t.Fatal("real vector header failed to parse")
			}
			changed := "t=" + strconv.FormatInt(parsed.timestampMS+1, 10) + ",v1=" + base64.StdEncoding.EncodeToString(parsed.bytes)
			expectWaffoSignatureRejection(t, f.s, vector.body, []string{changed})
			f.s.webhookKey = wrongKey
			expectWaffoSignatureRejection(t, f.s, vector.body, headers)
			f.s.webhookKey = key
			f.s.now = func() time.Time { return atReceipt.Add(waffoPastTolerance + time.Minute) }
			expectWaffoSignatureRejection(t, f.s, vector.body, headers)
			var count int
			if err := f.s.db.QueryRow("SELECT count(*) FROM webhook_events").Scan(&count); err != nil || count != 0 {
				t.Fatal("private diagnostic vectors changed authorization state")
			}
			if vectorDigest(vector.body) != item.BodySHA256 {
				t.Fatal("real vector body changed during replay")
			}
		})
	}
}
