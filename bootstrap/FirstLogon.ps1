# ==========================
# CONFIG SECTION
# ==========================

# winget package list
# Pin: $true for apps that self-auto-update (so winget upgrade will not fight them)
# MachineScope [$true]: $false for user-scope installs
$Apps = @(
  @{ Id = 'Microsoft.VisualStudioCode'; Pin = $true }
  @{ Id = 'Git.Git' }
  @{ Id = 'Microsoft.PowerShell' } # pwsh v7
)

$GIT_REPO = 'https://github.com/ftc2/Win11-Prolapse-Edition.git'

# Leave empty to derive the folder name from $GIT_REPO.
$RepoDesktopFolderName = 'Win11 Prolapse Edition'

$WingetTabCompletionStartMarker = '# >>> winget tab completion >>>'
$WingetTabCompletionEndMarker = '# <<< winget tab completion <<<'
$WingetTabCompletionBlock = @'
# https://learn.microsoft.com/en-us/windows/package-manager/winget/tab-completion
Register-ArgumentCompleter -Native -CommandName winget -ScriptBlock {
  param($wordToComplete, $commandAst, $cursorPosition)
    [Console]::InputEncoding = [Console]::OutputEncoding = $OutputEncoding = [System.Text.Utf8Encoding]::new()
    $Local:word = $wordToComplete.Replace('"', '""')
    $Local:ast = $commandAst.ToString().Replace('"', '""')
    winget complete --word="$Local:word" --commandline "$Local:ast" --position $cursorPosition | ForEach-Object {
      [System.Management.Automation.CompletionResult]::new($_, $_, 'ParameterValue', $_)
    }
}
'@

# ==========================
# BOOTSTRAP-SPECIFIC FUNCTIONS
# ==========================

function Wait-BootstrapWinget {
  param(
    [int]$MaxAttempts = 60,
    [int]$DelaySeconds = 10
  )

  for ($attempt = 1; $attempt -le $MaxAttempts; $attempt++) {
    $wingetPath = Find-ProlapseWingetPath

    if ($wingetPath) {
      $exitCode = Invoke-ProlapseExe -FilePath $wingetPath -ArgumentList @('--version') -ActionLabel "Validate winget (attempt $attempt/$MaxAttempts)"

      if ($exitCode -eq 0) {
        Write-ProlapseLog "Using winget at: $wingetPath"
        return $wingetPath
      }

      Write-ProlapseLog "winget.exe was found but is not ready yet (exit code $exitCode). Retrying in $DelaySeconds seconds..."
    }
    else {
      Write-ProlapseLog "winget.exe not found (attempt $attempt/$MaxAttempts). Retrying in $DelaySeconds seconds..."
    }

    Start-Sleep -Seconds $DelaySeconds
  }

  throw "winget.exe was not ready after $($MaxAttempts * $DelaySeconds) seconds."
}

function Get-BootstrapPowerShellProfilePath {
  $documentsPath = Join-Path -Path $env:USERPROFILE -ChildPath 'Documents'
  return (Join-Path -Path $documentsPath -ChildPath 'PowerShell\Microsoft.PowerShell_profile.ps1')
}

function Write-BootstrapProfileBlock {
  param(
    [Parameter(Mandatory)][string]$ProfilePath,
    [Parameter(Mandatory)][string]$StartMarker,
    [Parameter(Mandatory)][string]$EndMarker,
    [Parameter(Mandatory)][string]$BlockContent
  )

  $profileDir = Split-Path -Path $ProfilePath -Parent
  if (-not (Test-Path -LiteralPath $profileDir)) {
    New-Item -Path $profileDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
  }

  $newBlock = "$StartMarker`r`n$BlockContent`r`n$EndMarker"

  if (Test-Path -LiteralPath $ProfilePath) {
    $current = Get-Content -LiteralPath $ProfilePath -Raw -ErrorAction Stop
  }
  else {
    $current = ''
  }

  $startIndex = $current.IndexOf($StartMarker)
  $endIndex = $current.IndexOf($EndMarker)

  if (($startIndex -ge 0) -and ($endIndex -gt $startIndex)) {
    $endIndex += $EndMarker.Length
    $prefix = $current.Substring(0, $startIndex).TrimEnd()
    $suffix = $current.Substring($endIndex).TrimStart()
    $parts = @($prefix, $newBlock, $suffix) | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    }
    $updated = ($parts -join "`r`n`r`n") + "`r`n"
  }
  else {
    $parts = @($current.TrimEnd(), $newBlock) | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    }
    $updated = ($parts -join "`r`n`r`n") + "`r`n"
  }

  Set-Content -LiteralPath $ProfilePath -Value $updated -Encoding utf8 -ErrorAction Stop
}

