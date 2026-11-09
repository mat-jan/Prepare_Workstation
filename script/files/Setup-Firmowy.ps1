# ============================================================
#  PREPARE WORKSTATION - kreator przygotowania komputera firmowego (GUI)
#  Uruchom przez: Start-Firmowy.bat (jako Administrator)
#  Lista aplikacji: apps.json (obok tego pliku)
# ============================================================
[CmdletBinding()]
param(
    [string]$InstallerPath = "C:\instalki"   # folder z instalatorami (lokalny lub UNC)
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
            Set-Outcome $name "OK" "instalator zamknięty (kod: $code)"
            return
        }
        default { Set-Outcome $name "ERR" "nieznany typ instalatora: $($App.type)"; return }
    }

    if ($code -eq 0 -or $code -eq 3010 -or $code -eq 1641) {
        if ($code -ne 0) { $script:RebootNeeded = $true }
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

    $text = "Gotowe.`n`nOK: $ok`nPominięte: $skip`nBłędy: $err"
    if ($dry -gt 0) { $text = "Tryb testowy - nic nie zostało zmienione.`n`nKroków w symulacji: $dry" }
    $icon = if ($err -gt 0) { "Warning" } else { "Information" }

    if ($script:RebootNeeded -and -not $script:DryRun) {
        $text += "`n`nWymagany restart komputera. Uruchomić ponownie teraz?"
        $r = Show-Msg $text "Prepare Workstation - koniec" "YesNo" $icon
        if ($r -eq 'Yes') { Restart-Computer -Force }
    } else {
        [void](Show-Msg $text "Prepare Workstation - koniec" "OK" $icon)
    }
}

