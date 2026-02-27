# Klima ve Sunroof Kontrolü

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

Skywell ET5 üzerinde ADB ile klima ve cam tavan (sunroof) açma/kapama komutları.

---

## Gereksinim

- ADB bağlantısı aktif olmalı (USB veya VPS tüneli)
- `su 1000` (system UID) yetkisi gerekiyor

```bash
# VPS üzerinden bağlıysan önce:
adb connect 20.229.185.95:5555
```

---

## Klima (HVAC)

### Yöntem 1 — REMOTE_CONTROL Broadcast ✅ (Önerilen)

```bash
# KLİMA AÇ
adb shell "su 1000 am broadcast \
  -a com.skyworth.car.aisettings.action.REMOTE_CONTROL \
  -p com.skyworth.car.aisettings \
  --es MQTT_PAYLOAD '{\"content\":{\"intention\":\"airconditioner\",\"car_module\":\"power\",\"number\":1}}'"

# KLİMA KAPAT
adb shell "su 1000 am broadcast \
  -a com.skyworth.car.aisettings.action.REMOTE_CONTROL \
  -p com.skyworth.car.aisettings \
  --es MQTT_PAYLOAD '{\"content\":{\"intention\":\"airconditioner\",\"car_module\":\"power\",\"number\":0}}'"
```

### Yöntem 2 — SQLite DB + App Restart ✅ (Açma için daha güvenilir)

```bash
# KLİMA AÇ
adb shell "su 0 sqlite3 /data/user/0/com.coolwell.ai.skyhvac/databases/com.coolwell.ai.skyhvac.database \
  \"UPDATE airconditioner SET power='1' WHERE _id=1;\""
adb shell "su 0 am force-stop com.coolwell.ai.skyhvac"
adb shell "am start -n com.coolwell.ai.skyhvac/.SkyHvacActivity"
# 3-5 saniye bekle → VHAL 0x15200510 = [1] → klima fiziksel açılır ✅
```

> ⚠️ Kapatma için Yöntem 2 güvenilir değil (DB `power=0` MCU'ya OFF göndermeyebilir). Kapatmak için Yöntem 1'i kullan.

---

## Sunroof (Cam Tavan)

```bash
# SUNROOF AÇ
adb shell "su 1000 am broadcast \
  -a com.skyworth.car.aisettings.action.REMOTE_CONTROL \
  -p com.skyworth.car.aisettings \
  --es MQTT_PAYLOAD '{\"content\":{\"intention\":\"skylight\",\"number\":1}}'"

# SUNROOF KAPAT
adb shell "su 1000 am broadcast \
  -a com.skyworth.car.aisettings.action.REMOTE_CONTROL \
  -p com.skyworth.car.aisettings \
  --es MQTT_PAYLOAD '{\"content\":{\"intention\":\"skylight\",\"number\":0}}'"
```

---

## Nasıl Çalışır

```
adb shell su 1000 am broadcast
        │
        ▼
AISettingsService (UID 1000)
  └── SkyguardMessageReceiver
        │  REMOTE_CONTROL broadcast
        ▼
  VehicleControlHvacControllerV2
        │  CarHvacManager.setBooleanProperty()
        ▼
  VHAL (Vehicle HAL)
        │  0x15200510 = HVAC_POWER_ON
        ▼
  MCU → CAN bus → Fiziksel kontrol ✅
```

`VehicleSetting.apk` decompile edilerek (`jadx`) `AISettingsService.java` → `SkyguardMessageReceiver` içinden çözüldü.

---

## Durum Tablosu

| Komut | Yöntem | Durum |
|---|---|---|
| Klima aç | Broadcast / DB+restart | ✅ Çalışıyor |
| Klima kapat | Broadcast | ✅ Çalışıyor |
| Sunroof aç | Broadcast | ✅ Çalışıyor |
| Sunroof kapat | Broadcast | ✅ Çalışıyor |
| Kapı kilidi | — | ❌ Broadcast'e dahil değil |
| Cam kontrolü | — | ❌ Tam format bilinmiyor |

---

## VHAL Property Referansı

| Property | Hex | Açıklama |
|---|---|---|
| HVAC_POWER_ON | `0x15200510` | Klima güç (bool) |
| HVAC_FAN_SPEED | `0x15400500` | Fan hızı (1–7) |
| HVAC_AUTO_ON | `0x1520050a` | Oto mod (bool) |
| HVAC_TEMPERATURE_SET | `0x15600503` | Sıcaklık ayarı |
