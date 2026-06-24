# ============================================================
#  SKRYPT DEINSTALACJI - MASZYNA TESTOWA
#  Uruchom przez: Start-Deinstalator.bat (jako Administrator)
# ============================================================

# Kolory w konsoli
function Write-Step { param($msg) Write-Host "`n>>> $msg" -ForegroundColor Cyan }
function Write-OK   { param($msg) Write-Host "    [OK] $msg" -ForegroundColor Green }
function Write-Skip { param($msg) Write-Host "    [--] $msg" -ForegroundColor Yellow }
function Write-Err  { param($msg) Write-Host "    [!!] $msg" -ForegroundColor Red }

# Sprawdz uprawnienia administratora
if (-not ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Err "Uruchom skrypt jako Administrator!"
    pause; exit 1
}

Write-Host ""
Write-Host "============================================" -ForegroundColor Red
Write-Host "  DEINSTALATOR - MASZYNA TESTOWA" -ForegroundColor Red
Write-Host "  Usuwa: AnyDesk, ESET, Chrome, Intel DSA," -ForegroundColor Red
Write-Host "         Office, McAfee, Adobe Reader" -ForegroundColor Red
Write-Host "         oraz cofa ustawienia systemu" -ForegroundColor Red
Write-Host "============================================" -ForegroundColor Red
Write-Host ""

# ============================================================
#  FUNKCJA POMOCNICZA: znajdz i odinstaluj po nazwie z rejestru
# ============================================================
function Uninstall-ByName {
    param([string]$Pattern, [string]$DisplayLabel)

    Write-Step "Odinstalowywanie: $DisplayLabel"

    $regPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
    )

    $found = $false
    foreach ($regPath in $regPaths) {
        if (-not (Test-Path $regPath)) { continue }
        $entries = Get-ChildItem $regPath
        foreach ($entry in $entries) {
            $props = $entry | Get-ItemProperty -ErrorAction SilentlyContinue
            if ($props.DisplayName -match $Pattern -and $props.UninstallString) {
                $found = $true
                $uninstall = $props.UninstallString
                Write-Host "    Znaleziono: $($props.DisplayName)" -ForegroundColor Magenta

                if ($uninstall -match "MsiExec") {
                    $guid = ($uninstall -replace "MsiExec.exe\s*/[IX]", "").Trim()
                    $proc = Start-Process "msiexec.exe" -ArgumentList "/qn /x $guid /norestart" -Wait -PassThru
                } else {
                    $proc = Start-Process "cmd.exe" -ArgumentList "/c $uninstall /S /silent /quiet /norestart" -Wait -PassThru
                }
                Write-OK "$($props.DisplayName) usunieto (kod: $($proc.ExitCode))"
            }
        }
    }

    if (-not $found) {
        Write-Skip "$DisplayLabel - nie znaleziono w systemie"
    }
}

# ============================================================
#  1. ANYDESK
# ============================================================
Write-Step "Odinstalowywanie: AnyDesk"
$anydesk = "C:\Program Files (x86)\AnyDesk\AnyDesk.exe"
if (Test-Path $anydesk) {
    $proc = Start-Process $anydesk -ArgumentList "--remove" -Wait -PassThru
    Write-OK "AnyDesk usunieto (kod: $($proc.ExitCode))"
} else {
    Uninstall-ByName -Pattern "AnyDesk" -DisplayLabel "AnyDesk (rejestr)"
}

# ============================================================
#  2. ESET
# ============================================================
Write-Step "Odinstalowywanie: ESET"

$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
$esetFound = $false
foreach ($regPath in $regPaths) {
    if (-not (Test-Path $regPath)) { continue }
    Get-ChildItem $regPath | ForEach-Object {
        $props = $_ | Get-ItemProperty -ErrorAction SilentlyContinue
        if ($props.DisplayName -match "ESET" -and $props.UninstallString) {
            $esetFound = $true
            $guid = ($props.UninstallString -replace "MsiExec.exe\s*/[IX]", "").Trim()
            Write-Host "    Znaleziono: $($props.DisplayName)" -ForegroundColor Magenta
            $proc = Start-Process "msiexec.exe" -ArgumentList "/qn /x $guid /norestart" -Wait -PassThru
            Write-OK "ESET usunieto (kod: $($proc.ExitCode))"
        }
    }
}
if (-not $esetFound) {
    Write-Skip "ESET - nie znaleziono w systemie"
}

# ============================================================
#  3. GOOGLE CHROME
# ============================================================
Uninstall-ByName -Pattern "Google Chrome" -DisplayLabel "Google Chrome"

$chromePaths = @(
    "$env:ProgramFiles\Google\Chrome",
    "${env:ProgramFiles(x86)}\Google\Chrome"
)
foreach ($p in $chromePaths) {
    if (Test-Path $p) {
        Remove-Item $p -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "Usunieto folder: $p"
    }
}

# ============================================================
#  4. INTEL DRIVER AND SUPPORT ASSISTANT
# ============================================================
Uninstall-ByName -Pattern "Intel.*(Driver|DSA|Support Assistant)" -DisplayLabel "Intel Driver and Support Assistant"

# ============================================================
#  5. McAFEE + McAFEE WEB ADVISOR
# ============================================================
Write-Step "Odinstalowywanie: McAfee"

