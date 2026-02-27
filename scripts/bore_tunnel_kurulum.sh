#!/usr/bin/env bash
# Seçkin Kılınç
# XemBiLL
# xembill at gmail.com
# =============================================================
#  bore_tunnel_kurulum.sh — Bore Reverse Tunnel Tam Kurulum
#  macOS / Linux
# =============================================================
#
#  MİMARİ:
#
#    Araç (tablet ADB:5555)
#         │
#         │  bore local <VPS_PORT> --to <VPS_IP>
#         ▼
#    VPS <VPS_IP>:<VPS_PORT>   ← bore server (systemd)
#         ▲
#         │  adb connect <VPS_IP>:<VPS_PORT>
#    Mac / PC (her ağdan)
#
#  KOMUTLAR:
#    ./bore_tunnel_kurulum.sh arac          # Araçtaki kurulum (ADB üzerinden)
#    ./bore_tunnel_kurulum.sh vps           # VPS'e bore server kurulumu (SSH)
#    ./bore_tunnel_kurulum.sh baglan        # PC'den araca bağlan
#    ./bore_tunnel_kurulum.sh durum         # Tunnel durumu kontrol
#    ./bore_tunnel_kurulum.sh kaldir        # Araçtan tunnel kaldır
#
#  YAPILANDIRMA (değiştirilebilir):
# =============================================================

# ── Yapılandırma — İSTEĞE GÖRE DEĞİŞTİRİN ─────────────────────
VPS_IP="${VPS_IP:-20.229.185.95}"
VPS_PORT="${VPS_PORT:-5555}"
VPS_SSH_USER="${VPS_SSH_USER:-root}"
VPS_SSH_PORT="${VPS_SSH_PORT:-22}"
ADB_PORT="${ADB_PORT:-5555}"
BORE_DOWNLOAD_URL="https://github.com/ekzhang/bore/releases/latest/download/bore-aarch64-unknown-linux-musl.tar.gz"
# ──────────────────────────────────────────────────────────────

set -euo pipefail

ADB="${ADB_BIN:-adb}"
SERIAL=""

# Renk
if [[ -t 1 ]]; then
  C_OK="\033[0;32m"; C_FAIL="\033[0;31m"; C_STEP="\033[0;36m"
  C_WARN="\033[0;33m"; C_HEAD="\033[1;37m"; C_RST="\033[0m"
else
  C_OK="" C_FAIL="" C_STEP="" C_WARN="" C_HEAD="" C_RST=""
fi

ok()   { echo -e "  ${C_OK}✓${C_RST} $*"; }
fail() { echo -e "  ${C_FAIL}✗${C_RST} $*"; }
step() { echo -e "  ${C_STEP}→${C_RST} $*"; }
warn() { echo -e "  ${C_WARN}!${C_RST} $*"; }
head() { echo -e "\n${C_HEAD}[$*]${C_RST}"; }

# ── Kullanım ──────────────────────────────────────────────────
usage() {
  cat <<EOF

${C_HEAD}Bore Reverse Tunnel Kurulum Aracı${C_RST}

Kullanım:
  $(basename "$0") <komut> [seçenekler]

Komutlar:
  arac      Araç tabletine bore + watchdog + boot script kur
  vps       VPS'e bore server kur (SSH ile)
  baglan    Bu PC'den araca ADB bağlan
  durum     Tunnel ve ADB durumunu kontrol et
  kaldir    Araçtan bore tunnel dosyalarını kaldır

Seçenekler:
  --ip <ip>      Araç IP (USB yoksa TCP bağlantısı için)
  --serial <s>   ADB serial (birden fazla cihazda)
  -h, --help     Bu yardım

Ortam Değişkenleri (yapılandırma):
  VPS_IP        VPS IP adresi     (şu an: ${VPS_IP})
  VPS_PORT      Bore/ADB portu    (şu an: ${VPS_PORT})
  VPS_SSH_USER  VPS SSH kullanıcı (şu an: ${VPS_SSH_USER})
  VPS_SSH_PORT  VPS SSH portu     (şu an: ${VPS_SSH_PORT})

Örnekler:
  # Tam kurulum (USB bağlı araç):
  $(basename "$0") arac
  $(basename "$0") vps

  # Farklı VPS ile:
  VPS_IP=1.2.3.4 VPS_PORT=5556 $(basename "$0") arac

  # TCP bağlı araç:
  $(basename "$0") arac --ip 10.13.180.165

  # Bağlan:
  $(basename "$0") baglan

EOF
}

