# powercfg settings
# this script is generally recommended for gayming desktops
# it just enables the 'High Performance' power plan, sets monitor sleep to 15min, and sets standby to 2h
# https://www.youtube.com/watch?v=j-KGdLpGshQ

$ApplyHighPerformance = $true
$MonitorTimeoutACMinutes = 15 # default: 15 min
$StandbyTimeoutACMinutes = 120 # default: 0

$HighPerformanceSchemeGuid = '8c5e7fda-e8bf-4a96-9a85-a6e23a8c635c'
$powercfgPath = Join-Path -Path $env:WINDIR -ChildPath 'System32\powercfg.exe'

if (-not (Test-Path -LiteralPath $powercfgPath)) {
  throw "powercfg.exe was not found: $powercfgPath"
}

if ($ApplyHighPerformance) {
  & $powercfgPath /SetActive $HighPerformanceSchemeGuid
  if ($LASTEXITCODE -ne 0) {
    throw "Failed to set High Performance power plan. Exit code: $LASTEXITCODE"
  }
}

& $powercfgPath /change monitor-timeout-ac $MonitorTimeoutACMinutes
if ($LASTEXITCODE -ne 0) {
  throw "Failed to set monitor-timeout-ac. Exit code: $LASTEXITCODE"
}

& $powercfgPath /change standby-timeout-ac $StandbyTimeoutACMinutes
if ($LASTEXITCODE -ne 0) {
  throw "Failed to set standby-timeout-ac. Exit code: $LASTEXITCODE"
}
