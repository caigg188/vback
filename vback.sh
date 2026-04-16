#!/bin/bash
set -o pipefail
# ============================================================================
# vback - 优雅的服务器备份工具 v1.4.0
# Elegant Server Backup Tool
# 
# 更方便，更省心 | Effortless & Worry-free
# 一款上手即用的服务器数据备份脚本
# A ready-to-use server backup script
#
# 支持: 缤纷云S4 / Cloudflare R2 / AWS S3 / 阿里云OSS / 七牛云 / Google Cloud
# 
# 🔗 GitHub: https://github.com/caigg188/vback
# 📜 License: MIT
# ============================================================================

VERSION="1.4.0"
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || (
    # macOS fallback: resolve symlinks manually
    _dir=$(cd "$(dirname "$0")" && pwd)
    _base=$(basename "$0")
    while [[ -L "$_dir/$_base" ]]; do
        _target=$(readlink "$_dir/$_base" 2>/dev/null)
        _dir=$(cd "$(dirname "$_target")" && pwd)
        _base=$(basename "$_target")
    done
    echo "$_dir/$_base"
))
GITHUB_URL="https://github.com/caigg188/vback"
RAW_SCRIPT_URL="https://raw.githubusercontent.com/caigg188/vback/main/vback.sh"

# ========================= 数据目录 =========================
DATA_DIR="${VBACK_DATA_DIR:-$HOME/.vback}"
CONFIG_FILE="${DATA_DIR}/config"
TASKS_FILE="${DATA_DIR}/tasks"
SCHEDULES_FILE="${DATA_DIR}/schedules"
LANG_FILE="${DATA_DIR}/language"
LOG_DIR="${DATA_DIR}/logs"
LOG_FILE="${LOG_DIR}/vback.log"

DEFAULT_EXCLUDE_PATTERNS=(
    "*.log" "*.tmp" "node_modules" ".git"
    "__pycache__" "*.pyc" ".DS_Store" "Thumbs.db"
)

# ========================= 默认配置 =========================
CLOUD_PROVIDER=""
S3_ACCESS_KEY=""
S3_SECRET_KEY=""
S3_ENDPOINT=""
S3_BUCKET=""
S3_REGION=""
BACKUP_DIRS=()
BACKUP_PREFIX=""
MAX_BACKUPS=7
COMPRESS_BACKUP=true
COMPRESSION_LEVEL=6
SQLITE_SAFE_BACKUP=true
SCHEDULE_CRON="0 3 * * *"
EXCLUDE_PATTERNS=("${DEFAULT_EXCLUDE_PATTERNS[@]}")

# 备份任务 / 定时任务
TASK_IDS=()
SCHEDULE_IDS=()
ACTIVE_TASK_ID=""
DEFAULT_TASK_ID=""
CURRENT_TASK_ID=""
CLI_TASK_REF=""
CLI_TASK_ID=""
CLI_SCHEDULE_ID=""
CLI_SCHEDULE_NAME=""
CLI_CRON_EXPR=""
CLI_SCHEDULED=false
RUN_CONTEXT="interactive"

# 运行时变量
LOCK_DIR=""  # set by acquire_lock using mktemp -d
LOCK_FILE=""
TEMP_DIR=""  # set by init_temp_dir using mktemp -d
S3CMD_CFG="" # set by init_temp_dir using mktemp
VERBOSE="${VERBOSE:-false}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_MAX_SIZE=10485760
LOG_BACKUP_COUNT=5
CURRENT_LANG="en"

# 初始化临时目录（使用 mktemp 避免可预测路径的符号链接攻击）
init_temp_dir() {
    TEMP_DIR=$(mktemp -d "${TMPDIR:-/tmp}/vback.XXXXXX" 2>/dev/null) || TEMP_DIR="/tmp/vback-$$"
    S3CMD_CFG=$(mktemp "${TMPDIR:-/tmp}/.s3cfg-vback.XXXXXX" 2>/dev/null) || S3CMD_CFG="/tmp/.s3cfg-vback-$$"
    chmod 600 "$S3CMD_CFG" 2>/dev/null
}

# ============================================================================
# 多语言系统
# ============================================================================

declare -A L

load_lang_en() {
    # Branding
    L[slogan]="Effortless & Worry-free"
    L[tagline]="A ready-to-use server backup script"
    
    # General
    L[app_name]="vback"
    L[app_desc]="Elegant Server Backup Tool"
    L[version]="Version"
    L[yes]="y"
    L[no]="n"
    L[yes_no]="[y/N]"
    L[yes_no_y]="[Y/n]"
    L[press_enter]="Press Enter to continue..."
    L[back]="Back"
    L[save]="Save"
    L[cancel]="Cancel"
    L[confirm]="Confirm"
    L[success]="Success"
    L[failed]="Failed"
    L[error]="Error"
    L[warning]="Warning"
    L[info]="Info"
    L[enabled]="Enabled"
    L[disabled]="Disabled"
    L[not_set]="Not set"
    L[not_exist]="Not exist"
    L[none]="None"
    L[unknown]="Unknown"
    L[installed]="Installed"
    L[not_installed]="Not installed"
    L[installing]="Installing"
    L[select_option]="Select"
    L[invalid_option]="Invalid option"
    L[operation_cancelled]="Operation cancelled"
    
    # Language selection
    L[select_language]="Select Language"
    L[lang_en]="English"
    L[lang_zh]="中文"
    L[lang_saved]="Language preference saved"
    
    # Cloud providers
    L[cloud_provider]="Cloud Provider"
    L[select_provider]="Select Cloud Provider"
    L[provider_bitiful]="Bitiful S4"
    L[provider_bitiful_desc]="China, S3-compatible"
    L[provider_cloudflare]="Cloudflare R2"
    L[provider_cloudflare_desc]="Global, zero egress fees"
    L[provider_aws]="AWS S3"
    L[provider_aws_desc]="Global, industry standard"
    L[provider_aliyun]="Aliyun OSS"
    L[provider_aliyun_desc]="China, fast in Asia"
    L[provider_qiniu]="Qiniu Kodo"
    L[provider_qiniu_desc]="China, developer friendly"
    L[provider_gcloud]="Google Cloud Storage"
    L[provider_gcloud_desc]="Global, integrated with GCP"
    L[provider_custom]="Custom S3"
    L[provider_custom_desc]="Any S3-compatible service"
    
    # Setup wizard
    L[setup_wizard]="Setup Wizard"
    L[welcome_message]="Welcome to vback! Let's configure your backup."
    L[first_time_setup]="First time setup required"
    L[run_setup_first]="Please run 'vback setup' first"
    L[setup_s3_config]="S3 Connection"
    L[setup_backup_dirs]="Backup Directories"
    L[setup_options]="Backup Options"
    L[setup_complete]="Setup Complete"
    L[config_saved]="Configuration saved to"
    L[test_connection_now]="Test connection now?"
    L[save_config_confirm]="Save configuration?"
    L[config_not_saved]="Configuration not saved"
    
    # S3 Configuration
    L[access_key]="Access Key"
    L[access_key_hint]=""
    L[secret_key]="Secret Key"
    L[secret_key_hint]=""
    L[endpoint]="Endpoint"
    L[endpoint_hint]=""
    L[bucket]="Bucket"
    L[bucket_hint]=""
    L[region]="Region"
    L[region_hint]=""
    L[prefix]="Prefix"
    L[prefix_hint]=""
    L[account_id]="Account ID"
    L[keep_empty_unchanged]="Leave empty to keep unchanged"
    L[root_directory]="<root>"
    
    # Backup directories
    L[backup_directories]="Backup Directories"
    L[enter_dir_path]="Directory path"
    L[dir_path_hint]="Press Tab for auto-completion"
    L[empty_line_finish]="Empty line to finish"
    L[dir_added]="Added"
    L[dir_not_exist_add]="Directory not found. Add anyway?"
    L[need_at_least_one_dir]="Need at least one backup directory"
    L[add_directory]="Add directory"
    L[remove_directory]="Remove directory"
    L[total_size]="Total size"
    L[files]="files"
    L[sqlite_dbs]="SQLite DBs"
    
    # Backup options
    L[compression]="Compression"
    L[compression_level]="Compression level"
    L[enable_compression]="Enable compression?"
    L[sqlite_safe]="SQLite Safe Backup"
    L[enable_sqlite_safe]="Enable SQLite safe backup?"
    L[max_backups]="Max backups"
    L[max_backups_desc]="0 = unlimited"
    
    # Backup tasks
    L[backup_tasks]="Backup Tasks"
    L[task_name]="Task Name"
    L[current_task]="Current Task"
    L[default_task]="Default Task"
    L[add_task]="Add Task"
    L[edit_task]="Edit Task"
    L[delete_task]="Delete Task"
    L[set_default_task]="Set as Default"
    L[task_saved]="Task saved"
    L[task_deleted]="Task deleted"
    L[task_set_default]="Default task updated"
    L[select_backup_task]="Select backup task"
    L[need_task_first]="Create a backup task first"
    L[no_tasks]="No backup tasks yet"
    L[need_keep_one_task]="Keep at least one backup task"
    L[confirm_delete_task]="Delete backup task?"
    
    # Exclude patterns
    L[exclude_patterns]="Exclude Patterns"
    L[add_pattern]="Add pattern"
    L[remove_pattern]="Remove pattern"
    L[reset_default]="Reset to default"
    L[pattern_example]="e.g. *.log"
    
    # Main menu
    L[main_menu]="Main Menu"
    L[menu_backup]="Backup Now"
    L[menu_backup_desc]="Execute full backup"
    L[menu_list]="List Backups"
    L[menu_list_desc]="View remote backups"
    L[menu_test]="Test Connection"
    L[menu_test_desc]="Verify S3 connection"
    L[menu_cron]="Scheduled Backup"
    L[menu_cron_desc]="Auto backup settings"
    L[menu_config]="Edit Config"
    L[menu_config_desc]="Modify settings"
    L[menu_logs]="View Logs"
    L[menu_logs_desc]="Recent activity"
    L[menu_reconfig]="Reconfigure"
    L[menu_reconfig_desc]="Run setup wizard"
    L[menu_lang]="Language"
    L[menu_lang_desc]="Change language"
    L[menu_update]="Update"
    L[menu_update_desc]="Check for updates"
    L[menu_reset]="Reset All"
    L[menu_reset_desc]="Factory reset"
    L[menu_exit]="Exit"
    L[goodbye]="Goodbye!"
    
    # Backup process
    L[start_backup]="Starting Backup"
    L[backup_complete]="Backup Complete"
    L[backing_up]="Backing up"
    L[preparing_files]="Preparing files"
    L[compressing]="Compressing"
    L[compression_complete]="Compression complete"
    L[uploading]="Uploading"
    L[upload_complete]="Upload complete"
    L[upload_failed]="Upload failed"
    L[compress_failed]="Compression failed"
    L[tar_failed]="Tar failed"
    L[source]="Source"
    L[target]="Target"
    L[transfer]="Transfer"
    L[duration]="Duration"
    L[total_duration]="Total duration"
    L[all_success]="All successful"
    L[partial_success]="success, failed"
    L[cleaned_old_backups]="Cleaned old backups"
    L[confirm_backup]="Confirm backup?"
    L[will_backup_dirs]="Will backup directories"
    
    # Remote backups
    L[remote_backups]="Remote Backups"
    L[no_backups_yet]="No backups yet"
    
    # Connection test
    L[connection_test]="Connection Test"
    L[testing_connection]="Testing S3 connection..."
    L[connection_success]="Connection successful"
    L[connection_failed]="Connection failed"
    L[dependency_check]="Dependency Check"
    
    # Cron jobs
    L[scheduled_backup]="Scheduled Backup"
    L[cron_status]="Status"
    L[cron_enabled]="Enabled"
    L[cron_disabled]="Disabled"
    L[enable_update]="Enable/Update"
    L[disable_cron]="Disable"
    L[cron_expression]="Cron expression"
    L[cron_installed]="Scheduled backup installed"
    L[cron_removed]="Scheduled backup removed"
    L[confirm_disable]="Confirm disable?"
    L[cron_examples]="Cron examples"
    L[cron_daily]="Daily at 03:00"
    L[cron_6hours]="Every 6 hours"
    L[cron_weekly]="Weekly on Sunday"
    L[schedule_task]="Task"
    L[schedule_name]="Schedule Name"
    L[add_schedule]="Add Schedule"
    L[edit_schedule]="Edit Schedule"
    L[delete_schedule]="Delete Schedule"
    L[sync_schedules]="Sync to Cron"
    L[no_schedules]="No schedules yet"
    L[schedule_saved]="Schedule saved"
    L[schedule_deleted]="Schedule deleted"
    L[confirm_delete_schedule]="Delete schedule?"
    
    # Edit config menu
    L[edit_config]="Edit Configuration"
    L[current_config]="Current Configuration"
    L[s3_settings]="S3 Settings"
    L[backup_settings]="Backup Settings"
    L[settings_updated]="Settings updated"
    
    # Logs
    L[recent_logs]="Recent Logs"
    L[no_logs]="No logs yet"
    L[tip_realtime_log]="Tip: tail -f"
    
    # Update
    L[check_update]="Check for Updates"
    L[checking_update]="Checking for updates..."
    L[current_version]="Current version"
    L[latest_version]="Latest version"
    L[update_available]="Update available!"
    L[already_latest]="Already up to date"
    L[confirm_update]="Update now?"
    L[updating]="Updating..."
    L[update_success]="Update successful! Please restart the script."
    L[update_failed]="Update failed"
    L[backup_old_script]="Old version backed up to"
    L[download_failed]="Download failed"
    L[network_error]="Network error, please check your connection"
    
    # Reset
    L[reset_all]="Factory Reset"
    L[reset_warning]="WARNING: This will delete ALL data!"
    L[reset_items]="The following will be deleted"
    L[reset_config]="Configuration file"
    L[reset_logs]="All log files"
    L[reset_cron]="Scheduled tasks"
    L[reset_lang]="Language settings"
    L[reset_confirm]="Type 'RESET' to confirm"
    L[reset_success]="Reset complete! vback is now in factory state."
    L[reset_cancelled]="Reset cancelled"
    L[reset_type_mismatch]="Input does not match, reset cancelled"
    
    # Lock/Process errors
    L[err_task_running]="Another backup task is running"
    L[err_lock_pid]="Process ID"
    L[err_lock_process_info]="Process info"
    L[err_lock_ask_kill]="Terminate the process and continue?"
    L[err_lock_killed]="Process terminated"
    L[err_lock_kill_failed]="Failed to terminate process"
    L[err_lock_stale]="Stale lock file detected, cleaning up..."
    
    # Errors
    L[err_no_s3_tool]="No S3 tool found"
    L[err_install_s3cmd]="Install s3cmd?"
    L[err_install_failed]="Installation failed"
    L[err_install_manual]="Please install manually: pip install s3cmd"
    L[err_missing_deps]="Missing dependencies"
    L[err_config_errors]="Configuration errors"
    L[err_validate_config]="Please check configuration"
    
    # CLI help
    L[cli_usage]="Usage"
    L[cli_commands]="Commands"
    L[cli_options]="Options"
    L[cli_examples]="Examples"
    L[cli_cmd_backup]="Execute backup"
    L[cli_cmd_menu]="Interactive menu (default)"
    L[cli_cmd_setup]="Run setup wizard"
    L[cli_cmd_test]="Test S3 connection"
    L[cli_cmd_status]="View remote backups"
    L[cli_cmd_cron_install]="Install cron job"
    L[cli_cmd_cron_remove]="Remove cron job"
    L[cli_cmd_config]="Show current config"
    L[cli_cmd_update]="Update script"
    L[cli_cmd_reset]="Factory reset"
    L[cli_cmd_help]="Show help"
    L[cli_cmd_restore]="Restore from backup"

    # Restore
    L[restore_title]="Restore"
    L[restore_need_key]="Specify backup key to restore"
    L[restore_directory]="Destination directory"
    L[restore_dest_hint]="Leave empty for current directory"
    L[confirm_restore]="Restore"
    L[restore_complete]="Restore complete"
    L[restore_failed]="Restore failed"
    L[downloading]="Downloading"
    L[extracting]="Extracting"
    L[available_backups]="Available backups"
    L[upload_verify_failed]="Upload verification failed (MD5 mismatch)"
    L[warn_optional_deps]="Optional tools missing (some features may not work)"
    L[warn_no_rsync]="rsync not available: using cp fallback (exclude patterns and SQLite safe backup may not work)"
    L[compress_partial_warning]="Some files could not be read (partial backup)"
    L[cli_opt_verbose]="Verbose output"
    L[cli_opt_config]="Config file path"
    L[cli_opt_lang]="Language (en/zh)"
    L[cli_opt_task]="Task name or ID"
    L[cli_opt_task_id]="Task ID"
    L[cli_opt_scheduled]="Scheduled mode (no progress)"
    L[cli_opt_schedule_id]="Schedule ID"
    L[cli_opt_cron]="Cron expression"
    L[cli_opt_schedule_name]="Schedule name"
    L[cli_config_file]="Config file"
    L[cli_log_file]="Log file"
}

