# ============================================================
#  SKRYPT PRZYGOTOWANIA KOMPUTERA FIRMOWEGO
#  Uruchom przez: Start-Firmowy.bat (jako Administrator)
# ============================================================

#region --- KONFIGURACJA ---
$InstallerPath = "C:\instalki"   # <-- folder z instalatorami
#endregion

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

# Sprawdz czy folder z instalatorami istnieje
if (-not (Test-Path $InstallerPath)) {
    Write-Err "Folder $InstallerPath nie istnieje! Utworz go i wgraj instalatory."
    pause; exit 1
}

# ============================================================
#  KROK 0: NAZWA KOMPUTERA
# ============================================================
Write-Step "Ustawianie nazwy komputera"
Add-Type -AssemblyName Microsoft.VisualBasic
$currentName = $env:COMPUTERNAME
$newName = [Microsoft.VisualBasic.Interaction]::InputBox(
    "Aktualna nazwa komputera: $currentName`n`nWpisz nowa nazwe komputera (tylko litery, cyfry, myslniki; max 15 znakow):",
    "Nazwa komputera",
    $currentName
)

if ($newName -ne "" -and $newName -ne $currentName) {
    if ($newName -match "^[a-zA-Z0-9\-]{1,15}$") {
        Rename-Computer -NewName $newName -Force
        Write-OK "Nazwa komputera zmieniona na: $newName (wejdzie w zycie po restarcie)"
    } else {
        Write-Err "Nieprawidlowa nazwa! Pomijam zmiane nazwy."
    }
} else {
    Write-Skip "Nazwa komputera bez zmian: $currentName"
}

# ============================================================
#  KROK 1: WYGASZACZ EKRANU I HIBERNACJA - NIGDY
# ============================================================
Write-Step "Ustawianie zasilania: wygaszacz i hibernacja = nigdy"

Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive" -Value "0" -Force
Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "0" -Force
Write-OK "Wygaszacz ekranu: wylaczony"

$highPerfGUID = (powercfg /list | Select-String "Wysoka" | ForEach-Object { ($_ -split "\s+")[3] })
if (-not $highPerfGUID) {
    $highPerfGUID = (powercfg /list | Select-String "High performance" | ForEach-Object { ($_ -split "\s+")[3] })
}
if ($highPerfGUID) {
    powercfg /setactive $highPerfGUID
    Write-OK "Plan zasilania: Wysoka wydajnosc aktywny"
} else {
    Write-Skip "Nie znaleziono planu Wysoka wydajnosc, edytuje aktywny plan"
}

powercfg /change monitor-timeout-ac 0
powercfg /change monitor-timeout-dc 0
Write-OK "Wygaszenie ekranu: nigdy"

powercfg /change standby-timeout-ac 0
powercfg /change standby-timeout-dc 0
Write-OK "Usypianie: nigdy"

powercfg /hibernate off
Write-OK "Hibernacja: wylaczona"

# ============================================================
#  KROK 2a: ODINSTALOWANIE McAFEE
# ============================================================
Write-Step "Szukanie instalacji McAfee do usuniecia..."

$mcafeeKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$mcafeeFound = @()
foreach ($regPath in $mcafeeKeys) {
    if (Test-Path $regPath) {
        Get-ChildItem $regPath | ForEach-Object {
            $displayName = ($_ | Get-ItemProperty -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
            $uninstallStr = ($_ | Get-ItemProperty -Name UninstallString -ErrorAction SilentlyContinue).UninstallString
            if ($displayName -match "McAfee" -and $uninstallStr) {
                $mcafeeFound += [PSCustomObject]@{ Name = $displayName; Uninstall = $uninstallStr }
            }
        }
    }
}

if ($mcafeeFound.Count -eq 0) {
    Write-Skip "Nie znaleziono instalacji McAfee - pomijam"
} else {
    Write-Host "    Znaleziono instalacje McAfee do usuniecia:" -ForegroundColor Yellow
    $mcafeeFound | ForEach-Object { Write-Host "    - $($_.Name)" -ForegroundColor Yellow }

    foreach ($app in $mcafeeFound) {
        $uninstall = $app.Uninstall
        Write-Host "    Odinstalowuje: $($app.Name)" -ForegroundColor Magenta
        if ($uninstall -match "^MsiExec") {
            $guid = ($uninstall -replace "MsiExec.exe\s*/[IX]", "").Trim()
            $proc = Start-Process "msiexec.exe" -ArgumentList "/qn /x $guid /norestart" -Wait -PassThru
        } else {
            $proc = Start-Process "cmd.exe" -ArgumentList "/c $uninstall /quiet /norestart" -Wait -PassThru
        }
        Write-OK "Odinstalowano: $($app.Name) (kod: $($proc.ExitCode))"
    }

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

    Write-OK "McAfee usuniety"
}

# ============================================================
#  KROK 2b: USUNIECIE STAREGO OFFICE - oficjalna metoda SaRA
# ============================================================
Write-Step "Odinstalowanie Microsoft Office - metoda oficjalna (SaRA)"

$officeKeys = @(
    "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall",
    "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall"
)

$officeFound = $false
foreach ($regPath in $officeKeys) {
    if (Test-Path $regPath) {
        Get-ChildItem $regPath | ForEach-Object {
            $displayName = ($_ | Get-ItemProperty -Name DisplayName -ErrorAction SilentlyContinue).DisplayName
            if ($displayName -match "Microsoft 365|Microsoft Office|Office 16|Office 15|Office 14") {
                $officeFound = $true
            }
        }
    }
}

$c2rFound = Test-Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"

if (-not $officeFound -and -not $c2rFound) {
    Write-Skip "Nie znaleziono instalacji Office - pomijam"
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
#  KROK 3: INSTALACJA APLIKACJI
# ============================================================

function Install-App {
    param(
        [string]$Name,
        [string]$File,
        [string]$SilentArgs = "",
        [bool]$Silent = $true
    )

    $fullPath = Join-Path $InstallerPath $File

    if (-not (Test-Path $fullPath)) {
        Write-Skip "$Name - plik nie znaleziony: $File"
        return
    }

    Write-Step "Instalacja: $Name"

    if ($Silent -and $SilentArgs -ne "") {
        $proc = Start-Process -FilePath $fullPath -ArgumentList $SilentArgs -Wait -PassThru
        if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
            Write-OK "$Name zainstalowany (kod: $($proc.ExitCode))"
        } else {
            Write-Err "$Name - kod wyjscia: $($proc.ExitCode)"
        }
    } else {
        Write-Host "    -> Otwieranie instalatora $Name (instalacja reczna)..." -ForegroundColor Magenta
        $proc = Start-Process -FilePath $fullPath -Wait -PassThru
        Write-OK "$Name - instalator zamkniety"
    }
}

# AnyDesk - silent
Install-App -Name "AnyDesk" `
            -File "AnyDesk.exe" `
            -SilentArgs "--install `"C:\Program Files (x86)\AnyDesk`" --silent --create-shortcuts --create-desktop-icon --start-with-win" `
            -Silent $true

# ESET Endpoint Security - silent przez msiexec
$esetMsi = Join-Path $InstallerPath "ees_nt64.msi"
if (Test-Path $esetMsi) {
    Write-Step "Instalacja: ESET Endpoint Security"
    $proc = Start-Process -FilePath "msiexec.exe" `
        -ArgumentList "/qn /i `"$esetMsi`" ADDLOCAL=ALL REBOOT_WHEN_NEEDED=0" `
        -Wait -PassThru
    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
        Write-OK "ESET zainstalowany (kod: $($proc.ExitCode))"
    } else {
        Write-Err "ESET - kod wyjscia: $($proc.ExitCode)"
    }
} else {
    Write-Skip "ESET - plik nie znaleziony: ees_nt64.msi"
}

