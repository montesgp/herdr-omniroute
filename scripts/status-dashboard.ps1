param([switch]$Once, [int]$RefreshSec = 8)
$ErrorActionPreference = "SilentlyContinue"

$port = 20128
$node = "C:\Users\patri\scoop\persist\fnm\node-versions\v22.22.3\installation\node.exe"
$entry = "C:\Users\patri\node_modules\omniroute\bin\omniroute.mjs"
$ESC = [char]27

function Strip-Ansi([string]$s) {
  if ($null -eq $s) { return "" }
  return ($s -replace "$ESC\[[0-9;]*m", "" -replace "$ESC\[[0-9;]*[A-Za-z]", "")
}

function Is-Up {
  (netstat -an | Select-String -Pattern ":$port\s+.*LISTENING").Count -gt 0
}

function Get-Combos {
  $lines = & $node $entry combo list --no-color 2>$null | ForEach-Object { Strip-Ansi $_ }
  if (-not $lines) { return @("  (CLI de OmniRoute no disponible)") }
  $out = @()
  foreach ($l in $lines) {
    if ($l -match "○|●|\[priority\]|\[weighted\]|\[static\]|enabled|disabled") {
      $out += ("  " + $l.Trim())
    }
  }
  if ($out.Count -eq 0) { $out += "  (sin combos)" }
  return $out
}

function Home {
  # Volver arriba del buffer sin borrarlo: sobrescribimos en el mismo sitio.
  try { [Console]::SetCursorPosition(0, 0) } catch { Write-Host "$ESC[H" -NoNewline }
}

function Render {
  Home
  $up = Is-Up

  Write-Host ""
  Write-Host ("  OmniRoute Gateway" + $ESC + "[K")
  Write-Host ("  =================" + $ESC + "[K")
  if ($up) {
    Write-Host ("  Estado: UP   (localhost:$port)  " + $ESC + "[K") -ForegroundColor Green
    Write-Host ("  " + $ESC + "[K")   # línea reservada (evita restos al pasar de DOWN a UP)
  } else {
    Write-Host ("  Estado: DOWN (localhost:$port)  " + $ESC + "[K") -ForegroundColor Red
    Write-Host ("  Arranca con: prefix+o  o  herdr plugin action invoke herdr.omniroute.start" + $ESC + "[K") -ForegroundColor Yellow
  }
  Write-Host ("  URL:    http://localhost:$port" + $ESC + "[K")

  Write-Host ""
  Write-Host ("  Combos:" + $ESC + "[K")
  foreach ($c in (Get-Combos)) { Write-Host ($c + $ESC + "[K") }
  Write-Host ("  " + $ESC + "[K")
  Write-Host ("  Actualizado: " + (Get-Date -Format "HH:mm:ss") + "  (refresh cada ${RefreshSec}s)" + $ESC + "[K")
  Write-Host ("  " + $ESC + "[K")   # línea reservada (restos de transiciones)
}

if ($Once) {
  Render
  exit 0
}

while ($true) {
  Render
  Start-Sleep -Seconds $RefreshSec
}