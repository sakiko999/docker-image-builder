下面是一个适合作为 AI agent / 开发者实施指导的 `plan.md`。目标是创建一个 **Docker Image Overlay Repository**，用于跟踪 `HKUDS/nanobot` 上游 tag，并自动构建、发布自定义 Docker 镜像。

```markdown
# nanobot-image-builder Plan

## 1. 项目目标

创建一个独立的 Docker Image Overlay Repository，用于维护 `HKUDS/nanobot` 的自定义镜像构建流程。

该仓库不 fork 上游源码，而是作为镜像交付层存在：

```

HKUDS/nanobot
|
| checkout source/tag
|
v
nanobot-image-builder
|
| custom Dockerfile
| config
| patches
|
v
Docker Image
|
v
ghcr.io/<owner>/nanobot

```

目标：

- 自动跟踪上游版本 tag
- 使用指定版本源码构建镜像
- 使用自定义 Dockerfile
- 自动推送 GHCR
- 保留版本可追溯性
- 不维护源码 fork


---

# 2. Repository Structure

最终结构：

```

nanobot-image-builder/

├── .github/
│   └── workflows/
│       └── build-image.yml
│
├── docker/
│   ├── Dockerfile
│   ├── entrypoint.sh
│   └── healthcheck.sh
│
├── patches/
│   └── README.md
│
├── config/
│   └── README.md
│
├── scripts/
│   ├── check-upstream-tag.sh
│   └── build-local.sh
│
├── versions.json
│
├── README.md
└── plan.md

```

---

# 3. Repository Responsibilities

## 3.1 不保存上游源码

禁止：

```

src/
package.json
main.py

```

等上游文件进入本仓库。


源码来源：

```

[https://github.com/HKUDS/nanobot](https://github.com/HKUDS/nanobot)

````

通过 GitHub Actions 动态 checkout。


---

# 4. Version Tracking


## versions.json

用于记录当前构建版本。


示例：

```json
{
  "upstream": "HKUDS/nanobot",
  "tag": "v1.2.0",
  "image": "ghcr.io/<owner>/nanobot"
}
````

用途：

* 避免重复构建
* 记录构建来源
* 支持手动回滚

---

# 5. Docker Build Design

## 5.1 自定义 Dockerfile

位置：

```
docker/Dockerfile
```

Dockerfile 不直接依赖当前目录源码。

Build context：

```
.
├── docker/
│   └── Dockerfile
│
└── source/
    └── nanobot source
```

示例：

```dockerfile
FROM python:3.12-slim


WORKDIR /app


COPY source/ .


RUN pip install -r requirements.txt


COPY config/ /app/config/


COPY docker/entrypoint.sh /


ENTRYPOINT [
"/entrypoint.sh"
]
```

---

# 6. Upstream Version Detection

## 6.1 Trigger

支持：

### Scheduled

每天检查：

```yaml
schedule:
  - cron: "0 */6 * * *"
```

### Manual

支持：

```yaml
workflow_dispatch:
```

---

## 6.2 Tag Detection

流程：

```
GitHub Actions

        |
        |
git ls-remote upstream tags

        |
        |
compare versions.json

        |
        |
new tag?

        |
        +---- no
        |
        +---- yes
              |
              build image
```

---

# 7. GitHub Actions Workflow

文件：

```
.github/workflows/build-image.yml
```

职责：

1. 获取最新 upstream tag
2. checkout upstream source
3. checkout overlay repository
4. 应用 patches
5. build docker image
6. push registry

流程：

```
checkout overlay

        |

checkout HKUDS/nanobot@tag

        |

apply patches

        |

docker buildx build

        |

push ghcr.io
```

---

# 8. Image Tag Strategy

镜像标签：

```
ghcr.io/<owner>/nanobot:<upstream-tag>

ghcr.io/<owner>/nanobot:latest
```

例如：

```
nanobot:v1.2.0

nanobot:latest
```

同时建议增加：

```
nanobot:<git-sha>
```

用于精确回滚。

示例：

```
nanobot:v1.2.0
nanobot:a81c92f
nanobot:latest
```

---

# 9. Patch System

目录：

```
patches/
```

用途：

* 修复上游 bug
* 修改默认配置
* 修改启动逻辑

执行：

```bash
for patch in patches/*.patch
do
    patch -p1 < $patch
done
```

没有 patch 时：

```
patches/
└── README.md
```

---

# 10. Configuration Overlay

目录：

```
config/
```

用途：

存放：

* 默认配置
* 环境模板
* 启动脚本

例如：

```
config/
├── production.yaml
└── example.env
```

Docker:

```dockerfile
COPY config /
```

---

# 11. Local Development

提供：

```
scripts/build-local.sh
```

支持：

```bash
./scripts/build-local.sh v1.2.0
```

等价：

```
checkout upstream tag

docker build

local image
```

方便 CI 前测试。

---

# 12. Security

GitHub Actions permissions:

```yaml
permissions:
  contents: read
  packages: write
```

使用：

```
GITHUB_TOKEN
```

发布：

```
ghcr.io
```

不保存 Docker Hub 密钥。

---

# 13. Release Workflow

未来可以增加：

```
GitHub Release

        |
        |
create image release

        |
        |
generate changelog
```

发布：

```
nanobot:v1.2.0
```

---

# 14. Design Principles

## 不 fork

原因：

* 避免同步维护
* 避免权限问题
* 保持 upstream clean

## 镜像版本独立管理

源码：

```
HKUDS/nanobot
```

交付：

```
nanobot-image-builder
```

## 构建必须可复现

任何镜像必须能追溯：

```
image tag

        |

upstream commit

        |

overlay commit
```

---

# 15. Future Extensions

可能增加：

* 多架构构建

```
linux/amd64
linux/arm64
```

* SBOM

```
syft
```

* 镜像签名

```
cosign
```

* 自动安全扫描

```
trivy
```

* 多环境镜像

```
nanobot:latest
nanobot:stable
nanobot:dev
```

---

# Summary

该仓库定位：

> 一个独立的 Docker 镜像交付层，而不是源码 fork。

核心链路：

```
Upstream Tag

      ↓

GitHub Actions

      ↓

Checkout Source

      ↓

Apply Overlay

      ↓

Docker Build

      ↓

GHCR Image
```

该设计适合长期维护自动同步第三方项目镜像。

```

这个设计后续如果扩展到多个上游项目（例如同时维护多个 AI agent 镜像），也可以自然演化成一个统一的 `docker-image-overlay` 模板仓库。
```