load_lang_zh() {
    # Branding
    L[slogan]="更方便，更省心"
    L[tagline]="一款上手即用的服务器数据备份脚本"
    
    # General
    L[app_name]="vback"
    L[app_desc]="优雅的服务器备份工具"
    L[version]="版本"
    L[yes]="y"
    L[no]="n"
    L[yes_no]="[y/N]"
    L[yes_no_y]="[Y/n]"
    L[press_enter]="按 Enter 键继续..."
    L[back]="返回"
    L[save]="保存"
    L[cancel]="取消"
    L[confirm]="确认"
    L[success]="成功"
    L[failed]="失败"
    L[error]="错误"
    L[warning]="警告"
    L[info]="信息"
    L[enabled]="已启用"
    L[disabled]="已禁用"
    L[not_set]="未设置"
    L[not_exist]="不存在"
    L[none]="无"
    L[unknown]="未知"
    L[installed]="已安装"
    L[not_installed]="未安装"
    L[installing]="正在安装"
    L[select_option]="请选择"
    L[invalid_option]="无效选项"
    L[operation_cancelled]="操作已取消"
    
    # Language selection
    L[select_language]="选择语言"
    L[lang_en]="English"
    L[lang_zh]="中文"
    L[lang_saved]="语言设置已保存"
    
    # Cloud providers
    L[cloud_provider]="云服务商"
    L[select_provider]="选择云服务商"
    L[provider_bitiful]="缤纷云 S4"
    L[provider_bitiful_desc]="国内首选，S3 兼容"
    L[provider_cloudflare]="Cloudflare R2"
    L[provider_cloudflare_desc]="全球加速，零出口费"
    L[provider_aws]="AWS S3"
    L[provider_aws_desc]="行业标准，全球覆盖"
    L[provider_aliyun]="阿里云 OSS"
    L[provider_aliyun_desc]="国内主流，亚太高速"
    L[provider_qiniu]="七牛云 Kodo"
    L[provider_qiniu_desc]="开发者友好，性价比高"
    L[provider_gcloud]="Google Cloud Storage"
    L[provider_gcloud_desc]="全球覆盖，GCP 生态"
    L[provider_custom]="自定义 S3"
    L[provider_custom_desc]="任意 S3 兼容服务"
    
    # Setup wizard
    L[setup_wizard]="配置向导"
    L[welcome_message]="欢迎使用 vback！让我们开始配置备份。"
    L[first_time_setup]="需要首次配置"
    L[run_setup_first]="请先运行 'vback setup' 进行配置"
    L[setup_s3_config]="S3 连接配置"
    L[setup_backup_dirs]="备份目录"
    L[setup_options]="备份选项"
    L[setup_complete]="配置完成"
    L[config_saved]="配置已保存到"
    L[test_connection_now]="现在测试连接？"
    L[save_config_confirm]="保存配置？"
    L[config_not_saved]="配置未保存"
    
    # S3 Configuration
    L[access_key]="Access Key"
    L[access_key_hint]="访问密钥"
    L[secret_key]="Secret Key"
    L[secret_key_hint]="秘密密钥"
    L[endpoint]="Endpoint"
    L[endpoint_hint]="服务端点"
    L[bucket]="Bucket"
    L[bucket_hint]="存储桶名称"
    L[region]="Region"
    L[region_hint]="区域"
    L[prefix]="Prefix"
    L[prefix_hint]="目录前缀"
    L[account_id]="Account ID"
    L[keep_empty_unchanged]="留空保持不变"
    L[root_directory]="<根目录>"
    
    # Backup directories
    L[backup_directories]="备份目录"
    L[enter_dir_path]="目录路径"
    L[dir_path_hint]="按 Tab 键自动补全路径"
    L[empty_line_finish]="空行结束输入"
    L[dir_added]="已添加"
    L[dir_not_exist_add]="目录不存在，是否仍要添加？"
    L[need_at_least_one_dir]="至少需要一个备份目录"
    L[add_directory]="添加目录"
    L[remove_directory]="删除目录"
    L[total_size]="总大小"
    L[files]="个文件"
    L[sqlite_dbs]="个数据库"
    
    # Backup options
    L[compression]="压缩"
    L[compression_level]="压缩级别"
    L[enable_compression]="启用压缩？"
    L[sqlite_safe]="SQLite 安全备份"
    L[enable_sqlite_safe]="启用 SQLite 安全备份？"
    L[max_backups]="保留数量"
    L[max_backups_desc]="0 = 不限制"
    
    # Backup tasks
    L[backup_tasks]="备份任务"
    L[task_name]="任务名称"
    L[current_task]="当前任务"
    L[default_task]="默认任务"
    L[add_task]="新增任务"
    L[edit_task]="编辑任务"
    L[delete_task]="删除任务"
    L[set_default_task]="设为默认任务"
    L[task_saved]="任务已保存"
    L[task_deleted]="任务已删除"
    L[task_set_default]="默认任务已更新"
    L[select_backup_task]="选择备份任务"
    L[need_task_first]="请先创建备份任务"
    L[no_tasks]="暂无备份任务"
    L[need_keep_one_task]="至少保留一个备份任务"
    L[confirm_delete_task]="确认删除备份任务？"
    
    # Exclude patterns
    L[exclude_patterns]="排除规则"
    L[add_pattern]="添加规则"
    L[remove_pattern]="删除规则"
    L[reset_default]="重置为默认"
    L[pattern_example]="例如 *.log"
    
    # Main menu
    L[main_menu]="主菜单"
    L[menu_backup]="立即备份"
    L[menu_backup_desc]="执行完整备份"
    L[menu_list]="查看备份"
    L[menu_list_desc]="列出云端文件"
    L[menu_test]="测试连接"
    L[menu_test_desc]="验证 S3 配置"
    L[menu_cron]="定时备份"
    L[menu_cron_desc]="自动备份设置"
    L[menu_config]="编辑配置"
    L[menu_config_desc]="修改参数设置"
    L[menu_logs]="查看日志"
    L[menu_logs_desc]="最近操作记录"
    L[menu_reconfig]="重新配置"
    L[menu_reconfig_desc]="运行配置向导"
    L[menu_lang]="切换语言"
    L[menu_lang_desc]="Change language"
    L[menu_update]="检查更新"
    L[menu_update_desc]="更新脚本版本"
    L[menu_reset]="重置全部"
    L[menu_reset_desc]="恢复出厂设置"
    L[menu_exit]="退出"
    L[goodbye]="再见！"
    
    # Backup process
    L[start_backup]="开始备份"
    L[backup_complete]="备份完成"
    L[backing_up]="正在备份"
    L[preparing_files]="准备文件"
    L[compressing]="压缩中"
    L[compression_complete]="压缩完成"
    L[uploading]="上传中"
    L[upload_complete]="上传完成"
    L[upload_failed]="上传失败"
    L[compress_failed]="压缩失败"
    L[tar_failed]="打包失败"
    L[source]="源"
    L[target]="目标"
    L[transfer]="传输"
    L[duration]="耗时"
    L[total_duration]="总耗时"
    L[all_success]="全部成功"
    L[partial_success]="成功，失败"
    L[cleaned_old_backups]="已清理旧备份"
    L[confirm_backup]="确认备份？"
    L[will_backup_dirs]="将备份以下目录"
    
    # Remote backups
    L[remote_backups]="云端备份"
    L[no_backups_yet]="暂无备份"
    
    # Connection test
    L[connection_test]="连接测试"
    L[testing_connection]="正在测试 S3 连接..."
    L[connection_success]="连接成功"
    L[connection_failed]="连接失败"
    L[dependency_check]="依赖检查"
    
    # Cron jobs
    L[scheduled_backup]="定时备份"
    L[cron_status]="状态"
    L[cron_enabled]="已启用"
    L[cron_disabled]="未启用"
    L[enable_update]="启用/更新"
    L[disable_cron]="停用"
    L[cron_expression]="Cron 表达式"
    L[cron_installed]="定时任务已设置"
    L[cron_removed]="定时任务已移除"
    L[confirm_disable]="确认停用？"
    L[cron_examples]="Cron 示例"
    L[cron_daily]="每天 03:00"
    L[cron_6hours]="每 6 小时"
    L[cron_weekly]="每周日"
    L[schedule_task]="所属任务"
    L[schedule_name]="定时任务名称"
    L[add_schedule]="新增定时任务"
    L[edit_schedule]="编辑定时任务"
    L[delete_schedule]="删除定时任务"
    L[sync_schedules]="同步到 Cron"
    L[no_schedules]="暂无定时任务"
    L[schedule_saved]="定时任务已保存"
    L[schedule_deleted]="定时任务已删除"
    L[confirm_delete_schedule]="确认删除定时任务？"
    
    # Edit config menu
    L[edit_config]="编辑配置"
    L[current_config]="当前配置"
    L[s3_settings]="S3 设置"
    L[backup_settings]="备份设置"
    L[settings_updated]="设置已更新"
    
    # Logs
    L[recent_logs]="最近日志"
    L[no_logs]="暂无日志"
    L[tip_realtime_log]="提示: 实时查看"
    
    # Update
    L[check_update]="检查更新"
    L[checking_update]="正在检查更新..."
    L[current_version]="当前版本"
    L[latest_version]="最新版本"
    L[update_available]="发现新版本！"
    L[already_latest]="已是最新版本"
    L[confirm_update]="是否立即更新？"
    L[updating]="正在更新..."
    L[update_success]="更新成功！请重新运行脚本。"
    L[update_failed]="更新失败"
    L[backup_old_script]="旧版本已备份到"
    L[download_failed]="下载失败"
    L[network_error]="网络错误，请检查网络连接"
    
    # Reset
    L[reset_all]="恢复出厂设置"
    L[reset_warning]="警告：这将删除所有数据！"
    L[reset_items]="以下内容将被删除"
    L[reset_config]="配置文件"
    L[reset_logs]="所有日志文件"
    L[reset_cron]="定时任务"
    L[reset_lang]="语言设置"
    L[reset_confirm]="输入 'RESET' 确认重置"
    L[reset_success]="重置完成！vback 已恢复出厂状态。"
    L[reset_cancelled]="重置已取消"
    L[reset_type_mismatch]="输入不匹配，重置已取消"
    
    # Lock/Process errors
    L[err_task_running]="已有备份任务正在运行"
    L[err_lock_pid]="进程 ID"
    L[err_lock_process_info]="进程信息"
    L[err_lock_ask_kill]="是否终止该进程并继续？"
    L[err_lock_killed]="进程已终止"
    L[err_lock_kill_failed]="终止进程失败"
    L[err_lock_stale]="检测到残留锁文件，正在清理..."
    
    # Errors
    L[err_no_s3_tool]="未检测到 S3 工具"
    L[err_install_s3cmd]="是否安装 s3cmd？"
    L[err_install_failed]="安装失败"
    L[err_install_manual]="请手动安装: pip install s3cmd"
    L[err_missing_deps]="缺少依赖"
    L[err_config_errors]="配置错误"
    L[err_validate_config]="请检查配置"
    
    # CLI help
    L[cli_usage]="用法"
    L[cli_commands]="命令"
    L[cli_options]="选项"
    L[cli_examples]="示例"
    L[cli_cmd_backup]="执行备份"
    L[cli_cmd_menu]="交互菜单 (默认)"
    L[cli_cmd_setup]="运行配置向导"
    L[cli_cmd_test]="测试 S3 连接"
    L[cli_cmd_status]="查看云端备份"
    L[cli_cmd_cron_install]="安装定时任务"
    L[cli_cmd_cron_remove]="移除定时任务"
    L[cli_cmd_config]="显示当前配置"
    L[cli_cmd_update]="更新脚本"
    L[cli_cmd_reset]="恢复出厂设置"
    L[cli_cmd_help]="显示帮助"
    L[cli_cmd_restore]="从备份恢复"

    # 恢复
    L[restore_title]="恢复备份"
    L[restore_need_key]="请指定要恢复的备份键"
    L[restore_directory]="目标目录"
    L[restore_dest_hint]="留空则为当前目录"
    L[confirm_restore]="恢复"
    L[restore_complete]="恢复完成"
    L[restore_failed]="恢复失败"
    L[downloading]="正在下载"
    L[extracting]="正在解压"
    L[available_backups]="可用的备份"
    L[upload_verify_failed]="上传校验失败 (MD5 不匹配)"
    L[warn_optional_deps]="可选工具缺失 (部分功能可能不可用)"
    L[warn_no_rsync]="rsync 不可用: 使用 cp 替代 (排除规则和 SQLite 安全备份可能失效)"
    L[compress_partial_warning]="部分文件无法读取 (不完整备份)"
    L[cli_opt_verbose]="详细输出"
    L[cli_opt_config]="配置文件路径"
    L[cli_opt_lang]="语言 (en/zh)"
    L[cli_opt_task]="任务名称或 ID"
    L[cli_opt_task_id]="任务 ID"
    L[cli_opt_scheduled]="定时运行模式 (关闭进度)"
    L[cli_opt_schedule_id]="定时任务 ID"
    L[cli_opt_cron]="Cron 表达式"
    L[cli_opt_schedule_name]="定时任务名称"
    L[cli_config_file]="配置文件"
    L[cli_log_file]="日志文件"
}

set_language() {
    CURRENT_LANG="$1"
    case "$1" in
        zh|zh_CN|zh_TW|chinese) CURRENT_LANG="zh"; load_lang_zh ;;
        *) CURRENT_LANG="en"; load_lang_en ;;
    esac
    
    mkdir -p "$DATA_DIR" 2>/dev/null
    echo "$CURRENT_LANG" > "$LANG_FILE"
}

load_saved_language() {
    if [[ -f "$LANG_FILE" ]]; then
        local saved_lang=$(cat "$LANG_FILE" 2>/dev/null)
        set_language "$saved_lang"
        return 0
    fi
    return 1
}

select_language_dialog() {
    clear
    echo ""
    echo "  ╭────────────────────────────────────────╮"
    echo "  │                                        │"
    echo "  │     🌍 Select Language / 选择语言      │"
    echo "  │                                        │"
    echo "  ├────────────────────────────────────────┤"
    echo "  │                                        │"
    echo "  │     1)  English                        │"
    echo "  │                                        │"
    echo "  │     2)  中文                           │"
    echo "  │                                        │"
    echo "  ╰────────────────────────────────────────╯"
    echo ""
    echo -n "  Select [1-2]: "
    read -r choice
    
    case "$choice" in
        2) set_language "zh" ;;
        *) set_language "en" ;;
    esac
}

# ============================================================================
# 云服务商配置
# ============================================================================

declare -A PROVIDERS

init_providers() {
    PROVIDERS[bitiful_name]="${L[provider_bitiful]}"
    PROVIDERS[bitiful_desc]="${L[provider_bitiful_desc]}"
    PROVIDERS[bitiful_endpoint]="s3.bitiful.net"
    PROVIDERS[bitiful_region]="cn-east-1"
    
    PROVIDERS[cloudflare_name]="${L[provider_cloudflare]}"
    PROVIDERS[cloudflare_desc]="${L[provider_cloudflare_desc]}"
    PROVIDERS[cloudflare_endpoint]="{account_id}.r2.cloudflarestorage.com"
    PROVIDERS[cloudflare_region]="auto"
    
    PROVIDERS[aws_name]="${L[provider_aws]}"
    PROVIDERS[aws_desc]="${L[provider_aws_desc]}"
    PROVIDERS[aws_endpoint]="s3.{region}.amazonaws.com"
    PROVIDERS[aws_region]="us-east-1"
    
    PROVIDERS[aliyun_name]="${L[provider_aliyun]}"
    PROVIDERS[aliyun_desc]="${L[provider_aliyun_desc]}"
    PROVIDERS[aliyun_endpoint]="oss-{region}.aliyuncs.com"
    PROVIDERS[aliyun_region]="cn-hangzhou"
    
    PROVIDERS[qiniu_name]="${L[provider_qiniu]}"
    PROVIDERS[qiniu_desc]="${L[provider_qiniu_desc]}"
    PROVIDERS[qiniu_endpoint]="s3-{region}.qiniucs.com"
    PROVIDERS[qiniu_region]="cn-east-1"
    
    PROVIDERS[gcloud_name]="${L[provider_gcloud]}"
    PROVIDERS[gcloud_desc]="${L[provider_gcloud_desc]}"
    PROVIDERS[gcloud_endpoint]="storage.googleapis.com"
    PROVIDERS[gcloud_region]="us"
    
    PROVIDERS[custom_name]="${L[provider_custom]}"
    PROVIDERS[custom_desc]="${L[provider_custom_desc]}"
    PROVIDERS[custom_endpoint]=""
    PROVIDERS[custom_region]=""
}

get_provider_name() {
    local provider="$1"
    echo "${PROVIDERS[${provider}_name]:-$provider}"
}

get_default_endpoint() {
    local provider="$1"
    echo "${PROVIDERS[${provider}_endpoint]:-}"
}

get_default_region() {
    local provider="$1"
    echo "${PROVIDERS[${provider}_region]:-}"
}

# ============================================================================
# 终端颜色
# ============================================================================

setup_colors() {
    local use_color=false
    if [[ -t 1 ]]; then
        if [[ -n "$FORCE_COLOR" ]] || [[ "$TERM" != "dumb" ]]; then
            local colors=$(tput colors 2>/dev/null || echo 0)
            [[ $colors -ge 8 ]] && use_color=true
        fi
    fi
    
    if [[ "$use_color" == "true" ]]; then
        local colors=$(tput colors 2>/dev/null || echo 8)
        
        if [[ $colors -ge 256 ]]; then
            C_RESET='\033[0m'
            C_BOLD='\033[1m'
            C_DIM='\033[2m'
            C_ITALIC='\033[3m'
            C_UNDERLINE='\033[4m'
            C_SUCCESS='\033[38;5;35m'
            C_ERROR='\033[1;38;5;196m'
            C_WARNING='\033[38;5;214m'
            C_INFO='\033[38;5;39m'
            C_PRIMARY='\033[38;5;33m'
            C_MUTED='\033[38;5;245m'
            C_BORDER='\033[38;5;240m'
            C_MENU_NUM='\033[1;38;5;75m'
            C_TITLE='\033[1;38;5;141m'
            C_PATH='\033[38;5;80m'
            C_NUMBER='\033[38;5;156m'
            C_TIMESTAMP='\033[38;5;103m'
            C_INPUT='\033[38;5;230m'
            C_ACCENT='\033[38;5;213m'
            C_HINT='\033[38;5;244m'
            C_LOGO1='\033[38;5;39m'
            C_LOGO2='\033[38;5;38m'
            C_LOGO3='\033[38;5;44m'
            C_SLOGAN='\033[38;5;252m'
            C_LINK='\033[38;5;75m'
        else
            C_RESET='\033[0m'
            C_BOLD='\033[1m'
            C_DIM='\033[2m'
            C_ITALIC='\033[3m'
            C_UNDERLINE='\033[4m'
            C_SUCCESS='\033[32m'
            C_ERROR='\033[1;31m'
            C_WARNING='\033[33m'
            C_INFO='\033[36m'
            C_PRIMARY='\033[34m'
            C_MUTED='\033[90m'
            C_BORDER='\033[90m'
            C_MENU_NUM='\033[1;36m'
            C_TITLE='\033[1;35m'
            C_PATH='\033[36m'
            C_NUMBER='\033[32m'
            C_TIMESTAMP='\033[35m'
            C_INPUT='\033[93m'
            C_ACCENT='\033[95m'
            C_HINT='\033[90m'
            C_LOGO1='\033[34m'
            C_LOGO2='\033[36m'
            C_LOGO3='\033[36m'
            C_SLOGAN='\033[97m'
            C_LINK='\033[96m'
        fi
    else
        C_RESET='' C_BOLD='' C_DIM='' C_ITALIC='' C_UNDERLINE=''
        C_SUCCESS='' C_ERROR='' C_WARNING='' C_INFO=''
        C_PRIMARY='' C_MUTED='' C_BORDER=''
        C_MENU_NUM='' C_TITLE='' C_PATH=''
        C_NUMBER='' C_TIMESTAMP='' C_INPUT='' C_ACCENT='' C_HINT=''
        C_LOGO1='' C_LOGO2='' C_LOGO3='' C_SLOGAN='' C_LINK=''
    fi
}

# ============================================================================
# 数据持久化
# ============================================================================

init_data_dir() {
    if ! mkdir -p "$DATA_DIR" "$LOG_DIR" 2>/dev/null; then
        echo "Error: Cannot create data directory $DATA_DIR" >&2
        return 1
    fi
    chmod 700 "$DATA_DIR" 2>/dev/null
}

array_literal() {
    local item
    for item in "$@"; do
        printf '    %q\n' "$item"
    done
}

sanitize_identifier() {
    local raw="$1"
    raw=$(printf '%s' "${raw,,}" | sed 's/[^a-z0-9_]/_/g; s/__*/_/g; s/^_//; s/_$//')
    [[ -z "$raw" ]] && raw="item"
    [[ "$raw" =~ ^[0-9] ]] && raw="id_${raw}"
    echo "$raw"
}

array_remove_item() {
    local value="$1"
    shift
    local -a result=()
    local item
    for item in "$@"; do
        [[ "$item" == "$value" ]] || result+=("$item")
    done
    printf '%s\n' "${result[@]}"
}

copy_array_var() {
    local src="$1" dst="$2"
    eval "$dst=(\"\${${src}[@]}\")"
}

set_array_var() {
    local var_name="$1"
    shift
    eval "$var_name=()"
    local item quoted
    for item in "$@"; do
        printf -v quoted '%q' "$item"
        eval "$var_name+=( $quoted )"
    done
}

task_var_name() {
    echo "TASK_${2}_${1}"
}

schedule_var_name() {
    echo "SCHEDULE_${2}_${1}"
}

task_exists() {
    local target="$1" id
    for id in "${TASK_IDS[@]}"; do
        [[ "$id" == "$target" ]] && return 0
    done
    return 1
}

