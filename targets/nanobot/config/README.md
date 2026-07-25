# nanobot 覆盖层文档

## 容器运行时

该镜像默认以 **root 用户** 运行，不会降权。

- **默认数据目录**: `/root/.nanobot`（可通过 `NANOBOT_HOME` 覆盖）
- **默认 HOME**: `/root`
- 数据目录不存在时由入口点自动创建

### 挂载示例

```bash
docker run -v nanobot-data:/root/.nanobot ghcr.io/sakiko999/docker-image-builder/nanobot:latest gateway
docker run -v /host/path:/data -e NANOBOT_HOME=/data ghcr.io/sakiko999/docker-image-builder/nanobot:latest gateway
```

### 构建参数

| 参数 | 默认值 | 说明 |
|------|--------|------|
| `NANOBOT_EXTRAS` | (空) | 额外 Python 依赖 |
| `NANOBOT_CHANNELS` | (空) | 预装 channel 依赖，逗号分隔 |

```bash
NANOBOT_CHANNELS=telegram ./scripts/build-local.sh nanobot
```

Health 端点: `http://127.0.0.1:18790/health`（可通过 `NANOBOT_HEALTH_URL` 覆盖）。

### Render 部署

`RENDER=true` 时入口点自动从 `/app/render-config.json` 初始化配置。
