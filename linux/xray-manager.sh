#!/usr/bin/env bash
#
# xray-manager.sh - Xray configuration management tool
# Usage: xray [options]
#
# This script provides an interactive menu for managing Xray configurations.
#

set -euo pipefail

BASE_DIR="${XRAY_BASE_DIR:-/opt/xray}"
CONFIG_PATH="${BASE_DIR}/config.json"
LINKS_FILE="${BASE_DIR}/links.txt"
SERVICE_NAME="xray-server"

XRAY_LANG="${XRAY_LANG:-}"
if [[ -z "$XRAY_LANG" ]]; then
  sys_lang="${LANG:-en_US}"
  if [[ "$sys_lang" == zh_CN* || "$sys_lang" == zh_TW* ]]; then
    XRAY_LANG="zh"
  else
    XRAY_LANG="en"
  fi
fi

t() {
  if [[ "$XRAY_LANG" == "zh" ]]; then
    printf '%s' "$1"
  else
    printf '%s' "$2"
  fi
}

log_info()  { printf "[%s] [INFO ] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1"; }
log_warn()  { printf "[%s] [WARN ] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2; }
log_error() { printf "[%s] [ERROR] %s\n" "$(date '+%Y-%m-%d %H:%M:%S')" "$1" >&2; }

show_menu() {
  echo ""
  echo "========================================"
  echo "  $(t "Xray 配置管理" "Xray Configuration Manager")"
  echo "========================================"
  echo ""
  echo "$(t "【配置方案 1-19】" "[Profiles 1-19]")"
  echo "  1)  VLESS Reality + VMess mKCP [$(t "默认，最稳定" "Default, Most Stable")]"
  echo "  2)  VLESS Reality Only"
  echo "  3)  VMess mKCP Only"
  echo "  4)  VMess TCP"
  echo "  5)  VMess mKCP (Standalone)"
  echo "  6)  VMess QUIC"
  echo "  7)  VMess H2 + TLS"
  echo "  8)  VMess WebSocket + TLS"
  echo "  9)  VMess gRPC + TLS"
  echo "  10) VLESS H2 + TLS"
  echo "  11) VLESS WebSocket + TLS"
  echo "  12) VLESS gRPC + TLS"
  echo "  13) Trojan H2 + TLS"
  echo "  14) Trojan WebSocket + TLS"
  echo "  15) Trojan gRPC + TLS"
  echo "  16) Shadowsocks (AES-256-GCM)"
  echo "  17) VMess TCP Dynamic Port"
  echo "  18) VMess mKCP Dynamic Port"
  echo "  19) VMess QUIC Dynamic Port"
  echo ""
  echo "$(t "【查看信息 101-102】" "[View Info 101-102]")"
  echo "  101) $(t "查看连接链接" "View connection URLs")"
  echo "  102) $(t "查看当前配置" "View current configuration")"
  echo ""
  echo "$(t "【服务管理 201-203】" "[Service Management 201-203]")"
  echo "  201) $(t "查看服务状态" "View service status")"
  echo "  202) $(t "重启 Xray 服务" "Restart Xray service")"
  echo "  203) $(t "更新 Xray 内核" "Update Xray core")"
  echo ""
  echo "$(t "【卸载选项 301-303】" "[Uninstall Options 301-303]")"
  echo "  301) $(t "删除某条配置" "Delete a config entry")"
  echo "  302) $(t "卸载 Xray (保留配置)" "Uninstall Xray (keep config)")"
  echo "  303) $(t "彻底卸载 Xray" "Uninstall Xray (remove all)")"
  echo ""
  echo "  0) $(t "退出" "Exit")"
  echo ""
  printf "$(t "请选择操作: " "Select an option: ")"
}

check_installed() {
  if [[ ! -d "$BASE_DIR" ]]; then
    log_error "$(t "Xray 未安装。请先运行安装脚本。" "Xray is not installed. Please run the installation script first.")"
    exit 1
  fi
}

view_config() {
  if [[ -f "$CONFIG_PATH" ]]; then
    echo ""
    log_info "$(t "当前配置文件: $CONFIG_PATH" "Current config file: $CONFIG_PATH")"
    echo ""
    if command -v jq >/dev/null 2>&1; then
      jq '.' "$CONFIG_PATH"
    else
      cat "$CONFIG_PATH"
    fi
  else
    log_warn "$(t "配置文件不存在" "Config file does not exist")"
  fi
}

view_links() {
  if [[ -f "$LINKS_FILE" ]]; then
    echo ""
    log_info "$(t "连接链接:" "Connection URLs:")"
    echo ""
    cat "$LINKS_FILE"
    echo ""
  else
    log_warn "$(t "链接文件不存在" "Links file does not exist")"
  fi
}

restart_service() {
  log_info "$(t "重启 Xray 服务..." "Restarting Xray service...")"
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl restart "$SERVICE_NAME"
    sudo systemctl status "$SERVICE_NAME" --no-pager
  else
    log_warn "$(t "systemd 不可用" "systemd is not available")"
  fi
}

view_status() {
  log_info "$(t "Xray 服务状态:" "Xray service status:")"
  if command -v systemctl >/dev/null 2>&1; then
    sudo systemctl status "$SERVICE_NAME" --no-pager || true
  else
    if pgrep -x xray >/dev/null 2>&1; then
      log_info "$(t "Xray 进程正在运行" "Xray process is running")"
    else
      log_warn "$(t "Xray 进程未运行" "Xray process is not running")"
    fi
  fi
}

delete_entry() {
  local script_url="https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh"
  
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$script_url" | sudo bash -s -- --profile delete-config-entry
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$script_url" | sudo bash -s -- --profile delete-config-entry
  else
    log_error "$(t "需要 curl 或 wget" "curl or wget is required")"
    exit 1
  fi
}

update_core() {
  log_info "$(t "更新 Xray 内核..." "Updating Xray core...")"
  local script_url="https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh"
  
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$script_url" | sudo bash -s -- --keep-config
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$script_url" | sudo bash -s -- --keep-config
  else
    log_error "$(t "需要 curl 或 wget" "curl or wget is required")"
    exit 1
  fi
}

uninstall_keep_config() {
  local script_url="https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh"
  
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$script_url" | sudo bash -s -- --uninstall-config
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$script_url" | sudo bash -s -- --uninstall-config
  else
    log_error "$(t "需要 curl 或 wget" "curl or wget is required")"
    exit 1
  fi
}

uninstall_all() {
  local script_url="https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh"
  
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$script_url" | sudo bash -s -- --uninstall
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$script_url" | sudo bash -s -- --uninstall
  else
    log_error "$(t "需要 curl 或 wget" "curl or wget is required")"
    exit 1
  fi
}

add_profile_direct() {
  local profile="$1"
  log_info "$(t "选择方案: $profile" "Selected profile: $profile")"
  
  local script_url="https://github.com/owokit/Xray_Script/raw/main/xray-linux-airport.sh"
  
  if command -v curl >/dev/null 2>&1; then
    curl -fsSL "$script_url" | sudo bash -s -- --add --profile "$profile"
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$script_url" | sudo bash -s -- --add --profile "$profile"
  else
    log_error "$(t "需要 curl 或 wget" "curl or wget is required")"
    exit 1
  fi
}

main() {
  check_installed
  
  while true; do
    show_menu
    read -r choice
    
    case "$choice" in
      # Profiles 1-19
      1)  add_profile_direct "reality-kcp" ;;
      2)  add_profile_direct "reality-only" ;;
      3)  add_profile_direct "kcp-only" ;;
      4)  add_profile_direct "vmess-tcp" ;;
      5)  add_profile_direct "vmess-mkcp" ;;
      6)  add_profile_direct "vmess-quic" ;;
      7)  add_profile_direct "vmess-h2-tls" ;;
      8)  add_profile_direct "vmess-ws-tls" ;;
      9)  add_profile_direct "vmess-grpc-tls" ;;
      10) add_profile_direct "vless-h2-tls" ;;
      11) add_profile_direct "vless-ws-tls" ;;
      12) add_profile_direct "vless-grpc-tls" ;;
      13) add_profile_direct "trojan-h2-tls" ;;
      14) add_profile_direct "trojan-ws-tls" ;;
      15) add_profile_direct "trojan-grpc-tls" ;;
      16) add_profile_direct "shadowsocks" ;;
      17) add_profile_direct "vmess-tcp-dynamic" ;;
      18) add_profile_direct "vmess-mkcp-dynamic" ;;
      19) add_profile_direct "vmess-quic-dynamic" ;;
      # View Info 101-102
      101) view_links ;;
      102) view_config ;;
      # Service Management 201-203
      201) view_status ;;
      202) restart_service ;;
      203) update_core ;;
      # Uninstall Options 301-303
      301) delete_entry ;;
      302) uninstall_keep_config; break ;;
      303) uninstall_all; break ;;
      # Exit
      0) echo "$(t "再见!" "Goodbye!")"; break ;;
      *) log_warn "$(t "无效选项" "Invalid option")" ;;
    esac
    
    echo ""
    printf "$(t "按 Enter 继续..." "Press Enter to continue...")"
    read -r
  done
}

main "$@"
