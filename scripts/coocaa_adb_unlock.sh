#!/usr/bin/env bash
# Seçkin Kılınç
# XemBiLL
# xembill at gmail.com
# =============================================================
#  coocaa_adb_unlock_forUmit.sh — CoocaaOS WiFi ADB Unlock (macOS/Linux)
# =============================================================
#  Keşif: SystemSettings.apk → BackdoorAdapter.java
#    SystemUtils.setWifiAdbOpen()
#    → SystemProperties.set("sys.special.func", "1")
#
#  Gizli menü adımları GEREKMEZ:
#    Sistem → Logo 8-9x → şifre 2281 → ADB Aç
#
#  Kullanım:
#    ./coocaa_adb_unlock.sh                        # USB bağlı cihaz
#    ./coocaa_adb_unlock.sh --ip 10.13.180.165     # TCP bağlantısı
#    ./coocaa_adb_unlock.sh --ip 10.13.180.165 --persist
#    ./coocaa_adb_unlock.sh --scan                 # Ağı tara
#    ./coocaa_adb_unlock.sh --scan --network 192.168.1.0/24
# =============================================================

set -euo pipefail

ADB="${ADB_BIN:-adb}"
PORT="${ADB_PORT:-5555}"
COOCAA_PROP="sys.special.func"
COOCAA_VAL="1"
PERSIST_PATH="/data/local/userinit.d/01_coocaa_adb.sh"
PERSIST_TMP="/data/local/tmp/01_coocaa_adb.sh"

OPT_IP=""
OPT_PERSIST=0
OPT_SCAN=0
OPT_NETWORK=""
SERIAL=""

# ── Renk ──────────────────────────────────────────────────────
if [[ -t 1 ]]; then
  C_OK="\033[0;32m"
  C_FAIL="\033[0;31m"
  C_STEP="\033[0;36m"
  C_RST="\033[0m"
else
  C_OK="" C_FAIL="" C_STEP="" C_RST=""
fi

ok()   { echo -e "  ${C_OK}✓${C_RST} $*"; }
fail() { echo -e "  ${C_FAIL}✗${C_RST} $*"; }
step() { echo -e "  ${C_STEP}→${C_RST} $*"; }

# ── Yardım ────────────────────────────────────────────────────
usage() {
  cat <<EOF
Kullanim:
  $(basename "$0") [seçenekler]

Seçenekler:
  --ip <ip>           Cihaz IP adresi (TCP bağlantısı)
  --persist           Boot kalıcılığı yükle (userinit.d)
  --scan              Ağı tara, ADB portu açık cihaz bul
  --network <cidr>    Taranacak ağ (örn: 192.168.1.0/24)
  --port <port>       ADB TCP portu (varsayılan: 5555)
  -h, --help          Bu yardım

Örnekler:
  $(basename "$0") --ip 10.13.180.165
  $(basename "$0") --ip 10.13.180.165 --persist
  $(basename "$0") --scan
  $(basename "$0") --scan --network 10.13.180.0/24

Ortam Değişkenleri:
  ADB_BIN   adb binary yolu (varsayılan: adb)
  ADB_PORT  TCP portu (varsayılan: 5555)
EOF
}

# ── Argüman ayrıştırma ─────────────────────────────────────────
parse_args() {
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ip)       OPT_IP="$2";      shift 2 ;;
      --persist)  OPT_PERSIST=1;    shift   ;;
      --scan)     OPT_SCAN=1;       shift   ;;
      --network)  OPT_NETWORK="$2"; shift 2 ;;
      --port)     PORT="$2";        shift 2 ;;
      -h|--help)  usage; exit 0            ;;
      *)          echo "Bilinmeyen: $1"; usage; exit 1 ;;
    esac
  done
}

# ── ADB yardımcıları ───────────────────────────────────────────
adb_cmd() {
  if [[ -n "$SERIAL" ]]; then
    "$ADB" -s "$SERIAL" "$@" 2>/dev/null || true
  else
    "$ADB" "$@" 2>/dev/null || true
  fi
}

adb_shell() {
  adb_cmd shell "$@"
}

adb_shell_root() {
  adb_shell su 0 "$@"
}

connect_tcp() {
  local ip="$1"
  step "TCP bağlanılıyor: ${ip}:${PORT}"
  local out
  out=$("$ADB" connect "${ip}:${PORT}" 2>&1)
  if echo "$out" | grep -qi "connected"; then
    ok "Bağlandı: ${ip}:${PORT}"
    SERIAL="${ip}:${PORT}"
    return 0
  fi
  fail "Bağlanılamadı: $out"
  return 1
}

