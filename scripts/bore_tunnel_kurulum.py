#!/usr/bin/env python3
"""
Seçkin Kılınç
XemBiLL
xembill at gmail.com

bore_tunnel_kurulum.py — Bore Reverse Tunnel Tam Kurulum
=========================================================
MİMARİ:
  Araç (tablet) ──bore──► VPS:PORT ◄── adb connect ── PC

KULLANIM:
  python3 bore_tunnel_kurulum.py arac
  python3 bore_tunnel_kurulum.py arac --ip 192.168.1.100
  python3 bore_tunnel_kurulum.py vps
  python3 bore_tunnel_kurulum.py baglan
  python3 bore_tunnel_kurulum.py durum
  python3 bore_tunnel_kurulum.py kaldir

YAPILANDIRMA (değiştirilebilir):
  --vps-ip, --vps-port, --vps-user, --vps-ssh-port
  veya ortam değişkenleri: VPS_IP, VPS_PORT, VPS_SSH_USER, VPS_SSH_PORT
"""

import argparse
import os
import subprocess
import sys
import socket
import tempfile
import time

# ── Varsayılan Yapılandırma — DEĞİŞTİRİLEBİLİR ────────────────
DEFAULT_VPS_IP       = os.environ.get("VPS_IP",       "20.229.185.95")
DEFAULT_VPS_PORT     = int(os.environ.get("VPS_PORT", "5555"))
DEFAULT_VPS_SSH_USER = os.environ.get("VPS_SSH_USER", "root")
DEFAULT_VPS_SSH_PORT = int(os.environ.get("VPS_SSH_PORT", "22"))
DEFAULT_ADB_PORT     = int(os.environ.get("ADB_PORT", "5555"))
# ──────────────────────────────────────────────────────────────

ADB = os.environ.get("ADB_BIN", "adb")
SERIAL = ""


def run(cmd, check=False, capture=True):
    return subprocess.run(cmd, capture_output=capture, text=True, check=check)


def adb(*args):
    base = [ADB] + (["-s", SERIAL] if SERIAL else [])
    return run(base + list(args))


def adb_root(*args):
    return adb("shell", "su", "0", *args)


# ── Çıktı ─────────────────────────────────────────────────────
def ok(msg):   print(f"  \033[32m✓\033[0m {msg}")
def fail(msg): print(f"  \033[31m✗\033[0m {msg}")
def step(msg): print(f"  \033[36m→\033[0m {msg}")
def warn(msg): print(f"  \033[33m!\033[0m {msg}")
def head(msg): print(f"\n\033[1m[{msg}]\033[0m")


# ── Bağlantı ──────────────────────────────────────────────────
def connect_tcp(ip: str, port: int) -> bool:
    global SERIAL
    step(f"TCP bağlanılıyor: {ip}:{port}")
    r = run([ADB, "connect", f"{ip}:{port}"])
    if "connected" in r.stdout.lower():
        SERIAL = f"{ip}:{port}"
        ok(f"Bağlandı: {SERIAL}")
        return True
    fail(f"Bağlanılamadı: {r.stdout.strip() or r.stderr.strip()}")
    return False


def pick_device(opt_ip: str = "") -> bool:
    global SERIAL
    if opt_ip:
        return connect_tcp(opt_ip, DEFAULT_ADB_PORT)

    r = run([ADB, "devices"])
    devices = [
        line.split("\t")[0]
        for line in r.stdout.splitlines()[1:]
        if "\tdevice" in line
    ]
    if not devices:
        fail("ADB cihazı yok. USB takın veya --ip kullanın.")
        return False
    if len(devices) == 1:
        SERIAL = devices[0]
        ok(f"Cihaz: {SERIAL}")
        return True
    for i, d in enumerate(devices):
        print(f"    [{i}] {d}")
    idx = int(input("  Seçin [0]: ") or "0")
    SERIAL = devices[idx]
    return True


def push_script(content: str, remote_path: str, mode: str = "755"):
    """Geçici dosya oluştur, push et, chmod ver."""
    with tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False) as f:
        f.write(content)
        tmp = f.name
    try:
        base = [ADB] + (["-s", SERIAL] if SERIAL else [])
        run(base + ["push", tmp, remote_path + ".tmp"])
        adb_root(f"mv {remote_path}.tmp {remote_path}")
        adb_root(f"chmod {mode} {remote_path}")
    finally:
        os.unlink(tmp)


