# jellyops-plugin-file-transformation

A [JellyOps](../jellyops) plugin package that delivers
**[File Transformation](https://github.com/IAmParadox27/jellyfin-plugin-file-transformation)**
(IAmParadox27, GPL-3.0) to a JellyOps-managed **Jellyfin v12 (.NET 10)** instance as a
`JellyfinPlugin` custom resource.

File Transformation lets other plugins rewrite served jellyfin-web content (e.g. inject a
`<script>` into `index.html`) without rebuilding jellyfin-web. Our siblings OpenWatchParty,
Keycloak SSO (oauth2) and Distributed Transcoding (jellycode) register their `index.html`
transforms with it by reflection: `PluginInterface.RegisterTransformation(JObject)`.

## What's packaged

The payload is **not compiled here**. It is upstream's published release artifact,
repackaged unmodified:

| | |
|---|---|
| Upstream release | `3.0.2.0` |
| Asset | `Release-12.2.0.zip` (sha256 `b267dc0e…10b859`, pinned in the build) |
| Plugin GUID | `5e87cc92-571a-4d8d-8d98-d2d4147f9f90` |
| targetAbi | `12.2.0.0` (upstream's manifest value; loads on any server >= 12.2, e.g. 12.3) |
| Framework | `net10.0` |

The zip has no `meta.json` (Jellyfin normally writes it from the catalog manifest), so
[`docker/meta.json`](docker/meta.json) supplies it. Keep it, the Dockerfile labels and the
CR's `spec.meta` in sync when bumping.

This repo used to carry a source port of 2.5.0.x to v12 (Harmony-patching
`Startup.Configure`). Upstream 3.x replaced Harmony with an `IStartupFilter` middleware and
ships v12 builds, so the port was retired.

## Requirements

- Jellyfin v12 server **>= 12.2** that serves `/web` itself. On the CrunchyMonkies fork images
  (which bake `--nowebclient`) set the Jellyfin CR's `spec.web.mode: volume`; a separate
  nginx web tier is never transformed.
- Kubernetes >= 1.33 with image volumes; the JellyOps operator + CRDs.

## Build

```sh
# Requires curl, unzip, sha256sum and docker (or CONTAINER=podman PROVENANCE_FLAG=).
docker/build-push.sh                 # build + push to ghcr.io/crunchymonkies/jellyops-plugin-file-transformation/plugin
PUSH=false docker/build-push.sh      # build only
```

CI (`.github/workflows/plugin-image.yml`) does the same on a `v*` tag push or manual
dispatch, and prints the digest to pin in `k8s/30-jellyfinplugin.yaml`.

To move to a newer upstream release: update `FT_TAG`/`FT_ASSET`/`FT_SHA256` (script +
workflow), `docker/meta.json`, the Dockerfile labels and the CR `spec.meta`.

## License

GPL-3.0 (see [LICENSE](LICENSE)), following upstream.
