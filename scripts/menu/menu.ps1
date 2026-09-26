<#
.SYNOPSIS
  Herdr Hub menu - the on-demand mini-menu that runs inside a Herdr popup.

.DESCRIPTION
  Four rows, one per tool, each carrying that tool's own brand glyph:

    1  (claude)     2  (codex)     3  (opencode)     4  (omniroute)

  Rows 1-3 focus the agent's pane in the current workspace. Row 4 expands the
  OmniRoute gateway state INLINE, in the same popup: UP/DOWN from the listening
  socket on :20128 plus the configured combos read straight out of the gateway's
  own SQLite store. q returns from the expanded row to the menu; q/Q/Escape in the
  menu closes the popup.

  The surface is deliberately tiny. A popup is a session-modal terminal that Herdr
  draws on top of the workspace without touching the tiled layout, so the menu
  reserves NO space, never displaces the main pane, and disappears the moment this
  command exits. The dock this replaced split the workspace and cost 15-20% of its
  width, which is more than the user already gets from pi's own panels.

  Every glyph is a [char] code point and never a literal: Windows PowerShell 5.1
  reads a .ps1 without a BOM as ANSI, so a literal U+2733 in this file would arrive
  mojibake on a legacy console. Same reason status-dashboard.ps1 does it. The
  runtime output encoding is forced to UTF-8 for the same reason.

  Every external call is windowless (lib\Invoke-Native.ps1) and bounded, and every
  failure renders as a status line instead of an exception: a dead source must not
  close a menu the user is looking at. The active combo is reported as "sin datos"
  when the gateway exposes no such field, because that is the truth on this build -
  it is never guessed.

.EXAMPLE
  .\menu.ps1 -Once
  .\menu.ps1 -Once -View omni
#>
[CmdletBinding()]
param(
  [int]$MaxSeconds = 300,
  [int]$Width = 34,
  [ValidateSet("menu", "omni")][string]$View = "menu",
  [switch]$Once,
  [switch]$NoKeyWatch
)

$ErrorActionPreference = "SilentlyContinue"

try {
  if ([Console]::OutputEncoding.CodePage -ne 65001) {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
  }
} catch { }

$ESC = [char]27
$GatewayPort = 20128
$NetstatTimeoutMs = 5000
$HerdrTimeoutMs = 10000

# Herdr is addressed through HERDR_BIN_PATH so the plugin stays portable; a bare
# "herdr" resolves through PATH. Every call goes through Invoke-NativeText, so no
# child ever gets a console window of its own.
$herdrBin = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }

# Box drawing: U+2500 / U+2502 / U+250C / U+2510 / U+2514 / U+2518.
$BoxH = [string][char]0x2500
$BoxV = [string][char]0x2502
$BoxTL = [string][char]0x250C
$BoxTR = [string][char]0x2510
$BoxBL = [string][char]0x2514
$BoxBR = [string][char]0x2518

# Brand glyphs, one per row. The Herdr terminal renders all of them even at 18 px,
# which is why the menu can carry a logo instead of a letter.
$Bullet = [string][char]0x00B7    # U+00B7, the separator dot in the hint line

$script:MenuEntries = @(
  @{ Key = "1"; Logo = [string][char]0x2733; Name = "claude";    Agent = "claude" }
  @{ Key = "2"; Logo = [string][char]0x25CE; Name = "codex";     Agent = "codex" }
  @{ Key = "3"; Logo = [string][char]0x25C8; Name = "opencode";  Agent = "opencode" }
  @{ Key = "4"; Logo = [string][char]0x25A3; Name = "omniroute"; Agent = "" }
)

# 34 drawn columns inside a 35 column popup. The spare column matters: a line that
# fills the pane leaves the terminal in the pending auto-wrap state, and the next
# ESC[K then wraps the cursor and drags the frame down a row.
$script:Columns = [Math]::Max(20, $Width)
$script:Inner = $script:Columns - 2

# Frames are a fixed 9 lines in both states. A menu that changes height when a row
# is picked is a menu that reflows under the user's fingers.
$script:OmniContentMax = 5

$script:MenuView = ($View -ne "omni")
$script:StatusLine = ""
$script:DetailLine = ""
$script:KeyWatch = (-not $NoKeyWatch)