# ── ARAÇ KURULUMU ─────────────────────────────────────────────
def cmd_arac(args):
    head("ARAÇ KURULUMU")
    print(f"  VPS: {args.vps_ip}:{args.vps_port}")

    head("BAĞLANTI")
    if not pick_device(args.ip):
        sys.exit(1)

    # Bore binary kontrolü
    head("BORE BİNARY")
    r = adb("shell", "test -f /data/local/tmp/bore && echo EXISTS || echo MISSING")
    if "EXISTS" in r.stdout:
        ok("bore binary mevcut: /data/local/tmp/bore")
    else:
        warn("bore binary bulunamadı!")
        warn("ARM64 bore binary manuel olarak yüklenmelidir:")
        print()
        print("    # İndir:")
        print("    curl -fsSL https://github.com/ekzhang/bore/releases/latest/download/bore-aarch64-unknown-linux-musl.tar.gz | tar -xz")
        print(f"    {ADB} push bore /data/local/tmp/bore")
        print(f"    {ADB} shell su 0 chmod 755 /data/local/tmp/bore")
        print()
        warn("Bore olmadan tünel çalışmaz. Diğer dosyalar yüklenmeye devam ediyor...")

    # Watchdog script
    head("WATCHDOG SCRIPT")
    step("bore_watchdog.sh oluşturuluyor...")

    watchdog = f"""#!/system/bin/sh
# Bore Tunnel Watchdog — Seçkin Kılınç / XemBiLL
VPS_IP="{args.vps_ip}"
VPS_PORT="{args.vps_port}"
BORE_BIN="/data/local/tmp/bore"
LOG="/data/local/tmp/bore.log"

while true; do
  WIFI_IP=$(ip -o -4 addr show wlan0 2>/dev/null | awk '{{print $4}}' | cut -d/ -f1 | head -1)
  if [ -n "$WIFI_IP" ]; then
    if ! pgrep -f "bore local" > /dev/null 2>&1; then
      echo "$(date): WiFi=$WIFI_IP, bore baslatiliyor..." >> "$LOG"
      nohup "$BORE_BIN" local "$VPS_PORT" --to "$VPS_IP" >> "$LOG" 2>&1 &
    fi
  fi
  sleep 15
done
"""
    adb_root("mkdir -p /data/local/tmp")
    push_script(watchdog, "/data/local/tmp/bore_watchdog.sh")
    ok("bore_watchdog.sh yüklendi")

    # Boot script
    head("BOOT SCRIPT")
    step("userinit.d/01_adb_fix.sh oluşturuluyor...")

    boot = f"""#!/system/bin/sh
# CoocaaOS ADB + Bore Tunnel Boot Script — Seçkin Kılınç / XemBiLL
# sys.special.func bypass: gizli menü gerekmez

settings put global adb_enabled 1
settings put global adb_tcp_port {args.adb_port}
setprop service.adb.tcp.port {args.adb_port}
setprop sys.special.func 1

sleep 20
nohup sh /data/local/tmp/bore_watchdog.sh > /dev/null 2>&1 &
"""
    adb_root("mkdir -p /data/local/userinit.d")
    push_script(boot, "/data/local/userinit.d/01_adb_fix.sh")
    ok("01_adb_fix.sh yüklendi")

    # Hemen başlat
    head("HEMEN BAŞLAT")
    step("ADB ve watchdog şimdi başlatılıyor...")
    adb_root("settings put global adb_enabled 1")
    adb_root("setprop sys.special.func 1")
    adb_root(f"setprop service.adb.tcp.port {args.adb_port}")
    adb_root("nohup sh /data/local/tmp/bore_watchdog.sh > /dev/null 2>&1 &")
    time.sleep(3)

    bore_up = adb("shell", "pgrep -f 'bore local' && echo YES || echo NO")
    if "YES" in bore_up.stdout:
        ok("Bore tunnel çalışıyor!")
    else:
        warn("Bore henüz başlamadı (binary yoksa normal, watchdog 15sn'de tekrar dener)")

    print(f"""
  ┌─────────────────────────────────────────────────┐
  │  Araç kurulumu tamamlandı                        │
  │                                                  │
  │  Boot'ta otomatik:                               │
  │    1. ADB açılır (şifresiz)                      │
  │    2. Bore tunnel VPS'e bağlanır                 │
  │    3. WiFi değişirse 15sn'de yeniden bağlanır    │
  │                                                  │
  │  Bağlanmak için:                                 │
  │    adb connect {args.vps_ip}:{args.vps_port:<26}│
  └─────────────────────────────────────────────────┘
""")


