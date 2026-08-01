#!/usr/bin/env bash
#
# Build and push the File Transformation plugin image-volume payload for JellyOps.
#
# Compiles src/Plugin against a sibling jellyfin-src checkout pinned to the Jellyfin
# v12 rc3 tag the deployed server runs (v12.0.0-rc3-jc-0.2.1), strips host assemblies
# (the .csproj StripHostAssemblies* targets), and packages a FROM-scratch image.
# 0Harmony is embedded in the plugin DLL, not shipped loose.
#
# Usage: docker/build-push.sh [TAG]
# Env:  REGISTRY (default ghcr.io/crunchymonkies/jellyops-plugin-file-transformation)
#       IMAGE    (default <REGISTRY>/plugin)
#       JELLYFIN_SRC (default <repo>/../jellyfin-src)
#       PUSH     (default true)
set -euo pipefail

REGISTRY="${REGISTRY:-ghcr.io/crunchymonkies/jellyops-plugin-file-transformation}"
IMAGE="${IMAGE:-${REGISTRY}/plugin}"
PUSH="${PUSH:-true}"
TAG="${1:-$(date +%Y%m).$(date +%d).1}"

ROOT="$(cd "$(dirname "$0")/.." && pwd)"
JELLYFIN_SRC="${JELLYFIN_SRC:-$(cd "$ROOT/.." && pwd)/jellyfin-src}"
PROJECT="$ROOT/src/Plugin/Jellyfin.Plugin.FileTransformation.csproj"

[ -d "$JELLYFIN_SRC" ] || { echo "!! jellyfin-src not found at $JELLYFIN_SRC" >&2; exit 1; }
# Pin: build only against the rc3 tag the deployed server runs.
want="v12.0.0-rc3-jc-0.2.1"
got="$(git -C "$JELLYFIN_SRC" describe --tags --exact-match 2>/dev/null || echo none)"
[ "$got" = "$want" ] || { echo "!! jellyfin-src is at '$got', expected '$want' (rc3)" >&2; exit 1; }

CTX="$(mktemp -d)"; trap 'rm -rf "$CTX"' EXIT
mkdir -p "$CTX/plugin"

echo ">> Publishing plugin (Release, net10.0) against $JELLYFIN_SRC"
dotnet publish "$PROJECT" -c Release -o "$CTX/publish" -v minimal
cp "$CTX/publish/"*.dll "$CTX/plugin/"
cp "$CTX/publish/meta.json" "$CTX/plugin/meta.json"

# Host assemblies must NOT ship (find, not ls-globs — see the oauth2 leak lesson).
LEAKED="$(find "$CTX/plugin" -maxdepth 1 -type f \( -name 'Emby.*' -o -name 'MediaBrowser.*' \
  -o \( -name 'Jellyfin.*' -a ! -name 'Jellyfin.Plugin.FileTransformation*' \) \))"
[ -z "$LEAKED" ] || { echo "!! host assemblies leaked:" >&2; echo "$LEAKED" >&2; exit 1; }
echo ">> Payload:"; ( cd "$CTX/plugin" && ls -1 )

cp "$ROOT/docker/Dockerfile.plugin" "$CTX/Dockerfile.plugin"
echo ">> Building ${IMAGE} (tags: ${TAG}, latest)"
docker build --provenance=false -f "$CTX/Dockerfile.plugin" -t "${IMAGE}:${TAG}" -t "${IMAGE}:latest" "$CTX"

if [ "$PUSH" = "true" ]; then
  docker push "${IMAGE}:${TAG}"; docker push "${IMAGE}:latest"
  DIGEST="$(docker inspect --format='{{range .RepoDigests}}{{println .}}{{end}}' "${IMAGE}:${TAG}" | grep "^${IMAGE}@" | head -1)"
  echo ">> Pushed. Pin in k8s (spec.pluginImage.reference): ${DIGEST}"
else
  echo ">> PUSH=false — built only."
fi
