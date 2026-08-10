# vback

轻量、可靠的单机备份面板。vback v2 使用一个 Go 主程序提供 Web 控制台、CLI、调度、运行历史和安全恢复，并调用 [restic](https://restic.net/) 将加密增量快照保存到 S3 兼容对象存储。

> v2 当前处于开发预览阶段。生产环境继续使用 `vback.sh` v1.4.2，并先在测试仓库验证 v2。

## v2 的变化

- 响应式 Web 面板：适配手机、平板、桌面以及系统明暗主题。
- 增量、去重、加密快照：由 restic 提供，不再为每轮备份生成完整 tar 包。
- 结构化运行记录：显示进度、处理文件数、新增数据量、退出状态和错误原因。
- 内置计划调度：标准五字段 cron、IANA 时区、可预览下次执行时间。
- 自动维护：每周元数据检查，可选每月完整数据检查和独立 prune cron。
- 安全恢复：Web 只能恢复到受控 staging 目录，不直接覆盖系统路径。
- 多仓库、多任务：任务使用稳定 UUID 和显式来源，不再依赖目录 basename。
- 本机优先安全模型：默认只监听 `127.0.0.1:9898`，凭证存放在独立的 `0600` 文件中。
- v1 安全迁移：严格解析已知字段，不执行旧配置中的 Shell 内容。

v2.0 暂不包含多机器中心、团队角色、远程覆盖系统路径和 SaaS 能力。

## 架构

```text
Browser
   │ HTTP + SSE (127.0.0.1:9898)
   ▼
vback Go service
   ├── SQLite metadata / runs / audit
   ├── local scheduler
   ├── secret files (0600)
   └── controlled restic processes
             │
             ▼
       S3-compatible storage
```

前端使用 Preact + TypeScript，构建产物约 50 KB，并内嵌到 Go 二进制。运行服务器不需要 Node.js。

## 开发运行

依赖：

- Go 1.24+
- Node.js 22+（仅构建前端）
- restic
- sqlite3（仅在任务配置 SQLite 一致性来源时必需）

```bash
# 构建前端
cd web
npm ci
npm run build
cd ..

# 测试与构建
go test ./...
go build -o dist/vback ./cmd/vback

# 启动
VBACK_DATA_DIR="$PWD/data" ./dist/vback serve
```

首次启动会在日志中输出一次性 Setup Token。打开 `http://127.0.0.1:9898`，依次完成：

1. 创建管理员密码。
2. 配置并初始化 S3/restic 仓库。
3. 创建备份任务。
4. 执行第一次备份并检查快照。

远程访问建议使用 SSH 隧道：

```bash
ssh -L 9898:127.0.0.1:9898 user@server
```

随后在本机浏览器打开 `http://127.0.0.1:9898`。

## CLI

```bash
vback serve
vback backup <job-id>
vback backup <job-id> --dry-run
vback snapshots <job-id>
vback restore <snapshot-id> --job <job-id> --path /optional/path
vback check <repository-id>
vback doctor
vback import-v1 --from ~/.vback
vback import-v1 --from ~/.vback --confirm --restic-password 'save-this-offline'
vback version
```

`import-v1` 默认只显示迁移预览。加上 `--confirm` 后才写入 v2 数据库，并且必须显式提供、离线保存新的 restic 恢复密钥。导入的计划默认禁用，避免与 v1 crontab 重复运行；旧 tar 对象不会被删除或伪装成 restic 快照。

## 数据目录

root/systemd 模式默认使用 `/var/lib/vback`；普通用户使用 `$XDG_STATE_HOME/vback` 或 `~/.local/state/vback`。

```text
/var/lib/vback/
├── vback.db
├── setup-token
├── secrets/
├── staging/
└── restores/
```

可通过 `VBACK_DATA_DIR` 修改。程序拒绝把文件系统根目录作为数据目录。

## 网络安全

- 默认监听 `127.0.0.1:9898`。
- 非本机监听必须设置 `VBACK_ALLOW_REMOTE=true`。
- 非本机监听还必须配置 `VBACK_TLS_CERT` 和 `VBACK_TLS_KEY`；只有明确设置 `VBACK_INSECURE_HTTP=true` 才允许明文远程监听。
- 推荐让 Caddy/Nginx 在同机代理 `127.0.0.1:9898`，不要直接暴露服务端口。
- 管理员密码使用 Argon2id；会话 Cookie 为 HttpOnly、SameSite=Strict；写接口需要 CSRF token。

## systemd 安装

先构建 `dist/vback` 并安装 restic，然后：

```bash
sudo sh scripts/install.sh ./dist/vback
sudo journalctl -u vback -n 20
```

服务默认以独立 `vback` 用户运行。请使用 ACL 或组权限授予它对备份来源的只读访问：

```bash
sudo setfacl -R -m u:vback:rX /srv/example
sudo setfacl -R -d -m u:vback:rX /srv/example
```

## v1.4.2 维护线

`vback.sh` 仍可独立运行，适用于不准备迁移到 restic 的现有用户：

```bash
bash vback.sh setup
bash vback.sh backup
bash vback.sh restore
```

v1.4.2 修复了：

- 恢复列表在子进程中丢失。
- multipart ETag 被错误当作普通 MD5。
- provider endpoint 的 region 占位符未替换。
- 同 basename 来源可能覆盖。
- S3 测试忽略真实退出码、测试文件未正确清理。
- 无 rsync 时排除规则失效。
- 危险数据目录可进入递归重置。
- macOS 默认 Bash 3.2 静默破坏关联数组。

v1 现在明确要求 Bash 4.0+。macOS 需要先安装新版 Bash：

```bash
brew install bash
/opt/homebrew/bin/bash ./vback.sh
```

## 测试

```bash
make test
```

测试包含：

- Go 数据层、认证、严格 v1 配置解析。
- fake restic 成功、立即取消和退出码 3 场景。
- v1 Bash 语法与关键安全回归检查。
- Preact/TypeScript 生产构建。
- Playwright 首次向导，以及 360/768/1440px 和明暗主题布局检查。
- CI MinIO 两轮增量备份、快照查询和受控 staging 恢复。

CI 同时运行 ShellCheck、Go race detector，并构建静态 Linux 二进制。MinIO 集成测试可在本机已有测试 bucket 时运行：

```bash
VBACK_E2E_ENDPOINT=http://127.0.0.1:9000 \
VBACK_E2E_ACCESS_KEY=vbacktest \
VBACK_E2E_SECRET_KEY=vbacktestsecret \
bash tests/e2e_minio.sh
```

## 资源目标

- 内嵌前端压缩后低于 250 KB（当前约 17 KB gzip）。
- vback 服务空闲 RSS 目标低于 50 MB。
- 一个仓库默认只执行一个写操作。
- 低资源任务减少进度事件频率，并允许设置上传带宽限制。

restic 本身在 backup、check 和 prune 时需要额外 CPU、内存与临时空间。首次在低配机器使用前应先执行 dry-run 和小数据集备份。

## License

[MIT](LICENSE)
