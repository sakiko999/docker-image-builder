# Docker Image Builder

A configuration-driven delivery layer for upstream projects. This repository does **not** fork or commit upstream source code; it tracks the latest accepted upstream Git tag for each target, builds that exact revision with target-specific overlays, and publishes the result to GitHub Container Registry (GHCR).

## Current target

- `HKUDS/nanobot`
- Latest accepted Git tag only (no historical-tag selection or rollback)
- `ghcr.io/sakiko999/nanobot:latest`
- `ghcr.io/sakiko999/nanobot:<upstream-tag>`

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

该镜像默认以 **root 用户** 运行，不会降权。

- **默认数据目录**: `/root/.nanobot`（容器内 `$HOME/.nanobot`）
- **自定义路径**: 设置环境变量 `NANOBOT_HOME` 可覆盖
- 数据目录不存在时由入口点自动创建

### 挂载示例

```bash
# 默认 root 数据目录
docker run -v nanobot-data:/root/.nanobot ghcr.io/sakiko999/docker-image-builder/nanobot:latest gateway

# 自定义数据目录
docker run -v /host/path:/data -e NANOBOT_HOME=/data ghcr.io/sakiko999/docker-image-builder/nanobot:latest gateway
```

### 构建参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `NANOBOT_EXTRAS` | (空) | 额外 Python 依赖，对应 `[extra]` |
| `NANOBOT_CHANNELS` | (空) | 预装 channel 依赖，逗号分隔 |

示例：

```bash
# 指定 channel（默认无）
NANOBOT_CHANNELS=telegram ./scripts/build-local.sh nanobot
```

The image probes its gateway health endpoint at `http://127.0.0.1:18790/health` by default (override with `NANOBOT_HEALTH_URL`). The image intentionally does not embed secrets.

## Automation

`build-images.yml` checks targets every six hours and can be started manually with `target=nanobot` or `target=all`. It authenticates to GHCR with `GITHUB_TOKEN`, runs the test suite, builds and publishes each selected target's latest image, then commits a state file only after successful publication.
