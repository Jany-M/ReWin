# Package Mapper
# Maps installed software to winget and chocolatey package IDs

# Common software name to package ID mappings
$WingetMappings = @{
    # Browsers
    "Google Chrome" = "Google.Chrome"
    "Mozilla Firefox" = "Mozilla.Firefox"
    "Microsoft Edge" = "Microsoft.Edge"
    "Brave" = "Brave.Brave"
    "Opera" = "Opera.Opera"
    "Vivaldi" = "Vivaldi.Vivaldi"

    # Development
    "Visual Studio Code" = "Microsoft.VisualStudioCode"
    "Visual Studio" = "Microsoft.VisualStudio.2022.Community"
    "Git" = "Git.Git"
    "GitHub Desktop" = "GitHub.GitHubDesktop"
    "Node.js" = "OpenJS.NodeJS.LTS"
    "Python" = "Python.Python.3.12"
    "Docker Desktop" = "Docker.DockerDesktop"
    "Postman" = "Postman.Postman"
    "Windows Terminal" = "Microsoft.WindowsTerminal"
    "PowerShell" = "Microsoft.PowerShell"
    "JetBrains IntelliJ IDEA" = "JetBrains.IntelliJIDEA.Community"
    "JetBrains PyCharm" = "JetBrains.PyCharm.Community"
    "JetBrains WebStorm" = "JetBrains.WebStorm"
    "Sublime Text" = "SublimeHQ.SublimeText.4"
    "Notepad++" = "Notepad++.Notepad++"
    "Atom" = "GitHub.Atom"
    "Android Studio" = "Google.AndroidStudio"
    "Eclipse" = "EclipseAdoptium.Temurin.17.JDK"

    # Communication
    "Discord" = "Discord.Discord"
    "Slack" = "SlackTechnologies.Slack"
    "Microsoft Teams" = "Microsoft.Teams"
    "Zoom" = "Zoom.Zoom"
    "Telegram" = "Telegram.TelegramDesktop"
    "WhatsApp" = "WhatsApp.WhatsApp"
    "Skype" = "Microsoft.Skype"
    "Signal" = "OpenWhisperSystems.Signal"

    # Media
    "VLC media player" = "VideoLAN.VLC"
    "Spotify" = "Spotify.Spotify"
    "iTunes" = "Apple.iTunes"
    "foobar2000" = "PeterPawlowski.foobar2000"
    "AIMP" = "AIMP.AIMP"
    "MediaMonkey" = "Ventis.MediaMonkey"
    "Audacity" = "Audacity.Audacity"
    "OBS Studio" = "OBSProject.OBSStudio"
    "HandBrake" = "HandBrake.HandBrake"
    "FFmpeg" = "Gyan.FFmpeg"
    "ImageMagick" = "ImageMagick.ImageMagick"
    "GIMP" = "GIMP.GIMP"
    "Inkscape" = "Inkscape.Inkscape"
    "Blender" = "BlenderFoundation.Blender"

    # Utilities
    "7-Zip" = "7zip.7zip"
    "WinRAR" = "RARLab.WinRAR"
    "Everything" = "voidtools.Everything"
    "PowerToys" = "Microsoft.PowerToys"
    "Sysinternals Suite" = "Microsoft.Sysinternals.ProcessExplorer"
    "TreeSize Free" = "JAMSoftware.TreeSize.Free"
    "CCleaner" = "Piriform.CCleaner"
    "Revo Uninstaller" = "RevoUninstaller.RevoUninstaller"
    "Rufus" = "Rufus.Rufus"
    "Etcher" = "Balena.Etcher"
    "WizTree" = "AntibodySoftware.WizTree"
    "ShareX" = "ShareX.ShareX"
    "Greenshot" = "Greenshot.Greenshot"
    "Snagit" = "TechSmith.Snagit"
    "AutoHotkey" = "AutoHotkey.AutoHotkey"
    "Ditto" = "Ditto.Ditto"

    # Gaming
    "Steam" = "Valve.Steam"
    "Epic Games Launcher" = "EpicGames.EpicGamesLauncher"
    "GOG Galaxy" = "GOG.Galaxy"
    "Battle.net" = "Blizzard.BattleNet"
    "EA app" = "ElectronicArts.EADesktop"
    "Ubisoft Connect" = "Ubisoft.Connect"
    "Xbox" = "Microsoft.Xbox"

    # Cloud & Backup
    "Dropbox" = "Dropbox.Dropbox"
    "Google Drive" = "Google.GoogleDrive"
    "OneDrive" = "Microsoft.OneDrive"
    "MEGA" = "Mega.MEGASync"
    "pCloud" = "pCloud.pCloudDrive"
    "Resilio Sync" = "Resilio.ResilioSync"

    # Office & Productivity
    "Microsoft 365" = "Microsoft.Office"
    "LibreOffice" = "TheDocumentFoundation.LibreOffice"
    "Adobe Acrobat Reader" = "Adobe.Acrobat.Reader.64-bit"
    "Foxit PDF Reader" = "Foxit.FoxitReader"
    "Sumatra PDF" = "SumatraPDF.SumatraPDF"
    "Notion" = "Notion.Notion"
    "Obsidian" = "Obsidian.Obsidian"
    "Evernote" = "evernote.evernote"

    # Security
    "Bitwarden" = "Bitwarden.Bitwarden"
    "KeePass" = "DominikReichl.KeePass"
    "1Password" = "AgileBits.1Password"
    "LastPass" = "LogMeIn.LastPass"
    "Malwarebytes" = "Malwarebytes.Malwarebytes"
    "WireGuard" = "WireGuard.WireGuard"
    "OpenVPN" = "OpenVPNTechnologies.OpenVPN"
    "NordVPN" = "NordVPN.NordVPN"
    "ProtonVPN" = "ProtonTechnologies.ProtonVPN"

    # System Tools
    "CPU-Z" = "CPUID.CPU-Z"
    "GPU-Z" = "TechPowerUp.GPU-Z"
    "HWiNFO" = "REALiX.HWiNFO"
    "CrystalDiskInfo" = "CrystalDewWorld.CrystalDiskInfo"
    "CrystalDiskMark" = "CrystalDewWorld.CrystalDiskMark"
    "Speccy" = "Piriform.Speccy"
    "MSI Afterburner" = "Guru3D.Afterburner"

    # Remote
    "TeamViewer" = "TeamViewer.TeamViewer"
    "AnyDesk" = "AnyDeskSoftware.AnyDesk"
    "PuTTY" = "PuTTY.PuTTY"
    "WinSCP" = "WinSCP.WinSCP"
    "FileZilla" = "TimKosse.FileZilla.Client"
    "mRemoteNG" = "mRemoteNG.mRemoteNG"
}

