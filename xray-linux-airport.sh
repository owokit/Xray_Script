#!/usr/bin/env bash

set -euo pipefail

#################################
# Parameters (env / cli)
#################################

REALITY_PORT="${REALITY_PORT:-0}"
VMESS_KCP_PORT="${VMESS_KCP_PORT:-0}"
UUID="${UUID:-}"
CORE_VERSION="${CORE_VERSION:-}"
PROXY="${PROXY:-}"
REALITY_DEST="${REALITY_DEST:-cloudflare.com:443}"
REALITY_SERVER_NAME="${REALITY_SERVER_NAME:-cloudflare.com}"
REALITY_SHORT_ID="${REALITY_SHORT_ID:-}"
BASE_DIR="${BASE_DIR:-/opt/xray}"
TLS_CERT_MODE="${TLS_CERT_MODE:-}"
TLS_DOMAIN="${TLS_DOMAIN:-}"
UNINSTALL="false"
REBUILD_CONFIG_ONLY="false"
UNINSTALL_CONFIG="false"
DELETE_CONFIG="false"
KEEP_CONFIG="${KEEP_CONFIG:-false}"
FORCE_REBUILD_CONFIG="${FORCE_REBUILD_CONFIG:-false}"
UPDATE_CORE_ONLY="false"
PROFILE="${PROFILE:-}"
MAIN_PORT="${MAIN_PORT:-0}"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --reality-port)
      REALITY_PORT="$2"; shift 2;;
    --vmess-kcp-port)
      VMESS_KCP_PORT="$2"; shift 2;;
    --uuid)
      UUID="$2"; shift 2;;
    --core-version)
      CORE_VERSION="$2"; shift 2;;
    --proxy)
      PROXY="$2"; shift 2;;
    --reality-dest)
      REALITY_DEST="$2"; shift 2;;
    --reality-server-name)
      REALITY_SERVER_NAME="$2"; shift 2;;
    --reality-short-id)
      REALITY_SHORT_ID="$2"; shift 2;;
    --base-dir)
      BASE_DIR="$2"; shift 2;;
    --tls-cert-mode)
      TLS_CERT_MODE="$2"; shift 2;;
    --tls-domain)
      TLS_DOMAIN="$2"; shift 2;;
    --keep-config)
      KEEP_CONFIG="true"; shift 1;;
    --force-rebuild-config)
      FORCE_REBUILD_CONFIG="true"; shift 1;;
    --rebuild-config-only)
      REBUILD_CONFIG_ONLY="true"; shift 1;;
    --uninstall)
      UNINSTALL="true"; shift 1;;
    --uninstall-config)
      UNINSTALL_CONFIG="true"; shift 1;;
    --delete-config)
      DELETE_CONFIG="true"; shift 1;;
    --add)
      ADD_TO_CONFIG="true"; shift 1;;
    --profile)
      PROFILE="$2"; shift 2;;
    *)
      echo "Unknown argument: $1" >&2
      exit 1;;
  esac
done

#################################
# Helper functions
#################################

if [[ -t 1 && -z "${NO_COLOR:-}" ]]; then
  COLOR_INFO=$'\033[36m'
  COLOR_WARN=$'\033[33m'
  COLOR_ERROR=$'\033[31m'
  COLOR_RESET=$'\033[0m'

  COLOR_SUM_TITLE=$'\033[36m'
  COLOR_SUM_SECTION=$'\033[32m'
  COLOR_SUM_LABEL=$'\033[37m'
  COLOR_SUM_HIGHLIGHT=$'\033[35m'
  COLOR_SUM_URL=$'\033[33m'
else
  COLOR_INFO=""
  COLOR_WARN=""
  COLOR_ERROR=""
  COLOR_RESET=""

  COLOR_SUM_TITLE=""
  COLOR_SUM_SECTION=""
  COLOR_SUM_LABEL=""
  COLOR_SUM_HIGHLIGHT=""
  COLOR_SUM_URL=""
fi

XRAY_LANG_DETECTED=""

detect_lang() {
  if [[ -n "${XRAY_LANG:-}" ]]; then
    case "${XRAY_LANG,,}" in
      zh*) XRAY_LANG_DETECTED="zh"; return ;;
      en*) XRAY_LANG_DETECTED="en"; return ;;
      *)   XRAY_LANG_DETECTED="en"; return ;;
    esac
  fi

  local lc="${LC_ALL:-${LANG:-}}"
  if [[ "$lc" == zh_* || "$lc" == zh-* ]]; then
    XRAY_LANG_DETECTED="zh"
  else
    XRAY_LANG_DETECTED="en"
  fi
}

t() {
  local zh="$1" en="$2"
  if [[ "${XRAY_LANG_DETECTED:-en}" == "zh" ]]; then
    printf "%s" "$zh"
  else
    printf "%s" "$en"
  fi
}

detect_lang

log_info()  { printf "%b\n" "${COLOR_INFO}[$(date '+%F %T')] [INFO ] $*${COLOR_RESET}" >&2; }
log_warn()  { printf "%b\n" "${COLOR_WARN}[$(date '+%F %T')] [WARN ] $*${COLOR_RESET}" >&2; }
log_error() { printf "%b\n" "${COLOR_ERROR}[$(date '+%F %T')] [ERROR] $*${COLOR_RESET}" >&2; }

require_root() {
  if [[ "${EUID:-$(id -u)}" -ne 0 ]]; then
    log_error "Please run this script as root (sudo)."
    exit 1
  fi
}

