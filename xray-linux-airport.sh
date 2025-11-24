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

# Load profile library
PROFILE_LIB="${BASE_DIR}/xray-profiles-lib.sh"
if [[ ! -f "$PROFILE_LIB" ]]; then
  PROFILE_LIB="$(dirname "$0")/xray-profiles-lib.sh"
fi
if [[ ! -f "$PROFILE_LIB" ]]; then
  log_info "Profile library not found locally, downloading from GitHub..."
  PROFILE_LIB="${BASE_DIR}/xray-profiles-lib.sh"
  if ! curl -fsSL "https://github.com/owokit/Xray_Script/raw/main/xray-profiles-lib.sh" -o "$PROFILE_LIB"; then
    log_error "Failed to download profile library. Please check your network or download xray-profiles-lib.sh manually to $BASE_DIR."
    exit 1
  fi
fi
if [[ -f "$PROFILE_LIB" ]]; then
  source "$PROFILE_LIB"
else
  log_error "Profile library not found. Please check that xray-profiles-lib.sh exists under $BASE_DIR."
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
        log_warn "Config file already exists at $CONFIG_PATH."
        echo "  1) Overwrite (Delete existing config)"
        echo "  2) Add (Merge new profile to existing config)"
        echo "  3) Cancel"
        printf "Enter option [1-3, default: 3]: "
        read -r conflict_choice < "$input_file"
        case "${conflict_choice:-3}" in
          1) FORCE_REBUILD_CONFIG="true" ;;
          2) ADD_TO_CONFIG="true" ;;
          *) log_error "Operation cancelled by user."; exit 1 ;;
        esac
      else
        log_error "Config file already exists at $CONFIG_PATH. Use --keep-config to reuse it, --force-rebuild-config to overwrite it, or --add to merge new profile."
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

if [[ "$UPDATE_CORE_ONLY" != "true" ]]; then
  if [[ -z "$UUID" ]]; then
    if command -v uuidgen >/dev/null 2>&1; then
      UUID="$(uuidgen)"
    else
      UUID="$(cat /proc/sys/kernel/random/uuid)"
    fi
    log_info "Generated UUID: $UUID"
  fi

  validate_port_value "REALITY_PORT" "$REALITY_PORT"
  validate_port_value "VMESS_KCP_PORT" "$VMESS_KCP_PORT"

  REALITY_PORT="$(ensure_port "$REALITY_PORT" tcp)"
  VMESS_KCP_PORT="$(ensure_port "$VMESS_KCP_PORT" udp)"

  PROFILE="${PROFILE,,}"
  
  # Initialize required variables for config generation
  CERT_FILE=""
  KEY_FILE=""
  FIREWALL_PORTS=""
  PROFILE_DISPLAY_NAME=""

  if [[ "$REALITY_PORT" == "$VMESS_KCP_PORT" ]]; then
    VMESS_KCP_PORT="$(ensure_port 0 udp)"
    log_warn "VMess KCP port conflicts with Reality port, changed to: $VMESS_KCP_PORT"
  fi

  if [[ -z "$REALITY_SHORT_ID" ]]; then
    REALITY_SHORT_ID="$(openssl rand -hex 4 2>/dev/null || od -An -N4 -tx1 /dev/urandom | tr -d ' \n')"
    log_info "Generated Reality shortId: $REALITY_SHORT_ID"
  fi
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
  log_info "Merging new configuration into existing config..."
  
  # Use jq to merge inbounds
  if ! command -v jq >/dev/null 2>&1; then
    log_error "jq is required for merging configurations but not found."
    exit 1
  fi
  
  # Extract inbounds from new config
  NEW_INBOUNDS=$(jq '.inbounds' "$TEMP_CONFIG_PATH")
  
  # Merge with existing config
  # We append the new inbounds to the existing inbounds array
  if jq --argjson new_inbounds "$NEW_INBOUNDS" '.inbounds += $new_inbounds' "$CONFIG_PATH" > "${CONFIG_PATH}.merged"; then
    mv "${CONFIG_PATH}.merged" "$CONFIG_PATH"
    log_info "Configuration merged successfully."
  else
    log_error "Failed to merge configuration with jq."
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
      case "$profile" in
        *vmess*)
          local vmess_json=$(cat <<JSON
{
  "v": "2",
  "ps": "xray.owokit.com-${PROFILE_DISPLAY_NAME}",
  "add": "${public_ip}",
  "port": "${port}",
  "id": "${UUID}",
  "aid": "0",
  "scy": "auto",
  "net": "tcp",
  "type": "none",
  "host": "",
  "path": "",
  "tls": "$([[ "$profile" == *tls* ]] && echo "tls" || echo "")",
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
          echo "trojan://${UUID}@${public_ip}:${port}#xray.owokit.com-${PROFILE_DISPLAY_NAME}"
          ;;
        shadowsocks)
          # Shadowsocks URL format: ss://base64(method:password)@server:port#name
          local ss_str="aes-256-gcm:${UUID}"
          local ss_b64="$(printf '%s' "$ss_str" | base64 -w0 2>/dev/null || printf '%s' "$ss_str" | base64 | tr -d '\n')"
          echo "ss://${ss_b64}@${public_ip}:${port}#xray.owokit.com-Shadowsocks"
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
      printf "%s  %-11s %s%s\n" "${COLOR_SUM_LABEL}" "$(t "TLS:" "TLS:")" "$(t "已启用（自签名证书）" "Enabled (self-signed)")" "${COLOR_RESET}"
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
