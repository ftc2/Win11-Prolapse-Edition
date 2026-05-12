. (Join-Path -Path $PSScriptRoot -ChildPath 'lib/Prolapse.ps1')

$Pwsh7Path = Join-Path -Path $env:ProgramFiles -ChildPath 'PowerShell\7\pwsh.exe'

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

  throw 'Windows Terminal settings.json was not found. Open Windows Terminal once, close it, and run this script again.'
}

function Get-Pwsh7TerminalProfile {
  param(
    [Parameter(Mandatory)][object[]]$Profiles,
    [Parameter(Mandatory)][string]$PwshPath
  )

  $matchedProfile = $Profiles | Where-Object {
    $_.source -is [string] -and $_.source -eq 'Windows.Terminal.PowershellCore'
  } | Select-Object -First 1

  if ($matchedProfile) {
    return $matchedProfile
  }

  $matchedProfile = $Profiles | Where-Object {
    $_.commandline -is [string] -and $_.commandline -match '(?i)pwsh(?:\.exe)?'
  } | Select-Object -First 1

  if ($matchedProfile) {
    return $matchedProfile
  }

  return ($Profiles | Where-Object {
      $_.commandline -is [string] -and $_.commandline -eq $PwshPath
    } | Select-Object -First 1)
}

function Write-JsonNoBom {
  param(
    [Parameter(Mandatory)][string]$Path,
    [Parameter(Mandatory)]$Object
  )

  $json = $Object | ConvertTo-Json -Depth 50
  $utf8NoBom = [System.Text.UTF8Encoding]::new($false)
  [System.IO.File]::WriteAllText($Path, $json, $utf8NoBom)
}

Initialize-ProlapseLog -Name 'Default-Terminal-Pwsh7'
Write-ProlapseLog 'Default-Terminal-Pwsh7 started.'

$settingsPath = Get-WindowsTerminalSettingsPath
Write-ProlapseLog "Using Windows Terminal settings path: $settingsPath"

$json = Get-Content -LiteralPath $settingsPath -Raw -ErrorAction Stop | ConvertFrom-Json -ErrorAction Stop

if (-not $json.profiles -or -not $json.profiles.list -or $json.profiles.list.Count -eq 0) {
  throw "Windows Terminal profiles.list is missing or empty in: $settingsPath"
}

$pwshProfile = Get-Pwsh7TerminalProfile -Profiles $json.profiles.list -PwshPath $Pwsh7Path
if (-not $pwshProfile -or -not $pwshProfile.guid) {
  throw 'Could not find a pwsh7 profile with a GUID in Windows Terminal settings.'
}

$json.defaultProfile = $pwshProfile.guid
Write-JsonNoBom -Path $settingsPath -Object $json

Write-ProlapseLog "Windows Terminal defaultProfile set to pwsh7 GUID: $($pwshProfile.guid)"
Write-ProlapseLog 'Default-Terminal-Pwsh7 complete.'