$ChocolateyMappings = @{
    # Browsers
    "Google Chrome" = "googlechrome"
    "Mozilla Firefox" = "firefox"
    "Brave" = "brave"
    "Opera" = "opera"
    "Vivaldi" = "vivaldi"

    # Development
    "Visual Studio Code" = "vscode"
    "Git" = "git"
    "Node.js" = "nodejs-lts"
    "Python" = "python"
    "Docker Desktop" = "docker-desktop"
    "Postman" = "postman"
    "Notepad++" = "notepadplusplus"
    "Sublime Text" = "sublimetext4"

    # Communication
    "Discord" = "discord"
    "Slack" = "slack"
    "Zoom" = "zoom"
    "Telegram" = "telegram"

    # Media
    "VLC media player" = "vlc"
    "Spotify" = "spotify"
    "Audacity" = "audacity"
    "OBS Studio" = "obs-studio"
    "HandBrake" = "handbrake"
    "GIMP" = "gimp"
    "Inkscape" = "inkscape"

    # Utilities
    "7-Zip" = "7zip"
    "WinRAR" = "winrar"
    "Everything" = "everything"
    "PowerToys" = "powertoys"
    "ShareX" = "sharex"
    "Greenshot" = "greenshot"
    "AutoHotkey" = "autohotkey"

    # Gaming
    "Steam" = "steam"
    "Epic Games Launcher" = "epicgameslauncher"
    "GOG Galaxy" = "goggalaxy"

    # Cloud
    "Dropbox" = "dropbox"

    # Office
    "LibreOffice" = "libreoffice-fresh"
    "Adobe Acrobat Reader" = "adobereader"
    "Sumatra PDF" = "sumatrapdf"

    # Security
    "Bitwarden" = "bitwarden"
    "KeePass" = "keepass"
    "Malwarebytes" = "malwarebytes"

    # System
    "CPU-Z" = "cpu-z"
    "GPU-Z" = "gpu-z"
    "HWiNFO" = "hwinfo"

    # Remote
    "TeamViewer" = "teamviewer"
    "AnyDesk" = "anydesk"
    "PuTTY" = "putty"
    "WinSCP" = "winscp"
    "FileZilla" = "filezilla"
}

