@echo off
:: Seçkin Kılınç
:: XemBiLL
:: xembill at gmail.com
:: =============================================================
::  bore_tunnel_kurulum.bat — Bore Reverse Tunnel Tam Kurulum
::  Windows
:: =============================================================
::
::  MİMARİ:
::    Araç (tablet) ──bore──► VPS:PORT ◄── adb connect ── PC
::
::  KOMUTLAR:
::    bore_tunnel_kurulum.bat arac          Araca kur (ADB/USB)
::    bore_tunnel_kurulum.bat arac <ip>     Araca kur (TCP)
::    bore_tunnel_kurulum.bat vps           VPS kurulum komutu göster
::    bore_tunnel_kurulum.bat baglan        Bu PC'den bağlan
::    bore_tunnel_kurulum.bat durum         Tunnel durumu
::    bore_tunnel_kurulum.bat kaldir        Araçtan kaldır
::
:: =============================================================
::  YAPILANDIRMA — İSTEĞE GÖRE DEĞİŞTİRİN
:: =============================================================
set VPS_IP=20.229.185.95
set VPS_PORT=5555
set VPS_SSH_USER=root
set VPS_SSH_PORT=22
set ADB_PORT=5555
set ADB=adb
:: =============================================================

setlocal enabledelayedexpansion

set CMD=%~1
set OPT_IP=%~2
set SERIAL=

echo.
echo =======================================================
echo   Bore Reverse Tunnel Kurulum Araci
echo   VPS: %VPS_IP%:%VPS_PORT%
echo =======================================================
echo.

if "%CMD%"==""       goto :show_help
if "%CMD%"=="help"   goto :show_help
if "%CMD%"=="/?"     goto :show_help
if "%CMD%"=="arac"   goto :cmd_arac
if "%CMD%"=="vps"    goto :cmd_vps
if "%CMD%"=="baglan" goto :cmd_baglan
if "%CMD%"=="durum"  goto :cmd_durum
if "%CMD%"=="kaldir" goto :cmd_kaldir

echo   HATA: Bilinmeyen komut: %CMD%
goto :show_help

:: ── ARAÇ KURULUMU ─────────────────────────────────────────────
:cmd_arac
echo [BAGLANTI]
if not "%OPT_IP%"=="" (
  echo   TCP baglaniyor: %OPT_IP%:%ADB_PORT%
  %ADB% connect %OPT_IP%:%ADB_PORT% > nul 2>&1
  set SERIAL=%OPT_IP%:%ADB_PORT%
  echo   OK Baglandi: !SERIAL!
) else (
  for /f "skip=1 tokens=1,2" %%a in ('%ADB% devices 2^>nul') do (
    if "%%b"=="device" (
      set SERIAL=%%a
      echo   OK USB Cihaz: %%a
      goto :arac_device_found
    )
  )
  echo   HATA ADB cihazi yok. USB takin veya: %~nx0 arac ^<ip^>
  goto :end_fail
)
:arac_device_found

set ADB_S=%ADB% -s !SERIAL!

echo.
echo [WATCHDOG SCRIPT]
echo   bore_watchdog.sh olusturuluyor...

set TMP_WD=%TEMP%\bore_watchdog.sh
(
  echo #!/system/bin/sh
  echo # Bore Tunnel Watchdog
  echo # Seckin Kilinc / XemBiLL
  echo VPS_IP="%VPS_IP%"
  echo VPS_PORT="%VPS_PORT%"
  echo BORE_BIN="/data/local/tmp/bore"
  echo LOG="/data/local/tmp/bore.log"
  echo.
  echo while true; do
  echo   WIFI_IP=$(ip -o -4 addr show wlan0 2>/dev/null ^| awk '{print $4}' ^| cut -d/ -f1 ^| head -1^)
  echo   if [ -n "$WIFI_IP" ]; then
  echo     if ! pgrep -f "bore local" ^> /dev/null 2^>^&1; then
  echo       echo "$(date^): bore baslatiliyor..." ^>^> "$LOG"
  echo       nohup "$BORE_BIN" local "$VPS_PORT" --to "$VPS_IP" ^>^> "$LOG" 2^>^&1 ^&
  echo     fi
  echo   fi
  echo   sleep 15
  echo done
) > "%TMP_WD%"

!ADB_S! push "%TMP_WD%" /data/local/tmp/bore_watchdog.sh > nul
!ADB_S! shell su 0 "chmod 755 /data/local/tmp/bore_watchdog.sh" > nul
del "%TMP_WD%" > nul 2>&1
echo   OK bore_watchdog.sh yuklendi

echo.
echo [BOOT SCRIPT]
echo   userinit.d boot scripti olusturuluyor...

set TMP_BOOT=%TEMP%\bore_boot.sh
(
  echo #!/system/bin/sh
  echo # CoocaaOS ADB + Bore Tunnel Boot Script
  echo # Seckin Kilinc / XemBiLL
  echo settings put global adb_enabled 1
  echo settings put global adb_tcp_port %ADB_PORT%
  echo setprop service.adb.tcp.port %ADB_PORT%
  echo setprop sys.special.func 1
  echo sleep 20
  echo nohup sh /data/local/tmp/bore_watchdog.sh ^> /dev/null 2^>^&1 ^&
) > "%TMP_BOOT%"

!ADB_S! shell su 0 "mkdir -p /data/local/userinit.d" > nul
!ADB_S! push "%TMP_BOOT%" /data/local/tmp/01_adb_fix.sh > nul
!ADB_S! shell su 0 "mv /data/local/tmp/01_adb_fix.sh /data/local/userinit.d/01_adb_fix.sh" > nul
!ADB_S! shell su 0 "chmod 755 /data/local/userinit.d/01_adb_fix.sh" > nul
del "%TMP_BOOT%" > nul 2>&1
echo   OK 01_adb_fix.sh yuklendi

