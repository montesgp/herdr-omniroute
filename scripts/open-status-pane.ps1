$ErrorActionPreference = "Stop"
$herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }

# Idempotente: si el pane de status ya esta abierto en esta sesion, no abrir otro.
$existing = (& $herdr pane list 2>$null | Out-String)
if ($existing -match "herdr\.omniroute|OmniRoute Gateway") {
  Write-Output "pane already open"
  exit 0
}

& $herdr plugin pane open --plugin herdr.omniroute --entrypoint status 2>&1 | Out-String | Write-Output
exit $LASTEXITCODE