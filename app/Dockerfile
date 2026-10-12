# syntax=docker/dockerfile:1
# Both bases are pinned by digest; bump tag and digest together.
FROM golang:1.27.2-alpine@sha256:f92b6ef800e499660581efdabdf25d9d817a9d124eaf900924f0504e7e27e12d AS build
WORKDIR /src
COPY go.mod *.go ./
ARG VERSION=dev
RUN go vet ./... && go test ./... \
    && CGO_ENABLED=0 go build -trimpath -ldflags="-s -w -X main.version=${VERSION}" -o /out/app .

# Distroless static: no shell, no package manager, runs as uid 65532.
FROM gcr.io/distroless/static-debian13:nonroot@sha256:e2e927ec666bae08560abb3c55d0659eceabb657f56b6782ab500a9fc7f555e3
COPY --from=build /out/app /app
USER 65532:65532
ENV PORT=8080
EXPOSE 8080
# No curl in the image: the binary probes itself. (Kubernetes uses its own probes: /healthz, /readyz.)
HEALTHCHECK --interval=10s --timeout=2s --start-period=2s --retries=3 CMD ["/app", "-healthcheck"]
ENTRYPOINT ["/app"]