echo.
echo [HEMEN BASALT]
!ADB_S! shell su 0 "settings put global adb_enabled 1" > nul
!ADB_S! shell su 0 "setprop sys.special.func 1" > nul
!ADB_S! shell su 0 "setprop service.adb.tcp.port %ADB_PORT%" > nul
!ADB_S! shell su 0 "nohup sh /data/local/tmp/bore_watchdog.sh > /dev/null 2>&1 &" > nul
echo   OK ADB ve watchdog baslatildi

goto :done_arac

:done_arac
echo.
echo =======================================================
echo   ARAC KURULUMU TAMAMLANDI
echo   Boot'ta otomatik: ADB acilir + bore tunnel kurulur
echo   Baglanmak icin:
echo     adb connect %VPS_IP%:%VPS_PORT%
echo =======================================================
goto :eof

:: ── VPS KURULUMU ──────────────────────────────────────────────
:cmd_vps
echo [VPS KURULUMU]
echo   VPS'te asagidaki komutlari calistirin:
echo   SSH: ssh %VPS_SSH_USER%@%VPS_IP% -p %VPS_SSH_PORT%
echo.
echo   ---- VPS Komutlari ----
echo.
echo   # 1. bore binary indir (x86_64)
echo   curl -fsSL https://github.com/ekzhang/bore/releases/latest/download/bore-x86_64-unknown-linux-musl.tar.gz ^| tar -xz -C /usr/local/bin/
echo   chmod +x /usr/local/bin/bore
echo.
echo   # 2. systemd service olustur
echo   cat ^> /etc/systemd/system/bore-server.service ^<^<EOF
echo   [Unit]
echo   Description=Bore Reverse Tunnel Server
echo   After=network.target
echo   [Service]
echo   ExecStart=/usr/local/bin/bore server --min-port %VPS_PORT% --max-port %VPS_PORT%
echo   Restart=always
echo   RestartSec=5
echo   [Install]
echo   WantedBy=multi-user.target
echo   EOF
echo.
echo   # 3. Baslat
echo   systemctl daemon-reload
echo   systemctl enable --now bore-server
echo.
echo   # 4. Firewall
echo   ufw allow %VPS_PORT%/tcp
echo   ---- VPS Komutlari Sonu ----
echo.
echo   NOT: bore_tunnel_kurulum.sh (Linux/Mac) ile otomatik kurulum yapilabilir.
goto :eof

:: ── BAĞLAN ────────────────────────────────────────────────────
:cmd_baglan
echo [BAGLAN]
echo   adb connect %VPS_IP%:%VPS_PORT%
%ADB% connect %VPS_IP%:%VPS_PORT%
if errorlevel 1 (
  echo   HATA Baglanamadi.
  echo   Arac uyanik ve WiFi bagli mi?
  goto :end_fail
)
echo   OK Baglandi!
echo   Kullanim: adb -s %VPS_IP%:%VPS_PORT% shell
goto :eof

:: ── DURUM ─────────────────────────────────────────────────────
:cmd_durum
echo [DURUM KONTROLU]

echo   VPS port kontrol: %VPS_IP%:%VPS_PORT%
(
  echo open %VPS_IP% %VPS_PORT%
  echo quit
) | telnet 2>nul | findstr /i "connected" > nul 2>&1
if !errorlevel!==0 (
  echo   OK VPS portu acik
) else (
  echo   HATA VPS portuna ulasilamiyor
)

echo   ADB kontrol...
%ADB% connect %VPS_IP%:%VPS_PORT% > nul 2>&1
for /f "skip=1 tokens=1,2" %%a in ('%ADB% devices 2^>nul') do (
  if "%%a"=="%VPS_IP%:%VPS_PORT%" (
    if "%%b"=="device" (
      echo   OK ADB bagli: %VPS_IP%:%VPS_PORT%
      goto :durum_ok
    )
  )
)
echo   HATA ADB baglanamadi
:durum_ok
goto :eof

:: ── KALDIR ────────────────────────────────────────────────────
:cmd_kaldir
echo [KALDIR]
if not "%OPT_IP%"=="" (
  %ADB% connect %OPT_IP%:%ADB_PORT% > nul 2>&1
  set SERIAL=%OPT_IP%:%ADB_PORT%
  set ADB_S=%ADB% -s !SERIAL!
) else (
  set ADB_S=%ADB%
)
!ADB_S! shell su 0 "pkill -f 'bore local' 2>/dev/null; pkill -f bore_watchdog 2>/dev/null; rm -f /data/local/tmp/bore_watchdog.sh /data/local/userinit.d/01_adb_fix.sh /data/local/tmp/bore.log"
echo   OK Kaldirildi.
goto :eof

:: ── YARDIM ────────────────────────────────────────────────────
:show_help
echo Kullanim:
echo   %~nx0 arac [ip]      Araca kur (USB veya TCP)
echo   %~nx0 vps            VPS kurulum komutlari goster
echo   %~nx0 baglan         Bu PC'den araca baglan
echo   %~nx0 durum          Tunnel durumunu kontrol et
echo   %~nx0 kaldir [ip]    Aractan kaldır
echo.
echo Yapilandirma (dosya basindaki SET satirlari):
echo   VPS_IP       = %VPS_IP%
echo   VPS_PORT     = %VPS_PORT%
echo   VPS_SSH_USER = %VPS_SSH_USER%
goto :eof

:end_fail
exit /b 1
