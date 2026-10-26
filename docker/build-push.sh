#!/usr/bin/env bash
#
# Build and push the File Transformation plugin image-volume payload for JellyOps.
#
# The payload is NOT compiled here. It is upstream's published release artifact
# (Release-<jellyfin>.zip from IAmParadox27/jellyfin-plugin-file-transformation), verified
# against a pinned SHA-256, unzipped into the build context's `plugin/` dir together with
# docker/meta.json, and packaged into a FROM-scratch image whose root IS the Jellyfin
# plugin directory. Built with --provenance=false so it is a single plain manifest the
# kubelet mounts cleanly as an image volume (pass PROVENANCE_FLAG= for podman).
#
# Usage:
#   docker/build-push.sh [TAG]
#
# Environment overrides:
#   REGISTRY      image repo prefix  (default: ghcr.io/crunchymonkies/jellyops-plugin-file-transformation)
#   IMAGE         full image repo    (default: <REGISTRY>/plugin)
#   FT_REPO       release source     (default: IAmParadox27/jellyfin-plugin-file-transformation)
#   FT_TAG        release tag        (default: 3.0.2.0)
#   FT_ASSET      release zip name   (default: Release-12.2.0.zip)
#   FT_SHA256     expected zip hash  (default: pinned hash of 3.0.2.0/Release-12.2.0.zip)
#   CONTAINER     build tool         (default: docker; e.g. CONTAINER=podman)
#   PUSH          push to registry   (default: true; set PUSH=false to build only)
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/crunchymonkies/jellyops-plugin-file-transformation}"
IMAGE="${IMAGE:-${REGISTRY}/plugin}"
FT_REPO="${FT_REPO:-IAmParadox27/jellyfin-plugin-file-transformation}"
FT_TAG="${FT_TAG:-3.0.2.0}"
FT_ASSET="${FT_ASSET:-Release-12.2.0.zip}"
FT_SHA256="${FT_SHA256:-b267dc0e09154f242ef9d3201a6ed4fd1dc9594da42ff133400b0ed4ca10b859}"
CONTAINER="${CONTAINER:-docker}"
PROVENANCE_FLAG="${PROVENANCE_FLAG---provenance=false}"
PUSH="${PUSH:-true}"
TAG="${1:-$(date +%Y%m).$(date +%d).1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
CTX="$(mktemp -d)"; trap 'rm -rf "$CTX"' EXIT
mkdir -p "$CTX/plugin"

echo ">> Downloading ${FT_REPO} ${FT_TAG} (${FT_ASSET})"
curl -fsSL -o "$CTX/$FT_ASSET" \
  "https://github.com/${FT_REPO}/releases/download/${FT_TAG}/${FT_ASSET}"
echo "${FT_SHA256}  $CTX/$FT_ASSET" | sha256sum -c -

unzip -o -q "$CTX/$FT_ASSET" -d "$CTX/plugin"
cp "$ROOT/docker/meta.json" "$CTX/plugin/meta.json"

# Sanity-check: plugin DLL + meta present, and no host assemblies leaked.
test -f "$CTX/plugin/Jellyfin.Plugin.FileTransformation.dll" || { echo "!! plugin DLL missing" >&2; exit 1; }
test -f "$CTX/plugin/meta.json" || { echo "!! meta.json missing" >&2; exit 1; }
LEAKED="$(find "$CTX/plugin" -maxdepth 1 -type f \( -name 'Emby.*' -o -name 'MediaBrowser.*' \
  -o \( -name 'Jellyfin.*' -a ! -name 'Jellyfin.Plugin.FileTransformation*' \) \))"
[ -z "$LEAKED" ] || { echo "!! host assemblies leaked:" >&2; echo "$LEAKED" >&2; exit 1; }
echo ">> Payload:"; ( cd "$CTX/plugin" && ls -1 )

PLUGIN_VERSION="$(grep -oE '"version"[[:space:]]*:[[:space:]]*"[^"]+"' "$CTX/plugin/meta.json" | head -1 | grep -oE '[0-9.]+')"

cp "$ROOT/docker/Dockerfile.plugin" "$CTX/Dockerfile.plugin"
echo ">> Building ${IMAGE} (tags: ${PLUGIN_VERSION}, ${TAG}, latest)"
# shellcheck disable=SC2086
"$CONTAINER" build $PROVENANCE_FLAG -f "$CTX/Dockerfile.plugin" \
  -t "${IMAGE}:${PLUGIN_VERSION}" -t "${IMAGE}:${TAG}" -t "${IMAGE}:latest" "$CTX"

if [ "$PUSH" = "true" ]; then
  "$CONTAINER" push "${IMAGE}:${PLUGIN_VERSION}"
  "$CONTAINER" push "${IMAGE}:${TAG}"
  "$CONTAINER" push "${IMAGE}:latest"
  DIGEST="$("$CONTAINER" inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' "${IMAGE}:${PLUGIN_VERSION}" | grep "^${IMAGE}@" | head -1)"
  echo ">> Pushed. Pin in k8s (spec.pluginImage.reference): ${DIGEST}"
else
  echo ">> PUSH=false — built only."
fi
