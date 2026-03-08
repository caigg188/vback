<div align="center">

```
        _                _
 __   _| |__   __ _  ___| | __
 \ \ / / '_ \ / _` |/ __| |/ /
  \ V /| |_) | (_| | (__|   <
   \_/ |_.__/ \__,_|\___|_|\_\
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

`v1.3.0` 这次重点补了三个能力：

- 手动执行“立即备份”时，实时显示上传进度和速度
- 支持一个脚本里管理多个定时任务
- 引入“备份任务”概念，每个任务可独立配置目录、云端目录、压缩与保留策略

### v1.3.0 新特性

- **备份任务**：一个任务可包含多个待备份目录，并独立设置 `Prefix`、压缩、SQLite 安全备份、保留数量、排除规则。
- **多定时任务**：可以给不同备份任务分别配置不同的 cron 时间，例如同一天多次备份不同目录。
- **手动备份进度**：在交互终端执行备份时，会显示实时上传进度与速度；cron / 重定向日志场景默认静默。
- **兼容旧版本数据**：旧版 `~/.vback/config` 会自动映射成默认备份任务，原日志目录和原有配置可继续使用。

### 功能概览

- **开箱即用**：单脚本，无复杂部署
- **多云支持**：缤纷云 S4 / Cloudflare R2 / AWS S3 / 阿里云 OSS / 七牛云 / Google Cloud / 自定义 S3
- **SQLite 安全备份**：优先使用 `.backup`
- **压缩上传**：默认 `tar + gzip`
- **备份任务管理**：一个脚本可管理多个备份任务
- **多定时任务**：支持多个 cron 计划
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

### 快速开始

```bash
curl -fsSL https://raw.githubusercontent.com/caigg188/vback/main/vback.sh -o vback.sh \
  && chmod +x vback.sh \
  && ./vback.sh
```

第一次运行会自动进入配置向导。

### 核心概念

#### 1. 全局云配置

这一层配置的是 S3 连接信息：

- 云厂商
- Access Key / Secret Key
- Endpoint
- Bucket
- Region

#### 2. 备份任务

一个“备份任务”对应一组独立的备份策略，包含：

- 多个本地目录
- 一个云端目录前缀 `Prefix`
- 压缩开关与压缩级别
- SQLite 安全备份开关
- 备份保留数量
- 排除规则

可以理解为：旧版本里那一套“备份目录 + Prefix + 压缩设置”，在 `v1.3.0` 里被正式抽象成了一个任务。

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

`v1.3.0` 起，`~/.vback/` 目录通常如下：

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

升级到 `v1.3.0` 时：

- 旧版 `config` 会自动迁移成一个默认备份任务
- 旧日志目录 `~/.vback/logs/` 不会被破坏
- 旧的 `backup / install-cron / remove-cron` 命令仍然可以继续使用
- 旧 cron 行在脚本更新后仍可继续执行；当你重新同步定时任务时，会切换到新的多任务模型

也就是说，正常更新脚本后，原来的配置和日志可以延续使用。

### 恢复方式

`vback` 只负责备份，不负责恢复。恢复时直接下载对应归档并解压即可。

```bash
# s3cmd 示例
s3cmd get s3://your-bucket/your-prefix/project_20260308_030000.tar.gz

# 解压
tar -xzf project_20260308_030000.tar.gz
```

### 常见问题

#### 1. 手动备份为什么有进度，cron 里没有？

这是设计行为：

- 手动交互终端：显示实时上传进度和速度
- cron / 重定向日志：默认关闭进度，避免日志被刷满

#### 2. 可以同时有多个定时任务吗？

可以。`v1.3.0` 已支持给同一个备份任务配置多个计划，也支持不同任务分别配置不同计划。

#### 3. 旧配置升级会不会丢？

不会。旧配置会自动映射成一个默认备份任务，并继续保留兼容字段。

#### 4. 支持增量备份吗？

暂不支持。目前仍是全量备份，定位是简单、稳定、可维护。

### 系统要求

- Linux / macOS
- Bash 4.0+
- 必需：`tar`、`gzip`
- 可选：`rsync`、`sqlite3`
- 上传工具：`s3cmd` 或 `aws-cli`

### License

MIT

---

## English

### Overview

`vback` is a single-file Bash backup script for packaging local directories and uploading them to S3-compatible object storage.

`v1.3.0` adds three major improvements:

- real-time upload progress and speed for manual backups
- multiple scheduled jobs in one installation
- first-class backup tasks, each with its own directories and remote prefix

### Highlights

- **Backup tasks**: each task can manage multiple source directories, its own remote prefix, compression settings, retention, SQLite-safe mode, and exclude patterns
- **Multiple schedules**: assign one or more cron expressions to any backup task
- **Manual progress view**: interactive backups now show live upload progress and speed
- **Backward compatibility**: old `~/.vback/config` data is auto-mapped into a default task

### Quick Start

```bash
curl -fsSL https://raw.githubusercontent.com/caigg188/vback/main/vback.sh -o vback.sh \
  && chmod +x vback.sh \
  && ./vback.sh
```

### Commands

```bash
# interactive menu
./vback.sh

# backup default task
./vback.sh backup

# backup a specific task
./vback.sh backup --task web
./vback.sh backup --task-id task_web

# show remote backups for a task
./vback.sh status --task web

# test S3 connectivity
./vback.sh test

# sync all configured schedules into crontab
./vback.sh install-cron

# create one schedule from CLI and sync it
./vback.sh install-cron --task web --cron "0 */6 * * *" --schedule-name "web-6h"

# remove installed vback cron entries
./vback.sh remove-cron
```

### Data Layout

```text
~/.vback/
├── config
├── tasks
├── schedules
├── language
└── logs/
    └── vback.log
```

### Compatibility

- existing `config` files are upgraded automatically into the new task model
- old logs remain untouched
- old `backup`, `install-cron`, and `remove-cron` commands still work
- old cron entries keep working until you resync schedules

### Requirements

- Linux / macOS
- Bash 4.0+
- required: `tar`, `gzip`
- optional: `rsync`, `sqlite3`
- upload tool: `s3cmd` or `aws-cli`

### License

MIT
