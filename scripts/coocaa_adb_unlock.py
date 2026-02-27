#!/usr/bin/env python3
"""
Seçkin Kılınç
XemBiLL
xembill at gmail.com

coocaa_adb_unlock_forUmit.py — CoocaaOS WiFi ADB Unlock Tool
=====================================================
Keşif: SystemSettings.apk → BackdoorAdapter.java
  SystemUtils.setWifiAdbOpen() = SystemProperties.set("sys.special.func", "1")

Yani menü yerine (Sistem → Logo 8-9x → şifr81) tek komut:
  adb shell su 0 setprop sys.special.func 1

Bu tool:
  - USB veya mevcut TCP bağlantısı üzerinden komutu çalıştırır
  - WiFi ADB açıldıktan sonra TCP'ye geçer
  - İsteğe bağlı: boot kalıcılığı (userinit.d script)
  - Farklı cihaz profillerini destekler

Kullanım:
  python3 coocaa_adb_unlock.py                  # USB bağlı cihaz
  python3 coocaa_adb_unlock.py --ip 192.168.1.x # TCP bağlantısı
  python3 coocaa_adb_unlock.py --persist         # Boot kalıcılığı da yükle
  python3 coocaa_adb_unlock.py --scan            # Ağı tara, CoocaaOS cihaz bul
"""

import argparse
import subprocess
import sys
import socket
import ipaddress
import concurrent.futures
import time


ADB_PORT = 5555  # global, main() içinde args.port ile override edilir
COOCAA_PROP = "sys.special.func"
COOCAA_VALUE = "1"

PERSIST_SCRIPT = """\
#!/system/bin/sh
# CoocaaOS WiFi ADB kalici aktiflestiricisi
# coocaa_adb_unlock.py tarafindan yuklendi
settings put global adb_enabled 1
settings put global adb_tcp_port 5555
setprop service.adb.tcp.port 5555
setprop {prop} {val}
""".format(prop=COOCAA_PROP, val=COOCAA_VALUE)

PERSIST_PATH = "/data/local/userinit.d/01_coocaa_adb.sh"
PERSIST_TMP  = "/data/local/tmp/01_coocaa_adb.sh"


def run(cmd: list[str], check=True) -> subprocess.CompletedProcess:
    return subprocess.run(cmd, capture_output=True, text=True, check=check)


def adb(*args, device: str | None = None) -> subprocess.CompletedProcess:
    base = ["adb"]
    if device:
        base += ["-s", device]
    return run(base + list(args), check=False)


def step(msg: str):
    print(f"  → {msg}")


def ok(msg: str):
    print(f"  ✓ {msg}")


def fail(msg: str):
    print(f"  ✗ {msg}")


# ─── Cihaz Bağlantısı ────────────────────────────────────────────────────────

def list_devices() -> list[dict]:
    """Bağlı ADB cihazlarını döndür."""
    result = adb("devices")
    devices = []
    for line in result.stdout.strip().splitlines()[1:]:
        line = line.strip()
        if not line or "\t" not in line:
            continue
        serial, state = line.split("\t", 1)
        devices.append({"serial": serial.strip(), "state": state.strip()})
    return devices


def connect_tcp(ip: str) -> bool:
    step(f"TCP bağlanılıyor: {ip}:{ADB_PORT}")
    r = adb("connect", f"{ip}:{ADB_PORT}")
    if "connected" in r.stdout.lower() or "already connected" in r.stdout.lower():
        ok(f"Bağlandı: {ip}:{ADB_PORT}")
        return True
    fail(f"Bağlanılamadı: {r.stdout.strip() or r.stderr.strip()}")
    return False


def pick_device(ip: str | None) -> str | None:
    """Hedef cihazın ADB serial'ını döndür."""
    if ip:
        serial = f"{ip}:{ADB_PORT}"
        if not connect_tcp(ip):
            return None
        return serial

    devices = [d for d in list_devices() if d["state"] == "device"]
    if not devices:
        fail("Bağlı ADB cihazı yok. USB takın veya --ip kullanın.")
        return None
    if len(devices) == 1:
        ok(f"Cihaz bulundu: {devices[0]['serial']}")
        return devices[0]["serial"]

    print("\nBirden fazla cihaz:")
    for i, d in enumerate(devices):
        print(f"  [{i}] {d['serial']}")
    idx = int(input("Seçin [0]: ") or "0")
    return devices[idx]["serial"]


# ─── CoocaaOS Tespiti ─────────────────────────────────────────────────────────