# ── Cihaz seçimi ───────────────────────────────────────────────
pick_device() {
  if [[ -n "$OPT_IP" ]]; then
    connect_tcp "$OPT_IP"
    return
  fi

  # USB cihazları listele
  local devices
  devices=$("$ADB" devices 2>/dev/null | awk 'NR>1 && /device$/ {print $1}')
  local count
  count=$(echo "$devices" | grep -c . || true)

  if [[ $count -eq 0 ]]; then
    fail "Bağlı ADB cihazı yok. USB takın veya --ip kullanın."
    exit 1
  elif [[ $count -eq 1 ]]; then
    SERIAL="$devices"
    ok "Cihaz: $SERIAL"
  else
    echo "  Birden fazla cihaz:"
    local i=0
    while IFS= read -r d; do
      echo "    [$i] $d"
      ((i++)) || true
    done <<< "$devices"
    read -r -p "  Seçin [0]: " idx
    idx="${idx:-0}"
    SERIAL=$(echo "$devices" | sed -n "$((idx+1))p")
    ok "Seçildi: $SERIAL"
  fi
}

# ── Cihaz bilgisi ──────────────────────────────────────────────
device_info() {
  local mfr model
  mfr=$(adb_shell getprop ro.product.manufacturer | tr -d '\r')
  model=$(adb_shell getprop ro.product.model | tr -d '\r')
  echo "  Üretici  : ${mfr:-?}"
  echo "  Model    : ${model:-?}"

  local has_coocaa
  has_coocaa=$(adb_shell pm list packages com.coocaa 2>/dev/null | grep -c "com.coocaa" || true)
  if [[ "$has_coocaa" -gt 0 ]]; then
    echo "  CoocaaOS : Tespit edildi ✓"
  else
    echo "  CoocaaOS : Tespit edilemedi (yine de deneniyor)"
  fi
}

# ── Ana Kilit Açma ─────────────────────────────────────────────
unlock_adb() {
  step "setprop ${COOCAA_PROP}=${COOCAA_VAL} uygulanıyor..."
  adb_shell_root "setprop ${COOCAA_PROP} ${COOCAA_VAL}"
  adb_shell_root "settings put global adb_enabled 1"
  adb_shell_root "settings put global adb_tcp_port ${PORT}"
  adb_shell_root "setprop service.adb.tcp.port ${PORT}"

  sleep 1

  local val
  val=$(adb_shell getprop "${COOCAA_PROP}" | tr -d '\r')
  if [[ "$val" == "$COOCAA_VAL" ]]; then
    ok "WiFi ADB aktif! (${COOCAA_PROP}=${val})"
    return 0
  else
    fail "Değer beklenen '${COOCAA_VAL}', gerçek '${val:-boş}'"
    return 1
  fi
}

get_wifi_ip() {
  adb_shell "ip -o -4 addr show wlan0 2>/dev/null | awk '{print \$4}' | cut -d/ -f1 | head -1" | tr -d '\r'
}

# ── Kalıcılık ──────────────────────────────────────────────────
install_persist() {
  step "Boot kalıcılığı yükleniyor: ${PERSIST_PATH}"

  local tmp_local
  tmp_local=$(mktemp /tmp/coocaa_persist_XXXXXX.sh)
  cat > "$tmp_local" <<'SCRIPT'
#!/system/bin/sh
# CoocaaOS WiFi ADB kalici aktiflestiricisi
settings put global adb_enabled 1
settings put global adb_tcp_port 5555
setprop service.adb.tcp.port 5555
setprop sys.special.func 1
SCRIPT

  "$ADB" ${SERIAL:+-s "$SERIAL"} shell su 0 "mkdir -p /data/local/userinit.d" 2>/dev/null || true
  "$ADB" ${SERIAL:+-s "$SERIAL"} push "$tmp_local" "$PERSIST_TMP" >/dev/null
  adb_shell_root "mv ${PERSIST_TMP} ${PERSIST_PATH}"
  adb_shell_root "chmod 755 ${PERSIST_PATH}"
  rm -f "$tmp_local"

  ok "Yüklendi: ${PERSIST_PATH}"
}

