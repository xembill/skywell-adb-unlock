@echo off
:: Seçkin Kılınç
:: XemBiLL
:: xembill at gmail.com
:: =============================================================
::  coocaa_adb_unlock_forUmit.bat — CoocaaOS WiFi ADB Unlock (Windows)
:: =============================================================
::  Keşif: SystemSettings.apk → BackdoorAdapter.java
::    SystemUtils.setWifiAdbOpen()
::    → SystemProperties.set("sys.special.func", "1")
::
::  Gizli menü adımları GEREKMEZ:
::    Sistem → Logo 8-9x → şifre 2281 → ADB Aç
::
::  Kullanım:
::    coocaa_adb_unlock.bat                       (USB cihaz)
::    coocaa_adb_unlock.bat 192.168.1.100          (TCP bağlantısı)
::    coocaa_adb_unlock.bat 192.168.1.100 persist  (+ boot kalıcılığı)
::    coocaa_adb_unlock.bat scan                   (ağı tara)
:: =============================================================

setlocal enabledelayedexpansion

set ADB=adb
set PORT=5555
set COOCAA_PROP=sys.special.func
set COOCAA_VAL=1
set SERIAL=
set OPT_IP=
set OPT_PERSIST=0
set OPT_SCAN=0

:: ── Başlık ───────────────────────────────────────────────────
echo.
echo =======================================================
echo   CoocaaOS WiFi ADB Unlock
echo   sys.special.func bypass
echo =======================================================
echo.

:: ── Argümanları işle ─────────────────────────────────────────
if "%~1"==""       goto :usb_mode
if "%~1"=="scan"   goto :scan_mode
if "%~1"=="help"   goto :show_help
if "%~1"=="/?"     goto :show_help

:: IP adresi verilmiş
set OPT_IP=%~1
if "%~2"=="persist" set OPT_PERSIST=1
goto :tcp_mode

:: ── USB Modu ──────────────────────────────────────────────────
:usb_mode
echo [BAGLANTI] USB cihaz aranıyor...
for /f "skip=1 tokens=1,2" %%a in ('adb devices 2^>nul') do (
  if "%%b"=="device" (
    set SERIAL=%%a
    echo   OK Cihaz bulundu: %%a
    goto :device_found
  )
)
echo   HATA Bagli ADB cihazi yok. USB takin veya IP girin.
echo   Kullanim: %~nx0 ^<ip^>
goto :end_fail

:: ── TCP Modu ──────────────────────────────────────────────────
:tcp_mode
echo [BAGLANTI] TCP baglaniyor: %OPT_IP%:%PORT%
%ADB% connect %OPT_IP%:%PORT% > nul 2>&1
set SERIAL=%OPT_IP%:%PORT%
:: Bağlantı kontrolü
for /f "skip=1 tokens=1,2" %%a in ('adb devices 2^>nul') do (
  if "%%a"=="%SERIAL%" (
    if "%%b"=="device" (
      echo   OK Baglandi: %SERIAL%
      goto :device_found
    )
  )
)
echo   HATA Baglanamadi: %OPT_IP%:%PORT%
goto :end_fail

:: ── Tarama Modu ───────────────────────────────────────────────
:scan_mode
echo [TARAMA MODU] Ag taranıyor (port %PORT%)...
echo.

:: Yerel IP'yi bul
for /f "tokens=2 delims=:" %%a in ('ipconfig ^| findstr /i "IPv4"') do (
  set LOCAL_IP=%%a
  set LOCAL_IP=!LOCAL_IP: =!
  goto :got_local_ip
)
:got_local_ip
:: Son okteti al ve /24 tara
for /f "tokens=1-4 delims=." %%a in ("%LOCAL_IP%") do (
  set NET_PREFIX=%%a.%%b.%%c
)

echo   Yerel IP : %LOCAL_IP%
echo   Taranan  : %NET_PREFIX%.1-254
echo.

set FOUND_IPS=
for /L %%i in (1,1,254) do (
  set TEST_IP=%NET_PREFIX%.%%i
  (
    echo open !TEST_IP! %PORT%
    echo quit
  ) | telnet 2>nul | findstr /i "connected" > nul 2>&1
  if !errorlevel!==0 (
    echo   ADB port acik: !TEST_IP!:%PORT%
    set FOUND_IPS=!TEST_IP!
  )
)

if "!FOUND_IPS!"=="" (
  echo   HATA Hic cihaz bulunamadi.
  goto :end_fail
)

