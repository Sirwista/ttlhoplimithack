@echo off
title Bora TTL Manager Pro v2.0
color 0B
mode con cols=100 lines=35
setlocal enabledelayedexpansion

:: ==================== YAPILANDIRMA ====================
set "VERSION=2.0"
set "DEFAULT_TTL=65"
set "TASKNAME=Bora_TTL_Keeper"
set "LOG_FILE=%~dp0ttl_log.txt"
set "CONFIG_FILE=%~dp0ttl_config.ini"

:: ==================== ADMIN KONTROLU ====================
net session >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    cls
    echo.
    echo =========================================================
    echo              YONETICI YETKISI GEREKLI
    echo =========================================================
    echo.
    echo  [HATA] Bu program yonetici yetkisi ile calistirilmalidir!
    echo.
    echo  1. Bu dosyaya SAG TIK yapin
    echo  2. "Yonetici olarak calistir" secin
    echo  3. "EVET" deyin
    echo.
    echo =========================================================
    timeout /t 10
    exit /b 1
)

:: ==================== OTOMATIK STARTUP ====================
schtasks /Query /TN "%TASKNAME%" >nul 2>&1
if %ERRORLEVEL% NEQ 0 (
    schtasks /Create /SC ONLOGON /RL HIGHEST /TN "%TASKNAME%" /TR "\"%~f0\"" /F >nul 2>&1
)

:: ==================== CONFIG YUKLE ====================
if exist "%CONFIG_FILE%" (
    for /f "tokens=1,2 delims==" %%a in ('type "%CONFIG_FILE%" 2^>nul') do (
        if "%%a"=="LAST_TTL" set "LAST_TTL=%%b"
    )
)
if not defined LAST_TTL set "LAST_TTL=%DEFAULT_TTL%"

:: ==================== ANA MENU ====================
:menu
cls
call :get_current_ttl
echo.
echo =========================================================
echo          Bora TTL Manager Pro v%VERSION%
echo =========================================================
echo  Mevcut IPv4 TTL : !CURRENT_TTL_V4!
echo  Mevcut IPv6 TTL : !CURRENT_TTL_V6!
echo  Son Uygulanan   : %LAST_TTL%
echo  Oto. Baslatma   : !STARTUP_STATUS!
echo =========================================================
echo  [1] Hizli Ayar: TTL=%DEFAULT_TTL% (Onerilir)
echo  [2] Manuel TTL Ayarla (32-255)
echo  [3] TTL Durumu ve Baglanti Testi
echo  [4] DNS Onbellegi Temizle
echo  [5] Log Gecmisi Goruntule
echo  [6] TTL Sifirla (Varsayilana Don)
echo  [7] Otomatik Baslatma: ACIK/KAPALI
echo  [8] Hakkinda
echo  [9] Cikis
echo =========================================================
set /p "secim=Seciminiz (1-9): "

if "%secim%"=="" goto menu
if "%secim%"=="1" goto quick_set
if "%secim%"=="2" goto manual_set
if "%secim%"=="3" goto detailed_test
if "%secim%"=="4" goto flush_dns
if "%secim%"=="5" goto view_log
if "%secim%"=="6" goto reset_ttl
if "%secim%"=="7" goto toggle_startup
if "%secim%"=="8" goto about
if "%secim%"=="9" goto exit_now

echo [HATA] Gecersiz secim! Lutfen 1-9 arasi girin.
timeout /t 2 >nul
goto menu

:: ==================== HIZLI AYAR ====================
:quick_set
cls
echo.
echo =========================================================
echo              HIZLI TTL AYARI
echo =========================================================
echo.
echo TTL=%DEFAULT_TTL% uygulanıyor...
echo.
call :apply_ttl %DEFAULT_TTL% "Hizli Ayar"
call :log_action "Hizli ayar: TTL=%DEFAULT_TTL%"
echo.
echo [BASARILI] TTL=%DEFAULT_TTL% olarak ayarlandi!
goto end_prompt

:: ==================== MANUEL AYAR ====================
:manual_set
:manual_set_input
cls
echo.
echo =========================================================
echo              MANUEL TTL AYARI
echo =========================================================
echo.
call :get_current_ttl
echo Mevcut TTL  : !CURRENT_TTL_V4!
echo Gecerli Aralik: 32-255
echo.
echo Onerilen Degerler:
echo   64  - Standart Linux/Android
echo   65  - Hotspot Bypass (Onerilir)
echo  128  - Standart Windows
echo  255  - Maksimum
echo.
set /p "user_ttl=Yeni TTL Degeri: "

for /f "tokens=*" %%a in ("!user_ttl!") do set "user_ttl=%%a"

if "!user_ttl!"=="" (
    echo [HATA] Bos giris!
    timeout /t 3 >nul
    goto manual_set_input
)

set "is_valid=1"
for /f "delims=0123456789" %%i in ("!user_ttl!") do set "is_valid=0"
if "!is_valid!"=="0" (
    echo [HATA] Sadece rakam giriniz!
    timeout /t 3 >nul
    goto manual_set_input
)

