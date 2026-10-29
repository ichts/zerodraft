package licence

import (
	"bytes"
	"context"
	"encoding/base64"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"strings"
	"time"
)

// Client is the stateless HTTP boundary of the licence service (Mac WaffoLicenseClient): POST and JSON, no
// Authorization header, no cookie jar, and redirects are refused so an order number or token can never be
// forwarded to another origin.
type Client struct {
	base     *url.URL
	verifier *Verifier
	http     *http.Client
	Clock    func() time.Time
	// Platform is sent as `platform` on activation; the service accepts "macos" and "windows".
	Platform string
}

// Activation is the result of a successful activation (Mac LicenseActivation).
type Activation struct {
	InstanceID string
	ProductID  string
	Token      string
}

// NewClient builds the client. baseURL is the service origin without a path; publicKey is base64 of the raw 32
// bytes. An unusable configuration yields a client whose Configured() is false (activation then reports
// ProductNotConfigured, exactly like the Mac).
func NewClient(baseURL, productID, publicKeyB64 string, httpClient *http.Client) *Client {
	c := &Client{http: httpClient, Clock: time.Now, Platform: "windows"}
	if c.http == nil {
		c.http = &http.Client{Timeout: 15 * time.Second}
	}
	c.http = noRedirects(c.http)
	if u, err := url.Parse(baseURL); err == nil && AllowedURL(u) {
		c.base = u
	}
	if key, err := base64.StdEncoding.DecodeString(publicKeyB64); err == nil {
		c.verifier, _ = NewVerifier(key, productID)
	}
	return c
}

func noRedirects(h *http.Client) *http.Client {
	cp := *h
	cp.Jar = nil
	cp.CheckRedirect = func(*http.Request, []*http.Request) error { return http.ErrUseLastResponse }
	return &cp
}

// AllowedURL is the Mac rule: an https origin with no credentials, query, fragment or path; plain http only for
// loopback (local QA).
func AllowedURL(u *url.URL) bool {
	if u == nil || u.Hostname() == "" || u.User != nil || u.RawQuery != "" || u.Fragment != "" || u.ForceQuery ||
		(u.Path != "" && u.Path != "/") {
		return false
	}
	switch u.Scheme {
	case "https":
		return true
	case "http":
		h := u.Hostname()
		return h == "127.0.0.1" || h == "localhost" || h == "::1"
	}
	return false
}

// Configured reports whether activation can run at all.
func (c *Client) Configured() bool {
	return c.base != nil && c.verifier != nil && c.verifier.ProductID != ""
}

type httpFailure struct {
	status int
	detail string
}

func (f *httpFailure) Error() string { return "licence service HTTP " + http.StatusText(f.status) }

func (c *Client) post(ctx context.Context, endpoint string, body map[string]string) ([]byte, error) {
	payload, _ := json.Marshal(body)
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base.ResolveReference(&url.URL{Path: "/api/v1/licenses/" + endpoint}).String(), bytes.NewReader(payload))
	if err != nil {
		return nil, err
	}
	req.Header.Set("Content-Type", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return nil, err
	}
	defer resp.Body.Close()
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return nil, err
	}
	if resp.StatusCode != http.StatusOK {
		return nil, &httpFailure{status: resp.StatusCode, detail: string(data)}
	}
	return data, nil
}

type tokenResponse struct {
	Token string `json:"token"`
}

// Activate exchanges the order credential (already trimmed) for a signed token bound to installLabel.
// 403/404 -> invalid key (missing, refunded or revoked); 409 "device limit reached" -> the two-PC limit (any other
// 409 is NOT misreported as that limit); 429 and 5xx -> network failure; the response token must verify.
func (c *Client) Activate(ctx context.Context, licenseKey, installLabel string) (Activation, error) {
	if !c.Configured() {
		return Activation{}, actErr(KindProductNotConfigured)
	}
	data, err := c.post(ctx, "activate", map[string]string{"orderId": licenseKey, "installLabel": installLabel, "platform": c.Platform})
	if err != nil {
		var f *httpFailure
		if !errors.As(err, &f) {
			return Activation{}, actErr(KindNetworkFailure)
		}
		switch {
		case f.status == 403 || f.status == 404:
			return Activation{}, actErr(KindInvalidKey)
		case f.status == 409 && strings.TrimSpace(f.detail) == "device limit reached":
			return Activation{}, actErr(KindActivationLimitReached)
		case f.status == 429 || f.status >= 500 && f.status <= 599:
			return Activation{}, actErr(KindNetworkFailure)
		}
		return Activation{}, &ActivationError{Kind: KindUnexpected, Status: f.status}
	}
	var tr tokenResponse
	if json.Unmarshal(data, &tr) != nil || tr.Token == "" {
		return Activation{}, actErr(KindInvalidToken)
	}
	claims, err := c.verifier.Verify(tr.Token, installLabel, c.Clock())
	if err != nil {
		return Activation{}, actErr(KindInvalidToken)
	}
	return Activation{InstanceID: claims.ActivationID, ProductID: claims.Product, Token: tr.Token}, nil
}

// Validate renews a token. revoked is true on an explicit HTTP 403 (the Mac's nil); transport failures, 429 and
// 5xx are ValidationError{ValNetwork} and never revoke.
func (c *Client) Validate(ctx context.Context, token string) (renewed string, revoked bool, err error) {
	if !c.Configured() {
		return "", false, &ValidationError{Kind: ValInvalidToken}
	}
	data, err := c.post(ctx, "validate", map[string]string{"token": token})
	if err != nil {
		var f *httpFailure
		if !errors.As(err, &f) {
			return "", false, &ValidationError{Kind: ValNetwork}
		}
		switch {
		case f.status == 403:
			return "", true, nil
		case f.status == 429 || f.status >= 500 && f.status <= 599:
			return "", false, &ValidationError{Kind: ValNetwork}
		}
		return "", false, &ValidationError{Kind: ValUnexpected, Status: f.status}
	}
	var tr tokenResponse
	if json.Unmarshal(data, &tr) != nil || tr.Token == "" {
		return "", false, &ValidationError{Kind: ValInvalidToken}
	}
	return tr.Token, false, nil
}

// Deactivate frees the installation slot (used to undo an activation that could not be saved).
func (c *Client) Deactivate(ctx context.Context, token string) error {
	if !c.Configured() {
		return actErr(KindProductNotConfigured)
	}
	_, err := c.post(ctx, "deactivate", map[string]string{"token": token})
	return err
}

// PermitsAccess verifies the token locally for this installation and activation.
func (c *Client) PermitsAccess(token, instanceID, installLabel string, now time.Time) bool {
	if !c.Configured() {
		return false
	}
	claims, err := c.verifier.Verify(token, installLabel, now)
	return err == nil && claims.ActivationID == instanceID
}
