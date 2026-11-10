# ============================================================
#  PREPARE WORKSTATION - kreator przygotowania komputera firmowego (GUI)
#  Uruchom przez: Start-Firmowy.bat (jako Administrator)
#  Lista aplikacji: apps.json (obok tego pliku)
# ============================================================
[CmdletBinding()]
param(
    [string]$InstallerPath = "C:\instalki",  # folder z instalatorami (lokalny lub UNC)
    [switch]$Resume                           # wznowienie po restarcie (uruchamiane przez zadanie harmonogramu)
)

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

# Pozwala przeciagac pliki z Eksploratora (zwykly uzytkownik) do tego okna (administrator)
try {
    Add-Type -Namespace Win32 -Name Uipi -MemberDefinition '[DllImport("user32.dll")] public static extern bool ChangeWindowMessageFilterEx(IntPtr hWnd, uint msg, uint action, IntPtr changeInfo);'
} catch { }

$AppVersion = "dev"   # podmieniane przez build/Build-Package.ps1

# Katalog programu: dziala zarowno jako .ps1, jak i po zamianie na .exe (ps2exe)
$ScriptDir = if ($PSScriptRoot) { $PSScriptRoot }
             else { Split-Path -Parent ([System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName) }
$AppsFile  = @((Join-Path $ScriptDir "apps.json"), (Join-Path $ScriptDir "files\apps.json")) |
             Where-Object { Test-Path $_ } | Select-Object -First 1
if (-not $AppsFile) { $AppsFile = Join-Path $ScriptDir "apps.json" }
$LogDir    = Join-Path $env:ProgramData "PrepareWorkstation\logs"
$LogFile   = Join-Path $LogDir ("setup-{0:yyyyMMdd-HHmmss}.log" -f (Get-Date))

$script:Results      = New-Object System.Collections.ArrayList
$script:Catalog      = @()
$script:InstalledNow  = @()   # aplikacje zainstalowane w tym uruchomieniu
$script:Todo         = New-Object System.Collections.ArrayList   # lista "do zrobienia recznie"
$script:WuInstalled  = $false
$script:Resuming     = $false
$script:ResumeMode   = $false
$script:UninstallCache = @()
$script:UninSel      = @{}
$script:UninLoaded   = $false
$script:UninFilling  = $false
$script:AutoLoaded   = $false
$script:FileOverrides = @{}   # nazwa pliku (male litery) -> pelna sciezka dodana recznie / z pendrive
$script:Opts         = @{}
$script:DryRun       = $false
$script:Cancel       = $false
$script:Running      = $false
$script:RebootNeeded = $false

function Show-Msg {
    param(
        [string]$Text,
        [string]$Title   = "Prepare Workstation",
        [string]$Buttons = "OK",
        [string]$Icon    = "Information"
    )
    return [System.Windows.Forms.MessageBox]::Show(
        $Text, $Title,
        [System.Windows.Forms.MessageBoxButtons]::$Buttons,
        [System.Windows.Forms.MessageBoxIcon]::$Icon)
}

# --- Uprawnienia administratora ---
$isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin) {
    [void](Show-Msg "Uruchom program jako Administrator (przez Start-Firmowy.bat)." "Brak uprawnień" "OK" "Error")
    exit 1
}