def is_coocaa(serial: str) -> bool:
    """Cihazın CoocaaOS olup olmadığını kontrol et."""
    r = adb("shell", "getprop", "ro.product.manufacturer", device=serial)
    manufacturer = r.stdout.strip().lower()

    r2 = adb("shell", "getprop", "ro.product.model", device=serial)
    model = r2.stdout.strip()

    r3 = adb("shell", "pm", "list", "packages", "com.coocaa", device=serial)
    has_coocaa_pkg = "com.coocaa" in r3.stdout

    r4 = adb("shell", "ls", "/data/local/userinit.d", device=serial)
    has_userinit = "userinit.d" not in (r4.stderr or "")

    print(f"\n  Üretici  : {manufacturer or '?'}")
    print(f"  Model    : {model or '?'}")
    print(f"  CoocaaOS : {'Evet' if has_coocaa_pkg else 'Tespit edilemedi'}")
    print(f"  userinit : {'Destekleniyor' if has_userinit else 'Yok'}")
    return True  # Zaten bağlıysa dene


# ─── Ana Kilit Açma ──────────────────────────────────────────────────────────

def unlock_adb(serial: str) -> bool:
    """
    sys.special.func = 1 → CoocaaOS WiFi ADB açar.
    Menü bypass: Sistem → Logo 8-9x → Gizli menü → şi 81 adımları gerekmez.
    """
    step(f"setprop {COOCAA_PROP} {COOCAA_VALUE} uygulanıyor...")
    r = adb("shell", "su", "0", f"setprop {COOCAA_PROP} {COOCAA_VALUE}", device=serial)
    if r.returncode != 0:
        # Root yoksa direkt dene (bazı cihazlarda ADB zaten root)
        r = adb("shell", f"setprop {COOCAA_PROP} {COOCAA_VALUE}", device=serial)

    # Ek: ADB settings de ayarla
    adb("shell", "su", "0", "settings put global adb_enabled 1", device=serial)
    adb("shell", "su", "0", f"settings put global adb_tcp_port {ADB_PORT}", device=serial)
    adb("shell", "su", "0", f"setprop service.adb.tcp.port {ADB_PORT}", device=serial)

    # Doğrula
    time.sleep(1)
    r = adb("shell", "getprop", COOCAA_PROP, device=serial)
    val = r.stdout.strip()
    if val == COOCAA_VALUE:
        ok(f"WiFi ADB aktif! ({COOCAA_PROP}={val})")
        return True
    else:
        fail(f"Değer beklenen '{COOCAA_VALUE}', gerçek '{val}'")
        return False


def get_device_ip(serial: str) -> str | None:
    """Cihazın WiFi IP adresini bul."""
    r = adb("shell", "ip -o -4 addr show wlan0", device=serial)
    for part in r.stdout.split():
        try:
            ip = part.split("/")[0]
            ipaddress.ip_address(ip)
            if not ip.startswith("127."):
                return ip
        except ValueError:
            continue
    return None


# ─── Kalıcılık ───────────────────────────────────────────────────────────────

def install_persist(serial: str) -> bool:
    """Boot kalıcılığı: /data/local/userinit.d/01_coocaa_adb.sh"""
    step("Boot kalıcılığı yükleniyor...")

    # Dizini oluştur
    adb("shell", "su", "0", "mkdir -p /data/local/userinit.d", device=serial)

    # Script'i yükle
    push_cmd = ["adb"]
    if serial:
        push_cmd += ["-s", serial]

    # Geçici dosyaya yaz ve push et
    import tempfile, os
    with tempfile.NamedTemporaryFile(mode="w", suffix=".sh", delete=False) as f:
        f.write(PERSIST_SCRIPT)
        tmp = f.name

    try:
        run(push_cmd + ["push", tmp, PERSIST_TMP])
        adb("shell", "su", "0", f"mv {PERSIST_TMP} {PERSIST_PATH}", device=serial)
        adb("shell", "su", "0", f"chmod 755 {PERSIST_PATH}", device=serial)
        ok(f"Yüklendi: {PERSIST_PATH}")
        return True
    except Exception as e:
        fail(f"Kalıcılık yüklenemedi: {e}")
        return False
    finally:
        os.unlink(tmp)


# ─── Ağ Tarama ───────────────────────────────────────────────────────────────

def probe_adb(ip: str) -> str | None:
    """Verilen IP'de ADB portu açık mı?"""
    try:
        with socket.create_connection((ip, ADB_PORT), timeout=0.5):
            return ip
    except (socket.timeout, ConnectionRefusedError, OSError):
        return None