function Install-BootstrapWingetTabCompletion {
  try {
    $profilePath = Get-BootstrapPowerShellProfilePath

    Write-BootstrapProfileBlock `
      -ProfilePath $profilePath `
      -StartMarker $WingetTabCompletionStartMarker `
      -EndMarker $WingetTabCompletionEndMarker `
      -BlockContent $WingetTabCompletionBlock

    Write-ProlapseLog "Installed winget tab completion profile block: $profilePath"
  }
  catch {
    Write-ProlapseLog "ERROR installing winget tab completion: $($_.Exception.Message)"
  }
}

function Get-BootstrapRepoFolderName {
  param([Parameter(Mandatory)][string]$RepoUri)

  $repoLeaf = (($RepoUri.Trim().TrimEnd('/') -split '[\\/]') | Where-Object {
      -not [string]::IsNullOrWhiteSpace($_)
    } | Select-Object -Last 1)

  $repoLeaf = $repoLeaf -replace '[?#].*$', ''
  $repoLeaf = $repoLeaf -replace '\.git$', ''
  $repoLeaf = $repoLeaf -replace '[<>:"/\\|?*]', '-'

  if ([string]::IsNullOrWhiteSpace($repoLeaf)) {
    return 'Win11-Setup'
  }

  return $repoLeaf
}

function Get-BootstrapFollowupRepoPath {
  if ([string]::IsNullOrWhiteSpace($GIT_REPO)) {
    return $null
  }

  $repoFolderName = $RepoDesktopFolderName
  if ([string]::IsNullOrWhiteSpace($repoFolderName)) {
    $repoFolderName = Get-BootstrapRepoFolderName -RepoUri $GIT_REPO
  }

  $desktopPath = Get-ProlapseDesktopPath
  return (Join-Path -Path $desktopPath -ChildPath $repoFolderName)
}