if !user_ttl! LSS 32 (
    echo [HATA] Minimum deger 32!
    timeout /t 3 >nul
    goto manual_set_input
)
if !user_ttl! GTR 255 (
    echo [HATA] Maksimum deger 255!
    timeout /t 3 >nul
    goto manual_set_input
)

echo.
call :apply_ttl !user_ttl! "Manuel Ayar"
call :log_action "Manuel ayar: TTL=!user_ttl!"
echo.
echo [BASARILI] TTL=!user_ttl! olarak ayarlandi!
goto end_prompt

:: ==================== DETAYLI TEST ====================
:detailed_test
cls
echo.
echo =========================================================
echo          TTL DURUMU VE BAGLANTI TESTI
echo =========================================================
echo.
call :get_current_ttl

echo [Registry Durumu]
set "found_reg="
for /f "skip=2 tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v DefaultTTL 2^>nul') do (
    set "reg_ttl=%%a"
    call :convert_hex_to_dec "!reg_ttl!"
    echo   DefaultTTL: !hex_result! (0x!reg_ttl!)
    set "found_reg=1"
)
if not defined found_reg (
    echo   Registry'de DefaultTTL bulunamadi (Sistem varsayilani)
)
echo.
echo [Netsh Durumu]
echo   IPv4 TTL: !CURRENT_TTL_V4!
echo   IPv6 TTL: !CURRENT_TTL_V6!
echo.
echo =========================================================
echo [BAGLANTI TESTLERI] Lutfen bekleyin...
echo =========================================================
echo.

set "test1_success=0"
set "test2_success=0"
set "test3_success=0"

echo [Test 1/4] Google DNS (8.8.8.8)...
for /f "tokens=*" %%a in ('ping -n 1 -w 2000 8.8.8.8 2^>nul') do (
    echo %%a | find "TTL=" >nul
    if !errorlevel! equ 0 (
        echo   %%a
        set "test1_success=1"
    )
)
if !test1_success!==0 echo   [X] Baglanti basarisiz!
echo.

echo [Test 2/4] Cloudflare DNS (1.1.1.1)...
for /f "tokens=*" %%a in ('ping -n 1 -w 2000 1.1.1.1 2^>nul') do (
    echo %%a | find "TTL=" >nul
    if !errorlevel! equ 0 (
        echo   %%a
        set "test2_success=1"
    )
)
if !test2_success!==0 echo   [X] Baglanti basarisiz!
echo.

echo [Test 3/4] IPv6 Google...
for /f "tokens=*" %%a in ('ping -6 -n 1 -w 2000 ipv6.google.com 2^>nul') do (
    echo %%a | find "TTL=" >nul
    if !errorlevel! equ 0 (
        echo   %%a
        set "test3_success=1"
    )
)
if !test3_success!==0 echo   [-] IPv6 desteklenmiyor veya baglanti yok
echo.

echo [Test 4/4] Traceroute (ilk 3 atlama)...
for /f "tokens=*" %%a in ('tracert -d -h 3 -w 1000 8.8.8.8 2^>nul') do (
    echo %%a | find "ms" >nul
    if !errorlevel! equ 0 echo   %%a
)
echo.

echo =========================================================
echo [SONUC]
echo =========================================================
set /a "total=!test1_success!+!test2_success!"
if !total! GEQ 2 (
    echo [OK] Internet baglantisi IYI durumda.
) else if !total! EQU 1 (
    echo [!] Baglanti VAR ama SORUNLU. DNS ayarlarini kontrol edin.
) else (
    echo [X] Internet baglantisi YOK!
)
if !test3_success!==1 (echo [OK] IPv6 AKTIF) else (echo [-] IPv6 YOK/PASIF)
echo.
call :log_action "Detayli test: IPv4=%total%/2, IPv6=!test3_success!"
goto end_prompt

:: ==================== DNS TEMIZLEME ====================
:flush_dns
cls
echo.
echo =========================================================
echo              DNS ONBELLEGI TEMIZLEME
echo =========================================================
echo.
ipconfig /flushdns
echo.
call :log_action "DNS onbellegi temizlendi"
echo [BASARILI] DNS onbellegi temizlendi!
goto end_prompt

:: ==================== LOG GORUNTULEME ====================
:view_log
cls
echo.
echo =========================================================
echo                  LOG GECMISI
echo =========================================================
echo.
if exist "%LOG_FILE%" (
    type "%LOG_FILE%"
) else (
    echo Log dosyasi henuz olusturulmamis.
)
echo.
echo =========================================================
goto end_prompt

:: ==================== TTL SIFIRLAMA ====================
:reset_ttl
cls
echo.
echo =========================================================
echo           TTL SIFIRLAMA (VARSAYILAN)
echo =========================================================
echo.
netsh int ipv4 set global defaultcurhoplimit=0 >nul 2>&1
netsh int ipv6 set global defaultcurhoplimit=0 >nul 2>&1
reg delete "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v DefaultTTL /f >nul 2>&1
call :log_action "TTL varsayilana sifirlandi"
echo [BASARILI] TTL varsayilan degerlere sifirlandi!
echo   IPv4: Sistem varsayilani
echo   IPv6: Sistem varsayilani
set "LAST_TTL=Sifirlanmis"
echo LAST_TTL=Sifirlanmis>"%CONFIG_FILE%"
goto end_prompt

