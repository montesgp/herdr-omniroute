<#
.SYNOPSIS
  Hub widget: OmniRoute gateway state, active combo and the configured combos.

.DESCRIPTION
  Three independent facts, each sourced from the cheapest honest place:

    Gateway UP/DOWN   netstat -an, filtered for a LISTENING socket on :20128, read
                      through the windowless helper. Same detection as
                      scripts\status-dashboard.ps1, so the dock and the popup can
                      never disagree.

    Active combo      GET /api/settings with the machine-derived CLI token
                      (HMAC-SHA256, key = MachineGuid, message =
                      "omniroute-cli-auth-v1", hex lowercase, header
                      x-omniroute-cli-token). This is NOT the gateway API key and
                      nothing here reads or writes a key: the derivation only needs
                      HKLM\SOFTWARE\Microsoft\Cryptography.
                      Measured on this install (2026-09-25): the endpoint answers
                      200 with the token, but it exposes no active-combo field
                      (only comboStrategy / comboConfigMode /
                      comboAutoPromoteEnabled / hideAutoCombos), and neither does
                      /api/combos. So the widget asks for the plausible field
                      names, falls back to what the SQLite reader can prove
                      (key_value settings/activeCombo), and otherwise prints
                      "sin datos". It never guesses.

    Combo list        scripts\lib\Get-OmniRouteCombos.ps1, the same read-only
                      SELECT the popup uses. Not duplicated here.

.NOTES
  The port check and the database read are independent, so they are started
  together and collected afterwards: the frame pays for the slower one instead of
  their sum. Every external call is bounded, and every failure renders as a line
  rather than an exception, because one dead source must not take the dock down.

  Dot-source it, do not run it:

    . (Join-Path $PSScriptRoot "omniroute.ps1")
#>

$script:OmniRoutePort = 20128
$script:OmniRouteNetstatTimeoutMs = 5000
$script:OmniRouteSettingsTimeoutSec = 5

<#
.SYNOPSIS
  Derives the gateway CLI token from this machine's MachineGuid.

.DESCRIPTION
  Mirrors the derivation the OmniRoute CLI uses for its own management calls:
  HMAC-SHA256 keyed with the machine GUID over the salt "omniroute-cli-auth-v1",
  rendered as lowercase hex. The order matters - key = machine id, message = salt -
  and swapping the two yields a 401.

.NOTES
  Returns "" when the machine GUID is unavailable. This function never reads the
  gateway API key and must never be extended to do so.
#>
function Get-OmniRouteCliToken {
  $machineGuid = ""
  try {
    $machineGuid = (Get-ItemProperty -Path "HKLM:\SOFTWARE\Microsoft\Cryptography" -ErrorAction Stop).MachineGuid
  } catch {
    return ""
  }
  if (-not $machineGuid) { return "" }

  try {
    $hmac = New-Object System.Security.Cryptography.HMACSHA256
    $hmac.Key = [System.Text.Encoding]::UTF8.GetBytes($machineGuid)
    $sig = $hmac.ComputeHash([System.Text.Encoding]::UTF8.GetBytes("omniroute-cli-auth-v1"))
    return (([BitConverter]::ToString($sig)) -replace "-", "").ToLowerInvariant()
  } catch {
    return ""
  }
}

<#
.SYNOPSIS
  Asks the gateway for the active combo and reports where the answer came from.

.OUTPUTS
  A record with Name ("" when unknown), Source ("api/settings" or "sqlite") and
  Error (why it is empty). An unknown active combo is a normal result here, not a
  failure: the gateway keeps it in runtime memory.
#>
function Get-OmniRouteActiveCombo {
  $result = [pscustomobject]@{ Name = ""; Source = ""; Error = "" }

  $token = Get-OmniRouteCliToken
  if (-not $token) {
    $result.Error = "sin token de maquina"
    return $result
  }

  $settings = $null
  try {
    $settings = Invoke-RestMethod -Method Get -Uri ("http://127.0.0.1:" + $script:OmniRoutePort + "/api/settings") -Headers @{ "x-omniroute-cli-token" = $token } -TimeoutSec $script:OmniRouteSettingsTimeoutSec
  } catch {
    $result.Error = "api/settings no responde"
    return $result
  }

  # The field name is probed, not assumed: this build has none of them, and a
  # future build might rename it. An unrecognised payload is "sin datos", not a
  # guess at the active combo.
  foreach ($prop in $settings.PSObject.Properties) {
    if ($prop.Name -notmatch "^(?i:activeCombo|activeComboName|active_combo|defaultCombo)$") { continue }
    $value = [string]$prop.Value
    if ($value) {
      $result.Name = $value
      $result.Source = "api/settings"
      return $result
    }
  }

  $result.Error = "api/settings no expone el combo activo"
  return $result
}

