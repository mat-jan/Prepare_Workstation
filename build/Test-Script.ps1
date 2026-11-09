# ============================================================
#  Statyczne sprawdzenie skryptow PowerShell (uruchamiane w CI)
#  Lapie bledy, ktorych sam parser skladni nie zglasza:
#   1) typograficzne cudzyslowy (U+201E/201C/201D...) - PowerShell traktuje je jak "
#      i rozbijaja napis na kilka argumentow
#   2) zle argumenty funkcji budujacych okno (tekst tam, gdzie ma byc liczba)
# ============================================================
param([string[]]$Files = @("$PSScriptRoot\..\script\files\Setup-Firmowy.ps1", "$PSScriptRoot\Build-Package.ps1"))

$bad = 0
$smart = [regex]'[“”„‟‘’‚‛]'
$intPos = @{ 'New-Ctl' = 2..5; 'New-Group' = 1..4; 'New-Check' = 1..3; 'New-Label' = 1..4 }
$maxArg = @{ 'New-Ctl' = 7; 'New-Group' = 6; 'New-Check' = 6; 'New-Label' = 6 }

foreach ($file in $Files) {
    $name = Split-Path $file -Leaf
    $lineNo = 0
    foreach ($line in (Get-Content $file -Encoding UTF8)) {
        $lineNo++
        if ($smart.IsMatch($line)) { Write-Host "BLAD ${name}:${lineNo}: typograficzny cudzyslow w kodzie: $($line.Trim())"; $bad++ }
    }

    $tokens = $null; $errors = $null
    $ast = [System.Management.Automation.Language.Parser]::ParseFile((Resolve-Path $file), [ref]$tokens, [ref]$errors)
    foreach ($e in $errors) { Write-Host "BLAD ${name}:$($e.Extent.StartLineNumber): $($e.Message)"; $bad++ }

    $cmds = $ast.FindAll({ param($n) $n -is [System.Management.Automation.Language.CommandAst] }, $true)
    foreach ($c in $cmds) {
        $cn = $c.GetCommandName()
        if (-not ($cn -and $intPos.ContainsKey($cn))) { continue }
        $elems = @($c.CommandElements | Select-Object -Skip 1)
        foreach ($i in $intPos[$cn]) {
            if ($i -lt $elems.Count -and ($elems[$i] -is [System.Management.Automation.Language.StringConstantExpressionAst] -or
                                          $elems[$i] -is [System.Management.Automation.Language.ExpandableStringExpressionAst])) {
                Write-Host "BLAD ${name}:$($c.Extent.StartLineNumber): $cn - argument #$i to tekst ($($elems[$i].Extent.Text)), oczekiwano liczby"
                $bad++
            }
        }
        if ($elems.Count -gt $maxArg[$cn]) {
            Write-Host "BLAD ${name}:$($c.Extent.StartLineNumber): $cn ma $($elems.Count) argumentow (max $($maxArg[$cn]))"
            $bad++
        }
    }
    Write-Host "Sprawdzono: $name"
}

if ($bad -gt 0) { Write-Host "Problemow: $bad"; exit 1 }
Write-Host "OK - brak problemow"