:: ==================== OTOMATIK BASLAT ====================
:toggle_startup
cls
echo.
echo =========================================================
echo           OTOMATIK BASLATMA AYARI
echo =========================================================
echo.
schtasks /Query /TN "%TASKNAME%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (
    schtasks /Delete /TN "%TASKNAME%" /F >nul 2>&1
    call :log_action "Otomatik baslatma kapatildi"
    echo [BASARILI] Otomatik baslatma KAPATILDI.
) else (
    schtasks /Create /SC ONLOGON /RL HIGHEST /TN "%TASKNAME%" /TR "\"%~f0\"" /F >nul 2>&1
    call :log_action "Otomatik baslatma acildi"
    echo [BASARILI] Otomatik baslatma ACILDI.
)
goto end_prompt

:: ==================== HAKKINDA ====================
:about
cls
echo.
echo =========================================================
echo         Bora TTL Manager Pro v%VERSION%
echo         Gelistirici: Bora Kundakcioglu
echo =========================================================
echo.
echo  YouTube  : https://www.youtube.com/@borakundakcioglu
echo  LinkedIn : https://www.linkedin.com/in/borakundakcioglu
echo  E-posta  : boracan357@hotmail.com
echo.
echo =========================================================
echo  Bu program Windows uzerinde TTL degerlerini yonetmenize
echo  ve mobil hotspot sinirlamalarini asmaya yardimci olur.
echo =========================================================
call :log_action "Hakkinda ekrani goruntulendi"
goto end_prompt

:: ==================== YARDIMCI FONKSIYONLAR ====================

:apply_ttl
set "ttl_value=%~1"
netsh int ipv4 set global defaultcurhoplimit=%ttl_value% >nul 2>&1
netsh int ipv6 set global defaultcurhoplimit=%ttl_value% >nul 2>&1
reg add "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v DefaultTTL /t REG_DWORD /d %ttl_value% /f >nul 2>&1
set "LAST_TTL=%ttl_value%"
echo LAST_TTL=%ttl_value%>"%CONFIG_FILE%"
echo   IPv4 TTL: %ttl_value%
echo   IPv6 TTL: %ttl_value%
echo   Registry guncellendi.
exit /b

:get_current_ttl
set "CURRENT_TTL_V4=Varsayilan"
set "CURRENT_TTL_V6=Varsayilan"
for /f "tokens=3" %%a in ('netsh int ipv4 show global 2^>nul ^| findstr /C:"Current Hop Limit"') do set "CURRENT_TTL_V4=%%a"
for /f "tokens=3" %%a in ('netsh int ipv4 show global 2^>nul ^| findstr /C:"Atlama"') do (
    if "!CURRENT_TTL_V4!"=="Varsayilan" set "CURRENT_TTL_V4=%%a"
)
for /f "tokens=3" %%a in ('netsh int ipv6 show global 2^>nul ^| findstr /C:"Current Hop Limit"') do set "CURRENT_TTL_V6=%%a"
for /f "tokens=3" %%a in ('netsh int ipv6 show global 2^>nul ^| findstr /C:"Atlama"') do (
    if "!CURRENT_TTL_V6!"=="Varsayilan" set "CURRENT_TTL_V6=%%a"
)
if "!CURRENT_TTL_V4!"=="Varsayilan" (
    for /f "skip=2 tokens=3" %%a in ('reg query "HKLM\SYSTEM\CurrentControlSet\Services\Tcpip\Parameters" /v DefaultTTL 2^>nul') do (
        call :convert_hex_to_dec "%%a"
        set "CURRENT_TTL_V4=!hex_result!"
        set "CURRENT_TTL_V6=!hex_result!"
    )
)
schtasks /Query /TN "%TASKNAME%" >nul 2>&1
if %ERRORLEVEL% EQU 0 (set "STARTUP_STATUS=ACIK") else (set "STARTUP_STATUS=KAPALI")
exit /b

:convert_hex_to_dec
set "hex_value=%~1"
set "hex_result=%hex_value%"
if "%hex_value:~0,2%"=="0x" set /a "hex_result=%hex_value%"
exit /b

:log_action
echo [%date% %time%] %~1 >> "%LOG_FILE%"
exit /b

:: ==================== CIKIS PROMPT ====================
:end_prompt
echo.
echo =========================================================
set /p "continue=Ana menuye donmek icin ENTER, cikmak icin Q: "
if /i "!continue!"=="q" goto exit_now
goto menu

:: ==================== CIKIS ====================
:exit_now
cls
echo.
echo =========================================================
echo     Bora TTL Manager Pro kapatiliyor...
echo     Tum ayarlar aktif kalmaya devam ediyor.
echo.
echo     Gelistirici : Bora Kundakcioglu
echo     YouTube     : https://www.youtube.com/@borakundakcioglu
echo =========================================================
call :log_action "Program kapatildi"
timeout /t 2 >nul
endlocal
exit /b 0