validate_base_dir() {
  local dir="$1"

  if [[ -z "$dir" ]]; then
    log_error "BASE_DIR is empty. Please set a non-empty directory such as /opt/xray."
    exit 1
  fi

  if [[ "$dir" != /* ]]; then
    log_error "BASE_DIR must be an absolute path, e.g. /opt/xray."
    exit 1
  fi

  if [[ "$dir" == "/" ]]; then
    log_error "Refusing to use '/' as BASE_DIR."
    exit 1
  fi

  case "$dir" in
    /root|/home|/usr|/var|/etc|/opt|/tmp)
      log_error "Refusing to use system directory '$dir' as BASE_DIR. Please use a subdirectory such as /opt/xray."
      exit 1
      ;;
  esac

  if [[ "$dir" =~ ^/[^/]+$ ]]; then
    log_error "Refusing to use top-level directory '$dir' as BASE_DIR. Please use a subdirectory such as /opt/xray."
    exit 1
  fi
}

detect_pkg_manager() {
  if command -v apt-get >/dev/null 2>&1; then
    echo "apt-get"
  elif command -v yum >/dev/null 2>&1; then
    echo "yum"
  elif command -v dnf >/dev/null 2>&1; then
    echo "dnf"
  else
    echo ""
  fi
}

install_dep() {
  local bin_name="$1" pkg_name="${2:-$1}"

  if command -v "$bin_name" >/dev/null 2>&1; then
    return 0
  fi

  local pm
  pm="$(detect_pkg_manager)"
  if [[ -z "$pm" ]]; then
    log_error "Package manager not found (apt-get/yum/dnf). Please install '$pkg_name' manually and retry."
    exit 1
  fi

  log_info "Installing dependency: $pkg_name (via $pm)"
  case "$pm" in
    apt-get)
      DEBIAN_FRONTEND=noninteractive apt-get update -y && DEBIAN_FRONTEND=noninteractive apt-get install -y "$pkg_name" || {
        log_error "Failed to install $pkg_name via apt-get."
        exit 1
      }
      ;;
    yum|dnf)
      "$pm" install -y "$pkg_name" || {
        log_error "Failed to install $pkg_name via $pm."
        exit 1
      }
      ;;
  esac
}

ensure_deps() {
  install_dep curl curl
  install_dep unzip unzip
  install_dep openssl openssl  # For certificate generation
  install_dep jq jq            # For JSON manipulation
}

validate_port_value() {
  local name="$1" value="$2" num

  if [[ -z "$value" || "$value" == "0" ]]; then
    return 0
  fi

  if ! [[ "$value" =~ ^[0-9]+$ ]]; then
    log_error "Invalid $name: '$value' is not a valid number."
    exit 1
  fi

  num="$value"
  if (( num < 1 || num > 65535 )); then
    log_error "Invalid $name: '$value' is out of range (1-65535)."
    exit 1
  fi
}

#################################
# Uninstall
#################################

cleanup_firewall_rules_from_ports_file() {
  local ports_file="$1" reality_port="" vmess_kcp_port="" firewall_ports="" k v port proto

  if [[ -f "$ports_file" ]]; then
    while IFS='=' read -r k v; do
      case "$k" in
        REALITY_PORT) reality_port="$v" ;;
        VMESS_KCP_PORT) vmess_kcp_port="$v" ;;
        FIREWALL_PORTS) firewall_ports="$v" ;;
      esac
    done <"$ports_file"
  fi

  if [[ -z "$firewall_ports" && ( -n "$reality_port" || -n "$vmess_kcp_port" ) ]]; then
    if [[ -n "$reality_port" ]]; then
      firewall_ports="${firewall_ports}${firewall_ports:+ }${reality_port}/tcp"
    fi
    if [[ -n "$vmess_kcp_port" ]]; then
      firewall_ports="${firewall_ports}${firewall_ports:+ }${vmess_kcp_port}/udp"
    fi
  fi

  if [[ -z "$firewall_ports" ]]; then
    log_warn "Ports file not found or empty (${ports_file}); firewall rules may need manual cleanup."
    return 0
  fi

  log_info "Removing firewall rules (if available)..."
  if command -v firewall-cmd >/dev/null 2>&1; then
    for port_spec in $firewall_ports; do
      if [[ "$port_spec" =~ ^([0-9]+(-[0-9]+)?)/(.+)$ ]]; then
        port="${BASH_REMATCH[1]}"
        proto="${BASH_REMATCH[3]}"
        firewall-cmd --remove-port=${port}/${proto} --permanent || true
      fi
    done
    firewall-cmd --reload || true
  elif command -v ufw >/dev/null 2>&1; then
    for port_spec in $firewall_ports; do
      if [[ "$port_spec" =~ ^([0-9]+(-[0-9]+)?)/(.+)$ ]]; then
        port="${BASH_REMATCH[1]}"
        proto="${BASH_REMATCH[3]}"
        if [[ "$port" == *-* ]]; then port="${port//-/:}"; fi
        ufw delete allow ${port}/${proto} || true
      fi
    done
  else
    log_warn "No known firewall manager detected while uninstalling. Please check firewall rules for Xray ports manually if needed."
  fi
}

uninstall_xray() {
  local service_name="xray-server"
  local ports_file="${BASE_DIR}/ports.env"

  log_info "Uninstall mode: stopping service and removing files..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload || true
    log_info "systemd service ${service_name} removed (if existed)."
  fi

  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -x xray >/dev/null 2>&1; then
      pkill -x xray || true
      log_info "Stopped running xray processes (if any)."
    fi
  fi

  cleanup_firewall_rules_from_ports_file "$ports_file"

  if [[ -d "$BASE_DIR" ]]; then
    rm -rf "$BASE_DIR"
    log_info "Removed directory: $BASE_DIR"
  else
    log_info "Base directory not found: $BASE_DIR"
  fi

  log_info "Xray has been uninstalled on Linux."
}

uninstall_xray_config_only() {
  local service_name="xray-server"
  local ports_file="${BASE_DIR}/ports.env"
  local config_path="${BASE_DIR}/config.json"
  local links_file="${BASE_DIR}/links.txt"

  log_info "Uninstall-config mode: stopping service and removing configuration files..."

  if command -v systemctl >/dev/null 2>&1; then
    systemctl stop "$service_name" 2>/dev/null || true
    systemctl disable "$service_name" 2>/dev/null || true
    rm -f "/etc/systemd/system/${service_name}.service"
    systemctl daemon-reload || true
    log_info "systemd service ${service_name} removed (if existed)."
  fi

  if command -v pgrep >/dev/null 2>&1; then
    if pgrep -x xray >/dev/null 2>&1; then
      pkill -x xray || true
      log_info "Stopped running xray processes (if any)."
    fi
  fi

  cleanup_firewall_rules_from_ports_file "$ports_file"

  rm -f "$config_path" "$links_file" "$ports_file"
  log_info "Removed configuration files under ${BASE_DIR} (config.json, links.txt, ports.env)."
  log_info "Xray configuration has been uninstalled on Linux. Core binaries and logs were kept."
}

delete_xray_config_files() {
  local config_path="${BASE_DIR}/config.json"
  local links_file="${BASE_DIR}/links.txt"
  local ports_file="${BASE_DIR}/ports.env"

  rm -f "$config_path" "$links_file" "$ports_file"
  log_info "Deleted configuration files (if existed): $config_path, $links_file, $ports_file"
}

delete_config_entry_interactive() {
  local config_path="${BASE_DIR}/config.json"

  if [[ ! -f "$config_path" ]]; then
    log_error "Config file not found at $config_path. Nothing to delete."
    return 1
  fi

  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required to delete a specific config entry but is not installed."
    return 1
  fi

  local inbounds_json
  inbounds_json="$(jq -c '.inbounds // []' "$config_path")" || {
    log_error "Failed to parse inbounds from $config_path."
    return 1
  }

  local count
  count="$(printf '%s' "$inbounds_json" | jq 'length')" || count=0
  if [[ "$count" -eq 0 ]]; then
    log_warn "No inbounds found in $config_path. Nothing to delete."
    return 0
  fi

  echo ""
  log_info "Existing inbound entries in $config_path:"

  local i
  for (( i=0; i<count; i++ )); do
    local entry
    entry="$(printf '%s' "$inbounds_json" | jq ".[$i]")" || continue

    local port proto tag net path host name
    port="$(printf '%s' "$entry" | jq -r '.port // "-"')"
    proto="$(printf '%s' "$entry" | jq -r '.protocol // "-"')"
    tag="$(printf '%s' "$entry" | jq -r '.tag // "-"')"
    net="$(printf '%s' "$entry" | jq -r '.streamSettings.network // "-"' 2>/dev/null || echo "-")"
    path="$(printf '%s' "$entry" | jq -r '.streamSettings.wsSettings.path // .streamSettings.httpSettings.path // .streamSettings.grpcSettings.serviceName // "-"' 2>/dev/null || echo "-")"
    host="$(printf '%s' "$entry" | jq -r '.streamSettings.httpSettings.host[0] // "-"' 2>/dev/null || echo "-")"
    name="$tag"

    printf "  [%d] protocol=%s, port=%s, network=%s, tag=%s, path=%s, host=%s\n" \
      "$i" "$proto" "$port" "$net" "$tag" "$path" "$host"
  done

  echo ""
  local input_file="/dev/stdin" interactive_mode="false"

  if [[ -t 0 ]]; then
    interactive_mode="true"
  elif [[ -e /dev/tty ]]; then
    interactive_mode="true"
    input_file="/dev/tty"
  fi

  if [[ "$interactive_mode" != "true" ]]; then
    log_error "Interactive input is not available; cannot select which entry to delete."
    return 1
  fi

  local selection
  printf "Enter indices to delete (e.g. 0,2,4 or 0-2,4) [0-%d]: " "$(($count-1))"
  read -r selection < "$input_file"

  if [[ -z "$selection" ]]; then
    log_error "No indices entered. Aborting delete operation."
    return 1
  fi

  if [[ "$selection" == "q" || "$selection" == "Q" ]]; then
    log_error "Operation cancelled by user."
    return 1
  fi

  local tokens_str="$selection"
  tokens_str="${tokens_str// /,}"

  local -a indices
  local token
  IFS=',' read -r -a tokens <<< "$tokens_str"
  for token in "${tokens[@]}"; do
    [[ -z "$token" ]] && continue

    if [[ "$token" =~ ^[0-9]+$ ]]; then
      local idx="$token"
      if (( idx < 0 || idx >= count )); then
        log_error "Invalid index: $idx. Aborting delete operation."
        return 1
      fi
      indices+=("$idx")
    elif [[ "$token" =~ ^([0-9]+)-([0-9]+)$ ]]; then
      local start="${BASH_REMATCH[1]}" end="${BASH_REMATCH[2]}" i
      if (( start > end )); then
        local tmp="$start"; start="$end"; end="$tmp"
      fi
      for (( i=start; i<=end; i++ )); do
        if (( i < 0 || i >= count )); then
          log_error "Invalid index in range: $i (from $token). Aborting delete operation."
          return 1
        fi
        indices+=("$i")
      done
    else
      log_error "Invalid index expression: $token. Use forms like 0,2,4 or 0-2,4."
      return 1
    fi
  done

  if (( ${#indices[@]} == 0 )); then
    log_error "No valid indices parsed from input. Aborting delete operation."
    return 1
  fi

  local idx_json idx_display
  idx_json="$(printf '%s\n' "${indices[@]}" | jq -s 'sort | unique')" || {
    log_error "Failed to normalize indices list."
    return 1
  }

  idx_display="$(printf '%s' "$idx_json" | jq -r 'map(tostring) | join(",")')" || idx_display=""

  echo ""
  log_warn "Deleting inbound entry indices: ${idx_display:-$selection} from $config_path."

  if ! jq --argjson idxs "$idx_json" '(.inbounds // []) as $in | .inbounds = (if ($in|length) == 0 then $in else [ range(0; $in|length) as $i | select( ($idxs|index($i))|not ) | $in[$i] ] end)' "$config_path" >"${config_path}.tmp"; then
    log_error "Failed to delete selected entries from $config_path using jq."
    rm -f "${config_path}.tmp"
    return 1
  fi

  mv "${config_path}.tmp" "$config_path"
  chmod 600 "$config_path"

  log_info "Deleted inbound entry indices: ${idx_display:-$selection} from $config_path."
  log_warn "links.txt and ports.env were not updated automatically. Please regenerate or adjust them manually if needed."

  if command -v systemctl >/dev/null 2>&1; then
    local service_name="xray-server"
    log_info "Restarting systemd service ${service_name} to apply changes..."
    systemctl restart "$service_name" || log_warn "Failed to restart ${service_name}. Please check: journalctl -u ${service_name} -xe"
  fi

  return 0
}

#################################
# Port helpers
#################################

ban_ports=(22 80 81 82 83 88 110 143 443 3306 6379 8080 8081 1080 1081 3389 53 25 587 465)

is_port_free() {
  local port="$1" proto="$2"
  if command -v ss >/dev/null 2>&1; then
    if [[ "$proto" == "tcp" ]]; then
      if ss -ltn 2>/dev/null | awk 'NR>1{print $4}' | grep -qE ":${port}$"; then
        return 1
      fi
    else
      if ss -lun 2>/dev/null | awk 'NR>1{print $4}' | grep -qE ":${port}$"; then
        return 1
      fi
    fi
  elif command -v netstat >/dev/null 2>&1; then
    if [[ "$proto" == "tcp" ]]; then
      if netstat -lnt 2>/dev/null | awk 'NR>2{print $4}' | grep -qE ":${port}$"; then
        return 1
      fi
    else
      if netstat -lnu 2>/dev/null | awk 'NR>2{print $4}' | grep -qE ":${port}$"; then
        return 1
      fi
    fi
  else
    log_warn "Neither 'ss' nor 'netstat' was found. Skipping port-in-use check for ${proto} port ${port}."
  fi
  return 0
}

random_port() {
  local proto="$1" p
  while true; do
    p=$((RANDOM % 50000 + 10000))
    for b in "${ban_ports[@]}"; do
      [[ "$p" == "$b" ]] && continue 2
    done
    if is_port_free "$p" "$proto"; then
      echo "$p"; return 0
    fi
  done
}

ensure_port() {
  local port="$1" proto="$2"
  if [[ -z "$port" || "$port" == "0" ]]; then
    port="$(random_port "$proto")"
    log_info "No $proto port specified, using random free port: $port"
  else
    if ! is_port_free "$port" "$proto"; then
      local old="$port"
      port="$(random_port "$proto")"
      log_warn "Port $old ($proto) is in use, changed to: $port"
    fi
  fi
  echo "$port"
}

SCRIPT_SOURCE="${BASH_SOURCE[0]:-$0}"
SCRIPT_DIR="$(cd "$(dirname "$SCRIPT_SOURCE")" 2>/dev/null && pwd || pwd)"

load_linux_lib_if_present() {
  local rel="$1"
  local lib_path

  lib_path="${SCRIPT_DIR}/${rel}"
  if [[ ! -f "$lib_path" && -d "$BASE_DIR" ]]; then
    lib_path="${BASE_DIR}/${rel}"
  fi

  if [[ -f "$lib_path" ]]; then
    source "$lib_path"
  fi
}

load_linux_lib_if_present "linux/xray-common.sh"
load_linux_lib_if_present "linux/xray-uninstall.sh"
load_linux_lib_if_present "linux/xray-ports.sh"

#################################
# Main
#################################

require_root
validate_base_dir "$BASE_DIR"

ADD_TO_CONFIG="${ADD_TO_CONFIG:-false}"
ACTION_MODE="install"
modes_selected=0
if [[ "$UNINSTALL" == "true" ]]; then
  ACTION_MODE="uninstall-all"
  modes_selected=$((modes_selected+1))
fi
if [[ "$UNINSTALL_CONFIG" == "true" ]]; then
  ACTION_MODE="uninstall-config"
  modes_selected=$((modes_selected+1))
fi
if [[ "$DELETE_CONFIG" == "true" ]]; then
  ACTION_MODE="delete-config"
  modes_selected=$((modes_selected+1))
fi
if [[ "$REBUILD_CONFIG_ONLY" == "true" ]]; then
  ACTION_MODE="rebuild-config-only"
  modes_selected=$((modes_selected+1))
fi

if (( modes_selected > 1 )); then
  log_error "Multiple modes specified. Please choose only one of: --uninstall, --uninstall-config, --delete-config, --rebuild-config-only."
  exit 1
fi

case "$ACTION_MODE" in
  uninstall-all)
    uninstall_xray
    exit 0
    ;;
  uninstall-config)
    uninstall_xray_config_only
    exit 0
    ;;
  delete-config)
    delete_xray_config_files
    exit 0
    ;;
esac

ensure_deps

# Ensure base directory exists early for supporting files
mkdir -p "$BASE_DIR"

# Load profile library (always try to fetch latest from GitHub first)
PROFILE_LIB_URL="https://github.com/owokit/Xray_Script/raw/main/xray-profiles-lib.sh"
PROFILE_LIB="${BASE_DIR}/xray-profiles-lib.sh"

mkdir -p "$BASE_DIR"

download_ok="false"
for attempt in 1 2 3; do
  if curl -fsSL "$PROFILE_LIB_URL" -o "$PROFILE_LIB"; then
    download_ok="true"
    break
  fi
  log_warn "$(t "第 ${attempt} 次从 GitHub 下载 xray-profiles-lib.sh 失败" "Failed to download xray-profiles-lib.sh from GitHub (attempt ${attempt}).")"
  sleep 2
done

if [[ "$download_ok" != "true" ]]; then
  log_warn "$(t "多次从 GitHub 下载配置库失败，将尝试使用本地副本（如果存在）。" "Failed to download profile library from GitHub after multiple attempts; falling back to local copy (if available).")"
  if [[ ! -f "$PROFILE_LIB" ]]; then
    PROFILE_LIB="$(dirname "$0")/xray-profiles-lib.sh"
  fi
fi

if [[ -f "$PROFILE_LIB" ]]; then
  source "$PROFILE_LIB"
else
  log_error "Profile library not found. Please check that xray-profiles-lib.sh exists under $BASE_DIR or alongside this script."
  exit 1
fi

# Select profile interactively if not specified
if command -v select_profile_interactive >/dev/null 2>&1; then
  select_profile_interactive
fi

# Handle special maintenance profiles selected interactively
case "$PROFILE" in
  uninstall-all)
    uninstall_xray
    exit 0
    ;;
  uninstall-keep-config|uninstall-config)
    uninstall_xray_config_only
    exit 0
    ;;
  update-core)
    UPDATE_CORE_ONLY="true"
    KEEP_CONFIG="true"
    # Set a dummy profile to ensure variable expansion works if needed, though it shouldn't be used
    PROFILE="reality-kcp" 
    ;;
  delete-config-entry)
    delete_config_entry_interactive
    exit 0
    ;;
esac

CORE_REPO="XTLS/Xray-core"
CORE_FILE_NAME="Xray-linux-64.zip"
CORE_BIN_DIR="${BASE_DIR}/bin"
LOG_DIR="${BASE_DIR}/log"
CONFIG_PATH="${BASE_DIR}/config.json"
LINKS_FILE="${BASE_DIR}/links.txt"
PORTS_FILE="${BASE_DIR}/ports.env"
CORE_ZIP_PATH="${BASE_DIR}/${CORE_FILE_NAME}"
CORE_EXE="${CORE_BIN_DIR}/xray"
SERVICE_NAME="xray-server"

mkdir -p "$BASE_DIR" "$CORE_BIN_DIR" "$LOG_DIR"
 
if [[ "$REBUILD_CONFIG_ONLY" == "true" ]]; then
  if [[ "$KEEP_CONFIG" == "true" || "$FORCE_REBUILD_CONFIG" == "true" || "$ADD_TO_CONFIG" == "true" ]]; then
    log_error "Options --keep-config/--force-rebuild-config/--add cannot be used together with --rebuild-config-only."
    exit 1
  fi
  if [[ ! -f "$CONFIG_PATH" ]]; then
    log_error "Config file not found at $CONFIG_PATH. Please run the script without --rebuild-config-only first to perform initial installation."
    exit 1
  fi
else
  if [[ -f "$CONFIG_PATH" ]]; then
    if [[ "$KEEP_CONFIG" != "true" && "$FORCE_REBUILD_CONFIG" != "true" && "$ADD_TO_CONFIG" != "true" ]]; then
      inbounds_count=""
      if inbounds_count="$(jq -r '(.inbounds // []) | length' "$CONFIG_PATH" 2>/dev/null)"; then
        if [[ "$inbounds_count" -eq 0 ]]; then
          log_warn "$(t "检测到已有配置文件 $CONFIG_PATH，但其中没有任何入站配置，将视为全新安装并直接重建配置。" "Config file found at $CONFIG_PATH but contains no inbound entries; treating as fresh install and rebuilding config without asking.")"
          FORCE_REBUILD_CONFIG="true"
        fi
      fi
    fi
    if [[ "$KEEP_CONFIG" == "true" && "$FORCE_REBUILD_CONFIG" == "true" ]]; then
      log_error "Both --keep-config and --force-rebuild-config were specified. Please choose only one."
      exit 1
    elif [[ "$KEEP_CONFIG" == "true" ]]; then
      UPDATE_CORE_ONLY="true"
      log_info "Existing config detected at $CONFIG_PATH. --keep-config is set: will only update Xray core and keep existing config, firewall rules and service."
    elif [[ "$FORCE_REBUILD_CONFIG" == "true" ]]; then
      log_warn "Existing config at $CONFIG_PATH will be overwritten because --force-rebuild-config is set."
    elif [[ "$ADD_TO_CONFIG" == "true" ]]; then
      log_info "Existing config at $CONFIG_PATH will be merged with new profile because --add is set."
    else
      # Interactive check
      input_file="/dev/stdin"
      interactive_mode="false"

      if [[ -t 0 ]]; then
        interactive_mode="true"
      elif [[ -e /dev/tty ]]; then
        interactive_mode="true"
        input_file="/dev/tty"
      fi

      if [[ "$interactive_mode" == "true" ]]; then
        echo ""
        log_warn "$(t "检测到已有配置文件: $CONFIG_PATH" "Config file already exists at $CONFIG_PATH.")"
        echo "  1) $(t "追加（向现有配置中合并新方案）" "Add (Merge new profile to existing config)")"
        echo "  2) $(t "覆盖（删除现有配置并重建）" "Overwrite (Delete existing config)")"
        echo "  3) $(t "取消操作" "Cancel")"
        printf "$(t "请输入选项 [1-3，默认: 1]: " "Enter option [1-3, default: 1]: ")"
        read -r conflict_choice < "$input_file"
        case "${conflict_choice:-1}" in
          1) ADD_TO_CONFIG="true" ;;
          2) FORCE_REBUILD_CONFIG="true" ;;
          *) log_error "$(t "操作已取消。" "Operation cancelled by user.")"; exit 1 ;;
        esac
      else
        log_error "$(t "检测到已有配置文件 $CONFIG_PATH。请使用 --keep-config 保留配置，--force-rebuild-config 覆盖配置，或 --add 合并新方案。" "Config file already exists at $CONFIG_PATH. Use --keep-config to reuse it, --force-rebuild-config to overwrite it, or --add to merge new profile.")"
        exit 1
      fi
    fi
  else
    if [[ "$KEEP_CONFIG" == "true" ]]; then
      log_warn "--keep-config was specified but no existing config was found at $CONFIG_PATH. A fresh config will be created."
    fi
    if [[ "$ADD_TO_CONFIG" == "true" ]]; then
      log_warn "--add was specified but no existing config was found. Creating a new config instead."
      ADD_TO_CONFIG="false"
    fi
  fi
fi

profile_requires_tls() {
  local profile="$1"
  case "$profile" in
    *tls*|*grpc*|*trojan*) return 0 ;;
    *) return 1 ;;
  esac
}

obtain_letsencrypt_cert() {
  local domain="$TLS_DOMAIN"
  local cert_dir="${BASE_DIR}/cert"
  mkdir -p "$cert_dir"

  # Detect public IP
  local public_ip=""
  if command -v curl >/dev/null 2>&1; then
    public_ip="$(curl -s https://api.ipify.org || true)"
  fi
  if [[ -z "$public_ip" ]]; then
    log_error "$(t "无法检测服务器公网 IP，无法验证域名解析。请检查网络后重试。" "Unable to detect server public IP; cannot validate DNS. Please check your network and try again.")"
    exit 1
  fi

  # Resolve domain to IP
  local resolved_ip=""
  if command -v getent >/dev/null 2>&1; then
    resolved_ip="$(getent hosts "$domain" | awk '{print $1; exit}')"
  fi
  if [[ -z "$resolved_ip" ]] && command -v dig >/dev/null 2>&1; then
    resolved_ip="$(dig +short A "$domain" | head -n1)"
  fi
  if [[ -z "$resolved_ip" ]] && command -v nslookup >/dev/null 2>&1; then
    resolved_ip="$(nslookup "$domain" 2>/dev/null | awk '/^Address: /{print $2; exit}')"
  fi
  if [[ -z "$resolved_ip" ]]; then
    log_error "$(t "无法解析域名: $domain。请确认 DNS 记录已生效并指向本服务器。" "Failed to resolve domain: $domain. Please ensure DNS records are set and propagated to this server.")"
    exit 1
  fi

  if [[ "$resolved_ip" != "$public_ip" ]]; then
    log_error "$(t "DNS 解析错误：$domain 当前解析到 $resolved_ip，但本机公网 IP 为 $public_ip。请将该域名的 A 记录指向本机后重试。" "DNS mismatch: $domain currently resolves to $resolved_ip, but this server's public IP is $public_ip. Please point the domain's A record to this server and try again.")"
    exit 1
  fi

  # Check HTTP/HTTPS ports
  if ! is_port_free 80 tcp; then
    log_error "$(t "Let’s Encrypt 模式需要 80 端口空闲，但检测到 80 已被占用。请先停止占用 80 端口的服务后重试。" "Let\'s Encrypt mode requires port 80 to be free, but port 80 is currently in use. Please stop the service using port 80 and try again.")"
    exit 1
  fi

  if ! is_port_free 443 tcp; then
    log_warn "$(t "检测到 443 端口已被占用。这不会影响通过 80 端口的 HTTP-01 验证，但请确认这是预期行为。" "Port 443 is already in use. This will not affect HTTP-01 validation on port 80, but please ensure this is expected.")"
  fi

  # Ensure certbot is available
  if ! command -v certbot >/dev/null 2>&1; then
    log_info "$(t "正在安装 certbot 用于申请 Let’s Encrypt 证书..." "Installing certbot to request a Let\'s Encrypt certificate...")"
    install_dep certbot certbot || true
  fi
  if ! command -v certbot >/dev/null 2>&1; then
    log_error "$(t "未找到 certbot，且自动安装失败。请手动安装 certbot 后重试。" "certbot not found and automatic installation failed. Please install certbot manually and try again.")"
    exit 1
  fi

  log_info "$(t "开始为域名 $domain 申请 Let’s Encrypt 证书..." "Requesting Let\'s Encrypt certificate for domain $domain...")"
  if ! certbot certonly --standalone --non-interactive --agree-tos --register-unsafely-without-email --preferred-challenges http -d "$domain"; then
    log_error "$(t "Let’s Encrypt 证书申请失败。请检查 DNS、网络连通性以及 80 端口是否可从公网访问，然后重试。" "Failed to obtain Let\'s Encrypt certificate. Please check DNS, network connectivity, and that port 80 is reachable from the internet, then try again.")"
    exit 1
  fi

  local le_dir="/etc/letsencrypt/live/${domain}"
  local fullchain="${le_dir}/fullchain.pem"
  local privkey="${le_dir}/privkey.pem"

  if [[ ! -f "$fullchain" || ! -f "$privkey" ]]; then
    log_error "$(t "在 $le_dir 中未找到 fullchain.pem/privkey.pem。请检查 certbot 输出。" "fullchain.pem/privkey.pem not found in $le_dir. Please check certbot output.")"
    exit 1
  fi

  cp "$fullchain" "${cert_dir}/cert.pem"
  cp "$privkey" "${cert_dir}/key.pem"
  chmod 600 "${cert_dir}/cert.pem" "${cert_dir}/key.pem"

  log_info "$(t "Let’s Encrypt 证书已获取并保存至 ${cert_dir}/cert.pem / key.pem" "Let\'s Encrypt certificate obtained and saved to ${cert_dir}/cert.pem / key.pem")"
}

configure_tls_mode_interactive() {
  # Only relevant for TLS-enabled profiles
  if ! profile_requires_tls "$PROFILE"; then
    return 0
  fi

  local input_file="/dev/stdin" interactive_mode="false"

  if [[ -t 0 ]]; then
    interactive_mode="true"
  elif [[ -e /dev/tty ]]; then
    interactive_mode="true"
    input_file="/dev/tty"
  fi

  # Decide certificate mode if not already set via env/CLI
  if [[ -z "${TLS_CERT_MODE:-}" ]]; then
    if [[ "$interactive_mode" == "true" ]]; then
      echo ""
      log_info "$(t "检测到当前方案需要 TLS 证书" "TLS-enabled profile detected")"
      echo "  1) $(t "自动申请 Let’s Encrypt 证书（需已解析好域名，80 端口空闲，推荐）" "Automatically request a Let\'s Encrypt certificate (domain must point here, port 80 free, recommended)")"
      echo "  2) $(t "使用脚本自动生成的自签名证书（适合仅测试/局域网环境或无法使用公网域名的用户）" "Use self-signed certificate (for testing/LAN or when a public domain is not available)")"
      printf "$(t "请选择证书模式 [1-2，默认: 1]: " "Select certificate mode [1-2, default: 1]: ")"

      read -r cert_choice < "$input_file"
      case "${cert_choice:-1}" in
        1) TLS_CERT_MODE="letsencrypt" ;;
        2) TLS_CERT_MODE="self-signed" ;;
        *) TLS_CERT_MODE="letsencrypt" ;;
      esac
    else
      TLS_CERT_MODE="self-signed"
    fi
  fi

  # For letsencrypt/custom modes, ensure we have a domain
  if [[ "${TLS_CERT_MODE}" == "letsencrypt" || "${TLS_CERT_MODE}" == "custom" ]]; then
    if [[ "$interactive_mode" == "true" ]]; then
      while [[ -z "${TLS_DOMAIN:-}" ]]; do
        printf "$(t "请输入你的证书域名 (例如: example.com)：" "Enter your certificate domain (e.g. example.com): ")"

        read -r user_domain < "$input_file"
        TLS_DOMAIN="${user_domain// /}"
        if [[ -z "$TLS_DOMAIN" ]]; then
          log_error "$(t "域名不能为空，请重新输入。" "Domain cannot be empty, please try again.")"
        fi
      done
      log_info "$(t "将使用域名: $TLS_DOMAIN 作为证书与客户端连接主机名" "Using domain: $TLS_DOMAIN for certificate and client connections")"
    else
      if [[ -z "${TLS_DOMAIN:-}" ]]; then
        log_error "TLS_CERT_MODE=${TLS_CERT_MODE} but TLS_DOMAIN is not set. Please set TLS_DOMAIN to your certificate domain."
        exit 1
      fi
    fi
  fi

  # If using Lets Encrypt mode, obtain certificate automatically
  if [[ "${TLS_CERT_MODE}" == "letsencrypt" ]]; then
    obtain_letsencrypt_cert
  fi
}

if [[ "$UPDATE_CORE_ONLY" != "true" ]]; then
  configure_tls_mode_interactive
fi

if [[ "$REBUILD_CONFIG_ONLY" != "true" ]]; then
  if [[ -n "$CORE_VERSION" ]]; then
    CORE_VERSION_NORM="v${CORE_VERSION#v}"
    CORE_URL="https://github.com/${CORE_REPO}/releases/download/${CORE_VERSION_NORM}/${CORE_FILE_NAME}"
    log_info "Using Xray version: $CORE_VERSION_NORM"
  else
    CORE_URL="https://github.com/${CORE_REPO}/releases/latest/download/${CORE_FILE_NAME}"
    log_info "Using latest Xray from $CORE_REPO"
  fi

  log_info "Downloading Xray from: $CORE_URL"

  curl_args=("-fL" "$CORE_URL" -o "$CORE_ZIP_PATH")
  if [[ -n "$PROXY" ]]; then
    log_info "Using proxy for download: $PROXY"
    curl_args=("-fL" "$CORE_URL" -x "$PROXY" -o "$CORE_ZIP_PATH")
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_error "curl is required but not found. Please install curl and retry."
    exit 1
  fi

  if ! curl "${curl_args[@]}"; then
    log_error "Failed to download Xray core."
    exit 1
  fi

  log_info "Extracting Xray to $CORE_BIN_DIR"
  rm -rf "$CORE_BIN_DIR"/*
  if command -v unzip >/dev/null 2>&1; then
    unzip -o "$CORE_ZIP_PATH" -d "$CORE_BIN_DIR" >/dev/null
  else
    log_error "unzip is required but not found. Please install unzip and retry."
    exit 1
  fi

  if [[ ! -x "$CORE_EXE" ]]; then
    log_error "xray executable not found after extraction: $CORE_EXE"
    exit 1
  fi

  if [[ "$UPDATE_CORE_ONLY" == "true" ]]; then
    log_info "Core update-only mode: existing config at $CONFIG_PATH was kept. Firewall rules and service were not modified."
    log_info "To apply the new core, please restart the existing service, for example: systemctl restart ${SERVICE_NAME} (if systemd is available)."
    exit 0
  fi
else
  if [[ ! -x "$CORE_EXE" ]]; then
    log_error "xray executable not found: $CORE_EXE. Please run this script without --rebuild-config-only first to install Xray core."
    exit 1
  fi
fi

if [[ "$PROFILE" == reality* ]]; then
  log_info "Generating Reality X25519 key pair (xray x25519)..."
  if ! x25519_output="$($CORE_EXE x25519 2>&1)"; then
    log_error "Failed to run 'xray x25519'"
    echo "$x25519_output"
    exit 1
  fi

  reality_priv="$(printf '%s\n' "$x25519_output" | sed -n 's/^Private key:[[:space:]]*\([^[:space:]]\+\).*/\1/p')"
  reality_pub="$(printf '%s\n' "$x25519_output" | sed -n 's/^Public key:[[:space:]]*\([^[:space:]]\+\).*/\1/p')"
  if [[ -z "$reality_priv" || -z "$reality_pub" ]]; then
    reality_priv="$(printf '%s\n' "$x25519_output" | sed -n 's/^PrivateKey:[[:space:]]*\([^[:space:]]\+\).*/\1/p')"
    reality_pub="$(printf '%s\n' "$x25519_output" | sed -n 's/^Password:[[:space:]]*\([^[:space:]]\+\).*/\1/p')"
  fi

  if [[ -z "$reality_priv" || -z "$reality_pub" ]]; then
    log_error "Could not parse Reality keys from 'xray x25519' output."
    echo "$x25519_output"
    exit 1
  fi

  log_info "Reality keys generated."
fi

# Prepare to build config
TEMP_CONFIG_PATH="${BASE_DIR}/config.new.json"
REAL_CONFIG_PATH="$CONFIG_PATH"
CONFIG_PATH="$TEMP_CONFIG_PATH" # Temporarily redirect build_config output

log_info "Building config..."

# Build configuration based on selected profile
if command -v build_config_for_profile >/dev/null 2>&1; then
  build_config_for_profile "$PROFILE"
else
  log_error "Profile configuration builder not found. Please check the library file."
  exit 1
fi

if [[ ! -f "$TEMP_CONFIG_PATH" ]]; then
  log_error "Failed to generate configuration file."
  exit 1
fi

# Restore CONFIG_PATH
CONFIG_PATH="$REAL_CONFIG_PATH"

if [[ "$ADD_TO_CONFIG" == "true" && -f "$CONFIG_PATH" ]]; then
  log_info "$(t "正在将新配置合并到现有配置..." "Merging new configuration into existing config...")"
  
  # Use jq to merge inbounds
  if ! command -v jq >/dev/null 2>&1; then
    log_error "$(t "合并配置需要 jq，但系统中未找到该命令。" "jq is required for merging configurations but not found.")"
    exit 1
  fi
  
  # Extract inbounds from new config
  NEW_INBOUNDS=$(jq '.inbounds' "$TEMP_CONFIG_PATH")
  
  # Merge with existing config
  # We append the new inbounds to the existing inbounds array
  if jq --argjson new_inbounds "$NEW_INBOUNDS" '.inbounds += $new_inbounds' "$CONFIG_PATH" > "${CONFIG_PATH}.merged"; then
    mv "${CONFIG_PATH}.merged" "$CONFIG_PATH"
    log_info "$(t "配置合并成功。" "Configuration merged successfully.")"
    inbounds_count=$(jq '.inbounds | length' "$CONFIG_PATH")
    log_info "$(t "当前配置中的入站数量: $inbounds_count" "Total inbounds in config: $inbounds_count")"
  else
    log_error "$(t "使用 jq 合并配置失败。" "Failed to merge configuration with jq.")"
    exit 1
  fi
  
  rm -f "$TEMP_CONFIG_PATH"
else
  mv "$TEMP_CONFIG_PATH" "$CONFIG_PATH"
fi

chmod 600 "$CONFIG_PATH"

log_info "Configuring firewall (if available)"

# Open ports based on profile
if [[ -n "$FIREWALL_PORTS" ]]; then
  if command -v firewall-cmd >/dev/null 2>&1; then
    for port_spec in $FIREWALL_PORTS; do
      if [[ "$port_spec" =~ ^([0-9]+(-[0-9]+)?)/(.+)$ ]]; then
        port="${BASH_REMATCH[1]}"
        proto="${BASH_REMATCH[3]}"
        firewall-cmd --add-port=${port}/${proto} --permanent || true
      fi
    done
    firewall-cmd --reload || true
    log_info "Opened ports in firewalld: $FIREWALL_PORTS"
  elif command -v ufw >/dev/null 2>&1; then
    for port_spec in $FIREWALL_PORTS; do
      if [[ "$port_spec" =~ ^([0-9]+(-[0-9]+)?)/(.+)$ ]]; then
        port="${BASH_REMATCH[1]}"
        proto="${BASH_REMATCH[3]}"
        if [[ "$port" == *-* ]]; then port="${port//-/:}"; fi
        ufw allow ${port}/${proto} || true
      fi
    done
    log_info "Opened ports in ufw: $FIREWALL_PORTS"
  else
    log_warn "No known firewall manager detected (firewalld/ufw). Please ensure the ports are open manually: $FIREWALL_PORTS"
  fi
fi

log_info "Configuring systemd service: ${SERVICE_NAME}"

if ! command -v systemctl >/dev/null 2>&1; then
  log_warn "systemd not found. Starting xray directly in background, but it will NOT persist across reboot."
  nohup "$CORE_EXE" run -config "$CONFIG_PATH" >>"${LOG_DIR}/xray.log" 2>&1 &
else
  cat >/etc/systemd/system/${SERVICE_NAME}.service <<EOF
[Unit]
Description=Xray Server (VLESS Reality + VMess mKCP)
After=network.target

[Service]
Type=simple
User=root
ExecStart=${CORE_EXE} run -config ${CONFIG_PATH}
Restart=on-failure
RestartSec=10s

[Install]
WantedBy=multi-user.target
EOF

  systemctl daemon-reload
  systemctl enable ${SERVICE_NAME}
  systemctl restart ${SERVICE_NAME}

  sleep 1
  if systemctl is-active --quiet ${SERVICE_NAME}; then
    log_info "systemd service ${SERVICE_NAME} is running."
  else
    log_warn "systemd service ${SERVICE_NAME} is not active. Please check: journalctl -u ${SERVICE_NAME} -xe"
  fi
fi

public_ip=""
if command -v curl >/dev/null 2>&1; then
  public_ip="$(curl -s https://api.ipify.org)" || true
fi
if [[ -z "$public_ip" ]]; then
  public_ip="$(t "（公网 IP 未知，请自行检查）" "(public IP unknown, please check yourself)")"
fi

# Generate URLs and summary based on profile
generate_url_for_profile() {
  local profile="$1"
  local url=""
  
  case "$profile" in
    reality-kcp|reality-only)
      local vless_name="xray.owokit.com-VLESS-Reality"
      url="vless://${UUID}@${public_ip}:${REALITY_PORT}?encryption=none&flow=xtls-rprx-vision&security=reality&sni=${REALITY_SERVER_NAME}&fp=chrome&pbk=${reality_pub}&sid=${REALITY_SHORT_ID}&spx=%2F&type=tcp#${vless_name}"
      echo "$url"
      if [[ "$profile" == "reality-kcp" ]]; then
        local vmess_name="xray.owokit.com-VMess-mKCP-wechat-video"
        local vmess_json=$(cat <<JSON
{
  "v": "2",
  "ps": "${vmess_name}",
  "add": "${public_ip}",
  "port": "${VMESS_KCP_PORT}",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "kcp",
  "type": "wechat-video",
  "host": "",
  "path": "",
  "tls": "",
  "sni": "",
  "alpn": "",
  "fp": ""
}
JSON
)
        local vmess_b64="$(printf '%s' "$vmess_json" | base64 -w0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
        echo "vmess://${vmess_b64}"
      fi
      ;;
    *vmess*|*vless*|*trojan*|shadowsocks|kcp-only)
      # For other protocols, generate appropriate URLs
      local port="${MAIN_PORT:-${REALITY_PORT:-${VMESS_KCP_PORT}}}"
      local server_host="$public_ip"

      # If user configured a domain (custom CA or Lets Encrypt), prefer domain in URLs
      if [[ ( "${TLS_CERT_MODE:-}" == "custom" || "${TLS_CERT_MODE:-}" == "letsencrypt" ) && -n "${TLS_DOMAIN:-}" ]]; then
        server_host="$TLS_DOMAIN"
      fi
      
      # Fix for dynamic port profiles: ensure port is within range 20000-30000
      if [[ "$profile" == *dynamic* ]]; then
        port=$((RANDOM % 10000 + 20000))
      fi

      case "$profile" in
        *vmess*)
          local net="tcp" type="none" path="" host="" tls=""
          
          if [[ "$profile" == *tls* ]]; then tls="tls"; fi
          
          case "$profile" in
            *mkcp*) net="kcp"; type="wechat-video" ;;
            *quic*) net="quic"; type="none" ;;
            *ws*)   net="ws"; path="/ws" ;;
            *grpc*) net="grpc"; path="grpc" ;;
            *h2*)   net="h2"; path="/h2"; host="example.com" ;;
          esac

          local vmess_json=$(cat <<JSON
{
  "v": "2",
  "ps": "xray.owokit.com-${PROFILE_DISPLAY_NAME}",
  "add": "${server_host}",
  "port": "${port}",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "${net}",
  "type": "${type}",
  "host": "${host}",
  "path": "${path}",
  "tls": "${tls}",
  "sni": "",
  "alpn": "",
  "fp": ""
}
JSON
)
          local vmess_b64="$(printf '%s' "$vmess_json" | base64 -w0 2>/dev/null || printf '%s' "$vmess_json" | base64 | tr -d '\n')"
          echo "vmess://${vmess_b64}"
          ;;
        *trojan*)
          local query_args=""
          if [[ "$profile" == *ws* ]]; then
            query_args="?security=tls&type=ws&path=/trojan"
          elif [[ "$profile" == *grpc* ]]; then
            query_args="?security=tls&type=grpc&serviceName=grpc"
          elif [[ "$profile" == *h2* ]]; then
            query_args="?security=tls&type=h2&path=/trojan"
          else
             # Default generic trojan (tcp+tls)
             query_args="?security=tls&type=tcp"
          fi
          echo "trojan://${UUID}@${server_host}:${port}${query_args}#xray.owokit.com-${PROFILE_DISPLAY_NAME}"
          ;;
        shadowsocks)
          # Shadowsocks URL format: ss://base64(method:password)@server:port#name
          local ss_str="aes-256-gcm:${UUID}"
          local ss_b64="$(printf '%s' "$ss_str" | base64 -w0 2>/dev/null || printf '%s' "$ss_str" | base64 | tr -d '\n')"
          echo "ss://${ss_b64}@${server_host}:${port}#xray.owokit.com-Shadowsocks"
          ;;
      esac
      ;;
  esac
}

