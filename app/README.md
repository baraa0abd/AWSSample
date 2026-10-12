# app

Small Go HTTP service (standard library only).

| Endpoint | Purpose |
|---|---|
| `/` | Greeting (`GREETING` env) and version |
| `/healthz` | Liveness |
| `/readyz` | Readiness (503 while shutting down) |
| `/metrics` | Prometheus metrics: `http_requests_total`, `http_request_duration_seconds` |
| `/fail` | Always 500 - for testing the 5xx alert |

Build and scan: `IMAGE_REPO=ghcr.io/<owner>/webapp make build` (add `PUSH=1` to push).
Tags: git SHA and the semver in `VERSION`. Test: `go test ./...`.
