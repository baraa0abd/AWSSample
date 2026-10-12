// Demo HTTP service: /, /healthz, /readyz, /metrics (Prometheus text format), /fail (always 500,
// for exercising the 5xx alert). Standard library only, so the image has no third-party CVE surface.
package main

import (
	"context"
	"errors"
	"flag"
	"fmt"
	"log/slog"
	"net/http"
	"os"
	"os/signal"
	"sort"
	"strings"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

var version = "dev" // set at build time with -ldflags "-X main.version=..."

// ponytail: hand-rolled counter + histogram instead of prometheus/client_golang.
// Enough for RED dashboards; switch to the client library when you need more metric types.
var buckets = []float64{.005, .01, .025, .05, .1, .25, .5, 1, 2.5, 5}

type metrics struct {
	mu       sync.Mutex
	requests map[[3]string]uint64 // {method, path, code} -> count
	hist     map[string][]uint64  // path -> cumulative bucket counts, last = +Inf
	sum      map[string]float64   // path -> total seconds
}

func newMetrics() *metrics {
	return &metrics{requests: map[[3]string]uint64{}, hist: map[string][]uint64{}, sum: map[string]float64{}}
}

func (m *metrics) observe(method, path string, code int, d time.Duration) {
	m.mu.Lock()
	defer m.mu.Unlock()
	m.requests[[3]string{method, path, fmt.Sprint(code)}]++
	h := m.hist[path]
	if h == nil {
		h = make([]uint64, len(buckets)+1)
		m.hist[path] = h
	}
	s := d.Seconds()
	for i, b := range buckets {
		if s <= b {
			h[i]++
		}
	}
	h[len(buckets)]++
	m.sum[path] += s
}

func (m *metrics) ServeHTTP(w http.ResponseWriter, _ *http.Request) {
	m.mu.Lock()
	defer m.mu.Unlock()
	var lines []string
	for k, v := range m.requests {
		lines = append(lines, fmt.Sprintf("http_requests_total{method=%q,path=%q,code=%q} %d", k[0], k[1], k[2], v))
	}
	for path, h := range m.hist {
		for i, b := range buckets {
			lines = append(lines, fmt.Sprintf("http_request_duration_seconds_bucket{path=%q,le=\"%g\"} %d", path, b, h[i]))
		}
		lines = append(lines,
			fmt.Sprintf("http_request_duration_seconds_bucket{path=%q,le=\"+Inf\"} %d", path, h[len(buckets)]),
			fmt.Sprintf("http_request_duration_seconds_sum{path=%q} %g", path, m.sum[path]),
			fmt.Sprintf("http_request_duration_seconds_count{path=%q} %d", path, h[len(buckets)]))
	}
	sort.Strings(lines) // stable output; also groups each metric family together
	w.Header().Set("Content-Type", "text/plain; version=0.0.4")
	fmt.Fprintf(w, "# TYPE http_requests_total counter\n# TYPE http_request_duration_seconds histogram\n")
	fmt.Fprintf(w, "app_info{version=%q} 1\n%s\n", version, strings.Join(lines, "\n"))
}

type statusRecorder struct {
	http.ResponseWriter
	code int
}

func (r *statusRecorder) WriteHeader(code int) {
	r.code = code
	r.ResponseWriter.WriteHeader(code)
}

func newHandler(m *metrics, ready *atomic.Bool, greeting string) http.Handler {
	mux := http.NewServeMux()
	// "/{$}" matches only the root, so unknown paths 404 instead of all landing on the greeting.
	mux.HandleFunc("GET /{$}", func(w http.ResponseWriter, _ *http.Request) {
		fmt.Fprintf(w, "%s (version %s)\n", greeting, version)
	})
	mux.HandleFunc("GET /fail", func(w http.ResponseWriter, _ *http.Request) {
		http.Error(w, "intentional failure", http.StatusInternalServerError)
	})
	mux.HandleFunc("GET /healthz", func(w http.ResponseWriter, _ *http.Request) { fmt.Fprintln(w, "ok") })
	mux.HandleFunc("GET /readyz", func(w http.ResponseWriter, _ *http.Request) {
		if !ready.Load() {
			http.Error(w, "shutting down", http.StatusServiceUnavailable)
			return
		}
		fmt.Fprintln(w, "ready")
	})
	mux.Handle("GET /metrics", m)

	return http.HandlerFunc(func(w http.ResponseWriter, r *http.Request) {
		_, pattern := mux.Handler(r)
		path := strings.TrimSuffix(strings.TrimPrefix(pattern, "GET "), "{$}")
		if path == "" {
			path = "other" // unmatched paths share one label: bounded cardinality
		}
		rec := &statusRecorder{ResponseWriter: w, code: http.StatusOK}
		start := time.Now()
		mux.ServeHTTP(rec, r)
		// Probes and scrapes would drown out real traffic in metrics and logs.
		if path == "/healthz" || path == "/readyz" || path == "/metrics" {
			return
		}
		d := time.Since(start)
		m.observe(r.Method, path, rec.code, d)
		slog.Info("request", "method", r.Method, "path", r.URL.Path, "status", rec.code, "duration_ms", d.Milliseconds())
	})
}

func main() {
	healthcheck := flag.Bool("healthcheck", false, "probe the local /healthz and exit (used by the Docker HEALTHCHECK)")
	flag.Parse()
	port := os.Getenv("PORT")
	if port == "" {
		port = "8080"
	}

	if *healthcheck {
		resp, err := http.Get("http://127.0.0.1:" + port + "/healthz")
		if err != nil || resp.StatusCode != http.StatusOK {
			os.Exit(1)
		}
		return
	}

	slog.SetDefault(slog.New(slog.NewJSONHandler(os.Stdout, nil)))
	greeting := os.Getenv("GREETING")
	if greeting == "" {
		greeting = "hello"
	}

	var ready atomic.Bool
	ready.Store(true)
	srv := &http.Server{
		Addr:              ":" + port,
		Handler:           newHandler(newMetrics(), &ready, greeting),
		ReadHeaderTimeout: 5 * time.Second,
	}

	ctx, stop := signal.NotifyContext(context.Background(), syscall.SIGTERM, os.Interrupt)
	defer stop()
	go func() {
		<-ctx.Done()
		ready.Store(false) // fail readiness first so the Service stops sending traffic
		time.Sleep(5 * time.Second)
		shutdownCtx, cancel := context.WithTimeout(context.Background(), 10*time.Second)
		defer cancel()
		_ = srv.Shutdown(shutdownCtx)
	}()

	slog.Info("listening", "port", port, "version", version)
	if err := srv.ListenAndServe(); !errors.Is(err, http.ErrServerClosed) {
		slog.Error("server failed", "error", err)
		os.Exit(1)
	}
}