# ── ADB Yardımcıları ──────────────────────────────────────────
adb_cmd() {
  if [[ -n "$SERIAL" ]]; then
    "$ADB" -s "$SERIAL" "$@" 2>/dev/null || true
  else
    "$ADB" "$@" 2>/dev/null || true
  fi
}
adb_shell()      { adb_cmd shell "$@"; }
adb_shell_root() { adb_shell su 0 "$@"; }
adb_push()       { adb_cmd push "$@"; }

connect_tcp() {
  local ip="$1"
  step "TCP bağlanılıyor: ${ip}:${ADB_PORT}"
  local out; out=$("$ADB" connect "${ip}:${ADB_PORT}" 2>&1 || true)
  if echo "$out" | grep -qi "connected"; then
    SERIAL="${ip}:${ADB_PORT}"
    ok "Bağlandı: $SERIAL"
    return 0
  fi
  fail "Bağlanılamadı: $out"
  return 1
}

pick_device() {
  local ip="${1:-}"
  if [[ -n "$ip" ]]; then
    connect_tcp "$ip"; return
  fi
  if [[ -n "$SERIAL" ]]; then
    ok "Serial: $SERIAL"; return
  fi
  local devices
  devices=$("$ADB" devices 2>/dev/null | awk 'NR>1 && /\tdevice$/ {print $1}' || true)
  local count; count=$(echo "$devices" | grep -c . || true)
  if [[ $count -eq 0 ]]; then
    fail "ADB cihazı yok. USB takın veya --ip kullanın."
    exit 1
  elif [[ $count -eq 1 ]]; then
    SERIAL="$devices"
    ok "Cihaz: $SERIAL"
  else
    echo "  Birden fazla cihaz:"
    local i=0
    while IFS= read -r d; do echo "    [$i] $d"; ((i++)) || true; done <<< "$devices"
    read -r -p "  Seçin [0]: " idx; idx="${idx:-0}"
    SERIAL=$(echo "$devices" | sed -n "$((idx+1))p")
    ok "Seçildi: $SERIAL"
  fi
}

