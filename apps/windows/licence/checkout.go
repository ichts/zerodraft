package licence

import (
	"context"
	"encoding/json"
	"errors"
	"io"
	"net/http"
	"net/url"
	"time"
)

// ErrCheckout is any hosted-checkout failure; callers fall back to the public purchase page.
var ErrCheckout = errors.New("licence: checkout unavailable")

// CheckoutClient creates a hosted Stripe checkout session (Mac HostedCheckoutClient): POST
// {service}/api/v1/checkout with `Accept: application/json`, no body, no cookies, redirects refused. Only a 200
// with a string `url` on https://checkout.stripe.com (no user or password) is accepted.
type CheckoutClient struct {
	base *url.URL
	http *http.Client
}

// NewCheckoutClient builds it from the same service origin the licence client uses.
func NewCheckoutClient(baseURL string, httpClient *http.Client) *CheckoutClient {
	c := &CheckoutClient{http: httpClient}
	if c.http == nil {
		c.http = &http.Client{Timeout: 15 * time.Second}
	}
	c.http = noRedirects(c.http)
	if u, err := url.Parse(baseURL); err == nil && AllowedURL(u) {
		c.base = u
	}
	return c
}

// Configured reports whether a checkout request can be made.
func (c *CheckoutClient) Configured() bool { return c.base != nil }

// Session asks the service for the hosted checkout URL.
func (c *CheckoutClient) Session(ctx context.Context) (string, error) {
	if c.base == nil {
		return "", ErrCheckout
	}
	req, err := http.NewRequestWithContext(ctx, http.MethodPost, c.base.ResolveReference(&url.URL{Path: "/api/v1/checkout"}).String(), nil)
	if err != nil {
		return "", ErrCheckout
	}
	req.Header.Set("Accept", "application/json")
	resp, err := c.http.Do(req)
	if err != nil {
		return "", ErrCheckout
	}
	defer resp.Body.Close()
	if resp.StatusCode != http.StatusOK {
		return "", ErrCheckout
	}
	data, err := io.ReadAll(io.LimitReader(resp.Body, 1<<20))
	if err != nil {
		return "", ErrCheckout
	}
	var out struct {
		URL string `json:"url"`
	}
	if json.Unmarshal(data, &out) != nil {
		return "", ErrCheckout
	}
	u, err := url.Parse(out.URL)
	if err != nil || u.Scheme != "https" || u.Hostname() != "checkout.stripe.com" || u.User != nil {
		return "", ErrCheckout
	}
	return out.URL, nil
}