function Sync-BootstrapFollowupRepo {
  if ([string]::IsNullOrWhiteSpace($GIT_REPO)) {
    Write-ProlapseLog 'GIT_REPO is empty; skipping follow-up script repo clone/pull.'
    return $null
  }

  $gitPath = Find-ProlapseGitPath
  if (-not $gitPath) {
    Write-ProlapseLog 'git.exe was not found after installing Git.Git; skipping follow-up script repo clone/pull.'
    return $null
  }

  $repoPath = Get-BootstrapFollowupRepoPath
  $gitDir = Join-Path -Path $repoPath -ChildPath '.git'

  if (Test-Path -LiteralPath $repoPath) {
    if (Test-Path -LiteralPath $gitDir) {
      [void](Invoke-ProlapseExeWithRetry `
          -FilePath $gitPath `
          -ArgumentList @('-C', $repoPath, 'pull', '--ff-only') `
          -ActionLabel "Update follow-up repo at $repoPath")
    }
    else {
      Write-ProlapseLog "Follow-up repo destination already exists but is not a git repo; skipping: $repoPath"
    }

    return $repoPath
  }

  [void](Invoke-ProlapseExeWithRetry `
      -FilePath $gitPath `
      -ArgumentList @('clone', $GIT_REPO, $repoPath) `
      -ActionLabel "Clone follow-up repo to $repoPath")

  return $repoPath
}

function Find-BootstrapVsCodeCliPath {
  Initialize-ProlapseProcessPath

  $commands = @('code.cmd', 'code.exe', 'code')
  foreach ($commandName in $commands) {
    $command = Get-Command $commandName -ErrorAction SilentlyContinue | Select-Object -First 1
    if ($command -and (Test-Path -LiteralPath $command.Source)) {
      return $command.Source
    }
  }

  $candidates = @(
    (Join-Path -Path $env:ProgramFiles -ChildPath 'Microsoft VS Code\bin\code.cmd'),
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Programs\Microsoft VS Code\bin\code.cmd')
  )

  foreach ($candidate in $candidates) {
    if ($candidate -and (Test-Path -LiteralPath $candidate)) {
      return $candidate
    }
  }

  return $null
}

function Open-BootstrapWorkspaceInVSCode {
  param([string]$RepoPath)

  $codeCliPath = Find-BootstrapVsCodeCliPath
  if (-not $codeCliPath) {
    Write-ProlapseLog 'VS Code CLI was not found. Skipping automatic workspace open.'
    return
  }

  $desktopPath = Get-ProlapseDesktopPath
  $logDir = Join-Path -Path $desktopPath -ChildPath 'Prolapse Logs'
  $targets = @()

  if (-not [string]::IsNullOrWhiteSpace($RepoPath) -and (Test-Path -LiteralPath $RepoPath)) {
    $targets += $RepoPath
  }

  if (Test-Path -LiteralPath $logDir) {
    $targets += $logDir
  }

  if (-not [string]::IsNullOrWhiteSpace($script:ProlapseLogPath) -and (Test-Path -LiteralPath $script:ProlapseLogPath)) {
    $targets += $script:ProlapseLogPath
  }

  if ($targets.Count -eq 0) {
    Write-ProlapseLog 'No valid VS Code open targets found. Skipping automatic workspace open.'
    return
  }

  [void](Invoke-ProlapseExe `
      -FilePath $codeCliPath `
      -ArgumentList $targets `
      -ActionLabel 'Open bootstrap workspace in VS Code')
}

function Invoke-BootstrapWingetPreInstallMaintenance {
  param(
    [Parameter(Mandatory)][string]$WingetPath
  )

  # a lot of times, a winget pkg won't install due to out-of-date hash
  # for convenience, allow users to use --ignore-security-hash at their discretion.
  $hashOverrideExitCode = Invoke-ProlapseExeWithRetry `
    -FilePath $WingetPath `
    -ArgumentList @('settings', '--enable', 'InstallerHashOverride') `
    -ActionLabel 'Enable winget InstallerHashOverride'

  if ($hashOverrideExitCode -ne 0) {
    Write-ProlapseLog "Enable winget InstallerHashOverride: non-zero exit code ($hashOverrideExitCode). Continuing."
  }

  $upgradeExitCode = Invoke-ProlapseExeWithRetry `
    -FilePath $WingetPath `
    -ArgumentList @(
      'upgrade',
      '--all',
      '--silent',
      '--disable-interactivity',
      '--accept-source-agreements',
      '--accept-package-agreements',
      '--source', 'winget'
    ) `
    -ActionLabel 'Upgrade all'

  if ($upgradeExitCode -ne 0) {
    Write-ProlapseLog "Upgrade all: non-zero exit code ($upgradeExitCode). Continuing."
  }
}

# ==========================
# LIB COPIED LINE-FOR-LINE FROM post-install/lib/Prolapse.ps1
# ==========================
# BEGIN COPIED LIB: post-install/lib/Prolapse.ps1
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
# END COPIED LIB

# ==========================
# ACTUAL BOOTSTRAP ACTIONS
# ==========================

Initialize-ProlapseLog -Name 'FirstLogon'
Write-ProlapseLog 'FirstLogon bootstrap started.'

try {
  $script:ProlapseWingetPath = Wait-BootstrapWinget
}
catch {
  Write-ProlapseLog "ERROR: $($_.Exception.Message)"
  throw
}

[void](Invoke-BootstrapWingetPreInstallMaintenance -WingetPath $script:ProlapseWingetPath)

foreach ($app in $Apps) {
  [void](Invoke-ProlapseWingetInstall -App $app)
}

Install-BootstrapWingetTabCompletion
$followupRepoPath = Sync-BootstrapFollowupRepo
Open-BootstrapWorkspaceInVSCode -RepoPath $followupRepoPath

Write-ProlapseLog 'FirstLogon bootstrap complete.'
