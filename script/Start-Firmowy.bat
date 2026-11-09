@echo off
:: Uruchamia kreator Prepare Workstation (GUI) jako Administrator.
:: ExecutionPolicy jest omijana tylko dla tego jednego procesu.

net session >nul 2>&1
if %errorlevel% neq 0 (
    echo Wymagane uprawnienia Administratora. Uruchamiam ponownie jako Admin...
    powershell -Command "Start-Process '%~f0' -Verb RunAs"
    exit /b
)

start "" powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File "%~dp0files\Setup-Firmowy.ps1"
