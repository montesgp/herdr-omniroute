<#
.SYNOPSIS
  Herdr Hub - the multi-widget dock that runs inside the hub pane.

.DESCRIPTION
  The hub is a thin pane anchored to the right of a workspace. It has two states
  and no third:

    Collapsed  one line of icons (the "power wheel" strip) plus a hint line.
    Expanded   the selected widget's lines, its title, and the same strip at the
               bottom so the keys never go out of sight.

  Everything is drawn in place - cursor home, one ESC[K per line, ESC[J at the
  end - following the conventions in scripts\status-dashboard.ps1, so the dock
  never scrolls and never allocates a window. The only keys that mean anything are
  the selection keys declared by scripts\hub\widgets.ps1 plus q/Q and Escape.
  Anything else is consumed and ignored: a dock owns its own keymap and must not
  be steerable by stray bytes.

  The active combo marker and the widget layout come from the registry, not from
  this file. Adding a widget is one module plus one registry line.

.NOTES
  -PaneId is the hub pane's own id, passed by scripts\hub\open-hub.ps1. It is what
  lets the dock close itself on exit, and it is what makes the opener idempotent:
  the title set below is the marker the opener looks for. Empty means "run by
  hand", so exiting closes nothing.

  -MaxSeconds is a hard cap enforced in every path, including the host that cannot
  report keypresses, so the dock can never become an orphan loop.

.EXAMPLE
  .\index.ps1 -PaneId w1G:p5
  .\index.ps1 -Once
  .\index.ps1 -Once -Widget 1
#>
[CmdletBinding()]
param(
  [string]$PaneId = "",
  [int]$MaxSeconds = 1800,
  [int]$Width = 37,
  [int]$RefreshSec = 15,
  [switch]$Once,
  [switch]$NoKeyWatch,
  [string]$Widget = ""
)

$ErrorActionPreference = "SilentlyContinue"

# Markers are [char] code points, never literals: Windows PowerShell 5.1 reads a
# .ps1 without a BOM as ANSI, so a literal glyph in the source arrives mojibake on
# a legacy console. The runtime output encoding is forced to UTF-8 for the same
# reason status-dashboard.ps1 does it: the pane must be able to draw them.
try {
  if ([Console]::OutputEncoding.CodePage -ne 65001) {
    [Console]::OutputEncoding = New-Object System.Text.UTF8Encoding $false
  }
} catch { }

$ESC = [char]27
$Bullet = [string][char]0x00B7

# The title prefix is a contract, not decoration: open-hub.ps1 treats any pane in
# the current workspace whose terminal_title_stripped starts with it as an already
# open dock, so the hub is idempotent without a state file.
$script:HubTitle = "hub: herdr-omniroute"

# 37 is what a 0.8 right split leaves on a ~183 column workspace (the remaining
# 20%), not a guess. Lines are clipped one column short of it: a line that fills
# the pane leaves the terminal in the pending auto-wrap state, and the next ESC[K
# then wraps the cursor and drags the frame down a row.
$script:HubWidth = [Math]::Max(12, $Width)
$script:HubWidgetRoot = [System.IO.Path]::Combine($PSScriptRoot, "widgets")

# A widget may not take the dock down with it, and it may not take over the screen
# either, so its output is capped as well as caught.
$script:HubMaxWidgetLines = 14

$script:HubPaneId = $PaneId
$script:HubExpanded = $null
$script:HubLoadedModule = ""
$script:HubKeyWatch = $true
$script:HubRenderedAt = [DateTime]::MinValue

$libRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "..", "lib"))
foreach ($needed in @("Invoke-Native.ps1", "Get-OmniRouteCombos.ps1")) {
  if (-not [System.IO.File]::Exists([System.IO.Path]::Combine($libRoot, $needed))) {
    Write-Output ("Herdr Hub: falta el helper lib\" + $needed)
    exit 1
  }
}
$registry = [System.IO.Path]::Combine($PSScriptRoot, "widgets.ps1")
if (-not [System.IO.File]::Exists($registry)) {
  Write-Output "Herdr Hub: falta el registro widgets.ps1"
  exit 1
}

. ([System.IO.Path]::Combine($libRoot, "Invoke-Native.ps1"))
. ([System.IO.Path]::Combine($libRoot, "Get-OmniRouteCombos.ps1"))
. $registry

try { $Host.UI.RawUI.WindowTitle = $script:HubTitle } catch { }

# -Widget starts with one entry expanded. It exists so a frame can be checked from
# a shell (-Once -Widget 1) without a pane, a dock or a keypress.
if ($Widget) { $script:HubExpanded = Resolve-HubWidget -Key $Widget }

# Clips to the dock width. Tabs are expanded to spaces first: a tab would push the
# frame to the next line on a 37 column pane and break the in-place redraw.
function Format-HubLine([string]$Line) {
  if ($null -eq $Line) { return "" }
  $text = ([string]$Line) -replace "`t", " "
  $limit = $script:HubWidth - 1
  if ($text.Length -gt $limit) { $text = $text.Substring(0, $limit) }
  return $text
}

# Paints the frame in place: cursor home, one clear-to-end per line, clear-below at
# the end. ESC[J is what removes the leftovers when a frame shrinks, so a dock
# that goes from expanded to collapsed does not keep stale rows.
function Write-HubFrame([string[]]$Lines) {
  try { [Console]::SetCursorPosition(0, 0) } catch { Write-Host "$ESC[H" -NoNewline }
  foreach ($line in $Lines) {
    Write-Host ((Format-HubLine $line) + $ESC + "[K")
  }
  Write-Host ($ESC + "[J") -NoNewline
}

# The strip, identical in both states: "[HUB] 1 (o) 2 S 3 gear". The dock is only
# ~37 columns wide, so the strip is generated from the registry and never padded or
# aligned by hand.
function Get-HubStrip {
  $strip = "[HUB]"
  $sep = " "
  foreach ($w in Get-HubWidget) {
    $strip += $sep + $w.Key + " " + $w.Icon
    $sep = "  "
  }
  return $strip
}

# "1-3" for a consecutive run of single-digit keys, otherwise the keys spelled out.
# Generated from the registry so the hint cannot claim a key that does not exist.
function Get-HubKeyRange {
  $keys = @()
  foreach ($w in Get-HubWidget) { $keys += $w.Key }
  if ($keys.Count -eq 0) { return "" }

  $consecutive = $true
  for ($i = 0; $i -lt $keys.Count; $i++) {
    if ($keys[$i] -notmatch "^\d$") { $consecutive = $false; break }
    if ($i -gt 0 -and ([int]$keys[$i]) -ne (([int]$keys[$i - 1]) + 1)) { $consecutive = $false; break }
  }
  if ($consecutive) { return $keys[0] + "-" + $keys[$keys.Count - 1] }
  return ($keys -join " ")
}

<#
.SYNOPSIS
  Runs one widget and returns its lines.

.NOTES
  The module is dot-sourced on first use and then cached, so toggling a widget
  twice does not re-parse it. The function name and the module path are both
  derived from the registry Id, which is why a widget is "one file, one line".

  -Width is only splatted when the function declares it, so a minimal widget that
  takes no parameters still works.
#>
function Get-HubWidgetLines($Widget) {
  $module = [System.IO.Path]::Combine($script:HubWidgetRoot, ($Widget.Id.ToLowerInvariant() + ".ps1"))
  if (-not [System.IO.File]::Exists($module)) {
    return @("(falta el modulo " + $Widget.Id + ")")
  }
  if ($script:HubLoadedModule -ne $module) {
    . $module
    $script:HubLoadedModule = $module
  }

  $fn = "Get-Widget" + $Widget.Id
  $command = Get-Command $fn -ErrorAction SilentlyContinue
  if (-not $command) { return @("(el modulo no define " + $fn + ")") }

  $splat = @{}
  if ($command.Parameters.ContainsKey("Width")) { $splat["Width"] = $script:HubWidth }

  $result = & $fn @splat
  if ($null -eq $result) { return @() }

  $lines = @()
  foreach ($l in @($result)) {
    $lines += [string]$l
    if ($lines.Count -ge $script:HubMaxWidgetLines) { break }
  }
  return $lines
}

# The whole frame for the current state. Built as a list of strings and painted
# once, so a half-drawn frame is not something the user can ever see.
function Get-HubFrame {
  $frame = @()

  if ($null -eq $script:HubExpanded) {
    $frame += Get-HubStrip
    $frame += (Get-HubKeyRange) + " expande $Bullet q cierra"
    return $frame
  }

  $widget = $script:HubExpanded
  $frame += "[" + $widget.Key + "] " + $widget.Title
  $frame += ("-" * 30)

  # One widget's failure is one line. The dock keeps running: a dead source must
  # not close a pane the user is looking at.
  try {
    $frame += Get-HubWidgetLines $widget
  } catch {
    $frame += "(error del widget: " + $_.Exception.Message + ")"
  }

  $frame += ("-" * 30)
  $frame += Get-HubStrip
  $frame += (Get-HubKeyRange) + " cambia $Bullet q cierra"
  return $frame
}

<#
.SYNOPSIS
  Waits for one key, bounded.

.OUTPUTS
  The key as a string, "ESC" for Escape, "" on timeout, and $null when the host
  cannot report keypresses at all (redirected input, no console). The caller
  distinguishes the last two: a timeout is normal, a keyless host ends the loop
  instead of spinning to the cap.
#>
function Read-HubKey([int]$TimeoutMs) {
  $end = [DateTime]::UtcNow.AddMilliseconds($TimeoutMs)
  while ([DateTime]::UtcNow -lt $end) {
    if ($script:HubKeyWatch) {
      try {
        if ([Console]::KeyAvailable) {
          $key = [Console]::ReadKey($true)
          if ($key.Key -eq [ConsoleKey]::Escape) { return "ESC" }
          return [string]$key.KeyChar
        }
      } catch {
        $script:HubKeyWatch = $false
      }
    } else {
      # Degrade to a bounded wait instead of failing, so -MaxSeconds still holds
      # in a host that cannot report keypresses.
      $remaining = $end - [DateTime]::UtcNow
      if ($remaining.TotalMilliseconds -gt 0) { Start-Sleep -Milliseconds ([int]$remaining.TotalMilliseconds) }
      return $null
    }
    Start-Sleep -Milliseconds 40
  }
  return ""
}

# The pane is the process: closing it ends this script, so there is no code worth
# running afterwards and no error worth reporting. Errors are swallowed on purpose.
function Close-HubDock {
  if (-not $script:HubPaneId) { return }
  $herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }
  try {
    [void](Invoke-NativeText -FilePath $herdr -Arguments @("pane", "close", $script:HubPaneId) -TimeoutMs 10000)
  } catch { }
}

