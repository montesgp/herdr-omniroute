$ErrorActionPreference = "SilentlyContinue"
$herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }
$label = "OmniRoute Gateway"

# Enumerar workspaces y panes de la sesión (JSON). Si algo falla, se abre sin target (workspace activo).
$ws = $null
$panes = $null
try {
  $ws = (& $herdr workspace list 2>$null | Out-String | ConvertFrom-Json)
  $panes = (& $herdr pane list 2>$null | Out-String | ConvertFrom-Json)
} catch { }

$workspaces = @()
if ($ws -and $ws.result.workspaces) { $workspaces = @($ws.result.workspaces) }

if ($workspaces.Count -eq 0) {
  # Fallback: abrir en el workspace activo como antes
  & $herdr plugin pane open --plugin herdr.omniroute --entrypoint status 2>&1 | Out-String | Write-Output
  exit $LASTEXITCODE
}

$knownPanes = @()
if ($panes -and $panes.result.panes) { $knownPanes = @($panes.result.panes) }

$opened = 0
foreach ($w in $workspaces) {
  $wsId = $w.workspace_id
  $already = @($knownPanes | Where-Object { $_.workspace_id -eq $wsId -and $_.label -eq $label }).Count -gt 0
  if ($already) {
    Write-Output ("pane already open in " + $wsId)
    continue
  }
  & $herdr plugin pane open --plugin herdr.omniroute --entrypoint status --workspace $wsId --no-focus 2>&1 | Out-String | Write-Output
  $opened++
}
Write-Output ("open-status-pane: $opened opened, " + ($workspaces.Count - $opened) + " already open")
exit 0