# Save URLs to file
urls=($(generate_url_for_profile "$PROFILE"))

if [[ "$ADD_TO_CONFIG" == "true" ]]; then
  # Append URLs if merging
  printf "%s\n" "${urls[@]}" >> "$LINKS_FILE"
else
  # Overwrite if new config
  printf "%s\n" "${urls[@]}" > "$LINKS_FILE"
fi

# Save port info
# If merging, we need to read existing ports and append new ones
EXISTING_FIREWALL_PORTS=""
if [[ "$ADD_TO_CONFIG" == "true" && -f "$PORTS_FILE" ]]; then
  # Read existing FIREWALL_PORTS
  EXISTING_FIREWALL_PORTS=$(grep "^FIREWALL_PORTS=" "$PORTS_FILE" | cut -d'=' -f2-)
fi

# Combine ports
if [[ -n "$EXISTING_FIREWALL_PORTS" ]]; then
  # Avoid duplicates in FIREWALL_PORTS string roughly
  FULL_FIREWALL_PORTS="$EXISTING_FIREWALL_PORTS $FIREWALL_PORTS"
else
  FULL_FIREWALL_PORTS="$FIREWALL_PORTS"
fi

{
  if [[ "$ADD_TO_CONFIG" == "true" ]]; then
    # Keep existing profile name in file but maybe append? 
    # Actually ports.env is mostly for uninstallation.
    # We will just append the new profile to a list or something?
    # For simplicity, let's just keep the last profile name or append it.
    echo "PROFILE=${PROFILE}" # This might overwrite, but it's okay for now.
  else
    echo "PROFILE=${PROFILE}"
  fi
  echo "MAIN_PORT=${MAIN_PORT:-}"
  echo "REALITY_PORT=${REALITY_PORT:-}"
  echo "VMESS_KCP_PORT=${VMESS_KCP_PORT:-}"
  echo "FIREWALL_PORTS=${FULL_FIREWALL_PORTS}"
} >"$PORTS_FILE"
chmod 600 "$PORTS_FILE"
log_info "$(t "端口信息已保存到: $PORTS_FILE" "Port info has been saved to: $PORTS_FILE")"
log_info "$(t "所有链接已保存到: $LINKS_FILE" "All URLs have been saved to: $LINKS_FILE")"

