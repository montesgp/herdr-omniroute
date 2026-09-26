<#
.SYNOPSIS
  Hub widget: configuration surface. Stub.

.DESCRIPTION
  The hub has a "Config" entry from the start so the strip layout is not
  reshuffled when the widget arrives, and so the placeholder state is visible to
  the user instead of a mystery gap. It is registered and pressable on purpose:
  a disabled-looking key that cannot be pressed teaches nothing.

.NOTES
  What belongs here when it is built: the pieces a user changes often (which combo
  is active, whether the gateway autostarts) as key/value actions inside the same
  pane, never a second form. Anything that needs more room than 37 columns
  belongs in the full dashboard, not here.

  Dot-source it, do not run it:

    . (Join-Path $PSScriptRoot "config.ps1")
#>

<#
.SYNOPSIS
  The hub widget entry point. Returns the lines to render.

.PARAMETER Width
  Dock width in columns. Declared so the hub can splat it even though a stub
  has nothing to wrap.
#>
function Get-WidgetConfig {
  [CmdletBinding()]
  param([int]$Width = 37)

  $lines = @()
  $lines += "En construccion"
  $lines += ""
  $lines += "Sin acciones todavia."
  $lines += "Ver docs/hub.md para el"
  $lines += "contrato de widgets."
  return $lines
}
