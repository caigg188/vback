#!/bin/bash
# ============================================================================
# vback - 优雅的服务器备份工具 v1.1.0
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


VERSION="1.1.0"
SCRIPT_NAME=$(basename "$0")
SCRIPT_PATH=$(readlink -f "$0" 2>/dev/null || realpath "$0" 2>/dev/null || echo "$0")

# ========================= 数据目录 =========================
DATA_DIR="${VBACK_DATA_DIR:-$HOME/.vback}"
CONFIG_FILE="${DATA_DIR}/config"
LANG_FILE="${DATA_DIR}/language"
LOG_DIR="${DATA_DIR}/logs"
LOG_FILE="${LOG_DIR}/vback.log"

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
EXCLUDE_PATTERNS=(
    "*.log" "*.tmp" "node_modules" ".git"
    "__pycache__" "*.pyc" ".DS_Store" "Thumbs.db"
)

# 运行时变量
LOCK_FILE="/tmp/vback.lock"
TEMP_DIR="/tmp/vback-$$"
S3CMD_CFG="/tmp/.s3cfg-vback-$$"
VERBOSE="${VERBOSE:-false}"
LOG_LEVEL="${LOG_LEVEL:-INFO}"
LOG_MAX_SIZE=10485760
LOG_BACKUP_COUNT=5
CURRENT_LANG="en"

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
    L[cli_cmd_help]="Show help"
    L[cli_opt_verbose]="Verbose output"
    L[cli_opt_config]="Config file path"
    L[cli_opt_lang]="Language (en/zh)"
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
    L[cli_cmd_help]="显示帮助"
    L[cli_opt_verbose]="详细输出"
    L[cli_opt_config]="配置文件路径"
    L[cli_opt_lang]="语言 (en/zh)"
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
            C_LOGO1='\033[38;5;39m'   # 蓝色
            C_LOGO2='\033[38;5;38m'   # 青蓝
            C_LOGO3='\033[38;5;44m'   # 青色
            C_SLOGAN='\033[38;5;249m' # 浅灰
        else
            C_RESET='\033[0m'
            C_BOLD='\033[1m'
            C_DIM='\033[2m'
            C_ITALIC='\033[3m'
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
            C_SLOGAN='\033[37m'
        fi
    else
        C_RESET='' C_BOLD='' C_DIM='' C_ITALIC=''
        C_SUCCESS='' C_ERROR='' C_WARNING='' C_INFO=''
        C_PRIMARY='' C_MUTED='' C_BORDER=''
        C_MENU_NUM='' C_TITLE='' C_PATH=''
        C_NUMBER='' C_TIMESTAMP='' C_INPUT='' C_ACCENT='' C_HINT=''
        C_LOGO1='' C_LOGO2='' C_LOGO3='' C_SLOGAN=''
    fi
}

# ============================================================================
# 数据持久化
# ============================================================================

init_data_dir() {
    mkdir -p "$DATA_DIR" "$LOG_DIR" 2>/dev/null
    chmod 700 "$DATA_DIR" 2>/dev/null
}

load_config() {
    [[ -f "$CONFIG_FILE" ]] && source "$CONFIG_FILE"
}

save_config() {
    init_data_dir
    
    local backup_dirs_str=""
    for d in "${BACKUP_DIRS[@]}"; do
        backup_dirs_str+="    \"$d\"\n"
    done
    
    local exclude_str=""
    for p in "${EXCLUDE_PATTERNS[@]}"; do
        exclude_str+="    \"$p\"\n"
    done
    
    cat > "$CONFIG_FILE" << EOF
# vback configuration file
# Generated: $(date '+%Y-%m-%d %H:%M:%S')

# Cloud Provider
CLOUD_PROVIDER="$CLOUD_PROVIDER"

# S3 Connection
S3_ACCESS_KEY="$S3_ACCESS_KEY"
S3_SECRET_KEY="$S3_SECRET_KEY"
S3_ENDPOINT="$S3_ENDPOINT"
S3_BUCKET="$S3_BUCKET"
S3_REGION="$S3_REGION"

# Backup Directories
BACKUP_DIRS=(
$(echo -e "$backup_dirs_str"))

# Backup Options
BACKUP_PREFIX="$BACKUP_PREFIX"
MAX_BACKUPS=$MAX_BACKUPS
COMPRESS_BACKUP=$COMPRESS_BACKUP
COMPRESSION_LEVEL=$COMPRESSION_LEVEL
SQLITE_SAFE_BACKUP=$SQLITE_SAFE_BACKUP

# Schedule
SCHEDULE_CRON="$SCHEDULE_CRON"

# Exclude Patterns
EXCLUDE_PATTERNS=(
$(echo -e "$exclude_str"))
EOF
    chmod 600 "$CONFIG_FILE"
}