# Paths are combined with [System.IO.Path]::Combine, not Join-Path: the first
# Join-Path in a process autoloads Microsoft.PowerShell.Management, which costs
# ~95 ms. Do not "tidy" these back.
$libRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "..", "lib"))
foreach ($needed in @("Invoke-Native.ps1", "Get-OmniRouteCombos.ps1")) {
  if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($libRoot, $needed))) {
    Write-Output ("Herdr Hub: falta el helper lib\" + $needed)
    exit 1
  }
}
. ([System.IO.Path]::Combine($libRoot, "Invoke-Native.ps1"))
. ([System.IO.Path]::Combine($libRoot, "Get-OmniRouteCombos.ps1"))

<#
.SYNOPSIS
  One bounded windowless herdr call, parsed as JSON when it succeeds.

.OUTPUTS
  A record with ExitCode, Json (or $null) and Text (a single-line diagnostic).
  Never throws: a failed call is a message the menu renders, not an exception
  unwinding a script whose whole job is to stay open.
#>
function Invoke-HerdrJson {
  param([string[]]$Arguments, [int]$TimeoutMs = 8000)

  $run = Invoke-NativeText -FilePath $herdrBin -Arguments $Arguments -TimeoutMs $TimeoutMs

  $text = ""
  if ($run.Text) { $text = (([string]$run.Text) -replace "\s+", " ").Trim() }

  $out = [pscustomobject]@{ ExitCode = $run.ExitCode; Json = $null; Text = $text }
  if ($run.ExitCode -ne 0) { return $out }

  $raw = ""
  if ($run.Output) { $raw = ([string]$run.Output).Trim() }
  if (-not $raw) { return $out }

  # The CLI answers with a single JSON object, but a warning on stdout would break
  # ConvertFrom-Json, so parsing starts at the first brace.
  $start = $raw.IndexOf("{")
  if ($start -lt 0) { return $out }
  try { $out.Json = ($raw.Substring($start) | ConvertFrom-Json) } catch { $out.Json = $null }
  return $out
}

<#
.SYNOPSIS
  The workspace the menu belongs to, or "" when it cannot be told.

.DESCRIPTION
  A popup is not a Herdr pane: it has no pane id, so HERDR_PANE_ID is not injected
  and "current" is whatever the UI has focused underneath the modal. Three sources
  are tried in order, cheapest first, and an empty answer is reported honestly
  instead of falling back to another workspace's panes.
#>
function Get-MenuWorkspaceId {
  if ($env:HERDR_WORKSPACE_ID) { return [string]$env:HERDR_WORKSPACE_ID }

  $context = $env:HERDR_PLUGIN_CONTEXT_JSON
  if ($context) {
    try {
      $ctx = ([string]$context) | ConvertFrom-Json
      if ($ctx.workspace_id) { return [string]$ctx.workspace_id }
      if ($ctx.workspaceId) { return [string]$ctx.workspaceId }
      if ($ctx.workspace -and $ctx.workspace.id) { return [string]$ctx.workspace.id }
    } catch { }
  }

  $current = Invoke-HerdrJson -Arguments @("pane", "current")
  if ($current.Json -and $current.Json.result) {
    if ($current.Json.result.pane -and $current.Json.result.pane.workspace_id) {
      return [string]$current.Json.result.pane.workspace_id
    }
    if ($current.Json.result.workspace_id) { return [string]$current.Json.result.workspace_id }
  }
  return ""
}

<#
.SYNOPSIS
  The pane id hosting $Agent in $WorkspaceId, or "" when there is none.

.DESCRIPTION
  Matching is on the pane's `agent` field, which Herdr fills with the detected agent
  kind ("claude", "codex", "opencode"). A pane without a recognized agent has an
  empty field and is skipped, so a bare shell never answers for a tool.
