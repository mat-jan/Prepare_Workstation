@echo off
:: Uruchom deinstalator jako Administrator

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Wymagane uprawnienia Administratora. Uruchamiam ponownie jako Admin...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

powershell.exe -NoProfile -ExecutionPolicy Bypass -File "%~dp0files\Deinstalator.ps1"
