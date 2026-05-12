. (Join-Path -Path $PSScriptRoot -ChildPath 'lib/Prolapse.ps1')

$NerdFontFamily = 'meslo'
$NerdFontFace = 'MesloLGM Nerd Font'
$ConfigurePwshProfile = $true
$ConfigureWindowsTerminalFont = $true

$OhMyPoshProfileStartMarker = '# >>> Oh My Posh >>>'
$OhMyPoshProfileEndMarker = '# <<< Oh My Posh <<<'
$OhMyPoshProfileBlock = @'
oh-my-posh init pwsh | Invoke-Expression
'@

function Find-OhMyPoshPath {
  Initialize-ProlapseProcessPath

  $cmd = Get-Command oh-my-posh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) {
    return $cmd.Source
  }

  $candidate = Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\WindowsApps\oh-my-posh.exe'
  if (Test-Path -LiteralPath $candidate) {
    return $candidate
  }

  return $null
}

function Find-PwshPath {
  Initialize-ProlapseProcessPath

  $cmd = Get-Command pwsh.exe -ErrorAction SilentlyContinue | Select-Object -First 1
  if ($cmd -and (Test-Path -LiteralPath $cmd.Source)) {
    return $cmd.Source
  }

  $candidate = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'
  if (Test-Path -LiteralPath $candidate) {
    return $candidate
  }

  return $null
}

function Get-UserPwshProfilePath {
  param([Parameter(Mandatory)][string]$PwshPath)

  $profilePath = & $PwshPath -NoLogo -NoProfile -Command '$PROFILE'
  if ([string]::IsNullOrWhiteSpace($profilePath)) {
    throw 'pwsh returned an empty $PROFILE path.'
  }

  return $profilePath
}

function Write-ProfileBlock {
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

function Get-WindowsTerminalSettingsPath {
  $candidates = @(
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Packages\Microsoft.WindowsTerminalPreview_8wekyb3d8bbwe\LocalState\settings.json'),
    (Join-Path -Path $env:LOCALAPPDATA -ChildPath 'Microsoft\Windows Terminal\settings.json')
  )

  foreach ($candidate in $candidates) {
    if (Test-Path -LiteralPath $candidate) {
      return $candidate
    }
  }

  return $candidates[0]
}

function Get-DefaultWindowsTerminalSetting {
  return [pscustomobject]@{
    '$schema' = 'https://aka.ms/terminal-profiles-schema'
    profiles = [pscustomobject]@{
      defaults = [pscustomobject]@{}
      list = @()
    }
    schemes = @()
    themes = @()
  }
}

function Get-WindowsTerminalSetting {
  param([Parameter(Mandatory)][string]$Path)

  $settingsDir = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $settingsDir)) {
    New-Item -Path $settingsDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
  }

  if (-not (Test-Path -LiteralPath $Path)) {
    Write-ProlapseLog "Windows Terminal settings.json not found; creating minimal settings file at: $Path"
    return Get-DefaultWindowsTerminalSetting
  }

  try {
    $rawJson = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($rawJson)) {
      throw 'settings.json is empty.'
    }

    return ($rawJson | ConvertFrom-Json -ErrorAction Stop)
  }
  catch {
    $backupPath = "$Path.bak"
    Write-ProlapseLog "ERROR parsing Windows Terminal settings; backing up to $backupPath and creating a minimal settings object. $($_.Exception.Message)"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction SilentlyContinue
    return Get-DefaultWindowsTerminalSetting
  }
}

function Initialize-ObjectProperty {
  param(
    [Parameter(Mandatory)]$Object,
    [Parameter(Mandatory)][string]$Name,
    [Parameter(Mandatory)]$Value
  )

  if (-not $Object.PSObject.Properties[$Name]) {
    $Object | Add-Member -NotePropertyName $Name -NotePropertyValue $Value
  }
  elseif ($null -eq $Object.$Name) {
    $Object.$Name = $Value
  }
}

