@echo off
:: Uruchom skrypt PowerShell jako Administrator z pominiéciem ExecutionPolicy
:: Dziala bez koniecznosci naciskania ENTER - od razu startuje w nowym oknie admina

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Wymagane uprawnienia Administratora. Uruchamiam ponownie jako Admin...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\Setup-Firmowy.ps1"