#>
function Find-MenuAgentPane {
  param([string]$Agent, [string]$WorkspaceId)

  $list = Invoke-HerdrJson -Arguments @("pane", "list")
  if (-not $list.Json -or -not $list.Json.result) { return "" }

  $panes = @()
  if ($list.Json.result.panes) { $panes = @($list.Json.result.panes) }

  foreach ($p in $panes) {
    if (-not $p.agent) { continue }
    if ([string]$p.agent -ne $Agent) { continue }
    if ([string]$p.workspace_id -ne $WorkspaceId) { continue }
    return [string]$p.pane_id
  }
  return ""
}

<#
.SYNOPSIS
  Focuses an agent pane, windowless, and reports why it could not.

.OUTPUTS
  "" on success, otherwise a short diagnostic. `ui_busy` is reported on its own
  because it is the expected failure mode: another Herdr modal is holding the UI.
  `herdr agent focus` (not `pane focus`, which only walks to a NEIGHBOUR of the
  caller) is what can name an arbitrary pane.
#>
function Set-MenuAgentFocus {
  param([string]$PaneId)

  $run = Invoke-HerdrJson -Arguments @("agent", "focus", $PaneId) -TimeoutMs $HerdrTimeoutMs
  if ($run.ExitCode -eq 0) { return "" }
  if ($run.Text -match "ui_busy") { return "ui_busy: cerra los popups abiertos" }
  if ($run.Text) { return $run.Text }
  return "focus fallo"
}

<#
.SYNOPSIS
  Runs the action behind a menu row.

.OUTPUTS
  A record with Exit (true when the popup should close, which is the focus success
  case) and the two status lines to show otherwise. The menu stays alive on every
  failure: a row that could not run is a line, not a closed menu.
#>
function Invoke-MenuRow {
  param($Entry)

  $agent = [string]$Entry.Agent

  $workspaceId = Get-MenuWorkspaceId
  if (-not $workspaceId) {
    return [pscustomobject]@{
      Exit   = $false
      Status = "no se pudo saber el workspace"
      Detail = "herdr pane current no respondio"
    }
  }

  $paneId = Find-MenuAgentPane -Agent $agent -WorkspaceId $workspaceId
  if (-not $paneId) {
    return [pscustomobject]@{
      Exit   = $false
      Status = ("no hay pane " + $agent + " en este ws")
      Detail = "abri " + $agent + " en este workspace"
    }
  }

  $failure = Set-MenuAgentFocus -PaneId $paneId
  if ($failure -eq "") {
    # The popup is a session modal: exiting here is what closes it, and the pane
    # is already focused underneath.
    return [pscustomobject]@{ Exit = $true; Status = ""; Detail = "" }
  }

  return [pscustomobject]@{
    Exit   = $false
    Status = ("no se pudo enfocar " + $agent)
    Detail = $failure
  }
}

<#
.SYNOPSIS
  The gateway lines for the omniroute row, snapshot semantics.

.DESCRIPTION
  Two independent sources, started together and collected afterwards, so the frame
  costs the slower one instead of their sum:

    UP/DOWN      netstat -an filtered for a LISTENING socket on :20128. Same
                 detection as the status popup, so the two cannot disagree.
    combos       the same read-only SELECT the status popup uses, through
                 lib\Get-OmniRouteCombos.ps1. Not a second implementation.

  The active combo comes from what SQLite can prove. This build keeps it in runtime
  memory and exposes no such field, so "sin datos" is the honest answer and no
  marker is drawn. No HTTP call and no credential: the row reads the same two
  sources as the status popup and nothing else.
