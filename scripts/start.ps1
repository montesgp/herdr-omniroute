$ErrorActionPreference = "Stop"
$port = 20128
if ((netstat -an | Select-String -Pattern ":$port\s+.*LISTENING").Count -gt 0) { Write-Output "OmniRoute: already UP on $port"; exit 0 }
$node = "C:\Users\patri\scoop\persist\fnm\node-versions\v22.22.3\installation\node.exe"
$entry = "C:\Users\patri\node_modules\omniroute\bin\omniroute.mjs"
try {
  Start-Process -FilePath $node -ArgumentList "`"$entry`"","serve","--daemon","--no-open" -WindowStyle Hidden
  Write-Output "OmniRoute: starting daemon... (status in ~15s)"
  exit 0
} catch {
  Write-Output "OmniRoute: start FAILED - $($_.Exception.Message)"
  exit 2
}