# ── VPS KURULUMU ──────────────────────────────────────────────
def cmd_vps(args):
    head("VPS KURULUMU")
    print(f"  Hedef: {args.vps_user}@{args.vps_ip}:{args.vps_ssh_port}")
    print(f"  Bore port: {args.vps_port}")

    # SSH ile otomatik kur
    step("SSH ile kurulum deneniyor...")
    vps_script = f"""
set -e
# bore binary kur
if ! command -v bore &>/dev/null; then
    curl -fsSL https://github.com/ekzhang/bore/releases/latest/download/bore-x86_64-unknown-linux-musl.tar.gz | tar -xz -C /usr/local/bin/
    chmod +x /usr/local/bin/bore
    echo "bore kuruldu: $(bore --version)"
else
    echo "bore zaten mevcut: $(bore --version)"
fi

# systemd service
cat > /etc/systemd/system/bore-server.service <<'SVC'
[Unit]
Description=Bore Reverse Tunnel Server
After=network.target

[Service]
ExecStart=/usr/local/bin/bore server --min-port {args.vps_port} --max-port {args.vps_port}
Restart=always
RestartSec=5
StandardOutput=journal
StandardError=journal

[Install]
WantedBy=multi-user.target
SVC

systemctl daemon-reload
systemctl enable bore-server
systemctl restart bore-server
sleep 2
systemctl is-active bore-server && echo "SERVICE_OK" || echo "SERVICE_FAIL"

# Firewall
(ufw allow {args.vps_port}/tcp && echo "ufw OK") 2>/dev/null || true
(iptables -I INPUT -p tcp --dport {args.vps_port} -j ACCEPT 2>/dev/null && echo "iptables OK") || true
"""
    ssh_cmd = [
        "ssh",
        "-o", "StrictHostKeyChecking=accept-new",
        "-p", str(args.vps_ssh_port),
        f"{args.vps_user}@{args.vps_ip}",
        "bash", "-s"
    ]
    try:
        r = subprocess.run(ssh_cmd, input=vps_script, capture_output=False, text=True, timeout=120)
        if r.returncode == 0:
            ok("VPS kurulumu tamamlandı")
        else:
            raise RuntimeError("SSH hata kodu")
    except Exception as e:
        warn(f"Otomatik kurulum başarısız: {e}")
        print("\n  Manuel kurulum için VPS'te çalıştırın:")
        print(f"""
  # 1. bore indir
  curl -fsSL https://github.com/ekzhang/bore/releases/latest/download/bore-x86_64-unknown-linux-musl.tar.gz | tar -xz -C /usr/local/bin/

  # 2. systemd service
  cat > /etc/systemd/system/bore-server.service <<EOF
  [Unit]
  Description=Bore Reverse Tunnel Server
  After=network.target
  [Service]
  ExecStart=/usr/local/bin/bore server --min-port {args.vps_port} --max-port {args.vps_port}
  Restart=always
  [Install]
  WantedBy=multi-user.target
  EOF

  # 3. Başlat
  systemctl daemon-reload && systemctl enable --now bore-server

  # 4. Firewall
  ufw allow {args.vps_port}/tcp
""")


# ── BAĞLAN ────────────────────────────────────────────────────
def cmd_baglan(args):
    head("BAĞLAN")
    step(f"adb connect {args.vps_ip}:{args.vps_port}")
    r = run([ADB, "connect", f"{args.vps_ip}:{args.vps_port}"])
    if "connected" in r.stdout.lower():
        ok(f"Bağlandı: {args.vps_ip}:{args.vps_port}")
        print(f"\n  Kullanım:")
        print(f"    adb -s {args.vps_ip}:{args.vps_port} shell")
    else:
        fail(f"Bağlanılamadı: {r.stdout.strip()}")
        warn("Araç uyanık ve WiFi'ye bağlı mı?")
        sys.exit(1)