#>
function Get-MenuOmniRouteLines {
  $ErrorActionPreference = "SilentlyContinue"

  $portJob = Start-NativeProcess -FilePath "netstat" -Arguments @("-an")
  $comboJob = Start-OmniRouteComboRead

  # Named $portRun, NOT $port or $Port: PowerShell variable names are
  # case-insensitive, so either of those would be the same variable as the
  # $GatewayPort constant above, and the LISTENING filter below would then run
  # against a process record's ToString() and report the gateway DOWN forever.
  $up = $false
  $portRun = Complete-NativeProcess -Job $portJob -TimeoutMs $NetstatTimeoutMs
  if ($portRun.Output) {
    $up = @(($portRun.Output -split "`r?`n") | Where-Object { $_ -match ":$GatewayPort\s+.*LISTENING" }).Count -gt 0
  }

  $lines = @()
  if ($up) { $lines += "Gateway UP   localhost:" + $GatewayPort } else { $lines += "Gateway DOWN localhost:" + $GatewayPort }

  $read = Complete-OmniRouteComboRead -Job $comboJob
  if ($read.Ok -and $read.ActiveComboName) {
    $lines += "combo activo: " + $read.ActiveComboName
  } else {
    $lines += "combo activo: sin datos"
  }

  if (-not $read.Ok) {
    # A broken read is never rendered as "no combos configured".
    $detail = ""
    if ($read.Error) {
      $detail = [string]($read.Error -split "`r?`n" | Where-Object { $_.Trim() } | Select-Object -First 1)
      if ($detail) { $detail = $detail.Trim() }
    }
    if (-not $detail) { $detail = "lectura fallida" }
    $lines += "combos: sin datos"
    $lines += "(" + $detail + ")"
    return $lines
  }

  # Two combo rows plus a truncation note fill the space the box has. Hiding the
  # overflow behind a count is honest; silently dropping it would not be.
  $maxComboLines = 2
  $shown = 0
  foreach ($c in $read.Combos) {
    if ($shown -ge $maxComboLines) {
      $lines += "(+" + ($read.Combos.Count - $shown) + " mas)"
      break
    }
    $state = if ($c.Enabled) { "" } else { " off" }
    $lines += " " + $c.Name + $state
    $shown++
  }
  if ($read.Combos.Count -eq 0) { $lines += "(sin combos)" }
  return $lines
}

# Clips to the drawn width. Tabs become spaces first: a tab would push the frame to
# the next row on a 34 column popup and break the in-place redraw.
function Format-MenuLine([string]$Text) {
  if ($null -eq $Text) { return "" }
  $t = ([string]$Text) -replace "`t", " "
  if ($t.Length -gt $script:Columns) { $t = $t.Substring(0, $script:Columns) }
  return $t
}

function New-MenuBoxTop([string]$Title) {
  $label = " " + $Title + " "
  $fill = $script:Inner - 1 - $label.Length
  if ($fill -lt 0) { $fill = 0 }
  return ($BoxTL + $BoxH + $label + ($BoxH * $fill) + $BoxTR)
}

function New-MenuBoxBottom {
  return ($BoxBL + ($BoxH * $script:Inner) + $BoxBR)
}

# One framed row. The content is inset one column on each side, so a row can hold
# Inner-2 characters and the closing bar always lands on the same column.
function New-MenuBoxRow([string]$Text) {
  $t = ""
  if ($null -ne $Text) { $t = ([string]$Text) -replace "`t", " " }
  $room = $script:Inner - 2
  if ($t.Length -gt $room) { $t = $t.Substring(0, $room) }
  return ($BoxV + " " + $t.PadRight($room) + " " + $BoxV)
}

<#
.SYNOPSIS
  The whole frame for the current state, as a list of lines.

.NOTES
  Both states are 9 lines tall, so picking a row never reflows the popup.
#>
function Get-MenuFrame {
  $lines = @()

  if ($script:MenuView) {
    $lines += New-MenuBoxTop "Herdr Hub"
    foreach ($e in $script:MenuEntries) {
      $lines += New-MenuBoxRow ($e.Key + "  " + $e.Logo + "  " + $e.Name)
    }
    $lines += New-MenuBoxBottom
    $lines += (" " + $script:StatusLine)
    $lines += (" " + $script:DetailLine)
    $lines += (" " + (Get-MenuKeyRange) + " elige " + $Bullet + " q cierra")
    return $lines
  }

  $lines += New-MenuBoxTop "OmniRoute"
  $body = @(Get-MenuOmniRouteLines)
  for ($i = 0; $i -lt $script:OmniContentMax; $i++) {
    if ($i -lt $body.Count) { $lines += New-MenuBoxRow $body[$i] } else { $lines += New-MenuBoxRow "" }
  }
  $lines += New-MenuBoxBottom
  $lines += " "
  $lines += (" q vuelve " + $Bullet + " Esc sale")
  return $lines
}

