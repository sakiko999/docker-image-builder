# Docker Image Builder

配置驱动的上游项目镜像交付层。不 fork 上游源码，跟踪最新 Git tag 构建并发布到 GHCR。

## 当前目标

- `HKUDS/nanobot` → `ghcr.io/sakiko999/nanobot:latest`

参见 `docs/adding-target.md` 添加新目标。

## 仓库结构

```
targets/<id>/target.json     目标元数据
targets/<id>/build.sh        构建适配器
targets/<id>/Dockerfile      最终镜像覆盖层
targets/<id>/patches/        上游源码补丁（可选）
targets/<id>/config/         配置文件模板（可选）
scripts/                     通用构建引擎
state/<id>.json              上次成功构建记录（CI 提交）
```

## 本地构建

```bash
./scripts/build-local.sh nanobot
```

构建 `:latest` 和 `:<upstream-tag>` 两个镜像，不写入 state，不推送。

## 自动化

每 6 小时检查上游新 tag，也可手动触发：

```bash
gh workflow run build-images.yml -f target=nanobot
```

工作流运行测试套件→构建镜像→推送 GHCR→提交 state 文件。
