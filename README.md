# Docker Image Builder

A configuration-driven delivery layer for upstream projects. This repository does **not** fork or commit upstream source code; it tracks the latest accepted upstream Git tag for each target, builds that exact revision with target-specific overlays, and publishes the result to GitHub Container Registry (GHCR).

## Current target

- `HKUDS/nanobot`
- Latest accepted Git tag only (no historical-tag selection or rollback)
- `ghcr.io/sakiko999/nanobot-image:latest`
- `ghcr.io/sakiko999/nanobot-image:<upstream-tag>`

Adding another upstream project means adding a self-contained `targets/<id>/` directory; the generic engine and workflows stay unchanged. See `docs/adding-target.md`.

## Repository model

```
targets/<id>/target.json     declarative target metadata
targets/<id>/build.sh        project-specific build adapter
targets/<id>/Dockerfile      final image overlay
targets/<id>/patches/        optional ordered source patches
targets/<id>/config/         non-secret configuration templates
scripts/                     generic validation, tag, patch, and build engine
state/<id>.json              latest successful build record (committed by CI)
```

The engine resolves the latest matching upstream tag, clones that tag into a temporary directory, applies patches, invokes the target adapter, pushes `latest` and the upstream tag, and writes `state/<id>.json` only after both tags are published.

## Local build

```bash
./scripts/build-local.sh nanobot
```

The local command always resolves the latest matching upstream tag, builds both `:latest` and `:<upstream-tag>` images locally, and never writes state or publishes. It accepts exactly one target ID and never accepts a historical tag.

## Container runtime

Mount persistent nanobot state at `$HOME/.nanobot` (or set `NANOBOT_HOME`). The image probes its gateway health endpoint at `http://127.0.0.1:18790/health` by default (override with `NANOBOT_HEALTH_URL`). The image intentionally does not embed secrets.

## Automation

`build-images.yml` checks targets every six hours and can be started manually with `target=nanobot` or `target=all`. It authenticates to GHCR with `GITHUB_TOKEN`, runs the test suite, builds and publishes each selected target's latest image, then commits a state file only after successful publication.
