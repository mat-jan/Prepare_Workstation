# ============================================================
#  Buduje paczki dystrybucyjne do folderu dist\
#
#    PrepareWorkstation-<wersja>.zip       - wersja skryptowa (Start-Firmowy.bat + files\)
#    PrepareWorkstation-exe-<wersja>.zip   - Prepare-Workstation.exe (tylko z -WithExe, Windows)
#    SHA256SUMS.txt                        - sumy kontrolne
#
#  Uzycie:
#    pwsh -File build\Build-Package.ps1 -Version 1.0.0
#    powershell -File build\Build-Package.ps1 -Version 1.0.0 -WithExe
# ============================================================
[CmdletBinding()]
param(
    [string]$Version = "dev",
    [switch]$WithExe
)

$ErrorActionPreference = "Stop"
$Version = $Version.TrimStart('v')

$Root    = Split-Path -Parent $PSScriptRoot
$Dist    = Join-Path $Root "dist"
$Stage   = Join-Path $Dist "stage"
$Utf8Bom = New-Object System.Text.UTF8Encoding($true)

function Write-Step { param($m) Write-Host ">>> $m" -ForegroundColor Cyan }

if (Test-Path $Dist) { Remove-Item $Dist -Recurse -Force }
New-Item -ItemType Directory -Path $Dist, $Stage | Out-Null

# --- 1. katalog zrodlowy -> stage (z wpisana wersja) ---
Write-Step "Przygotowanie plikow (wersja $Version)"
Copy-Item (Join-Path $Root "script\*") $Stage -Recurse

$ps1 = Join-Path $Stage "files\Setup-Firmowy.ps1"
$src = [System.IO.File]::ReadAllText($ps1)
$new = [regex]::Replace($src, '(?m)^\$AppVersion = "dev"', "`$AppVersion = `"$Version`"")
if ($new -eq $src -and $Version -ne "dev") { throw "Nie znaleziono linii `$AppVersion w Setup-Firmowy.ps1" }
[System.IO.File]::WriteAllText($ps1, $new, $Utf8Bom)

foreach ($f in "README.md", "README.en.md", "LICENSE") { Copy-Item (Join-Path $Root $f) $Stage }

# --- 2. szablon folderu z instalatorami (generowany z apps.json) ---
Write-Step "Generowanie szablonu folderu instalki"
$apps = Get-Content (Join-Path $Stage "files\apps.json") -Raw -Encoding UTF8 | ConvertFrom-Json
$tpl  = Join-Path $Stage "instalki-template"
New-Item -ItemType Directory -Path $tpl | Out-Null

$lines = @(
    "FOLDER Z INSTALATORAMI",
    "======================",
    "Skopiuj ten folder jako C:\instalki (albo wskaz inny w oknie programu)",
    "i wgraj do niego ponizsze pliki. Nazwy musza zgadzac sie z apps.json.",
    ""
)
foreach ($a in $apps) {
    $mode = switch ($a.type) { 'msi' { 'cicha (MSI)' } 'manual' { 'reczna' } default { 'cicha' } }
    $opt  = if ($a.default) { "" } else { "  [opcjonalna]" }
    $lines += "{0}{1}" -f $a.name, $opt
    $lines += "    plik: {0}   instalacja: {1}" -f $a.file, $mode
    if ($a.url) { $lines += "    pobierz: $($a.url)" }
    $lines += ""
}
[System.IO.File]::WriteAllText((Join-Path $tpl "WGRAJ-TUTAJ-INSTALATORY.txt"), ($lines -join "`r`n"), $Utf8Bom)

# --- 3. ZIP ze skryptami ---
Write-Step "ZIP: wersja skryptowa"
$zipScript = Join-Path $Dist "PrepareWorkstation-$Version.zip"
Compress-Archive -Path (Join-Path $Stage "*") -DestinationPath $zipScript -CompressionLevel Optimal

# --- 4. EXE (opcjonalnie, tylko Windows) ---
if ($WithExe) {
    if ($PSVersionTable.Platform -and $PSVersionTable.Platform -ne 'Win32NT') { throw "Budowanie .exe wymaga Windows." }
    Write-Step "Budowanie .exe (ps2exe)"
    if (-not (Get-Command Invoke-ps2exe -ErrorAction SilentlyContinue)) {
        Install-Module ps2exe -RequiredVersion 1.0.13 -Scope CurrentUser -Force
    }
    Import-Module ps2exe

    $exeStage = Join-Path $Dist "stage-exe"
    New-Item -ItemType Directory -Path $exeStage | Out-Null
    $numeric = if ($Version -match '^(\d+)\.(\d+)\.(\d+)') { "$($Matches[1]).$($Matches[2]).$($Matches[3]).0" } else { "0.0.0.0" }

    Invoke-ps2exe -inputFile $ps1 -outputFile (Join-Path $exeStage "Prepare-Workstation.exe") `
        -noConsole -requireAdmin -STA -title "Prepare Workstation" `
        -product "Prepare Workstation" -version $numeric

    Copy-Item (Join-Path $Stage "files\apps.json") $exeStage
    Copy-Item $tpl (Join-Path $exeStage "instalki-template") -Recurse
    foreach ($f in "README.md", "README.en.md", "LICENSE") { Copy-Item (Join-Path $Root $f) $exeStage }

    $zipExe = Join-Path $Dist "PrepareWorkstation-exe-$Version.zip"
    Compress-Archive -Path (Join-Path $exeStage "*") -DestinationPath $zipExe -CompressionLevel Optimal
}

# --- 5. sumy kontrolne ---
Write-Step "Sumy kontrolne"
Remove-Item $Stage, (Join-Path $Dist "stage-exe") -Recurse -Force -ErrorAction SilentlyContinue
$sums = Get-ChildItem $Dist -Filter *.zip | ForEach-Object {
    "{0}  {1}" -f (Get-FileHash $_.FullName -Algorithm SHA256).Hash.ToLower(), $_.Name
}
[System.IO.File]::WriteAllText((Join-Path $Dist "SHA256SUMS.txt"), (($sums -join "`n") + "`n"))

Write-Host ""
Write-Host "Gotowe. Zawartosc dist\:" -ForegroundColor Green
Get-ChildItem $Dist | ForEach-Object { "  {0}  ({1:N0} B)" -f $_.Name, $_.Length }