$mcafeeFound = $false
$regPaths = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
foreach ($regPath in $regPaths) {
    if (-not (Test-Path $regPath)) { continue }
    Get-ChildItem $regPath | ForEach-Object {
        $props = $_ | Get-ItemProperty -ErrorAction SilentlyContinue
        if ($props.DisplayName -match "McAfee" -and $props.UninstallString) {
            $mcafeeFound = $true
            $uninstall = $props.UninstallString
            Write-Host "    Znaleziono: $($props.DisplayName)" -ForegroundColor Magenta
            if ($uninstall -match "MsiExec") {
                $guid = ($uninstall -replace "MsiExec.exe\s*/[IX]", "").Trim()
                $proc = Start-Process "msiexec.exe" -ArgumentList "/qn /x $guid /norestart" -Wait -PassThru
            } else {
                $proc = Start-Process "cmd.exe" -ArgumentList "/c $uninstall /quiet /norestart" -Wait -PassThru
            }
            Write-OK "$($props.DisplayName) usunieto (kod: $($proc.ExitCode))"
        }
    }
}

if (-not $mcafeeFound) {
    Write-Skip "McAfee - nie znaleziono w systemie"
} else {
    $mcafeeFolders = @(
        "C:\Program Files\McAfee",
        "C:\Program Files (x86)\McAfee",
        "C:\ProgramData\McAfee"
    )
    foreach ($folder in $mcafeeFolders) {
        if (Test-Path $folder) {
            Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
            Write-OK "Usunieto folder: $folder"
        }
    }
}

# ============================================================
#  6. MICROSOFT OFFICE - oficjalna metoda SaRA
# ============================================================
Write-Step "Odinstalowywanie: Microsoft Office"

$officeKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)
$officeFound = $false
foreach ($regPath in $officeKeys) {
    if (Test-Path $regPath) {
        Get-ChildItem $regPath | ForEach-Object {
            $props = $_ | Get-ItemProperty -ErrorAction SilentlyContinue
            if ($props.DisplayName -match "Microsoft 365|Microsoft Office|Office 16|Office 15|Office 14") {
                $officeFound = $true
            }
        }
    }
}
$c2rFound = Test-Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

if (-not $officeFound -and -not $c2rFound) {
    Write-Skip "Microsoft Office - nie znaleziono w systemie"
} else {
    Write-Host ""
    Write-Host "    UWAGA: Zostanie otwarta oficjalna strona Microsoft do odinstalowania Office." -ForegroundColor Yellow
    Write-Host "    Postepuj zgodnie z instrukcjami na stronie (narzedzie SaRA)." -ForegroundColor Yellow
    Write-Host "    Po zakonczeniu odinstalowania - wróc do tego okna i nacisnij ENTER." -ForegroundColor Yellow
    Write-Host ""
    Start-Process "https://aka.ms/SaRA-officeUninstallFromPC"
    Write-Host "    Nacisnij ENTER gdy Office zostanie odinstalowany..." -ForegroundColor Green
    $null = Read-Host
    Write-OK "Kontynuowanie po odinstalowaniu Office"
}

# ============================================================
#  7. ADOBE READER
# ============================================================
Uninstall-ByName -Pattern "Adobe Acrobat Reader|Adobe Reader" -DisplayLabel "Adobe Acrobat Reader"

$adobeFolders = @(
    "C:\Program Files\Adobe\Acrobat Reader DC",
    "C:\Program Files (x86)\Adobe\Acrobat Reader DC",
    "C:\Program Files\Adobe\Reader",
    "C:\Program Files (x86)\Adobe\Reader"
)
foreach ($folder in $adobeFolders) {
    if (Test-Path $folder) {
        Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
        Write-OK "Usunieto folder: $folder"
    }
}

# ============================================================
#  8. COFNIECIE USTAWIEN ZASILANIA
# ============================================================
Write-Step "Cofanie ustawien zasilania do domyslnych"

$balancedGUID = (powercfg /list | Select-String "Zrownow|Balanced" | ForEach-Object { ($_ -split "\s+")[3] })
if ($balancedGUID) {
    powercfg /setactive $balancedGUID
    Write-OK "Plan zasilania: Zrownowazony przywrocony"
}

powercfg /change monitor-timeout-ac 10
powercfg /change monitor-timeout-dc 5
Write-OK "Wygaszenie ekranu: 10 min (AC), 5 min (DC)"

powercfg /change standby-timeout-ac 30
powercfg /change standby-timeout-dc 15
Write-OK "Usypianie: 30 min (AC), 15 min (DC)"

Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "1" -Force
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "600" -Force
Write-OK "Wygaszacz ekranu: przywrocony (10 min)"

powercfg /hibernate on
Write-OK "Hibernacja: przywrocona"

# ============================================================
#  9. PRZYWROCENIE EXECUTION POLICY
# ============================================================
Write-Step "Przywracanie ExecutionPolicy"

Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process -Force -ErrorAction SilentlyContinue
Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser -Force -ErrorAction SilentlyContinue

try {
    Set-ExecutionPolicy -ExecutionPolicy Restricted -Scope LocalMachine -Force -ErrorAction Stop
    Write-OK "ExecutionPolicy LocalMachine przywrocona do: Restricted"
} catch {
    Write-Skip "ExecutionPolicy jest zarzadzana przez GPO (polityka domenowa) - pomijam"
}

# ============================================================
#  PODSUMOWANIE
# ============================================================
Write-Host ""
Write-Host "============================================" -ForegroundColor Green
Write-Host "  GOTOWE! Maszyna testowa wyczyszczona." -ForegroundColor Green
Write-Host "  Mozesz uruchomic Setup-Firmowy.ps1" -ForegroundColor Green
Write-Host "  aby zaczac od nowa." -ForegroundColor Green
Write-Host "============================================" -ForegroundColor Green
Write-Host ""
pause