# ── ARAÇ KURULUMU ─────────────────────────────────────────────
cmd_arac() {
  local opt_ip="${1:-}"

  head "ARAÇ KURULUMU"
  echo "  VPS  : ${VPS_IP}:${VPS_PORT}"

  # Bağlan
  head "BAĞLANTI"
  pick_device "$opt_ip"

  # Bore binary
  head "BORE BİNARY"
  if adb_shell "test -f /data/local/tmp/bore && echo EXISTS" | grep -q "EXISTS"; then
    ok "bore binary zaten var: /data/local/tmp/bore"
  else
    step "bore binary bulunamadı."
    warn "ARM64 bore binary manuel olarak sağlanmalı."
    warn "İndir: ${BORE_DOWNLOAD_URL}"
    warn "Sonra: ${C_STEP}$ADB push bore /data/local/tmp/bore${C_RST}"
    warn "       ${C_STEP}$ADB shell su 0 chmod 755 /data/local/tmp/bore${C_RST}"
    warn "Bore yoksa tünel çalışmaz. Devam ediliyor (diğer dosyalar kurulacak)..."
  fi

  # Watchdog script
  head "WATCHDOG SCRIPT"
  step "bore_watchdog.sh oluşturuluyor: /data/local/tmp/bore_watchdog.sh"

  local tmp_watchdog; tmp_watchdog=$(mktemp /tmp/bore_watchdog_XXXXXX.sh)
  cat > "$tmp_watchdog" <<WATCHDOG
#!/system/bin/sh
# Bore Tunnel Watchdog
# Seçkin Kılınç / XemBiLL — xembill at gmail.com
# VPS: ${VPS_IP}:${VPS_PORT}
VPS_IP="${VPS_IP}"
VPS_PORT="${VPS_PORT}"
BORE_BIN="/data/local/tmp/bore"
LOG="/data/local/tmp/bore.log"

while true; do
  # WiFi bağlantı kontrolü
  WIFI_IP=\$(ip -o -4 addr show wlan0 2>/dev/null | awk '{print \$4}' | cut -d/ -f1 | head -1)

  if [ -n "\$WIFI_IP" ]; then
    # WiFi var ama bore çalışmıyor mu?
    if ! pgrep -f "bore local" > /dev/null 2>&1; then
      echo "\$(date): WiFi=\$WIFI_IP, bore başlatılıyor..." >> "\$LOG"
      nohup "\$BORE_BIN" local "\$VPS_PORT" --to "\$VPS_IP" >> "\$LOG" 2>&1 &
    fi
  fi

  sleep 15
done
WATCHDOG

  adb_push "$tmp_watchdog" "/data/local/tmp/bore_watchdog.sh" > /dev/null
  adb_shell_root "chmod 755 /data/local/tmp/bore_watchdog.sh"
  rm -f "$tmp_watchdog"
  ok "bore_watchdog.sh yüklendi"

  # Boot script (userinit.d)
  head "BOOT SCRIPT"
  step "userinit.d boot scripti oluşturuluyor: /data/local/userinit.d/01_adb_fix.sh"

  local tmp_boot; tmp_boot=$(mktemp /tmp/bore_boot_XXXXXX.sh)
  cat > "$tmp_boot" <<BOOT
#!/system/bin/sh
# CoocaaOS ADB + Bore Tunnel Boot Script
# Seçkin Kılınç / XemBiLL — xembill at gmail.com
# Her boot'ta otomatik çalışır

# ADB aç (şifresiz — sys.special.func bypass)
settings put global adb_enabled 1
settings put global adb_tcp_port ${ADB_PORT}
setprop service.adb.tcp.port ${ADB_PORT}
setprop sys.special.func 1

# WiFi'nin bağlanması için bekle
sleep 20

# Bore watchdog başlat
nohup sh /data/local/tmp/bore_watchdog.sh > /dev/null 2>&1 &
BOOT

  adb_shell_root "mkdir -p /data/local/userinit.d"
  adb_push "$tmp_boot" "/data/local/tmp/01_adb_fix.sh" > /dev/null
  adb_shell_root "mv /data/local/tmp/01_adb_fix.sh /data/local/userinit.d/01_adb_fix.sh"
  adb_shell_root "chmod 755 /data/local/userinit.d/01_adb_fix.sh"
  rm -f "$tmp_boot"
  ok "01_adb_fix.sh yüklendi"

  # Şimdi çalıştır
  head "HEMEN BAŞLAT"
  step "ADB ve watchdog şimdi başlatılıyor..."
  adb_shell_root "settings put global adb_enabled 1"
  adb_shell_root "setprop sys.special.func 1"
  adb_shell_root "setprop service.adb.tcp.port ${ADB_PORT}"
  adb_shell_root "nohup sh /data/local/tmp/bore_watchdog.sh > /dev/null 2>&1 &"
  sleep 3

  # Bore çalışıyor mu?
  local bore_running
  bore_running=$(adb_shell "pgrep -f 'bore local' && echo YES || echo NO" | tr -d '\r')
  if echo "$bore_running" | grep -q "YES"; then
    ok "Bore tunnel çalışıyor!"
  else
    warn "Bore henüz başlamadı (bore binary yoksa normal). watchdog 15sn'de tekrar deneyecek."
  fi

  head "TAMAMLANDI"
  echo ""
  echo "  ┌─────────────────────────────────────────────────┐"
  echo "  │  Araç kurulumu tamamlandı                       │"
  echo "  │                                                  │"
  echo "  │  Boot'ta otomatik:                               │"
  echo "  │    1. ADB açılır (şifresiz)                      │"
  echo "  │    2. Bore tunnel VPS'e bağlanır                 │"
  echo "  │    3. WiFi değişirse 15sn içinde yeniden bağlanır│"
  echo "  │                                                  │"
  echo "  │  Bağlanmak için:                                 │"
  printf "  │    adb connect %-33s│\n" "${VPS_IP}:${VPS_PORT}"
  echo "  └─────────────────────────────────────────────────┘"
  echo ""
}