function Start-Setup {
    $name = $txtName.Text.Trim()
    $renameWanted = ($name -ne "" -and $name -ne $env:COMPUTERNAME)
    if ($renameWanted -and $name -notmatch '^(?!\d+$)[a-zA-Z0-9\-]{1,15}$') {
        [void](Show-Msg "Nieprawidłowa nazwa komputera (litery, cyfry, myślniki; max 15 znaków; nie same cyfry)." "Błąd" "OK" "Warning")
        return
    }

    $o = @{}
    $o.InstallerPath = $txtPath.Text.Trim()
    $o.NewName       = if ($renameWanted) { $name } else { $null }
    $o.PowerPlan     = $chkPlan.Checked
    $o.PowerNever    = $chkNever.Checked
    $o.Hibernate     = $chkHib.Checked
    $o.ScreenSaver   = $chkSaver.Checked
    $o.SkipInstalled = $chkSkipInst.Checked
    $o.EsetKey       = $txtEset.Text.Trim()
    $o.TimeZone      = [string]$cmbTz.SelectedItem
    $script:Opts     = $o
    $script:DryRun   = $chkDry.Checked

    $apps = @($lvApps.CheckedItems | ForEach-Object { $_.Tag })

    # --- plan ---
    $plan = @()
    if ($chkRestore.Checked) { $plan += [pscustomobject]@{ Name = "Punkt przywracania systemu"; Fn = "Step-RestorePoint"; Arg = $null } }
    if ($renameWanted)       { $plan += [pscustomobject]@{ Name = "Nazwa komputera: $name";     Fn = "Step-Rename";       Arg = $null } }
    if ($o.PowerPlan -or $o.PowerNever -or $o.Hibernate -or $o.ScreenSaver) {
                               $plan += [pscustomobject]@{ Name = "Ustawienia zasilania";       Fn = "Step-Power";        Arg = $null } }
    if ($chkMcAfee.Checked)  { $plan += [pscustomobject]@{ Name = "Usuwanie McAfee";            Fn = "Step-McAfee";       Arg = $null } }
    if ($chkOffice.Checked)  { $plan += [pscustomobject]@{ Name = "Usuwanie starego Office";    Fn = "Step-Office";       Arg = $null } }
    foreach ($a in $apps)    { $plan += [pscustomobject]@{ Name = "Instalacja: $($a.name)";     Fn = "Step-App";          Arg = $a } }
    if ($chkTz.Checked)      { $plan += [pscustomobject]@{ Name = "Strefa czasowa";             Fn = "Step-TimeZone";     Arg = $null } }
    if ($chkExt.Checked)     { $plan += [pscustomobject]@{ Name = "Eksplorator plików";         Fn = "Step-FileExt";      Arg = $null } }
    if ($chkThisPC.Checked)  { $plan += [pscustomobject]@{ Name = "Ikona Ten komputer";         Fn = "Step-ThisPC";       Arg = $null } }
    if ($chkPolicy.Checked)  { $plan += [pscustomobject]@{ Name = "Przywrócenie ExecutionPolicy"; Fn = "Step-Policy";     Arg = $null } }
    if ($chkWU.Checked)      { $plan += [pscustomobject]@{ Name = "Windows Update";             Fn = "Step-WindowsUpdate"; Arg = $null } }

    if ($plan.Count -eq 0) {
        [void](Show-Msg "Nic nie zaznaczono do wykonania." "Prepare Workstation" "OK" "Information")
        return
    }

    $mode = if ($script:DryRun) { "TRYB TESTOWY (symulacja)" } else { "Zmiany zostaną wprowadzone w systemie" }
    $r = Show-Msg ("$mode`n`nKroki ($($plan.Count)):`n- " + (($plan | ForEach-Object { $_.Name }) -join "`n- ") + "`n`nKontynuować?") `
                  "Potwierdzenie" "YesNo" "Question"
    if ($r -ne 'Yes') { return }

    # --- wykonanie ---
    $script:Results.Clear()
    $script:Cancel = $false
    $script:RebootNeeded = $false
    $script:Running = $true
    $script:LogBox.Clear()
    $tabs.SelectedTab = $tabLog
    foreach ($c in $busyControls) { $c.Enabled = $false }
    $btnCancel.Enabled = $true
    $progress.Maximum = $plan.Count
    $progress.Value = 0

    Write-Log "Prepare Workstation $AppVersion - start: $env:COMPUTERNAME, Windows $([Environment]::OSVersion.Version), użytkownik $env:USERNAME" "INFO"
    if ($script:DryRun) { Write-Log "TRYB TESTOWY - żadne zmiany nie są wprowadzane" "DRY" }

    $i = 0
    foreach ($s in $plan) {
        if ($script:Cancel) { Set-Outcome "Przerwano" "SKIP" "pominięto pozostałe kroki ($($plan.Count - $i))"; break }
        $lblStatus.Text = "Krok $($i + 1)/$($plan.Count): $($s.Name)"
        Write-Log $s.Name "STEP"
        try {
            if ($s.Arg) { & $s.Fn $s.Arg } else { & $s.Fn }
        } catch {
            Set-Outcome $s.Name "ERR" $_.Exception.Message
        }
        $i++
        $progress.Value = $i
    }

    $lblStatus.Text = "Zakończono."
    $script:Running = $false
    foreach ($c in $busyControls) { $c.Enabled = $true }
    $btnCancel.Enabled = $false
    Show-Summary
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
$tabLog   = New-Object System.Windows.Forms.TabPage "Przebieg"
$tabSet.AutoScroll = $true
[void]$tabs.TabPages.Add($tabSet)
[void]$tabs.TabPages.Add($tabApps)
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
$chkThisPC = New-Check "Ikona „Ten komputer” na pulpicie"                   12 98  416 $gExtra
$chkTz.Checked = $true

$gOpt = New-Group "Opcje instalacji" 444 168 440 100 $tabSet
$chkSkipInst = New-Check "Pomijaj aplikacje, które są już zainstalowane" 12 22 416 $gOpt
[void](New-Label "Klucz ESET (opcjonalnie):" 12 52 150 20 $gOpt)
$txtEset = New-Ctl System.Windows.Forms.TextBox "" 166 49 262 23 $gOpt
$txtEset.UseSystemPasswordChar = $true
$lblEsetHint = New-Label "Klucz nie jest zapisywany do logu ani na dysku." 12 76 416 18 $gOpt
$lblEsetHint.ForeColor = [System.Drawing.Color]::Gray

$gEnd = New-Group "Na koniec" 444 276 440 80 $tabSet
$chkPolicy = New-Check "Przywróć ExecutionPolicy (Restricted)" 12 22 416 $gEnd
$chkWU     = New-Check "Otwórz Windows Update"                12 46 416 $gEnd
$chkWU.Checked = $false

# --- zakladka: Aplikacje ---
$lvApps = New-Object System.Windows.Forms.ListView
$lvApps.Dock = "Fill"
$lvApps.View = "Details"
$lvApps.CheckBoxes = $true
$lvApps.FullRowSelect = $true
$lvApps.GridLines = $true
[void]$lvApps.Columns.Add("Aplikacja", 260)
[void]$lvApps.Columns.Add("Plik instalatora", 300)
[void]$lvApps.Columns.Add("Plik w folderze", 110)
[void]$lvApps.Columns.Add("Zainstalowana", 100)
[void]$lvApps.Columns.Add("Tryb", 100)
$tabApps.Controls.Add($lvApps)

$appsBar = New-Object System.Windows.Forms.Panel
$appsBar.Dock = "Bottom"
$appsBar.Height = 44
$tabApps.Controls.Add($appsBar)
$btnAll     = New-Ctl System.Windows.Forms.Button "Zaznacz wszystkie" 8 8 130 28 $appsBar
$btnNone    = New-Ctl System.Windows.Forms.Button "Odznacz wszystkie" 146 8 130 28 $appsBar
$btnRefresh = New-Ctl System.Windows.Forms.Button "Odśwież listę"     284 8 110 28 $appsBar
$btnEdit    = New-Ctl System.Windows.Forms.Button "Edytuj apps.json"  402 8 120 28 $appsBar
$btnAddFiles = New-Ctl System.Windows.Forms.Button "Dodaj pliki..."    534 8 110 28 $appsBar
$btnUsb      = New-Ctl System.Windows.Forms.Button "Znajdź na pendrive" 652 8 140 28 $appsBar

$lblDrop = New-Object System.Windows.Forms.Label
$lblDrop.Dock = "Top"
$lblDrop.Height = 26
$lblDrop.TextAlign = "MiddleLeft"
$lblDrop.ForeColor = [System.Drawing.Color]::DimGray
$lblDrop.Text = "  Przeciągnij na okno pliki instalatorów lub cały folder z pendrive'a - program rozpozna je po nazwie i użyje bezpośrednio z pendrive'a."
$tabApps.Controls.Add($lblDrop)

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
$chkDry    = New-Check "Tryb testowy (nic nie zmieniaj)" 384 53 240 $bottom $false
$btnClose  = New-Ctl System.Windows.Forms.Button "Zamknij" 808 48 100 30 $bottom
$btnClose.Anchor = "Top, Right"

# kontrolki blokowane na czas pracy (zakladka "Przebieg", Przerwij i Folder logow zostaja aktywne)
$busyControls = @($tabSet, $lvApps, $appsBar, $btnRun, $chkDry)

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
        [void](Show-Msg "Nie rozpoznano żadnego instalatora.`nProgram dopasowuje pliki po nazwie podanej w apps.json (kolumna „Plik instalatora”)." "Prepare Workstation" "OK" "Information")
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
        [void](Show-Msg "Nie wykryto pendrive'a (dysku wymiennego).`nPodłącz go albo użyj przycisku „Dodaj pliki...”." "Prepare Workstation" "OK" "Information")
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
})

try {
    [void]$form.ShowDialog()
} catch {
    [void](Show-Msg "Błąd krytyczny:`n$($_.Exception.Message)" "Prepare Workstation" "OK" "Error")
}
