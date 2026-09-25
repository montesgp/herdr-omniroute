param([switch]$Once)
$ErrorActionPreference = "SilentlyContinue"

$port = 20128
$node = "C:\Users\patri\scoop\persist\fnm\node-versions\v22.22.3\installation\node.exe"
$entry = "C:\Users\patri\node_modules\omniroute\bin\omniroute.mjs"
$refreshSec = 8

function Strip-Ansi([string]$s) {
  if ($null -eq $s) { return "" }
  return ($s -replace "\x1b\[[0-9;]*m", "" -replace "\x1b\[[0-9;]*[A-Za-z]", "")
}

function Is-Up {
  (netstat -an | Select-String -Pattern ":$port\s+.*LISTENING").Count -gt 0
}

function Show-Combos {
  $lines = & $node $entry combo list --no-color 2>$null | ForEach-Object { Strip-Ansi $_ }
  if (-not $lines) {
    Write-Host "  (CLI de OmniRoute no disponible)" -ForegroundColor Gray
    return
  }
  foreach ($l in $lines) {
    if ($l -match "○|●|\[priority\]|\[weighted\]|\[static\]|enabled|disabled") {
      Write-Host ("  " + $l.Trim())
    }
  }
}

function Render {
  Clear-Host
  Write-Host ""
  Write-Host "  OmniRoute Gateway" -ForegroundColor Cyan
  Write-Host "  =================" -ForegroundColor Cyan
  if (Is-Up) {
    Write-Host "  Estado: UP   (localhost:$port)" -ForegroundColor Green
  } else {
    Write-Host "  Estado: DOWN (localhost:$port)" -ForegroundColor Red
    Write-Host "  Arranca con: prefix+o  o  herdr plugin action invoke herdr.omniroute.start" -ForegroundColor Yellow
  }
  Write-Host "  URL:    http://localhost:$port" -ForegroundColor Gray
  Write-Host ""
  Write-Host "  Combos:" -ForegroundColor Cyan
  Show-Combos
  Write-Host ""
  Write-Host ("  Actualizado: " + (Get-Date -Format "HH:mm:ss") + "  (refresh cada ${refreshSec}s)" ) -ForegroundColor DarkGray
}

if ($Once) {
  Render
  exit 0
}

while ($true) {
  Render
  Start-Sleep -Seconds $refreshSec
}