function Find-WingetPackage {
    [CmdletBinding()]
    param(
        [string]$SoftwareName
    )

    # First check static mappings
    foreach ($key in $WingetMappings.Keys) {
        if ($SoftwareName -match [regex]::Escape($key)) {
            return $WingetMappings[$key]
        }
    }

    # Try to search winget
    try {
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            # Clean the software name for searching
            $searchTerm = $SoftwareName -replace '\s*\(.*\)$', '' -replace '\s+\d+(\.\d+)*$', ''
            $searchTerm = $searchTerm.Trim()

            if ($searchTerm.Length -lt 3) { return $null }

            $output = winget search "$searchTerm" --accept-source-agreements 2>$null | Out-String
            $lines = $output -split "`n" | Where-Object { $_.Trim() -ne "" }

            # Parse results
            $dataStarted = $false
            foreach ($line in $lines) {
                if ($line -match "^-+") {
                    $dataStarted = $true
                    continue
                }
                if ($dataStarted -and $line.Trim() -ne "") {
                    $parts = $line -split '\s{2,}'
                    if ($parts.Count -ge 2) {
                        # Check if it's a good match
                        $packageName = $parts[0].Trim()
                        $packageId = if ($parts.Count -ge 3) { $parts[1].Trim() } else { "" }

                        # Simple fuzzy matching
                        $normalizedSoftware = $SoftwareName.ToLower() -replace '[^\w]', ''
                        $normalizedPackage = $packageName.ToLower() -replace '[^\w]', ''

                        if ($normalizedPackage -match [regex]::Escape($normalizedSoftware.Substring(0, [Math]::Min(5, $normalizedSoftware.Length)))) {
                            return $packageId
                        }
                    }
                }
            }
        }
    } catch {}

    return $null
}

function Find-ChocolateyPackage {
    [CmdletBinding()]
    param(
        [string]$SoftwareName
    )

    # Check static mappings
    foreach ($key in $ChocolateyMappings.Keys) {
        if ($SoftwareName -match [regex]::Escape($key)) {
            return $ChocolateyMappings[$key]
        }
    }

    # Try to search chocolatey
    try {
        $chocoPath = Get-Command choco -ErrorAction SilentlyContinue
        if ($chocoPath) {
            $searchTerm = $SoftwareName -replace '\s*\(.*\)$', '' -replace '\s+\d+(\.\d+)*$', ''
            $searchTerm = $searchTerm.Trim()

            if ($searchTerm.Length -lt 3) { return $null }

            $output = choco search "$searchTerm" --limit-output 2>$null
            $firstResult = $output | Select-Object -First 1
            if ($firstResult -match "^([^|]+)\|") {
                return $matches[1]
            }
        }
    } catch {}

    return $null
}

