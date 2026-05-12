. (Join-Path -Path $PSScriptRoot -ChildPath 'lib/Prolapse.ps1')

$DefaultCatppuccinFlavor = 'mocha' # color scheme (actual term colors)
$CatppuccinTheme = 'frappe' # Terminal app theme (the surrounding controls)

$CatppuccinRawBaseUrl = 'https://raw.githubusercontent.com/catppuccin/windows-terminal/main'
$CatppuccinFlavors = @('latte', 'frappe', 'macchiato', 'mocha')
$SetExistingProfilesToDefaultScheme = $false

function Get-CatppuccinName {
  param([Parameter(Mandatory)][string]$Flavor)

  if ([string]::IsNullOrWhiteSpace($Flavor)) {
    throw 'Catppuccin flavor cannot be empty.'
  }

  $normalized = $Flavor.Substring(0, 1).ToUpperInvariant()
  if ($Flavor.Length -gt 1) {
    $normalized += $Flavor.Substring(1).ToLowerInvariant()
  }

  return "Catppuccin $normalized"
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

function Get-MinimalWindowsTerminalSetting {
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

function Read-WindowsTerminalSetting {
  param([Parameter(Mandatory)][string]$Path)

  $settingsDir = Split-Path -Path $Path -Parent
  if (-not (Test-Path -LiteralPath $settingsDir)) {
    New-Item -Path $settingsDir -ItemType Directory -Force -ErrorAction Stop | Out-Null
  }

  if (-not (Test-Path -LiteralPath $Path)) {
    Write-ProlapseLog "Windows Terminal settings.json not found; creating minimal settings at: $Path"
    return Get-MinimalWindowsTerminalSetting
  }

  try {
    $raw = Get-Content -LiteralPath $Path -Raw -ErrorAction Stop
    if ([string]::IsNullOrWhiteSpace($raw)) {
      throw 'settings.json is empty.'
    }

    return ($raw | ConvertFrom-Json -ErrorAction Stop)
  }
  catch {
    $backupPath = "$Path.bak"
    Write-ProlapseLog "ERROR parsing settings.json; backing up to $backupPath and recreating minimal object. $($_.Exception.Message)"
    Copy-Item -LiteralPath $Path -Destination $backupPath -Force -ErrorAction SilentlyContinue
    return Get-MinimalWindowsTerminalSetting
  }
}

function Get-FlatArray {
  param([Parameter(Mandatory)]$Value)

  $flat = @()
  foreach ($entry in @($Value)) {
    if ($entry -is [System.Array]) {
      $flat += @(Get-FlatArray -Value $entry)
    }
    else {
      $flat += $entry
    }
  }

  return @($flat)
}

function Get-MergedNamedItem {
  param(
    [Parameter(Mandatory)]$Items,
    [Parameter(Mandatory)]$Item
  )

  if (-not $Item.PSObject.Properties['name'] -or [string]::IsNullOrWhiteSpace($Item.name)) {
    throw 'Item is missing a non-empty top-level name property.'
  }

  $itemsArray = @(Get-FlatArray -Value $Items)
  $filtered = @($itemsArray | Where-Object {
      $null -eq $_ -or -not $_.PSObject.Properties['name'] -or $_.name -ne $Item.name
    })
  $filtered += $Item

  return @($filtered)
}

function Get-CatppuccinJson {
  param([Parameter(Mandatory)][string]$Url)

  Write-ProlapseLog "Fetching: $Url"

  try {
    $invokeRestMethodParams = @{
      Uri = $Url
      Method = 'Get'
      ErrorAction = 'Stop'
    }

    if ((Get-Command Invoke-RestMethod).Parameters.ContainsKey('ProgressAction')) {
      $invokeRestMethodParams['ProgressAction'] = 'SilentlyContinue'
    }

    return (Invoke-RestMethod @invokeRestMethodParams)
  }
  catch {
    throw "Failed to fetch Catppuccin JSON from $($Url): $($_.Exception.Message)"
  }
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

Initialize-ProlapseLog -Name 'Catppuccin-Terminal-Colors'
Write-ProlapseLog 'Catppuccin Terminal color setup started.'

if ($CatppuccinFlavors -notcontains $DefaultCatppuccinFlavor) {
  throw "DefaultCatppuccinFlavor '$DefaultCatppuccinFlavor' is not in CatppuccinFlavors: $($CatppuccinFlavors -join ', ')"
}

if ($CatppuccinFlavors -notcontains $CatppuccinTheme) {
  throw "CatppuccinTheme '$CatppuccinTheme' is not in CatppuccinFlavors: $($CatppuccinFlavors -join ', ')"
}

$settingsPath = Get-WindowsTerminalSettingsPath
Write-ProlapseLog "Using Windows Terminal settings path: $settingsPath"

$settings = Read-WindowsTerminalSetting -Path $settingsPath

if (-not $settings.PSObject.Properties['profiles'] -or $null -eq $settings.profiles) {
  $settings | Add-Member -NotePropertyName 'profiles' -NotePropertyValue ([pscustomobject]@{}) -Force
}

if (-not $settings.profiles.PSObject.Properties['defaults'] -or $null -eq $settings.profiles.defaults) {
  $settings.profiles | Add-Member -NotePropertyName 'defaults' -NotePropertyValue ([pscustomobject]@{}) -Force
}

if (-not $settings.profiles.PSObject.Properties['list'] -or $null -eq $settings.profiles.list) {
  $settings.profiles | Add-Member -NotePropertyName 'list' -NotePropertyValue @() -Force
}

if (-not $settings.PSObject.Properties['schemes'] -or $null -eq $settings.schemes) {
  $settings | Add-Member -NotePropertyName 'schemes' -NotePropertyValue @() -Force
}

if (-not $settings.PSObject.Properties['themes'] -or $null -eq $settings.themes) {
  $settings | Add-Member -NotePropertyName 'themes' -NotePropertyValue @() -Force
}

$settings.schemes = @(Get-FlatArray -Value $settings.schemes)
$settings.themes = @(Get-FlatArray -Value $settings.themes)

foreach ($flavor in $CatppuccinFlavors) {
  $scheme = Get-CatppuccinJson -Url "$CatppuccinRawBaseUrl/$flavor.json"
  $theme = Get-CatppuccinJson -Url "$CatppuccinRawBaseUrl/$($flavor)Theme.json"

  $settings.schemes = Get-MergedNamedItem -Items $settings.schemes -Item $scheme
  $settings.themes = Get-MergedNamedItem -Items $settings.themes -Item $theme

  Write-ProlapseLog "Installed scheme: $($scheme.name)"
  Write-ProlapseLog "Installed theme: $($theme.name)"
}

$settings.schemes = @(Get-FlatArray -Value $settings.schemes)
$settings.themes = @(Get-FlatArray -Value $settings.themes)

$defaultSchemeName = Get-CatppuccinName -Flavor $DefaultCatppuccinFlavor
$themeName = Get-CatppuccinName -Flavor $CatppuccinTheme

$schemeNames = @($settings.schemes | ForEach-Object { $_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })
$themeNames = @($settings.themes | ForEach-Object { $_.name } | Where-Object { -not [string]::IsNullOrWhiteSpace($_) })

if ($schemeNames -notcontains $defaultSchemeName) {
  throw "Default scheme '$defaultSchemeName' was not found in settings.schemes."
}

if ($themeNames -notcontains $themeName) {
  throw "Theme '$themeName' was not found in settings.themes."
}

$settings.profiles.defaults | Add-Member -NotePropertyName 'colorScheme' -NotePropertyValue $defaultSchemeName -Force
$settings | Add-Member -NotePropertyName 'theme' -NotePropertyValue $themeName -Force

Write-ProlapseLog "Set default profile color scheme: $defaultSchemeName"
Write-ProlapseLog "Set Terminal theme: $themeName"

if ($SetExistingProfilesToDefaultScheme -and $settings.profiles.list.Count -gt 0) {
  foreach ($terminalProfile in $settings.profiles.list) {
    $terminalProfile | Add-Member -NotePropertyName 'colorScheme' -NotePropertyValue $defaultSchemeName -Force
  }

  Write-ProlapseLog "Applied '$defaultSchemeName' to all existing profiles."
}

Write-WindowsTerminalSetting -Path $settingsPath -Settings $settings
Write-ProlapseLog 'Catppuccin Terminal color setup complete. Restart Windows Terminal if it was open.'