# Generated from the registry so the hint can never name a key that does not exist.
function Get-MenuKeyRange {
  $keys = @()
  foreach ($e in $script:MenuEntries) { $keys += $e.Key }
  if ($keys.Count -eq 0) { return "" }

  $consecutive = $true
  for ($i = 0; $i -lt $keys.Count; $i++) {
    if ($keys[$i] -notmatch "^\d$") { $consecutive = $false; break }
    if ($i -gt 0 -and ([int]$keys[$i]) -ne (([int]$keys[$i - 1]) + 1)) { $consecutive = $false; break }
  }
  if ($consecutive) { return ($keys[0] + "-" + $keys[$keys.Count - 1]) }
  return ($keys -join " ")
}

function Get-MenuEntry([string]$Key) {
  if (-not $Key) { return $null }
  foreach ($e in $script:MenuEntries) { if ($e.Key -eq $Key) { return $e } }
  return $null
}

# Paints in place: cursor home, one clear-to-end per line, clear-below at the end.
# ESC[J is what removes leftovers when the frame changes, so switching rows never
# leaves a stale line behind.
function Write-MenuFrame {
  try { [Console]::SetCursorPosition(0, 0) } catch { Write-Host "$ESC[H" -NoNewline }
  foreach ($line in (Get-MenuFrame)) {
    Write-Host ((Format-MenuLine $line) + $ESC + "[K")
  }
  Write-Host ($ESC + "[J") -NoNewline
}

<#
.SYNOPSIS
  Waits for one key, bounded.

.OUTPUTS
  The key as a string, "ESC" for Escape, "" when the slice timed out, and $null when
  the host cannot report keypresses at all (redirected input, no console). The
  caller tells the last two apart: a timeout is normal, a keyless host ends the
  loop instead of spinning to the cap.
#>
function Read-MenuKey([int]$TimeoutMs) {
  $end = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
  while ([DateTime]::UtcNow -lt $end) {
    if ($script:KeyWatch) {
      try {
        if ([Console]::KeyAvailable) {
          $key = [Console]::ReadKey($true)
          if ($key.Key -eq [ConsoleKey]::Escape) { return "ESC" }
          return [string]$key.KeyChar
        }
      } catch {
        $script:KeyWatch = $false
      }
    } else {
      $remaining = $end - [DateTime]::UtcNow
      if ($remaining.TotalMilliseconds -gt 0) { Start-Sleep -Milliseconds ([int]$remaining.TotalMilliseconds) }
      return $null
    }
    Start-Sleep -Milliseconds 40
  }
  return ""
}

try {
  if ($Once) { Write-MenuFrame; exit 0 }

  if ($NoKeyWatch) {
    Write-MenuFrame
    Start-Sleep -Seconds ([int][Math]::Max(1, $MaxSeconds))
    exit 0
  }

  $deadline = [DateTime]::UtcNow.AddSeconds([int][Math]::Max(1, $MaxSeconds))
  $dirty = $true

  while ([DateTime]::UtcNow -lt $deadline) {
    if ($dirty) { Write-MenuFrame; $dirty = $false }

    $key = Read-MenuKey -TimeoutMs 200
    if ($null -eq $key) { break }   # host without keypresses: the frame stays, we leave
    if (-not $key) { continue }     # nothing pressed

    if ($key -eq "q" -or $key -eq "Q") {
      if ($script:MenuView) { break }
      $script:MenuView = $true    # expanded row: q goes back, it does not close
      $dirty = $true
      continue
    }
    if ($key -eq "ESC") { break }  # Escape always closes

    $entry = Get-MenuEntry $key
    if ($null -eq $entry) { continue }   # not our key: ignored, the menu keeps its keymap

    if ($script:MenuView) {
      if ($entry.Agent) {
        $result = Invoke-MenuRow $entry
        if ($result.Exit) { break }      # focus landed: exiting here is what closes the popup
        $script:StatusLine = $result.Status
        $script:DetailLine = $result.Detail
        $dirty = $true
      } else {
        $script:MenuView = $false
        $script:StatusLine = ""
        $script:DetailLine = ""
        $dirty = $true
      }
    }
  }
} catch {
  # The popup is the process: ending this script is what closes it, so there is
  # nothing worth reporting after the frame. The last frame stays on screen.
  exit 0
}

exit 0
