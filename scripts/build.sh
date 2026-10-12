#!/usr/bin/env bash
# Build -> scan -> (optionally) push. Tags: git SHA (what gets deployed) and semver from app/VERSION.
# Usage: IMAGE_REPO=ghcr.io/<owner>/webapp [PUSH=1] scripts/build.sh
set -euo pipefail
cd "$(dirname "$0")/.."

: "${IMAGE_REPO:?set IMAGE_REPO, e.g. ghcr.io/<owner>/webapp}"
IMAGE_TAG="${IMAGE_TAG:-$(git rev-parse --short=12 HEAD)}"
semver=$(cat app/VERSION)
TRIVY_VERSION=0.75.0

docker build --build-arg VERSION="${semver}+${IMAGE_TAG}" \
  -t "${IMAGE_REPO}:${IMAGE_TAG}" -t "${IMAGE_REPO}:${semver}" app/

# Gate: any HIGH/CRITICAL finding fails the build, so a vulnerable image is never pushed.
docker run --rm -v /var/run/docker.sock:/var/run/docker.sock "aquasec/trivy:${TRIVY_VERSION}" \
  image --quiet --severity HIGH,CRITICAL --exit-code 1 "${IMAGE_REPO}:${IMAGE_TAG}"

if [ "${PUSH:-0}" = "1" ]; then
  docker push "${IMAGE_REPO}:${IMAGE_TAG}"
  docker push "${IMAGE_REPO}:${semver}"
fi
echo "built ${IMAGE_REPO}:${IMAGE_TAG} (${semver})"
