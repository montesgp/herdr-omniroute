<#
.SYNOPSIS
  Opens the Herdr Hub menu, once, in the current context.

.DESCRIPTION
  The menu pane is declared with placement = "popup", which is a session-modal
  terminal: it takes all terminal input, reserves no space in the tiled layout and
  closes on its own when its command exits. The running command is therefore the
  state, so there is nothing to probe and no existing-pane detection to keep in
  sync. The menu closes on q/Q/Escape, or at its -MaxSeconds cap; every key outside
  that set is ignored, because a session modal swallows the whole byte stream and
  an any-key rule lets ambient input dismiss it.

  One windowless call, through the helper in lib\Invoke-Native.ps1, so opening the
  menu never flashes a console window.

.EXAMPLE
  .\open-menu.ps1
#>
$ErrorActionPreference = "SilentlyContinue"

$herdr = if ($env:HERDR_BIN_PATH) { $env:HERDR_BIN_PATH } else { "herdr" }

# Combined rather than Join-Path: the first Join-Path in a process autoloads
# Microsoft.PowerShell.Management, which measures ~95 ms.
$lib = [System.IO.Path]::GetFullPath([System.IO.Path]::Combine($PSScriptRoot, "..", "lib", "Invoke-Native.ps1"))
if (-not [System.IO.File]::Exists($lib)) {
  Write-Output ("Herdr Hub: falta el helper " + $lib)
  exit 1
}
. $lib

try {
  $r = Invoke-NativeText -FilePath $herdr -Arguments @(
    "plugin", "pane", "open",
    "--plugin", "herdr.omniroute",
    "--entrypoint", "menu"
  ) -TimeoutMs 20000

  $text = ""
  if ($r.Text) { $text = (([string]$r.Text) -replace "\s+", " ").Trim() }

  if ($text -match "ui_busy") {
    Write-Output "Herdr Hub: otro modal activo, cerra el menu actual."
    exit 0
  }
  if ($r.ExitCode -ne 0) {
    Write-Output ("Herdr Hub: no se pudo abrir el menu - " + $text)
    exit 1
  }

  Write-Output "Herdr Hub: menu abierto (1-4 elige, q cierra)."
  exit 0
} catch {
  Write-Output ("Herdr Hub: apertura fallida - " + $_.Exception.Message)
  exit 1
}