schedule_exists() {
    local target="$1" id
    for id in "${SCHEDULE_IDS[@]}"; do
        [[ "$id" == "$target" ]] && return 0
    done
    return 1
}

task_get_scalar() {
    local var_name
    var_name=$(task_var_name "$1" "$2")
    printf '%s' "${!var_name}"
}

task_set_scalar() {
    local var_name
    var_name=$(task_var_name "$1" "$2")
    printf -v "$var_name" '%s' "$3"
}

task_get_array() {
    copy_array_var "$(task_var_name "$1" "$2")" "$3"
}

task_set_array() {
    local var_name
    var_name=$(task_var_name "$1" "$2")
    shift 2
    set_array_var "$var_name" "$@"
}

schedule_get_scalar() {
    local var_name
    var_name=$(schedule_var_name "$1" "$2")
    printf '%s' "${!var_name}"
}

schedule_set_scalar() {
    local var_name
    var_name=$(schedule_var_name "$1" "$2")
    printf -v "$var_name" '%s' "$3"
}

default_task_name() {
    [[ "$CURRENT_LANG" == "zh" ]] && echo "默认任务" || echo "Default Task"
}

default_schedule_name() {
    local task_name="$1"
    [[ -n "$task_name" ]] && echo "$task_name" && return
    [[ "$CURRENT_LANG" == "zh" ]] && echo "默认定时任务" || echo "Default Schedule"
}

generate_task_id() {
    local seed base candidate n=1
    seed="${1:-task}"
    base="task_$(sanitize_identifier "$seed")"
    candidate="$base"
    while task_exists "$candidate"; do
        candidate="${base}_$n"
        ((n++))
    done
    echo "$candidate"
}

generate_schedule_id() {
    local seed base candidate n=1
    seed="${1:-schedule}"
    base="schedule_$(sanitize_identifier "$seed")"
    candidate="$base"
    while schedule_exists "$candidate"; do
        candidate="${base}_$n"
        ((n++))
    done
    echo "$candidate"
}

create_task() {
    local task_name="${1:-$(default_task_name)}"
    local task_id="${2:-$(generate_task_id "$task_name")}"
    
    TASK_IDS+=("$task_id")
    task_set_scalar "$task_id" NAME "$task_name"
    task_set_scalar "$task_id" PREFIX ""
    task_set_scalar "$task_id" MAX_BACKUPS "7"
    task_set_scalar "$task_id" COMPRESS "true"
    task_set_scalar "$task_id" COMPRESSION_LEVEL "6"
    task_set_scalar "$task_id" SQLITE_SAFE "true"
    task_set_array "$task_id" DIRS
    task_set_array "$task_id" EXCLUDES "${DEFAULT_EXCLUDE_PATTERNS[@]}"
    
    [[ -z "$DEFAULT_TASK_ID" ]] && DEFAULT_TASK_ID="$task_id"
    [[ -z "$ACTIVE_TASK_ID" ]] && ACTIVE_TASK_ID="$task_id"
    echo "$task_id"
}

create_schedule() {
    local schedule_name="$1" task_id="$2" cron_expr="$3" schedule_id="$4"
    [[ -z "$task_id" ]] && return 1
    
    schedule_id="${schedule_id:-$(generate_schedule_id "$schedule_name")}"
    [[ -z "$schedule_name" ]] && schedule_name="$(default_schedule_name "$(task_get_scalar "$task_id" NAME)")"
    
    SCHEDULE_IDS+=("$schedule_id")
    schedule_set_scalar "$schedule_id" NAME "$schedule_name"
    schedule_set_scalar "$schedule_id" TASK "$task_id"
    schedule_set_scalar "$schedule_id" CRON "$cron_expr"
    echo "$schedule_id"
}

delete_schedule() {
    local schedule_id="$1"
    local -a next_ids=()
    local id
    for id in "${SCHEDULE_IDS[@]}"; do
        [[ "$id" == "$schedule_id" ]] || next_ids+=("$id")
    done
    SCHEDULE_IDS=("${next_ids[@]}")
    
    unset "$(schedule_var_name "$schedule_id" NAME)"
    unset "$(schedule_var_name "$schedule_id" TASK)"
    unset "$(schedule_var_name "$schedule_id" CRON)"
}

delete_task() {
    local task_id="$1"
    local schedule_id
    for schedule_id in "${SCHEDULE_IDS[@]}"; do
        [[ "$(schedule_get_scalar "$schedule_id" TASK)" == "$task_id" ]] && delete_schedule "$schedule_id"
    done
    
    local -a next_ids=()
    local id
    for id in "${TASK_IDS[@]}"; do
        [[ "$id" == "$task_id" ]] || next_ids+=("$id")
    done
    TASK_IDS=("${next_ids[@]}")
    
    unset "$(task_var_name "$task_id" NAME)"
    unset "$(task_var_name "$task_id" PREFIX)"
    unset "$(task_var_name "$task_id" MAX_BACKUPS)"
    unset "$(task_var_name "$task_id" COMPRESS)"
    unset "$(task_var_name "$task_id" COMPRESSION_LEVEL)"
    unset "$(task_var_name "$task_id" SQLITE_SAFE)"
    unset "$(task_var_name "$task_id" DIRS)"
    unset "$(task_var_name "$task_id" EXCLUDES)"
    
    [[ "$ACTIVE_TASK_ID" == "$task_id" ]] && ACTIVE_TASK_ID="${TASK_IDS[0]}"
    [[ "$DEFAULT_TASK_ID" == "$task_id" ]] && DEFAULT_TASK_ID="${TASK_IDS[0]}"
    [[ "$CURRENT_TASK_ID" == "$task_id" ]] && CURRENT_TASK_ID=""
}

