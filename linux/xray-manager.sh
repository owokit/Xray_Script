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
  echo "  1) $(t "添加新配置方案" "Add new profile")"
  echo "  2) $(t "查看当前配置" "View current configuration")"
  echo "  3) $(t "查看连接链接" "View connection URLs")"
  echo "  4) $(t "重启 Xray 服务" "Restart Xray service")"
  echo "  5) $(t "查看服务状态" "View service status")"
  echo "  6) $(t "删除某条配置" "Delete a config entry")"
  echo "  7) $(t "更新 Xray 内核" "Update Xray core")"
  echo "  8) $(t "卸载 Xray (保留配置)" "Uninstall Xray (keep config)")"
  echo "  9) $(t "彻底卸载 Xray" "Uninstall Xray (remove all)")"
  echo "  0) $(t "退出" "Exit")"
  echo ""
  printf "$(t "请选择操作 [0-9]: " "Select an option [0-9]: ")"
}

check_installed() {
  if [[ ! -d "$BASE_DIR" ]]; then
    log_error "$(t "Xray 未安装。请先运行安装脚本。" "Xray is not installed. Please run the installation script first.")"
    exit 1
  fi
}

show_profile_menu() {
  echo ""
  log_info "$(t "请选择要部署的协议方案：" "Please select the protocol scheme to deploy:")"
  echo ""
  echo "  1)  VLESS Reality + VMess mKCP [$(t "默认，最稳定" "Default, Most Stable")]"
  echo "  2)  VLESS Reality Only"
  echo "  3)  VMess mKCP Only"
  echo "  4)  VMess TCP"
  echo "  5)  VMess mKCP (Standalone)"
  echo "  6)  VMess QUIC"
  echo "  7)  VMess H2 + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  8)  VMess WebSocket + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  9)  VMess gRPC + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  10) VLESS H2 + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  11) VLESS WebSocket + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  12) VLESS gRPC + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  13) Trojan H2 + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  14) Trojan WebSocket + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  15) Trojan gRPC + TLS [$(t "自签名证书" "Self-signed cert")]"
  echo "  16) Shadowsocks (AES-256-GCM)"
  echo "  17) VMess TCP Dynamic Port [$(t "动态端口 20000-30000" "Dynamic ports 20000-30000")]"
  echo "  18) VMess mKCP Dynamic Port [$(t "动态端口 20000-30000" "Dynamic ports 20000-30000")]"
  echo "  19) VMess QUIC Dynamic Port [$(t "动态端口 20000-30000" "Dynamic ports 20000-30000")]"
  echo ""
  echo "  0) $(t "返回主菜单" "Back to main menu")"
  echo ""
  printf "$(t "请输入选项编号 [0-19，默认: 1]: " "Enter option number [0-19, default: 1]: ")"
}

add_profile() {
  show_profile_menu
  read -r choice
  
  local profile=""
  case "${choice:-1}" in
    0)  return ;;
    1)  profile="reality-kcp" ;;
    2)  profile="reality-only" ;;
    3)  profile="kcp-only" ;;
    4)  profile="vmess-tcp" ;;
    5)  profile="vmess-mkcp" ;;
    6)  profile="vmess-quic" ;;
    7)  profile="vmess-h2-tls" ;;
    8)  profile="vmess-ws-tls" ;;
    9)  profile="vmess-grpc-tls" ;;
    10) profile="vless-h2-tls" ;;
    11) profile="vless-ws-tls" ;;
    12) profile="vless-grpc-tls" ;;
    13) profile="trojan-h2-tls" ;;
    14) profile="trojan-ws-tls" ;;
    15) profile="trojan-grpc-tls" ;;
    16) profile="shadowsocks" ;;
    17) profile="vmess-tcp-dynamic" ;;
    18) profile="vmess-mkcp-dynamic" ;;
    19) profile="vmess-quic-dynamic" ;;
    *)  profile="reality-kcp" ;;
  esac
  
  log_info "$(t "选择方案: $profile" "Selected profile: $profile")"
  
  # Download and run the main script with --add and --profile flags
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
    curl -fsSL "$script_url" | sudo bash -s -- --delete-config-entry
  elif command -v wget >/dev/null 2>&1; then
    wget -qO- "$script_url" | sudo bash -s -- --delete-config-entry
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

main() {
  check_installed
  
  while true; do
    show_menu
    read -r choice
    
    case "$choice" in
      1) add_profile ;;
      2) view_config ;;
      3) view_links ;;
      4) restart_service ;;
      5) view_status ;;
      6) delete_entry ;;
      7) update_core ;;
      8) uninstall_keep_config; break ;;
      9) uninstall_all; break ;;
      0) echo "$(t "再见!" "Goodbye!")"; break ;;
      *) log_warn "$(t "无效选项" "Invalid option")" ;;
    esac
    
    echo ""
    printf "$(t "按 Enter 继续..." "Press Enter to continue...")"
    read -r
  done
}

main "$@"
