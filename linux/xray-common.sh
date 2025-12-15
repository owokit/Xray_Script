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
  install_dep openssl openssl
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
