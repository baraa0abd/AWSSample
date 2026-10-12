package main

import (
	"net/http"
	"net/http/httptest"
	"strings"
	"sync/atomic"
	"testing"
)

func get(t *testing.T, h http.Handler, path string) (int, string) {
	t.Helper()
	rec := httptest.NewRecorder()
	h.ServeHTTP(rec, httptest.NewRequest(http.MethodGet, path, nil))
	return rec.Code, rec.Body.String()
}

func TestHandler(t *testing.T) {
	var ready atomic.Bool
	ready.Store(true)
	h := newHandler(newMetrics(), &ready, "hi")

	for path, want := range map[string]int{"/": 200, "/fail": 500, "/nope": 404, "/healthz": 200, "/readyz": 200} {
		if code, _ := get(t, h, path); code != want {
			t.Errorf("GET %s = %d, want %d", path, code, want)
		}
	}

	_, body := get(t, h, "/metrics")
	for _, want := range []string{
		`http_requests_total{method="GET",path="/",code="200"} 1`,
		`http_requests_total{method="GET",path="/fail",code="500"} 1`,
		`http_requests_total{method="GET",path="other",code="404"} 1`,
		`http_request_duration_seconds_bucket{path="/",le="+Inf"} 1`,
		`http_request_duration_seconds_count{path="/"} 1`,
	} {
		if !strings.Contains(body, want) {
			t.Errorf("metrics missing %q in:\n%s", want, body)
		}
	}
	if strings.Contains(body, "healthz") {
		t.Error("probe requests must not be recorded")
	}

	ready.Store(false)
	if code, _ := get(t, h, "/readyz"); code != 503 {
		t.Errorf("readyz while shutting down = %d, want 503", code)
	}
}
