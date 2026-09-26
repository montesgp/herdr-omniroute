<#
.SYNOPSIS
  Widget registry for the Herdr Hub dock.

.DESCRIPTION
  The hub strip is generated from this list and nothing else: one entry per widget,
  in the order the strip renders them. Adding a widget is therefore two edits, and
  only two:

    1. drop scripts/hub/widgets/<id>.ps1 next to the existing ones, exporting
       Get-Widget<Id> (see docs/hub.md for the full contract);
    2. add one line below.

  The hub derives the module path and the function name from Id, so the registry
  never has to repeat them. Ids are the file name in lower case plus the name of
  the function, so they must stay in sync with the module.

.NOTES
  Icons are [char] code points, not literals. Windows PowerShell 5.1 reads a .ps1
  without a BOM using the ANSI code page, so a literal U+25C9 in this file would
  arrive mojibake on a legacy console. Same reason as status-dashboard.ps1, whose
  dot markers are [char]0x25CF / [char]0x25CB.

  Dot-source it, do not run it:

    . (Join-Path $PSScriptRoot "widgets.ps1")
#>

# Order is the strip order. The key is what the user presses to expand.
$script:HubWidgets = @(
  @{ Id = "OmniRoute"; Key = "1"; Icon = [string][char]0x25C9; Title = "OmniRoute" }
  @{ Id = "Tokens";    Key = "2"; Icon = [string][char]0x03A3; Title = "Tokens" }
  @{ Id = "Config";    Key = "3"; Icon = [string][char]0x2699; Title = "Config" }
)

<#
.SYNOPSIS
  Returns the widget registry.

.NOTES
  Returns a copy of the entries so a caller cannot corrupt the registry by
  assigning into the hashtable it received.
#>
function Get-HubWidget {
  $out = @()
  foreach ($w in $script:HubWidgets) {
    $out += @{ Id = $w.Id; Key = $w.Key; Icon = $w.Icon; Title = $w.Title }
  }
  return $out
}

<#
.SYNOPSIS
  Resolves one registry entry by selection key or by id.

.PARAMETER Key
  Single selection key, for example "1". Case-insensitive, so both the key and the
  id resolve from the same lookup.

.NOTES
  Returns $null for an unknown key. The hub treats that as "key not mine" and
  ignores it: a dock owns only the keys its registry declares.
#>
function Resolve-HubWidget {
  [CmdletBinding()]
  param([string]$Key)

  if (-not $Key) { return $null }
  foreach ($w in $script:HubWidgets) {
    if ($w.Key -eq $Key -or $w.Id -eq $Key) { return $w }
  }
  return $null
}
