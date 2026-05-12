# Windows 11 *Prolapse Edition™*

*Goal: a **conservatively** debloated, not-fucked-up Win11*
- Win11 Enterprise (relatively debloated by default)

[`autounattend.xml`](https://learn.microsoft.com/en-us/windows-hardware/manufacture/desktop/automate-windows-setup?view=windows-11) is used to streamline installation:
- various tweaks
- noninteractively partition your drive with 512MiB EFI System Partition (ESP) and 1GiB Windows recovery partition, but **it will pause and ask you to press a key before doing so**.
- offline, local windows account
- [`FirstLogon.ps1`](bootstrap/FirstLogon.ps1) bootstrap script
  - baked into `autounattend.xml`
  - logs to `Prolapse Logs` dir on your desktop
  - installs git, vscode, and pwsh v7 (v5 ships with windows) via `winget`
  - adds [winget tab completion](https://learn.microsoft.com/en-us/windows/package-manager/winget/tab-completion) to your pwsh 7 `$PROFILE`
  - pulls this repo to your Desktop for manual post-install customization
- automatically activates windows with [massgrave MAS](https://github.com/massgravel/Microsoft-Activation-Scripts)

## post-install scripts
the bootstrap script automatically pulls this repo to your desktop. included are some *optional* post-install scripts that you can edit with vscode and then run if you like:
- [`Apps.ps1`](post-install/Apps.ps1): installs a variety of apps via `winget`. edit this for sure.
- [`Default-Terminal-Pwsh7.ps1`](post-install/Default-Terminal-Pwsh7.ps1): sets pwsh 7 as your default shell in Windows Terminal
- [`Catppuccin-Terminal-Colors.ps1`](post-install/Catppuccin-Terminal-Colors.ps1): installs catppuccin colors (all flavors) for Windows Terminal from their [official repo](https://github.com/catppuccin/windows-terminal).
    - mocha color scheme (actual term colors) and frappe app theme (the surrounding controls) are used by default, but you can edit the script to change that. obviously, you can also manually change it after running the script if you don't like my choice.
- [`Oh-My-Posh.ps1`](post-install/Oh-My-Posh.ps1):
  - installs [Oh My Posh](https://ohmyposh.dev/) pwsh prompt via `winget`
  - uses OMP to install a [nerd font](https://www.nerdfonts.com/) and sets it as default font in Windows Terminal
  - updates your pwsh 7 `$PROFILE` to start OMP
- [`High-Performance-Power-Plan.ps1`](post-install/High-Performance-Power-Plan.ps1): simple script that enables the 'High Performance' power plan, sets monitor sleep to 15min, and sets standby to 2h
  - i would only use this for a gaming desktop, and imo it's sensible. here is an in-depth look at what this power plan *actually* does: https://www.youtube.com/watch?v=j-KGdLpGshQ

## how2
### prepare install media
1. [download latest win11 **BUSINESS** iso](https://massgrave.dev/windows_11_links). FYI:
   - business ISO has everything except home edition
   - consumer ISO has everything except enterprise edition, **so don't use it.**
1. write it to a usb drive with a media creation tool (apparently `dd` may not work, lol?)
   - windows: [rufus](https://rufus.ie/en/#download) `winget install -e --id Rufus.Rufus`
   - macOS: [WinDiskWriter](https://github.com/TechUnRestricted/WinDiskWriter/releases)
1. **click the [absurdly long link](autounattend%20link.md)** to load my `autounattend.xml` in the [schneegans.de unattend-generator](https://schneegans.de/windows/unattend-generator) and review my choices. particularly:
   - set your **time zone** (`Let Windows determine your time zone based on language and region settings` doesn't work ime)
   - `WLAN / Wi-Fi setup`:
     - `Configure Wi-Fi interactively during Windows Setup`: enable this if you're using wifi during setup instead of wired.
   - a classic/local/offline windows account with admin privs will be created interactively as your main user account. if you want some other setup like admin + everyday non-admin user local accts or (*gasp*) online acct, you'll have to pick those options instead.
     - note that `FirstLogon` scripts run the first time an **admin account** logs in, so if you're not using an admin account as your main account, there *might* be unexpected consequences.
     - i assume a single online account would work fine since that'd be an admin.
1. click `Download .xml file` at the very bottom of the page
1. **place `autounattend.xml` in the root dir of the windows install media**

### install windows
*note: this assumes internet access is available during installation*
1. for safety, make sure the only storage devices attached are the target disk and the install media since i have it set to format noninteractively.
1. boot the install media
1. it will ask you to press any key to continue before it wipes the autodetected target disk
1. enter desired computer name
1. create an offline/local user as your main account when prompted
1. once you're at the desktop (past the OOBE), you'll see some cmd windows doing shit. let them finish. this includes a `FirstLogon` bootstrap script that copies the Win11 Prolapse Edition™ repo to your desktop.
1. upon completion, the bootstrap log should automatically open in vscode for your review. the post-install scripts will log here as well.
   - if the log doesn't open for some reason, you can find it at `Desktop\Prolapse Logs\FirstLogon.log.txt`

### post-installation
1. i know it's dumb, but please do this to fix a lot of issues before continuing:
   - **open the Windows Terminal app** (so it builds your settings and dynamic profiles)
   - **reboot windows**
1. double-click `Desktop\Win11 Prolapse Edition\Open-In-VSCode.cmd` – this is just a convenience script to open this repo and logs dir in vscode.
1. the post-install scripts are [described above](#post-install-scripts). edit in vscode and run them as desired. you can right click them and 'Run with PowerShell'.
1. if you need MS Office, [download it](https://gravesoft.dev/office_c2r_links) and then [Ohook license it with massgrave](https://massgrave.dev/): `irm https://get.activated.win | iex`

### tips
- NanaZip → options → Integration tab
  - click the 'associate file types' button
  - check `Extract on open` (the killer feature of NanaZip: you can double click an archive, and it JUST FUCKING EXTRACTS, HOLY SHIT)
- peruse `start ms-settings:developers` (type that in Terminal)
- you can list outdated packages with `winget upgrade` and upgrade them with `winget upgrade --all`
- Terminal `settings.json`: `Ctrl + Shift + ,`
- `Win + x` menu is pretty good
  - `Win + x, i` Terminal
  - `Win + x, a` Terminal as admin
  - `Win + x, m` Device Manager
- `Win + e` Explorer
