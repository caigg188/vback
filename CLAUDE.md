# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

`vback` is a single-file Bash backup script (~3800 lines) that uploads server directories to S3-compatible cloud storage. It distributes as one executable file (`vback.sh`) with no external dependencies beyond standard Unix tools.

**Critical constraint**: This is intentionally a single-file script. Never split it into modules or separate files.

## Commands

### Testing & Development
```bash
# Manual testing workflow
./vback.sh setup              # Interactive configuration wizard
./vback.sh test               # Test S3 connection
./vback.sh backup             # Execute backup manually
./vback.sh backup --task web  # Backup specific task
./vback.sh status             # View remote backups
./vback.sh restore            # Restore from backup (interactive)

# Cron management
./vback.sh install-cron --task web --cron "0 3 * * *"
./vback.sh remove-cron

# Configuration
./vback.sh config             # Show current config
./vback.sh menu               # Interactive menu (default)
./vback.sh --lang zh menu     # Chinese interface
```

### No Automated Tests
This project has no test suite. Verify changes by running the commands above against a test S3 bucket.

## Architecture

### Single-File Structure
The script is organized into functional sections (approximate line ranges):

- **80-700**: Internationalization (`load_lang_en`, `load_lang_zh`)
- **750-900**: Cloud provider configs, color setup, data directory initialization
- **900-1250**: Task/schedule CRUD operations, config persistence
- **1250-1400**: Logging system, UI primitives (boxes, colors, prompts)
- **1650-1800**: S3 abstraction layer (`s3_put`, `s3_list`, `s3_rm`, `s3_test`)
- **1825-1870**: SQLite safe backup (uses `.backup` command)
- **1909-1960**: Lock file management
- **1961-2120**: Core backup flow (`backup_dir`, `do_backup`)
- **2125-2190**: Cron synchronization
- **2654-3500**: Interactive menus (TUI)
- **3487-3632**: CLI argument parsing and main entrypoint

### Data Model (v1.3.x)

**Task**: A backup policy containing:
- Multiple source directories
- Cloud prefix (destination path)
- Compression settings (enabled, level 1-9)
- SQLite safe backup toggle
- Retention count (max backups to keep)
- Exclude patterns

**Schedule**: A cron expression mapped to a task

**Storage**: Shell variable files in `~/.vback/`:
- `config` - Global S3 credentials and settings
- `tasks` - Task definitions (sourced as Bash variables)
- `schedules` - Cron schedule definitions
- `logs/vback.log` - Execution log

### Key Design Patterns

**Config Persistence**: Files are generated as valid Bash scripts using `printf %q` for safe quoting, then `source`d on load. When modifying save functions, ensure output remains valid shell syntax.

**Task Context Loading**: `load_task_context()` copies task variables into global scope (`BACKUP_DIRS`, `BACKUP_PREFIX`, etc.). `save_current_task_context()` writes them back. Always call these when switching tasks.

**S3 Tool Abstraction**: Script detects `s3cmd` or `aws-cli` at runtime. All S3 operations go through `s3_put()`, `s3_list()`, `s3_rm()`, `s3_test()` wrappers.

**Bilingual UI**: Every user-facing string lives in associative array `L[]`. When adding features, update both `load_lang_en()` and `load_lang_zh()` with matching keys.

## Development Guidelines

### Language Requirements
- **Bash 4.0+** required (uses associative arrays, `[[`, `((`)
- Do not add Bash 3 compatibility
- Avoid bashisms that break on macOS default shell (script already handles this)

### Adding Features
1. Add i18n strings to both `load_lang_en()` and `load_lang_zh()`
2. If adding task properties, update:
   - `create_task()` - default values
   - `load_task_context()` - load into globals
   - `save_current_task_context()` - persist from globals
   - `save_tasks_store()` - serialization format
3. Test with both `s3cmd` and `aws-cli` if touching S3 operations
4. Verify cron mode works: `./vback.sh backup --scheduled`

### Code Style
- Use `[[ ]]` for conditionals, not `[ ]`
- Use `(( ))` for arithmetic
- Quote variables: `"$var"` not `$var`
- Prefer `local` for function variables
- Use `|| return 1` for error propagation in functions

### Common Pitfalls
- **Breaking config files**: `save_config()` output must be valid Bash. Test by sourcing the generated file.
- **Missing i18n**: Hardcoded English strings break Chinese mode.
- **Cron environment**: Commands run via cron have minimal `PATH`. Script uses full paths (`/usr/bin/tar`) where needed.
- **Lock file cleanup**: `do_backup()` uses trap to ensure lock removal. Don't bypass this.

## Cloud Provider Support

Supported providers (configured in `init_providers()`):
- Bitiful S4 (China)
- Cloudflare R2
- AWS S3
- Aliyun OSS
- Qiniu Kodo
- Google Cloud Storage
- Custom S3-compatible endpoints

Each provider has preset endpoint/region templates. When adding providers, update `init_providers()` and both language files.

## File Locations

**Runtime**:
- `~/.vback/` - All persistent data (mode 700)
- `/tmp/vback-$$` - Temporary backup staging
- `/tmp/vback.lock` - Prevents concurrent runs
- `/tmp/.s3cfg-vback-$$` - Ephemeral s3cmd config

**Distribution**:
- Single file: `vback.sh`
- Install location: `/usr/local/bin/vback` (recommended) or local directory

## Version Management

Version is hardcoded at line 16: `VERSION="1.4.0"`

Update mechanism (`do_update()`):
1. Downloads latest from GitHub raw URL
2. Compares versions
3. Replaces current script
4. Preserves `~/.vback/` data

When releasing, update `VERSION` and ensure `RAW_SCRIPT_URL` points to correct branch.