# ============================================================
#  LOGOWANIE I WYNIKI
# ============================================================
function Write-Log {
    param([string]$Message, [string]$Level = "INFO")

    $colors = @{ INFO = 'Gainsboro'; STEP = 'DeepSkyBlue'; OK = 'LightGreen'; SKIP = 'Khaki'; ERR = 'Tomato'; DRY = 'Violet' }
    $prefix = @{ INFO = '    '; STEP = '>>> '; OK = '[OK] '; SKIP = '[--] '; ERR = '[!!] '; DRY = '[DRY] ' }

    $line = "{0:HH:mm:ss} {1}{2}" -f (Get-Date), $prefix[$Level], $Message
    try {
        if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
        Add-Content -Path $LogFile -Value $line -Encoding UTF8
    } catch { }

    if ($script:LogBox) {
        $script:LogBox.SelectionStart  = $script:LogBox.TextLength
        $script:LogBox.SelectionLength = 0
        $script:LogBox.SelectionColor  = [System.Drawing.Color]::FromName($colors[$Level])
        $script:LogBox.AppendText($line + "`n")
        $script:LogBox.ScrollToCaret()
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Outcome {
    param([string]$Step, [string]$Status, [string]$Detail = "")
    [void]$script:Results.Add([pscustomobject]@{ Step = $Step; Status = $Status; Detail = $Detail })
    $msg = if ($Detail) { "$Step - $Detail" } else { $Step }
    Write-Log $msg $Status
}

function Test-Dry {
    param([string]$Step, [string]$Detail)
    if ($script:DryRun) { Set-Outcome $Step "DRY" $Detail; return $true }
    return $false
}

# ============================================================
#  NARZEDZIA
# ============================================================
function Get-InstalledApps {
    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue |
        Where-Object { $_.DisplayName } |
        Select-Object DisplayName, DisplayVersion, UninstallString
}

# Uruchamia proces i czeka na zakonczenie, nie blokujac okna GUI
function Invoke-External {
    param([string]$FilePath, [string]$Arguments = "")

    if ($Arguments) { $p = Start-Process -FilePath $FilePath -ArgumentList $Arguments -PassThru }
    else            { $p = Start-Process -FilePath $FilePath -PassThru }
    $null = $p.Handle   # zapewnia poprawny ExitCode
    while (-not $p.HasExited) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 100
    }
    return $p.ExitCode
}

# Sciezka instalatora: najpierw plik dodany recznie (przeciagniety/z pendrive), potem folder instalatorow
function Resolve-Installer {
    param([string]$File, [string]$Folder)
    $k = $File.ToLower()
    if ($script:FileOverrides.ContainsKey($k) -and (Test-Path $script:FileOverrides[$k])) {
        return $script:FileOverrides[$k]
    }
    return (Join-Path $Folder $File)
}

function Get-AppCatalog {
    if (-not (Test-Path $AppsFile)) {
        [void](Show-Msg "Nie znaleziono apps.json obok programu:`n$AppsFile" "Błąd konfiguracji" "OK" "Error")
        return @()
    }
    try {
        return @(Get-Content $AppsFile -Raw -Encoding UTF8 | ConvertFrom-Json)
    } catch {
        [void](Show-Msg "Nie można wczytać apps.json:`n$($_.Exception.Message)" "Błąd konfiguracji" "OK" "Error")
        return @()
    }
}

# ============================================================
#  KROKI
# ============================================================
function Step-RestorePoint {
    if (Test-Dry "Punkt przywracania" "zostałby utworzony") { return }
    try {
        Enable-ComputerRestore -Drive "$env:SystemDrive\" -ErrorAction SilentlyContinue
        Checkpoint-Computer -Description "Prepare Workstation" -RestorePointType MODIFY_SETTINGS -ErrorAction Stop
        Set-Outcome "Punkt przywracania" "OK" "utworzony"
    } catch {
        Set-Outcome "Punkt przywracania" "SKIP" "nie utworzono ($($_.Exception.Message))"
    }
}

function Step-Rename {
    $n = $script:Opts.NewName
    if (Test-Dry "Nazwa komputera" "zmiana na $n") { return }
    Rename-Computer -NewName $n -Force -ErrorAction Stop
    $script:RebootNeeded = $true
    Set-Outcome "Nazwa komputera" "OK" "$n (wejdzie w życie po restarcie)"
}

function Step-Power {
    $o = $script:Opts
    if (Test-Dry "Zasilanie" "plan/ekran/uśpienie/hibernacja/wygaszacz wg wyboru") { return }

    if ($o.PowerPlan) {
        $hp = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'   # Wysoka wydajnosc
        $list = (powercfg /list) -join "`n"
        if ($list -notmatch $hp) {
            $out = (powercfg /duplicatescheme $hp) -join "`n"
            $m = [regex]::Match($out, '[0-9a-fA-F]{8}(-[0-9a-fA-F]{4}){3}-[0-9a-fA-F]{12}')
            $hp = if ($m.Success) { $m.Value } else { $null }
        }
        if ($hp) {
            powercfg /setactive $hp | Out-Null
            Set-Outcome "Plan zasilania" "OK" "Wysoka wydajność"
        } else {
            Set-Outcome "Plan zasilania" "SKIP" "plan Wysoka wydajność niedostępny na tym sprzęcie"
        }
    }
    if ($o.PowerNever) {
        powercfg /change monitor-timeout-ac 0 | Out-Null
        powercfg /change monitor-timeout-dc 0 | Out-Null
        powercfg /change standby-timeout-ac 0 | Out-Null
        powercfg /change standby-timeout-dc 0 | Out-Null
        Set-Outcome "Ekran i usypianie" "OK" "nigdy (AC i DC)"
    }
    if ($o.Hibernate) {
        powercfg /hibernate off | Out-Null
        Set-Outcome "Hibernacja" "OK" "wyłączona"
    }
    if ($o.ScreenSaver) {
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveActive"  -Value "0" -Force
        Set-ItemProperty -Path "HKCU:\Control Panel\Desktop" -Name "ScreenSaveTimeOut" -Value "0" -Force
        Set-Outcome "Wygaszacz ekranu" "OK" "wyłączony"
    }
}

function Step-McAfee {
    $found = @(Get-InstalledApps | Where-Object { $_.DisplayName -match "McAfee" -and $_.UninstallString })
    if ($found.Count -eq 0) { Set-Outcome "McAfee" "SKIP" "nie znaleziono"; return }
    if (Test-Dry "McAfee" "do usunięcia: $(($found.DisplayName) -join ', ')") { return }

    foreach ($app in $found) {
        Write-Log "Odinstalowuję: $($app.DisplayName)"
        $u = $app.UninstallString
        if ($u -match '(?i)msiexec') {
            $guid = [regex]::Match($u, '\{[0-9A-Fa-f\-]+\}').Value
            if (-not $guid) { Set-Outcome $app.DisplayName "ERR" "nie rozpoznano GUID"; continue }
            $code = Invoke-External "msiexec.exe" "/qn /x $guid /norestart"
        } else {
            $code = Invoke-External "cmd.exe" "/c `"$u /quiet /norestart`""
        }
        Set-Outcome $app.DisplayName "OK" "odinstalowano (kod: $code)"
    }
    foreach ($folder in @("C:\Program Files\McAfee", "C:\Program Files (x86)\McAfee", "C:\ProgramData\McAfee")) {
        if (Test-Path $folder) {
            Remove-Item $folder -Recurse -Force -ErrorAction SilentlyContinue
            Write-Log "Usunięto folder: $folder" "OK"
        }
    }
}

function Step-Office {
    $found = @(Get-InstalledApps | Where-Object { $_.DisplayName -match "Microsoft 365|Microsoft Office|Office 16|Office 15|Office 14" })
    $c2r = Test-Path "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
    if ($found.Count -eq 0 -and -not $c2r) { Set-Outcome "Stary Office" "SKIP" "nie znaleziono"; return }
    if (Test-Dry "Stary Office" "otwarcie narzędzia SaRA") { return }

    Start-Process "https://aka.ms/SaRA-officeUninstallFromPC"
    [void](Show-Msg ("Otwarto oficjalne narzędzie Microsoft (SaRA) do usunięcia Office.`n`n" +
                     "Postępuj zgodnie z instrukcjami na stronie. Gdy Office zostanie odinstalowany, kliknij OK.") `
                    "Usuwanie Office" "OK" "Information")
    Set-Outcome "Stary Office" "OK" "procedura SaRA zakończona (potwierdzona ręcznie)"
}

function Step-App {
    param($App)
    $o    = $script:Opts
    $name = $App.name
    $path = Resolve-Installer $App.file $o.InstallerPath

    if (-not (Test-Path $path)) { Set-Outcome $name "SKIP" "brak pliku: $($App.file)"; return }

    if ($o.SkipInstalled -and $App.detect) {
        $hit = Get-InstalledApps | Where-Object { $_.DisplayName -match $App.detect } | Select-Object -First 1
        if ($hit) { Set-Outcome $name "SKIP" "już zainstalowana ($($hit.DisplayName) $($hit.DisplayVersion))"; return }
    }
    if (Test-Dry $name "instalacja ($($App.type)) z $($App.file)") { return }

    if ($o.Hash -and $App.sha256) {
        Write-Log "Sprawdzam sumę SHA256: $($App.file)..."
        $actual = (Get-FileHash -LiteralPath $path -Algorithm SHA256).Hash
        if ($actual -ne ([string]$App.sha256)) {
            Set-Outcome $name "ERR" "suma SHA256 nie zgadza się (plik zmieniony lub inna wersja) - pominięto instalację"
            return
        }
        Write-Log "Suma SHA256 zgodna" "OK"
    }

    $code = $null
    switch ($App.type) {
        'msi' {
            $argLine = "/qn /i `"$path`" /norestart"
            if ($App.args) { $argLine += " $($App.args)" }
            if ($App.id -eq 'eset' -and $o.EsetKey) { $argLine += " ACTIVATION_DATA=key:$($o.EsetKey)" }
            $code = Invoke-External "msiexec.exe" $argLine
        }
        'exe' {
            $code = Invoke-External $path $App.args
        }
        'manual' {
            if ($App.warn32on64 -and [Environment]::Is64BitOperatingSystem) {
                $r = Show-Msg ("Wykryto 64-bitowy system, a instalator ($($App.file)) jest 32-bitowy.`n" +
                               "Microsoft może zablokować taką instalację.`n`nUruchomić mimo to?") `
                              $name "YesNo" "Warning"
                if ($r -ne 'Yes') { Set-Outcome $name "SKIP" "pominięto na życzenie"; return }
            }
            Write-Log "Otwieram instalator $name (instalacja ręczna) - dokończ ją w otwartym oknie..."
            $code = Invoke-External $path ""
            $script:InstalledNow += $App
            Set-Outcome $name "OK" "instalator zamknięty (kod: $code)"
            return
        }
        default { Set-Outcome $name "ERR" "nieznany typ instalatora: $($App.type)"; return }
    }

    if ($code -eq 0 -or $code -eq 3010 -or $code -eq 1641) {
        if ($code -ne 0) { $script:RebootNeeded = $true }
        $script:InstalledNow += $App
        Set-Outcome $name "OK" "zainstalowano (kod: $code)"
    } else {
        Set-Outcome $name "ERR" "kod wyjścia: $code"
    }
}

function Step-TimeZone {
    $id = $script:Opts.TimeZone
    if (Test-Dry "Strefa czasowa" $id) { return }
    Set-TimeZone -Id $id -ErrorAction Stop
    Start-Service w32time -ErrorAction SilentlyContinue
    w32tm /resync 2>&1 | Out-Null
    Set-Outcome "Strefa czasowa" "OK" "$id (czas zsynchronizowany)"
}

function Step-FileExt {
    if (Test-Dry "Eksplorator" "pokaż rozszerzenia i ukryte pliki") { return }
    $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
    Set-ItemProperty -Path $k -Name "HideFileExt" -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $k -Name "Hidden"      -Value 1 -Type DWord -Force
    Set-Outcome "Eksplorator" "OK" "rozszerzenia i ukryte pliki widoczne (po ponownym zalogowaniu)"
}

function Step-ThisPC {
    if (Test-Dry "Ikona Ten komputer" "dodanie na pulpit") { return }
    $k = "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\HideDesktopIcons\NewStartPanel"
    if (-not (Test-Path $k)) { New-Item -Path $k -Force | Out-Null }
    Set-ItemProperty -Path $k -Name '{20D04FE0-3AEA-1069-A2D8-08002B30309D}' -Value 0 -Type DWord -Force
    Set-Outcome "Ikona Ten komputer" "OK" "dodana na pulpit"
}

function Step-Policy {
    if (Test-Dry "ExecutionPolicy" "przywrócenie do Restricted") { return }
    Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope Process     -Force -ErrorAction SilentlyContinue
    Set-ExecutionPolicy -ExecutionPolicy Undefined -Scope CurrentUser -Force -ErrorAction SilentlyContinue
    try {
        Set-ExecutionPolicy -ExecutionPolicy Restricted -Scope LocalMachine -Force -ErrorAction Stop
        Set-Outcome "ExecutionPolicy" "OK" "LocalMachine: Restricted"
    } catch {
        Set-Outcome "ExecutionPolicy" "SKIP" "zarządzana przez GPO - pominięto"
    }
}

function Step-WindowsUpdate {
    if (Test-Dry "Windows Update" "otwarcie ustawień") { return }
    Start-Process "ms-settings:windowsupdate"
    Set-Outcome "Windows Update" "OK" "otwarto ustawienia aktualizacji"
}

# ============================================================
#  URUCHOMIENIE KREATORA
# ============================================================
# ------------------------------------------------------------
#  Dodatkowe funkcje
# ------------------------------------------------------------
function Step-Ads {
    if (Test-Dry "Reklamy i sugestie" "wyłączenie w Start/ekranie blokady") { return }
    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    if (-not (Test-Path $cdm)) { New-Item -Path $cdm -Force | Out-Null }
    foreach ($n in 'SubscribedContent-338387Enabled', 'SubscribedContent-338388Enabled', 'SubscribedContent-338389Enabled',
                   'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SubscribedContent-338393Enabled',
                   'SubscribedContent-310093Enabled', 'SystemPaneSuggestionsEnabled', 'SoftLandingEnabled',
                   'RotatingLockScreenOverlayEnabled', 'OemPreInstalledAppsEnabled', 'PreInstalledAppsEnabled',
                   'SilentInstalledAppsEnabled', 'ContentDeliveryAllowed') {
        Set-ItemProperty -Path $cdm -Name $n -Value 0 -Type DWord -Force
    }
    $adv = "HKCU:\Software\Microsoft\Windows\CurrentVersion\AdvertisingInfo"
    if (-not (Test-Path $adv)) { New-Item -Path $adv -Force | Out-Null }
    Set-ItemProperty -Path $adv -Name "Enabled" -Value 0 -Type DWord -Force
    Set-Outcome "Reklamy i sugestie" "OK" "wyłączone (Start, ekran blokady, identyfikator reklamowy)"
}

function Step-Language {
    if (Test-Dry "Region i język" "pl-PL, klawiatura polska programisty") { return }
    Set-Culture -CultureInfo pl-PL
    Set-WinHomeLocation -GeoId 191
    Set-WinSystemLocale -SystemLocale pl-PL
    $list = New-WinUserLanguageList -Language "pl-PL"
    $list[0].InputMethodTips.Clear()
    $list[0].InputMethodTips.Add("0415:00000415")
    Set-WinUserLanguageList -LanguageList $list -Force
    $script:RebootNeeded = $true
    Set-Outcome "Region i język" "OK" "pl-PL, klawiatura polska programisty (pełny efekt po restarcie)"
}

function Step-Shortcuts {
    if (Test-Dry "Skróty na pulpicie" "Chrome, Word, Excel, Outlook, Adobe Reader") { return }
    $pf  = $env:ProgramFiles
    $pf86 = ${env:ProgramFiles(x86)}
    $targets = @(
        @{ Name = "Google Chrome";  Paths = @("$pf\Google\Chrome\Application\chrome.exe", "$pf86\Google\Chrome\Application\chrome.exe") },
        @{ Name = "Word";           Paths = @("$pf\Microsoft Office\root\Office16\WINWORD.EXE", "$pf86\Microsoft Office\root\Office16\WINWORD.EXE") },
        @{ Name = "Excel";          Paths = @("$pf\Microsoft Office\root\Office16\EXCEL.EXE", "$pf86\Microsoft Office\root\Office16\EXCEL.EXE") },
        @{ Name = "Outlook";        Paths = @("$pf\Microsoft Office\root\Office16\OUTLOOK.EXE", "$pf86\Microsoft Office\root\Office16\OUTLOOK.EXE") },
        @{ Name = "Adobe Acrobat Reader"; Paths = @("$pf\Adobe\Acrobat DC\Acrobat\Acrobat.exe", "$pf86\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe", "$pf\Adobe\Acrobat Reader DC\Reader\AcroRd32.exe") }
    )
    $desktop = Join-Path $env:Public "Desktop"
    $shell = New-Object -ComObject WScript.Shell
    $made = @()
    foreach ($t in $targets) {
        $exe = $t.Paths | Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
        if (-not $exe) { continue }
        $lnk = $shell.CreateShortcut((Join-Path $desktop "$($t.Name).lnk"))
        $lnk.TargetPath = $exe
        $lnk.WorkingDirectory = Split-Path $exe -Parent
        $lnk.Save()
        $made += $t.Name
    }
    if ($made.Count -gt 0) { Set-Outcome "Skróty na pulpicie" "OK" ($made -join ", ") }
    else { Set-Outcome "Skróty na pulpicie" "SKIP" "nie znaleziono zainstalowanych programów" }
}

function Step-ChromePolicy {
    $url = $script:Opts.ChromeUrl
    if (Test-Dry "Chrome - strona startowa" $url) { return }
    $k = "HKLM:\SOFTWARE\Policies\Google\Chrome"
    New-Item -Path $k -Force | Out-Null
    Set-ItemProperty -Path $k -Name "HomepageLocation"        -Value $url -Type String -Force
    Set-ItemProperty -Path $k -Name "HomepageIsNewTabPage"    -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $k -Name "ShowHomeButton"          -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $k -Name "RestoreOnStartup"        -Value 4 -Type DWord -Force
    Set-ItemProperty -Path $k -Name "PromotionalTabsEnabled"  -Value 0 -Type DWord -Force
    Set-ItemProperty -Path $k -Name "MetricsReportingEnabled" -Value 0 -Type DWord -Force
    New-Item -Path "$k\RestoreOnStartupURLs" -Force | Out-Null
    Set-ItemProperty -Path "$k\RestoreOnStartupURLs" -Name "1" -Value $url -Type String -Force
    Set-Outcome "Chrome - strona startowa" "OK" "$url (Chrome pokaże «zarządzane przez organizację»)"
}

# Pobiera i instaluje aktualizacje przez wbudowane API Windows Update (bez dodatkowych modułow).
# Praca w osobnym watku, zeby okno nie zawieszalo sie na czas wyszukiwania i instalacji.
function Step-WindowsUpdateInstall {
    if (Test-Dry "Aktualizacje Windows" "wyszukanie i instalacja") { return }
    Write-Log "Szukam i instaluję aktualizacje Windows - to może potrwać kilka do kilkunastu minut (nie można przerwać w trakcie)..."

    $sb = {
        $out = @{ Found = 0; Installed = 0; Failed = 0; Titles = @(); Reboot = $false; Error = $null }
        try {
            $session  = New-Object -ComObject Microsoft.Update.Session
            $searcher = $session.CreateUpdateSearcher()
            $found    = $searcher.Search("IsInstalled=0 and Type='Software' and IsHidden=0")
            $coll     = New-Object -ComObject Microsoft.Update.UpdateColl
            foreach ($u in $found.Updates) {
                if ($u.InstallationBehavior.CanRequestUserInput) { continue }
                if (-not $u.EulaAccepted) { $u.AcceptEula() }
                [void]$coll.Add($u)
                $out.Titles += $u.Title
            }
            $out.Found = $coll.Count
            if ($coll.Count -gt 0) {
                $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; [void]$dl.Download()
                $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll
                $r = $inst.Install()
                $out.Reboot = [bool]$r.RebootRequired
                for ($i = 0; $i -lt $coll.Count; $i++) {
                    if ($r.GetUpdateResult($i).ResultCode -eq 2) { $out.Installed++ } else { $out.Failed++ }
                }
            }
        } catch { $out.Error = $_.Exception.Message }
        $out
    }

    $ps = [powershell]::Create()
    [void]$ps.AddScript($sb)
    $async = $ps.BeginInvoke()
    $t0 = Get-Date
    while (-not $async.IsCompleted) {
        [System.Windows.Forms.Application]::DoEvents()
        Start-Sleep -Milliseconds 200
        $lblStatus.Text = ("Aktualizacje Windows: trwa... ({0:mm\:ss})" -f ((Get-Date) - $t0))
    }
    $res = $ps.EndInvoke($async)
    $ps.Dispose()
    $r = if ($res.Count -gt 0) { $res[$res.Count - 1].BaseObject } else { $null }

    if (-not $r)       { Set-Outcome "Aktualizacje Windows" "ERR" "brak wyniku z Windows Update"; return }
    if ($r.Error)      { Set-Outcome "Aktualizacje Windows" "ERR" $r.Error; return }
    foreach ($t in $r.Titles) { Write-Log $t "INFO" }
    if ($r.Found -eq 0) { Set-Outcome "Aktualizacje Windows" "OK" "brak nowych aktualizacji"; return }
    if ($r.Reboot) { $script:RebootNeeded = $true }
    if ($r.Installed -gt 0) { $script:WuInstalled = $true }
    if ($r.Failed -gt 0) { Set-Outcome "Aktualizacje Windows" "ERR" "zainstalowano $($r.Installed) z $($r.Found), błędy: $($r.Failed)" }
    else                 { Set-Outcome "Aktualizacje Windows" "OK" "zainstalowano $($r.Installed) z $($r.Found)" }
}

function Step-CleanTemp {
    if (Test-Dry "Sprzątanie" "pliki tymczasowe i koszyk") { return }
    foreach ($d in @($env:TEMP, "$env:WINDIR\Temp")) {
        foreach ($i in @(Get-ChildItem -LiteralPath $d -Force -ErrorAction SilentlyContinue)) {
            try { Remove-Item -LiteralPath $i.FullName -Recurse -Force -ErrorAction Stop } catch { }
        }
        [System.Windows.Forms.Application]::DoEvents()
    }
    try { Clear-RecycleBin -Force -ErrorAction Stop } catch { }
    Set-Outcome "Sprzątanie" "OK" "wyczyszczono pliki tymczasowe i koszyk"
}

# Usuwa tylko te instalatory, ktore zostaly zainstalowane w tym uruchomieniu - i tylko z lokalnego dysku
function Step-CleanInstallers {
    $folder = $script:Opts.InstallerPath
    if (Test-Dry "Sprzątanie instalatorów" "usunięcie zainstalowanych plików z $folder") { return }
    if ($folder -like '\\*') { Set-Outcome "Sprzątanie instalatorów" "SKIP" "udział sieciowy - nie usuwam"; return }
    try {
        $di = New-Object System.IO.DriveInfo([System.IO.Path]::GetPathRoot($folder))
        if ($di.DriveType -ne 'Fixed') { Set-Outcome "Sprzątanie instalatorów" "SKIP" "to nie dysk lokalny - nie usuwam"; return }
    } catch { Set-Outcome "Sprzątanie instalatorów" "SKIP" "nie można ustalić typu dysku"; return }

    $n = 0
    foreach ($a in @($script:InstalledNow)) {
        $p = Join-Path $folder $a.file
        if (Test-Path -LiteralPath $p) {
            try { Remove-Item -LiteralPath $p -Force -ErrorAction Stop; $n++ } catch { Write-Log "Nie można usunąć: $p" "SKIP" }
        }
    }
    Set-Outcome "Sprzątanie instalatorów" "OK" "usunięto plików: $n"
}

# Sprawdza w rejestrze, czy zainstalowane programy faktycznie sie pojawily
function Step-Verify {
    if (Test-Dry "Weryfikacja instalacji" "sprawdzenie w rejestrze") { return }
    $apps = @($script:InstalledNow)
    if ($apps.Count -eq 0) { Set-Outcome "Weryfikacja instalacji" "SKIP" "nic nie zainstalowano w tym uruchomieniu"; return }
    $inst = @(Get-InstalledApps)
    foreach ($a in $apps) {
        if (-not $a.detect) { continue }
        $hit = $inst | Where-Object { $_.DisplayName -match $a.detect } | Select-Object -First 1
        if ($hit)                     { Set-Outcome "Weryfikacja: $($a.name)" "OK" "wykryta: $($hit.DisplayName) $($hit.DisplayVersion)" }
        elseif ($a.type -eq 'manual') { Set-Outcome "Weryfikacja: $($a.name)" "SKIP" "nie wykryto - dokończ instalację ręcznie" }
        else                          { Set-Outcome "Weryfikacja: $($a.name)" "ERR" "instalator zakończył pracę, ale programu nie ma w rejestrze" }
    }

    # usługi (pole "service" w apps.json) - czekamy do 20 s, aż wystartują
    foreach ($a in $apps) {
        if (-not $a.service) { continue }
        $svc = $null
        $t0 = Get-Date
        do {
            $svc = Get-Service -Name $a.service -ErrorAction SilentlyContinue
            if ($svc -and $svc.Status -eq 'Running') { break }
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 500
        } while (((Get-Date) - $t0).TotalSeconds -lt 20)

        if (-not $svc)                         { Set-Outcome "Usługa: $($a.name)" "ERR" "nie znaleziono usługi $($a.service)" }
        elseif ($svc.Status -eq 'Running')     { Set-Outcome "Usługa: $($a.name)" "OK" "$($a.service) działa" }
        else                                   { Set-Outcome "Usługa: $($a.name)" "ERR" "usługa $($a.service) nie działa (stan: $($svc.Status))" }
    }
}

# Kopiuje log na pendrive (najpierw ten, z ktorego pochodza instalatory)
function Copy-LogToUsb {
    $roots = @([System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady } |
        ForEach-Object { $_.RootDirectory.FullName })
    if ($roots.Count -eq 0) { Write-Log "Kopia logu: nie wykryto pendrive'a" "SKIP"; return }

    $target = $roots[0]
    foreach ($p in $script:FileOverrides.Values) {
        $r = [System.IO.Path]::GetPathRoot($p)
        if ($roots -contains $r) { $target = $r; break }
    }
    try {
        $dir = Join-Path $target "PrepareWorkstation-logs"
        New-Item -ItemType Directory -Path $dir -Force | Out-Null
        $pc = if ($script:Opts.NewName) { $script:Opts.NewName } else { $env:COMPUTERNAME }
        $dest = Join-Path $dir ("{0}-{1:yyyyMMdd-HHmmss}.log" -f $pc, (Get-Date))
        Copy-Item -LiteralPath $LogFile -Destination $dest -Force
        Write-Log "Log skopiowano na pendrive: $dest" "OK"
    } catch {
        Write-Log "Kopia logu nie powiodła się: $($_.Exception.Message)" "ERR"
    }
}

# Zapisuje sumy SHA256 obecnych instalatorow do apps.json
function Save-Hashes {
    $folder = $txtPath.Text.Trim()
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    $n = 0
    try {
        foreach ($a in $script:Catalog) {
            $p = Resolve-Installer $a.file $folder
            if (Test-Path -LiteralPath $p) {
                $h = (Get-FileHash -LiteralPath $p -Algorithm SHA256).Hash.ToLower()
                Add-Member -InputObject $a -NotePropertyName sha256 -NotePropertyValue $h -Force
                $n++
            }
        }
    } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }

    if ($n -eq 0) {
        [void](Show-Msg "Nie znaleziono żadnych plików instalatorów do policzenia sum." "Sumy SHA256" "OK" "Information")
        return
    }
    $r = Show-Msg ("Policzono sumy SHA256 dla $n instalatorów.`n`nZapisać je do apps.json? Od tej pory (przy włączonej opcji sprawdzania) " +
                   "program odmówi instalacji pliku o innej sumie - np. nowszej wersji. Wtedy trzeba ponownie kliknąć ten przycisk.") `
                  "Sumy SHA256" "YesNo" "Question"
    if ($r -ne 'Yes') { return }
    try {
        $json = ConvertTo-Json -InputObject @($script:Catalog) -Depth 5
        [System.IO.File]::WriteAllText($AppsFile, $json, (New-Object System.Text.UTF8Encoding($true)))
        Write-Log "Zapisano sumy SHA256 ($n) do $AppsFile" "OK"
        Update-AppList $false $true
    } catch {
        [void](Show-Msg "Nie udało się zapisać apps.json:`n$($_.Exception.Message)" "Sumy SHA256" "OK" "Error")
    }
}

# ------------------------------------------------------------
#  Narzedzia pomocnicze (siec, adres IP, ID AnyDesk)
# ------------------------------------------------------------
function Add-Todo {
    param([string]$Text)
    if (-not $script:Todo.Contains($Text)) { [void]$script:Todo.Add($Text) }
}

function Test-TcpPort {
    param([string]$HostName, [int]$Port, [int]$TimeoutMs = 2500)
    $c = New-Object System.Net.Sockets.TcpClient
    try {
        $iar = $c.BeginConnect($HostName, $Port, $null, $null)
        $t0 = Get-Date
        while (-not $iar.IsCompleted -and ((Get-Date) - $t0).TotalMilliseconds -lt $TimeoutMs) {
            [System.Windows.Forms.Application]::DoEvents()
            Start-Sleep -Milliseconds 50
        }
        if (-not $iar.IsCompleted) { return $false }
        $c.EndConnect($iar)
        return $c.Connected
    } catch { return $false } finally { $c.Close() }
}

function Get-LocalIPv4 {
    try {
        return @(Get-NetIPAddress -AddressFamily IPv4 -ErrorAction Stop |
            Where-Object { $_.IPAddress -notmatch '^(127\.|169\.254\.)' -and $_.PrefixOrigin -ne 'WellKnown' } |
            ForEach-Object { $_.IPAddress })
    } catch { return @() }
}

function Get-AnyDeskId {
    $exe = @("${env:ProgramFiles(x86)}\AnyDesk\AnyDesk.exe", "$env:ProgramFiles\AnyDesk\AnyDesk.exe") |
           Where-Object { Test-Path -LiteralPath $_ } | Select-Object -First 1
    if (-not $exe) { return $null }
    for ($try = 0; $try -lt 3; $try++) {
        $tmp = Join-Path $env:TEMP ("anydesk-id-{0}.txt" -f [guid]::NewGuid())
        try {
            $p = Start-Process -FilePath $exe -ArgumentList "--get-id" -RedirectStandardOutput $tmp -WindowStyle Hidden -PassThru
            $t0 = Get-Date
            while (-not $p.HasExited -and ((Get-Date) - $t0).TotalSeconds -lt 10) {
                [System.Windows.Forms.Application]::DoEvents()
                Start-Sleep -Milliseconds 100
            }
            if (-not $p.HasExited) { try { $p.Kill() } catch { } }
            $txt = if (Test-Path -LiteralPath $tmp) { Get-Content -LiteralPath $tmp -Raw -ErrorAction SilentlyContinue } else { "" }
            if ($txt -and ($txt.Trim() -match '^\d{6,12}$')) { return $txt.Trim() }
        } catch { } finally { Remove-Item -LiteralPath $tmp -Force -ErrorAction SilentlyContinue }
        $t1 = Get-Date
        while (((Get-Date) - $t1).TotalSeconds -lt 2) { [System.Windows.Forms.Application]::DoEvents(); Start-Sleep -Milliseconds 100 }
    }
    return $null
}

# ------------------------------------------------------------
#  Bez pytan o opinie i podpowiedzi
# ------------------------------------------------------------
function Step-NoFeedback {
    if (Test-Dry "Opinie i podpowiedzi" "wyłączenie pytań o opinię, Spotlight, «dokończ konfigurację»") { return }

    $siuf = "HKCU:\Software\Microsoft\Siuf\Rules"
    if (-not (Test-Path $siuf)) { New-Item -Path $siuf -Force | Out-Null }
    Set-ItemProperty -Path $siuf -Name "NumberOfSIUFInPeriod" -Value 0 -Type DWord -Force
    Remove-ItemProperty -Path $siuf -Name "PeriodInNanoSeconds" -ErrorAction SilentlyContinue

    $upe = "HKCU:\Software\Microsoft\Windows\CurrentVersion\UserProfileEngagement"
    if (-not (Test-Path $upe)) { New-Item -Path $upe -Force | Out-Null }
    Set-ItemProperty -Path $upe -Name "ScoobeSystemSettingEnabled" -Value 0 -Type DWord -Force

    $cdm = "HKCU:\Software\Microsoft\Windows\CurrentVersion\ContentDeliveryManager"
    if (-not (Test-Path $cdm)) { New-Item -Path $cdm -Force | Out-Null }
    foreach ($n in 'SubscribedContent-310093Enabled', 'SubscribedContent-338389Enabled', 'SubscribedContent-338393Enabled',
                   'SubscribedContent-353694Enabled', 'SubscribedContent-353696Enabled', 'SoftLandingEnabled') {
        Set-ItemProperty -Path $cdm -Name $n -Value 0 -Type DWord -Force
    }

    $cc = "HKCU:\SOFTWARE\Policies\Microsoft\Windows\CloudContent"
    if (-not (Test-Path $cc)) { New-Item -Path $cc -Force | Out-Null }
    Set-ItemProperty -Path $cc -Name "DisableWindowsSpotlightFeatures" -Value 1 -Type DWord -Force
    Set-ItemProperty -Path $cc -Name "DisableThirdPartySuggestions"    -Value 1 -Type DWord -Force

    Set-Outcome "Opinie i podpowiedzi" "OK" "wyłączone (częstotliwość opinii, Spotlight, porady, «dokończ konfigurację urządzenia»)"
}

# ------------------------------------------------------------
#  Odinstalowanie programow (lista jak w Ustawienia -> Aplikacje)
# ------------------------------------------------------------
$script:UninstallProtected = '^(Microsoft\.(WindowsStore|StorePurchaseApp|DesktopAppInstaller|SecHealthUI|Windows\.|MicrosoftEdge|AAD\.|AccountsControl|LockApp|CredDialogHost|BioEnrollment|ECApp|AsyncTextService|UI\.Xaml|VCLibs|NET\.|WindowsAppRuntime|Services\.Store|WebpImageExtension|HEIFImageExtension|VP9VideoExtensions)|MicrosoftWindows\.|Windows\.|NcsiUwpApp)'
$script:JunkStore = @(
    'Microsoft.BingNews', 'Microsoft.BingWeather', 'Microsoft.GetHelp', 'Microsoft.Getstarted',
    'Microsoft.MicrosoftSolitaireCollection', 'Microsoft.MicrosoftOfficeHub', 'Microsoft.WindowsFeedbackHub',
    'Microsoft.ZuneMusic', 'Microsoft.ZuneVideo', 'Microsoft.People', 'Microsoft.SkypeApp',
    'Microsoft.XboxApp', 'Microsoft.XboxGamingOverlay', 'Microsoft.Xbox.TV.App', 'Microsoft.MixedReality.Portal',
    'Microsoft.3DBuilder', 'Microsoft.Microsoft3DViewer', 'Microsoft.Print3D', 'Microsoft.WindowsMaps',
    'Clipchamp.Clipchamp', 'MicrosoftTeams', '*CandyCrush*', 'SpotifyAB.SpotifyMusic', 'Disney.*', 'king.com.*'
)
$script:JunkProgram = 'McAfee|Norton|WildTangent|Dell (SupportAssist|Digital Delivery|Optimizer|Customer Connect|Update)|HP (Wolf|Documentation|Smart|Support Assistant|Client Security)|Lenovo (Vantage|Welcome|Companion)|Booking\.com|Candy'

function Get-UninstallList {
    param([bool]$IncludeComponents = $false)
    $list = New-Object System.Collections.ArrayList

    $paths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )
    $seen = @{}
    foreach ($e in @(Get-ItemProperty -Path $paths -ErrorAction SilentlyContinue)) {
        $name = [string]$e.DisplayName
        if (-not $name) { continue }
        $cmd   = [string]$e.UninstallString
        $quiet = [string]$e.QuietUninstallString
        if (-not $cmd -and -not $quiet) { continue }
        if ($e.NoRemove -eq 1) { continue }

        $isComp = ($e.SystemComponent -eq 1) -or [bool]$e.ParentKeyName -or
                  ($name -match '^(KB\d+|Update for |Security Update|Hotfix)') -or
                  ($name -match 'Visual C\+\+ \d|\.NET (Runtime|Core|Desktop|SDK)|Windows Desktop Runtime|Microsoft Edge|WebView2|Windows Driver Package')
        if ($isComp -and -not $IncludeComponents) { continue }

        $key = "$name|$($e.DisplayVersion)"
        if ($seen.ContainsKey($key)) { continue }
        $seen[$key] = $true

        $guid = ""
        if ($cmd -match '(?i)msiexec') { $guid = [regex]::Match($cmd, '\{[0-9A-Fa-f\-]+\}').Value }
        $mode = if ($guid) { "cicha (MSI)" } elseif ($quiet) { "cicha" } else { "widoczna" }
        $size = if ($e.EstimatedSize) { "{0:N0} MB" -f ($e.EstimatedSize / 1024) } else { "" }

        [void]$list.Add([pscustomobject]@{
            Kind = 'Program'; Name = $name; Version = [string]$e.DisplayVersion; Publisher = [string]$e.Publisher
            Size = $size; Mode = $mode; Cmd = $cmd; Quiet = $quiet; Guid = $guid; Package = ""; IsComponent = $isComp
        })
    }

    try {
        foreach ($p in @(Get-AppxPackage -AllUsers -ErrorAction Stop |
                         Where-Object { -not $_.IsFramework -and -not $_.IsResourcePackage } |
                         Sort-Object Name -Unique)) {
            $prot = ($p.Name -match $script:UninstallProtected) -or ($p.NonRemovable -eq $true) -or ($p.SignatureKind -eq 'System')
            if ($prot -and -not $IncludeComponents) { continue }
            [void]$list.Add([pscustomobject]@{
                Kind = 'Store'; Name = $p.Name; Version = [string]$p.Version; Publisher = [string]$p.PublisherId
                Size = ""; Mode = "cicha"; Cmd = ""; Quiet = ""; Guid = ""; Package = $p.PackageFullName; IsComponent = $prot
            })
        }
    } catch { Write-Log "Nie można odczytać aplikacji Sklepu: $($_.Exception.Message)" "SKIP" }

    return @($list | Sort-Object Name)
}

function Step-Uninstall {
    param($Items)
    $items = @($Items)
    if (Test-Dry "Odinstalowanie programów" "($($items.Count)): $(($items | ForEach-Object { $_.Name }) -join ', ')") { return }

    foreach ($it in $items) {
        if ($script:Cancel) { Set-Outcome "Odinstalowanie programów" "SKIP" "przerwano - pominięto pozostałe"; break }
        Write-Log "Odinstalowuję: $($it.Name)"
        try {
            if ($it.Kind -eq 'Store') {
                Remove-AppxPackage -Package $it.Package -AllUsers -ErrorAction Stop
                if ($script:Opts.UninProvisioned) {
                    foreach ($pp in @(Get-AppxProvisionedPackage -Online -ErrorAction SilentlyContinue | Where-Object { $_.DisplayName -eq $it.Name })) {
                        try { Remove-AppxProvisionedPackage -Online -PackageName $pp.PackageName -ErrorAction Stop | Out-Null } catch { }
                    }
                }
                Set-Outcome "Odinstalowano: $($it.Name)" "OK" "aplikacja Sklepu"
                continue
            }

            if ($it.Guid) {
                $code = Invoke-External "msiexec.exe" "/x $($it.Guid) /qn /norestart"
            } elseif ($it.Quiet) {
                $code = Invoke-External "cmd.exe" "/c `"$($it.Quiet)`""
            } else {
                Write-Log "Brak trybu cichego - uruchamiam deinstalator widocznie, dokończ go w otwartym oknie..."
                $code = Invoke-External "cmd.exe" "/c `"$($it.Cmd)`""
            }

            if ($code -eq 3010 -or $code -eq 1641) { $script:RebootNeeded = $true }
            if ($code -eq 1605) { Set-Outcome "Odinstalowano: $($it.Name)" "SKIP" "już nieobecny"; continue }

            $still = Get-InstalledApps | Where-Object { $_.DisplayName -eq $it.Name } | Select-Object -First 1
            if ($code -ne 0 -and $code -ne 3010 -and $code -ne 1641) {
                Set-Outcome "Odinstalowano: $($it.Name)" "ERR" "kod wyjścia: $code"
            } elseif ($still -and $it.Mode -eq 'widoczna') {
                Set-Outcome "Odinstalowano: $($it.Name)" "SKIP" "wpis nadal widoczny - czy deinstalacja została dokończona?"
            } else {
                Set-Outcome "Odinstalowano: $($it.Name)" "OK" "kod: $code"
            }
        } catch {
            Set-Outcome "Odinstalowano: $($it.Name)" "ERR" $_.Exception.Message
        }
    }
}

# ------------------------------------------------------------
#  Autostart (jak w Menedzerze zadan: StartupApproved)
# ------------------------------------------------------------
function Get-AutostartDisabled {
    param([string]$Approved, [string]$Name)
    try {
        $v = (Get-ItemProperty -Path $Approved -Name $Name -ErrorAction Stop).$Name
        if ($v -is [byte[]] -and $v.Length -gt 0) { return (($v[0] -band 1) -eq 1) }
    } catch { }
    return $false
}

function Set-AutostartDisabled {
    param([string]$Approved, [string]$Name, [bool]$Disabled)
    if (-not (Test-Path $Approved)) { New-Item -Path $Approved -Force | Out-Null }
    $b = New-Object byte[] 12
    $b[0] = $(if ($Disabled) { 3 } else { 2 })
    Set-ItemProperty -Path $Approved -Name $Name -Value $b -Type Binary -Force
}

function Get-AutostartList {
    $list = New-Object System.Collections.ArrayList
    $apr = "Microsoft\Windows\CurrentVersion\Explorer\StartupApproved"
    $runKeys = @(
        @{ Path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKLM:\SOFTWARE\$apr\Run";   Source = 'HKLM Run' },
        @{ Path = 'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'; Approved = "HKLM:\SOFTWARE\$apr\Run32"; Source = 'HKLM Run (32-bit)' },
        @{ Path = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run';             Approved = "HKCU:\SOFTWARE\$apr\Run";   Source = 'HKCU Run' }
    )
    $skip = 'PSPath', 'PSParentPath', 'PSChildName', 'PSDrive', 'PSProvider'
    foreach ($k in $runKeys) {
        if (-not (Test-Path $k.Path)) { continue }
        $props = Get-ItemProperty -Path $k.Path
        foreach ($p in $props.PSObject.Properties) {
            if ($skip -contains $p.Name) { continue }
            [void]$list.Add([pscustomobject]@{
                Name = $p.Name; Command = [string]$p.Value; Source = $k.Source; Approved = $k.Approved
                Disabled = (Get-AutostartDisabled $k.Approved $p.Name)
            })
        }
    }
    $folders = @(
        @{ Path = "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp"; Approved = "HKLM:\SOFTWARE\$apr\StartupFolder"; Source = 'Autostart (wszyscy)' },
        @{ Path = "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup";     Approved = "HKCU:\SOFTWARE\$apr\StartupFolder"; Source = 'Autostart (użytkownik)' }
    )
    foreach ($f in $folders) {
        foreach ($i in @(Get-ChildItem -LiteralPath $f.Path -File -ErrorAction SilentlyContinue | Where-Object { $_.Name -ne 'desktop.ini' })) {
            [void]$list.Add([pscustomobject]@{
                Name = $i.Name; Command = $i.FullName; Source = $f.Source; Approved = $f.Approved
                Disabled = (Get-AutostartDisabled $f.Approved $i.Name)
            })
        }
    }
    return @($list | Sort-Object Name)
}

function Step-Autostart {
    param($Changes)
    $changes = @($Changes)
    if (Test-Dry "Autostart" "zmian: $($changes.Count)") { return }
    $off = 0; $on = 0
    foreach ($c in $changes) {
        try {
            Set-AutostartDisabled $c.Approved $c.Name ([bool]$c.Disable)
            if ($c.Disable) { $off++; Write-Log "Wyłączono autostart: $($c.Name)" "INFO" } else { $on++; Write-Log "Przywrócono autostart: $($c.Name)" "INFO" }
        } catch { Set-Outcome "Autostart: $($c.Name)" "ERR" $_.Exception.Message }
    }
    Set-Outcome "Autostart" "OK" "wyłączono: $off, przywrócono: $on (zmiana widoczna po ponownym zalogowaniu)"
}

# ------------------------------------------------------------
#  UrBackup - adres serwera
# ------------------------------------------------------------
function Step-UrBackupServer {
    $srv = $script:Opts.UrServer
    if (Test-Dry "UrBackup - serwer" $srv) { return }
    $pc  = if ($script:Opts.NewName) { $script:Opts.NewName } else { $env:COMPUTERNAME }
    $ips = (Get-LocalIPv4) -join ", "

    if (Test-TcpPort $srv 55414) { Set-Outcome "UrBackup - serwer" "OK" "serwer $srv odpowiada (panel www, port 55414)" }
    else { Set-Outcome "UrBackup - serwer" "SKIP" "serwer $srv nie odpowiada na porcie 55414 - sprawdź adres i zaporę" }

    Add-Todo "UrBackup: w panelu serwera ($srv, port 55414) dodaj klienta «$pc» (IP: $ips) i upewnij się, że jest widoczny jako online"
}

# ------------------------------------------------------------
#  Znacznik "komputer przygotowany"
# ------------------------------------------------------------
function Get-PreparedMarker {
    try {
        $k = "HKLM:\SOFTWARE\PrepareWorkstation"
        if (Test-Path $k) { $p = Get-ItemProperty $k; if ($p.LastRun) { return $p } }
    } catch { }
    return $null
}

function Set-PreparedMarker {
    try {
        $k = "HKLM:\SOFTWARE\PrepareWorkstation"
        New-Item -Path $k -Force | Out-Null
        $steps = (@($script:Results | Where-Object { $_.Status -eq 'OK' } | ForEach-Object { $_.Step }) -join "; ")
        if ($steps.Length -gt 1800) { $steps = $steps.Substring(0, 1800) + "..." }
        Set-ItemProperty -Path $k -Name "Version" -Value $AppVersion -Force
        Set-ItemProperty -Path $k -Name "LastRun" -Value (Get-Date -Format "yyyy-MM-dd HH:mm") -Force
        Set-ItemProperty -Path $k -Name "Steps"   -Value $steps -Force
    } catch { Write-Log "Nie udało się zapisać znacznika przygotowania: $($_.Exception.Message)" "SKIP" }
}

# ------------------------------------------------------------
#  Lista "do zrobienia recznie"
# ------------------------------------------------------------
function Build-Todo {
    $pc  = if ($script:Opts.NewName -and -not $script:ResumeMode) { $script:Opts.NewName } else { $env:COMPUTERNAME }
    $ids = @($script:InstalledNow | ForEach-Object { [string]$_.id })

    Add-Todo "Dołącz komputer do domeny, uruchom ponownie i zaloguj się kontem domenowym"
    if ($script:Opts.NewName -and -not $script:ResumeMode) { Add-Todo "Nazwa komputera «$($script:Opts.NewName)» wejdzie w życie po restarcie" }

    if ($ids -contains 'office') { Add-Todo "Office: zaloguj się kontem Microsoft 365 lub aktywuj licencję (Plik -> Konto)" }
    if (($ids -contains 'eset') -and -not $script:Opts.EsetKey) { Add-Todo "ESET: zainstalowany bez klucza - aktywuj licencję (okno programu lub konsola ESET)" }
    if ($ids -contains 'anydesk') {
        $id = Get-AnyDeskId
        if ($id) { Add-Todo "AnyDesk: ID tego komputera ($pc) = $id - zapisz w ewidencji" }
        else     { Add-Todo "AnyDesk: nie udało się odczytać ID automatycznie - odczytaj w oknie AnyDesk i zapisz w ewidencji" }
    }
    if (($ids -contains 'urbackup') -and -not $script:Opts.UrServer) {
        Add-Todo "UrBackup: zainstalowany - upewnij się, że serwer widzi klienta «$pc» (lub dodaj go ręcznie w panelu serwera)"
    }
    foreach ($r in $script:Results) {
        if ($r.Status -eq 'ERR') { Add-Todo "Sprawdź / napraw: $($r.Step) - $($r.Detail)" }
        elseif ($r.Status -eq 'SKIP' -and $r.Detail -like 'brak pliku*') { Add-Todo "Zainstaluj ręcznie: $($r.Step) ($($r.Detail))" }
    }
    if ($script:WuInstalled) { Add-Todo "Po restarcie uruchom Windows Update ponownie - mogą być kolejne aktualizacje" }
    if ($script:RebootNeeded) { Add-Todo "Zrestartuj komputer" }
}

function Write-TodoFile {
    Build-Todo
    $pc = if ($script:Opts.NewName -and -not $script:ResumeMode) { $script:Opts.NewName } else { $env:COMPUTERNAME }
    $lines = @(
        "LISTA DO ZROBIENIA RĘCZNIE",
        "==========================",
        "Komputer: $pc",
        "Data:     $(Get-Date -Format 'yyyy-MM-dd HH:mm')",
        "IP:       $((Get-LocalIPv4) -join ', ')",
        "Program:  Prepare Workstation $AppVersion",
        ""
    )
    Write-Log "" "INFO"
    Write-Log "============ DO ZROBIENIA RĘCZNIE ============" "STEP"
    $i = 0
    foreach ($t in $script:Todo) {
        $i++
        $lines += ("[ ] {0}. {1}" -f $i, $t)
        Write-Log ("[ ] {0}. {1}" -f $i, $t) "INFO"
    }

    $fileName = "DO-ZROBIENIA-{0}-{1:yyyyMMdd-HHmm}.txt" -f $pc, (Get-Date)
    foreach ($d in @($script:Opts.InstallerPath, $LogDir)) {
        if (-not $d -or -not (Test-Path -LiteralPath $d)) { continue }
        try {
            $path = Join-Path $d $fileName
            [System.IO.File]::WriteAllText($path, ($lines -join "`r`n"), (New-Object System.Text.UTF8Encoding($true)))
            Write-Log "Lista do zrobienia zapisana: $path" "OK"
            return $path
        } catch { }
    }
    Write-Log "Nie udało się zapisać pliku z listą do zrobienia" "ERR"
    return $null
}

# ------------------------------------------------------------
#  Sprawdzenie gotowosci
# ------------------------------------------------------------
function Get-Readiness {
    param([string]$Folder, [string]$UrServer)
    $r = New-Object System.Collections.ArrayList
    $add = { param($s, $n, $d) [void]$r.Add([pscustomobject]@{ Status = $s; Name = $n; Detail = $d }) }

    # system
    try {
        $os = Get-CimInstance Win32_OperatingSystem
        if ($os.Caption -match 'Home') { & $add 'ERR' 'System' "$($os.Caption) - wersja Home nie umożliwia dołączenia do domeny" }
        else { & $add 'OK' 'System' "$($os.Caption) (build $($os.BuildNumber))" }
    } catch { & $add 'WARN' 'System' 'nie udało się odczytać wersji systemu' }

    # domena
    try {
        $cs = Get-CimInstance Win32_ComputerSystem
        if ($cs.PartOfDomain) { & $add 'OK' 'Domena' "komputer jest w domenie $($cs.Domain)" }
        else { & $add 'OK' 'Domena' "poza domeną (grupa robocza: $($cs.Workgroup)) - do dołączenia ręcznie" }
    } catch { }

    # instalatory
    try {
        $have = @(); $miss = @()
        foreach ($a in $script:Catalog) {
            if (Test-Path -LiteralPath (Resolve-Installer $a.file $Folder)) { $have += $a.name } else { $miss += $a.name }
        }
        if ($have.Count -eq 0) { & $add 'ERR' 'Instalatory' "nie znaleziono żadnego instalatora (folder: $Folder)" }
        elseif ($miss.Count -gt 0) { & $add 'WARN' 'Instalatory' "znaleziono $($have.Count) z $($script:Catalog.Count); brakuje: $($miss -join ', ')" }
        else { & $add 'OK' 'Instalatory' "wszystkie pliki na miejscu ($($have.Count))" }
    } catch { }

    # internet
    try {
        if (Test-TcpPort "www.msftconnecttest.com" 80 3000) { & $add 'OK' 'Internet' 'dostępny' }
        else { & $add 'WARN' 'Internet' 'brak połączenia z internetem (potrzebny dla Windows Update)' }
    } catch { }

    # zasilanie i bateria
    try {
        $bat = @(Get-CimInstance Win32_Battery -ErrorAction SilentlyContinue)
        if ($bat.Count -eq 0) { & $add 'OK' 'Zasilanie' 'komputer bez baterii (stacjonarny)' }
        else {
            $pct = $bat[0].EstimatedChargeRemaining
            if ($bat[0].BatteryStatus -eq 1) { & $add 'WARN' 'Zasilanie' "praca na baterii ($pct%) - podłącz zasilacz" }
            else { & $add 'OK' 'Zasilanie' "zasilacz podłączony (bateria $pct%)" }
            try {
                $full = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryFullChargedCapacity -ErrorAction Stop)[0].FullChargedCapacity
                $des  = @(Get-CimInstance -Namespace root\wmi -ClassName BatteryStaticData -ErrorAction Stop)[0].DesignedCapacity
                if ($des -gt 0) {
                    $h = [int](100 * $full / $des)
                    if ($h -lt 60) { & $add 'WARN' 'Bateria' "zużyta: pojemność $h% pojemności fabrycznej" } else { & $add 'OK' 'Bateria' "pojemność $h% fabrycznej" }
                }
            } catch { }
        }
    } catch { }

    # miejsce na dysku
    try {
        $drv = Get-PSDrive -Name ($env:SystemDrive.TrimEnd(':'))
        $free = [math]::Round($drv.Free / 1GB, 1)
        if ($free -lt 10) { & $add 'ERR' 'Miejsce na dysku' "tylko $free GB wolnego na $env:SystemDrive" }
        elseif ($free -lt 20) { & $add 'WARN' 'Miejsce na dysku' "$free GB wolnego na $env:SystemDrive" }
        else { & $add 'OK' 'Miejsce na dysku' "$free GB wolnego na $env:SystemDrive" }
    } catch { }

    # zdrowie dyskow
    try {
        $disks = @(Get-PhysicalDisk -ErrorAction Stop)
        $bad = @($disks | Where-Object { $_.HealthStatus -ne 'Healthy' })
        if ($bad.Count -gt 0) { & $add 'WARN' 'Dyski' "problem ze zdrowiem: $(($bad | ForEach-Object { "$($_.FriendlyName): $($_.HealthStatus)" }) -join '; ')" }
        elseif ($disks.Count -gt 0) { & $add 'OK' 'Dyski' "stan dobry: $(($disks | ForEach-Object { $_.FriendlyName }) -join ', ')" }
    } catch { }

    # oczekujacy restart
    try {
        $pend = (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending') -or
                (Test-Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired') -or
                ($null -ne (Get-ItemProperty 'HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager' -Name PendingFileRenameOperations -ErrorAction SilentlyContinue))
        if ($pend) { & $add 'WARN' 'Restart' 'system oczekuje na restart - zrestartuj przed instalacją' } else { & $add 'OK' 'Restart' 'brak oczekującego restartu' }
    } catch { }

    # antywirus
    try {
        $av = @(Get-CimInstance -Namespace 'root/SecurityCenter2' -ClassName AntiVirusProduct -ErrorAction Stop | ForEach-Object { $_.displayName })
        $other = @($av | Where-Object { $_ -notmatch 'ESET|Windows Defender|Microsoft Defender' })
        if ($other.Count -gt 0) { & $add 'WARN' 'Antywirus' "wykryto inny antywirus: $($other -join ', ') - konflikt z ESET, usuń go przed instalacją" }
        elseif ($av.Count -gt 0) { & $add 'OK' 'Antywirus' ($av -join ', ') }
    } catch { }

    # aktywacja
    try {
        $lic = Get-CimInstance SoftwareLicensingProduct -Filter "ApplicationId='55c92734-d682-4d71-983e-d6ec3f16059f' AND PartialProductKey IS NOT NULL" -ErrorAction Stop | Select-Object -First 1
        if ($lic -and $lic.LicenseStatus -eq 1) { & $add 'OK' 'Aktywacja Windows' 'system aktywowany' }
        else { & $add 'WARN' 'Aktywacja Windows' 'system nieaktywowany' }
    } catch { }

    # znacznik
    $m = Get-PreparedMarker
    if ($m) { & $add 'WARN' 'Poprzednie przygotowanie' "ten komputer był już przygotowany $($m.LastRun) (wersja $($m.Version))" }

    # UrBackup
    if ($UrServer) {
        if (Test-TcpPort $UrServer 55414) { & $add 'OK' 'Serwer UrBackup' "$UrServer odpowiada (port 55414)" }
        else { & $add 'WARN' 'Serwer UrBackup' "$UrServer nie odpowiada na porcie 55414" }
    }
    return @($r)
}

function Write-ReadinessLog {
    param($Results)
    $map = @{ OK = 'OK'; WARN = 'SKIP'; ERR = 'ERR' }
    foreach ($x in $Results) { Write-Log "$($x.Name) - $($x.Detail)" $map[$x.Status] }
}

function Invoke-Readiness {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try { $res = Get-Readiness $txtPath.Text.Trim() $txtUrIp.Text.Trim() }
    finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }

    $tabs.SelectedTab = $tabLog
    Write-Log "Sprawdzenie gotowości" "STEP"
    Write-ReadinessLog $res

    $err  = @($res | Where-Object { $_.Status -eq 'ERR' })
    $warn = @($res | Where-Object { $_.Status -eq 'WARN' })
    $text = "Sprawdzenie gotowości zakończone.`n`nBłędy: $($err.Count)   Ostrzeżenia: $($warn.Count)   OK: $(@($res | Where-Object { $_.Status -eq 'OK' }).Count)"
    $details = @($err + $warn | ForEach-Object { "- $($_.Name): $($_.Detail)" })
    if ($details.Count -gt 0) { $text += "`n`n" + ($details -join "`n") }
    $icon = if ($err.Count -gt 0) { "Error" } elseif ($warn.Count -gt 0) { "Warning" } else { "Information" }
    [void](Show-Msg $text "Sprawdzenie gotowości" "OK" $icon)
}

# ------------------------------------------------------------
#  Wznawianie po restarcie (po aktualizacjach Windows)
# ------------------------------------------------------------
$ResumeFile = Join-Path $env:ProgramData "PrepareWorkstation\resume.json"
$ResumeTask = "PrepareWorkstation-Resume"

function Remove-ResumeState {
    try { Unregister-ScheduledTask -TaskName $ResumeTask -Confirm:$false -ErrorAction SilentlyContinue } catch { }
    Remove-Item -LiteralPath $ResumeFile -Force -ErrorAction SilentlyContinue
}

function Register-ResumeTask {
    try {
        if ($PSCommandPath) {
            $exe  = Join-Path $env:WINDIR "System32\WindowsPowerShell\v1.0\powershell.exe"
            $argl = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$PSCommandPath`" -Resume"
        } else {
            $exe  = [System.Diagnostics.Process]::GetCurrentProcess().MainModule.FileName
            $argl = "-Resume"
        }
        $admins    = (New-Object System.Security.Principal.SecurityIdentifier 'S-1-5-32-544').Translate([System.Security.Principal.NTAccount]).Value
        $action    = New-ScheduledTaskAction -Execute $exe -Argument $argl
        $trigger   = New-ScheduledTaskTrigger -AtLogOn
        $principal = New-ScheduledTaskPrincipal -GroupId $admins -RunLevel Highest
        $settings  = New-ScheduledTaskSettingsSet -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries
        Register-ScheduledTask -TaskName $ResumeTask -Action $action -Trigger $trigger -Principal $principal -Settings $settings -Force | Out-Null
        return $true
    } catch {
        Write-Log "Nie udało się zarejestrować zadania wznowienia: $($_.Exception.Message)" "ERR"
        return $false
    }
}

function Save-ResumeState {
    param($Remaining)
    $planOut = @($Remaining | ForEach-Object {
        $argData = $null
        if ($_.Fn -eq 'Step-App') { $argData = [string]$_.Arg.id }
        elseif ($_.Fn -eq 'Step-Uninstall') {
            $argData = @($_.Arg | ForEach-Object { [pscustomobject]@{ Kind = $_.Kind; Name = $_.Name; Version = $_.Version; Mode = $_.Mode; Cmd = $_.Cmd; Quiet = $_.Quiet; Guid = $_.Guid; Package = $_.Package } })
        }
        elseif ($_.Fn -eq 'Step-Autostart') {
            $argData = @($_.Arg | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Approved = $_.Approved; Disable = [bool]$_.Disable } })
        }
        [pscustomobject]@{ Name = $_.Name; Fn = $_.Fn; Arg = $argData }
    })
    $optsOut = @{}
    foreach ($k in $script:Opts.Keys) { $optsOut[$k] = $script:Opts[$k] }
    $optsOut['EsetKey'] = ""      # klucza nie zapisujemy na dysku

    $state = [pscustomobject]@{
        Version       = $AppVersion
        Saved         = (Get-Date -Format "yyyy-MM-dd HH:mm")
        Opts          = $optsOut
        Plan          = $planOut
        Results       = @($script:Results)
        InstalledIds  = @($script:InstalledNow | ForEach-Object { [string]$_.id })
        Todo          = @($script:Todo)
        FileOverrides = $script:FileOverrides
        WuInstalled   = [bool]$script:WuInstalled
    }
    $dir = Split-Path $ResumeFile -Parent
    if (-not (Test-Path $dir)) { New-Item -ItemType Directory -Path $dir -Force | Out-Null }
    $json = ConvertTo-Json -InputObject $state -Depth 8
    [System.IO.File]::WriteAllText($ResumeFile, $json, (New-Object System.Text.UTF8Encoding($true)))
}

function Import-ResumeState {
    $s = Get-Content -LiteralPath $ResumeFile -Raw -Encoding UTF8 | ConvertFrom-Json
    $o = @{}
    foreach ($p in $s.Opts.PSObject.Properties) { $o[$p.Name] = $p.Value }
    $script:Opts = $o
    $script:DryRun = $false
    $script:ResumeMode = $true
    $script:WuInstalled = [bool]$s.WuInstalled

    $script:FileOverrides = @{}
    if ($s.FileOverrides) {
        foreach ($p in $s.FileOverrides.PSObject.Properties) { if (Test-Path -LiteralPath $p.Value) { $script:FileOverrides[$p.Name] = $p.Value } }
    }
    $script:Results.Clear()
    foreach ($r in @($s.Results)) { [void]$script:Results.Add([pscustomobject]@{ Step = $r.Step; Status = $r.Status; Detail = $r.Detail }) }
    $script:Todo.Clear()
    foreach ($t in @($s.Todo)) { [void]$script:Todo.Add([string]$t) }
    $script:InstalledNow = @()
    foreach ($id in @($s.InstalledIds)) {
        $a = $script:Catalog | Where-Object { [string]$_.id -eq $id } | Select-Object -First 1
        if ($a) { $script:InstalledNow += $a }
    }

    $plan = @()
    foreach ($p in @($s.Plan)) {
        $arg = $p.Arg
        if ($p.Fn -eq 'Step-App') { $arg = $script:Catalog | Where-Object { [string]$_.id -eq [string]$p.Arg } | Select-Object -First 1 }
        $plan += [pscustomobject]@{ Name = $p.Name; Fn = $p.Fn; Arg = $arg }
    }
    return $plan
}

function Show-Summary {
    $ok   = @($script:Results | Where-Object Status -eq 'OK').Count
    $skip = @($script:Results | Where-Object Status -eq 'SKIP').Count
    $err  = @($script:Results | Where-Object Status -eq 'ERR').Count
    $dry  = @($script:Results | Where-Object Status -eq 'DRY').Count

    Write-Log "" "INFO"
    Write-Log "============ PODSUMOWANIE ============" "STEP"
    Write-Log "OK: $ok   Pominięte: $skip   Błędy: $err   Symulacja: $dry" "INFO"
    foreach ($r in ($script:Results | Where-Object Status -eq 'ERR')) { Write-Log "$($r.Step): $($r.Detail)" "ERR" }
    Write-Log "Log zapisano: $LogFile" "INFO"

    $todoPath = $null
    if (-not $script:DryRun) {
        Set-PreparedMarker
        $todoPath = Write-TodoFile
        if ($script:Opts.CopyLog) { Copy-LogToUsb }
    }

    $text = "Gotowe.`n`nOK: $ok`nPominięte: $skip`nBłędy: $err"
    if ($dry -gt 0) { $text = "Tryb testowy - nic nie zostało zmienione.`n`nKroków w symulacji: $dry" }
    if ($todoPath) { $text += "`n`nLista do zrobienia ręcznie:`n$todoPath" }
    $icon = if ($err -gt 0) { "Warning" } else { "Information" }

    if ($script:RebootNeeded -and -not $script:DryRun) {
        $text += "`n`nWymagany restart komputera. Uruchomić ponownie teraz?"
        $r = Show-Msg $text "Prepare Workstation - koniec" "YesNo" $icon
        if ($r -eq 'Yes') { Restart-Computer -Force }
    } else {
        [void](Show-Msg $text "Prepare Workstation - koniec" "OK" $icon)
    }
}

# Wykonuje plan krok po kroku. Po aktualizacjach Windows wymagajacych restartu mozna zapisac stan,
# zrestartowac komputer i dokonczyc pozostale kroki po zalogowaniu (zadanie harmonogramu).
function Invoke-Plan {
    param($Plan, [bool]$Resumed = $false)
    $Plan = @($Plan)

    $script:Cancel = $false
    $script:Resuming = $false
    $script:Running = $true
    if (-not $Resumed) { $script:LogBox.Clear() }
    $tabs.SelectedTab = $tabLog
    foreach ($c in $busyControls) { $c.Enabled = $false }
    $btnCancel.Enabled = $true
    $progress.Maximum = [Math]::Max($Plan.Count, 1)
    $progress.Value = 0

    Write-Log "Prepare Workstation $AppVersion - start: $env:COMPUTERNAME, Windows $([Environment]::OSVersion.Version), użytkownik $env:USERNAME" "INFO"
    if ($Resumed)         { Write-Log "Wznowienie po restarcie - pozostało kroków: $($Plan.Count)" "STEP" }
    if ($script:DryRun)   { Write-Log "TRYB TESTOWY - żadne zmiany nie są wprowadzane" "DRY" }

    $i = 0
    foreach ($s in $Plan) {
        if ($script:Cancel) { Set-Outcome "Przerwano" "SKIP" "pominięto pozostałe kroki ($($Plan.Count - $i))"; break }
        $lblStatus.Text = "Krok $($i + 1)/$($Plan.Count): $($s.Name)"
        Write-Log $s.Name "STEP"
        try {
            if ($s.Arg) { & $s.Fn $s.Arg } else { & $s.Fn }
        } catch {
            Set-Outcome $s.Name "ERR" $_.Exception.Message
        }
        $i++
        $progress.Value = $i

        if ($s.Fn -eq 'Step-WindowsUpdateInstall' -and $script:RebootNeeded -and -not $script:DryRun) {
            $remaining = @($Plan | Select-Object -Skip $i)
            if ($remaining.Count -gt 0) {
                $ans = Show-Msg ("Aktualizacje Windows wymagają restartu.`n`nPozostało kroków: $($remaining.Count).`n`n" +
                                 "TAK - zrestartuj teraz; po zalogowaniu (konto administratora) program dokończy resztę.`n" +
                                 "NIE - kontynuuj bez restartu.") `
                                "Restart po aktualizacjach" "YesNo" "Question"
                if ($ans -eq 'Yes') {
                    try {
                        Save-ResumeState $remaining
                        if (Register-ResumeTask) { $script:Resuming = $true; break }
                        Remove-ResumeState
                    } catch {
                        Write-Log "Nie udało się zapisać stanu do wznowienia: $($_.Exception.Message)" "ERR"
                        Remove-ResumeState
                    }
                }
            }
        }
    }

    $script:Running = $false
    if ($script:Resuming) {
        $lblStatus.Text = "Restart..."
        Write-Log "Zapisano stan. Komputer zostanie zrestartowany - po zalogowaniu program dokończy pozostałe kroki." "INFO"
        Start-Sleep -Seconds 2
        Restart-Computer -Force
        return
    }

    $lblStatus.Text = "Zakończono."
    foreach ($c in $busyControls) { $c.Enabled = $true }
    $btnCancel.Enabled = $false
    Show-Summary
}

function Invoke-Resume {
    if (-not (Test-Path -LiteralPath $ResumeFile)) {
        Remove-ResumeState
        [void](Show-Msg "Brak zapisanego stanu do wznowienia." "Prepare Workstation" "OK" "Information")
        return
    }
    try { $plan = Import-ResumeState } catch {
        [void](Show-Msg "Nie można wczytać zapisanego stanu:`n$($_.Exception.Message)" "Prepare Workstation" "OK" "Error")
        Remove-ResumeState
        return
    }
    $ans = Show-Msg ("Wznowienie przygotowania komputera po restarcie.`n`nPozostało kroków: $($plan.Count):`n- " +
                     (($plan | ForEach-Object { $_.Name }) -join "`n- ") + "`n`nKontynuować?") `
                    "Wznowienie" "YesNo" "Question"
    Remove-ResumeState
    if ($ans -ne 'Yes') { return }
    Invoke-Plan $plan $true
}

function Start-Setup {
    $name = $txtName.Text.Trim()
    $renameWanted = ($name -ne "" -and $name -ne $env:COMPUTERNAME)
    if ($renameWanted -and $name -notmatch '^(?!\d+$)[a-zA-Z0-9\-]{1,15}$') {
        [void](Show-Msg "Nieprawidłowa nazwa komputera (litery, cyfry, myślniki; max 15 znaków; nie same cyfry)." "Błąd" "OK" "Warning")
        return
    }
    if ($chkChrome.Checked -and $txtChrome.Text.Trim() -notmatch '^https?://\S+$') {
        [void](Show-Msg "Adres strony startowej Chrome musi zaczynać się od http:// lub https://" "Błąd" "OK" "Warning")
        return
    }
    $ur = $txtUrIp.Text.Trim()
    if ($ur -and $ur -notmatch '^[A-Za-z0-9\.\-]{1,253}$') {
        [void](Show-Msg "Nieprawidłowy adres serwera UrBackup (adres IP lub nazwa hosta)." "Błąd" "OK" "Warning")
        return
    }

    $o = @{}
    $o.InstallerPath   = $txtPath.Text.Trim()
    $o.NewName         = if ($renameWanted) { $name } else { $null }
    $o.PowerPlan       = $chkPlan.Checked
    $o.PowerNever      = $chkNever.Checked
    $o.Hibernate       = $chkHib.Checked
    $o.ScreenSaver     = $chkSaver.Checked
    $o.SkipInstalled   = $chkSkipInst.Checked
    $o.EsetKey         = $txtEset.Text.Trim()
    $o.TimeZone        = [string]$cmbTz.SelectedItem
    $o.Hash            = $chkHash.Checked
    $o.ChromeUrl       = $txtChrome.Text.Trim()
    $o.CopyLog         = $chkCopyLog.Checked
    $o.UrServer        = $ur
    $o.UninProvisioned = $chkUninProv.Checked
    $script:Opts       = $o
    $script:DryRun     = $chkDry.Checked

    $apps  = @($lvApps.CheckedItems | ForEach-Object { $_.Tag })
    $unin  = @($script:UninstallCache | Where-Object { $script:UninSel.ContainsKey("$($_.Kind)|$($_.Name)|$($_.Version)") })
    $autoChanges = @()
    foreach ($it in $lvAuto.Items) {
        $a = $it.Tag
        if ($it.Checked -ne [bool]$a.Disabled) {
            $autoChanges += [pscustomobject]@{ Name = $a.Name; Approved = $a.Approved; Disable = $it.Checked }
        }
    }

    # --- plan ---
    $plan = @()
    if ($chkRestore.Checked) { $plan += [pscustomobject]@{ Name = "Punkt przywracania systemu"; Fn = "Step-RestorePoint"; Arg = $null } }
    if ($renameWanted)       { $plan += [pscustomobject]@{ Name = "Nazwa komputera: $name";     Fn = "Step-Rename";       Arg = $null } }
    if ($o.PowerPlan -or $o.PowerNever -or $o.Hibernate -or $o.ScreenSaver) {
                               $plan += [pscustomobject]@{ Name = "Ustawienia zasilania";       Fn = "Step-Power";        Arg = $null } }
    if ($chkMcAfee.Checked)  { $plan += [pscustomobject]@{ Name = "Usuwanie McAfee";            Fn = "Step-McAfee";       Arg = $null } }
    if ($chkOffice.Checked)  { $plan += [pscustomobject]@{ Name = "Usuwanie starego Office";    Fn = "Step-Office";       Arg = $null } }
    if ($unin.Count -gt 0)   { $plan += [pscustomobject]@{ Name = "Odinstalowanie programów ($($unin.Count))"; Fn = "Step-Uninstall"; Arg = $unin } }
    foreach ($a in $apps)    { $plan += [pscustomobject]@{ Name = "Instalacja: $($a.name)";     Fn = "Step-App";          Arg = $a } }
    if ($chkVerify.Checked -and $apps.Count -gt 0) {
                               $plan += [pscustomobject]@{ Name = "Weryfikacja instalacji";     Fn = "Step-Verify";       Arg = $null } }
    if ($ur)                 { $plan += [pscustomobject]@{ Name = "UrBackup - serwer $ur";      Fn = "Step-UrBackupServer"; Arg = $null } }
    if ($autoChanges.Count -gt 0) {
                               $plan += [pscustomobject]@{ Name = "Autostart (zmian: $($autoChanges.Count))"; Fn = "Step-Autostart"; Arg = $autoChanges } }
    if ($chkTz.Checked)      { $plan += [pscustomobject]@{ Name = "Strefa czasowa";             Fn = "Step-TimeZone";     Arg = $null } }
    if ($chkExt.Checked)     { $plan += [pscustomobject]@{ Name = "Eksplorator plików";         Fn = "Step-FileExt";      Arg = $null } }
    if ($chkThisPC.Checked)  { $plan += [pscustomobject]@{ Name = "Ikona Ten komputer";         Fn = "Step-ThisPC";       Arg = $null } }
    if ($chkAds.Checked)       { $plan += [pscustomobject]@{ Name = "Wyłączenie reklam i sugestii"; Fn = "Step-Ads";          Arg = $null } }
    if ($chkNoFb.Checked)      { $plan += [pscustomobject]@{ Name = "Bez pytań o opinię i podpowiedzi"; Fn = "Step-NoFeedback"; Arg = $null } }
    if ($chkLang.Checked)      { $plan += [pscustomobject]@{ Name = "Region i język: polski";    Fn = "Step-Language";     Arg = $null } }
    if ($chkShortcuts.Checked) { $plan += [pscustomobject]@{ Name = "Skróty na pulpicie";        Fn = "Step-Shortcuts";    Arg = $null } }
    if ($chkChrome.Checked)    { $plan += [pscustomobject]@{ Name = "Chrome - strona startowa";  Fn = "Step-ChromePolicy"; Arg = $null } }
    if ($chkWUInstall.Checked) { $plan += [pscustomobject]@{ Name = "Aktualizacje Windows";      Fn = "Step-WindowsUpdateInstall"; Arg = $null } }
    if ($chkCleanInst.Checked) { $plan += [pscustomobject]@{ Name = "Sprzątanie instalatorów";   Fn = "Step-CleanInstallers"; Arg = $null } }
    if ($chkCleanTemp.Checked) { $plan += [pscustomobject]@{ Name = "Sprzątanie plików tymczasowych"; Fn = "Step-CleanTemp"; Arg = $null } }
    if ($chkPolicy.Checked)  { $plan += [pscustomobject]@{ Name = "Przywrócenie ExecutionPolicy"; Fn = "Step-Policy";     Arg = $null } }
    if ($chkWU.Checked)      { $plan += [pscustomobject]@{ Name = "Windows Update";             Fn = "Step-WindowsUpdate"; Arg = $null } }

    if ($plan.Count -eq 0) {
        [void](Show-Msg "Nic nie zaznaczono do wykonania." "Prepare Workstation" "OK" "Information")
        return
    }

    # --- ostrzezenia przed startem ---
    $notes = ""
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try { $ready = Get-Readiness $o.InstallerPath $ur } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
    $bad = @($ready | Where-Object { $_.Status -eq 'ERR' })
    if ($bad.Count -gt 0) { $notes += "`n`nUWAGA - problemy wykryte przy sprawdzeniu gotowości:`n" + (($bad | ForEach-Object { "- $($_.Name): $($_.Detail)" }) -join "`n") }
    $m = Get-PreparedMarker
    if ($m -and -not $script:DryRun) { $notes += "`n`nUWAGA: ten komputer był już przygotowany $($m.LastRun) (wersja $($m.Version))." }

    $mode = if ($script:DryRun) { "TRYB TESTOWY (symulacja)" } else { "Zmiany zostaną wprowadzone w systemie" }
    $r = Show-Msg ("$mode`n`nKroki ($($plan.Count)):`n- " + (($plan | ForEach-Object { $_.Name }) -join "`n- ") + $notes + "`n`nKontynuować?") `
                  "Potwierdzenie" "YesNo" "Question"
    if ($r -ne 'Yes') { return }

    # --- wykonanie ---
    $script:Results.Clear()
    $script:Todo.Clear()
    $script:RebootNeeded = $false
    $script:WuInstalled = $false
    $script:ResumeMode = $false
    $script:InstalledNow = @()
    Invoke-Plan $plan $false
}

# ============================================================
#  BUDOWA OKNA
# ============================================================
function New-Ctl {
    param([string]$Type, [string]$Text = "", [int]$X = 0, [int]$Y = 0, [int]$W = 100, [int]$H = 23, $Parent = $null)
    $c = New-Object $Type
    $c.Text     = $Text
    $c.Location = New-Object System.Drawing.Point($X, $Y)
    $c.Size     = New-Object System.Drawing.Size($W, $H)
    if ($Parent) { $Parent.Controls.Add($c) }
    return $c
}
function New-Group { param($Text, $X, $Y, $W, $H, $Parent) return (New-Ctl System.Windows.Forms.GroupBox $Text $X $Y $W $H $Parent) }
function New-Check {
    param($Text, $X, $Y, $W, $Parent, [bool]$Checked = $true)
    $c = New-Ctl System.Windows.Forms.CheckBox $Text $X $Y $W 22 $Parent
    $c.Checked = $Checked
    return $c
}
function New-Label {
    param($Text, $X, $Y, $W, $H, $Parent)
    $c = New-Ctl System.Windows.Forms.Label $Text $X $Y $W $H $Parent
    $c.AutoSize = $false
    return $c
}

$form = New-Object System.Windows.Forms.Form
$form.Text          = "Prepare Workstation $AppVersion - przygotowanie komputera firmowego"
$form.ClientSize    = New-Object System.Drawing.Size(920, 690)
$form.MinimumSize   = New-Object System.Drawing.Size(800, 560)
$form.StartPosition = "CenterScreen"
$form.Font          = New-Object System.Drawing.Font("Segoe UI", 9)

$tabs     = New-Object System.Windows.Forms.TabControl
$tabs.Dock = "Fill"
$tabSet   = New-Object System.Windows.Forms.TabPage "Ustawienia"
$tabApps  = New-Object System.Windows.Forms.TabPage "Aplikacje"
$tabUnin  = New-Object System.Windows.Forms.TabPage "Odinstaluj"
$tabAuto  = New-Object System.Windows.Forms.TabPage "Autostart"
$tabLog   = New-Object System.Windows.Forms.TabPage "Przebieg"
$tabSet.AutoScroll = $true
[void]$tabs.TabPages.Add($tabSet)
[void]$tabs.TabPages.Add($tabApps)
[void]$tabs.TabPages.Add($tabUnin)
[void]$tabs.TabPages.Add($tabAuto)
[void]$tabs.TabPages.Add($tabLog)
$form.Controls.Add($tabs)       # Fill dodajemy jako pierwszy

$bottom = New-Object System.Windows.Forms.Panel
$bottom.Dock   = "Bottom"
$bottom.Height = 84
$form.Controls.Add($bottom)

# --- zakladka: Ustawienia, lewa kolumna ---
$gPath = New-Group "Folder z instalatorami" 12 10 420 66 $tabSet
$txtPath = New-Ctl System.Windows.Forms.TextBox $InstallerPath 12 27 300 23 $gPath
$btnBrowse = New-Ctl System.Windows.Forms.Button "Przeglądaj..." 320 25 90 27 $gPath

$gName = New-Group "Nazwa komputera" 12 84 420 84 $tabSet
[void](New-Label "Aktualna nazwa: $env:COMPUTERNAME" 12 22 396 18 $gName)
$txtName = New-Ctl System.Windows.Forms.TextBox $env:COMPUTERNAME 12 44 200 23 $gName
$txtName.MaxLength = 15
$lblNameHint = New-Label "litery, cyfry, myślniki; max 15" 220 47 190 18 $gName
$lblNameHint.ForeColor = [System.Drawing.Color]::Gray

$gPower = New-Group "Zasilanie" 12 176 420 124 $tabSet
$chkPlan  = New-Check "Plan zasilania: Wysoka wydajność"      12 22 396 $gPower
$chkNever = New-Check "Ekran i usypianie: nigdy (AC i DC)"    12 46 396 $gPower
$chkHib   = New-Check "Wyłącz hibernację"                     12 70 396 $gPower
$chkSaver = New-Check "Wyłącz wygaszacz ekranu"               12 94 396 $gPower

$gClean = New-Group "Czyszczenie przed instalacją" 12 308 420 80 $tabSet
$chkMcAfee = New-Check "Usuń McAfee (Antivirus, WebAdvisor)"                 12 22 396 $gClean
$chkOffice = New-Check "Usuń stary Office (oficjalne narzędzie SaRA)"       12 46 396 $gClean

# --- zakladka: Ustawienia, prawa kolumna ---
$gExtra = New-Group "Dodatkowe ustawienia" 444 10 440 150 $tabSet
$chkRestore = New-Check "Utwórz punkt przywracania systemu przed zmianami" 12 22 416 $gExtra
$chkTz      = New-Check "Strefa czasowa:" 12 46 120 $gExtra
$cmbTz = New-Object System.Windows.Forms.ComboBox
$cmbTz.DropDownStyle = "DropDownList"
$cmbTz.Location = New-Object System.Drawing.Point(136, 45)
$cmbTz.Size = New-Object System.Drawing.Size(290, 23)
foreach ($tz in [System.TimeZoneInfo]::GetSystemTimeZones()) { [void]$cmbTz.Items.Add($tz.Id) }
$cmbTz.SelectedItem = "Central European Standard Time"
if ($cmbTz.SelectedIndex -lt 0 -and $cmbTz.Items.Count -gt 0) { $cmbTz.SelectedIndex = 0 }
$gExtra.Controls.Add($cmbTz)
$chkExt    = New-Check "Pokaż rozszerzenia plików i ukryte pliki"           12 74  416 $gExtra
$chkThisPC = New-Check "Ikona «Ten komputer» na pulpicie"                   12 98  416 $gExtra
$chkTz.Checked = $true

$gOpt = New-Group "Opcje instalacji" 444 168 440 152 $tabSet
$chkSkipInst = New-Check "Pomijaj aplikacje, które są już zainstalowane" 12 22 416 $gOpt
$chkVerify   = New-Check "Zweryfikuj instalację w rejestrze po zakończeniu" 12 46 416 $gOpt
$chkHash     = New-Check "Sprawdzaj sumy SHA256 instalatorów (jeśli są w apps.json)" 12 70 416 $gOpt
[void](New-Label "Klucz ESET (opcjonalnie):" 12 102 150 20 $gOpt)
$txtEset = New-Ctl System.Windows.Forms.TextBox "" 166 99 262 23 $gOpt
$txtEset.UseSystemPasswordChar = $true
$lblEsetHint = New-Label "Klucz nie jest zapisywany do logu ani na dysku." 12 126 416 18 $gOpt
$lblEsetHint.ForeColor = [System.Drawing.Color]::Gray

$gMore = New-Group "Dodatkowe funkcje" 444 328 440 178 $tabSet
$chkAds       = New-Check "Wyłącz reklamy i sugestie w Windows (Start, ekran blokady)"  12 22 416 $gMore
$chkNoFb      = New-Check "Bez pytań o opinię i podpowiedzi (Feedback, Spotlight, porady)" 12 46 416 $gMore
$chkLang      = New-Check "Region i język: polski (pl-PL), klawiatura polska programisty" 12 70 416 $gMore $false
$chkShortcuts = New-Check "Skróty na pulpicie: Chrome, Word, Excel, Outlook, Adobe Reader" 12 94 416 $gMore
$chkChrome    = New-Check "Chrome: strona startowa firmy (zasada Chrome Enterprise)"    12 118 416 $gMore $false
$txtChrome    = New-Ctl System.Windows.Forms.TextBox "https://www.google.pl" 32 144 396 23 $gMore

$gTidy = New-Group "Sprzątanie" 12 396 420 104 $tabSet
$chkCleanTemp = New-Check "Wyczyść pliki tymczasowe i koszyk na koniec"                  12 22 396 $gTidy $false
$chkCleanInst = New-Check "Usuń zainstalowane instalatory z folderu (tylko dysk lokalny)" 12 46 396 $gTidy $false
$chkCopyLog   = New-Check "Skopiuj log na pendrive po zakończeniu"                       12 70 396 $gTidy $false

$gEnd = New-Group "Na koniec" 12 508 420 104 $tabSet
$chkWUInstall = New-Check "Zainstaluj aktualizacje Windows (może potrwać długo)" 12 22 396 $gEnd $false
$chkWU        = New-Check "Otwórz Windows Update"                                12 46 396 $gEnd $false
$chkPolicy    = New-Check "Przywróć ExecutionPolicy (Restricted)"                12 70 396 $gEnd

# --- zakladka: Aplikacje ---
$lvApps = New-Object System.Windows.Forms.ListView
$lvApps.Dock = "Fill"
$lvApps.View = "Details"
$lvApps.CheckBoxes = $true
$lvApps.FullRowSelect = $true
$lvApps.GridLines = $true
[void]$lvApps.Columns.Add("Aplikacja", 230)
[void]$lvApps.Columns.Add("Plik instalatora", 270)
[void]$lvApps.Columns.Add("Plik w folderze", 110)
[void]$lvApps.Columns.Add("Zainstalowana", 100)
[void]$lvApps.Columns.Add("Suma SHA256", 90)
[void]$lvApps.Columns.Add("Tryb", 90)
$tabApps.Controls.Add($lvApps)

$appsBar = New-Object System.Windows.Forms.Panel
$appsBar.Dock = "Bottom"
$appsBar.Height = 44
$tabApps.Controls.Add($appsBar)
$btnAll     = New-Ctl System.Windows.Forms.Button "Zaznacz wszystkie" 8 8 120 28 $appsBar
$btnNone    = New-Ctl System.Windows.Forms.Button "Odznacz wszystkie" 136 8 120 28 $appsBar
$btnRefresh = New-Ctl System.Windows.Forms.Button "Odśwież listę"     264 8 100 28 $appsBar
$btnEdit    = New-Ctl System.Windows.Forms.Button "Edytuj apps.json"  372 8 112 28 $appsBar
$btnAddFiles = New-Ctl System.Windows.Forms.Button "Dodaj pliki..."    492 8 100 28 $appsBar
$btnUsb      = New-Ctl System.Windows.Forms.Button "Znajdź na pendrive" 600 8 130 28 $appsBar
$btnHash     = New-Ctl System.Windows.Forms.Button "Zapisz sumy SHA256" 738 8 140 28 $appsBar

$urBar = New-Object System.Windows.Forms.Panel
$urBar.Dock = "Bottom"
$urBar.Height = 36
$tabApps.Controls.Add($urBar)
[void](New-Label "Serwer UrBackup (adres IP):" 8 10 170 20 $urBar)
$txtUrIp = New-Ctl System.Windows.Forms.TextBox "" 180 7 160 23 $urBar
$lblUrHint = New-Label "opcjonalnie - sprawdzę połączenie z serwerem i dopiszę instrukcję do listy «do zrobienia»" 352 10 520 18 $urBar
$lblUrHint.ForeColor = [System.Drawing.Color]::Gray

$lblDrop = New-Object System.Windows.Forms.Label
$lblDrop.Dock = "Top"
$lblDrop.Height = 26
$lblDrop.TextAlign = "MiddleLeft"
$lblDrop.ForeColor = [System.Drawing.Color]::DimGray
$lblDrop.Text = "  Przeciągnij na okno pliki instalatorów lub cały folder z pendrive'a - program rozpozna je po nazwie i użyje bezpośrednio z pendrive'a."
$tabApps.Controls.Add($lblDrop)

# --- zakladka: Odinstaluj ---
$lvUnin = New-Object System.Windows.Forms.ListView
$lvUnin.Dock = "Fill"
$lvUnin.View = "Details"
$lvUnin.CheckBoxes = $true
$lvUnin.FullRowSelect = $true
$lvUnin.GridLines = $true
[void]$lvUnin.Columns.Add("Nazwa", 300)
[void]$lvUnin.Columns.Add("Wersja", 90)
[void]$lvUnin.Columns.Add("Wydawca", 180)
[void]$lvUnin.Columns.Add("Rozmiar", 70)
[void]$lvUnin.Columns.Add("Typ", 110)
[void]$lvUnin.Columns.Add("Tryb", 90)
$tabUnin.Controls.Add($lvUnin)

$uninTop = New-Object System.Windows.Forms.Panel
$uninTop.Dock = "Top"
$uninTop.Height = 70
$tabUnin.Controls.Add($uninTop)
[void](New-Label "Szukaj:" 8 11 50 20 $uninTop)
$txtUninFilter = New-Ctl System.Windows.Forms.TextBox "" 60 8 220 23 $uninTop
$chkUninAll    = New-Check "Pokaż także komponenty i aktualizacje" 296 8 260 $uninTop $false
$chkUninProv   = New-Check "Sklep: usuń też dla nowych użytkowników" 560 8 320 $uninTop
$btnUninRefresh = New-Ctl System.Windows.Forms.Button "Odśwież listę" 8 36 110 28 $uninTop
$btnUninJunk    = New-Ctl System.Windows.Forms.Button "Zaznacz typowe zbędne" 126 36 170 28 $uninTop
$btnUninNone    = New-Ctl System.Windows.Forms.Button "Odznacz wszystkie" 304 36 130 28 $uninTop
$lblUninHint = New-Label "Lista jak w Ustawienia - Aplikacje. Zaznaczone zostaną odinstalowane przed instalacją nowych programów." 442 41 440 18 $uninTop
$lblUninHint.ForeColor = [System.Drawing.Color]::Gray

# --- zakladka: Autostart ---
$lvAuto = New-Object System.Windows.Forms.ListView
$lvAuto.Dock = "Fill"
$lvAuto.View = "Details"
$lvAuto.CheckBoxes = $true
$lvAuto.FullRowSelect = $true
$lvAuto.GridLines = $true
[void]$lvAuto.Columns.Add("Nazwa", 210)
[void]$lvAuto.Columns.Add("Polecenie", 360)
[void]$lvAuto.Columns.Add("Źródło", 150)
[void]$lvAuto.Columns.Add("Stan", 90)
$tabAuto.Controls.Add($lvAuto)

$autoTop = New-Object System.Windows.Forms.Panel
$autoTop.Dock = "Top"
$autoTop.Height = 74
$tabAuto.Controls.Add($autoTop)
$lblAutoHint = New-Label "Zaznaczone = wyłączone przy starcie systemu (tak jak w Menedżerze zadań); odznaczenie przywraca autostart. Dotyczy wpisów dla wszystkich użytkowników (HKLM) i konta administratora (HKCU). Zmiany widać po ponownym zalogowaniu." 8 6 870 32 $autoTop
$lblAutoHint.ForeColor = [System.Drawing.Color]::DimGray
$btnAutoRefresh = New-Ctl System.Windows.Forms.Button "Odśwież (stan początkowy)" 8 40 170 28 $autoTop
$btnAutoJunk    = New-Ctl System.Windows.Forms.Button "Zaznacz typowe zbędne" 186 40 170 28 $autoTop

# --- zakladka: Przebieg ---
$script:LogBox = New-Object System.Windows.Forms.RichTextBox
$script:LogBox.Dock = "Fill"
$script:LogBox.ReadOnly = $true
$script:LogBox.BackColor = [System.Drawing.Color]::FromArgb(30, 30, 30)
$script:LogBox.ForeColor = [System.Drawing.Color]::Gainsboro
$script:LogBox.Font = New-Object System.Drawing.Font("Consolas", 9.5)
$tabLog.Controls.Add($script:LogBox)

# --- dol: postep i przyciski ---
$progress = New-Ctl System.Windows.Forms.ProgressBar "" 12 8 896 16 $bottom
$progress.Anchor = "Top, Left, Right"
$lblStatus = New-Label "Gotowy." 12 28 896 18 $bottom
$lblStatus.Anchor = "Top, Left, Right"
$btnRun    = New-Ctl System.Windows.Forms.Button "Uruchom" 12 48 140 30 $bottom
$btnRun.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)
$btnCancel = New-Ctl System.Windows.Forms.Button "Przerwij" 160 48 90 30 $bottom
$btnCancel.Enabled = $false
$btnLogs   = New-Ctl System.Windows.Forms.Button "Folder logów" 258 48 110 30 $bottom
$chkDry    = New-Check "Tryb testowy (nic nie zmieniaj)" 384 53 205 $bottom $false
$btnReady  = New-Ctl System.Windows.Forms.Button "Sprawdź gotowość" 596 48 140 30 $bottom
$btnClose  = New-Ctl System.Windows.Forms.Button "Zamknij" 808 48 100 30 $bottom
$btnClose.Anchor = "Top, Right"

# kontrolki blokowane na czas pracy (zakladka "Przebieg", Przerwij i Folder logow zostaja aktywne)
$busyControls = @($tabSet, $lvApps, $appsBar, $urBar, $tabUnin, $tabAuto, $btnRun, $btnReady, $chkDry)

# ============================================================
#  ZDARZENIA
# ============================================================
function Update-AppList {
    param([bool]$ReloadCatalog = $false, [bool]$KeepSelection = $false, [string[]]$ForceCheck = @())

    $prev = @{}
    if ($KeepSelection) { foreach ($it in $lvApps.Items) { $prev[[string]$it.Tag.id] = $it.Checked } }
    if ($ReloadCatalog) { $script:Catalog = Get-AppCatalog }

    $lvApps.Items.Clear()
    $installed = @(Get-InstalledApps)
    $types = @{ exe = "cicha"; msi = "cicha (MSI)"; manual = "ręczna" }
    $folder = $txtPath.Text.Trim()

    foreach ($a in $script:Catalog) {
        $id     = [string]$a.id
        $key    = ([string]$a.file).ToLower()
        $isOver = $script:FileOverrides.ContainsKey($key) -and (Test-Path $script:FileOverrides[$key])
        $fileOk = $isOver -or (Test-Path (Join-Path $folder $a.file))
        $isInst = $false
        if ($a.detect) {
            $isInst = [bool]($installed | Where-Object { $_.DisplayName -match $a.detect } | Select-Object -First 1)
        }
        $fileCol = if ($isOver) { "dodany ręcznie" } elseif ($fileOk) { "tak" } else { "BRAK" }

        $item = New-Object System.Windows.Forms.ListViewItem($a.name)
        [void]$item.SubItems.Add($a.file)
        [void]$item.SubItems.Add($fileCol)
        [void]$item.SubItems.Add($(if ($isInst) { "tak" } else { "nie" }))
        [void]$item.SubItems.Add($(if ($a.PSObject.Properties['sha256'] -and $a.sha256) { "zapisana" } else { "brak" }))
        [void]$item.SubItems.Add([string]$types[[string]$a.type])
        $item.Tag = $a

        if ($ForceCheck -contains $id)                           { $item.Checked = $true }
        elseif ($KeepSelection -and $prev.ContainsKey($id))      { $item.Checked = ($prev[$id] -and $fileOk) }
        else                                                     { $item.Checked = ($fileOk -and [bool]$a.default) }

        if (-not $fileOk) { $item.ForeColor = [System.Drawing.Color]::Gray }
        [void]$lvApps.Items.Add($item)
    }
}

# Dopasowuje pliki/foldery (przeciagniete lub znalezione na pendrive) do aplikacji z apps.json po nazwie pliku
function Add-DroppedPaths {
    param([string[]]$Paths)

    $files = @()
    foreach ($p in $Paths) {
        if (Test-Path -LiteralPath $p -PathType Container) {
            $files += @(Get-ChildItem -LiteralPath $p -File -Recurse -Depth 3 -ErrorAction SilentlyContinue)
        } elseif (Test-Path -LiteralPath $p -PathType Leaf) {
            $files += Get-Item -LiteralPath $p
        }
    }

    $byName = @{}
    foreach ($a in $script:Catalog) { $byName[([string]$a.file).ToLower()] = $a }

    $matchedIds = @()
    $unmatched  = 0
    foreach ($f in $files) {
        $k = $f.Name.ToLower()
        if ($byName.ContainsKey($k)) {
            $script:FileOverrides[$k] = $f.FullName
            $matchedIds += [string]$byName[$k].id
            Write-Log "Dodano: $($byName[$k].name) <- $($f.FullName)" "OK"
        } else {
            $unmatched++
        }
    }

    if ($matchedIds.Count -eq 0) {
        Write-Log "Żaden z $($files.Count) plików nie pasuje do apps.json (rozpoznawanie po nazwie pliku)." "SKIP"
        [void](Show-Msg "Nie rozpoznano żadnego instalatora.`nProgram dopasowuje pliki po nazwie podanej w apps.json (kolumna «Plik instalatora»)." "Prepare Workstation" "OK" "Information")
        return
    }
    if ($unmatched -gt 0) { Write-Log "Pominięto $unmatched plików niepasujących do żadnej aplikacji." "INFO" }
    Update-AppList $false $true $matchedIds
    $tabs.SelectedTab = $tabApps
}

# Szuka instalatorow na pendrive'ach (dyskach wymiennych)
function Find-RemovableInstallers {
    $roots = @([System.IO.DriveInfo]::GetDrives() |
        Where-Object { $_.DriveType -eq 'Removable' -and $_.IsReady } |
        ForEach-Object { $_.RootDirectory.FullName })
    if ($roots.Count -eq 0) {
        [void](Show-Msg "Nie wykryto pendrive'a (dysku wymiennego).`nPodłącz go albo użyj przycisku «Dodaj pliki...»." "Prepare Workstation" "OK" "Information")
        return
    }
    $names = @($script:Catalog | ForEach-Object { ([string]$_.file).ToLower() })
    $found = @()
    foreach ($r in $roots) {
        Write-Log "Przeszukuję: $r" "INFO"
        $found += @(Get-ChildItem -LiteralPath $r -File -Recurse -Depth 3 -ErrorAction SilentlyContinue |
                    Where-Object { $names -contains $_.Name.ToLower() })
    }
    if ($found.Count -eq 0) {
        [void](Show-Msg "Na dyskach wymiennych ($($roots -join ', ')) nie znaleziono pasujących instalatorów." "Prepare Workstation" "OK" "Information")
        return
    }
    Add-DroppedPaths @($found | ForEach-Object { $_.FullName })
}

function Enable-ElevatedDrop {
    try {
        foreach ($c in @($form, $tabApps, $lvApps)) {
            foreach ($m in 0x233, 0x4A, 0x49) {   # WM_DROPFILES, WM_COPYDATA, WM_COPYGLOBALDATA
                [void][Win32.Uipi]::ChangeWindowMessageFilterEx($c.Handle, [uint32]$m, 1, [IntPtr]::Zero)
            }
        }
    } catch { }
}

function Update-UninstallView {
    $filter = $txtUninFilter.Text.Trim()
    $script:UninFilling = $true
    try {
        $lvUnin.BeginUpdate()
        $lvUnin.Items.Clear()
        foreach ($it in $script:UninstallCache) {
            if ($filter) {
                $hit = ($it.Name.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0) -or
                       ($it.Publisher.IndexOf($filter, [System.StringComparison]::OrdinalIgnoreCase) -ge 0)
                if (-not $hit) { continue }
            }
            $key = "$($it.Kind)|$($it.Name)|$($it.Version)"
            $item = New-Object System.Windows.Forms.ListViewItem($it.Name)
            $item.Name = $key
            [void]$item.SubItems.Add($it.Version)
            [void]$item.SubItems.Add($it.Publisher)
            [void]$item.SubItems.Add($it.Size)
            [void]$item.SubItems.Add($(if ($it.Kind -eq 'Store') { "Aplikacja Sklepu" } else { "Program" }))
            [void]$item.SubItems.Add($it.Mode)
            $item.Tag = $it
            $item.Checked = $script:UninSel.ContainsKey($key)
            if ($it.IsComponent) { $item.ForeColor = [System.Drawing.Color]::Gray }
            [void]$lvUnin.Items.Add($item)
        }
    } finally {
        $lvUnin.EndUpdate()
        $script:UninFilling = $false
    }
}

function Update-UninstallList {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $script:UninstallCache = @(Get-UninstallList ([bool]$chkUninAll.Checked))
        $script:UninLoaded = $true
        $keys = @{}
        foreach ($it in $script:UninstallCache) { $keys["$($it.Kind)|$($it.Name)|$($it.Version)"] = $true }
        foreach ($k in @($script:UninSel.Keys)) { if (-not $keys.ContainsKey($k)) { $script:UninSel.Remove($k) } }
    } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
    Update-UninstallView
}

function Update-AutostartList {
    $form.Cursor = [System.Windows.Forms.Cursors]::WaitCursor
    try {
        $lvAuto.Items.Clear()
        foreach ($a in @(Get-AutostartList)) {
            $item = New-Object System.Windows.Forms.ListViewItem($a.Name)
            [void]$item.SubItems.Add($a.Command)
            [void]$item.SubItems.Add($a.Source)
            [void]$item.SubItems.Add($(if ($a.Disabled) { "wyłączony" } else { "włączony" }))
            $item.Tag = $a
            $item.Checked = [bool]$a.Disabled
            [void]$lvAuto.Items.Add($item)
        }
        $script:AutoLoaded = $true
    } finally { $form.Cursor = [System.Windows.Forms.Cursors]::Default }
}

$txtName.Add_TextChanged({
    $n = $txtName.Text.Trim()
    if ($n -eq "" -or $n -eq $env:COMPUTERNAME -or $n -match '^(?!\d+$)[a-zA-Z0-9\-]{1,15}$') {
        $lblNameHint.ForeColor = [System.Drawing.Color]::Gray
        $lblNameHint.Text = "litery, cyfry, myślniki; max 15"
    } else {
        $lblNameHint.ForeColor = [System.Drawing.Color]::Firebrick
        $lblNameHint.Text = "nieprawidłowa nazwa"
    }
})

$btnBrowse.Add_Click({
    $dlg = New-Object System.Windows.Forms.FolderBrowserDialog
    $dlg.Description = "Wybierz folder z instalatorami"
    if (Test-Path $txtPath.Text) { $dlg.SelectedPath = $txtPath.Text }
    if ($dlg.ShowDialog() -eq 'OK') { $txtPath.Text = $dlg.SelectedPath; Update-AppList }
})
$txtPath.Add_Leave({ Update-AppList })

$btnAll.Add_Click({  foreach ($i in $lvApps.Items) { $i.Checked = $true } })
$btnNone.Add_Click({ foreach ($i in $lvApps.Items) { $i.Checked = $false } })
$btnRefresh.Add_Click({ Update-AppList $true })
$btnEdit.Add_Click({ Start-Process notepad.exe -ArgumentList "`"$AppsFile`"" })

$btnAddFiles.Add_Click({
    $dlg = New-Object System.Windows.Forms.OpenFileDialog
    $dlg.Title = "Wybierz pliki instalatorów"
    $dlg.Multiselect = $true
    $dlg.Filter = "Instalatory (*.exe;*.msi)|*.exe;*.msi|Wszystkie pliki (*.*)|*.*"
    if ($dlg.ShowDialog() -eq 'OK') { Add-DroppedPaths $dlg.FileNames }
})
$btnUsb.Add_Click({ Find-RemovableInstallers })
$btnHash.Add_Click({ Save-Hashes })

# Przeciaganie plikow/folderow na okno
$onDragEnter = {
    param($sender, $e)
    if (-not $script:Running -and $e.Data.GetDataPresent([System.Windows.Forms.DataFormats]::FileDrop)) { $e.Effect = 'Copy' }
    else { $e.Effect = 'None' }
}
$onDragDrop = {
    param($sender, $e)
    if ($script:Running) { return }
    Add-DroppedPaths ([string[]]$e.Data.GetData([System.Windows.Forms.DataFormats]::FileDrop))
}
foreach ($c in @($form, $tabApps, $lvApps)) {
    $c.AllowDrop = $true
    $c.Add_DragEnter($onDragEnter)
    $c.Add_DragDrop($onDragDrop)
}

$tabs.Add_SelectedIndexChanged({
    if ($script:Running) { return }
    if ($tabs.SelectedTab -eq $tabUnin -and -not $script:UninLoaded) { Update-UninstallList }
    if ($tabs.SelectedTab -eq $tabAuto -and -not $script:AutoLoaded) { Update-AutostartList }
})

$lvUnin.Add_ItemChecked({
    param($sender, $e)
    if ($script:UninFilling) { return }
    $k = $e.Item.Name
    if ($e.Item.Checked) { $script:UninSel[$k] = $true } else { $script:UninSel.Remove($k) }
})
$txtUninFilter.Add_TextChanged({ if ($script:UninLoaded) { Update-UninstallView } })
$chkUninAll.Add_CheckedChanged({ if ($script:UninLoaded) { Update-UninstallList } })
$btnUninRefresh.Add_Click({ Update-UninstallList })
$btnUninNone.Add_Click({ $script:UninSel.Clear(); Update-UninstallView })
$btnUninJunk.Add_Click({
    if (-not $script:UninLoaded) { Update-UninstallList }
    foreach ($it in $script:UninstallCache) {
        $hit = $false
        if ($it.Kind -eq 'Store') {
            foreach ($pat in $script:JunkStore) { if ($it.Name -like $pat) { $hit = $true; break } }
        } elseif ($it.Name -match $script:JunkProgram) { $hit = $true }
        if ($hit -and -not $it.IsComponent) { $script:UninSel["$($it.Kind)|$($it.Name)|$($it.Version)"] = $true }
    }
    Update-UninstallView
})

$btnAutoRefresh.Add_Click({ Update-AutostartList })
$btnAutoJunk.Add_Click({
    if (-not $script:AutoLoaded) { Update-AutostartList }
    foreach ($item in $lvAuto.Items) {
        $a = $item.Tag
        if (("$($a.Name) $($a.Command)") -match '(?i)OneDrive|Teams|Spotify|Skype|Discord|Steam|EpicGamesLauncher|Dropbox|Adobe.*(ARM|Updater|AAM)|MicrosoftEdgeAutoLaunch|Cortana|YourPhone|Phone ?Link') { $item.Checked = $true }
    }
})

$btnReady.Add_Click({ Invoke-Readiness })
$btnRun.Add_Click({ Start-Setup })
$btnCancel.Add_Click({
    $script:Cancel = $true
    $btnCancel.Enabled = $false
    Write-Log "Przerwanie - kończę bieżący krok i zatrzymuję..." "SKIP"
})
$btnLogs.Add_Click({
    if (-not (Test-Path $LogDir)) { New-Item -ItemType Directory -Path $LogDir -Force | Out-Null }
    Start-Process explorer.exe -ArgumentList "`"$LogDir`""
})
$btnClose.Add_Click({ $form.Close() })

$form.Add_FormClosing({
    param($sender, $e)
    if ($script:Running) {
        $e.Cancel = $true
        [void](Show-Msg "Trwa przygotowanie komputera. Poczekaj na koniec lub kliknij Przerwij." "Prepare Workstation" "OK" "Warning")
    }
})

$form.Add_Shown({
    if (-not (Test-Path $txtPath.Text)) {
        Write-Log "Folder instalatorów nie istnieje: $($txtPath.Text)" "SKIP"
    }
    Update-AppList $true
    Enable-ElevatedDrop
    if ($Resume) { Invoke-Resume }
})

try {
    [void]$form.ShowDialog()
} catch {
    [void](Show-Msg "Błąd krytyczny:`n$($_.Exception.Message)" "Prepare Workstation" "OK" "Error")
}
