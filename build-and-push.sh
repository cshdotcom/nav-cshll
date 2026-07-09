#!/usr/bin/env bash
# ============================================================================
# build-and-push.sh - One-click build, tag and push the nav Docker image
#
# Usage:
#   ./build-and-push.sh                       # builds and pushes :latest + :<version>
#   ./build-and-push.sh v1.0.0                # builds and pushes :v1.0.0 + :latest
#   ./build-and-push.sh v1.0.0 --no-push      # builds and tags locally only
#   DOCKER_USER=myname ./build-and-push.sh    # override Docker Hub username
#
# Prerequisites:
#   - docker installed and running
#   - docker login done:  docker login -u cshdotcom
#     (use a Docker Hub Access Token instead of your password)
# ============================================================================

set -euo pipefail

# ---------- Config ----------
DOCKER_USER="${DOCKER_USER:-cshdotcom}"
IMAGE_NAME="${IMAGE_NAME:-nav}"
PLATFORMS="${PLATFORMS:-linux/amd64,linux/arm64}"

# ---------- Args ----------
VERSION_TAG="${1:-}"
NO_PUSH=0
[[ "${2:-}" == "--no-push" ]] && NO_PUSH=1

# Auto-detect version from package.json if not provided
if [[ -z "$VERSION_TAG" ]]; then
    if command -v node >/dev/null 2>&1; then
        VERSION_TAG="v$(node -p "require('./package.json').version")"
    else
        VERSION_TAG="v$(grep -oP '"version"\s*:\s*"\K[^"]+' package.json | head -1)"
    fi
    echo "ℹ️  Auto-detected version from package.json: $VERSION_TAG"
fi

# Git short SHA for traceability
GIT_SHA="$(git rev-parse --short HEAD 2>/dev/null || echo 'unknown')"
BUILD_DATE="$(date -u +%Y-%m-%dT%H:%M:%SZ)"

echo "=============================================="
echo "  Image:     $DOCKER_USER/$IMAGE_NAME"
echo "  Version:   $VERSION_TAG"
echo "  Git SHA:   $GIT_SHA"
echo "  Build at:  $BUILD_DATE"
echo "  Push:      $([ $NO_PUSH -eq 0 ] && echo yes || echo no)"
echo "  Platforms: $PLATFORMS"
echo "=============================================="

# ---------- Pre-flight checks ----------
if ! command -v docker >/dev/null 2>&1; then
    echo "❌ docker not found. Install Docker first: https://docs.docker.com/get-docker/"
    exit 1
fi

if ! docker info >/dev/null 2>&1; then
    echo "❌ Docker daemon not running. Start Docker Desktop or the docker service."
    exit 1
fi

if [[ "$NO_PUSH" -eq 0 ]]; then
    if ! docker info 2>/dev/null | grep -q "Username:"; then
        echo "❌ Not logged in to Docker Hub."
        echo "   Run:  docker login -u $DOCKER_USER"
        echo "   Use a Docker Hub Access Token from https://hub.docker.com/settings/security"
        exit 1
    fi
fi

cd "$(dirname "$0")"

# ---------- Step 1: Create and switch to buildx builder ----------
BUILDER_NAME="nav-multiarch"
if ! docker buildx inspect "$BUILDER_NAME" >/dev/null 2>&1; then
    echo "📦 Creating buildx builder: $BUILDER_NAME"
    docker buildx create --name "$BUILDER_NAME" --use
else
    docker buildx use "$BUILDER_NAME"
fi

# ---------- Step 2: Build & push (multi-arch) ----------
FULL_IMAGE="$DOCKER_USER/$IMAGE_NAME"

LABELS=(
    --label "org.opencontainers.image.title=$IMAGE_NAME"
    --label "org.opencontainers.image.version=$VERSION_TAG"
    --label "org.opencontainers.image.revision=$GIT_SHA"
    --label "org.opencontainers.image.created=$BUILD_DATE"
    --label "org.opencontainers.image.source=https://github.com/cshdotcom/nav-cshll"
    --label "org.opencontainers.image.licenses=GPL-3.0"
)

PUSH_FLAG=""
[[ "$NO_PUSH" -eq 0 ]] && PUSH_FLAG="--push"

echo ""
echo "🏗️  Building multi-arch image: $FULL_IMAGE:$VERSION_TAG (+ :latest)"
echo ""
docker buildx build \
    --platform "$PLATFORMS" \
    --tag "$FULL_IMAGE:$VERSION_TAG" \
    --tag "$FULL_IMAGE:latest" \
    --tag "$FULL_IMAGE:sha-$GIT_SHA" \
    "${LABELS[@]}" \
    $PUSH_FLAG \
    .

echo ""
echo "✅ Done."
echo ""
if [[ "$NO_PUSH" -eq 0 ]]; then
    echo "📦 Pushed tags:"
    echo "   - $FULL_IMAGE:$VERSION_TAG"
    echo "   - $FULL_IMAGE:latest"
    echo "   - $FULL_IMAGE:sha-$GIT_SHA"
    echo ""
    echo "🔍 View at: https://hub.docker.com/r/$DOCKER_USER/$IMAGE_NAME/tags"
    echo ""
    echo "▶️  Pull and run:"
    echo "   docker pull $FULL_IMAGE:$VERSION_TAG"
    echo "   docker run -d -p 8080:80 --name nav $FULL_IMAGE:$VERSION_TAG"
    echo "   open http://localhost:8080"
else
    echo "📦 Built locally (not pushed). To run:"
    echo "   docker run -d -p 8080:80 --name nav $FULL_IMAGE:$VERSION_TAG"
    echo "   open http://localhost:8080"
fi

# ---------- Step 3: Tag the git commit (optional) ----------
if [[ "$NO_PUSH" -eq 0 ]] && [[ -n "${GIT_PUSH_TAG:-}" ]]; then
    echo ""
    echo "🏷️  Tagging git commit as $VERSION_TAG ..."
    git tag -a "$VERSION_TAG" -m "Release $VERSION_TAG (image: $FULL_IMAGE:$VERSION_TAG)"
    git push origin "$VERSION_TAG"
fi