function Get-PackageMapping {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$SoftwareList,
        [switch]$SearchOnline
    )

    Write-Host "Mapping software to package managers..." -ForegroundColor Cyan

    $mappings = @()
    $total = $SoftwareList.Count
    $current = 0
    $startTime = Get-Date

    foreach ($software in $SoftwareList) {
        $current++
        $name = $software.Name
        if (-not $name) { continue }

        # Text-based progress (every 25 items)
        if ($current % 25 -eq 0 -or $current -eq $total -or $current -eq 1) {
            $percent = [math]::Round(($current / $total) * 100)
            $elapsed = (Get-Date) - $startTime
            $itemsPerSec = if ($elapsed.TotalSeconds -gt 0) { $current / $elapsed.TotalSeconds } else { 0 }
            $remaining = if ($itemsPerSec -gt 0) { ($total - $current) / $itemsPerSec } else { 0 }
            $eta = if ($remaining -gt 0) { [timespan]::FromSeconds($remaining).ToString("mm\:ss") } else { "--:--" }
            Write-Host "`r  Mapping packages: $current/$total ($percent%) ETA: $eta".PadRight(60) -NoNewline -ForegroundColor Gray
        }

        $mapping = [PSCustomObject]@{
            SoftwareName = $name
            Version = $software.Version
            Publisher = $software.Publisher
            WingetId = $null
            ChocolateyId = $null
            InstallMethod = "Manual"
            DownloadUrl = $null
        }

        # Check winget mappings
        $wingetId = $null
        foreach ($key in $WingetMappings.Keys) {
            if ($name -match [regex]::Escape($key)) {
                $wingetId = $WingetMappings[$key]
                break
            }
        }
        if (-not $wingetId -and $SearchOnline) {
            $wingetId = Find-WingetPackage -SoftwareName $name
        }
        $mapping.WingetId = $wingetId

        # Check chocolatey mappings
        $chocoId = $null
        foreach ($key in $ChocolateyMappings.Keys) {
            if ($name -match [regex]::Escape($key)) {
                $chocoId = $ChocolateyMappings[$key]
                break
            }
        }
        if (-not $chocoId -and $SearchOnline) {
            $chocoId = Find-ChocolateyPackage -SoftwareName $name
        }
        $mapping.ChocolateyId = $chocoId

        # Determine install method
        if ($wingetId) {
            $mapping.InstallMethod = "Winget"
        } elseif ($chocoId) {
            $mapping.InstallMethod = "Chocolatey"
        } else {
            $mapping.InstallMethod = "Manual"
        }

        $mappings += $mapping
    }

    Write-Host ""  # Clear the progress line

    # Summary
    $wingetCount = ($mappings | Where-Object { $_.WingetId }).Count
    $chocoCount = ($mappings | Where-Object { $_.ChocolateyId -and -not $_.WingetId }).Count
    $manualCount = ($mappings | Where-Object { $_.InstallMethod -eq "Manual" }).Count

    Write-Host "Package mapping complete:" -ForegroundColor Green
    Write-Host "  - Winget: $wingetCount packages" -ForegroundColor White
    Write-Host "  - Chocolatey only: $chocoCount packages" -ForegroundColor White
    Write-Host "  - Manual install required: $manualCount packages" -ForegroundColor White

    return $mappings
}

function Export-PackageMappings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Mappings,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $Mappings | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Package mappings saved to: $OutputPath" -ForegroundColor Green

    # Also create separate install scripts
    $basePath = Split-Path $OutputPath -Parent

    # Winget install script
    $wingetPackages = $Mappings | Where-Object { $_.WingetId } | ForEach-Object { $_.WingetId }
    if ($wingetPackages) {
        $wingetScript = @"
# Winget Installation Script
# Generated by ReWin Migration Tool

Write-Host "Installing packages via winget..." -ForegroundColor Cyan

`$packages = @(
$(($wingetPackages | ForEach-Object { "    `"$_`"" }) -join ",`n")
)

foreach (`$package in `$packages) {
    Write-Host "Installing `$package..." -ForegroundColor Yellow
    winget install --id `$package --accept-source-agreements --accept-package-agreements -h
}

Write-Host "Winget installation complete!" -ForegroundColor Green
"@
        $wingetScript | Out-File -FilePath "$basePath\install_winget.ps1" -Encoding UTF8
    }

    # Chocolatey install script
    $chocoPackages = $Mappings | Where-Object { $_.ChocolateyId -and -not $_.WingetId } | ForEach-Object { $_.ChocolateyId }
    if ($chocoPackages) {
        $chocoScript = @"
# Chocolatey Installation Script
# Generated by ReWin Migration Tool

Write-Host "Installing packages via Chocolatey..." -ForegroundColor Cyan

`$packages = @(
$(($chocoPackages | ForEach-Object { "    `"$_`"" }) -join ",`n")
)

foreach (`$package in `$packages) {
    Write-Host "Installing `$package..." -ForegroundColor Yellow
    choco install `$package -y
}

Write-Host "Chocolatey installation complete!" -ForegroundColor Green
"@
        $chocoScript | Out-File -FilePath "$basePath\install_chocolatey.ps1" -Encoding UTF8
    }
}

# Functions are available when dot-sourced