# ── Ağ Tarama ──────────────────────────────────────────────────
scan_network() {
  local cidr="$1"

  # CIDR boşsa yerel ağı tahmin et
  if [[ -z "$cidr" ]]; then
    local local_ip
    local_ip=$(ip route get 8.8.8.8 2>/dev/null | awk '/src/ {print $7; exit}' || \
               ifconfig | awk '/inet / && !/127.0.0.1/ {print $2; exit}' || echo "")
    if [[ -z "$local_ip" ]]; then
      fail "Yerel IP tespit edilemedi, --network kullanın."
      exit 1
    fi
    local prefix
    prefix="${local_ip%.*}"
    cidr="${prefix}.0/24"
  fi

  step "Taranıyor: ${cidr} (port ${PORT})..."

  # /24 için son okteti 1-254 arası dene
  local base="${cidr%.*}"
  local found=()

  scan_host() {
    local ip="$1"
    if (echo >/dev/tcp/"$ip"/"$PORT") 2>/dev/null; then
      echo "$ip"
    fi
  }
  export -f scan_host

  # Paralel tarama (bash /dev/tcp)
  local pids=()
  local results=()
  for i in $(seq 1 254); do
    local ip="${base}.${i}"
    (
      if (echo >/dev/tcp/"$ip"/$PORT) 2>/dev/null; then
        echo "$ip"
      fi
    ) &
    pids+=($!)
  done

  for pid in "${pids[@]}"; do
    local out
    out=$(wait "$pid" 2>/dev/null; jobs -p "$pid" 2>/dev/null) || true
  done

  # wait + subshell sonuçlarını topla (macOS uyumlu alternatif)
  local tmpdir
  tmpdir=$(mktemp -d)
  for i in $(seq 1 254); do
    local ip="${base}.${i}"
    (
      if (echo >/dev/tcp/"$ip"/$PORT) 2>/dev/null; then
        echo "$ip" > "${tmpdir}/${i}"
      fi
    ) &
  done
  wait

  local found_ips=()
  for f in "${tmpdir}"/*; do
    [[ -f "$f" ]] || continue
    local ip
    ip=$(cat "$f")
    echo "    ADB port açık: ${ip}:${PORT}"
    found_ips+=("$ip")
  done
  rm -rf "$tmpdir"

  if [[ ${#found_ips[@]} -eq 0 ]]; then
    fail "Hiç cihaz bulunamadı."
    exit 1
  fi

  echo "  ${#found_ips[@]} cihaz bulundu."

  if [[ ${#found_ips[@]} -eq 1 ]]; then
    OPT_IP="${found_ips[0]}"
  else
    local i=0
    for ip in "${found_ips[@]}"; do
      echo "    [$i] $ip"
      ((i++)) || true
    done
    read -r -p "  Unlock için seçin [0]: " idx
    idx="${idx:-0}"
    OPT_IP="${found_ips[$idx]}"
  fi
}

# ── Ana Akış ──────────────────────────────────────────────────
main() {
  parse_args "$@"

  echo "======================================================="
  echo "  CoocaaOS WiFi ADB Unlock"
  echo "  sys.special.func bypass"
  echo "======================================================="

  if [[ "$OPT_SCAN" -eq 1 ]]; then
    echo ""
    echo "[TARAMA MODU]"
    scan_network "$OPT_NETWORK"
  fi

  echo ""
  echo "[BAĞLANTI]"
  pick_device

  echo ""
  echo "[CİHAZ BİLGİSİ]"
  device_info

  echo ""
  echo "[KİLİT AÇMA]"
  if ! unlock_adb; then
    fail "Unlock başarısız. Root erişimi gerekiyor olabilir."
    exit 1
  fi

  # USB ise TCP'ye geç
  if [[ "$SERIAL" != *":"* ]]; then
    local wifi_ip
    wifi_ip=$(get_wifi_ip)
    if [[ -n "$wifi_ip" ]]; then
      step "WiFi IP: ${wifi_ip}, TCP'ye geçiliyor..."
      connect_tcp "$wifi_ip" || true
    fi
  fi

  if [[ "$OPT_PERSIST" -eq 1 ]]; then
    echo ""
    echo "[KALICILIK]"
    install_persist
  fi

  local ip_display="${SERIAL%%:*}"
  echo ""
  echo "======================================================="
  echo "  TAMAMLANDI"
  [[ -n "$ip_display" ]] && echo "  Bağlantı : adb connect ${ip_display}:${PORT}"
  echo "  Şifre    : GEREKMEZ (setprop bypass aktif)"
  [[ "$OPT_PERSIST" -eq 1 ]] && echo "  Kalıcı   : Her boot'ta otomatik açılır"
  echo "======================================================="
}

main "$@"