load_task_context() {
    local task_id="$1"
    task_exists "$task_id" || return 1
    
    CURRENT_TASK_ID="$task_id"
    ACTIVE_TASK_ID="$task_id"
    BACKUP_PREFIX="$(task_get_scalar "$task_id" PREFIX)"
    MAX_BACKUPS="$(task_get_scalar "$task_id" MAX_BACKUPS)"
    COMPRESS_BACKUP="$(task_get_scalar "$task_id" COMPRESS)"
    COMPRESSION_LEVEL="$(task_get_scalar "$task_id" COMPRESSION_LEVEL)"
    SQLITE_SAFE_BACKUP="$(task_get_scalar "$task_id" SQLITE_SAFE)"
    
    [[ -z "$MAX_BACKUPS" ]] && MAX_BACKUPS=7
    [[ -z "$COMPRESS_BACKUP" ]] && COMPRESS_BACKUP=true
    [[ -z "$COMPRESSION_LEVEL" ]] && COMPRESSION_LEVEL=6
    [[ -z "$SQLITE_SAFE_BACKUP" ]] && SQLITE_SAFE_BACKUP=true
    
    task_get_array "$task_id" DIRS BACKUP_DIRS
    task_get_array "$task_id" EXCLUDES EXCLUDE_PATTERNS
    [[ ${#EXCLUDE_PATTERNS[@]} -eq 0 ]] && EXCLUDE_PATTERNS=("${DEFAULT_EXCLUDE_PATTERNS[@]}")
    return 0
}

save_current_task_context() {
    local task_id="${1:-$CURRENT_TASK_ID}"
    [[ -z "$task_id" ]] && return 0
    
    task_set_scalar "$task_id" PREFIX "$BACKUP_PREFIX"
    task_set_scalar "$task_id" MAX_BACKUPS "$MAX_BACKUPS"
    task_set_scalar "$task_id" COMPRESS "$COMPRESS_BACKUP"
    task_set_scalar "$task_id" COMPRESSION_LEVEL "$COMPRESSION_LEVEL"
    task_set_scalar "$task_id" SQLITE_SAFE "$SQLITE_SAFE_BACKUP"
    task_set_array "$task_id" DIRS "${BACKUP_DIRS[@]}"
    task_set_array "$task_id" EXCLUDES "${EXCLUDE_PATTERNS[@]}"
}

# 验证数据文件安全性：确保只包含合法的 shell 赋值语句
validate_data_file() {
    local file="$1"
    [[ ! -f "$file" ]] && return 1
    # 检查文件是否包含可疑内容（命令替换、管道、重定向等）
    local suspicious
    suspicious=$(grep -n '`\|^\s*exec\s\|^\s*source\s\|^\s*\.\s\||\s*>\s*\$(' "$file" 2>/dev/null | grep -v '^#' | head -1)
    if [[ -n "$suspicious" ]]; then
        log_error "Security: suspicious content in $file: $suspicious"
        return 1
    fi
    return 0
}

load_tasks_store() {
    [[ -f "$TASKS_FILE" ]] && validate_data_file "$TASKS_FILE" && source "$TASKS_FILE"
}

load_schedules_store() {
    [[ -f "$SCHEDULES_FILE" ]] && validate_data_file "$SCHEDULES_FILE" && source "$SCHEDULES_FILE"
}

save_tasks_store() {
    init_data_dir
    
    {
        echo "# vback tasks file"
        echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "TASK_IDS=("
        array_literal "${TASK_IDS[@]}"
        echo ")"
        printf 'ACTIVE_TASK_ID=%q\n' "$ACTIVE_TASK_ID"
        printf 'DEFAULT_TASK_ID=%q\n' "$DEFAULT_TASK_ID"
        echo ""
        
        local task_id
        for task_id in "${TASK_IDS[@]}"; do
            local -a task_dirs=() task_excludes=()
            task_get_array "$task_id" DIRS task_dirs
            task_get_array "$task_id" EXCLUDES task_excludes
            
            printf 'TASK_NAME_%s=%q\n' "$task_id" "$(task_get_scalar "$task_id" NAME)"
            printf 'TASK_PREFIX_%s=%q\n' "$task_id" "$(task_get_scalar "$task_id" PREFIX)"
            printf 'TASK_MAX_BACKUPS_%s=%q\n' "$task_id" "$(task_get_scalar "$task_id" MAX_BACKUPS)"
            printf 'TASK_COMPRESS_%s=%q\n' "$task_id" "$(task_get_scalar "$task_id" COMPRESS)"
            printf 'TASK_COMPRESSION_LEVEL_%s=%q\n' "$task_id" "$(task_get_scalar "$task_id" COMPRESSION_LEVEL)"
            printf 'TASK_SQLITE_SAFE_%s=%q\n' "$task_id" "$(task_get_scalar "$task_id" SQLITE_SAFE)"
            echo "TASK_DIRS_${task_id}=("
            array_literal "${task_dirs[@]}"
            echo ")"
            echo "TASK_EXCLUDES_${task_id}=("
            array_literal "${task_excludes[@]}"
            echo ")"
            echo ""
        done
    } > "$TASKS_FILE"
    
    chmod 600 "$TASKS_FILE"
}

save_schedules_store() {
    init_data_dir
    
    {
        echo "# vback schedules file"
        echo "# Generated: $(date '+%Y-%m-%d %H:%M:%S')"
        echo ""
        echo "SCHEDULE_IDS=("
        array_literal "${SCHEDULE_IDS[@]}"
        echo ")"
        echo ""
        
        local schedule_id
        for schedule_id in "${SCHEDULE_IDS[@]}"; do
            printf 'SCHEDULE_NAME_%s=%q\n' "$schedule_id" "$(schedule_get_scalar "$schedule_id" NAME)"
            printf 'SCHEDULE_TASK_%s=%q\n' "$schedule_id" "$(schedule_get_scalar "$schedule_id" TASK)"
            printf 'SCHEDULE_CRON_%s=%q\n' "$schedule_id" "$(schedule_get_scalar "$schedule_id" CRON)"
            echo ""
        done
    } > "$SCHEDULES_FILE"
    
    chmod 600 "$SCHEDULES_FILE"
}

migrate_legacy_config() {
    if [[ ${#TASK_IDS[@]} -eq 0 && -f "$CONFIG_FILE" && ${#BACKUP_DIRS[@]} -gt 0 ]]; then
        local legacy_task_id="task_default"
        local -a legacy_excludes=("${EXCLUDE_PATTERNS[@]}")
        [[ ${#legacy_excludes[@]} -eq 0 ]] && legacy_excludes=("${DEFAULT_EXCLUDE_PATTERNS[@]}")
        
        TASK_IDS=("$legacy_task_id")
        DEFAULT_TASK_ID="$legacy_task_id"
        ACTIVE_TASK_ID="$legacy_task_id"
        
        task_set_scalar "$legacy_task_id" NAME "$(default_task_name)"
        task_set_scalar "$legacy_task_id" PREFIX "$BACKUP_PREFIX"
        task_set_scalar "$legacy_task_id" MAX_BACKUPS "$MAX_BACKUPS"
        task_set_scalar "$legacy_task_id" COMPRESS "$COMPRESS_BACKUP"
        task_set_scalar "$legacy_task_id" COMPRESSION_LEVEL "$COMPRESSION_LEVEL"
        task_set_scalar "$legacy_task_id" SQLITE_SAFE "$SQLITE_SAFE_BACKUP"
        task_set_array "$legacy_task_id" DIRS "${BACKUP_DIRS[@]}"
        task_set_array "$legacy_task_id" EXCLUDES "${legacy_excludes[@]}"
    fi
    
    if [[ ${#SCHEDULE_IDS[@]} -eq 0 && -f "$CONFIG_FILE" && -n "$SCHEDULE_CRON" && ${#TASK_IDS[@]} -gt 0 ]]; then
        local default_task="${DEFAULT_TASK_ID:-${TASK_IDS[0]}}"
        create_schedule "$(default_schedule_name "$(task_get_scalar "$default_task" NAME)")" "$default_task" "$SCHEDULE_CRON" "schedule_default" >/dev/null
    fi
}

ensure_task_store() {
    if [[ ${#TASK_IDS[@]} -eq 0 && ! -f "$CONFIG_FILE" ]]; then
        CURRENT_TASK_ID=""
        return 0
    fi
    
    if [[ -z "$DEFAULT_TASK_ID" ]] || ! task_exists "$DEFAULT_TASK_ID"; then
        DEFAULT_TASK_ID="${TASK_IDS[0]}"
    fi
    
    if [[ -z "$ACTIVE_TASK_ID" ]] || ! task_exists "$ACTIVE_TASK_ID"; then
        ACTIVE_TASK_ID="${DEFAULT_TASK_ID:-${TASK_IDS[0]}}"
    fi
    
    if [[ -n "$ACTIVE_TASK_ID" ]]; then
        load_task_context "$ACTIVE_TASK_ID"
    fi
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] && validate_data_file "$CONFIG_FILE" && source "$CONFIG_FILE"
    load_tasks_store
    load_schedules_store
    migrate_legacy_config
    ensure_task_store
}

save_config() {
    init_data_dir
    save_current_task_context
    save_tasks_store
    save_schedules_store
    
    local mirror_task_id="$(resolve_default_task_id)"
    local mirror_prefix="" mirror_max_backups=7 mirror_compress=true mirror_compression_level=6 mirror_sqlite_safe=true
    local -a mirror_dirs=() mirror_excludes=("${DEFAULT_EXCLUDE_PATTERNS[@]}")
    
    if [[ -n "$mirror_task_id" ]] && task_exists "$mirror_task_id"; then
        mirror_prefix="$(task_get_scalar "$mirror_task_id" PREFIX)"
        mirror_max_backups="$(task_get_scalar "$mirror_task_id" MAX_BACKUPS)"
        mirror_compress="$(task_get_scalar "$mirror_task_id" COMPRESS)"
        mirror_compression_level="$(task_get_scalar "$mirror_task_id" COMPRESSION_LEVEL)"
        mirror_sqlite_safe="$(task_get_scalar "$mirror_task_id" SQLITE_SAFE)"
        task_get_array "$mirror_task_id" DIRS mirror_dirs
        task_get_array "$mirror_task_id" EXCLUDES mirror_excludes
    fi
    
    local mirror_schedule_cron="${SCHEDULE_CRON:-0 3 * * *}"
    if [[ ${#SCHEDULE_IDS[@]} -gt 0 ]]; then
        mirror_schedule_cron="$(schedule_get_scalar "${SCHEDULE_IDS[0]}" CRON)"
    fi
    
    cat > "$CONFIG_FILE" << EOF
# vback configuration file
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# Cloud Provider
CLOUD_PROVIDER=$(printf '%q' "$CLOUD_PROVIDER")

# S3 Connection
S3_ACCESS_KEY=$(printf '%q' "$S3_ACCESS_KEY")
S3_SECRET_KEY=$(printf '%q' "$S3_SECRET_KEY")
S3_ENDPOINT=$(printf '%q' "$S3_ENDPOINT")
S3_BUCKET=$(printf '%q' "$S3_BUCKET")
S3_REGION=$(printf '%q' "$S3_REGION")

# Legacy mirror (compatible with v1.2.x data layout)
BACKUP_DIRS=(
$(array_literal "${mirror_dirs[@]}")
)
BACKUP_PREFIX=$(printf '%q' "$mirror_prefix")
MAX_BACKUPS=$(printf '%q' "${mirror_max_backups:-7}")
COMPRESS_BACKUP=$(printf '%q' "${mirror_compress:-true}")
COMPRESSION_LEVEL=$(printf '%q' "${mirror_compression_level:-6}")
SQLITE_SAFE_BACKUP=$(printf '%q' "${mirror_sqlite_safe:-true}")
SCHEDULE_CRON=$(printf '%q' "$mirror_schedule_cron")
EXCLUDE_PATTERNS=(
$(array_literal "${mirror_excludes[@]}")
)

# Current defaults
ACTIVE_TASK_ID=$(printf '%q' "$ACTIVE_TASK_ID")
DEFAULT_TASK_ID=$(printf '%q' "$DEFAULT_TASK_ID")
EOF
    chmod 600 "$CONFIG_FILE"
}

needs_setup() {
    local check_task_id="$(resolve_default_task_id)"
    local -a check_dirs=()
    
    [[ -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" || -z "$S3_BUCKET" || -z "$check_task_id" ]] && return 0
    task_get_array "$check_task_id" DIRS check_dirs
    [[ ${#check_dirs[@]} -eq 0 ]]
}

# ============================================================================
# 日志系统
# ============================================================================

declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

rotate_logs() {
    [[ ! -f "$LOG_FILE" ]] && return
    local size=$(get_file_size "$LOG_FILE")
    
    if [[ $size -ge $LOG_MAX_SIZE ]]; then
        for ((i=LOG_BACKUP_COUNT-1; i>=1; i--)); do
            [[ -f "${LOG_FILE}.$((i-1)).gz" ]] && mv "${LOG_FILE}.$((i-1)).gz" "${LOG_FILE}.${i}.gz"
        done
        gzip -c "$LOG_FILE" > "${LOG_FILE}.0.gz" 2>/dev/null && : > "$LOG_FILE"
    fi
}

log() {
    local level="${1:-INFO}" message="$2"
    local level_num="${LOG_LEVELS[$level]:-1}"
    local current_level_num="${LOG_LEVELS[${LOG_LEVEL:-INFO}]:-1}"
    [[ $level_num -lt $current_level_num ]] && return
    
    init_data_dir
    local ts=$(date '+%Y-%m-%d %H:%M:%S')
    echo "[$ts] [$level] $message" >> "$LOG_FILE" 2>/dev/null
    rotate_logs
    
    [[ "$VERBOSE" == "true" ]] && {
        local color
        case "$level" in
            DEBUG) color="$C_MUTED" ;; INFO) color="$C_INFO" ;;
            WARN) color="$C_WARNING" ;; ERROR) color="$C_ERROR" ;;
        esac
        echo -e "${color}[$ts] [$level] $message${C_RESET}" >&2
    }
}

log_info()  { log "INFO" "$1"; }
log_warn()  { log "WARN" "$1"; }
log_error() { log "ERROR" "$1"; }
log_debug() { log "DEBUG" "$1"; }

# ============================================================================
# UI 组件
# ============================================================================

BOX_WIDTH=58

print_line() {
    local char="${1:-─}"
    printf "  ${C_BORDER}"
    printf '%*s' "$((BOX_WIDTH-4))" '' | tr ' ' "$char"
    printf "${C_RESET}\n"
}

print_box_top() {
    printf "  ${C_BORDER}╭"
    printf '%*s' "$((BOX_WIDTH-4))" '' | tr ' ' '─'
    printf "╮${C_RESET}\n"
}

print_box_bottom() {
    printf "  ${C_BORDER}╰"
    printf '%*s' "$((BOX_WIDTH-4))" '' | tr ' ' '─'
    printf "╯${C_RESET}\n"
}

print_box_line() {
    local content="$1" align="${2:-left}"
    local stripped=$(echo -e "$content" | sed 's/\x1b\[[0-9;]*m//g')
    local inner_width=$((BOX_WIDTH-6))
    local padding=$((inner_width - ${#stripped}))
    [[ $padding -lt 0 ]] && padding=0
    
    case "$align" in
        center)
            local lp=$((padding/2)) rp=$((padding-lp))
            printf "  ${C_BORDER}│${C_RESET} %*s%b%*s ${C_BORDER}│${C_RESET}\n" "$lp" "" "$content" "$rp" ""
            ;;
        right)
            printf "  ${C_BORDER}│${C_RESET} %*s%b ${C_BORDER}│${C_RESET}\n" "$padding" "" "$content"
            ;;
        *)
            printf "  ${C_BORDER}│${C_RESET} %b%*s ${C_BORDER}│${C_RESET}\n" "$content" "$padding" ""
            ;;
    esac
}

info()    { echo -e "  ${C_INFO}▸${C_RESET} $1"; log_info "$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')"; }
success() { echo -e "  ${C_SUCCESS}✓${C_RESET} $1"; log_info "$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')"; }
warn()    { echo -e "  ${C_WARNING}⚠${C_RESET} $1"; log_warn "$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')"; }
error()   { echo -e "  ${C_ERROR}✗${C_RESET} $1"; log_error "$(echo -e "$1" | sed 's/\x1b\[[0-9;]*m//g')"; }

fmt_size() {
    local s=$1
    if [[ $s -ge 1073741824 ]]; then awk "BEGIN {printf \"%.2f GB\", $s/1073741824}"
    elif [[ $s -ge 1048576 ]]; then awk "BEGIN {printf \"%.2f MB\", $s/1048576}"
    elif [[ $s -ge 1024 ]]; then awk "BEGIN {printf \"%.1f KB\", $s/1024}"
    else echo "${s} B"; fi
}

fmt_duration() {
    local secs=$1
    if [[ $secs -ge 3600 ]]; then printf "%dh %dm %ds" $((secs/3600)) $((secs%3600/60)) $((secs%60))
    elif [[ $secs -ge 60 ]]; then printf "%dm %ds" $((secs/60)) $((secs%60))
    else printf "%ds" "$secs"; fi
}

fmt_speed() {
    local bytes=$1 secs=$2
    [[ $secs -le 0 ]] && secs=1
    fmt_size $((bytes/secs))
}

press_enter() {
    echo ""
    echo -ne "  ${C_MUTED}${L[press_enter]}${C_RESET}"
    read -r
}

confirm() {
    local msg="${1:-${L[confirm]}?}" default="${2:-n}"
    local prompt="${L[yes_no]}"
    [[ "$default" == "y" ]] && prompt="${L[yes_no_y]}"
    
    echo -ne "  ${C_WARNING}?${C_RESET} ${msg} ${prompt}: "
    read -r ans
    
    if [[ -z "$ans" ]]; then
        [[ "$default" == "y" ]] && return 0 || return 1
    fi
    [[ "$ans" =~ ^[Yy]$ ]]
}

input_path() {
    local label="$1" default="$2" var_name="$3"
    local current="${!var_name:-$default}"
    local hint="${L[dir_path_hint]}"
    
    echo -ne "  ${C_PRIMARY}${label}${C_RESET}"
    [[ -n "$current" ]] && echo -ne " ${C_MUTED}[$current]${C_RESET}"
    echo ""
    echo -e "  ${C_HINT}${hint}${C_RESET}"
    echo -ne "  > ${C_INPUT}"
    
    read -e -r input
    echo -ne "${C_RESET}"
    
    if [[ -n "$input" ]]; then
        # 安全展开 ~ 和环境变量，不使用 eval
        input="${input//\~/$HOME}"
        while [[ "$input" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*)\} ]]; do
            local ename="${BASH_REMATCH[1]}"
            input="${input//\$\{${ename}\}/${!ename}}"
        done
        while [[ "$input" =~ \$([a-zA-Z_][a-zA-Z0-9_]*) ]]; do
            local ename="${BASH_REMATCH[1]}"
            input="${input//\$${ename}/${!ename}}"
        done
        eval "$var_name=\"\$input\""
    elif [[ -n "$current" ]]; then
        eval "$var_name=\"\$current\""
    fi
}

input_field() {
    local label="$1" default="$2" var_name="$3" is_secret="${4:-false}"
    local current="${!var_name:-$default}"
    local hint_key="${5:-}"
    
    echo -ne "  ${C_PRIMARY}${label}${C_RESET}"
    if [[ -n "$hint_key" && -n "${L[$hint_key]}" ]]; then
        echo -ne " ${C_HINT}(${L[$hint_key]})${C_RESET}"
    fi
    
    if [[ "$is_secret" == "true" ]]; then
        [[ -n "$current" ]] && echo -ne " ${C_MUTED}[${L[keep_empty_unchanged]}]${C_RESET}"
        echo -ne ": "
        read -rs input
        echo ""
    else
        [[ -n "$current" ]] && echo -ne " ${C_MUTED}[$current]${C_RESET}"
        echo -ne ": ${C_INPUT}"
        read -r input
        echo -ne "${C_RESET}"
    fi
    
    if [[ -n "$input" ]]; then
        eval "$var_name=\"\$input\""
    elif [[ -n "$current" && "$is_secret" != "true" ]]; then
        eval "$var_name=\"\$current\""
    fi
}

menu_item() {
    local key="$1" label="$2" desc="${3:-}"
    if [[ -n "$desc" ]]; then
        printf "    ${C_MENU_NUM}%s${C_RESET})  %-18s ${C_MUTED}%s${C_RESET}\n" "$key" "$label" "$desc"
    else
        printf "    ${C_MENU_NUM}%s${C_RESET})  %s\n" "$key" "$label"
    fi
}

menu_group() {
    echo ""
    echo -e "  ${C_MUTED}── ${C_BOLD}$1${C_RESET} ${C_MUTED}──${C_RESET}"
}

status_badge() {
    local status="$1" label="$2"
    case "$status" in
        ok|on|true)   echo -e "${C_SUCCESS}●${C_RESET} ${label}" ;;
        warn)         echo -e "${C_WARNING}●${C_RESET} ${label}" ;;
        error|off|false) echo -e "${C_ERROR}●${C_RESET} ${label}" ;;
        *)            echo -e "${C_MUTED}○${C_RESET} ${label}" ;;
    esac
}

show_kv() {
    local key="$1" value="$2" color="${3:-}"
    if [[ -n "$color" ]]; then
        printf "    ${C_MUTED}%-14s${C_RESET} ${color}%s${C_RESET}\n" "${key}" "$value"
    else
        printf "    ${C_MUTED}%-14s${C_RESET} %s\n" "${key}" "$value"
    fi
}

task_display_name() {
    local task_id="$1"
    local task_name
    task_name="$(task_get_scalar "$task_id" NAME)"
    printf '%s' "${task_name:-$task_id}"
}

task_dir_count() {
    local -a task_dirs=()
    task_get_array "$1" DIRS task_dirs
    echo "${#task_dirs[@]}"
}

task_prefix_display() {
    local prefix
    prefix="$(task_get_scalar "$1" PREFIX)"
    [[ -n "$prefix" ]] && printf '%s' "$prefix" || printf '%s' "${L[root_directory]}"
}

task_schedule_count() {
    local task_id="$1" count=0 schedule_id
    for schedule_id in "${SCHEDULE_IDS[@]}"; do
        [[ "$(schedule_get_scalar "$schedule_id" TASK)" == "$task_id" ]] && ((count++))
    done
    echo "$count"
}

resolve_task_ref() {
    local ref="$1" task_id
    [[ -z "$ref" ]] && return 1
    
    if task_exists "$ref"; then
        echo "$ref"
        return 0
    fi
    
    for task_id in "${TASK_IDS[@]}"; do
        [[ "$(task_display_name "$task_id")" == "$ref" ]] && {
            echo "$task_id"
            return 0
        }
    done
    
    return 1
}

schedule_display_name() {
    local schedule_id="$1"
    local schedule_name
    schedule_name="$(schedule_get_scalar "$schedule_id" NAME)"
    printf '%s' "${schedule_name:-$schedule_id}"
}

schedule_installed() {
    get_cron_status | grep -F -- "--schedule-id $1" >/dev/null 2>&1
}

prompt_task_selection() {
    local title="${1:-${L[select_option]}}" default_task="${2:-${ACTIVE_TASK_ID:-${TASK_IDS[0]}}}"
    
    if [[ ${#TASK_IDS[@]} -eq 0 ]]; then
        echo -e "  ${C_ERROR}✗${C_RESET} ${L[need_task_first]}" >&2
        log_error "${L[need_task_first]}"
        return 1
    fi
    
    if [[ ${#TASK_IDS[@]} -eq 1 ]]; then
        echo "${TASK_IDS[0]}"
        return 0
    fi
    
    echo -e "  ${C_BOLD}${title}${C_RESET}" >&2
    local i=1 task_id
    for task_id in "${TASK_IDS[@]}"; do
        local marker=" "
        [[ "$task_id" == "$default_task" ]] && marker="*"
        printf "    ${C_MENU_NUM}%d${C_RESET}) [%s] %s ${C_MUTED}(%s, %s %s)${C_RESET}\n" \
            "$i" "$marker" "$(task_display_name "$task_id")" "$(task_prefix_display "$task_id")" "$(task_dir_count "$task_id")" "${L[backup_directories]}" >&2
        ((i++))
    done
    
    echo "" >&2
    echo -ne "  ${L[select_option]} ${C_MUTED}[1-${#TASK_IDS[@]}/0]${C_RESET}: " >&2
    local choice
    read -r choice
    
    [[ "$choice" == "0" || -z "$choice" ]] && return 1
    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#TASK_IDS[@]} ]]; then
        echo "${TASK_IDS[$((choice-1))]}"
        return 0
    fi
    
    warn "${L[invalid_option]}"
    return 1
}

# ============================================================================
# S3 工具
# ============================================================================

check_s3_tool() {
    if command -v s3cmd &>/dev/null; then S3_TOOL="s3cmd"; return 0; fi
    if command -v aws &>/dev/null; then S3_TOOL="aws"; return 0; fi
    return 1
}

# 统一 S3 工具初始化（替代重复的 [[ "$S3_TOOL" == "s3cmd" ]] && setup_s3cmd || setup_aws）
setup_s3_tool() {
    if [[ "$S3_TOOL" == "s3cmd" ]]; then
        setup_s3cmd
    elif [[ "$S3_TOOL" == "aws" ]]; then
        setup_aws
    else
        log_error "No S3 tool configured (neither s3cmd nor aws-cli)"
        return 1
    fi
}

# 跨平台获取文件大小
get_file_size() {
    local file="$1"
    stat -c%s "$file" 2>/dev/null || stat -f%z "$file" 2>/dev/null || echo 0
}

# 解析默认任务 ID（消除重复的三级 fallback）
resolve_default_task_id() {
    echo "${DEFAULT_TASK_ID:-${ACTIVE_TASK_ID:-${TASK_IDS[0]}}}"
}

install_s3cmd() {
    info "${L[installing]} s3cmd..."
    
    if command -v apt-get &>/dev/null; then
        apt-get update -qq && apt-get install -y -qq s3cmd
    elif command -v yum &>/dev/null; then
        yum install -y -q s3cmd
    elif command -v dnf &>/dev/null; then
        dnf install -y -q s3cmd
    elif command -v pacman &>/dev/null; then
        pacman -Sy --noconfirm s3cmd
    elif command -v brew &>/dev/null; then
        brew install s3cmd
    elif command -v pip3 &>/dev/null; then
        pip3 install -q s3cmd
    elif command -v pip &>/dev/null; then
        pip install -q s3cmd
    else
        error "${L[err_install_failed]}"
        echo -e "  ${C_MUTED}${L[err_install_manual]}${C_RESET}"
        return 1
    fi
    
    command -v s3cmd &>/dev/null && { success "${L[installed]}"; return 0; }
    error "${L[err_install_failed]}"
    return 1
}

check_dependencies() {
    local missing=() optional_missing=()
    # 必需工具
    for cmd in tar gzip; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    # 推荐工具（缺失时警告但不阻止）
    for cmd in curl awk crontab; do
        command -v "$cmd" &>/dev/null || optional_missing+=("$cmd")
    done

    if [[ ${#missing[@]} -gt 0 ]]; then
        error "${L[err_missing_deps]}: ${missing[*]}"
        return 1
    fi

    if [[ ${#optional_missing[@]} -gt 0 ]]; then
        warn "${L[warn_optional_deps]}: ${optional_missing[*]}"
    fi
    return 0
}

setup_s3cmd() {
    cat > "$S3CMD_CFG" << EOF
[default]
access_key = ${S3_ACCESS_KEY}
secret_key = ${S3_SECRET_KEY}
host_base = ${S3_ENDPOINT}
host_bucket = %(bucket)s.${S3_ENDPOINT}
use_https = True
signature_v2 = False
bucket_location = ${S3_REGION}
EOF
    chmod 600 "$S3CMD_CFG"
}

setup_aws() {
    export AWS_ACCESS_KEY_ID="$S3_ACCESS_KEY"
    export AWS_SECRET_ACCESS_KEY="$S3_SECRET_KEY"
    export AWS_DEFAULT_REGION="$S3_REGION"
    AWS_ENDPOINT="--endpoint-url https://${S3_ENDPOINT}"
}

build_s3_path() {
    local path="$1"
    [[ -n "$BACKUP_PREFIX" ]] && echo "${BACKUP_PREFIX}/${path}" || echo "$path"
}

should_show_upload_progress() {
    [[ "$RUN_CONTEXT" != "scheduled" && -t 1 && -t 2 ]]
}

S3_UPLOAD_RETRIES="${S3_UPLOAD_RETRIES:-3}"
S3_UPLOAD_RETRY_DELAY="${S3_UPLOAD_RETRY_DELAY:-5}"

s3_put() {
    local src="$1" dst=$(build_s3_path "$2") show_progress="${3:-auto}"
    [[ "$show_progress" == "auto" ]] && { should_show_upload_progress && show_progress=true || show_progress=false; }

    local attempt=1 rc=1
    while ((attempt <= S3_UPLOAD_RETRIES)); do
        if [[ "$S3_TOOL" == "s3cmd" ]]; then
            if [[ "$show_progress" == "true" ]]; then
                s3cmd -c "$S3CMD_CFG" put --progress "$src" "s3://${S3_BUCKET}/${dst}"
            else
                s3cmd -c "$S3CMD_CFG" put "$src" "s3://${S3_BUCKET}/${dst}" 2>&1
            fi
        else
            if [[ "$show_progress" == "true" ]]; then
                aws s3 cp "$src" "s3://${S3_BUCKET}/${dst}" $AWS_ENDPOINT
            else
                aws s3 cp "$src" "s3://${S3_BUCKET}/${dst}" $AWS_ENDPOINT --no-progress 2>&1
            fi
        fi
        rc=$?
        [[ $rc -eq 0 ]] && break
        ((attempt < S3_UPLOAD_RETRIES)) && log_warn "Upload attempt $attempt/$S3_UPLOAD_RETRIES failed, retrying in ${S3_UPLOAD_RETRY_DELAY}s..."
        ((attempt < S3_UPLOAD_RETRIES)) && sleep "$S3_UPLOAD_RETRY_DELAY"
        ((attempt++))
    done
    return $rc
}

# 上传后 MD5 校验
s3_verify_upload() {
    local src="$1" dst=$(build_s3_path "$2")
    local local_md5 remote_md5

    if ! command -v md5sum &>/dev/null && ! command -v md5 &>/dev/null; then
        log_debug "MD5 tool not available, skipping upload verification"
        return 0
    fi

    if command -v md5sum &>/dev/null; then
        local_md5=$(md5sum "$src" 2>/dev/null | awk '{print $1}')
    else
        local_md5=$(md5 -q "$src" 2>/dev/null)
    fi
    [[ -z "$local_md5" ]] && { log_warn "Cannot compute local MD5"; return 0; }

    if [[ "$S3_TOOL" == "s3cmd" ]]; then
        remote_md5=$(s3cmd -c "$S3CMD_CFG" info "s3://${S3_BUCKET}/${dst}" 2>/dev/null | grep -i "MD5 sum" | awk '{print $NF}' | tr -d '"')
    else
        remote_md5=$(aws s3api head-object --bucket "$S3_BUCKET" --key "$dst" $AWS_ENDPOINT --query ETag --output text 2>/dev/null | tr -d '"')
    fi

    if [[ -z "$remote_md5" ]]; then
        log_warn "Cannot verify upload: remote MD5 not available"
        return 0
    fi

    if [[ "$local_md5" == "$remote_md5" ]]; then
        log_info "Upload verified: MD5 match ($local_md5)"
        return 0
    else
        log_error "Upload verification failed: local=$local_md5 remote=$remote_md5"
        return 1
    fi
}

s3_list() {
    local prefix=$(build_s3_path "$1")
    if [[ "$S3_TOOL" == "s3cmd" ]]; then
        s3cmd -c "$S3CMD_CFG" ls "s3://${S3_BUCKET}/${prefix}" 2>/dev/null
    else
        aws s3 ls "s3://${S3_BUCKET}/${prefix}" $AWS_ENDPOINT 2>/dev/null
    fi
}

s3_rm() {
    local path=$(build_s3_path "$1")
    if [[ "$S3_TOOL" == "s3cmd" ]]; then
        s3cmd -c "$S3CMD_CFG" del "s3://${S3_BUCKET}/${path}" --recursive 2>/dev/null
    else
        aws s3 rm "s3://${S3_BUCKET}/${path}" --recursive $AWS_ENDPOINT 2>/dev/null
    fi
}

s3_test() {
    info "${L[testing_connection]}"
    local test_file
    test_file=$(mktemp "${TMPDIR:-/tmp}/vback-test.XXXXXX.txt" 2>/dev/null) || test_file="/tmp/vback-test-$$.txt"
    echo "vback-test-$(date +%s)" > "$test_file"
    
    local start=$(date +%s)
    local result
    if [[ "$S3_TOOL" == "s3cmd" ]]; then
        result=$(s3cmd -c "$S3CMD_CFG" put "$test_file" "s3://${S3_BUCKET}/.vback-test" 2>&1)
    else
        result=$(aws s3 cp "$test_file" "s3://${S3_BUCKET}/.vback-test" $AWS_ENDPOINT 2>&1)
    fi
    local duration=$(($(date +%s) - start))
    rm -f "$test_file"
    
    if echo "$result" | grep -qi "error\|fail\|denied\|invalid"; then
        error "${L[connection_failed]}"
        echo "$result" | head -3 | sed 's/^/    /'
        return 1
    fi
    
    s3_rm ".vback-test" &>/dev/null
    success "${L[connection_success]} (${duration}s)"
    return 0
}

# ============================================================================
# 配置验证
# ============================================================================

validate_config() {
    local task_id="${1:-${CURRENT_TASK_ID:-${DEFAULT_TASK_ID:-${TASK_IDS[0]}}}}"
    [[ -n "$task_id" && "$CURRENT_TASK_ID" != "$task_id" ]] && load_task_context "$task_id"
    
    local errors=()
    [[ -z "$S3_ACCESS_KEY" ]] && errors+=("${L[access_key]} ${L[not_set]}")
    [[ -z "$S3_SECRET_KEY" ]] && errors+=("${L[secret_key]} ${L[not_set]}")
    [[ -z "$S3_BUCKET" ]] && errors+=("${L[bucket]} ${L[not_set]}")
    [[ ${#BACKUP_DIRS[@]} -eq 0 ]] && errors+=("${L[backup_directories]} ${L[not_set]}")
    
    for d in "${BACKUP_DIRS[@]}"; do
        [[ ! -d "$d" ]] && errors+=("$d ${L[not_exist]}")
    done
    
    if [[ ${#errors[@]} -gt 0 ]]; then
        error "${L[err_config_errors]}:"
        for e in "${errors[@]}"; do
            echo -e "    ${C_ERROR}•${C_RESET} $e"
        done
        return 1
    fi
    return 0
}

# ============================================================================
# SQLite 安全备份
# ============================================================================

backup_sqlite_db() {
    local db_file="$1" backup_file="$2"
    if command -v sqlite3 &>/dev/null; then
        # 使用 .backup 命令的参数化形式，避免 SQL 注入
        sqlite3 "$db_file" ".backup" "$backup_file" 2>/dev/null && return 0
    fi
    cp "$db_file" "$backup_file" 2>/dev/null
}

prepare_safe_copy() {
    local src_dir="$1" dest_dir="$2"
    local db_count=0
    
    mkdir -p "$dest_dir"
    
    local exclude_args=()
    for p in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_args+=(--exclude="$p")
    done
    
    if [[ "$SQLITE_SAFE_BACKUP" == "true" ]]; then
        exclude_args+=(--exclude='*.db' --exclude='*.sqlite')
        exclude_args+=(--exclude='*.db-wal' --exclude='*.db-shm' --exclude='*.db-journal')
    fi
    
    if command -v rsync &>/dev/null; then
        rsync -a "${exclude_args[@]}" "$src_dir/" "$dest_dir/" 2>/dev/null
    else
        # cp -a 在 macOS 上可能不可用，使用 cp -pR 作为 fallback
        cp -a "$src_dir/." "$dest_dir/" 2>/dev/null || cp -pR "$src_dir/." "$dest_dir/" 2>/dev/null
        warn "${L[warn_no_rsync]}"
    fi
    
    if [[ "$SQLITE_SAFE_BACKUP" == "true" ]]; then
        while IFS= read -r -d '' db_file; do
            local rel_path="${db_file#$src_dir/}"
            local dest_file="$dest_dir/$rel_path"
            mkdir -p "$(dirname "$dest_file")"
            backup_sqlite_db "$db_file" "$dest_file" && ((db_count++))
        done < <(find "$src_dir" -type f \( -name "*.db" -o -name "*.sqlite" \) -print0 2>/dev/null)
        
        [[ $db_count -gt 0 ]] && info "SQLite: ${C_NUMBER}${db_count}${C_RESET} ${L[sqlite_dbs]}"
    fi
    
    echo "$db_count"
}

# ============================================================================
# 进程锁管理
# ============================================================================

get_process_info() {
    local pid="$1"
    if [[ -d "/proc/$pid" ]]; then
        local cmd=$(cat "/proc/$pid/cmdline" 2>/dev/null | tr '\0' ' ')
        local start_time
        start_time=$(stat -c %Y "/proc/$pid" 2>/dev/null || stat -f %m "/proc/$pid" 2>/dev/null)
        if [[ -n "$start_time" ]]; then
            local running_time=$(($(date +%s) - start_time))
            echo "CMD: $cmd"
            echo "Running: $(fmt_duration $running_time)"
        else
            echo "CMD: $cmd"
        fi
    else
        ps -p "$pid" -o pid,etime,command 2>/dev/null | tail -1
    fi
}

is_process_alive() {
    local pid="$1"
    kill -0 "$pid" 2>/dev/null
}

kill_process() {
    local pid="$1"
    
    kill -15 "$pid" 2>/dev/null
    sleep 1
    
    if is_process_alive "$pid"; then
        kill -9 "$pid" 2>/dev/null
        sleep 1
    fi
    
    ! is_process_alive "$pid"
}

acquire_lock() {
    local lock_dir="${TMPDIR:-/tmp}/vback.lock"

    if [[ -d "$lock_dir" ]]; then
        local pid
        pid=$(cat "$lock_dir/pid" 2>/dev/null)

        if [[ -n "$pid" ]]; then
            if is_process_alive "$pid"; then
                echo ""
                error "${L[err_task_running]}"
                echo ""
                echo -e "  ${C_MUTED}${L[err_lock_pid]}:${C_RESET} ${C_NUMBER}$pid${C_RESET}"
                echo ""
                echo -e "  ${C_MUTED}${L[err_lock_process_info]}:${C_RESET}"
                get_process_info "$pid" | sed 's/^/    /'
                echo ""

                if confirm "${L[err_lock_ask_kill]}" "n"; then
                    info "Terminating process $pid..."
                    if kill_process "$pid"; then
                        success "${L[err_lock_killed]}"
                        rm -rf "$lock_dir"
                        log_warn "Killed stale process $pid and removed lock"
                    else
                        error "${L[err_lock_kill_failed]}"
                        return 1
                    fi
                else
                    return 1
                fi
            else
                warn "${L[err_lock_stale]}"
                rm -rf "$lock_dir"
                log_warn "Removed stale lock (pid $pid not running)"
            fi
        else
            warn "${L[err_lock_stale]}"
            rm -rf "$lock_dir"
        fi
    fi

    # 使用 mkdir 原子操作创建锁，避免竞态条件
    if ! mkdir "$lock_dir" 2>/dev/null; then
        error "${L[err_task_running]}"
        return 1
    fi
    echo $$ > "$lock_dir/pid"
    LOCK_DIR="$lock_dir"
    LOCK_FILE="$lock_dir/pid"
    trap 'rm -rf "$LOCK_DIR" "$S3CMD_CFG"; rm -rf "$TEMP_DIR"' EXIT
    return 0
}

# ============================================================================
# 备份核心
# ============================================================================

get_dir_size() {
    # 跨平台兼容：Linux 用 du -sb，macOS 用 du -sk * 1024
    local size
    size=$(du -sb "$1" 2>/dev/null | cut -f1) && [[ -n "$size" ]] && echo "$size" && return
    size=$(du -sk "$1" 2>/dev/null | cut -f1) && [[ -n "$size" ]] && echo "$((size * 1024))" && return
    echo 0
}
count_files() { find "$1" -type f 2>/dev/null | wc -l; }
count_sqlite_dbs() { find "$1" -type f \( -name "*.db" -o -name "*.sqlite" \) 2>/dev/null | wc -l; }

backup_dir() {
    local src="$1" ts="$2"
    local name=$(basename "$src")
    
    echo ""
    info "${L[backing_up]}: ${C_PATH}$src${C_RESET}"
    
    local start=$(date +%s)
    local src_size=$(get_dir_size "$src")
    local src_files=$(count_files "$src")
    
    info "${L[source]}: ${C_NUMBER}$(fmt_size $src_size)${C_RESET}, ${C_NUMBER}${src_files}${C_RESET} ${L[files]}"
    
    mkdir -p "$TEMP_DIR"
    local work_dir="$TEMP_DIR/${name}"
    
    info "${L[preparing_files]}..."
    prepare_safe_copy "$src" "$work_dir"
    
    local archive_file s3_key
    if [[ "$COMPRESS_BACKUP" == "true" ]]; then
        archive_file="${TEMP_DIR}/${name}_${ts}.tar.gz"
        s3_key="${name}/${name}_${ts}.tar.gz"
        
        info "${L[compressing]} (${L[compression_level]} ${COMPRESSION_LEVEL})..."
        if ! tar -cf - -C "$TEMP_DIR" "$name" 2>"${TEMP_DIR}/tar_errors.log" | gzip -"${COMPRESSION_LEVEL}" > "$archive_file" 2>/dev/null; then
            # 显示 tar 的部分失败信息（如权限不足的文件）
            if [[ -s "${TEMP_DIR}/tar_errors.log" ]]; then
                warn "${L[compress_partial_warning]}"
                head -5 "${TEMP_DIR}/tar_errors.log" | sed 's/^/    /'
            fi
            error "${L[compress_failed]}"
            rm -rf "$work_dir"
            return 1
        fi
    else
        archive_file="${TEMP_DIR}/${name}_${ts}.tar"
        s3_key="${name}/${name}_${ts}.tar"
        
        if ! tar -cf "$archive_file" -C "$TEMP_DIR" "$name" 2>"${TEMP_DIR}/tar_errors.log"; then
            if [[ -s "${TEMP_DIR}/tar_errors.log" ]]; then
                warn "${L[compress_partial_warning]}"
                head -5 "${TEMP_DIR}/tar_errors.log" | sed 's/^/    /'
            fi
            error "${L[tar_failed]}"
            rm -rf "$work_dir"
            return 1
        fi
    fi
    
    rm -rf "$work_dir"
    local archive_size=$(get_file_size "$archive_file")
    
    info "${L[uploading]}..."
    local upload_start=$(date +%s)
    local result="" rc=0
    if should_show_upload_progress; then
        echo ""
        s3_put "$archive_file" "$s3_key" true
        rc=$?
        echo ""
    else
        result=$(s3_put "$archive_file" "$s3_key" false)
        rc=$?
    fi
    local upload_duration=$(($(date +%s) - upload_start))

    # 上传后 MD5 校验
    local verify_rc=0
    if [[ $rc -eq 0 ]]; then
        s3_verify_upload "$archive_file" "$s3_key" || verify_rc=$?
    fi

    rm -f "$archive_file"
    local total_duration=$(($(date +%s) - start))

    local output_has_error=false
    [[ -n "$result" ]] && echo "$result" | grep -qi "error\|fail" && output_has_error=true

    if [[ $rc -eq 0 && $verify_rc -eq 0 && "$output_has_error" != "true" ]]; then
        local speed=$(fmt_speed $archive_size $upload_duration)
        success "${L[upload_complete]}: ${C_PATH}${s3_key}${C_RESET}"
        info "${L[transfer]}: ${C_NUMBER}$(fmt_size $archive_size)${C_RESET} @ ${C_NUMBER}${speed}/s${C_RESET}"
        info "${L[duration]}: ${C_NUMBER}$(fmt_duration $total_duration)${C_RESET}"
        log_info "Backup success: $name size=$(fmt_size $archive_size)"
        return 0
    else
        if [[ $verify_rc -ne 0 ]]; then
            error "${L[upload_verify_failed]}"
            log_error "Upload verification failed: $name"
        else
            error "${L[upload_failed]}"
            log_error "Backup failed: $name"
        fi
        [[ -n "$result" ]] && echo "$result" | head -3 | sed 's/^/    /'
        return 1
    fi
}

cleanup_old() {
    local name="$1"
    [[ $MAX_BACKUPS -le 0 ]] && return
    
    local items
    if [[ "$S3_TOOL" == "s3cmd" ]]; then
        items=$(s3_list "${name}/" | awk '{print $NF}' | xargs -I{} basename {} 2>/dev/null | sort -ru)
    else
        items=$(s3_list "${name}/" | awk '{print $NF}' | sort -ru)
    fi
    
    local n=0 deleted=0
    while IFS= read -r item; do
        [[ -z "$item" ]] && continue
        ((n++))
        [[ $n -gt $MAX_BACKUPS ]] && s3_rm "${name}/${item}" &>/dev/null && ((deleted++))
    done <<< "$items"
    
    [[ $deleted -gt 0 ]] && info "${L[cleaned_old_backups]}: ${C_NUMBER}${deleted}${C_RESET}"
}

do_backup() {
    local ts=$(date '+%Y%m%d_%H%M%S')
    local start=$(date +%s)
    local ok=0 fail=0
    
    echo ""
    print_box_top
    print_box_line ""
    print_box_line "${C_TITLE}${L[start_backup]}${C_RESET}" center
    print_box_line ""
    print_box_line "$(date '+%Y-%m-%d %H:%M:%S')" center
    print_box_line "${C_MUTED}${S3_BUCKET}${BACKUP_PREFIX:+/${BACKUP_PREFIX}}${C_RESET}" center
    print_box_bottom
    
    log_info "========== Backup started =========="
    
    validate_config || return 1
    acquire_lock || return 1
    
    setup_s3_tool
    
    local total=${#BACKUP_DIRS[@]}
    local current=0
    
    for d in "${BACKUP_DIRS[@]}"; do
        ((current++))
        echo ""
        print_line '─'
        local progress_pct=$((current * 100 / total))
        echo -e "  ${C_BOLD}[$current/$total | ${progress_pct}%]${C_RESET} $(basename "$d")"
        
        if backup_dir "$d" "$ts"; then
            ((ok++))
            cleanup_old "$(basename "$d")"
        else
            ((fail++))
        fi
    done
    
    rm -rf "$TEMP_DIR"
    local duration=$(($(date +%s) - start))
    
    echo ""
    print_box_top
    print_box_line ""
    if [[ $fail -eq 0 ]]; then
        print_box_line "${C_SUCCESS}✓ ${L[backup_complete]}${C_RESET}" center
        print_box_line "${L[all_success]}: ${ok}/${total}" center
    else
        print_box_line "${C_WARNING}⚠ ${L[backup_complete]}${C_RESET}" center
        print_box_line "${ok} ${L[partial_success]} ${fail}" center
    fi
    print_box_line ""
    print_box_line "${L[total_duration]}: $(fmt_duration $duration)" center
    print_box_bottom
    
    log_info "========== Backup completed: ok=$ok fail=$fail =========="
    return $fail
}

# ============================================================================
# 定时任务
# ============================================================================

get_cron_status() {
    crontab -l 2>/dev/null | grep -F "$SCRIPT_PATH" | grep -v "^#"
}

remove_all_cron_jobs() {
    local current_crontab
    current_crontab="$(crontab -l 2>/dev/null || true)"
    printf '%s\n' "$current_crontab" | grep -v -F "$SCRIPT_PATH" | crontab - 2>/dev/null
}

build_cron_command() {
    local task_id="$1" schedule_id="$2"
    local script_q task_q schedule_q log_q
    printf -v script_q '%q' "$SCRIPT_PATH"
    printf -v task_q '%q' "$task_id"
    printf -v schedule_q '%q' "$schedule_id"
    printf -v log_q '%q' "$LOG_FILE"
    printf '%s backup --task-id %s --scheduled --schedule-id %s >> %s 2>&1' "$script_q" "$task_q" "$schedule_q" "$log_q"
}

sync_cron_jobs() {
    local current_crontab filtered_crontab
    current_crontab="$(crontab -l 2>/dev/null || true)"
    filtered_crontab="$(printf '%s\n' "$current_crontab" | grep -v -F "$SCRIPT_PATH")"
    
    {
        [[ -n "$filtered_crontab" ]] && printf '%s\n' "$filtered_crontab"
        local schedule_id cron_expr task_id
        for schedule_id in "${SCHEDULE_IDS[@]}"; do
            cron_expr="$(schedule_get_scalar "$schedule_id" CRON)"
            task_id="$(schedule_get_scalar "$schedule_id" TASK)"
            [[ -n "$cron_expr" && -n "$task_id" ]] || continue
            printf '%s %s\n' "$cron_expr" "$(build_cron_command "$task_id" "$schedule_id")"
        done
    } | crontab -
}

install_cron() {
    local task_id="${1:-}" cron_expr="${2:-}" schedule_name="${3:-}" schedule_id="${4:-}"
    
    if [[ -n "$task_id" || -n "$cron_expr" || ${#SCHEDULE_IDS[@]} -eq 0 ]]; then
        task_id="${task_id:-$(resolve_default_task_id)}"
        cron_expr="${cron_expr:-${SCHEDULE_CRON:-0 3 * * *}}"
        schedule_name="${schedule_name:-$(default_schedule_name "$(task_get_scalar "$task_id" NAME)")}"
        schedule_id="${schedule_id:-}"
        
        if [[ -n "$schedule_id" ]] && schedule_exists "$schedule_id"; then
            schedule_set_scalar "$schedule_id" NAME "$schedule_name"
            schedule_set_scalar "$schedule_id" TASK "$task_id"
            schedule_set_scalar "$schedule_id" CRON "$cron_expr"
        elif [[ -n "$schedule_id" ]]; then
            create_schedule "$schedule_name" "$task_id" "$cron_expr" "$schedule_id" >/dev/null
        else
            create_schedule "$schedule_name" "$task_id" "$cron_expr" >/dev/null
        fi
    fi
    
    sync_cron_jobs
    save_config
    success "${L[cron_installed]}"
    log_info "Cron synced schedules=${#SCHEDULE_IDS[@]}"
}

remove_cron() {
    remove_all_cron_jobs
    success "${L[cron_removed]}"
    log_info "Cron removed"
}

# ============================================================================
# 更新功能
# ============================================================================

get_remote_version() {
    local remote_script
    remote_script=$(curl -fsSL --connect-timeout 10 "$RAW_SCRIPT_URL" 2>/dev/null)
    if [[ $? -ne 0 || -z "$remote_script" ]]; then
        return 1
    fi
    
    echo "$remote_script" | grep -m1 '^VERSION=' | cut -d'"' -f2
}

compare_versions() {
    local v1="$1" v2="$2"

    if [[ "$v1" == "$v2" ]]; then
        echo "equal"
        return
    fi

    local IFS='.'
    local -a ver1=($v1) ver2=($v2)

    for ((i=0; i<${#ver1[@]} || i<${#ver2[@]}; i++)); do
        # 去除非数字后缀（如 -beta, -rc1），仅比较数字部分
        local num1=${ver1[i]:-0}
        local num2=${ver2[i]:-0}
        num1=${num1%%[^0-9]*}
        num2=${num2%%[^0-9]*}
        [[ -z "$num1" ]] && num1=0
        [[ -z "$num2" ]] && num2=0

        if ((num1 > num2)); then
            echo "newer"
            return
        elif ((num1 < num2)); then
            echo "older"
            return
        fi
    done

    echo "equal"
}

do_update() {
    info "${L[checking_update]}"
    echo ""
    
    local remote_version
    remote_version=$(get_remote_version)
    
    if [[ -z "$remote_version" ]]; then
        error "${L[network_error]}"
        return 1
    fi
    
    show_kv "${L[current_version]}" "$VERSION" "$C_INFO"
    show_kv "${L[latest_version]}" "$remote_version" "$C_SUCCESS"
    echo ""
    
    local cmp=$(compare_versions "$VERSION" "$remote_version")
    
    if [[ "$cmp" == "older" ]]; then
        success "${L[update_available]}"
        echo ""
        
        if confirm "${L[confirm_update]}" "y"; then
            echo ""
            info "${L[updating]}"
            
            # 备份旧脚本
            local backup_file="${SCRIPT_PATH}.backup.$(date +%Y%m%d_%H%M%S)"
            cp "$SCRIPT_PATH" "$backup_file" 2>/dev/null
            
            # 下载新版本
            local new_script
            new_script=$(curl -fsSL --connect-timeout 30 "$RAW_SCRIPT_URL" 2>/dev/null)
            
            if [[ -z "$new_script" ]]; then
                error "${L[download_failed]}"
                return 1
            fi
            
            # 验证下载的脚本
            if ! echo "$new_script" | grep -q '^#!/bin/bash'; then
                error "${L[download_failed]}"
                return 1
            fi
            
            # 写入新脚本
            echo "$new_script" > "$SCRIPT_PATH"
            chmod +x "$SCRIPT_PATH"
            
            echo ""
            success "${L[update_success]}"
            info "${L[backup_old_script]} ${C_PATH}${backup_file}${C_RESET}"
            
            log_info "Updated from $VERSION to $remote_version"
            return 0
        else
            info "${L[operation_cancelled]}"
            return 0
        fi
    else
        success "${L[already_latest]}"
        return 0
    fi
}

# ============================================================================
# 恢复功能
# ============================================================================

do_restore() {
    local s3_key="$1" dest_dir="$2"

    if [[ -z "$s3_key" ]]; then
        error "${L[restore_need_key]}"
        return 1
    fi

    [[ -z "$dest_dir" ]] && dest_dir="."

    local full_key
    full_key=$(build_s3_path "$s3_key")
    local filename=$(basename "$s3_key")
    local local_file="${TEMP_DIR}/${filename}"

    info "${L[downloading]}: ${C_PATH}${full_key}${C_RESET}"
    mkdir -p "$TEMP_DIR"

    local rc=0
    if [[ "$S3_TOOL" == "s3cmd" ]]; then
        s3cmd -c "$S3CMD_CFG" get "s3://${S3_BUCKET}/${full_key}" "$local_file" 2>&1
        rc=$?
    else
        aws s3 cp "s3://${S3_BUCKET}/${full_key}" "$local_file" $AWS_ENDPOINT 2>&1
        rc=$?
    fi

    if [[ $rc -ne 0 || ! -f "$local_file" ]]; then
        error "${L[download_failed]}"
        rm -f "$local_file"
        return 1
    fi

    info "${L[extracting]}: ${C_PATH}${filename}${C_RESET} -> ${C_PATH}${dest_dir}${C_RESET}"
    mkdir -p "$dest_dir"

    if [[ "$filename" == *.tar.gz ]]; then
        tar -xzf "$local_file" -C "$dest_dir"
    elif [[ "$filename" == *.tar ]]; then
        tar -xf "$local_file" -C "$dest_dir"
    else
        cp "$local_file" "$dest_dir/"
    fi

    if [[ $? -eq 0 ]]; then
        success "${L[restore_complete]}: ${C_PATH}${dest_dir}${C_RESET}"
        log_info "Restore success: $s3_key -> $dest_dir"
    else
        error "${L[restore_failed]}"
        log_error "Restore failed: $s3_key"
        return 1
    fi

    rm -f "$local_file"
    return 0
}

menu_restore() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[restore_title]}${C_RESET}"
    echo ""

    local selected_task=""
    selected_task=$(prompt_task_selection "${L[select_backup_task]}" "$(resolve_default_task_id)") || { press_enter; return; }
    load_task_context "$selected_task"

    if ! validate_config "$selected_task"; then
        press_enter
        return
    fi

    check_s3_tool || { error "${L[err_no_s3_tool]}"; press_enter; return; }
    setup_s3_tool

    # 列出远端备份供选择
    echo -e "  ${C_BOLD}${L[available_backups]}${C_RESET}"
    echo ""

    local -a backup_keys=()
    for d in "${BACKUP_DIRS[@]}"; do
        local name=$(basename "$d")
        local list=$(s3_list "${name}/")
        if [[ -n "$list" ]]; then
            echo -e "  ${C_BOLD}$name${C_RESET}"
            echo "$list" | while read -r line; do
                local fn=$(echo "$line" | awk '{print $4}' | xargs basename 2>/dev/null)
                local dt=$(echo "$line" | awk '{print $1, $2}')
                local sz=$(echo "$line" | awk '{print $3}')
                if [[ -n "$fn" ]]; then
                    backup_keys+=("${name}/${fn}")
                    printf "    ${C_MENU_NUM}%d${C_RESET}) ${C_TIMESTAMP}%-16s${C_RESET}  ${C_NUMBER}%10s${C_RESET}  ${C_PATH}%s${C_RESET}\n" "${#backup_keys[@]}" "$dt" "$sz" "$fn"
                fi
            done
        fi
        echo ""
    done

    if [[ ${#backup_keys[@]} -eq 0 ]]; then
        warn "${L[no_backups_yet]}"
        press_enter
        return
    fi

    echo ""
    echo -ne "  ${L[select_option]} ${C_MUTED}[1-${#backup_keys[@]}/0]${C_RESET}: "
    local choice
    read -r choice

    [[ "$choice" == "0" || -z "$choice" ]] && return

    if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#backup_keys[@]} ]]; then
        local selected_key="${backup_keys[$((choice-1))]}"
        echo ""
        echo -e "  ${L[restore_dest_hint]}"
        echo -ne "  ${C_PRIMARY}${L[restore_directory]}${C_RESET}: ${C_INPUT}"
        read -r dest_dir
        echo -ne "${C_RESET}"
        [[ -z "$dest_dir" ]] && dest_dir="."

        if confirm "${L[confirm_restore]} ${C_PATH}${selected_key}${C_RESET} -> ${C_PATH}${dest_dir}${C_RESET}"; then
            do_restore "$selected_key" "$dest_dir"
        else
            info "${L[operation_cancelled]}"
        fi
    fi

    press_enter
}

# ============================================================================
# 重置功能
# ============================================================================

do_reset() {
    echo ""
    print_box_top
    print_box_line ""
    print_box_line "${C_ERROR}⚠ ${L[reset_all]}${C_RESET}" center
    print_box_line ""
    print_box_bottom
    echo ""
    
    echo -e "  ${C_ERROR}${L[reset_warning]}${C_RESET}"
    echo ""
    echo -e "  ${C_MUTED}${L[reset_items]}:${C_RESET}"
    echo -e "    ${C_ERROR}•${C_RESET} ${L[reset_config]}: ${C_PATH}${CONFIG_FILE}${C_RESET}"
    echo -e "    ${C_ERROR}•${C_RESET} ${L[reset_logs]}: ${C_PATH}${LOG_DIR}/*${C_RESET}"
    echo -e "    ${C_ERROR}•${C_RESET} ${L[reset_cron]}"
    echo -e "    ${C_ERROR}•${C_RESET} ${L[reset_lang]}"
    echo ""
    
    echo -ne "  ${C_WARNING}${L[reset_confirm]}${C_RESET}: "
    read -r confirm_text
    
    if [[ "$confirm_text" != "RESET" ]]; then
        echo ""
        warn "${L[reset_type_mismatch]}"
        return 1
    fi
    
    echo ""
    info "Resetting..."
    
    # 1. 移除定时任务
    if crontab -l 2>/dev/null | grep -qF "$SCRIPT_PATH"; then
        remove_all_cron_jobs
        info "Removed cron jobs"
    fi
    
    # 2. 删除配置目录
    if [[ -d "$DATA_DIR" ]]; then
        rm -rf "$DATA_DIR"
        info "Removed ${DATA_DIR}"
    fi
    
    # 3. 清理锁文件
    rm -rf "${TMPDIR:-/tmp}/vback.lock" 2>/dev/null
    
    # 4. 重置内存中的变量
    CLOUD_PROVIDER=""
    S3_ACCESS_KEY=""
    S3_SECRET_KEY=""
    S3_ENDPOINT=""
    S3_BUCKET=""
    S3_REGION=""
    BACKUP_DIRS=()
    BACKUP_PREFIX=""
    MAX_BACKUPS=7
    COMPRESS_BACKUP=true
    COMPRESSION_LEVEL=6
    SQLITE_SAFE_BACKUP=true
    EXCLUDE_PATTERNS=("${DEFAULT_EXCLUDE_PATTERNS[@]}")
    TASK_IDS=()
    SCHEDULE_IDS=()
    ACTIVE_TASK_ID=""
    DEFAULT_TASK_ID=""
    CURRENT_TASK_ID=""
    
    echo ""
    success "${L[reset_success]}"
    
    return 0
}

# ============================================================================
# 配置向导
# ============================================================================

select_provider() {
    clear
    echo ""
    print_box_top
    print_box_line ""
    print_box_line "${C_TITLE}${L[select_provider]}${C_RESET}" center
    print_box_line ""
    print_box_bottom
    echo ""
    
    local providers=("bitiful" "cloudflare" "aws" "aliyun" "qiniu" "gcloud" "custom")
    local i=1
    
    for p in "${providers[@]}"; do
        local name="${PROVIDERS[${p}_name]}"
        local desc="${PROVIDERS[${p}_desc]}"
        printf "    ${C_MENU_NUM}%d${C_RESET})  %-20s ${C_MUTED}%s${C_RESET}\n" "$i" "$name" "$desc"
        ((i++))
    done
    
    echo ""
    echo -ne "  ${L[select_option]} ${C_MUTED}[1-7]${C_RESET}: "
    read -r choice
    
    case "$choice" in
        1) CLOUD_PROVIDER="bitiful" ;;
        2) CLOUD_PROVIDER="cloudflare" ;;
        3) CLOUD_PROVIDER="aws" ;;
        4) CLOUD_PROVIDER="aliyun" ;;
        5) CLOUD_PROVIDER="qiniu" ;;
        6) CLOUD_PROVIDER="gcloud" ;;
        7) CLOUD_PROVIDER="custom" ;;
        *) CLOUD_PROVIDER="bitiful" ;;
    esac
    
    local default_endpoint=$(get_default_endpoint "$CLOUD_PROVIDER")
    local default_region=$(get_default_region "$CLOUD_PROVIDER")
    
    [[ -z "$S3_ENDPOINT" && -n "$default_endpoint" ]] && S3_ENDPOINT="$default_endpoint"
    [[ -z "$S3_REGION" && -n "$default_region" ]] && S3_REGION="$default_region"
}

setup_wizard() {
    local setup_task_id="${DEFAULT_TASK_ID}"
    local setup_task_name=""
    
    if [[ -z "$setup_task_id" ]]; then
        setup_task_id="$(create_task "$(default_task_name)")"
    elif ! task_exists "$setup_task_id"; then
        setup_task_id="$(create_task "$(default_task_name)")"
    fi
    
    load_task_context "$setup_task_id"
    setup_task_name="$(task_display_name "$setup_task_id")"
    
    clear
    echo ""
    print_box_top
    print_box_line ""
    print_box_line "${C_TITLE}vback ${L[setup_wizard]}${C_RESET}" center
    print_box_line ""
    print_box_bottom
    echo ""
    
    echo -e "  ${C_INFO}${L[welcome_message]}${C_RESET}"
    echo ""
    press_enter
    
    init_providers
    select_provider
    
    clear
    echo ""
    print_box_top
    print_box_line "${C_TITLE}${L[setup_s3_config]}${C_RESET}" center
    print_box_bottom
    echo ""
    
    echo -e "  ${C_MUTED}${L[cloud_provider]}: ${C_INFO}$(get_provider_name "$CLOUD_PROVIDER")${C_RESET}"
    echo ""
    
    if [[ "$CLOUD_PROVIDER" == "cloudflare" ]]; then
        input_field "${L[account_id]}" "" CF_ACCOUNT_ID
        S3_ENDPOINT="${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
    fi
    
    input_field "${L[access_key]}" "" S3_ACCESS_KEY false "access_key_hint"
    input_field "${L[secret_key]}" "" S3_SECRET_KEY true "secret_key_hint"
    input_field "${L[bucket]}" "" S3_BUCKET false "bucket_hint"
    
    if [[ "$CLOUD_PROVIDER" != "cloudflare" ]]; then
        input_field "${L[endpoint]}" "$S3_ENDPOINT" S3_ENDPOINT false "endpoint_hint"
    fi
    
    input_field "${L[region]}" "$S3_REGION" S3_REGION false "region_hint"
    
    echo ""
    input_field "${L[task_name]}" "$setup_task_name" setup_task_name false
    task_set_scalar "$setup_task_id" NAME "$setup_task_name"
    ACTIVE_TASK_ID="$setup_task_id"
    DEFAULT_TASK_ID="${DEFAULT_TASK_ID:-$setup_task_id}"
    
    clear
    echo ""
    print_box_top
    print_box_line "${C_TITLE}${L[setup_backup_dirs]}${C_RESET}" center
    print_box_bottom
    echo ""
    
    echo -e "  ${C_HINT}${L[dir_path_hint]}${C_RESET}"
    echo -e "  ${C_MUTED}${L[empty_line_finish]}${C_RESET}"
    echo ""
    
    BACKUP_DIRS=()
    while true; do
        echo -ne "  ${C_PRIMARY}${L[enter_dir_path]}${C_RESET}: ${C_INPUT}"
        read -e -r dir_path
        echo -ne "${C_RESET}"
        
        [[ -z "$dir_path" ]] && break

        # 安全展开 ~ 和环境变量
        dir_path="${dir_path//\~/$HOME}"
        while [[ "$dir_path" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*)\} ]]; do
            local ename="${BASH_REMATCH[1]}"
            dir_path="${dir_path//\$\{${ename}\}/${!ename}}"
        done
        while [[ "$dir_path" =~ \$([a-zA-Z_][a-zA-Z0-9_]*) ]]; do
            local ename="${BASH_REMATCH[1]}"
            dir_path="${dir_path//\$${ename}/${!ename}}"
        done
        
        if [[ -d "$dir_path" ]]; then
            BACKUP_DIRS+=("$dir_path")
            local sz=$(fmt_size $(get_dir_size "$dir_path"))
            echo -e "    ${C_SUCCESS}✓${C_RESET} ${L[dir_added]} ${C_MUTED}($sz)${C_RESET}"
        else
            if confirm "${L[dir_not_exist_add]}" "n"; then
                BACKUP_DIRS+=("$dir_path")
            fi
        fi
    done
    
    if [[ ${#BACKUP_DIRS[@]} -eq 0 ]]; then
        error "${L[need_at_least_one_dir]}"
        return 1
    fi
    
    clear
    echo ""
    print_box_top
    print_box_line "${C_TITLE}${L[setup_options]}${C_RESET}" center
    print_box_bottom
    echo ""
    
    input_field "${L[prefix]}" "$BACKUP_PREFIX" BACKUP_PREFIX false "prefix_hint"
    
    if confirm "${L[enable_compression]}" "y"; then
        COMPRESS_BACKUP=true
        input_field "${L[compression_level]} (1-9)" "6" COMPRESSION_LEVEL
    else
        COMPRESS_BACKUP=false
    fi
    
    echo ""
    if confirm "${L[enable_sqlite_safe]}" "y"; then
        SQLITE_SAFE_BACKUP=true
    else
        SQLITE_SAFE_BACKUP=false
    fi
    
    echo ""
    input_field "${L[max_backups]} (${L[max_backups_desc]})" "7" MAX_BACKUPS
    
    clear
    echo ""
    print_box_top
    print_box_line "${C_TITLE}${L[setup_complete]}${C_RESET}" center
    print_box_bottom
    echo ""
    
    show_kv "${L[cloud_provider]}" "$(get_provider_name "$CLOUD_PROVIDER")" "$C_INFO"
    show_kv "${L[bucket]}" "$S3_BUCKET" "$C_INFO"
    show_kv "${L[endpoint]}" "$S3_ENDPOINT"
    show_kv "${L[task_name]}" "$setup_task_name" "$C_INFO"
    show_kv "${L[backup_directories]}" "${#BACKUP_DIRS[@]}"
    show_kv "${L[prefix]}" "${BACKUP_PREFIX:-${L[root_directory]}}"
    show_kv "${L[compression]}" "$COMPRESS_BACKUP"
    show_kv "${L[sqlite_safe]}" "$SQLITE_SAFE_BACKUP"
    echo ""
    
    if confirm "${L[save_config_confirm]}" "y"; then
        save_current_task_context "$setup_task_id"
        save_config
        success "${L[config_saved]} ${C_PATH}${CONFIG_FILE}${C_RESET}"
        echo ""
        
        if confirm "${L[test_connection_now]}" "y"; then
            check_s3_tool || {
                if confirm "${L[err_install_s3cmd]}"; then
                    install_s3cmd
                fi
            }
            check_s3_tool && {
                setup_s3_tool
                s3_test
            }
        fi
        return 0
    else
        warn "${L[config_not_saved]}"
        return 1
    fi
}

# ============================================================================
# 交互菜单 - 美化首页
# ============================================================================

show_logo() {
    echo -e "${C_LOGO1}"
    cat << 'EOF'
       ★       ★
    ██╗   ██╗██████╗  █████╗  ██████╗██╗  ██╗
    ██║   ██║██╔══██╗██╔══██╗██╔════╝██║ ██╔╝
    ██║   ██║██████╔╝███████║██║     █████╔╝
    ╚██╗ ██╔╝██╔══██╗██╔══██║██║     ██╔═██╗
     ╚████╔╝ ██████╔╝██║  ██║╚██████╗██║  ██╗
      ╚═══╝  ╚═════╝ ╚═╝  ╚═╝ ╚═════╝╚═╝  ╚═╝
       ★       ★
EOF
    echo -e "${C_RESET}"
}

show_header() {
    clear
    echo ""
    
    # Logo
    show_logo
    
    # Slogan & Version
    echo -e "       ${C_SLOGAN}${L[slogan]}${C_RESET}  ${C_MUTED}v${VERSION}${C_RESET}"
    echo ""
    
    # Tagline
    echo -e "    ${C_HINT}${L[tagline]}${C_RESET}"
    
    # GitHub Link - 使用更醒目的颜色
    echo -e "    ${C_LINK}🔗 ${GITHUB_URL}${C_RESET}"
    echo ""
}

show_status_bar() {
    local cron_status=$([[ ${#SCHEDULE_IDS[@]} -gt 0 && -n "$(get_cron_status)" ]] && echo "on" || echo "off")
    local provider_name=$(get_provider_name "$CLOUD_PROVIDER")
    local active_task_id="$(resolve_default_task_id)"
    local active_task_label="${L[not_set]}"
    [[ -n "$active_task_id" ]] && task_exists "$active_task_id" && active_task_label="$(task_display_name "$active_task_id")"
    
    print_box_top
    
    if [[ -n "$S3_BUCKET" ]]; then
        print_box_line "${C_MUTED}☁${C_RESET}  ${C_INFO}${provider_name:-Cloud}${C_RESET} › ${C_PRIMARY}${S3_BUCKET}${C_RESET}"
    else
        print_box_line "${C_MUTED}☁${C_RESET}  ${C_WARNING}${L[not_set]}${C_RESET}"
    fi
    
    if [[ -n "$active_task_id" ]] && task_exists "$active_task_id"; then
        print_box_line "${C_MUTED}◆${C_RESET}  ${L[current_task]} ${C_PRIMARY}${active_task_label}${C_RESET} ${C_MUTED}(${L[prefix]}: $(task_prefix_display "$active_task_id"), $(task_schedule_count "$active_task_id") ${L[scheduled_backup]})${C_RESET}"
    else
        print_box_line "${C_MUTED}◆${C_RESET}  ${L[current_task]} ${C_WARNING}${L[not_set]}${C_RESET}"
    fi
    
    local status_line=""
    status_line+="$(status_badge $cron_status "${L[scheduled_backup]} ${#SCHEDULE_IDS[@]}")  "
    status_line+="$(status_badge $COMPRESS_BACKUP "${L[compression]}")  "
    status_line+="$(status_badge $SQLITE_SAFE_BACKUP "SQLite")"
    print_box_line "$status_line"
    
    print_box_bottom
    echo ""
}

menu_main() {
    while true; do
        show_header
        show_status_bar
        
        echo -e "  ${C_BOLD}${L[select_option]}${C_RESET}"
        
        menu_group "${L[menu_backup]}"
        menu_item "1" "${L[menu_backup]}" "${L[menu_backup_desc]}"
        menu_item "2" "${L[menu_list]}" "${L[menu_list_desc]}"
        menu_item "3" "${L[menu_test]}" "${L[menu_test_desc]}"
        
        menu_group "${L[menu_config]}"
        menu_item "4" "${L[menu_cron]}" "${L[menu_cron_desc]}"
        menu_item "5" "${L[menu_config]}" "${L[menu_config_desc]}"
        menu_item "6" "${L[menu_logs]}" "${L[menu_logs_desc]}"
        
        menu_group "${L[menu_exit]}"
        menu_item "r" "${L[menu_reconfig]}" "${L[menu_reconfig_desc]}"
        menu_item "l" "${L[menu_lang]}" "${L[menu_lang_desc]}"
        menu_item "u" "${L[menu_update]}" "${L[menu_update_desc]}"
        menu_item "x" "${L[menu_reset]}" "${L[menu_reset_desc]}"
        menu_item "0" "${L[menu_exit]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[0-6/r/l/u/x]${C_RESET}: "
        read -r choice
        
        case $choice in
            1) menu_backup ;;
            2) menu_list_backups ;;
            3) menu_test ;;
            4) menu_cron ;;
            5) menu_edit_config ;;
            6) menu_logs ;;
            r|R) setup_wizard; load_config ;;
            l|L) select_language_dialog; init_providers ;;
            u|U) menu_update ;;
            x|X) menu_reset ;;
            0|q|Q) clear; echo -e "\n  ${C_SUCCESS}${L[goodbye]}${C_RESET}\n"; exit 0 ;;
        esac
    done
}

menu_backup() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[menu_backup]}${C_RESET}"
    echo ""
    
    local selected_task=""
    selected_task=$(prompt_task_selection "${L[select_backup_task]}" "$(resolve_default_task_id)") || { press_enter; return; }
    load_task_context "$selected_task"
    
    if ! validate_config "$selected_task"; then
        press_enter
        return
    fi
    
    show_kv "${L[task_name]}" "$(task_display_name "$selected_task")" "$C_INFO"
    show_kv "${L[prefix]}" "${BACKUP_PREFIX:-${L[root_directory]}}"
    echo ""
    
    echo -e "  ${L[will_backup_dirs]} ${C_NUMBER}${#BACKUP_DIRS[@]}${C_RESET}:"
    echo ""
    
    local total_size=0
    for d in "${BACKUP_DIRS[@]}"; do
        local sz=$(get_dir_size "$d")
        total_size=$((total_size + sz))
        local files=$(count_files "$d")
        local dbs=$(count_sqlite_dbs "$d")
        
        echo -e "    ${C_SUCCESS}•${C_RESET} ${C_PATH}$d${C_RESET}"
        echo -e "      ${C_MUTED}$(fmt_size $sz), ${files} ${L[files]}${C_RESET}$([[ $dbs -gt 0 ]] && echo " ${C_INFO}[${dbs} SQLite]${C_RESET}")"
    done
    
    echo ""
    echo -e "  ${L[total_size]}: ${C_NUMBER}$(fmt_size $total_size)${C_RESET}"
    echo ""
    
    if confirm "${L[confirm_backup]}"; then
        save_config
        do_backup
    else
        info "${L[operation_cancelled]}"
    fi
    
    press_enter
}

menu_list_backups() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[remote_backups]}${C_RESET}"
    echo ""
    
    local selected_task=""
    selected_task=$(prompt_task_selection "${L[select_backup_task]}" "$(resolve_default_task_id)") || { press_enter; return; }
    load_task_context "$selected_task"
    
    if ! validate_config "$selected_task"; then
        press_enter
        return
    fi
    
    check_s3_tool || { error "${L[err_no_s3_tool]}"; press_enter; return; }
    setup_s3_tool
    
    echo -e "  ${C_BOLD}$(task_display_name "$selected_task")${C_RESET} ${C_MUTED}(${BACKUP_PREFIX:-${L[root_directory]}})${C_RESET}"
    echo ""
    
    for d in "${BACKUP_DIRS[@]}"; do
        local name=$(basename "$d")
        echo -e "  ${C_BOLD}$name${C_RESET}"
        
        local list=$(s3_list "${name}/")
        if [[ -n "$list" ]]; then
            echo "$list" | while read -r line; do
                local dt=$(echo "$line" | awk '{print $1, $2}')
                local sz=$(echo "$line" | awk '{print $3}')
                local fn=$(echo "$line" | awk '{print $4}' | xargs basename 2>/dev/null)
                [[ -n "$fn" ]] && printf "    ${C_TIMESTAMP}%-16s${C_RESET}  ${C_NUMBER}%10s${C_RESET}  ${C_PATH}%s${C_RESET}\n" "$dt" "$sz" "$fn"
            done
        else
            echo -e "    ${C_MUTED}(${L[no_backups_yet]})${C_RESET}"
        fi
        echo ""
    done
    
    press_enter
}

menu_test() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[connection_test]}${C_RESET}"
    echo ""
    
    if ! validate_config; then
        press_enter
        return
    fi
    
    check_s3_tool || { error "${L[err_no_s3_tool]}"; press_enter; return; }
    setup_s3_tool
    
    echo -e "  ${C_BOLD}${L[s3_settings]}${C_RESET}"
    show_kv "${L[cloud_provider]}" "$(get_provider_name "$CLOUD_PROVIDER")" "$C_INFO"
    show_kv "${L[endpoint]}" "$S3_ENDPOINT"
    show_kv "${L[bucket]}" "$S3_BUCKET" "$C_INFO"
    echo ""
    
    s3_test
    
    echo ""
    echo -e "  ${C_BOLD}${L[dependency_check]}${C_RESET}"
    for cmd in sqlite3 rsync gzip tar s3cmd aws; do
        if command -v $cmd &>/dev/null; then
            echo -e "    $(status_badge ok "$cmd")"
        else
            echo -e "    $(status_badge off "$cmd ${C_MUTED}(${L[not_installed]})${C_RESET}")"
        fi
    done
    
    press_enter
}

edit_task_menu() {
    local task_id="$1"
    
    while true; do
        load_task_context "$task_id"
        show_header
        echo -e "  ${C_TITLE}▸ ${L[backup_tasks]}${C_RESET}"
        echo ""
        
        show_kv "${L[task_name]}" "$(task_display_name "$task_id")" "$C_INFO"
        show_kv "${L[prefix]}" "${BACKUP_PREFIX:-${L[root_directory]}}"
        show_kv "${L[backup_directories]}" "${#BACKUP_DIRS[@]}"
        show_kv "${L[scheduled_backup]}" "$(task_schedule_count "$task_id")"
        show_kv "${L[compression]}" "$COMPRESS_BACKUP (${L[compression_level]} $COMPRESSION_LEVEL)"
        show_kv "${L[sqlite_safe]}" "$SQLITE_SAFE_BACKUP"
        show_kv "${L[max_backups]}" "$MAX_BACKUPS"
        show_kv "${L[default_task]}" "$([[ "$DEFAULT_TASK_ID" == "$task_id" ]] && echo "${L[yes]}" || echo "${L[no]}")"
        
        echo ""
        print_line '─'
        menu_item "1" "${L[task_name]}"
        menu_item "2" "${L[backup_directories]}"
        menu_item "3" "${L[backup_settings]}"
        menu_item "4" "${L[exclude_patterns]}"
        menu_item "5" "${L[set_default_task]}"
        menu_item "s" "${L[save]}"
        menu_item "0" "${L[back]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[0-5/s]${C_RESET}: "
        local choice new_task_name
        read -r choice
        
        case $choice in
            1)
                new_task_name="$(task_display_name "$task_id")"
                input_field "${L[task_name]}" "$new_task_name" new_task_name false
                task_set_scalar "$task_id" NAME "$new_task_name"
                ;;
            2) edit_backup_dirs ;;
            3) edit_backup_options ;;
            4) edit_exclude_patterns ;;
            5)
                DEFAULT_TASK_ID="$task_id"
                ACTIVE_TASK_ID="$task_id"
                save_current_task_context "$task_id"
                save_config
                success "${L[task_set_default]}"
                press_enter
                ;;
            s|S)
                ACTIVE_TASK_ID="$task_id"
                save_current_task_context "$task_id"
                save_config
                success "${L[task_saved]}"
                press_enter
                ;;
            0|"")
                save_current_task_context "$task_id"
                ACTIVE_TASK_ID="$task_id"
                return
                ;;
        esac
    done
}

menu_tasks() {
    while true; do
        show_header
        echo -e "  ${C_TITLE}▸ ${L[backup_tasks]}${C_RESET}"
        echo ""
        
        if [[ ${#TASK_IDS[@]} -eq 0 ]]; then
            echo -e "  ${C_MUTED}(${L[no_tasks]})${C_RESET}"
        else
            local i=1 task_id
            for task_id in "${TASK_IDS[@]}"; do
                local flags=""
                [[ "$task_id" == "$ACTIVE_TASK_ID" ]] && flags+=" ${L[current_task]}"
                [[ "$task_id" == "$DEFAULT_TASK_ID" ]] && flags+=" ${L[default_task]}"
                printf "    ${C_MENU_NUM}%d${C_RESET}) %s${C_MUTED}%s${C_RESET}\n" "$i" "$(task_display_name "$task_id")" "${flags:+ [$flags]}"
                printf "       ${C_MUTED}%s: %s | %s: %s | %s: %s${C_RESET}\n" \
                    "${L[prefix]}" "$(task_prefix_display "$task_id")" \
                    "${L[backup_directories]}" "$(task_dir_count "$task_id")" \
                    "${L[scheduled_backup]}" "$(task_schedule_count "$task_id")"
                ((i++))
            done
        fi
        
        echo ""
        print_line '─'
        menu_item "1-${#TASK_IDS[@]}" "${L[edit_task]}"
        menu_item "a" "${L[add_task]}"
        menu_item "d" "${L[delete_task]}"
        menu_item "0" "${L[back]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[1-${#TASK_IDS[@]}/a/d/0]${C_RESET}: "
        local choice new_task_name delete_idx delete_task_id
        read -r choice
        
        case $choice in
            a|A)
                new_task_name="$(default_task_name)"
                input_field "${L[task_name]}" "$new_task_name" new_task_name false
                local new_task_id
                new_task_id="$(create_task "$new_task_name")"
                ACTIVE_TASK_ID="$new_task_id"
                load_task_context "$new_task_id"
                save_config
                success "${L[task_saved]}"
                press_enter
                ;;
            d|D)
                if [[ ${#TASK_IDS[@]} -le 1 ]]; then
                    warn "${L[need_keep_one_task]}"
                    press_enter
                    continue
                fi
                echo ""
                echo -ne "  ${C_PRIMARY}#${C_RESET}: "
                read -r delete_idx
                if [[ "$delete_idx" =~ ^[0-9]+$ ]] && [[ $delete_idx -ge 1 ]] && [[ $delete_idx -le ${#TASK_IDS[@]} ]]; then
                    delete_task_id="${TASK_IDS[$((delete_idx-1))]}"
                    if confirm "${L[confirm_delete_task]} $(task_display_name "$delete_task_id")"; then
                        delete_task "$delete_task_id"
                        sync_cron_jobs
                        save_config
                        [[ -n "$ACTIVE_TASK_ID" ]] && load_task_context "$ACTIVE_TASK_ID"
                        success "${L[task_deleted]}"
                    fi
                fi
                press_enter
                ;;
            0|"") return ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#TASK_IDS[@]} ]]; then
                    ACTIVE_TASK_ID="${TASK_IDS[$((choice-1))]}"
                    edit_task_menu "$ACTIVE_TASK_ID"
                fi
                ;;
        esac
    done
}

edit_schedule_form() {
    local schedule_id="$1"
    local schedule_name="" task_id="" cron_expr="$SCHEDULE_CRON"
    
    if [[ -n "$schedule_id" ]] && schedule_exists "$schedule_id"; then
        schedule_name="$(schedule_display_name "$schedule_id")"
        task_id="$(schedule_get_scalar "$schedule_id" TASK)"
        cron_expr="$(schedule_get_scalar "$schedule_id" CRON)"
    fi
    
    show_header
    echo -e "  ${C_TITLE}▸ ${L[scheduled_backup]}${C_RESET}"
    echo ""
    
    local selected_task=""
    selected_task=$(prompt_task_selection "${L[schedule_task]}" "${task_id:-$(resolve_default_task_id)}") || return 1
    task_id="$selected_task"
    
    echo ""
    input_field "${L[schedule_name]}" "$schedule_name" schedule_name false
    echo ""
    echo -e "  ${C_MUTED}${L[cron_examples]}:${C_RESET}"
    echo -e "    ${C_MUTED}0 3 * * *${C_RESET}   ${L[cron_daily]}"
    echo -e "    ${C_MUTED}0 */6 * * *${C_RESET} ${L[cron_6hours]}"
    echo -e "    ${C_MUTED}0 0 * * 0${C_RESET}   ${L[cron_weekly]}"
    echo ""
    input_field "${L[cron_expression]}" "$cron_expr" cron_expr false
    
    [[ -z "$schedule_name" ]] && schedule_name="$(task_display_name "$task_id")"
    
    if [[ -n "$schedule_id" ]] && schedule_exists "$schedule_id"; then
        schedule_set_scalar "$schedule_id" NAME "$schedule_name"
        schedule_set_scalar "$schedule_id" TASK "$task_id"
        schedule_set_scalar "$schedule_id" CRON "$cron_expr"
    else
        create_schedule "$schedule_name" "$task_id" "$cron_expr" >/dev/null
    fi
    
    sync_cron_jobs
    save_config
    success "${L[schedule_saved]}"
    press_enter
    return 0
}

menu_cron() {
    while true; do
        show_header
        echo -e "  ${C_TITLE}▸ ${L[scheduled_backup]}${C_RESET}"
        echo ""
        
        if [[ ${#SCHEDULE_IDS[@]} -eq 0 ]]; then
            echo -e "  ${C_MUTED}(${L[no_schedules]})${C_RESET}"
        else
            local i=1 schedule_id
            for schedule_id in "${SCHEDULE_IDS[@]}"; do
                local task_id schedule_state schedule_label
                task_id="$(schedule_get_scalar "$schedule_id" TASK)"
                if schedule_installed "$schedule_id"; then
                    schedule_state="ok"
                    schedule_label="${L[cron_enabled]}"
                else
                    schedule_state="off"
                    schedule_label="${L[cron_disabled]}"
                fi
                printf "    ${C_MENU_NUM}%d${C_RESET}) %s %s\n" \
                    "$i" "$(schedule_display_name "$schedule_id")" \
                    "$(status_badge "$schedule_state" "$schedule_label")"
                printf "       ${C_MUTED}%s: %s | %s${C_RESET}\n" "${L[schedule_task]}" "$(task_display_name "$task_id")" "$(schedule_get_scalar "$schedule_id" CRON)"
                ((i++))
            done
        fi
        
        local cron_job
        cron_job="$(get_cron_status)"
        if [[ -n "$cron_job" ]]; then
            echo ""
            echo -e "  ${L[cron_status]}: $(status_badge ok "${L[cron_enabled]}")"
            echo "$cron_job" | sed 's/^/    /'
        else
            echo ""
            echo -e "  ${L[cron_status]}: $(status_badge off "${L[cron_disabled]}")"
        fi
        
        echo ""
        print_line '─'
        
        menu_item "1-${#SCHEDULE_IDS[@]}" "${L[edit_schedule]}"
        menu_item "a" "${L[add_schedule]}"
        menu_item "d" "${L[delete_schedule]}"
        menu_item "s" "${L[sync_schedules]}"
        menu_item "2" "${L[disable_cron]}"
        menu_item "0" "${L[back]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[1-${#SCHEDULE_IDS[@]}/a/d/s/2/0]${C_RESET}: "
        local choice del_idx del_schedule_id
        read -r choice
        
        case $choice in
            a|A) edit_schedule_form "" ;;
            d|D)
                if [[ ${#SCHEDULE_IDS[@]} -eq 0 ]]; then
                    press_enter
                    continue
                fi
                echo ""
                echo -ne "  ${C_PRIMARY}#${C_RESET}: "
                read -r del_idx
                if [[ "$del_idx" =~ ^[0-9]+$ ]] && [[ $del_idx -ge 1 ]] && [[ $del_idx -le ${#SCHEDULE_IDS[@]} ]]; then
                    del_schedule_id="${SCHEDULE_IDS[$((del_idx-1))]}"
                    if confirm "${L[confirm_delete_schedule]} $(schedule_display_name "$del_schedule_id")"; then
                        delete_schedule "$del_schedule_id"
                        sync_cron_jobs
                        save_config
                        success "${L[schedule_deleted]}"
                    fi
                fi
                press_enter
                ;;
            s|S)
                sync_cron_jobs
                save_config
                success "${L[cron_installed]}"
                press_enter
                ;;
            2)
                if confirm "${L[confirm_disable]}"; then
                    remove_cron
                fi
                press_enter
                ;;
            0|"") return ;;
            *)
                if [[ "$choice" =~ ^[0-9]+$ ]] && [[ $choice -ge 1 ]] && [[ $choice -le ${#SCHEDULE_IDS[@]} ]]; then
                    edit_schedule_form "${SCHEDULE_IDS[$((choice-1))]}"
                fi
                ;;
        esac
    done
}

menu_edit_config() {
    while true; do
        local config_task_id="$(resolve_default_task_id)"
        local config_task_label="${L[not_set]}"
        [[ -n "$config_task_id" ]] && task_exists "$config_task_id" && config_task_label="$(task_display_name "$config_task_id")"
        
        show_header
        echo -e "  ${C_TITLE}▸ ${L[edit_config]}${C_RESET}"
        echo ""
        
        echo -e "  ${C_BOLD}${L[current_config]}${C_RESET}"
        show_kv "${L[cloud_provider]}" "$(get_provider_name "$CLOUD_PROVIDER")" "$C_INFO"
        show_kv "${L[bucket]}" "$S3_BUCKET" "$C_INFO"
        show_kv "${L[current_task]}" "$config_task_label" "$C_INFO"
        show_kv "${L[backup_tasks]}" "${#TASK_IDS[@]}"
        show_kv "${L[scheduled_backup]}" "${#SCHEDULE_IDS[@]}"
        
        echo ""
        print_line '─'
        
        menu_item "1" "${L[s3_settings]}"
        menu_item "2" "${L[backup_tasks]}"
        menu_item "s" "${L[save]}"
        menu_item "0" "${L[back]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[0-2/s]${C_RESET}: "
        read -r choice
        
        case $choice in
            1) edit_s3_config ;;
            2) menu_tasks ;;
            s|S) save_config; success "${L[config_saved]} ${CONFIG_FILE}"; press_enter ;;
            0|"") return ;;
        esac
    done
}

edit_s3_config() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[s3_settings]}${C_RESET}"
    echo ""
    
    init_providers
    select_provider
    
    if [[ "$CLOUD_PROVIDER" == "cloudflare" ]]; then
        input_field "${L[account_id]}" "" CF_ACCOUNT_ID
        S3_ENDPOINT="${CF_ACCOUNT_ID}.r2.cloudflarestorage.com"
    fi
    
    input_field "${L[bucket]}" "$S3_BUCKET" S3_BUCKET false "bucket_hint"
    
    if [[ "$CLOUD_PROVIDER" != "cloudflare" ]]; then
        input_field "${L[endpoint]}" "$S3_ENDPOINT" S3_ENDPOINT false "endpoint_hint"
    fi
    
    input_field "${L[region]}" "$S3_REGION" S3_REGION false "region_hint"
    input_field "${L[access_key]}" "" S3_ACCESS_KEY true "access_key_hint"
    input_field "${L[secret_key]}" "" S3_SECRET_KEY true "secret_key_hint"
    
    success "${L[settings_updated]}"
    press_enter
}

edit_backup_dirs() {
    while true; do
        show_header
        echo -e "  ${C_TITLE}▸ ${L[backup_directories]}${C_RESET}"
        echo ""
        
        if [[ ${#BACKUP_DIRS[@]} -eq 0 ]]; then
            echo -e "  ${C_MUTED}(${L[none]})${C_RESET}"
        else
            for i in "${!BACKUP_DIRS[@]}"; do
                local d="${BACKUP_DIRS[$i]}"
                if [[ -d "$d" ]]; then
                    local sz=$(fmt_size $(get_dir_size "$d"))
                    echo -e "    ${C_MENU_NUM}$((i+1))${C_RESET}) ${C_PATH}$d${C_RESET} ${C_MUTED}($sz)${C_RESET}"
                else
                    echo -e "    ${C_MENU_NUM}$((i+1))${C_RESET}) ${C_PATH}$d${C_RESET} ${C_ERROR}(${L[not_exist]})${C_RESET}"
                fi
            done
        fi
        
        echo ""
        print_line '─'
        menu_item "a" "${L[add_directory]}"
        menu_item "d" "${L[remove_directory]}"
        menu_item "0" "${L[back]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[0/a/d]${C_RESET}: "
        read -r choice
        
        case $choice in
            a|A)
                echo ""
                echo -e "  ${C_HINT}${L[dir_path_hint]}${C_RESET}"
                echo -ne "  ${C_PRIMARY}${L[enter_dir_path]}${C_RESET}: ${C_INPUT}"
                read -e -r new_dir
                echo -ne "${C_RESET}"
                if [[ -n "$new_dir" ]]; then
                    # 安全展开 ~ 和环境变量
                    new_dir="${new_dir//\~/$HOME}"
                    while [[ "$new_dir" =~ \$\{([a-zA-Z_][a-zA-Z0-9_]*)\} ]]; do
                        local ename="${BASH_REMATCH[1]}"
                        new_dir="${new_dir//\$\{${ename}\}/${!ename}}"
                    done
                    while [[ "$new_dir" =~ \$([a-zA-Z_][a-zA-Z0-9_]*) ]]; do
                        local ename="${BASH_REMATCH[1]}"
                        new_dir="${new_dir//\$${ename}/${!ename}}"
                    done
                    BACKUP_DIRS+=("$new_dir")
                    if [[ -d "$new_dir" ]]; then
                        local sz=$(fmt_size $(get_dir_size "$new_dir"))
                        success "${L[dir_added]}: $new_dir ${C_MUTED}($sz)${C_RESET}"
                    else
                        warn "${L[dir_added]}: $new_dir ${C_WARNING}(${L[not_exist]})${C_RESET}"
                    fi
                fi
                ;;
            d|D)
                echo ""
                echo -ne "  ${C_PRIMARY}#${C_RESET}: "
                read -r del_idx
                if [[ "$del_idx" =~ ^[0-9]+$ ]] && [[ $del_idx -ge 1 ]] && [[ $del_idx -le ${#BACKUP_DIRS[@]} ]]; then
                    local removed="${BACKUP_DIRS[$((del_idx-1))]}"
                    unset 'BACKUP_DIRS[$((del_idx-1))]'
                    BACKUP_DIRS=("${BACKUP_DIRS[@]}")
                    success "Removed: $removed"
                fi
                ;;
            0|"") return ;;
        esac
    done
}

edit_backup_options() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[backup_settings]}${C_RESET}"
    echo ""
    
    input_field "${L[prefix]}" "$BACKUP_PREFIX" BACKUP_PREFIX false "prefix_hint"
    echo ""
    
    echo -e "  ${C_BOLD}${L[compression]}${C_RESET}"
    if confirm "${L[enable_compression]}" "$([[ "$COMPRESS_BACKUP" == "true" ]] && echo y || echo n)"; then
        COMPRESS_BACKUP=true
        input_field "${L[compression_level]} (1-9)" "$COMPRESSION_LEVEL" COMPRESSION_LEVEL
    else
        COMPRESS_BACKUP=false
    fi
    
    echo ""
    echo -e "  ${C_BOLD}SQLite${C_RESET}"
    if confirm "${L[enable_sqlite_safe]}" "$([[ "$SQLITE_SAFE_BACKUP" == "true" ]] && echo y || echo n)"; then
        SQLITE_SAFE_BACKUP=true
    else
        SQLITE_SAFE_BACKUP=false
    fi
    
    echo ""
    input_field "${L[max_backups]} (${L[max_backups_desc]})" "$MAX_BACKUPS" MAX_BACKUPS
    
    success "${L[settings_updated]}"
    press_enter
}

edit_exclude_patterns() {
    while true; do
        show_header
        echo -e "  ${C_TITLE}▸ ${L[exclude_patterns]}${C_RESET}"
        echo ""
        
        if [[ ${#EXCLUDE_PATTERNS[@]} -eq 0 ]]; then
            echo -e "  ${C_MUTED}(${L[none]})${C_RESET}"
        else
            for i in "${!EXCLUDE_PATTERNS[@]}"; do
                echo -e "    ${C_MENU_NUM}$((i+1))${C_RESET}) ${C_MUTED}${EXCLUDE_PATTERNS[$i]}${C_RESET}"
            done
        fi
        
        echo ""
        print_line '─'
        menu_item "a" "${L[add_pattern]}"
        menu_item "d" "${L[remove_pattern]}"
        menu_item "r" "${L[reset_default]}"
        menu_item "0" "${L[back]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[0/a/d/r]${C_RESET}: "
        read -r choice
        
        case $choice in
            a|A)
                echo ""
                echo -ne "  ${C_PRIMARY}${L[pattern_example]}${C_RESET}: ${C_INPUT}"
                read -r pattern
                echo -ne "${C_RESET}"
                [[ -n "$pattern" ]] && EXCLUDE_PATTERNS+=("$pattern")
                ;;
            d|D)
                echo ""
                echo -ne "  ${C_PRIMARY}#${C_RESET}: "
                read -r del_idx
                if [[ "$del_idx" =~ ^[0-9]+$ ]] && [[ $del_idx -ge 1 ]] && [[ $del_idx -le ${#EXCLUDE_PATTERNS[@]} ]]; then
                    unset 'EXCLUDE_PATTERNS[$((del_idx-1))]'
                    EXCLUDE_PATTERNS=("${EXCLUDE_PATTERNS[@]}")
                fi
                ;;
            r|R)
                EXCLUDE_PATTERNS=("${DEFAULT_EXCLUDE_PATTERNS[@]}")
                success "${L[success]}"
                ;;
            0|"") return ;;
        esac
    done
}

menu_logs() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[recent_logs]}${C_RESET}"
    echo -e "  ${C_MUTED}${LOG_FILE}${C_RESET}"
    echo ""
    print_line '─'
    
    if [[ -f "$LOG_FILE" ]]; then
        tail -20 "$LOG_FILE" | while IFS= read -r line; do
            if [[ "$line" =~ \[ERROR\] ]]; then
                echo -e "  ${C_ERROR}$line${C_RESET}"
            elif [[ "$line" =~ \[WARN\] ]]; then
                echo -e "  ${C_WARNING}$line${C_RESET}"
            elif [[ "$line" =~ ={5,} ]]; then
                echo -e "  ${C_PRIMARY}$line${C_RESET}"
            else
                echo "  $line"
            fi
        done
    else
        echo -e "  ${C_MUTED}(${L[no_logs]})${C_RESET}"
    fi
    
    print_line '─'
    echo -e "  ${C_MUTED}${L[tip_realtime_log]}: tail -f $LOG_FILE${C_RESET}"
    
    press_enter
}

menu_update() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[check_update]}${C_RESET}"
    echo ""
    
    do_update
    
    press_enter
}

menu_reset() {
    show_header
    
    do_reset
    
    if [[ $? -eq 0 ]]; then
        echo ""
        info "Restarting setup wizard..."
        sleep 2
        
        # 重新选择语言
        select_language_dialog
        init_providers
        
        # 运行配置向导
        setup_wizard
        load_config
    else
        press_enter
    fi
}

# ============================================================================
# 命令行接口
# ============================================================================

usage() {
    echo ""
    show_logo
    echo -e "  ${C_SLOGAN}${L[slogan]}${C_RESET} - ${L[tagline]}"
    echo -e "  ${C_LINK}${GITHUB_URL}${C_RESET}"
    echo ""
    
    cat << EOF
  ${C_BOLD}${L[cli_usage]}${C_RESET}
    $SCRIPT_NAME [command] [options]

  ${C_BOLD}${L[cli_commands]}${C_RESET}
    backup          ${L[cli_cmd_backup]}
    menu            ${L[cli_cmd_menu]}
    setup           ${L[cli_cmd_setup]}
    test            ${L[cli_cmd_test]}
    status          ${L[cli_cmd_status]}
    install-cron    ${L[cli_cmd_cron_install]}
    remove-cron     ${L[cli_cmd_cron_remove]}
    config          ${L[cli_cmd_config]}
    update          ${L[cli_cmd_update]}
    restore         ${L[cli_cmd_restore]}
    reset           ${L[cli_cmd_reset]}
    help            ${L[cli_cmd_help]}

  ${C_BOLD}${L[cli_options]}${C_RESET}
    -v, --verbose       ${L[cli_opt_verbose]}
    -c, --config FILE   ${L[cli_opt_config]}
    --lang LANG         ${L[cli_opt_lang]}
    --task NAME         ${L[cli_opt_task]}
    --task-id ID        ${L[cli_opt_task_id]}
    --scheduled         ${L[cli_opt_scheduled]}
    --schedule-id ID    ${L[cli_opt_schedule_id]}
    --cron EXPR         ${L[cli_opt_cron]}
    --schedule-name N   ${L[cli_opt_schedule_name]}

  ${C_BOLD}${L[cli_examples]}${C_RESET}
    $SCRIPT_NAME                    # ${L[cli_cmd_menu]}
    $SCRIPT_NAME backup             # ${L[cli_cmd_backup]}
    $SCRIPT_NAME backup --task default
    $SCRIPT_NAME setup              # ${L[cli_cmd_setup]}
    $SCRIPT_NAME install-cron --task default --cron "0 */6 * * *"
    $SCRIPT_NAME update             # ${L[cli_cmd_update]}
    $SCRIPT_NAME --lang zh menu     # 中文菜单

  ${C_BOLD}${L[cli_config_file]}${C_RESET}
    $CONFIG_FILE

  ${C_BOLD}${L[cli_log_file]}${C_RESET}
    $LOG_FILE

EOF
}

show_config_cli() {
    echo ""
    show_logo
    echo -e "  ${C_BOLD}${L[current_config]}${C_RESET}"
    echo ""
    echo -e "  ${C_MUTED}${L[cli_config_file]}:${C_RESET} $CONFIG_FILE"
    echo ""
    
    show_kv "${L[cloud_provider]}" "$(get_provider_name "$CLOUD_PROVIDER")" "$C_INFO"
    show_kv "${L[bucket]}" "${S3_BUCKET:-${L[not_set]}}" "$C_INFO"
    show_kv "${L[endpoint]}" "$S3_ENDPOINT"
    show_kv "${L[region]}" "$S3_REGION"
    show_kv "${L[backup_tasks]}" "${#TASK_IDS[@]}"
    show_kv "${L[scheduled_backup]}" "${#SCHEDULE_IDS[@]}"
    echo ""
    
    echo -e "  ${C_BOLD}${L[backup_tasks]}${C_RESET}"
    local task_id
    for task_id in "${TASK_IDS[@]}"; do
        local -a task_dirs=()
        task_get_array "$task_id" DIRS task_dirs
        show_kv "${L[task_name]}" "$(task_display_name "$task_id")" "$C_INFO"
        show_kv "${L[prefix]}" "$(task_prefix_display "$task_id")"
        show_kv "${L[backup_directories]}" "${#task_dirs[@]}"
        show_kv "${L[max_backups]}" "$(task_get_scalar "$task_id" MAX_BACKUPS)"
        show_kv "${L[compression]}" "$(task_get_scalar "$task_id" COMPRESS) (${L[compression_level]} $(task_get_scalar "$task_id" COMPRESSION_LEVEL))"
        show_kv "${L[sqlite_safe]}" "$(task_get_scalar "$task_id" SQLITE_SAFE)"
        echo -e "    ${C_MUTED}${L[scheduled_backup]}: $(task_schedule_count "$task_id")${C_RESET}"
        local d
        for d in "${task_dirs[@]}"; do
            if [[ -d "$d" ]]; then
                echo -e "      ${C_SUCCESS}✓${C_RESET} $d"
            else
                echo -e "      ${C_ERROR}✗${C_RESET} $d ${C_ERROR}(${L[not_exist]})${C_RESET}"
            fi
        done
        echo ""
    done
    
    echo -e "  ${C_BOLD}${L[scheduled_backup]}${C_RESET}"
    if [[ ${#SCHEDULE_IDS[@]} -eq 0 ]]; then
        echo -e "    ${C_MUTED}(${L[no_schedules]})${C_RESET}"
    else
        local schedule_id
        for schedule_id in "${SCHEDULE_IDS[@]}"; do
            echo -e "    ${C_INFO}•${C_RESET} $(schedule_display_name "$schedule_id") ${C_MUTED}[$(task_display_name "$(schedule_get_scalar "$schedule_id" TASK)")]${C_RESET}"
            echo -e "      ${C_MUTED}$(schedule_get_scalar "$schedule_id" CRON)${C_RESET}"
        done
    fi
    echo ""
}

main() {
    local COMMAND=""
    local ARG_LANG=""
    local -a POSITIONAL=()
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) VERBOSE=true ;;
            -c|--config) shift; CONFIG_FILE="$1" ;;
            --lang) shift; ARG_LANG="$1" ;;
            --task) shift; CLI_TASK_REF="$1" ;;
            --task-id) shift; CLI_TASK_ID="$1" ;;
            --scheduled) CLI_SCHEDULED=true ;;
            --schedule-id) shift; CLI_SCHEDULE_ID="$1" ;;
            --cron) shift; CLI_CRON_EXPR="$1" ;;
            --schedule-name) shift; CLI_SCHEDULE_NAME="$1" ;;
            -h|--help|help) COMMAND="help" ;;
            -*) error "Unknown option: $1"; exit 1 ;;
            *)
                if [[ -z "$COMMAND" ]]; then
                    COMMAND="$1"
                else
                    POSITIONAL+=("$1")
                fi
                ;;
        esac
        shift
    done
    
    setup_colors
    init_data_dir
    init_temp_dir
    
    if [[ -n "$ARG_LANG" ]]; then
        set_language "$ARG_LANG"
    elif ! load_saved_language; then
        if [[ -t 0 ]] && [[ "${COMMAND:-menu}" == "menu" || "${COMMAND:-menu}" == "setup" ]]; then
            select_language_dialog
        else
            set_language "en"
        fi
    fi
    
    init_providers
    load_config
    
    if [[ -n "$CLI_TASK_REF" && -z "$CLI_TASK_ID" ]]; then
        CLI_TASK_ID="$(resolve_task_ref "$CLI_TASK_REF")"
        if [[ -z "$CLI_TASK_ID" ]]; then
            error "${L[invalid_option]}: ${CLI_TASK_REF}"
            exit 1
        fi
    fi
    
    [[ -z "$CLI_TASK_ID" ]] && CLI_TASK_ID="$(resolve_default_task_id)"
    if [[ -n "$CLI_TASK_ID" ]] && ! task_exists "$CLI_TASK_ID"; then
        error "${L[invalid_option]}: ${CLI_TASK_ID}"
        exit 1
    fi
    
    if [[ -n "$CLI_TASK_ID" ]] && task_exists "$CLI_TASK_ID"; then
        load_task_context "$CLI_TASK_ID"
    fi
    
    check_dependencies || exit 1
    
    if ! check_s3_tool; then
        if [[ -t 0 ]] && confirm "${L[err_no_s3_tool]}. ${L[err_install_s3cmd]}"; then
            install_s3cmd || exit 1
            check_s3_tool
        fi
    fi
    
    RUN_CONTEXT=$([[ "$CLI_SCHEDULED" == "true" ]] && echo "scheduled" || echo "cli")
    [[ "${COMMAND:-menu}" == "menu" || "${COMMAND:-menu}" == "setup" ]] && RUN_CONTEXT="interactive"
    
    log_info "vback started version=$VERSION cmd=${COMMAND:-menu} lang=$CURRENT_LANG task=${CLI_TASK_ID:-none} scheduled=${CLI_SCHEDULED}"
    
    case "${COMMAND:-menu}" in
        backup)
            if needs_setup; then
                error "${L[run_setup_first]}"
                exit 1
            fi
            validate_config "$CLI_TASK_ID" || exit 1
            do_backup
            ;;
        menu)
            if needs_setup; then
                setup_wizard
                load_config
            fi
            RUN_CONTEXT="interactive"
            menu_main
            ;;
        setup)
            RUN_CONTEXT="interactive"
            setup_wizard
            ;;
        test)
            validate_config "$CLI_TASK_ID" || exit 1
            setup_s3_tool
            s3_test
            ;;
        status)
            validate_config "$CLI_TASK_ID" || exit 1
            setup_s3_tool
            echo -e "${C_BOLD}$(task_display_name "$CLI_TASK_ID")${C_RESET} ${C_MUTED}(${BACKUP_PREFIX:-${L[root_directory]}})${C_RESET}"
            echo ""
            for d in "${BACKUP_DIRS[@]}"; do
                echo -e "${C_BOLD}$(basename "$d")${C_RESET}:"
                s3_list "$(basename "$d")/" | sed 's/^/  /'
                echo ""
            done
            ;;
        install-cron)
            validate_config "$CLI_TASK_ID" || exit 1
            if [[ -n "$CLI_CRON_EXPR" || -n "$CLI_SCHEDULE_NAME" || -n "$CLI_SCHEDULE_ID" || ${#SCHEDULE_IDS[@]} -eq 0 ]]; then
                install_cron "$CLI_TASK_ID" "${CLI_CRON_EXPR:-${SCHEDULE_CRON:-0 3 * * *}}" "$CLI_SCHEDULE_NAME" "$CLI_SCHEDULE_ID"
            else
                install_cron
            fi
            ;;
        remove-cron)
            remove_cron
            ;;
        config)
            show_config_cli
            ;;
        update)
            do_update
            ;;
        restore)
            if needs_setup; then
                error "${L[run_setup_first]}"
                exit 1
            fi
            validate_config "$CLI_TASK_ID" || exit 1
            setup_s3_tool
            menu_restore
            ;;
        reset)
            do_reset
            ;;
        help)
            usage
            ;;
        *)
            error "${L[invalid_option]}: $COMMAND"
            usage
            exit 1
            ;;
    esac
}

main "$@"
