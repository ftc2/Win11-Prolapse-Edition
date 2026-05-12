$script:ProlapseLogPath = $null
$script:ProlapseWingetPath = $null

$script:ProlapseWingetNoRetryExitCodeHints = @{
  -1978335215 = 'ERROR: Hash mismatch. Update the package manifest or retry manually with --ignore-security-hash if you trust the installer.'
  -1978335216 = 'ERROR: The installer is not applicable in this context. Try a user-scope install or an elevated/manual install.'
  -1978334972 = 'ERROR: The installer is not applicable in this context. Try a user-scope install or an elevated/manual install.'
  -1978335146 = 'ERROR: The installer requires a different elevation context. Try a non-elevated/manual install.'
  -1978334957 = 'ERROR: The current system configuration does not support this install context. Try a user-scope install.'
}

function Get-ProlapseDesktopPath {
  $desktopPath = [Environment]::GetFolderPath('Desktop')

  if ([string]::IsNullOrWhiteSpace($desktopPath)) {
    $desktopPath = Join-Path -Path $env:USERPROFILE -ChildPath 'Desktop'
  }

  if (-not (Test-Path -LiteralPath $desktopPath)) {
    New-Item -Path $desktopPath -ItemType Directory -Force -ErrorAction Stop | Out-Null
  }

  return $desktopPath
}

function Initialize-ProlapseLog {
  param(
    [string]$Name = 'PostInstall'
  )

  $desktopPath = Get-ProlapseDesktopPath
  $safeName = $Name -replace '[<>:"/\\|?*]', '-'
  $logDir = Join-Path -Path $desktopPath -ChildPath 'Prolapse Logs'

  if (-not (Test-Path -LiteralPath $logDir)) {
    New-Item -Path $logDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
  }

  $script:ProlapseLogPath = Join-Path -Path $logDir -ChildPath "$safeName.log.txt"

  Write-ProlapseLog "Logging to: $script:ProlapseLogPath"
}

function Write-ProlapseLog {
  param([Parameter(Mandatory)][string]$Message)

  $timestamp = Get-Date -Format 'yyyy-MM-dd HH:mm:ss'
  $line = "[$timestamp] $Message"

  Write-Information -MessageData $line -InformationAction Continue

  if ([string]::IsNullOrWhiteSpace($script:ProlapseLogPath)) {
    return
  }

  try {
    Add-Content -LiteralPath $script:ProlapseLogPath -Value $line -Encoding utf8 -ErrorAction Stop
  }
  catch {
    Write-Warning "Failed to write log file: $($_.Exception.Message)"
  }
}

function Join-ProlapseArgumentList {
  param([string[]]$ArgumentList)

  return (($ArgumentList | ForEach-Object {
        if ($_ -match '[\s"]') {
          '"' + ($_ -replace '"', '\"') + '"'
        }
        else {
          $_
        }
      }) -join ' ')
}

function Invoke-ProlapseExe {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$ArgumentList,
    [Parameter(Mandatory)][string]$ActionLabel
  )

  $argumentText = Join-ProlapseArgumentList -ArgumentList $ArgumentList
  Write-ProlapseLog "$($ActionLabel): $FilePath $argumentText"

  try {
    $global:LASTEXITCODE = 0
    $output = & $FilePath @ArgumentList 2>&1
    $exitCode = $global:LASTEXITCODE

    foreach ($line in $output) {
      if ($line -is [System.Management.Automation.ErrorRecord]) {
        $lineText = [string]$line.Exception.Message
      }
      else {
        $lineText = [string]$line
      }

      $lineText = $lineText.TrimEnd()
      if (-not [string]::IsNullOrWhiteSpace($lineText)) {
        Write-ProlapseLog "$($ActionLabel): $lineText"
      }
    }

    Write-ProlapseLog "$($ActionLabel): exit code $exitCode"
    return $exitCode
  }
  catch {
    Write-ProlapseLog "$($ActionLabel): ERROR invoking $($FilePath): $($_.Exception.Message)"
    return 1
  }
}

function Invoke-ProlapseExeWithRetry {
  param(
    [Parameter(Mandatory)][string]$FilePath,
    [Parameter(Mandatory)][string[]]$ArgumentList,
    [Parameter(Mandatory)][string]$ActionLabel,
    [int]$MaxAttempts = 3,
    [int]$DelaySeconds = 20,
    [hashtable]$NoRetryExitCodeHints
  )

  $lastExitCode = $null

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $lastExitCode = Invoke-ProlapseExe -FilePath $FilePath -ArgumentList $ArgumentList -ActionLabel "$ActionLabel (attempt $attempt/$MaxAttempts)"

    if ($lastExitCode -eq 0) {
      return 0
    }

    if ($NoRetryExitCodeHints -and $NoRetryExitCodeHints.ContainsKey($lastExitCode)) {
      Write-ProlapseLog "$($ActionLabel): $($NoRetryExitCodeHints[$lastExitCode])"
      Write-ProlapseLog "$($ActionLabel): Not retrying because this error is non-transient."
      return $lastExitCode
    }

    if ($attempt -lt $MaxAttempts) {
      Write-ProlapseLog "$($ActionLabel): failed with exit code $lastExitCode; retrying in $DelaySeconds seconds..."
      Start-Sleep -Seconds $DelaySeconds
    }
  }

  Write-ProlapseLog "$($ActionLabel): failed after $MaxAttempts attempts (last exit code $lastExitCode)"
  return $lastExitCode
}

function Initialize-ProlapseProcessPath {
  $machinePath = [Environment]::GetEnvironmentVariable('Path', 'Machine')
  $userPath = [Environment]::GetEnvironmentVariable('Path', 'User')

  $env:Path = (($env:Path, $machinePath, $userPath) | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    }) -join ';'
}

