@echo off
REM SAKLAZ Gateway'i bu bilgisayarda baslatir (gelistirme).
REM Ilk calistirmada .env ve cihaz tokeni olusturulur.
cd /d "%~dp0gateway"
node scripts\setup-local.ts
if errorlevel 1 goto :eof
echo.
echo Gateway baslatiliyor... Kapatmak icin Ctrl+C.
echo (Windows Guvenlik Duvari soru sorarsa "Ozel aglar" icin izin verin.)
node --env-file=.env src\server.ts
