<#
.SYNOPSIS
  Opens the Herdr Hub dock in the current workspace, at most once.

.DESCRIPTION
  Five herdr calls, all windowless through lib\Invoke-Native.ps1, all bounded:

    pane current   which workspace the action was invoked in, and its focused pane
    pane list      idempotency: any pane there whose terminal_title_stripped starts
                   with "hub: " is a dock we already opened
    pane edges     the layout rects, so the dock is split off the largest pane and
                   not off a 30 px sliver
    pane split     the dock itself, right side, --ratio 0.8, --no-focus
    pane run       the hub process inside the new pane

  Two details that are easy to get wrong and are load-bearing here:

  - --ratio applies to the ORIGINAL pane. 0.8 keeps the original at 80% and leaves
    the new pane the remaining ~20% on the right, which on a ~183 column workspace
    is the ~37 column dock the hub renders for. 0.2 would do the opposite and
    swallow the workspace.
  - the id of the new pane is read from the split response, with a
    before/after "pane list" diff as the fallback, so the opener does not depend
    on one undocumented response shape.

  --no-focus keeps the user's cursor where it was: the dock is something to look
  at, not something to type into.

.NOTES
  Nothing is mutated in any other workspace: the split target and the idempotency
  check are both scoped to the current workspace id.

.EXAMPLE
  .\open-hub.ps1
#>
$ErrorActionPreference = "SilentlyContinue"

$herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }

$lib = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "..", "lib", "Invoke-Native.ps1"))
if (-not [System.IO.File]::Exists($lib)) {
  Write-Output "Herdr Hub: falta el helper $lib"
  exit 1
}
. $lib

$RepoRoot = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "..", ".."))
$HubEntry = [System.IO.Path]::Combine($RepoRoot, "scripts", "hub", "index.ps1")
if (-not [System.IO.File]::Exists($HubEntry)) {
  Write-Output "Herdr Hub: no encuentro el menu del dock en $HubEntry"
  exit 1
}

# Wall clock budget for the whole opener. A hung call must not turn the action
# into a hung action; every individual call is bounded below as well.
$Deadline = [DateTime]::UtcNow.AddSeconds(45)
$TitlePrefix = "hub: "

# First non-blank line of a diagnostic, so a multi-line stderr still prints as one
# readable reason.
function Get-FirstLine([string]$text) {
  if (-not $text) { return "" }
  foreach ($line in ($text -split "`r?`n")) {
    $trimmed = $line.Trim()
    if ($trimmed) { return $trimmed }
  }
  return ""
}

# One bounded herdr call parsed as JSON. Returns $null instead of throwing: a
# failed call is a decision the caller makes with a message, not an exception that
# unwinds a script whose job is to explain what went wrong.
function Invoke-HerdrJson {
  param([string[]]$Arguments, [int]$TimeoutMs = 8000)

  $run = Invoke-NativeText -FilePath $herdr -Arguments $Arguments -TimeoutMs $TimeoutMs
  if ($run.ExitCode -ne 0) { return $null }
  $out = ""
  if ($run.Output) { $out = ([string]$run.Output).Trim() }
  if (-not $out) { return $null }

  # The CLI answers with a single JSON object, but a warning on stdout would break
  # ConvertFrom-Json, so parsing starts at the first brace.
  $start = $out.IndexOf("{")
  if ($start -lt 0) { return $null }
  try { return ($out.Substring($start) | ConvertFrom-Json) } catch { return $null }
}

# Panes of the current workspace only, as a list of records.
function Get-HerdrPaneList {
  $json = Invoke-HerdrJson -Arguments @("pane", "list")
  $panes = @()
  if ($json -and $json.result -and $json.result.panes) { $panes = @($json.result.panes) }
  return $panes
}

<#
.SYNOPSIS
  Finds the hub dock already open in a workspace, or $null.

.DESCRIPTION
  Idempotency. The dock sets its own window title, so the running dock IS the
  state - the same trick the status popup uses, except that a dock has a pane id
  and therefore shows up in pane list.

  Scoped to one workspace on purpose: a dock in another workspace is a different
  dock, and closing or duplicating it from here would be a surprise.
#>
function Find-HubDock {
  param($Panes, [string]$WorkspaceId)

  foreach ($p in @($Panes)) {
    if ([string]$p.workspace_id -ne $WorkspaceId) { continue }
    $title = ""
    if ($p.terminal_title_stripped) { $title = [string]$p.terminal_title_stripped }
    if ($title.StartsWith($TitlePrefix)) { return $p }
  }
  return $null
}

<#
.SYNOPSIS
  Picks the pane to split the dock off, from a "pane edges" layout.

.DESCRIPTION
  The largest pane of the current tab: the dock is a sidebar, and halving a 30 px
  sliver produces a 15 px dock nobody can read. A tie goes to the focused pane,
  which is the one the user is actually looking at.

  Falls back to the current pane when the layout cannot be read, so a missing or
  reshaped response degrades to "split where I am" instead of failing.