set OPT_IP=!FOUND_IPS!
echo.
echo   Bulunan cihaz: !OPT_IP!
set /p CONFIRM="  Bu cihaza unlock uygulansin mi? [E/h]: "
if /i "!CONFIRM!"=="h" goto :end_fail
goto :tcp_mode

:: ── Cihaz Bulundu ─────────────────────────────────────────────
:device_found
echo.
echo [CIHAZ BILGISI]

if defined SERIAL (
  set ADB_S=%ADB% -s %SERIAL%
) else (
  set ADB_S=%ADB%
)

for /f "tokens=*" %%a in ('!ADB_S! shell getprop ro.product.manufacturer 2^>nul') do echo   Uretici  : %%a
for /f "tokens=*" %%a in ('!ADB_S! shell getprop ro.product.model 2^>nul') do echo   Model    : %%a

echo.
echo [KILIT ACMA]
echo   setprop %COOCAA_PROP%=%COOCAA_VAL% uygulanıyor...

!ADB_S! shell su 0 "setprop %COOCAA_PROP% %COOCAA_VAL%" > nul 2>&1
!ADB_S! shell su 0 "settings put global adb_enabled 1" > nul 2>&1
!ADB_S! shell su 0 "settings put global adb_tcp_port %PORT%" > nul 2>&1
!ADB_S! shell su 0 "setprop service.adb.tcp.port %PORT%" > nul 2>&1

:: Doğrula
timeout /t 1 /nobreak > nul
for /f "tokens=*" %%a in ('!ADB_S! shell getprop %COOCAA_PROP% 2^>nul') do set ACTUAL_VAL=%%a

:: Boşluk/CR temizle
set ACTUAL_VAL=%ACTUAL_VAL: =%
set ACTUAL_VAL=%ACTUAL_VAL:	=%

if "%ACTUAL_VAL%"=="%COOCAA_VAL%" (
  echo   OK WiFi ADB aktif! ^(%COOCAA_PROP%=%ACTUAL_VAL%^)
) else (
  echo   UYARI Deger dogrulanamadi. Yine de devam ediliyor...
  echo   Beklenen: %COOCAA_VAL%   Gercel: %ACTUAL_VAL%
)

:: ── Kalıcılık ─────────────────────────────────────────────────
if "%OPT_PERSIST%"=="1" goto :do_persist
goto :done

:do_persist
echo.
echo [KALICILIK]
echo   Boot scripti yukleniyor...

:: Geçici dosya oluştur
set TMP_SCRIPT=%TEMP%\coocaa_persist.sh
(
  echo #!/system/bin/sh
  echo # CoocaaOS WiFi ADB kalici aktiflestiricisi
  echo settings put global adb_enabled 1
  echo settings put global adb_tcp_port 5555
  echo setprop service.adb.tcp.port 5555
  echo setprop sys.special.func 1
) > "%TMP_SCRIPT%"

!ADB_S! shell su 0 "mkdir -p /data/local/userinit.d" > nul 2>&1
!ADB_S! push "%TMP_SCRIPT%" /data/local/tmp/01_coocaa_adb.sh > nul 2>&1
!ADB_S! shell su 0 "mv /data/local/tmp/01_coocaa_adb.sh /data/local/userinit.d/01_coocaa_adb.sh" > nul 2>&1
!ADB_S! shell su 0 "chmod 755 /data/local/userinit.d/01_coocaa_adb.sh" > nul 2>&1
del "%TMP_SCRIPT%" > nul 2>&1

echo   OK Yuklendi: /data/local/userinit.d/01_coocaa_adb.sh
goto :done

:: ── Yardım ───────────────────────────────────────────────────
:show_help
echo.
echo Kullanim:
echo   %~nx0                          USB bagli cihaz
echo   %~nx0 ^<ip^>                     TCP baglantiis
echo   %~nx0 ^<ip^> persist             TCP + boot kaliciligi
echo   %~nx0 scan                      Agi tara, cihaz bul
echo.
echo Ornekler:
echo   %~nx0 10.13.180.165
echo   %~nx0 10.13.180.165 persist
echo   %~nx0 scan
goto :eof

:: ── Tamamlandı ────────────────────────────────────────────────
:done
echo.
echo =======================================================
echo   TAMAMLANDI
if defined OPT_IP echo   Baglanti : adb connect %OPT_IP%:%PORT%
echo   Sifre    : GEREKMEZ ^(setprop bypass aktif^)
if "%OPT_PERSIST%"=="1" echo   Kalici   : Her boot'ta otomatik acilir
echo =======================================================
echo.
endlocal
exit /b 0

:end_fail
echo.
echo   Islem basarisiz. Cikiliyor.
echo.
endlocal
exit /b 1