<#
.SYNOPSIS
  The hub widget entry point. Returns the lines to render, already sized.

.PARAMETER Width
  Dock width in columns. Declared as an optional parameter so the hub can splat it,
  and clamped here so a direct call cannot produce a line wider than the dock.
#>
function Get-WidgetOmniRoute {
  [CmdletBinding()]
  param([int]$Width = 37)

  # Local, not script-scoped: dot-sourcing this module must not change the
  # caller's error policy.
  $ErrorActionPreference = "SilentlyContinue"

  if (-not $script:InvokeNativeLoaded) {
    $helper = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "..", "..", "lib", "Invoke-Native.ps1"))
    if ([System.IO.File]::Exists($helper)) { . $helper }
  }
  if (-not (Get-Command "Start-OmniRouteComboRead" -ErrorAction SilentlyContinue)) {
    $combos = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "..", "..", "lib", "Get-OmniRouteCombos.ps1"))
    if ([System.IO.File]::Exists($combos)) { . $combos }
  }

  $lines = @()

  $portJob = Start-NativeProcess -FilePath "netstat" -Arguments @("-an")
  $comboJob = Start-OmniRouteComboRead

  $up = $false
  $port = Complete-NativeProcess -Job $portJob -TimeoutMs $script:OmniRouteNetstatTimeoutMs
  if ($port.Output) {
    $up = @(($port.Output -split "`r?`n") | Where-Object { $_ -match ":" + $script:OmniRoutePort + "\s+.*LISTENING" }).Count -gt 0
  }

  if ($up) {
    $lines += "Gateway: UP   localhost:" + $script:OmniRoutePort
  } else {
    $lines += "Gateway: DOWN localhost:" + $script:OmniRoutePort
    $lines += "Arranca con: prefix+o"
  }

  # The active combo needs the HTTP probe only when the database cannot answer it,
  # so the cheap, local source is tried first.
  $read = Complete-OmniRouteComboRead -Job $comboJob
  $activeName = ""
  $activeSource = ""
  if ($read.Ok -and $read.ActiveComboName) {
    $activeName = $read.ActiveComboName
    $activeSource = "sqlite"
  } else {
    $active = Get-OmniRouteActiveCombo
    if ($active.Name) {
      $activeName = $active.Name
      $activeSource = $active.Source
    }
  }

  if ($activeName) {
    $lines += "Activo: " + $activeName
  } else {
    $lines += "Activo: sin datos"
  }

  $lines += ""

  if (-not $read.Ok) {
    # A broken read is never rendered as "no combos configured".
    $detail = ""
    if ($read.Error) {
      $detail = ([string]$read.Error -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
      if ($detail) { $detail = $detail.Trim() }
    }
    if (-not $detail) { $detail = "lectura fallida" }
    $lines += "Combos: sin datos"
    $lines += "  (" + $detail + ")"
    return $lines
  }

  $lines += "Combos:"
  $iconActive = [string][char]0x25CF    # U+25CF, the filled dot
  $iconIdle = [string][char]0x25CB     # U+25CB, the hollow dot
  $activeKnown = ($activeName -ne "")
  foreach ($c in $read.Combos) {
    $icon = ""
    if ($activeKnown) { $icon = if ($c.Active) { $iconActive } else { $iconIdle } }
    $state = if ($c.Enabled) { "" } else { " off" }
    $prefix = if ($activeKnown) { $icon + " " } else { "  " }
    $lines += " " + $prefix + $c.Name + $state
  }
  if ($read.Combos.Count -eq 0) { $lines += "  (sin combos)" }
  if (-not $activeKnown) {
    $lines += "  (combo activo: sin datos)"
  }

  return $lines
}
