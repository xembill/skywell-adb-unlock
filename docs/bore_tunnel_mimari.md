# Bore Tunnel Mimarisi

> **Seçkin Kılınç (XemBiLL)** · xembill at gmail.com

---

## Genel Mimari

```
┌─────────────────────────────────────────────────────────────┐
│  ARAÇ                                                        │
│                                                              │
│  Android Tablet (CoocaaOS)                                   │
│  ├── ADB daemon         :5555                                │
│  ├── bore binary        /data/local/tmp/bore                 │
│  ├── bore_watchdog.sh   (15sn döngü)                         │
│  └── 01_adb_fix.sh      (boot'ta çalışır)                    │
│                                                              │
│  bore local 5555 --to VPS_IP  ──────────────────────────┐   │
└─────────────────────────────────────────────────────────│───┘
                                                          │
                             outbound TCP (araç→VPS)      │
                             firewall bypass              │
                                                          ▼
┌─────────────────────────────────────────────────────────────┐
│  VPS (sabit IP: 20.229.185.95)                               │
│                                                              │
│  bore server                                                 │
│  ├── Kontrol portu  :7835  (bore internal)                   │
│  └── Tunnel portu   :5555  (dışarıya açık)                   │
│                                                              │
│  systemd: bore-server.service (always restart)              │
└──────────────────────────────┬──────────────────────────────┘
                               │
                    inbound TCP :5555
                               │
┌──────────────────────────────▼──────────────────────────────┐
│  PC / Mac (herhangi bir ağdan)                               │
│                                                              │
│  adb connect 20.229.185.95:5555                              │
│  adb shell ...                                               │
│  adb push / pull ...                                         │
└─────────────────────────────────────────────────────────────┘
```

---

## Bağlantı Akışı

```
1. Araç boot olur
       │
       ▼
2. userinit.d/01_adb_fix.sh çalışır (root)
       │
       ├─► setprop sys.special.func 1   → WiFi ADB açılır (:5555)
       └─► sleep 20 → bore_watchdog.sh başlar
       │
       ▼
3. bore_watchdog.sh döngüsü (her 15sn)
       │
       ├─► WiFi bağlı mı? → EVET
       ├─► bore çalışıyor mu? → HAYIR
       └─► bore local 5555 --to VPS_IP başlatılır
       │
       ▼
4. VPS bore-server bağlantıyı kabul eder
   VPS:5555 → Araç:5555 tüneli kurulur
       │
       ▼
5. PC: adb connect VPS_IP:5555
   → Araç ADB daemon'a ulaşılır
```

---

## Port Haritası

| Port | Nerede | Ne işe yarar |
|------|--------|--------------|
| 5555 | Araç (tablet) | ADB TCP daemon |
| 7835 | VPS | Bore kontrol portu (internal) |
| 5555 | VPS | Bore tunnel portu (dışarıya açık) |
| 22   | VPS | SSH (kurulum için) |

---

## Güvenlik Notu

- Bore tüneli şifreleme **içermez** — güvenilir VPS kullanın
- VPS firewall: sadece 5555 portunu açın, diğer portları kısıtlayın
- ADB root erişimi verdiğinden araç üzerinde tam kontrol sağlar
