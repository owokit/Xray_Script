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
