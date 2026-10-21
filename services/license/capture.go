// [INPUT] Opt-in private directory, bounded callback bytes and parsed HTTP headers.
// [OUTPUT] Bounded rolling private captures and expiry cleanup, never authorization.
// [POS] TEST evidence collection before the unchanged provisional webhook verifier.
// [PROTOCOL] Keep this header and AGENTS.md aligned with README.md.
package main

import (
	"encoding/hex"
	"encoding/json"
	"errors"
	"io"
	"log"
	"net/http"
	"os"
	"path/filepath"
	"strconv"
	"strings"
	"sync"
	"time"
)

const (
	callbackBodyLimit   = 64 << 10
	captureHeaderLimit  = 32 << 10
	captureCountLimit   = 128
	captureRetention    = 24 * time.Hour
	captureCleanupEvery = time.Minute
)

type callbackCapture struct {
	root      *os.Root
	now       func() time.Time
	mu        sync.Mutex
	stop      chan struct{}
	done      chan struct{}
	closeOnce sync.Once
	closeErr  error
}

// Byte slices preserve non-UTF-8 header values through JSON's base64 encoding.
// These are the headers received by net/http, not the original wire framing.
type captureMetadata struct {
	ReceivedAt       time.Time           `json:"receivedAt"`
	Method           string              `json:"method"`
	RequestURI       []byte              `json:"requestURI"`
	Protocol         string              `json:"protocol"`
	Host             []byte              `json:"host"`
	Headers          map[string][][]byte `json:"headers"`
	Trailers         map[string][][]byte `json:"trailers"`
	ContentLength    int64               `json:"contentLength"`
	TransferEncoding []string            `json:"transferEncoding"`
}

func openCallbackCapture(path string, now func() time.Time) (*callbackCapture, error) {
	if path == "" {
		return nil, nil
	}
	if !filepath.IsAbs(path) || filepath.Clean(path) != path {
		return nil, errors.New("capture directory must be an absolute clean path")
	}
	if err := privateDirectory(filepath.Dir(path)); err != nil {
		return nil, errors.New("capture parent must be a private directory")
	}
	if err := os.Mkdir(path, 0700); err != nil && !errors.Is(err, os.ErrExist) {
		return nil, errors.New("cannot create capture directory")
	}
	if err := privateDirectory(path); err != nil {
		return nil, err
	}
	root, err := os.OpenRoot(path)
	if err != nil {
		return nil, errors.New("cannot open capture directory")
	}
	c := &callbackCapture{root: root, now: now, stop: make(chan struct{}), done: make(chan struct{})}
	if _, _, err := c.prune(now()); err != nil {
		root.Close()
		return nil, errors.New("cannot initialize capture directory")
	}
	go c.cleanupLoop()
	return c, nil
}

func privateDirectory(path string) error {
	info, err := os.Lstat(path)
	if err != nil || !info.IsDir() || info.Mode().Perm() != 0700 {
		return errors.New("capture directory must be a real directory with mode 0700")
	}
	return nil
}

func (c *callbackCapture) close() error {
	c.closeOnce.Do(func() {
		close(c.stop)
		<-c.done
		c.mu.Lock()
		defer c.mu.Unlock()
		c.closeErr = c.root.Close()
	})
	return c.closeErr
}

func (c *callbackCapture) cleanupLoop() {
	defer close(c.done)
	ticker := time.NewTicker(captureCleanupEvery)
	defer ticker.Stop()
	for {
		select {
		case <-c.stop:
			return
		case <-ticker.C:
			if err := c.cleanup(); err != nil {
				log.Print("callback capture cleanup failed")
			}
		}
	}
}

func (c *callbackCapture) cleanup() error {
	c.mu.Lock()
	defer c.mu.Unlock()
	_, _, err := c.prune(c.now())
	return err
}

func headerBytes(headers http.Header) map[string][][]byte {
	result := make(map[string][][]byte, len(headers))
	for name, values := range headers {
		if values == nil {
			result[name] = nil
			continue
		}
		result[name] = make([][]byte, len(values))
		for i, value := range values {
			result[name][i] = []byte(value)
		}
	}
	return result
}

