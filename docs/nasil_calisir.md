# Nasıl Çalışır — Teknik Detaylar

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

## 1. sys.special.func Bypass

### Keşif Süreci

CoocaaOS'ta WiFi ADB'yi UI olmadan açmanın yolu araştırılırken `SystemSettings.apk` decompile edildi.

`BackdoorAdapter.java` içinde:

```java
public static void setWifiAdbOpen(Context context) {
    SystemUtils.setWifiAdbOpen();
}
```

`SystemUtils.java` içinde:

```java
public static void setWifiAdbOpen() {
    SystemProperties.set("sys.special.func", "1");
}
```

Bu property Android `init` tarafından dinleniyor:

```sh
# init.rc veya vendor init içinde (muhtemelen):
on property:sys.special.func=1
    setprop service.adb.tcp.port 5555
    restart adbd
```

### Sonuç

```bash
# Gizli menü yerine (Sistem → Logo 8-9x → şifre 2281):
adb shell su 0 setprop sys.special.func 1
```

---

## 2. userinit.d Mekanizması

CoocaaOS / bazı Android head unit'lerde sistem boot'ta şunu çalıştırır:

```
/data/local/userinit.d/*.sh   → root olarak çalışır
```

Bu dizine script koymak = kalıcı boot persistence.

**Doğrulama:**
```bash
adb shell ls /data/local/userinit.d/
adb shell cat /data/local/userinit.d/01_adb_fix.sh
```

---

## 3. Boot Script İçeriği

`/data/local/userinit.d/01_adb_fix.sh`:

```sh
#!/system/bin/sh

# ADB aç — sys.special.func bypass
settings put global adb_enabled 1
settings put global adb_tcp_port 5555
setprop service.adb.tcp.port 5555
setprop sys.special.func 1

# WiFi bağlanana kadar bekle
sleep 20

# Bore watchdog başlat
nohup sh /data/local/tmp/bore_watchdog.sh > /dev/null 2>&1 &
```

---

## 4. Bore Watchdog Mantığı

`/data/local/tmp/bore_watchdog.sh`:

```sh
#!/system/bin/sh
while true; do
  # WiFi bağlı mı?
  WIFI_IP=$(ip -o -4 addr show wlan0 2>/dev/null | awk '{print $4}' | cut -d/ -f1)

  if [ -n "$WIFI_IP" ]; then
    # Bore çalışmıyor mu?
    if ! pgrep -f "bore local" > /dev/null 2>&1; then
      # Yeniden başlat
      nohup /data/local/tmp/bore local 5555 --to 20.229.185.95 >> /data/local/tmp/bore.log 2>&1 &
    fi
  fi

  sleep 15   # 15 saniyede bir kontrol
done
```

**Watchdog neden gerekli?**
- WiFi değişince (ağdan ağa geçiş) bore bağlantısı kopar
- Process crash ederse otomatik yeniden başlar
- Araç sleep/wake döngülerinde tüneli canlı tutar

---

## 5. Bore Tüneli Tekniği

[bore](https://github.com/ekzhang/bore) — Rust ile yazılmış minimal reverse tunnel aracı.

```
Araç:  bore local 5555 --to VPS_IP
VPS:   bore server --min-port 5555 --max-port 5555
```

- Araç tarafı `VPS:7835` (kontrol portu) üzerinden VPS'e bağlanır
- VPS `5555` portunu expose eder
- PC `adb connect VPS:5555` yapar → araçtaki ADB'ye ulaşır

**Neden bore?**
- Tek binary, bağımlılık yok
- ARM64 Linux binary mevcut (araç için)
- Firewall bypass (outbound bağlantı, inbound gerekmez araçta)

---

## 6. Bore Binary — ARM64

Araç tabletinin CPU mimarisi: **ARM64 (aarch64)**

```bash
# Doğrulama:
adb shell getprop ro.product.cpu.abi
# → arm64-v8a

# Binary indir:
curl -fsSL https://github.com/ekzhang/bore/releases/latest/download/bore-aarch64-unknown-linux-musl.tar.gz \
  | tar -xz

# Araca yükle:
adb push bore /data/local/tmp/bore
adb shell su 0 chmod 755 /data/local/tmp/bore
```

---

## 7. VPS Bore Server (systemd)

`/etc/systemd/system/bore-server.service`:

```ini
[Unit]
Description=Bore Reverse Tunnel Server
After=network.target

[Service]
ExecStart=/usr/local/bin/bore server --min-port 5555 --max-port 5555
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
```

```bash
systemctl enable --now bore-server
systemctl status bore-server
```

---

## 8. Sık Karşılaşılan Sorunlar

| Sorun | Çözüm |
|---|---|
| `adb connect` timeout | VPS firewall port 5555 açık mı? |
| Bore başlamıyor | ARM64 binary doğru mu? `adb shell /data/local/tmp/bore --version` |
| Boot'ta çalışmıyor | `userinit.d` dizini var mı? chmod 755 verildi mi? |
| WiFi'den sonra kopuyor | watchdog 15sn döngü — normal, bekle |
| `su 0` çalışmıyor | Cihaz root'lu değil, USB debugging gerekli |