# ── VPS KURULUMU ──────────────────────────────────────────────
cmd_vps() {
  head "VPS KURULUMU"
  echo "  Hedef: ${VPS_SSH_USER}@${VPS_IP}:${VPS_SSH_PORT}"
  echo "  Bore server portu: ${VPS_PORT}"
  echo ""

  local ssh_opts="-o StrictHostKeyChecking=accept-new -p ${VPS_SSH_PORT}"

  step "SSH bağlantısı test ediliyor..."
  if ! ssh $ssh_opts "${VPS_SSH_USER}@${VPS_IP}" "echo OK" 2>/dev/null | grep -q "OK"; then
    fail "SSH bağlantısı kurulamadı: ${VPS_SSH_USER}@${VPS_IP}:${VPS_SSH_PORT}"
    echo ""
    echo "  Manuel kurulum için VPS'te şunu çalıştırın:"
    echo ""
    _print_vps_manual
    exit 1
  fi
  ok "SSH bağlantısı başarılı"

  step "bore server kuruluyor..."
  ssh $ssh_opts "${VPS_SSH_USER}@${VPS_IP}" bash <<REMOTE
set -e
# Bore binary indir
if ! command -v bore &>/dev/null; then
  echo "  → bore indiriliyor..."
  curl -fsSL https://github.com/ekzhang/bore/releases/latest/download/bore-x86_64-unknown-linux-musl.tar.gz \
    | tar -xz -C /usr/local/bin/
  chmod +x /usr/local/bin/bore
  echo "  ✓ bore kuruldu: \$(bore --version)"
else
  echo "  ✓ bore zaten kurulu: \$(bore --version)"
fi

# Systemd service
cat > /etc/systemd/system/bore-server.service <<SERVICE
[Unit]
Description=Bore Reverse Tunnel Server
After=network.target

[Service]
ExecStart=/usr/local/bin/bore server --min-port ${VPS_PORT} --max-port ${VPS_PORT}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SERVICE

systemctl daemon-reload
systemctl enable bore-server
systemctl restart bore-server
sleep 2
systemctl is-active bore-server && echo "SERVICE_OK" || echo "SERVICE_FAIL"
REMOTE

  step "Firewall portu açılıyor: ${VPS_PORT}..."
  ssh $ssh_opts "${VPS_SSH_USER}@${VPS_IP}" "
    (ufw allow ${VPS_PORT}/tcp && echo 'ufw OK') 2>/dev/null || true
    (iptables -I INPUT -p tcp --dport ${VPS_PORT} -j ACCEPT 2>/dev/null && echo 'iptables OK') || true
  " 2>/dev/null || true

  head "TAMAMLANDI"
  echo ""
  echo "  ┌─────────────────────────────────────────────────┐"
  echo "  │  VPS kurulumu tamamlandı                        │"
  echo "  │                                                  │"
  printf "  │  Bore server: %-34s│\n" "${VPS_IP}:${VPS_PORT}"
  echo "  │  Systemd     : bore-server.service (aktif)      │"
  echo "  │                                                  │"
  echo "  │  Sonraki adım: arac kurulumu                    │"
  printf "  │    ./$(basename "$0") arac%-30s│\n" ""
  echo "  └─────────────────────────────────────────────────┘"
  echo ""
}

_print_vps_manual() {
  cat <<MANUAL
  ── Manuel VPS Kurulumu ──────────────────────────────────
  # 1. bore binary indir
  curl -fsSL https://github.com/ekzhang/bore/releases/latest/download/bore-x86_64-unknown-linux-musl.tar.gz \\
    | tar -xz -C /usr/local/bin/

  # 2. systemd service oluştur
  cat > /etc/systemd/system/bore-server.service <<EOF
  [Unit]
  Description=Bore Reverse Tunnel Server
  After=network.target

  [Service]
  ExecStart=/usr/local/bin/bore server --min-port ${VPS_PORT} --max-port ${VPS_PORT}
  Restart=always

  [Install]
  WantedBy=multi-user.target
  EOF

  # 3. Başlat
  systemctl daemon-reload
  systemctl enable --now bore-server

  # 4. Firewall
  ufw allow ${VPS_PORT}/tcp
  ──────────────────────────────────────────────────────────
MANUAL
}

# ── BAĞLAN ────────────────────────────────────────────────────
cmd_baglan() {
  head "BAĞLAN"
  step "adb connect ${VPS_IP}:${VPS_PORT}"
  local out; out=$("$ADB" connect "${VPS_IP}:${VPS_PORT}" 2>&1 || true)
  if echo "$out" | grep -qi "connected"; then
    ok "Bağlandı: ${VPS_IP}:${VPS_PORT}"
    echo ""
    echo "  Artık kullanabilirsiniz:"
    echo "    adb -s ${VPS_IP}:${VPS_PORT} shell"
    echo "    adb -s ${VPS_IP}:${VPS_PORT} shell su 0 ..."
  else
    fail "Bağlanılamadı: $out"
    warn "Araç uyanık ve WiFi'ye bağlı mı?"
    warn "VPS bore server çalışıyor mu? (cmd: $(basename "$0") durum)"
    exit 1
  fi
}