def scan_network(network_cidr: str | None = None) -> list[str]:
    """Ağdaki CoocaaOS cihazlarını tara (port 5555)."""
    if not network_cidr:
        # Yerel ağı tahmin et
        s = socket.socket(socket.AF_INET, socket.SOCK_DGRAM)
        try:
            s.connect(("8.8.8.8", 80))
            local_ip = s.getsockname()[0]
        finally:
            s.close()
        network_cidr = local_ip.rsplit(".", 1)[0] + ".0/24"

    step(f"Taranıyor: {network_cidr} (port {ADB_PORT})...")
    hosts = list(ipaddress.ip_network(network_cidr, strict=False).hosts())

    found = []
    with concurrent.futures.ThreadPoolExecutor(max_workers=64) as ex:
        futures = {ex.submit(probe_adb, str(h)): str(h) for h in hosts}
        for fut in concurrent.futures.as_completed(futures):
            r = fut.result()
            if r:
                found.append(r)
                print(f"    ADB port açık: {r}:{ADB_PORT}")

    return found


# ─── Ana Program ─────────────────────────────────────────────────────────────

def main():
    global ADB_PORT
    parser = argparse.ArgumentParser(
        description="CoocaaOS WiFi ADB Unlock — sys.special.func bypass",
        formatter_class=argparse.RawDescriptionHelpFormatter,
        epilog="""
Örnekler:
  python3 coocaa_adb_unlock.py                        # USB bağlı cihaz
  python3 coocaa_adb_unlock.py --ip 10.13.180.165     # TCP bağlantısı
  python3 coocaa_adb_unlock.py --ip 10.13.180.165 --persist  # + boot kalıcılığı
  python3 coocaa_adb_unlock.py --scan                 # Ağdaki cihazları bul
  python3 coocaa_adb_unlock.py --scan --network 192.168.1.0/24
        """
    )
    parser.add_argument("--ip", help="Cihaz IP adresi (TCP bağlantısı için)")
    parser.add_argument("--persist", action="store_true",
                        help="Boot kalıcılığı yükle (userinit.d)")
    parser.add_argument("--scan", action="store_true",
                        help="Ağı tara, ADB portu açık cihazları bul")
    parser.add_argument("--network", help="Taranacak CIDR (örn: 192.168.1.0/24)")
    parser.add_argument("--port", type=int, default=ADB_PORT,
                        help=f"ADB TCP portu (varsayılan: {ADB_PORT})")
    args = parser.parse_args()

    if args.port != 5555:
        ADB_PORT = args.port

    print("=" * 55)
    print("  CoocaaOS WiFi ADB Unlock")
    print("  sys.special.func bypass — github.com/seckinkilinc")
    print("=" * 55)

    # Ağ tarama modu
    if args.scan:
        print("\n[TARAMA MODU]")
        found = scan_network(args.network)
        if not found:
            fail("Hiç cihaz bulunamadı.")
            sys.exit(1)
        print(f"\n  {len(found)} cihaz bulundu.")
        if len(found) == 1:
            ip = found[0]
        else:
            for i, ip in enumerate(found):
                print(f"  [{i}] {ip}")
            idx = int(input("  Unlock için seçin [0]: ") or "0")
            ip = found[idx]
        args.ip = ip

    # Cihaza bağlan
    print("\n[BAĞLANTI]")
    serial = pick_device(args.ip)
    if not serial:
        sys.exit(1)

    # Cihaz bilgisi
    print("\n[CİHAZ BİLGİSİ]")
    is_coocaa(serial)

    # Kilit aç
    print("\n[KİLİT AÇMA]")
    success = unlock_adb(serial)

    if success:
        # TCP bağlantısı değilse WiFi IP'yi bul ve TCP geç
        if ":" not in serial:
            ip = get_device_ip(serial)
            if ip:
                step(f"WiFi IP tespit edildi: {ip}, TCP'ye geçiliyor...")
                if connect_tcp(ip):
                    serial = f"{ip}:{ADB_PORT}"

        # Kalıcılık
        if args.persist:
            print("\n[KALICILIK]")
            install_persist(serial)

        print(f"\n{'=' * 55}")
        print(f"  TAMAMLANDI")
        if ":" in serial:
            ip_part = serial.split(":")[0]
            print(f"  Bağlantı : adb connect {ip_part}:{ADB_PORT}")
        print(f"  Şifre    : GEREKMEZ (setprop bypass aktif)")
        if args.persist:
            print(f"  Kalıcı   : Her boot'ta otomatik açılır")
        print(f"{'=' * 55}\n")
    else:
        print("\n  ✗ Unlock başarısız. Root erişimi gerekiyor olabilir.")
        print("    USB bağlantısıyla deneyin veya cihaz zaten root'lu olmalı.\n")
        sys.exit(1)


if __name__ == "__main__":
    main()