func (c *callbackCapture) save(r *http.Request, body []byte) error {
	if len(body) > callbackBodyLimit {
		return errors.New("capture body limit exceeded")
	}
	now := c.now()
	metadata, err := json.Marshal(captureMetadata{
		ReceivedAt: now.UTC(), Method: r.Method, RequestURI: []byte(r.RequestURI),
		Protocol: r.Proto, Host: []byte(r.Host), Headers: headerBytes(r.Header),
		Trailers: headerBytes(r.Trailer), ContentLength: r.ContentLength,
		TransferEncoding: r.TransferEncoding,
	})
	if err != nil || len(metadata) > captureHeaderLimit {
		return errors.New("capture header limit exceeded")
	}
	c.mu.Lock()
	defer c.mu.Unlock()
	count, oldest, err := c.prune(now)
	if err != nil {
		return err
	}
	if count >= captureCountLimit {
		if err := c.root.RemoveAll(oldest); err != nil {
			return err
		}
	}
	return c.publish(now, body, metadata)
}

func (c *callbackCapture) publish(now time.Time, body, metadata []byte) error {
	id := randomID()
	pending := ".pending-" + id
	if err := c.root.Mkdir(pending, 0700); err != nil {
		return err
	}
	defer c.root.RemoveAll(pending)
	staging, err := c.root.OpenRoot(pending)
	if err != nil {
		return err
	}
	defer staging.Close()
	if err := writeCaptureFile(staging, "body.bin", body); err != nil {
		return err
	}
	if err := writeCaptureFile(staging, "request.json", metadata); err != nil {
		return err
	}
	if err := syncCaptureDirectory(staging); err != nil {
		return err
	}
	name := "capture-" + strconv.FormatInt(now.UnixNano(), 10) + "-" + id
	if err := c.root.Rename(pending, name); err != nil {
		return err
	}
	return syncCaptureDirectory(c.root)
}

func writeCaptureFile(root *os.Root, name string, data []byte) error {
	file, err := root.OpenFile(name, os.O_WRONLY|os.O_CREATE|os.O_EXCL, 0600)
	if err != nil {
		return err
	}
	defer file.Close()
	if _, err := file.Write(data); err != nil {
		return err
	}
	if err := file.Sync(); err != nil {
		return err
	}
	return file.Close()
}

func syncCaptureDirectory(root *os.Root) error {
	dir, err := root.Open(".")
	if err != nil {
		return err
	}
	defer dir.Close()
	return dir.Sync()
}

func captureID(value string) bool {
	decoded, err := hex.DecodeString(value)
	return err == nil && len(decoded) == 16 && value == strings.ToLower(value)
}

func captureTime(name string) (time.Time, bool) {
	parts := strings.Split(name, "-")
	if len(parts) != 3 || parts[0] != "capture" || !captureID(parts[2]) {
		return time.Time{}, false
	}
	ns, err := strconv.ParseInt(parts[1], 10, 64)
	return time.Unix(0, ns), err == nil && ns > 0
}

// The dedicated directory contains only this process's captures. Refuse unknown
// entries instead of deleting unrelated files or scanning an unbounded directory.
func (c *callbackCapture) prune(now time.Time) (int, string, error) {
	dir, err := c.root.Open(".")
	if err != nil {
		return 0, "", err
	}
	defer dir.Close()
	info, err := dir.Stat()
	if err != nil || info.Mode().Perm() != 0700 {
		return 0, "", errors.New("capture directory permissions changed")
	}
	entries, err := dir.ReadDir(2*captureCountLimit + 1)
	if err != nil && err != io.EOF {
		return 0, "", err
	}
	if len(entries) > 2*captureCountLimit {
		return 0, "", errors.New("capture directory entry limit exceeded")
	}
	published := 0
	for _, entry := range entries {
		name := entry.Name()
		_, capture := captureTime(name)
		pending := strings.HasPrefix(name, ".pending-") && captureID(strings.TrimPrefix(name, ".pending-"))
		if !entry.IsDir() || (!capture && !pending) {
			return 0, "", errors.New("unexpected capture directory entry")
		}
		if capture {
			published++
		}
	}
	if published > captureCountLimit {
		return 0, "", errors.New("capture record limit exceeded")
	}
	count, oldest := 0, ""
	var oldestTime time.Time
	for _, entry := range entries {
		name := entry.Name()
		created, capture := captureTime(name)
		if !capture || !now.Before(created.Add(captureRetention)) {
			if err := c.root.RemoveAll(name); err != nil {
				return 0, "", err
			}
		} else {
			count++
			if oldest == "" || created.Before(oldestTime) || created.Equal(oldestTime) && name < oldest {
				oldest, oldestTime = name, created
			}
		}
	}
	return count, oldest, nil
}
