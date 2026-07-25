# Configuration templates

Only non-secret templates belong in this directory. A later build step copies them to `/opt/nanobot-overlay/config`; it never overwrites a mounted `NANOBOT_HOME` runtime directory.

## Root 运行环境

该覆盖层镜像默认以 **root 用户** 运行，不会降权到 `nanobot` 用户。

- 默认数据目录: `/root/.nanobot`（可通过 `NANOBOT_HOME` 环境变量覆盖）
- 默认 HOME: `/root`
- 数据目录不存在时由入口点自动创建

## 容器挂载示例

```bash
# 默认 root 数据目录
docker run -v nanobot-data:/root/.nanobot ghcr.io/sakiko999/docker-image-builder/nanobot:latest gateway

# 自定义数据目录
docker run -v /host/path:/data -e NANOBOT_HOME=/data ghcr.io/sakiko999/docker-image-builder/nanobot:latest gateway
```

## Render 部署

当 `RENDER=true` 时，入口点自动从 `/app/render-config.json` 初始化配置文件到数据目录。
