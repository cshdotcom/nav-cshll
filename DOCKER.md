# Docker 部署 - 发现导航 (Nav)

将 Fork 后的导航项目构建为 Docker 镜像并发布到 Docker Hub。

## 镜像信息

- **Docker Hub 仓库**: `cshdotcom/nav`
- **多架构支持**: `linux/amd64` + `linux/arm64`
- **基础镜像**: `nginx:1.27-alpine` (运行时) / `node:22-bookworm-slim` (构建时)
- **最终镜像大小**: ~50MB (压缩后)

## 文件说明

| 文件 | 作用 |
|------|------|
| `Dockerfile` | 多阶段构建：Node 构建 → nginx 运行 |
| `nginx.conf` | nginx 配置：SPA 路由回退、gzip、缓存策略、安全头 |
| `.dockerignore` | 减少构建上下文体积，加速构建 |
| `docker-compose.yml` | 一键 `docker compose up` 部署 |
| `build-and-push.sh` | 本地一键构建 + 推送 + 打 tag 脚本 |
| `.github/workflows/docker.yml` | GitHub Actions 自动构建（推 main 或打 tag 时触发） |

## 快速开始

### 方式 1：拉取已发布的镜像（推荐终端用户）

```bash
docker pull cshdotcom/nav:latest
docker run -d --name nav -p 8080:80 --restart unless-stopped cshdotcom/nav:latest
```

访问 http://localhost:8080 即可。

### 方式 2：本地构建并推送（开发者）

**前置条件：**

1. 安装 [Docker](https://docs.docker.com/get-docker/) (含 buildx)
2. 登录 Docker Hub（使用 Access Token，不要用密码）：
   ```bash
   # 在 https://hub.docker.com/settings/security 创建 Access Token
   docker login -u cshdotcom
   ```

**一键构建 + 推送：**

```bash
# 自动从 package.json 读取版本号，打 :vX.Y.Z + :latest 两个 tag
./build-and-push.sh

# 或显式指定版本
./build-and-push.sh v1.0.0

# 只构建不推送（本地测试）
./build-and-push.sh v1.0.0 --no-push
```

**只本地构建（不用脚本）：**

```bash
docker build -t cshdotcom/nav:test .
docker run --rm -p 8080:80 cshdotcom/nav:test
```

### 方式 3：docker compose

```bash
docker compose up -d --build
# 访问 http://localhost:8080
docker compose logs -f
docker compose down
```

### 方式 4：GitHub Actions 自动构建（推荐生产）

在 GitHub Fork 仓库设置中添加以下 Secrets：

1. 进入 `https://github.com/cshdotcom/nav-cshll/settings/secrets/actions`
2. 添加：
   - `DOCKERHUB_USERNAME` = `cshdotcom`
   - `DOCKERHUB_TOKEN` = Docker Hub Access Token

然后：
- 推送到 `main` 分支 → 自动构建 `:latest` + `:sha-<git>` + `:v<package-version>`
- 推送 `v1.0.0` 格式的 git tag → 自动构建 `:v1.0.0` + `:latest` 并发布 Release
- 手动触发：Actions 页 → "Docker Build & Push" → Run workflow

## Tag 策略

| Tag | 含义 |
|-----|------|
| `cshdotcom/nav:latest` | 最新稳定版 |
| `cshdotcom/nav:v17.0.0` | 与 package.json 版本对应 |
| `cshdotcom/nav:sha-abc1234` | 对应 git commit short SHA |
| `cshdotcom/nav:v1.0.0` | 自定义 release tag |

## 配置说明

镜像构建时会读取 `nav.config.yaml` 的配置。当前 Fork 配置：

```yaml
gitRepoUrl: https://github.com/cshdotcom/nav-cshll  # 你的 Fork 地址
hashMode: true                                       # Hash 路由模式
# address: ''                                       # 未填写 = Fork 模式
```

如需切换为 **自有部署模式**（数据存在本地 Docker 卷而非 GitHub 仓库），修改 `nav.config.yaml`：

```yaml
gitRepoUrl: https://github.com/cshdotcom/nav-cshll
hashMode: false         # Docker 部署建议关闭 Hash 模式
address: 'http://localhost:8080'   # 你的部署地址，填了就进入自有部署模式
password: your-admin-password      # 后台登录密码
port: 7777
```

然后重新构建镜像即可。

## K8s 部署示例

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: nav
spec:
  replicas: 2
  selector:
    matchLabels:
      app: nav
  template:
    metadata:
      labels:
        app: nav
    spec:
      containers:
      - name: nav
        image: cshdotcom/nav:latest
        ports:
        - containerPort: 80
        resources:
          limits:
            memory: "128Mi"
            cpu: "200m"
        livenessProbe:
          httpGet:
            path: /healthz
            port: 80
          initialDelaySeconds: 5
          periodSeconds: 30
---
apiVersion: v1
kind: Service
metadata:
  name: nav
spec:
  type: ClusterIP
  selector:
    app: nav
  ports:
  - port: 80
    targetPort: 80
```

## 故障排查

**Q: 构建时 `pnpm install` 报错 puppeteer 下载失败？**
A: Dockerfile 已设置 `PUPPETEER_SKIP_DOWNLOAD=true`。如果你确实需要 puppeteer 抓取网站信息（在 `data/settings.json` 中将 `spiderIcon`/`spiderTitle` 设为 `'EMPTY'` 或 `'ALWAYS'`），请删除 Dockerfile 中的 `PUPPETEER_SKIP_DOWNLOAD=true` 并安装 Chromium：

```dockerfile
RUN apk add --no-cache chromium nss freetype harfbuzz
ENV PUPPETEER_EXECUTABLE_PATH=/usr/bin/chromium-browser
```

**Q: 推送到 Docker Hub 提示 401 Unauthorized？**
A: 检查：
1. `docker login -u cshdotcom` 时输入的是 **Access Token** 而不是密码
2. Token 在 https://hub.docker.com/settings/security 创建，需要 Read/Write 权限
3. Token 没有过期或被撤销

**Q: 多架构构建很慢？**
A: arm64 build 需要通过 QEMU 模拟，比 amd64 慢 3-5 倍。如果只需要 amd64，修改 `build-and-push.sh`：
```bash
PLATFORMS="linux/amd64"
```

**Q: 镜像太大？**
A: 当前镜像 ~50MB（nginx:alpine + 静态文件）。如需进一步压缩，可以使用 `nginx:alpine-slim` 或更换为 `caddy:alpine`。

## 安全提示

- **GitHub Token** 和 **Docker Hub Token** 都不要硬编码到 `Dockerfile` 或脚本中，统一通过环境变量或 GitHub Secrets 注入
- `nav.config.yaml` 中的 `password` 字段如果硬编码会进入镜像层，建议运行时通过环境变量覆盖或挂载配置文件
- 定期更新基础镜像：`docker pull nginx:1.27-alpine` + 重新构建