# ── DURUM ─────────────────────────────────────────────────────
def cmd_durum(args):
    global SERIAL
    head("DURUM KONTROLÜ")

    # VPS port
    step(f"VPS port kontrol: {args.vps_ip}:{args.vps_port}")
    try:
        with socket.create_connection((args.vps_ip, args.vps_port), timeout=3):
            ok(f"VPS portu açık: {args.vps_ip}:{args.vps_port}")
    except Exception:
        fail(f"VPS portuna ulaşılamıyor: {args.vps_ip}:{args.vps_port}")

    # ADB
    step(f"ADB bağlantı kontrol: {args.vps_ip}:{args.vps_port}")
    r = run([ADB, "connect", f"{args.vps_ip}:{args.vps_port}"])
    if "connected" in r.stdout.lower():
        SERIAL = f"{args.vps_ip}:{args.vps_port}"
        ok("ADB bağlı!")

        bore = adb("shell", "pgrep -f 'bore local' && echo YES || echo NO")
        if "YES" in bore.stdout:
            ok("Bore çalışıyor")
        else:
            warn("Bore process bulunamadı")

        wdog = adb("shell", "pgrep -f bore_watchdog && echo YES || echo NO")
        if "YES" in wdog.stdout:
            ok("Watchdog çalışıyor")
        else:
            warn("Watchdog çalışmıyor")

        boot = adb("shell", "test -f /data/local/userinit.d/01_adb_fix.sh && echo YES || echo NO")
        if "YES" in boot.stdout:
            ok("Boot script mevcut")
        else:
            warn("Boot script yok — araç yeniden başladığında tunnel kurulmaz")
    else:
        fail("ADB bağlanamadı. Araç uyanık mı?")


# ── KALDIR ────────────────────────────────────────────────────
def cmd_kaldir(args):
    head("KALDIR")
    if not pick_device(args.ip):
        sys.exit(1)
    step("Bore process durduruluyor...")
    adb_root("pkill -f 'bore local' 2>/dev/null || true")
    adb_root("pkill -f bore_watchdog 2>/dev/null || true")
    step("Dosyalar kaldırılıyor...")
    adb_root("rm -f /data/local/tmp/bore_watchdog.sh")
    adb_root("rm -f /data/local/userinit.d/01_adb_fix.sh")
    adb_root("rm -f /data/local/tmp/bore.log")
    ok("Kaldırıldı.")


# ── Ana Program ───────────────────────────────────────────────
def main():
    parser = argparse.ArgumentParser(
        description="Bore Reverse Tunnel Kurulum Aracı",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Komutlar:
  arac      Araç tabletine bore + watchdog + boot script kur
  vps       VPS'e bore server kur (SSH)
  baglan    Bu PC'den araca ADB bağlan
  durum     Tunnel ve ADB durumunu kontrol et
  kaldir    Araçtan bore tunnel dosyalarını kaldır

Örnekler:
  python3 bore_tunnel_kurulum.py arac
  python3 bore_tunnel_kurulum.py arac --ip 10.13.180.165
  python3 bore_tunnel_kurulum.py vps --vps-ip 1.2.3.4 --vps-port 9000
  python3 bore_tunnel_kurulum.py baglan
  python3 bore_tunnel_kurulum.py durum
        """
    )
    parser.add_argument("cmd", choices=["arac", "vps", "baglan", "durum", "kaldir"],
                        help="Çalıştırılacak komut")
    parser.add_argument("--ip", default="", help="Araç IP (TCP bağlantısı için)")
    parser.add_argument("--vps-ip",       default=DEFAULT_VPS_IP)
    parser.add_argument("--vps-port",     default=DEFAULT_VPS_PORT, type=int)
    parser.add_argument("--vps-user",     default=DEFAULT_VPS_SSH_USER)
    parser.add_argument("--vps-ssh-port", default=DEFAULT_VPS_SSH_PORT, type=int)
    parser.add_argument("--adb-port",     default=DEFAULT_ADB_PORT, type=int)

    args = parser.parse_args()

    print()
    print("=" * 55)
    print("  Bore Reverse Tunnel Kurulum Aracı")
    print(f"  VPS: {args.vps_ip}:{args.vps_port}")
    print("=" * 55)

    dispatch = {
        "arac":   cmd_arac,
        "vps":    cmd_vps,
        "baglan": cmd_baglan,
        "durum":  cmd_durum,
        "kaldir": cmd_kaldir,
    }
    dispatch[args.cmd](args)


if __name__ == "__main__":
    main()
