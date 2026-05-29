# NRL Supercoach Draft Board - Data Updater
# Fetches player ratings from nrlsupercoachstats.com/draftgrid.php
# Run this script before your draft to get current data.
# Output: players-data.js (auto-loaded by supercoach-draft.html)

$ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
$OutputFile = Join-Path $ScriptDir "players-data.js"

# Position columns in the draftgrid table (in order they appear left to right)
$POSITIONS = @("HOK", "FRF", "2RF", "HFB", "5/8", "CTW", "FLB")

Write-Host ""
Write-Host "  NRL Supercoach Data Updater" -ForegroundColor Cyan
Write-Host "  =============================" -ForegroundColor Cyan
Write-Host ""

# ─── PARSE ONE DRAFTGRID PAGE ──────────────────────────────────────────────────
function Get-DraftGridPlayers([int]$year) {
    Write-Host "  Fetching $year data ... " -NoNewline
    try {
        $resp = Invoke-WebRequest -Uri "https://www.nrlsupercoachstats.com/draftgrid.php?year=$year" `
                                  -UseBasicParsing -TimeoutSec 30
        $html = $resp.Content
    } catch {
        Write-Host "FAILED ($_)" -ForegroundColor Red
        return @{}
    }

    $players = @{}

    $trMatches   = [regex]::Matches($html, '<tr[^>]*>(.*?)</tr>', 'Singleline')
    $tdPattern   = [regex]'<td[^>]*>(.*?)</td>'
    $linePattern = [regex]'([A-Z][a-zA-Z''\-]+,\s+[A-Za-z0-9''\-\s]+?)\s+(?:(HOK|FRF|2RF|HFB|5/8|CTW|FLB)\s+)?(\d{2,3}\.\d{1,2})'

    foreach ($tr in $trMatches) {
        $cells = $tdPattern.Matches($tr.Groups[1].Value)
        if ($cells.Count -lt 3) { continue }

        for ($i = 1; $i -lt $cells.Count; $i++) {
            $posIdx = $i - 1
            if ($posIdx -ge $POSITIONS.Count) { break }
            $colPos = $POSITIONS[$posIdx]

            $cellText = $cells[$i].Groups[1].Value
            $cellText = $cellText -replace '&amp;',  '&'
            $cellText = $cellText -replace '&lt;',   '<'
            $cellText = $cellText -replace '&gt;',   '>'
            $cellText = $cellText -replace '&#39;',  "'"
            $cellText = $cellText -replace '<[^>]+>', ' '

            foreach ($pm in $linePattern.Matches($cellText)) {
                $rawName = $pm.Groups[1].Value.Trim()
                $altPos  = $pm.Groups[2].Value.Trim()
                $rating  = [double]$pm.Groups[3].Value

                if (-not $players.Contains($rawName)) {
                    $posArr = [System.Collections.Generic.List[string]]::new()
                    $posArr.Add($colPos)
                    if ($altPos -and $altPos -ne $colPos) { $posArr.Add($altPos) }
                    $players[$rawName] = @{ positions = $posArr; rating = $rating }
                } elseif ($altPos -and $players.Contains($rawName) -and -not ($players[$rawName].positions -contains $altPos)) {
                    $players[$rawName].positions.Add($altPos)
                }
            }
        }
    }

    Write-Host "$($players.Count) players" -ForegroundColor Green
    return $players
}

# ─── FETCH TEAM DATA FROM PLAYERLIST ──────────────────────────────────────────
function Get-PlayerTeams {
    Write-Host "  Fetching team data   ... " -NoNewline
    try {
        $resp = Invoke-WebRequest -Uri "https://www.nrlsupercoachstats.com/playerlist.php" `
                                  -UseBasicParsing -TimeoutSec 30
        $html = $resp.Content
    } catch {
        Write-Host "FAILED (teams will show as unknown)" -ForegroundColor Yellow
        return @{}
    }

    $playerInfo = @{}   # key = rawName, value = @{ team; price }
    $trMatches = [regex]::Matches($html, '<tr[^>]*>(.*?)</tr>', 'Singleline')
    $tdPattern = [regex]'<td[^>]*>(.*?)</td>'

    foreach ($tr in $trMatches) {
        $cells = $tdPattern.Matches($tr.Groups[1].Value)
        if ($cells.Count -lt 5) { continue }
        $name  = ($cells[0].Groups[1].Value -replace '<[^>]+>', '' -replace '&amp;','&' -replace '&#39;',"'").Trim()
        $team  = ($cells[1].Groups[1].Value -replace '<[^>]+>', '').Trim().ToUpper()
        $price = ($cells[4].Groups[1].Value -replace '<[^>]+>', '' -replace '[^0-9]','').Trim()
        if ($name -match '^[A-Z][a-z]' -and $team.Length -ge 2 -and $team.Length -le 5) {
            $playerInfo[$name] = @{ team = $team; price = if ($price) { [int]$price } else { 0 } }
        }
    }

    Write-Host "$($playerInfo.Count) players" -ForegroundColor Green
    return $playerInfo
}