#>
function Select-HubMainPane {
  param($Layout, [string]$CurrentPaneId)

  if (-not $Layout -or -not $Layout.panes) { return $CurrentPaneId }

  $bestId = ""
  $bestArea = -1
  $bestFocused = $false
  foreach ($p in @($Layout.panes)) {
    $width = 0
    $height = 0
    if ($p.rect) { $width = [int]$p.rect.width; $height = [int]$p.rect.height }
    $area = $width * $height
    $focused = [bool]$p.focused
    if ($area -gt $bestArea -or ($area -eq $bestArea -and $focused -and -not $bestFocused)) {
      $bestId = [string]$p.pane_id
      $bestArea = $area
      $bestFocused = $focused
    }
  }
  if ($bestId) { return $bestId }
  return $CurrentPaneId
}

# The layout of the tab a pane belongs to. Both observed shapes are accepted:
# result.edges.layout on this build, result.layout on the flatter one.
function Get-HerdrLayout {
  param([string]$PaneId)

  $edges = Invoke-HerdrJson -Arguments @("pane", "edges", "--pane", $PaneId)
  if (-not $edges -or -not $edges.result) { return $null }
  if ($edges.result.edges -and $edges.result.edges.layout) { return $edges.result.edges.layout }
  if ($edges.result.layout) { return $edges.result.layout }
  return $null
}

# The new pane id, from the split response when it carries one and from a
# before/after difference of the workspace panes when it does not.
function Resolve-HubDockId {
  param($Split, $BeforeIds, [string]$MainPaneId, [string]$WorkspaceId)

  if ($Split -and $Split.result) {
    if ($Split.result.pane -and $Split.result.pane.pane_id) { return [string]$Split.result.pane.pane_id }
    if ($Split.result.pane_id) { return [string]$Split.result.pane_id }
  }
  foreach ($p in (Get-HerdrPaneList)) {
    if ([string]$p.workspace_id -ne $WorkspaceId) { continue }
    $id = [string]$p.pane_id
    if ($id -eq $MainPaneId) { continue }
    if (-not $BeforeIds.ContainsKey($id)) { return $id }
  }
  return ""
}

try {
  $current = Invoke-HerdrJson -Arguments @("pane", "current")
  if (-not $current -or -not $current.result -or -not $current.result.pane) {
    Write-Output "Herdr Hub: no hay un pane actual. Abre el hub desde un workspace de Herdr."
    exit 1
  }
  $currentPane = $current.result.pane
  $workspaceId = [string]$currentPane.workspace_id
  $currentPaneId = [string]$currentPane.pane_id

  $panes = Get-HerdrPaneList

  $existing = Find-HubDock -Panes $panes -WorkspaceId $workspaceId
  if ($existing) {
    Write-Output ("Herdr Hub: ya esta abierto (pane " + $existing.pane_id + ")")
    exit 0
  }

  $layout = Get-HerdrLayout -PaneId $currentPaneId
  $mainPaneId = Select-HubMainPane -Layout $layout -CurrentPaneId $currentPaneId

  # Snapshot of the workspace panes, so the new pane id can be recovered by
  # difference if the split response does not carry it.
  $known = @{}
  foreach ($p in $panes) {
    if ([string]$p.workspace_id -eq $workspaceId) { $known[[string]$p.pane_id] = $true }
  }

  $split = Invoke-HerdrJson -Arguments @(
    "pane", "split", $mainPaneId,
    "--direction", "right",
    "--ratio", "0.8",
    "--cwd", $RepoRoot,
    "--no-focus"
  ) -TimeoutMs 12000

  if (-not $split) {
    Write-Output "Herdr Hub: pane split fallo (pane $mainPaneId). No se abrio el dock."
    exit 1
  }

  $dockId = Resolve-HubDockId -Split $split -BeforeIds $known -MainPaneId $mainPaneId -WorkspaceId $workspaceId

  if (-not $dockId) {
    Write-Output "Herdr Hub: el dock se creo pero no se pudo leer su pane id. Cierralo a mano."
    exit 1
  }

  # The split shell needs a moment before it can host a command. Waiting is the
  # whole retry strategy: one wait, one run, one wait, one run.
  $runArgs = @(
    "pane", "run", $dockId,
    "powershell", "-NoProfile", "-ExecutionPolicy", "Bypass",
    "-File", $HubEntry, $dockId
  )

  Start-Sleep -Milliseconds 1500
  $run = Invoke-NativeText -FilePath $herdr -Arguments $runArgs -TimeoutMs 15000

  if ($run.ExitCode -ne 0 -and [DateTime]::UtcNow -lt $Deadline) {
    Start-Sleep -Milliseconds 1500
    $run = Invoke-NativeText -FilePath $herdr -Arguments $runArgs -TimeoutMs 15000
  }

  if ($run.ExitCode -ne 0) {
    $detail = Get-FirstLine $run.Text
    if (-not $detail) { $detail = "pane run fallo" }
    # Never leave half a dock behind: an empty pane on the right of the workspace
    # is worse than no dock at all.
    [void](Invoke-NativeText -FilePath $herdr -Arguments @("pane", "close", $dockId) -TimeoutMs 8000)
    Write-Output ("Herdr Hub: no se pudo lanzar el menu del dock - " + $detail)
    exit 1
  }

  Write-Output ("Herdr Hub: dock abierto (pane " + $dockId + "). q/Esc lo cierra.")
  exit 0
} catch {
  Write-Output ("Herdr Hub: apertura fallida - " + $_.Exception.Message)
  exit 1
}
