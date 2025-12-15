
install_xray_core() {
  local core_version="$1"
  local core_zip_path="$2"
  local core_bin_dir="$3"
  local core_exe="$4"
  local proxy="$5"
  local update_core_only="$6"

  local core_repo="XTLS/Xray-core"
  local core_file_name="Xray-linux-64.zip"
  local core_url=""

  if [[ -n "$core_version" ]]; then
    local core_version_norm="v${core_version#v}"
    core_url="https://github.com/${core_repo}/releases/download/${core_version_norm}/${core_file_name}"
    log_info "Using Xray version: $core_version_norm"
  else
    core_url="https://github.com/${core_repo}/releases/latest/download/${core_file_name}"
    log_info "Using latest Xray from $core_repo"
  fi

  log_info "Downloading Xray from: $core_url"

  local curl_args=("-fL" "$core_url" -o "$core_zip_path")
  if [[ -n "$proxy" ]]; then
    log_info "Using proxy for download: $proxy"
    curl_args=("-fL" "$core_url" -x "$proxy" -o "$core_zip_path")
  fi

  if ! command -v curl >/dev/null 2>&1; then
    log_error "curl is required but not found. Please install curl and retry."
    exit 1
  fi

  if ! curl "${curl_args[@]}"; then
    log_error "Failed to download Xray core."
    exit 1
  fi

  log_info "Extracting Xray to $core_bin_dir"
  rm -rf "$core_bin_dir"/*
  if command -v unzip >/dev/null 2>&1; then
    unzip -o "$core_zip_path" -d "$core_bin_dir" >/dev/null
  else
    log_error "unzip is required but not found. Please install unzip and retry."
    exit 1
  fi

  if [[ ! -x "$core_exe" ]]; then
    log_error "xray executable not found after extraction: $core_exe"
    exit 1
  fi

  if [[ "$update_core_only" == "true" ]]; then
    log_info "Core update-only mode: existing config was kept. Firewall rules and service were not modified."
    log_info "To apply the new core, please restart the existing service."
    exit 0
  fi
}