# Google Chrome Enterprise - silent przez msiexec
$chromeMsi = Join-Path $InstallerPath "googlechromestandaloneenterprise64.msi"
if (Test-Path $chromeMsi) {
    Write-Step "Instalacja: Google Chrome Enterprise"
    $proc = Start-Process -FilePath "msiexec.exe" `
        -ArgumentList "/qn /i `"$chromeMsi`" /norestart" `
        -Wait -PassThru
    if ($proc.ExitCode -eq 0 -or $proc.ExitCode -eq 3010) {
        Write-OK "Google Chrome zainstalowany (kod: $($proc.ExitCode))"
    } else {
        Write-Err "Google Chrome - kod wyjscia: $($proc.ExitCode)"
    }
} else {
    Write-Skip "Google Chrome - plik nie znaleziony: googlechromestandaloneenterprise64.msi"
}

# Intel Driver and Support Assistant - silent
Install-App -Name "Intel Driver and Support Assistant" `
            -File "Intel-Driver-and-Support-Assistant-Installer.exe" `
            -SilentArgs "-q -norestart" `
            -Silent $true

# Microsoft Office 32-bit PL - instalacja reczna z ostrzezeniem dla 64-bit
Write-Step "Instalacja: Microsoft Office 32-bit PL"
$officeFile = Join-Path $InstallerPath "OfficeSetup32bitPL.exe"

if (-not (Test-Path $officeFile)) {
    Write-Skip "Office 32-bit - plik nie znaleziony: OfficeSetup32bitPL.exe"
} else {
    $is64bitOS = [Environment]::Is64BitOperatingSystem
    if ($is64bitOS) {
        Write-Host ""
        Write-Host "    UWAGA: Wykryto 64-bitowy system operacyjny." -ForegroundColor Yellow
        Write-Host "    Instalator OfficeSetup32bitPL.exe moze byc zablokowany przez Microsoft." -ForegroundColor Yellow
        Write-Host "    Jesli instalacja sie nie uruchomi - pobierz 64-bitowa wersje Office." -ForegroundColor Yellow
        Write-Host ""
        Write-Host "    Nacisnij ENTER aby mimo wszystko sprobowac uruchomiec instalator 32-bit," -ForegroundColor Cyan
        Write-Host "    lub CTRL+C aby pominac instalacje Office." -ForegroundColor Cyan
        $null = Read-Host
    }
    Write-Host "    -> Otwieranie instalatora Office (instalacja reczna)..." -ForegroundColor Magenta
    $proc = Start-Process -FilePath $officeFile -Wait -PassThru
    Write-OK "Office - instalator zamkniety (kod: $($proc.ExitCode))"
}

# Adobe Acrobat Reader PL - silent (offline installer)
Install-App -Name "Adobe Acrobat Reader PL" `
            -File "AdobeReader_PL.exe" `
            -SilentArgs "/sAll /rs /msi /qn /norestart EULA_ACCEPT=YES" `
            -Silent $true

# UrBackup Client (x86/x64) - silent (instalator EXE, wspiera x86 i x64)
Install-App -Name "UrBackup Client" `
            -File "UrBackup_Client.exe" `
            -SilentArgs "/S" `
            -Silent $true
# ============================================================
#  >> DODAJ KOLEJNE APLIKACJE TUTAJ <<
#
#  Silent .exe:
#  Install-App -Name "Nazwa" -File "plik.exe" -SilentArgs "/S" -Silent $true
#
#  Silent .msi:
#  $msi = Join-Path $InstallerPath "plik.msi"
#  Start-Process "msiexec.exe" -ArgumentList "/qn /i `"$msi`" /norestart" -Wait
#
#  Reczna:
#  Install-App -Name "Nazwa" -File "plik.exe" -Silent $false
# ============================================================

# ============================================================
#  KROK 4: PRZYWROCENIE EXECUTION POLICY
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
Write-Host "============================================" -ForegroundColor Cyan
Write-Host "  GOTOWE! Przygotowanie komputera ukonczone." -ForegroundColor Cyan
Write-Host "============================================" -ForegroundColor Cyan
Write-Host ""
if ($newName -ne "" -and $newName -ne $currentName) {
    Write-Host "  UWAGA: Wymagany restart aby nazwa komputera" -ForegroundColor Yellow
    Write-Host "         '$newName' weszla w zycie!" -ForegroundColor Yellow
    Write-Host ""
}
pause