try {
  if ($Once) { Write-HubFrame (Get-HubFrame); exit 0 }

  if ($NoKeyWatch) {
    Write-HubFrame (Get-HubFrame)
    Start-Sleep -Seconds ([int][Math]::Max(1, $MaxSeconds))
    Close-HubDock
    exit 0
  }

  $deadline = [DateTime]::UtcNow.AddSeconds([int][Math]::Max(1, $MaxSeconds))
  $dirty = $true

  while ([DateTime]::UtcNow -lt $deadline) {
    $now = [DateTime]::UtcNow

    # Repaint on a state change, and on a slow tick while a widget is expanded so
    # the dock is not a photograph. Nothing repaints in the collapsed state: the
    # strip does not change and redrawing it is what caused the visible lag in the
    # popup.
    $stale = $false
    if ($null -ne $script:HubExpanded -and $RefreshSec -gt 0) {
      $stale = ($now - $script:HubRenderedAt).TotalSeconds -ge $RefreshSec
    }
    if ($dirty -or $stale) {
      Write-HubFrame (Get-HubFrame)
      $script:HubRenderedAt = $now
      $dirty = $false
    }

    $key = Read-HubKey -TimeoutMs 200
    if ($null -eq $key) { break }        # host without keypresses: the frame stays, we leave
    if (-not $key) { continue }          # nothing pressed

    if ($key -eq "q" -or $key -eq "Q" -or $key -eq "ESC") { break }

    $target = Resolve-HubWidget -Key $key
    if ($null -eq $target) { continue }  # not our key: ignored, the dock keeps its keymap

    if ($null -ne $script:HubExpanded -and $script:HubExpanded.Id -eq $target.Id) {
      $script:HubExpanded = $null        # same key again: collapse
    } else {
      $script:HubExpanded = $target      # any other key: swap
    }
    $dirty = $true
  }
} catch {
  $lines = @(Get-HubStrip)
  $lines += ("error: " + $_.Exception.Message)
  $lines += "q/Esc sale"
  Write-HubFrame $lines
} finally {
  Close-HubDock
}

exit 0