printf "\n%s%s%s\n" "${COLOR_SUM_TITLE}" "$(t "================= Xray 服务器部署完成（Linux） =================" "================= Xray server deployed (Linux) =================")" "${COLOR_RESET}"
printf "%s%s%s%s\n" "${COLOR_SUM_TITLE}" "$(t "服务器公网 IP: " "Server public IP: ")" "${public_ip}" "${COLOR_RESET}"
printf "%s%s%s%s\n\n" "${COLOR_SUM_TITLE}" "$(t "部署方案: " "Profile: ")" "${PROFILE_DISPLAY_NAME}" "${COLOR_RESET}"

# Print summary based on profile
case "$PROFILE" in
  reality-kcp|reality-only)
    printf "%s%s%s\n" "${COLOR_SUM_SECTION}" "$(t "[1] VLESS Reality" "[1] VLESS Reality")" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口:" "Port:")" "${REALITY_PORT}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID:" "${UUID}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "流控:" "Flow:")" "xtls-rprx-vision" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "目标站:" "Dest:")" "${REALITY_DEST}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "SNI:" "${REALITY_SERVER_NAME}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "shortId:" "${REALITY_SHORT_ID}" "${COLOR_RESET}"
    printf "%s  %-11s%s\n" "${COLOR_SUM_LABEL}" "$(t "公钥:" "publicKey:")" "${COLOR_RESET}"
    printf "%s    %s%s\n" "${COLOR_SUM_HIGHLIGHT}" "${reality_pub}" "${COLOR_RESET}"
    if [[ "$PROFILE" == "reality-kcp" ]]; then
      printf "\n%s%s%s\n" "${COLOR_SUM_SECTION}" "$(t "[2] VMess mKCP + wechat-video" "[2] VMess mKCP + wechat-video")" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口(UDP):" "Port(UDP):")" "${VMESS_KCP_PORT}" "${COLOR_RESET}"
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID:" "${UUID}" "${COLOR_RESET}"
    fi
    ;;
  *dynamic*)
    printf "%s%s%s\n" "${COLOR_SUM_SECTION}" "${PROFILE_DISPLAY_NAME}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口范围:" "Port Range:")" "20000-30000" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID:" "${UUID}" "${COLOR_RESET}"
    ;;
  shadowsocks)
    printf "%s%s%s\n" "${COLOR_SUM_SECTION}" "Shadowsocks (AES-256-GCM)" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口:" "Port:")" "${MAIN_PORT}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "密码:" "Password:")" "${UUID}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "加密:" "Encryption:")" "aes-256-gcm" "${COLOR_RESET}"
    ;;
  *)
    printf "%s%s%s\n" "${COLOR_SUM_SECTION}" "${PROFILE_DISPLAY_NAME}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "地址:" "Address:")" "${public_ip}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "端口:" "Port:")" "${MAIN_PORT:-${REALITY_PORT:-${VMESS_KCP_PORT}}}" "${COLOR_RESET}"
    printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "UUID/Password:" "${UUID}" "${COLOR_RESET}"
    if [[ "$PROFILE" == *tls* ]]; then
      tls_desc_zh="已启用（自签名证书）"
      tls_desc_en="Enabled (self-signed)"
      case "${TLS_CERT_MODE:-self-signed}" in
        letsencrypt)
          tls_desc_zh="已启用（Let’s Encrypt 证书）"
          tls_desc_en="Enabled (Let\'s Encrypt certificate)"
          ;;
        custom)
          tls_desc_zh="已启用（自有 CA 证书）"
          tls_desc_en="Enabled (custom CA certificate)"
          ;;
      esac
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "TLS:" "TLS:")" "$(t "$tls_desc_zh" "$tls_desc_en")" "${COLOR_RESET}"
    fi
    ;;
esac

printf "\n%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "订阅链接:" "URLs:")" "${COLOR_RESET}"
for url in "${urls[@]}"; do
  printf "%s%s%s\n" "${COLOR_SUM_URL}" "$url" "${COLOR_RESET}"
done

printf "\n%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "链接文件:   ${LINKS_FILE}" "links file:   ${LINKS_FILE}")" "${COLOR_RESET}"
printf "%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "配置文件:  ${CONFIG_PATH}" "config file:  ${CONFIG_PATH}")" "${COLOR_RESET}"
printf "%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "日志目录:      ${LOG_DIR}" "log dir:      ${LOG_DIR}")" "${COLOR_RESET}"
printf "%s%s%s\n" "${COLOR_SUM_LABEL}" "$(t "服务:        ${SERVICE_NAME} (systemd)" "service:      ${SERVICE_NAME} (systemd)")" "${COLOR_RESET}"
printf "%s%s%s\n" "${COLOR_SUM_TITLE}" "$(t "========================================================" "========================================================")" "${COLOR_RESET}"