function Find-ProlapseWingetPath {
  Initialize-ProlapseProcessPath

  $cmd = Get-Command winget.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) {
    return $cmd.Source
  }

  $candidate = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\winget.exe'
  if ($candidate -and (Test-Path -LiteralPath $candidate)) {
    return $candidate
  }

  return $null
}

function Find-ProlapseGitPath {
  Initialize-ProlapseProcessPath

  $cmd = Get-Command git.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) {
    return $cmd.Source
  }

  $programFilesX86 = [Environment]::GetEnvironmentVariable('ProgramFiles(x86)')
  $candidates = @(
    (Join-Path -Path $env:ProgramFiles -ChildPath 'Git\cmd\git.exe'),
    (Join-Path -Path $env:ProgramFiles -ChildPath 'Git\bin\git.exe'),
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\Git\cmd\git.exe'),
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\Git\bin\git.exe')
  )

  if (-not [string]::IsNullOrWhiteSpace($programFilesX86)) {
    $candidates += @(
      (Join-Path -Path $programFilesX86 -ChildPath 'Git\cmd\git.exe'),
      (Join-Path -Path $programFilesX86 -ChildPath 'Git\bin\git.exe')
    )
  }

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  return $null
}

function Assert-ProlapseWinget {
  $wingetPath = Find-ProlapseWingetPath

  if (-not $wingetPath) {
    throw 'winget.exe was not found. Run the bootstrap first, or install App Installer from Microsoft Store.'
  }

  $exitCode = Invoke-ProlapseExe -FilePath $wingetPath -ArgumentList @('--version') -ActionLabel 'Validate winget'
  if ($exitCode -ne 0) {
    throw "winget.exe was found but is not usable yet (exit code $exitCode): $wingetPath"
  }

  $script:ProlapseWingetPath = $wingetPath
  Write-ProlapseLog "Using winget at: $wingetPath"
  return $wingetPath
}

function Invoke-ProlapseWingetInstall {
  param([Parameter(Mandatory)][hashtable]$App)

  if (-not $script:ProlapseWingetPath) {
    [void](Assert-ProlapseWinget)
  }

  if (-not $App.ContainsKey('Id') -or [string]::IsNullOrWhiteSpace($App.Id)) {
    Write-ProlapseLog 'Skipping app entry without an Id.'

    return [pscustomobject]@{
      Id = $null
      InstallExitCode = $null
      PinExitCode = $null
      InstallSucceeded = $false
      PinRequested = $false
      PinSucceeded = $false
    }
  }

  $machineScope = $true
  if ($App.ContainsKey('MachineScope') -and ($App.MachineScope -is [bool])) {
    $machineScope = $App.MachineScope
  }

  $installArgs = @(
    'install',
    '--id', $App.Id,
    '--exact',
    '--silent',
    '--disable-interactivity',
    '--accept-source-agreements',
    '--accept-package-agreements',
    '--source', 'winget'
  )

  if ($machineScope) {
    $installArgs += @('--scope', 'machine')
  }

  $installExitCode = Invoke-ProlapseExeWithRetry `
    -FilePath $script:ProlapseWingetPath `
    -ArgumentList $installArgs `
    -ActionLabel "Install $($App.Id)" `
    -NoRetryExitCodeHints $script:ProlapseWingetNoRetryExitCodeHints

  $scopeFallbackExitCodes = @(
    -1978335216,
    -1978334972,
    -1978335146,
    -1978334957
  )

  if (($installExitCode -ne 0) -and $machineScope -and ($scopeFallbackExitCodes -contains $installExitCode)) {
    Write-ProlapseLog "Install $($App.Id): machine-scope install failed with scope/context exit code $installExitCode; retrying with user scope."

    $userScopeInstallArgs = @(
      'install',
      '--id', $App.Id,
      '--exact',
      '--silent',
      '--disable-interactivity',
      '--accept-source-agreements',
      '--accept-package-agreements',
      '--source', 'winget',
      '--scope', 'user'
    )

    $installExitCode = Invoke-ProlapseExeWithRetry `
      -FilePath $script:ProlapseWingetPath `
      -ArgumentList $userScopeInstallArgs `
      -ActionLabel "Install $($App.Id) [fallback user scope]" `
      -NoRetryExitCodeHints $script:ProlapseWingetNoRetryExitCodeHints
  }

  $pinRequested = $App.ContainsKey('Pin') -and $App.Pin
  $pinExitCode = $null

  if ($installExitCode -eq 0 -and $pinRequested) {
    $pinArgs = @(
      'pin',
      'add',
      '--id', $App.Id,
      '--exact',
      '--disable-interactivity',
      '--accept-source-agreements',
      '--source', 'winget'
    )

    $pinExitCode = Invoke-ProlapseExe -FilePath $script:ProlapseWingetPath -ArgumentList $pinArgs -ActionLabel "Pin $($App.Id)"
  }
  elseif ($installExitCode -ne 0) {
    Write-ProlapseLog "Install $($App.Id): failed; skipping any post-install action for this app."
  }

  return [pscustomobject]@{
    Id = $App.Id
    InstallExitCode = $installExitCode
    PinExitCode = $pinExitCode
    InstallSucceeded = ($installExitCode -eq 0)
    PinRequested = $pinRequested
    PinSucceeded = (-not $pinRequested -or $pinExitCode -eq 0)
  }
}

function Invoke-ProlapseWingetAppSet {
  param([Parameter(Mandatory)][hashtable[]]$Apps)

  $results = foreach ($app in $Apps) {
    Invoke-ProlapseWingetInstall -App $app
  }

  return $results
}
