# CoocaaOS ADB Tools

> **Seçkin Kılınç (XemBiLL)** · xembill at gmail.com

---

> ### ⚠️ SORUMLULUK REDDİ BEYANI
>
> Bu repo'da yer alan tüm araçlar, komutlar, scriptler ve belgeler **yalnızca eğitim ve araştırma amaçlıdır.**
>
> Bu araçları kullanan kişiler, aşağıdaki hususları **açıkça kabul etmiş sayılır:**
>
> - Araçların kullanımı **tamamen kullanıcının kendi sorumluluğundadır.**
> - Bu komutların uygulanması sonucunda araçta, head unit'te, T-Box'ta veya bağlı herhangi bir sistemde oluşabilecek **yazılım hatası, donanım arızası, garanti iptali, veri kaybı veya beklenmedik davranışlar** dahil olmak üzere **hiçbir olumsuz sonuçtan** Seçkin Kılınç (XemBiLL) sorumlu tutulamaz.
> - Araç üreticisinin yazılımına müdahale etmek **garanti koşullarınızı geçersiz kılabilir.**
> - Root erişimi ve ADB komutları yanlış kullanıldığında aracın elektronik sistemlerine **kalıcı zarar verebilir.**
> - Bu araçları **üretici izni olmayan bir araç üzerinde** kullanmak, bulunduğunuz ülkenin yasalarına aykırı olabilir. Yasal uyumluluktan kullanıcı sorumludur.
>
> **Devam ederek bu koşulları okuduğunuzu, anladığınızı ve kabul ettiğinizi beyan etmiş olursunuz.**

---

CoocaaOS tabanlı araç head unit'leri için **şifresiz ADB açma** ve **uzaktan erişim tüneli** kurulum araçları.

---

## Keşif

`SystemSettings.apk` decompile edildiğinde `BackdoorAdapter.java` içinde bulundu:

```java
SystemUtils.setWifiAdbOpen()
  → SystemProperties.set("sys.special.func", "1")
```

Yani gizli menüye gerek yok:

| ❌ Eski Yol | ✅ Yeni Yol |
|---|---|
| Sistem → Logo 8-9x → şifre `2281` → ADB Aç | `adb shell su 0 setprop sys.special.func 1` |

---

## İçerik

```
coocaa-adb-tools/
├── scripts/
│   ├── coocaa_adb_unlock.sh       # ADB kilit açma — macOS/Linux
│   ├── coocaa_adb_unlock.bat      # ADB kilit açma — Windows
│   ├── coocaa_adb_unlock.py       # ADB kilit açma — Python (her platform)
│   ├── bore_tunnel_kurulum.sh     # Bore tüneli tam kurulum — macOS/Linux
│   ├── bore_tunnel_kurulum.bat    # Bore tüneli tam kurulum — Windows
│   └── bore_tunnel_kurulum.py    # Bore tüneli tam kurulum — Python
├── docs/
│   ├── nasil_calisir.md           # Teknik detaylar
│   └── bore_tunnel_mimari.md      # Tünel mimarisi
└── README.md
```

---

## 1. ADB Kilit Açma

### Gereksinimler
- `adb` kurulu ve PATH'te
- Cihazda root erişimi (`su 0`)
- USB veya aynı WiFi ağında olma

### Kullanım

**macOS / Linux:**
```bash
# USB bağlı cihaz
./scripts/coocaa_adb_unlock.sh

# TCP bağlantısı
./scripts/coocaa_adb_unlock.sh --ip 192.168.1.100

# + boot kalıcılığı
./scripts/coocaa_adb_unlock.sh --ip 192.168.1.100 --persist

# Ağı tara, cihaz bul
./scripts/coocaa_adb_unlock.sh --scan
```

**Windows:**
```cmd
coocaa_adb_unlock.bat 192.168.1.100
coocaa_adb_unlock.bat 192.168.1.100 persist
coocaa_adb_unlock.bat scan
```

**Python (tüm platformlar):**
```bash
python3 scripts/coocaa_adb_unlock.py --ip 192.168.1.100 --persist
```

---

## 2. Bore Reverse Tunnel

Araç farklı bir ağdayken (4G, başka WiFi) PC'den ADB bağlantısı sağlar.

### Mimari

```
Araç (tablet)
    │
    │  bore local <PORT> --to <VPS_IP>
    ▼
VPS (sabit IP) ──── bore server (systemd, her zaman açık)
    ▲
    │  adb connect <VPS_IP>:<PORT>
PC / Mac (her ağdan)
```

### Adım 1 — VPS'e Bore Server Kur

```bash
# VPS bilgilerini ayarla
export VPS_IP="20.229.185.95"
export VPS_PORT="5555"
export VPS_SSH_USER="root"

./scripts/bore_tunnel_kurulum.sh vps
```

### Adım 2 — Araca Kur (USB ile bir kez)

```bash
./scripts/bore_tunnel_kurulum.sh arac
```

Bu adım şunları yükler:
- `/data/local/userinit.d/01_adb_fix.sh` → boot'ta ADB açar
- `/data/local/tmp/bore_watchdog.sh` → WiFi değişince tüneli yeniden kurar
- `/data/local/tmp/bore` → ARM64 binary (ayrıca sağlanmalı)

### Adım 3 — Her Yerden Bağlan

```bash
./scripts/bore_tunnel_kurulum.sh baglan

# veya direkt:
adb connect 20.229.185.95:5555
```

### Durum Kontrol

```bash
./scripts/bore_tunnel_kurulum.sh durum
```

---

## Yapılandırma

Tüm scriptlerde değiştirilebilir değerler dosyanın en üstündedir:

| Değişken | Varsayılan | Açıklama |
|---|---|---|
| `VPS_IP` | `20.229.185.95` | VPS IP adresi |
| `VPS_PORT` | `5555` | Bore/ADB portu |
| `VPS_SSH_USER` | `root` | VPS SSH kullanıcısı |
| `VPS_SSH_PORT` | `22` | VPS SSH portu |
| `ADB_BIN` | `adb` | ADB binary yolu |
| `ADB_PORT` | `5555` | Cihaz ADB TCP portu |

**Örnek — farklı VPS ile:**
```bash
VPS_IP=1.2.3.4 VPS_PORT=9000 ./scripts/bore_tunnel_kurulum.sh arac
```

---

## Uyumluluk

| Sistem | Durum |
|---|---|
| Skywell ET5 (CoocaaOS) | ✅ Test edildi |
| Diğer CoocaaOS head unit | ✅ Aynı `sys.special.func` bypass |
| Android tabanlı head unit (root'lu) | ⚠️ `sys.special.func` çalışmayabilir, diğer ADB komutları çalışır |

---

## Lisans

MIT © Seçkin Kılınç (XemBiLL)
