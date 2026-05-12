# Pin [$false]: set $true for apps that can update themselves, so winget upgrade will not fight them.
# MachineScope [$true]: $false for user-scope installs.
$Apps = @(
  # browsers
  @{ Id = 'Mozilla.Firefox'; Pin = $true }
  @{ Id = 'Google.Chrome'; Pin = $true }

  # utils
  # @{ Id = '7zip.7zip' }
  @{ Id = 'M2Team.NanaZip.Preview' } # imo better than 7zip
  @{ Id = 'SumatraPDF.SumatraPDF' }
  @{ Id = 'CPUID.CPU-Z' }
  @{ Id = 'Bitwarden.Bitwarden'; Pin = $true }
  @{ Id = 'AutoHotkey.AutoHotkey' }

  # look/feel
  @{ Id = 'Open-Shell.Open-Shell-Menu' }
  @{ Id = 'zhongyang219.TrafficMonitor.Full' }
  @{ Id = 'derceg.Explorer++' }

  # dev extras
  @{ Id = 'Microsoft.Sysinternals.Suite' }
  @{ Id = 'astral-sh.uv' }

  # multimedia
  @{ Id = 'VideoLAN.VLC' }
  @{ Id = 'Spotify.Spotify'; Pin = $true; MachineScope = $false }
  @{ Id = 'Jellyfin.JellyfinMediaPlayer' }
  @{ Id = 'yt-dlp.yt-dlp' }

  # gayming
  @{ Id = 'Hawaii_Beach.TinyNvidiaUpdateChecker'; MachineScope = $false }
  @{ Id = 'Guru3D.Afterburner' }
  @{ Id = 'Unigine.HeavenBenchmark' }
  @{ Id = 'Discord.Discord'; Pin = $true; MachineScope = $false }
  @{ Id = 'Vendicated.Vencord'; Pin = $true; MachineScope = $false }
  @{ Id = 'Valve.Steam'; Pin = $true }
  @{ Id = 'EpicGames.EpicGamesLauncher'; Pin = $true }
)

$principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
  if ([string]::IsNullOrWhiteSpace($PSCommandPath)) {
    throw 'Cannot self-elevate: PSCommandPath is empty.'
  }

  $hostExePath = (Get-Process -Id $PID -ErrorAction Stop).Path
  $elevated = Start-Process -FilePath $hostExePath -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $PSCommandPath) -Verb RunAs -PassThru -Wait -ErrorAction Stop
  exit $elevated.ExitCode
}

. (Join-Path -Path $PSScriptRoot -ChildPath 'lib/Prolapse.ps1')

Initialize-ProlapseLog -Name 'Apps'
Write-ProlapseLog 'Apps started.'

[void](Assert-ProlapseWinget)
$results = Invoke-ProlapseWingetAppSet -Apps $Apps

$installFailures = @($results | Where-Object { -not $_.InstallSucceeded })
$pinFailures = @($results | Where-Object { $_.PinRequested -and -not $_.PinSucceeded })

Write-ProlapseLog "Apps complete. Installed: $(@($results | Where-Object { $_.InstallSucceeded }).Count)/$($results.Count). Pin failures: $($pinFailures.Count)."

if ($installFailures.Count -gt 0) {
  Write-ProlapseLog "Install failures: $($installFailures.Id -join ', ')"
  exit 1
}

exit 0