needs_setup() {
    [[ -z "$S3_ACCESS_KEY" || -z "$S3_SECRET_KEY" || -z "$S3_BUCKET" || ${#BACKUP_DIRS[@]} -eq 0 ]]
}

# ============================================================================
# 日志系统
# ============================================================================

declare -A LOG_LEVELS=([DEBUG]=0 [INFO]=1 [WARN]=2 [ERROR]=3)

rotate_logs() {
    [[ ! -f "$LOG_FILE" ]] && return
    local size=$(stat -c%s "$LOG_FILE" 2>/dev/null || stat -f%z "$LOG_FILE" 2>/dev/null || echo 0)
    
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
        input=$(eval echo "$input" 2>/dev/null || echo "$input")
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

# ============================================================================
# S3 工具
# ============================================================================

check_s3_tool() {
    if command -v s3cmd &>/dev/null; then S3_TOOL="s3cmd"; return 0; fi
    if command -v aws &>/dev/null; then S3_TOOL="aws"; return 0; fi
    return 1
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
    local missing=()
    for cmd in tar gzip; do
        command -v "$cmd" &>/dev/null || missing+=("$cmd")
    done
    
    if [[ ${#missing[@]} -gt 0 ]]; then
        error "${L[err_missing_deps]}: ${missing[*]}"
        return 1
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

s3_put() {
    local src="$1" dst=$(build_s3_path "$2")
    if [[ "$S3_TOOL" == "s3cmd" ]]; then
        s3cmd -c "$S3CMD_CFG" put "$src" "s3://${S3_BUCKET}/${dst}" 2>&1
    else
        aws s3 cp "$src" "s3://${S3_BUCKET}/${dst}" $AWS_ENDPOINT 2>&1
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
    local test_file="/tmp/vback-test-$$.txt"
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
        sqlite3 "$db_file" ".backup '${backup_file}'" 2>/dev/null && return 0
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
        cp -a "$src_dir/." "$dest_dir/" 2>/dev/null
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
        local start_time=$(stat -c %Y "/proc/$pid" 2>/dev/null)
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
    if [[ -f "$LOCK_FILE" ]]; then
        local pid=$(cat "$LOCK_FILE" 2>/dev/null)
        
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
                        rm -f "$LOCK_FILE"
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
                rm -f "$LOCK_FILE"
                log_warn "Removed stale lock file (pid $pid not running)"
            fi
        else
            warn "${L[err_lock_stale]}"
            rm -f "$LOCK_FILE"
        fi
    fi
    
    echo $$ > "$LOCK_FILE"
    trap 'rm -f "$LOCK_FILE" "$S3CMD_CFG"; rm -rf "$TEMP_DIR"' EXIT
    return 0
}

# ============================================================================
# 备份核心
# ============================================================================

get_dir_size() { du -sb "$1" 2>/dev/null | cut -f1 || echo 0; }
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
        if ! tar -cf - -C "$TEMP_DIR" "$name" 2>/dev/null | gzip -"${COMPRESSION_LEVEL}" > "$archive_file" 2>/dev/null; then
            error "${L[compress_failed]}"
            rm -rf "$work_dir"
            return 1
        fi
    else
        archive_file="${TEMP_DIR}/${name}_${ts}.tar"
        s3_key="${name}/${name}_${ts}.tar"
        
        if ! tar -cf "$archive_file" -C "$TEMP_DIR" "$name" 2>/dev/null; then
            error "${L[tar_failed]}"
            rm -rf "$work_dir"
            return 1
        fi
    fi
    
    rm -rf "$work_dir"
    local archive_size=$(stat -c%s "$archive_file" 2>/dev/null || stat -f%z "$archive_file" 2>/dev/null || echo 0)
    
    info "${L[uploading]}..."
    local upload_start=$(date +%s)
    local result=$(s3_put "$archive_file" "$s3_key")
    local rc=$?
    local upload_duration=$(($(date +%s) - upload_start))
    
    rm -f "$archive_file"
    local total_duration=$(($(date +%s) - start))
    
    if [[ $rc -eq 0 ]] && ! echo "$result" | grep -qi "error\|fail"; then
        local speed=$(fmt_speed $archive_size $upload_duration)
        success "${L[upload_complete]}: ${C_PATH}${s3_key}${C_RESET}"
        info "${L[transfer]}: ${C_NUMBER}$(fmt_size $archive_size)${C_RESET} @ ${C_NUMBER}${speed}/s${C_RESET}"
        info "${L[duration]}: ${C_NUMBER}$(fmt_duration $total_duration)${C_RESET}"
        log_info "Backup success: $name size=$(fmt_size $archive_size)"
        return 0
    else
        error "${L[upload_failed]}"
        echo "$result" | head -3 | sed 's/^/    /'
        log_error "Backup failed: $name"
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
    
    [[ "$S3_TOOL" == "s3cmd" ]] && setup_s3cmd || setup_aws
    
    local total=${#BACKUP_DIRS[@]}
    local current=0
    
    for d in "${BACKUP_DIRS[@]}"; do
        ((current++))
        echo ""
        print_line '─'
        echo -e "  ${C_BOLD}[$current/$total]${C_RESET} $(basename "$d")"
        
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

install_cron() {
    crontab -l 2>/dev/null | grep -v -F "$SCRIPT_PATH" | crontab - 2>/dev/null
    (crontab -l 2>/dev/null; echo "${SCHEDULE_CRON} ${SCRIPT_PATH} backup >> ${LOG_FILE} 2>&1") | crontab -
    success "${L[cron_installed]}: ${C_INFO}${SCHEDULE_CRON}${C_RESET}"
    log_info "Cron installed: $SCHEDULE_CRON"
}

remove_cron() {
    crontab -l 2>/dev/null | grep -v -F "$SCRIPT_PATH" | crontab - 2>/dev/null
    success "${L[cron_removed]}"
    log_info "Cron removed"
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
    input_field "${L[prefix]}" "" BACKUP_PREFIX false "prefix_hint"
    
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
        
        dir_path=$(eval echo "$dir_path" 2>/dev/null || echo "$dir_path")
        
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
    show_kv "${L[backup_directories]}" "${#BACKUP_DIRS[@]}"
    show_kv "${L[compression]}" "$COMPRESS_BACKUP"
    show_kv "${L[sqlite_safe]}" "$SQLITE_SAFE_BACKUP"
    echo ""
    
    if confirm "${L[save_config_confirm]}" "y"; then
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
                [[ "$S3_TOOL" == "s3cmd" ]] && setup_s3cmd || setup_aws
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
    # ASCII Logo
    echo -e "${C_LOGO1}"
    cat << 'EOF'
          _                _    
   __   _| |__   __ _  ___| | __
   \ \ / / '_ \ / _` |/ __| |/ /
    \ V /| |_) | (_| | (__|   < 
     \_/ |_.__/ \__,_|\___|_|\_\
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
    
    # GitHub Link
    echo -e "    ${C_MUTED}🔗${C_RESET} ${C_INFO}${GITHUB_URL}${C_RESET}"
    echo ""
}

show_status_bar() {
    local cron_status=$([[ -n "$(get_cron_status)" ]] && echo "on" || echo "off")
    local provider_name=$(get_provider_name "$CLOUD_PROVIDER")
    
    # 状态卡片
    print_box_top
    
    # 云服务商和存储桶
    if [[ -n "$S3_BUCKET" ]]; then
        print_box_line "${C_MUTED}☁${C_RESET}  ${C_INFO}${provider_name:-Cloud}${C_RESET} › ${C_PRIMARY}${S3_BUCKET}${C_RESET}"
    else
        print_box_line "${C_MUTED}☁${C_RESET}  ${C_WARNING}${L[not_set]}${C_RESET}"
    fi
    
    # 状态指示器
    local status_line=""
    status_line+="$(status_badge $cron_status "${L[scheduled_backup]}")  "
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
        menu_item "0" "${L[menu_exit]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[0-6/r/l]${C_RESET}: "
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
            0|q|Q) clear; echo -e "\n  ${C_SUCCESS}${L[goodbye]}${C_RESET}\n"; exit 0 ;;
        esac
    done
}

menu_backup() {
    show_header
    echo -e "  ${C_TITLE}▸ ${L[menu_backup]}${C_RESET}"
    echo ""
    
    if ! validate_config; then
        press_enter
        return
    fi
    
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
    
    if ! validate_config; then
        press_enter
        return
    fi
    
    check_s3_tool || { error "${L[err_no_s3_tool]}"; press_enter; return; }
    [[ "$S3_TOOL" == "s3cmd" ]] && setup_s3cmd || setup_aws
    
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
    [[ "$S3_TOOL" == "s3cmd" ]] && setup_s3cmd || setup_aws
    
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

menu_cron() {
    while true; do
        show_header
        echo -e "  ${C_TITLE}▸ ${L[scheduled_backup]}${C_RESET}"
        echo ""
        
        local cron_job=$(get_cron_status)
        if [[ -n "$cron_job" ]]; then
            echo -e "  ${L[cron_status]}: $(status_badge ok "${L[cron_enabled]}")"
            echo -e "  ${C_MUTED}$cron_job${C_RESET}"
        else
            echo -e "  ${L[cron_status]}: $(status_badge off "${L[cron_disabled]}")"
        fi
        
        echo ""
        print_line '─'
        
        menu_item "1" "${L[enable_update]}"
        menu_item "2" "${L[disable_cron]}"
        menu_item "0" "${L[back]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[0-2]${C_RESET}: "
        read -r choice
        
        case $choice in
            1)
                echo ""
                echo -e "  ${C_MUTED}${L[cron_examples]}:${C_RESET}"
                echo -e "    ${C_MUTED}0 3 * * *${C_RESET}   ${L[cron_daily]}"
                echo -e "    ${C_MUTED}0 */6 * * *${C_RESET} ${L[cron_6hours]}"
                echo -e "    ${C_MUTED}0 0 * * 0${C_RESET}   ${L[cron_weekly]}"
                echo ""
                input_field "${L[cron_expression]}" "$SCHEDULE_CRON" SCHEDULE_CRON
                install_cron
                save_config
                press_enter
                ;;
            2)
                if confirm "${L[confirm_disable]}"; then
                    remove_cron
                fi
                press_enter
                ;;
            0|"") return ;;
        esac
    done
}

menu_edit_config() {
    while true; do
        show_header
        echo -e "  ${C_TITLE}▸ ${L[edit_config]}${C_RESET}"
        echo ""
        
        echo -e "  ${C_BOLD}${L[current_config]}${C_RESET}"
        show_kv "${L[cloud_provider]}" "$(get_provider_name "$CLOUD_PROVIDER")" "$C_INFO"
        show_kv "${L[bucket]}" "$S3_BUCKET" "$C_INFO"
        show_kv "${L[prefix]}" "${BACKUP_PREFIX:-${L[root_directory]}}"
        show_kv "${L[backup_directories]}" "${#BACKUP_DIRS[@]}"
        show_kv "${L[compression]}" "$COMPRESS_BACKUP (${L[compression_level]} $COMPRESSION_LEVEL)"
        show_kv "${L[sqlite_safe]}" "$SQLITE_SAFE_BACKUP"
        show_kv "${L[max_backups]}" "$MAX_BACKUPS"
        
        echo ""
        print_line '─'
        
        menu_item "1" "${L[s3_settings]}"
        menu_item "2" "${L[backup_directories]}"
        menu_item "3" "${L[backup_settings]}"
        menu_item "4" "${L[exclude_patterns]}"
        menu_item "s" "${L[save]}"
        menu_item "0" "${L[back]}"
        
        echo ""
        echo -ne "  ${L[select_option]} ${C_MUTED}[0-4/s]${C_RESET}: "
        read -r choice
        
        case $choice in
            1) edit_s3_config ;;
            2) edit_backup_dirs ;;
            3) edit_backup_options ;;
            4) edit_exclude_patterns ;;
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
    input_field "${L[prefix]}" "$BACKUP_PREFIX" BACKUP_PREFIX false "prefix_hint"
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
                    new_dir=$(eval echo "$new_dir" 2>/dev/null || echo "$new_dir")
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
                EXCLUDE_PATTERNS=("*.log" "*.tmp" "node_modules" ".git" "__pycache__" "*.pyc" ".DS_Store" "Thumbs.db")
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

# ============================================================================
# 命令行接口
# ============================================================================

usage() {
    echo ""
    show_logo
    echo -e "  ${C_SLOGAN}${L[slogan]}${C_RESET} - ${L[tagline]}"
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
    help            ${L[cli_cmd_help]}

  ${C_BOLD}${L[cli_options]}${C_RESET}
    -v, --verbose       ${L[cli_opt_verbose]}
    -c, --config FILE   ${L[cli_opt_config]}
    --lang LANG         ${L[cli_opt_lang]}

  ${C_BOLD}${L[cli_examples]}${C_RESET}
    $SCRIPT_NAME                    # ${L[cli_cmd_menu]}
    $SCRIPT_NAME backup             # ${L[cli_cmd_backup]}
    $SCRIPT_NAME setup              # ${L[cli_cmd_setup]}
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
    show_kv "${L[prefix]}" "${BACKUP_PREFIX:-${L[root_directory]}}"
    echo ""
    
    echo -e "  ${C_MUTED}${L[backup_directories]} (${#BACKUP_DIRS[@]}):${C_RESET}"
    for d in "${BACKUP_DIRS[@]}"; do
        if [[ -d "$d" ]]; then
            echo -e "    ${C_SUCCESS}✓${C_RESET} $d"
        else
            echo -e "    ${C_ERROR}✗${C_RESET} $d ${C_ERROR}(${L[not_exist]})${C_RESET}"
        fi
    done
    echo ""
    
    show_kv "${L[compression]}" "$COMPRESS_BACKUP"
    show_kv "${L[compression_level]}" "$COMPRESSION_LEVEL"
    show_kv "${L[sqlite_safe]}" "$SQLITE_SAFE_BACKUP"
    show_kv "${L[max_backups]}" "$MAX_BACKUPS"
    show_kv "${L[cron_expression]}" "$SCHEDULE_CRON"
    echo ""
}

main() {
    local COMMAND=""
    local ARG_LANG=""
    
    while [[ $# -gt 0 ]]; do
        case "$1" in
            -v|--verbose) VERBOSE=true ;;
            -c|--config) shift; CONFIG_FILE="$1" ;;
            --lang) shift; ARG_LANG="$1" ;;
            -h|--help|help) COMMAND="help" ;;
            -*) error "Unknown option: $1"; exit 1 ;;
            *) COMMAND="$1" ;;
        esac
        shift
    done
    
    setup_colors
    init_data_dir
    
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
    
    check_dependencies || exit 1
    
    if ! check_s3_tool; then
        if [[ -t 0 ]] && confirm "${L[err_no_s3_tool]}. ${L[err_install_s3cmd]}"; then
            install_s3cmd || exit 1
            check_s3_tool
        fi
    fi
    
    log_info "vback started version=$VERSION cmd=${COMMAND:-menu} lang=$CURRENT_LANG"
    
    case "${COMMAND:-menu}" in
        backup)
            if needs_setup; then
                error "${L[run_setup_first]}"
                exit 1
            fi
            do_backup
            ;;
        menu)
            if needs_setup; then
                setup_wizard
                load_config
            fi
            menu_main
            ;;
        setup)
            setup_wizard
            ;;
        test)
            validate_config || exit 1
            [[ "$S3_TOOL" == "s3cmd" ]] && setup_s3cmd || setup_aws
            s3_test
            ;;
        status)
            validate_config || exit 1
            [[ "$S3_TOOL" == "s3cmd" ]] && setup_s3cmd || setup_aws
            for d in "${BACKUP_DIRS[@]}"; do
                echo -e "${C_BOLD}$(basename "$d")${C_RESET}:"
                s3_list "$(basename "$d")/" | sed 's/^/  /'
                echo ""
            done
            ;;
        install-cron)
            validate_config || exit 1
            install_cron
            ;;
        remove-cron)
            remove_cron
            ;;
        config)
            show_config_cli
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