# ── DURUM ─────────────────────────────────────────────────────
cmd_durum() {
  head "DURUM KONTROLÜ"

  # VPS bore server
  step "VPS bore server kontrol: ${VPS_IP}:${VPS_PORT}"
  if (echo >/dev/tcp/"${VPS_IP}"/"${VPS_PORT}") 2>/dev/null; then
    ok "VPS portu açık: ${VPS_IP}:${VPS_PORT}"
  else
    fail "VPS portu kapalı/ulaşılamıyor: ${VPS_IP}:${VPS_PORT}"
  fi

  # ADB bağlantısı
  step "ADB bağlantısı kontrol: ${VPS_IP}:${VPS_PORT}"
  local out; out=$("$ADB" connect "${VPS_IP}:${VPS_PORT}" 2>&1 || true)
  if echo "$out" | grep -qi "connected"; then
    SERIAL="${VPS_IP}:${VPS_PORT}"
    ok "ADB bağlı!"

    # Araçtaki bore durumu
    step "Araçtaki bore process kontrol..."
    local bore_pid; bore_pid=$(adb_shell "pgrep -f 'bore local' 2>/dev/null || true" | tr -d '\r')
    if [[ -n "$bore_pid" ]]; then
      ok "Bore çalışıyor (PID: $bore_pid)"
    else
      warn "Bore process bulunamadı"
    fi

    # Araçtaki watchdog durumu
    local wdog_pid; wdog_pid=$(adb_shell "pgrep -f 'bore_watchdog' 2>/dev/null || true" | tr -d '\r')
    if [[ -n "$wdog_pid" ]]; then
      ok "Watchdog çalışıyor (PID: $wdog_pid)"
    else
      warn "Watchdog çalışmıyor"
    fi

    # Boot script var mı?
    local boot_exists
    boot_exists=$(adb_shell "test -f /data/local/userinit.d/01_adb_fix.sh && echo YES || echo NO" | tr -d '\r')
    if echo "$boot_exists" | grep -q "YES"; then
      ok "Boot script mevcut: /data/local/userinit.d/01_adb_fix.sh"
    else
      warn "Boot script yok: /data/local/userinit.d/01_adb_fix.sh"
    fi
  else
    fail "ADB bağlanamadı. Araç uyanık ve WiFi'ye bağlı mı?"
  fi
}

# ── KALDIR ────────────────────────────────────────────────────
cmd_kaldir() {
  local opt_ip="${1:-}"
  head "KALDIR"
  pick_device "$opt_ip"

  step "Bore process durdur..."
  adb_shell_root "pkill -f 'bore local' 2>/dev/null || true"
  adb_shell_root "pkill -f 'bore_watchdog' 2>/dev/null || true"

  step "Dosyaları kaldır..."
  adb_shell_root "rm -f /data/local/tmp/bore_watchdog.sh"
  adb_shell_root "rm -f /data/local/userinit.d/01_adb_fix.sh"
  adb_shell_root "rm -f /data/local/tmp/bore.log"

  ok "Kaldırıldı."
  warn "bore binary (/data/local/tmp/bore) ve userinit.d dizini korundu."
}

# ── Ana Akış ──────────────────────────────────────────────────
main() {
  local cmd="${1:-help}"
  shift || true

  local opt_ip=""
  while [[ $# -gt 0 ]]; do
    case "$1" in
      --ip)     opt_ip="$2";    shift 2 ;;
      --serial) SERIAL="$2";   shift 2 ;;
      -h|--help) usage; exit 0 ;;
      *) shift ;;
    esac
  done

  echo ""
  echo "======================================================="
  echo "  Bore Reverse Tunnel Kurulum Aracı"
  echo "  VPS: ${VPS_IP}:${VPS_PORT}  |  SSH: ${VPS_SSH_USER}@${VPS_IP}:${VPS_SSH_PORT}"
  echo "======================================================="

  case "$cmd" in
    arac)   cmd_arac "$opt_ip" ;;
    vps)    cmd_vps ;;
    baglan) cmd_baglan ;;
    durum)  cmd_durum ;;
    kaldir) cmd_kaldir "$opt_ip" ;;
    help|-h|--help) usage ;;
    *) fail "Bilinmeyen komut: $cmd"; usage; exit 1 ;;
  esac
}

main "$@"
