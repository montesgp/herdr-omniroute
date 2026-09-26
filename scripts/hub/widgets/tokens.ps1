<#
.SYNOPSIS
  Hub widget: total token output across projects. Honest stub.

.DESCRIPTION
  The widget exists so the extension contract is demonstrated on a real entry
  rather than on a one-line example, and it is deliberately EMPTY of numbers.

  Two facts make "no numbers" the correct output instead of a placeholder:

    - The data source was never decided. Candidates are the gateway usage logs,
      Herdr session snapshots and the pi logs. Only the first would be free of new
      plumbing, and the gateway keeps the total itself.
    - Nothing routes through the gateway yet, so even the gateway's own usage
      would read a true 0 that means "not measured", not "not used".

  A token total invented here would be the worst possible output: it looks like
  the number the widget exists to show.

.NOTES
  TODO(H4): decide the data source with the user (see odd/tasks/herdr-hub.md, H4)
  and then replace the body of Get-WidgetTokens with the read. Keep the
  "honest if there is no data" rule: a source that answers with nothing renders
  "sin datos", never a zero.

  Dot-source it, do not run it:

    . (Join-Path $PSScriptRoot "tokens.ps1")
#>

<#
.SYNOPSIS
  The hub widget entry point. Returns the lines to render.

.PARAMETER Width
  Dock width in columns. Declared so the hub can splat it even though a stub
  has nothing to wrap.
#>
function Get-WidgetTokens {
  [CmdletBinding()]
  param([int]$Width = 37)

  $lines = @()
  $lines += "Total por proyecto:"
  $lines += "  pendiente"
  $lines += ""
  $lines += "Fuente de datos sin decidir:"
  $lines += "  gateway / snapshots / pi"
  $lines += ""
  $lines += "Clientes aun no enrutados al"
  $lines += "gateway: no hay uso que sumar"
  $lines += ""
  $lines += "TODO(H4): odd/tasks/herdr-hub.md"
  return $lines
}