function Initialize-WindowsTerminalSettingShape {
  param([Parameter(Mandatory)]$Settings)

  Initialize-ObjectProperty -Object $Settings -Name 'profiles' -Value ([pscustomobject]@{})
  Initialize-ObjectProperty -Object $Settings.profiles -Name 'defaults' -Value ([pscustomobject]@{})
  Initialize-ObjectProperty -Object $Settings.profiles -Name 'list' -Value @()
  Initialize-ObjectProperty -Object $Settings -Name 'schemes' -Value @()
  Initialize-ObjectProperty -Object $Settings -Name 'themes' -Value @()
}

function Write-WindowsTerminalSetting {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Settings
  )

  $json = $Settings | ConvertTo-Json -Depth 50
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)

  Write-ProlapseLog "Wrote Windows Terminal settings: $Path"
}

Initialize-ProlapseLog -Name 'Oh-My-Posh'
Write-ProlapseLog 'Oh My Posh setup started.'

[void](Assert-ProlapseWinget)

$installResult = Invoke-ProlapseWingetInstall -App @{
  Id = 'JanDeDobbeleer.OhMyPosh'
  MachineScope = $false
}

if (-not $installResult.InstallSucceeded) {
  Write-ProlapseLog "Oh My Posh install failed with exit code: $($installResult.InstallExitCode)"
  exit 1
}

$ompPath = Find-OhMyPoshPath
if (-not $ompPath) {
  Write-ProlapseLog 'Oh My Posh executable not found after install.'
  exit 1
}

$fontInstallExitCode = Invoke-ProlapseExe `
  -FilePath $ompPath `
  -ArgumentList @('font', 'install', $NerdFontFamily) `
  -ActionLabel "Oh My Posh font install ($NerdFontFamily)"

$configuredNerdFont = ($fontInstallExitCode -eq 0)
if (-not $configuredNerdFont) {
  Write-ProlapseLog "Nerd font install returned non-zero exit code ($fontInstallExitCode); skipping Windows Terminal font face update."
}

$hadErrors = $false

if ($ConfigurePwshProfile) {
  try {
    $pwshPath = Find-PwshPath
    if (-not $pwshPath) {
      throw 'pwsh.exe was not found.'
    }

    $profilePath = Get-UserPwshProfilePath -PwshPath $pwshPath
    Write-ProfileBlock `
      -ProfilePath $profilePath `
      -StartMarker $OhMyPoshProfileStartMarker `
      -EndMarker $OhMyPoshProfileEndMarker `
      -BlockContent $OhMyPoshProfileBlock

    Write-ProlapseLog "Updated pwsh profile: $profilePath"
  }
  catch {
    Write-ProlapseLog "ERROR configuring pwsh profile for Oh My Posh: $($_.Exception.Message)"
    $hadErrors = $true
  }
}
else {
  Write-ProlapseLog 'Skipping pwsh profile configuration by config.'
}

if ($ConfigureWindowsTerminalFont -and $configuredNerdFont) {
  try {
    $settingsPath = Get-WindowsTerminalSettingsPath
    Write-ProlapseLog "Using Windows Terminal settings path: $settingsPath"

    $settings = Get-WindowsTerminalSetting -Path $settingsPath
    Initialize-WindowsTerminalSettingShape -Settings $settings
    Initialize-ObjectProperty -Object $settings.profiles.defaults -Name 'font' -Value ([pscustomobject]@{})

    $settings.profiles.defaults.font | Add-Member -NotePropertyName 'face' -NotePropertyValue $NerdFontFace -Force
    Write-ProlapseLog "Set Windows Terminal default font face: $NerdFontFace"

    Write-WindowsTerminalSetting -Path $settingsPath -Settings $settings
  }
  catch {
    Write-ProlapseLog "ERROR configuring Windows Terminal font: $($_.Exception.Message)"
    $hadErrors = $true
  }
}
elseif (-not $ConfigureWindowsTerminalFont) {
  Write-ProlapseLog 'Skipping Windows Terminal font configuration by config.'
}

if ($hadErrors) {
  Write-ProlapseLog 'Oh My Posh setup completed with errors.'
  exit 1
}

Write-ProlapseLog 'Oh My Posh setup complete.'
exit 0
