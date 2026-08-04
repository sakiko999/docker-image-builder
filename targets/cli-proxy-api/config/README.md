# cli-proxy-api 覆盖层文档

## 容器运行时

该镜像默认以 **root 用户** 运行，不会降权。

- **工作目录**: `/CLIProxyAPI`（上游已放入二进制与 `config.example.yaml`）
- **默认配置**: `/CLIProxyAPI/config.yaml`（首次启动自动从 `config.example.yaml` 初始化）
- **默认 HOME**: `/root`
- **认证目录**: `/root/.cli-proxy-api`（不存在时由入口点自动创建）

### 挂载示例

```bash
# 持久化认证目录
docker run -v cli-proxy-api-auth:/root/.cli-proxy-api \
  -p 8317:8317 ghcr.io/sakiko999/docker-image-builder/cli-proxy-api:latest

# 使用外部挂载的配置文件（跳过自动 bootstrap）
docker run -v /host/config.yaml:/config.yaml:ro \
  -e CONFIG_PATH=/config.yaml \
  -p 8317:8317 ghcr.io/sakiko999/docker-image-builder/cli-proxy-api:latest
```

### 配置 bootstrap

入口点在 `CONFIG_PATH` 未设置且 `/CLIProxyAPI/config.yaml` 不存在时，自动从
`/CLIProxyAPI/config.example.yaml` 拷贝一份。该操作幂等：已存在或已挂载的配置不会被覆盖。

Health 端点: `http://127.0.0.1:8317/healthz`（可通过 `CLI_PROXY_API_HEALTH_URL` 覆盖）。
