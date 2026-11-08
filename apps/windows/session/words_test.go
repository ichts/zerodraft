package session

import (
	"encoding/json"
	"os"
	"testing"
)

// wordCountFixture is the one fixture the web, the Mac and the Windows suites share (D-099).
type wordCountFixture struct {
	Counts []struct {
		Name  string `json:"name"`
		Text  string `json:"text"`
		Words int    `json:"words"`
	} `json:"counts"`
	Labels []struct {
		Text  string `json:"text"`
		Label string `json:"label"`
	} `json:"labels"`
}

func loadWordCountFixture(t testing.TB) wordCountFixture {
	t.Helper()
	b, err := os.ReadFile("../../../tests/fixtures/word-count.json")
	if err != nil {
		t.Fatal(err)
	}
	var f wordCountFixture
	if err := json.Unmarshal(b, &f); err != nil {
		t.Fatal(err)
	}
	return f
}

func TestWordCountMatchesTheSharedFixture(t *testing.T) {
	for _, c := range loadWordCountFixture(t).Counts {
		if got := WordCount(c.Text); got != c.Words {
			t.Errorf("%s: WordCount(%q) = %d, want %d", c.Name, c.Text, got, c.Words)
		}
	}
}
