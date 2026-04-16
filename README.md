<div align="center">

```
   ★       ★
██╗   ██╗██████╗  █████╗  ██████╗██╗  ██╗
██║   ██║██╔══██╗██╔══██╗██╔════╝██║ ██╔╝
██║   ██║██████╔╝███████║██║     █████╔╝
╚██╗ ██╔╝██╔══██╗██╔══██║██║     ██╔═██╗
 ╚████╔╝ ██████╔╝██║  ██║╚██████╗██║  ██╗
  ╚═══╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
   ★       ★
```

### 更方便，更省心

**一款上手即用的服务器数据备份脚本**

[![License: MIT](https://img.shields.io/badge/License-MIT-yellow.svg)](https://opensource.org/licenses/MIT)
[![Bash](https://img.shields.io/badge/Bash-4.0+-green.svg)](https://www.gnu.org/software/bash/)
[![GitHub stars](https://img.shields.io/github/stars/caigg188/vback?style=social)](https://github.com/caigg188/vback)

[English](#english) | [简体中文](#简体中文)

GitHub: [https://github.com/caigg188/vback](https://github.com/caigg188/vback)

</div>

---

## 简体中文

### 这是什么

`vback` 是一个单文件 Bash 备份脚本，用来把服务器上的目录打包后上传到 S3 兼容云存储。

它的目标一直很简单：

- 下载就能用
- 菜单式配置，不折腾
- 适合小中型项目做稳定的全量备份

#### 适合谁

- 需要把服务器目录定期备份到 S3 兼容存储的人
- 希望单脚本部署，不想引入复杂备份系统的人
- 需要在同一台机器上管理多套不同备份策略的人
- 需要为 SQLite 数据库做安全备份的人

#### 不适合谁

- 需要增量备份的人（目前仅支持全量备份）
- 需要备份编排和自动恢复的人（只负责备份，不负责恢复）
- 需要数据库专用备份系统的人（如 MySQL/PostgreSQL 专业备份）
- 需要备份 TB 级数据的人（更适合中小规模目录）

### v1.4.0 新特性

在 v1.3.x 基础上，v1.4.0 重点强化了安全性、可靠性和跨平台兼容：

- **安全加固**：使用 `mktemp` 替代可预测的 PID 临时路径，移除 `eval echo` 命令注入风险，数据文件加载前进行安全校验，SQLite `.backup` 使用参数化调用避免注入，锁文件使用 `mkdir` 原子操作避免竞态条件
- **上传校验**：上传后自动进行 MD5 完整性校验，确保数据无损到达远端
- **上传重试**：S3 上传失败自动重试（默认 3 次，间隔 5 秒），应对网络瞬断
- **恢复命令**：新增 `restore` 命令，支持交互式选择远端备份并下载解压到指定目录
- **macOS 兼容**：修复 `du -sb`、`stat -c`、`/proc`、`readlink -f`、`cp -a` 在 macOS 上的兼容问题
- **可靠性提升**：启用 `pipefail` 防止管道错误被吞掉，tar 部分失败时显示具体错误，rsync 不可用时发出明确警告，版本号比较支持非数字后缀（如 `-beta`）
- **代码优化**：提取 `setup_s3_tool()`、`get_file_size()`、`resolve_default_task_id()` 工具函数消除重复代码，配置文件写入使用 `printf %q` 安全引用

### v1.3.x 新特性

- **备份任务**：一个任务可包含多个待备份目录，并独立设置 `Prefix`、压缩、SQLite 安全备份、保留数量、排除规则。
- **多定时任务**：可以给不同备份任务分别配置不同的 cron 时间，例如同一天多次备份不同目录。
- **手动备份进度**：在交互终端执行备份时，会显示实时上传进度与速度；cron / 重定向日志场景默认静默。
- **兼容旧版本数据**：旧版 `~/.vback/config` 会自动映射成默认备份任务，原日志目录和原有配置可继续使用。

### 功能概览

- **单文件部署**：适合直接扔到服务器上使用
- **多任务备份**：一台机器可管理多套目录策略
- **多计划调度**：不同任务可不同频率执行
- **SQLite 安全备份**：减少活跃数据库文件直接拷贝的风险
- **S3 兼容多云**：缤纷云 S4 / Cloudflare R2 / AWS S3 / 阿里云 OSS / 七牛云 / Google Cloud / 自定义 S3
- **上传校验与重试**：MD5 完整性校验 + 自动重试机制
- **恢复功能**：交互式选择远端备份并下载解压
- **双语界面**：中文 / English

### 截图

<details>
<summary>点击展开</summary>

<br>

<img src="imgs/ScreenShot_001.png" width="600" alt="主界面">

<br><br>

<img src="imgs/ScreenShot_003.png" width="600" alt="配置向导">

<br><br>

<img src="imgs/ScreenShot_004.png" width="600" alt="备份过程">

</details>

### 安装与依赖

#### 系统要求

- Linux / macOS
- Bash 4.0+
- 必需：`tar`、`gzip`
- 推荐：`curl`、`awk`、`crontab`
- 上传工具：`s3cmd` 或 `aws-cli`（至少需要一个）
- 可选增强：`rsync`、`sqlite3`、`md5sum`/`md5`

#### 依赖检查

```bash
bash --version
tar --version
gzip --version
s3cmd --version   # 或 aws --version
```

#### 安装方式

方式一：本地运行（推荐快速体验）

```bash
curl -fsSL https://raw.githubusercontent.com/caigg188/vback/main/vback.sh -o vback.sh \
  && chmod +x vback.sh \
  && ./vback.sh
```

方式二：全局安装（推荐生产使用）

```bash
curl -fsSL https://raw.githubusercontent.com/caigg188/vback/main/vback.sh -o /usr/local/bin/vback \
  && chmod +x /usr/local/bin/vback \
  && vback
```

第一次运行会自动进入配置向导。

### 典型工作流

```bash
# 1. 首次配置
./vback.sh setup

# 2. 测试连接
./vback.sh test

# 3. 手动备份一次
./vback.sh backup --task web

# 4. 配置定时任务
./vback.sh install-cron --task web --cron "0 3 * * *"

# 5. 查看远端备份
./vback.sh status --task web

# 6. 恢复备份
./vback.sh restore --task web
```

### 快速开始

首次使用建议：

```bash
# 下载脚本
curl -fsSL https://raw.githubusercontent.com/caigg188/vback/main/vback.sh -o vback.sh \
  && chmod +x vback.sh

# 运行配置向导
./vback.sh setup

# 测试连接
./vback.sh test

# 执行备份
./vback.sh backup
```

### 核心概念

#### 1. 全局云配置

这一层配置的是 S3 连接信息：

- 云厂商
- Access Key / Secret Key
- Endpoint
- Bucket
- Region

#### 2. 备份任务

一个"备份任务"对应一组独立的备份策略，包含：

- 多个本地目录
- 一个云端目录前缀 `Prefix`
- 压缩开关与压缩级别
- SQLite 安全备份开关
- 备份保留数量
- 排除规则

可以理解为：旧版本里那一套"备份目录 + Prefix + 压缩设置"，在 `v1.3.x` 里被正式抽象成了一个任务。

#### 3. 定时任务

定时任务现在和备份任务解耦：

- 先创建备份任务
- 再给某个备份任务配置一个或多个 cron 表达式

这样就可以实现：

- 任务 A 每天凌晨备份
- 任务 B 每 6 小时备份一次
- 同一个任务一天内跑多次

### 使用方式

#### 交互模式

```bash
./vback.sh
```

推荐直接用菜单：

- `立即备份`
- `定时备份`
- `编辑配置 -> 备份任务`
- `编辑配置 -> S3 设置`

#### 命令行模式

```bash
# 打开菜单
./vback.sh

# 立即备份默认任务
./vback.sh backup

# 立即备份指定任务
./vback.sh backup --task web
./vback.sh backup --task-id task_web

# 查看指定任务的云端备份
./vback.sh status --task web

# 测试连接
./vback.sh test

# 同步已配置的所有定时任务到 crontab
./vback.sh install-cron

# 直接创建一个定时任务并同步
./vback.sh install-cron --task web --cron "0 */6 * * *" --schedule-name "web-6h"

# 移除当前安装到 crontab 的 vback 定时任务
./vback.sh remove-cron

# 查看当前配置
./vback.sh config

# 恢复备份（交互式选择）
./vback.sh restore --task web

# 重新进入配置向导
./vback.sh setup
```

#### 常用参数

```bash
# 详细输出
./vback.sh -v backup

# 指定配置目录中的 config 文件
./vback.sh -c /path/to/config backup

# 指定语言
./vback.sh --lang zh
./vback.sh --lang en

# 计划任务内部使用，通常不需要手动调用
./vback.sh backup --task web --scheduled
```

#### 上传重试配置

通过环境变量控制上传重试行为：

```bash
# 设置最大重试次数（默认 3）
S3_UPLOAD_RETRIES=5 ./vback.sh backup

# 设置重试间隔秒数（默认 5）
S3_UPLOAD_RETRY_DELAY=10 ./vback.sh backup
```

### 定时任务示例

```bash
# 每天 03:00
0 3 * * *

# 每 6 小时
0 */6 * * *

# 每天 09:30 / 14:30 / 21:30
30 9,14,21 * * *

# 每周日 02:00
0 2 * * 0
```

### 目录结构

`v1.3.x` 起，`~/.vback/` 目录通常如下：

```text
~/.vback/
├── config          # 全局配置 + 旧版兼容镜像字段
├── tasks           # 备份任务定义
├── schedules       # 定时任务定义
├── language        # 语言设置
└── logs/
    └── vback.log   # 运行日志
```

### 兼容旧版本

升级到 `v1.3.x` 时：

- 旧版 `config` 会自动迁移成一个默认备份任务
- 旧日志目录 `~/.vback/logs/` 不会被破坏
- 旧的 `backup / install-cron / remove-cron` 命令仍然可以继续使用
- 旧 cron 行在脚本更新后仍可继续执行；当你重新同步定时任务时，会切换到新的多任务模型

也就是说，正常更新脚本后，原来的配置和日志可以延续使用。

### 恢复方式

`v1.4.0` 起支持交互式恢复：

```bash
# 交互式选择远端备份并恢复
./vback.sh restore --task web
```

也可手动恢复（下载对应归档并解压）：

```bash
# s3cmd 示例
s3cmd get s3://your-bucket/your-prefix/project_20260308_030000.tar.gz

# 解压
tar -xzf project_20260308_030000.tar.gz
```

**注意事项**：

- 备份包内目录结构与源目录 basename 对应
- 如果启用了 `Prefix`，需要从对应云端前缀下下载
- 恢复前建议先在临时目录解压检查
- 定期验证备份文件可下载、可解压

### 常见问题

#### 1. 手动备份为什么有进度，cron 里没有？

这是设计行为：

- 手动交互终端：显示实时上传进度和速度
- cron / 重定向日志：默认关闭进度，避免日志被刷满

#### 2. 可以同时有多个定时任务吗？

可以。`v1.3.x` 已支持给同一个备份任务配置多个计划，也支持不同任务分别配置不同计划。

#### 3. 旧配置升级会不会丢？

不会。旧配置会自动映射成一个默认备份任务，并继续保留兼容字段。

#### 4. 支持增量备份吗？

暂不支持。目前仍是全量备份，定位是简单、稳定、可维护。

#### 5. `s3cmd` 和 `aws-cli` 优先使用哪个？

两者都可以，`vback` 会优先检测 `s3cmd`，其次使用 `aws-cli`。如果都没安装，首次运行时会提示安装 `s3cmd`。

建议：
- 国内环境优先 `s3cmd`，兼容性更好
- 已有 AWS 配置的环境可直接用 `aws-cli`

#### 6. cron 执行时为什么环境变量与手动运行不一致？

cron 默认使用 `/bin/sh` 和最小环境变量，可能导致：
- 脚本找不到 `bash` 或其他命令
- `PATH` 不包含某些工具路径

解决方法：
- 确保脚本 shebang 为 `#!/bin/bash`
- 在 cron 任务中指定完整路径：`/usr/local/bin/vback backup --scheduled`
- 或在 crontab 中设置 `PATH`：`PATH=/usr/local/bin:/usr/bin:/bin`

#### 7. 上传校验失败怎么办？

v1.4.0 默认启用 MD5 上传校验。如果校验失败，说明上传数据与本地不一致，建议：
- 检查网络稳定性
- 增加重试次数：`S3_UPLOAD_RETRIES=5`
- 重新执行备份

#### 8. macOS 上有什么已知问题？

v1.4.0 已修复主要 macOS 兼容性问题（`du`、`stat`、`readlink`、`cp -a`）。如仍有问题，请确保安装了 GNU coreutils。

### 限制与注意事项

#### 项目边界

- 目前仅支持全量备份，不支持增量备份
- 恢复功能为交互式下载解压，不提供自动恢复编排
- 不替代数据库专用备份系统（如 MySQL/PostgreSQL 专业工具）
- 适合小中型目录型备份场景，不建议用于 TB 级数据

#### 安全建议

- 不要把 `~/.vback/` 目录暴露给其他用户（已设置 700 权限）
- 建议给对象存储配置最小权限策略
- 首次启用前先手动执行一次 `backup` 和 `test`
- 定期验证备份可下载、可解压
- 定期检查日志文件 `~/.vback/logs/vback.log`
- v1.4.0 起临时文件使用 `mktemp` 生成不可预测路径，数据文件加载前进行安全校验

#### 性能建议

- 单个备份目录建议不超过 50GB
- 文件数量过多时，排除不必要的文件（如日志、缓存）
- 压缩级别 6 已能在速度和压缩率间取得较好平衡
- 建议在业务低峰期执行定时备份
- 安装 `rsync` 以支持排除规则和 SQLite 安全备份

### 系统要求

- Linux / macOS
- Bash 4.0+
- 必需：`tar`、`gzip`
- 推荐：`curl`、`awk`、`crontab`
- 可选：`rsync`、`sqlite3`、`md5sum`/`md5`
- 上传工具：`s3cmd` 或 `aws-cli`

### License

MIT

---

## English

### Overview

`vback` is a single-file Bash backup script for packaging local directories and uploading them to S3-compatible object storage.

`v1.4.0` builds on v1.3.x with major improvements to security, reliability, and cross-platform compatibility:

- **Security hardening**: `mktemp` for unpredictable temp paths, removed `eval echo` command injection risk, data file validation before sourcing, parameterized SQLite `.backup` call, atomic `mkdir` lock to prevent race conditions
- **Upload verification**: Automatic MD5 integrity check after upload to ensure data arrives intact
- **Upload retry**: Automatic retry on S3 upload failure (default 3 attempts, 5s interval) to handle transient network issues
- **Restore command**: New `restore` command for interactive backup selection, download, and extraction
- **macOS compatibility**: Fixed `du -sb`, `stat -c`, `/proc`, `readlink -f`, `cp -a` on macOS
- **Reliability**: Enabled `pipefail` to catch pipeline errors, show tar partial-failure details, warn when rsync unavailable, handle non-numeric version suffixes (e.g. `-beta`)
- **Code quality**: Extracted `setup_s3_tool()`, `get_file_size()`, `resolve_default_task_id()` utility functions, safe `printf %q` quoting in config writes

`v1.3.x` adds three major improvements:

- real-time upload progress and speed for manual backups
- multiple scheduled jobs in one installation
- first-class backup tasks, each with its own directories and remote prefix

#### Who Should Use It

- People who need to backup server directories to S3-compatible storage
- People who want single-script deployment without complex backup systems
- People who need to manage multiple backup strategies on one machine
- People who need safe backups for SQLite databases

#### Who Should NOT Use It

- People who need incremental backup (currently only full backup)
- People who need backup orchestration and auto-recovery (backup only, no restore)
- People who need dedicated database backup systems (e.g., MySQL/PostgreSQL tools)
- People who need to backup TB-scale data (better for small/medium directories)

### Highlights

- **Single-file deployment**: ready to use on any server
- **Multiple backup tasks**: manage multiple directory strategies on one machine
- **Multiple schedules**: different tasks can run at different frequencies
- **SQLite-safe backup**: reduces risk of copying active database files
- **S3-compatible multi-cloud**: Bitiful S4 / Cloudflare R2 / AWS S3 / Aliyun OSS / Qiniu Kodo / Google Cloud / Custom S3
- **Upload verification & retry**: MD5 integrity check + automatic retry on failure
- **Restore support**: interactive backup selection, download, and extraction
- **Bilingual interface**: English / 中文

### Installation & Requirements

#### System Requirements

- Linux / macOS
- Bash 4.0+
- Required: `tar`, `gzip`
- Recommended: `curl`, `awk`, `crontab`
- Upload tool: `s3cmd` or `aws-cli` (at least one required)
- Optional enhancements: `rsync`, `sqlite3`, `md5sum`/`md5`

#### Dependency Check

```bash
bash --version
tar --version
gzip --version
s3cmd --version   # or aws --version
```

#### Installation Methods

Option 1: Local execution (recommended for quick try)

```bash
curl -fsSL https://raw.githubusercontent.com/caigg188/vback/main/vback.sh -o vback.sh \
  && chmod +x vback.sh \
  && ./vback.sh
```

Option 2: Global installation (recommended for production)

```bash
curl -fsSL https://raw.githubusercontent.com/caigg188/vback/main/vback.sh -o /usr/local/bin/vback \
  && chmod +x /usr/local/bin/vback \
  && vback
```

First run will automatically enter the setup wizard.

### Typical Workflow

```bash
# 1. Initial setup
./vback.sh setup

# 2. Test connection
./vback.sh test

# 3. Manual backup
./vback.sh backup --task web

# 4. Configure scheduled task
./vback.sh install-cron --task web --cron "0 3 * * *"

# 5. View remote backups
./vback.sh status --task web

# 6. Restore from backup
./vback.sh restore --task web
```

### Quick Start

```bash
# Download script
curl -fsSL https://raw.githubusercontent.com/caigg188/vback/main/vback.sh -o vback.sh \
  && chmod +x vback.sh

# Run setup wizard
./vback.sh setup

# Test connection
./vback.sh test

# Execute backup
./vback.sh backup
```

### Core Concepts

#### 1. Global S3 Configuration

S3 connection settings:

- Cloud provider
- Access Key / Secret Key
- Endpoint
- Bucket
- Region

#### 2. Backup Task

A "backup task" represents an independent backup strategy:

- Multiple local directories
- A remote prefix
- Compression switch and level
- SQLite safe backup switch
- Backup retention count
- Exclude patterns

Think of it as: the old "backup directories + Prefix + compression settings" is now formalized as a task in `v1.3.x`.

#### 3. Scheduled Task

Scheduled tasks are now decoupled from backup tasks:

- First create a backup task
- Then assign one or more cron expressions to it

This enables:

- Task A backs up daily at midnight
- Task B backs up every 6 hours
- Same task runs multiple times a day

### Commands

```bash
# Interactive menu
./vback.sh

# Backup default task
./vback.sh backup

# Backup specific task
./vback.sh backup --task web
./vback.sh backup --task-id task_web

# Show remote backups for a task
./vback.sh status --task web

# Test S3 connectivity
./vback.sh test

# Sync all configured schedules into crontab
./vback.sh install-cron

# Create one schedule from CLI and sync it
./vback.sh install-cron --task web --cron "0 */6 * * *" --schedule-name "web-6h"

# Remove installed vback cron entries
./vback.sh remove-cron

# Show current configuration
./vback.sh config

# Restore from backup (interactive)
./vback.sh restore --task web

# Re-enter setup wizard
./vback.sh setup
```

#### Upload Retry Configuration

Control upload retry behavior via environment variables:

```bash
# Set max retry attempts (default 3)
S3_UPLOAD_RETRIES=5 ./vback.sh backup

# Set retry interval in seconds (default 5)
S3_UPLOAD_RETRY_DELAY=10 ./vback.sh backup
```

### Data Layout

```text
~/.vback/
├── config          # global config + legacy mirror fields
├── tasks           # task definitions
├── schedules       # schedule definitions
├── language        # language preference
└── logs/
    └── vback.log   # runtime logs
```

### Compatibility

When upgrading to `v1.3.x`:

- Existing `config` files are upgraded automatically into a default task
- Old logs remain untouched
- Old `backup`, `install-cron`, and `remove-cron` commands still work
- Old cron entries keep working until you resync schedules

### Restore

`v1.4.0` adds interactive restore support:

```bash
# Interactive restore: select remote backup and extract
./vback.sh restore --task web
```

Manual restore (download and extract):

```bash
# s3cmd example
s3cmd get s3://your-bucket/your-prefix/project_20260308_030000.tar.gz

# Extract
tar -xzf project_20260308_030000.tar.gz
```

**Notes**:

- Directory structure in backup matches source directory basename
- If `Prefix` is enabled, download from corresponding remote prefix
- Recommend extracting to a temp directory first to verify
- Periodically verify backups are downloadable and extractable

### FAQ

#### 1. Why does manual backup show progress but cron doesn't?

By design:

- Interactive terminal: shows real-time upload progress and speed
- cron / redirected log: progress disabled by default to avoid log flooding

#### 2. Can I have multiple scheduled tasks?

Yes. `v1.3.x` supports multiple schedules for the same task, and different schedules for different tasks.

#### 3. Will old configs be lost on upgrade?

No. Old configs are auto-mapped into a default task with compatible fields preserved.

#### 4. Is incremental backup supported?

Not yet. Currently only full backup, designed for simplicity, stability, and maintainability.

#### 5. Should I use `s3cmd` or `aws-cli`?

Both work. `vback` checks `s3cmd` first, then `aws-cli`. If neither is installed, it will prompt to install `s3cmd`.

Recommendations:
- Prefer `s3cmd` for better compatibility, especially in China
- Use `aws-cli` if you already have AWS configs

#### 6. Why are environment variables different in cron?

cron uses `/bin/sh` and minimal environment by default, which may cause:
- Script can't find `bash` or other commands
- `PATH` doesn't include some tool paths

Solutions:
- Ensure shebang is `#!/bin/bash`
- Use full path in cron: `/usr/local/bin/vback backup --scheduled`
- Or set `PATH` in crontab: `PATH=/usr/local/bin:/usr/bin:/bin`

#### 7. What if upload verification fails?

v1.4.0 enables MD5 upload verification by default. If verification fails, the uploaded data differs from local. Suggestions:
- Check network stability
- Increase retry count: `S3_UPLOAD_RETRIES=5`
- Re-run the backup

#### 8. Are there known macOS issues?

v1.4.0 has fixed major macOS compatibility issues (`du`, `stat`, `readlink`, `cp -a`). If issues persist, ensure GNU coreutils is installed.

### Limitations & Notes

#### Project Boundaries

- Currently only full backup, no incremental support
- Restore is interactive download + extract, no automated recovery orchestration
- Not a replacement for dedicated database backup systems (e.g., MySQL/PostgreSQL tools)
- Suitable for small/medium directory backup scenarios, not recommended for TB-scale data

#### Security Recommendations

- Don't expose `~/.vback/` to other users (already set to 700 permission)
- Configure minimum-privilege policy for object storage
- Run `backup` and `test` manually before first scheduled run
- Periodically verify backups are downloadable and extractable
- Check log file `~/.vback/logs/vback.log` regularly
- Since v1.4.0: temp files use `mktemp` for unpredictable paths, data files are validated before loading

#### Performance Recommendations

- Single backup directory should not exceed 50GB
- Exclude unnecessary files (logs, caches) if file count is large
- Compression level 6 provides good balance between speed and ratio
- Schedule backups during off-peak hours
- Install `rsync` for exclude pattern support and SQLite safe backup

### Requirements

- Linux / macOS
- Bash 4.0+
- required: `tar`, `gzip`
- recommended: `curl`, `awk`, `crontab`
- optional: `rsync`, `sqlite3`, `md5sum`/`md5`
- upload tool: `s3cmd` or `aws-cli`

### License

MIT