# ─── FETCH DATA ────────────────────────────────────────────────────────────────
# draftgrid?year=N contains season N-1 data (it is the pre-season draft guide for year N)
# So year=2026 → 2025 season data, year=2025 → 2024, year=2024 → 2023
$data2025 = Get-DraftGridPlayers 2026
$data2024 = Get-DraftGridPlayers 2025
$data2023 = Get-DraftGridPlayers 2024
$teams    = Get-PlayerTeams   # returns @{ rawName = @{ team; price } }

Write-Host ""

# ─── MERGE ACROSS YEARS ────────────────────────────────────────────────────────
$allNames = @($data2025.Keys) + @($data2024.Keys) + @($data2023.Keys) | Sort-Object -Unique

$playerLines = [System.Collections.Generic.List[string]]::new()

foreach ($rawName in $allNames) {
    $p25 = if ($data2025.ContainsKey($rawName)) { $data2025[$rawName] } else { $null }
    $p24 = if ($data2024.ContainsKey($rawName)) { $data2024[$rawName] } else { $null }
    $p23 = if ($data2023.ContainsKey($rawName)) { $data2023[$rawName] } else { $null }

    $posSource = if ($p25) { $p25 } elseif ($p24) { $p24 } else { $p23 }
    $posArr    = $posSource.positions

    $inv = [System.Globalization.CultureInfo]::InvariantCulture
    $r25 = if ($p25) { $p25.rating.ToString("F2", $inv) } else { "null" }
    $r24 = if ($p24) { $p24.rating.ToString("F2", $inv) } else { "null" }
    $r23 = if ($p23) { $p23.rating.ToString("F2", $inv) } else { "null" }

    # Convert "Surname, Firstname" -> "Firstname Surname"
    if ($rawName -match '^([^,]+),\s*(.+)$') {
        $display = "$($Matches[2].Trim()) $($Matches[1].Trim())"
    } else {
        $display = $rawName
    }
    $display = $display -replace "'", "'"

    $info  = if ($teams.ContainsKey($rawName)) { $teams[$rawName] } else { $null }
    $team  = if ($info) { $info.team } else { "?" }
    $price = if ($info -and $info.price -gt 0) { $info.price.ToString() } else { "null" }

    $posQuoted = ($posArr | ForEach-Object { '"' + $_ + '"' }) -join ","

    $line = '    {"name":"' + $display + '","team":"' + $team + '","positions":[' + $posQuoted + '],"avg2025":' + $r25 + ',"avg2024":' + $r24 + ',"avgPrior":' + $r23 + ',"price":' + $price + '}'
    $playerLines.Add($line)
}

# ─── WRITE OUTPUT ──────────────────────────────────────────────────────────────
$generated  = Get-Date -Format "yyyy-MM-dd HH:mm"
$playerJson = $playerLines -join ",`r`n"

$header = "// Auto-generated by update-players.ps1 on $generated`r`n// Source: nrlsupercoachstats.com/draftgrid.php (year=2026→2025 data, year=2025→2024 data, year=2024→2023 data)`r`n// Re-run update-players.ps1 to refresh.`r`nwindow.PLAYER_DATA = {`r`n  generated: `"$generated`",`r`n  players: [`r`n"
$footer = "`r`n  ]`r`n};`r`n"

[System.IO.File]::WriteAllText($OutputFile, $header + $playerJson + $footer, [System.Text.Encoding]::UTF8)

Write-Host "  Written : $OutputFile" -ForegroundColor Green
Write-Host "  Players : $($playerLines.Count) total" -ForegroundColor Green
Write-Host ""
Write-Host "  Open supercoach-draft.html in your browser to see updated rankings." -ForegroundColor Cyan
Write-Host ""
