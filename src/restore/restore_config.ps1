# Configuration Restoration Module
# Restores configurations from backup on the new system

param(
    [string]$BackupPath,
    [hashtable]$Options = @{}
)

function Restore-EnvironmentVariables {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$EnvVars,
        [hashtable]$Options = @{},
        [string]$OldUsername = "",
        [string]$NewUsername = $env:USERNAME
    )

    # Check if env var restoration is disabled
    if ($Options['RestoreEnvironmentVariables'] -eq $false) {
        Write-Host "Skipping environment variables (disabled in options)" -ForegroundColor Gray
        return 0
    }

    Write-Host "Restoring environment variables..." -ForegroundColor Cyan

    # Detect old username from environment variables if not provided
    if (-not $OldUsername) {
        # Try to detect from USERPROFILE or other user-specific paths
        foreach ($key in $EnvVars.User.Keys) {
            if ($EnvVars.User[$key] -match 'C:\\Users\\([^\\]+)') {
                $OldUsername = $matches[1]
                break
            }
        }
    }

    $replaced = 0
    $restored = 0

    # Show username replacement info
    if ($OldUsername -and $OldUsername -ne $NewUsername) {
        Write-Host "  Username mapping: '$OldUsername' -> '$NewUsername'" -ForegroundColor Yellow
    }

    # Restore user environment variables
    if ($EnvVars.User) {
        foreach ($key in $EnvVars.User.Keys) {
            try {
                # Skip system-managed variables
                if ($key -in @('TEMP', 'TMP', 'USERNAME')) { continue }

                $value = $EnvVars.User[$key]

                # Replace old username with new username in paths
                if ($OldUsername -and $OldUsername -ne $NewUsername) {
                    $oldValue = $value
                    $value = $value -replace "C:\\Users\\$OldUsername", "C:\Users\$NewUsername"
                    $value = $value -replace "\\$OldUsername\\", "\$NewUsername\"
                    
                    if ($value -ne $oldValue) {
                        $replaced++
                        Write-Host "  [User] $key (username replaced)" -ForegroundColor Cyan
                    } else {
                        Write-Host "  [User] $key" -ForegroundColor Gray
                    }
                } else {
                    Write-Host "  [User] $key" -ForegroundColor Gray
                }

                [Environment]::SetEnvironmentVariable($key, $value, [EnvironmentVariableTarget]::User)
                $restored++
            } catch {
                Write-Warning "Failed to set user env var $key : $_"
            }
        }
    }

    # Restore system environment variables (requires admin)
    if ($EnvVars.System) {
        $isAdmin = ([Security.Principal.WindowsPrincipal] [Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)

        if ($isAdmin) {
            foreach ($key in $EnvVars.System.Keys) {
                try {
                    # Skip system-managed variables
                    if ($key -in @('ComSpec', 'OS', 'PATHEXT', 'PROCESSOR_ARCHITECTURE', 'PROCESSOR_IDENTIFIER', 'PROCESSOR_LEVEL', 'PROCESSOR_REVISION', 'PSModulePath', 'SystemDrive', 'SystemRoot', 'windir', 'NUMBER_OF_PROCESSORS')) {
                        continue
                    }

                    $value = $EnvVars.System[$key]

                    # Replace old username with new username in system paths too
                    if ($OldUsername -and $OldUsername -ne $NewUsername) {
                        $oldValue = $value
                        $value = $value -replace "C:\\Users\\$OldUsername", "C:\Users\$NewUsername"
                        $value = $value -replace "\\$OldUsername\\", "\$NewUsername\"
                        
                        if ($value -ne $oldValue) {
                            $replaced++
                            Write-Host "  [System] $key (username replaced)" -ForegroundColor Cyan
                        } else {
                            Write-Host "  [System] $key" -ForegroundColor Gray
                        }
                    } else {
                        Write-Host "  [System] $key" -ForegroundColor Gray
                    }

                    [Environment]::SetEnvironmentVariable($key, $value, [EnvironmentVariableTarget]::Machine)
                    $restored++
                } catch {
                    Write-Warning "Failed to set system env var $key : $_"
                }
            }
        } else {
            Write-Warning "Skipping system environment variables (requires admin privileges)"
        }
    }

    Write-Host "Restored $restored environment variables" -ForegroundColor Green
    if ($replaced -gt 0) {
        Write-Host "  ($replaced variables had username paths replaced)" -ForegroundColor Yellow
    }
    return $restored
}

function Restore-ScheduledTasks {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Tasks,
        [hashtable]$Options = @{}
    )

    # Check if scheduled task restoration is disabled
    if ($Options['RestoreScheduledTasks'] -eq $false) {
        Write-Host "Skipping scheduled task restoration (disabled in options)" -ForegroundColor Gray
        return 0
    }

    Write-Host "Restoring scheduled tasks..." -ForegroundColor Cyan

    $restored = 0

    foreach ($task in $Tasks) {
        try {
            # Skip tasks that shouldn't be restored by default
            if ($null -eq $task.RestoreByDefault) {
                # For backward compatibility with old backups
                $task | Add-Member -NotePropertyName 'RestoreByDefault' -NotePropertyValue $true -Force
            }

            # Check if this task should be restored
            $shouldRestore = $task.RestoreByDefault
            if (-not $shouldRestore) {
                Write-Host "  Skipping: $($task.TaskName) (system or installer task)" -ForegroundColor Gray
                continue
            }

            if ($task.XML) {
                $taskPath = $task.TaskPath
                if (-not $taskPath) { $taskPath = "\" }

                # Create a temporary XML file
                $tempFile = [System.IO.Path]::GetTempFileName() + ".xml"
                $task.XML | Out-File -FilePath $tempFile -Encoding UTF8

                # Register the task
                Register-ScheduledTask -Xml (Get-Content $tempFile -Raw) -TaskName $task.TaskName -TaskPath $taskPath -Force -ErrorAction Stop

                Remove-Item $tempFile -Force

                $restored++
                Write-Host "  Restored: $($task.TaskName)" -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Failed to restore task $($task.TaskName): $_"
        }
    }

    Write-Host "Restored $restored scheduled tasks" -ForegroundColor Green
    return $restored
}

function Restore-Services {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Services,
        [hashtable]$Options = @{}
    )

    # Check if service restoration is disabled
    if ($Options['RestoreServices'] -eq $false) {
        Write-Host "Skipping service restoration (disabled in options)" -ForegroundColor Gray
        return 0
    }

    Write-Host "Restoring service configurations..." -ForegroundColor Cyan

    $restored = 0

    foreach ($service in $Services) {
        try {
            # Skip services that shouldn't be restored by default
            if ($null -eq $service.RestoreByDefault) {
                # For backward compatibility with old backups
                $service | Add-Member -NotePropertyName 'RestoreByDefault' -NotePropertyValue ($service.Category -eq 'UserDisabled') -Force
            }

            # Only restore user-disabled services by default
            $shouldRestore = $service.RestoreByDefault
            if (-not $shouldRestore) {
                Write-Host "  Skipping: $($service.DisplayName) (system or third-party service)" -ForegroundColor Gray
                continue
            }

            $svc = Get-Service -Name $service.Name -ErrorAction SilentlyContinue
            if ($svc) {
                # Restore the startup type
                if ($service.StartType -eq 'Disabled') {
                    Set-Service -Name $service.Name -StartupType Disabled -ErrorAction SilentlyContinue
                    $restored++
                    Write-Host "  Disabled: $($service.DisplayName)" -ForegroundColor Gray
                } elseif ($service.StartType -eq 'Automatic') {
                    Set-Service -Name $service.Name -StartupType Automatic -ErrorAction SilentlyContinue
                    $restored++
                    Write-Host "  Enabled: $($service.DisplayName)" -ForegroundColor Gray
                }
            }
        } catch {
            Write-Warning "Failed to restore service $($service.Name): $_"
        }
    }

    Write-Host "Restored $restored service configurations" -ForegroundColor Green
    return $restored
}

function Restore-NetworkSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$NetworkConfig,
        [hashtable]$Options = @{}
    )

    # Check if network restoration is disabled
    if ($Options['RestoreNetwork'] -eq $false) {
        Write-Host "Skipping network settings (disabled in options)" -ForegroundColor Gray
        return
    }

    Write-Host "Restoring network settings..." -ForegroundColor Cyan

    # Restore hosts file
    if ($NetworkConfig.Hosts) {
        try {
            $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
            # Backup current hosts file
            Copy-Item $hostsPath "$hostsPath.backup" -Force -ErrorAction SilentlyContinue

            # Merge entries (don't overwrite completely)
            $currentHosts = Get-Content $hostsPath -Raw -ErrorAction SilentlyContinue
            $newEntries = $NetworkConfig.Hosts -split "`n" | Where-Object {
                $_.Trim() -ne "" -and -not $_.StartsWith("#") -and $currentHosts -notmatch [regex]::Escape($_.Trim())
            }

            if ($newEntries) {
                Add-Content -Path $hostsPath -Value "`n# Restored by ReWin"
                Add-Content -Path $hostsPath -Value $newEntries
                Write-Host "  Restored hosts file entries" -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Failed to restore hosts file: $_"
        }
    }

    # Restore DNS settings
    if ($NetworkConfig.DNSServers) {
        foreach ($dns in $NetworkConfig.DNSServers) {
            try {
                if ($dns.ServerAddresses -and $dns.InterfaceAlias) {
                    Set-DnsClientServerAddress -InterfaceAlias $dns.InterfaceAlias -ServerAddresses $dns.ServerAddresses -ErrorAction SilentlyContinue
                    Write-Host "  Restored DNS for $($dns.InterfaceAlias)" -ForegroundColor Gray
                }
            } catch {
                Write-Warning "Failed to restore DNS for $($dns.InterfaceAlias): $_"
            }
        }
    }

    Write-Host "Network settings restored" -ForegroundColor Green
}

function Restore-FileAssociations {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Associations,
        [hashtable]$Options = @{}
    )

    # Check if file assoc restoration is disabled
    if ($Options['RestoreFileAssociations'] -eq $false) {
        Write-Host "Skipping file associations (disabled in options)" -ForegroundColor Gray
        return 0
    }

    Write-Host "Restoring file associations..." -ForegroundColor Cyan

    $restored = 0

    foreach ($assoc in $Associations) {
        try {
            if ($assoc.Extension -and $assoc.ProgId) {
                # Use ftype/assoc commands or registry
                $regPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts\$($assoc.Extension)\UserChoice"

                # Note: UserChoice requires special handling due to hash verification
                # This is a simplified version
                $cmd = "cmd /c assoc $($assoc.Extension)=$($assoc.ProgId)"
                Invoke-Expression $cmd 2>$null

                $restored++
            }
        } catch {
            # File associations are tricky due to Windows protections
        }
    }

    Write-Host "Restored $restored file associations" -ForegroundColor Green
    return $restored
}

function Restore-WindowsSettings {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [hashtable]$Settings,
        [hashtable]$Options = @{}
    )

    # Check if Windows settings restoration is disabled
    if ($Options['RestoreWindowsSettings'] -eq $false) {
        Write-Host "Skipping Windows settings (disabled in options)" -ForegroundColor Gray
        return
    }

    Write-Host "Restoring Windows settings..." -ForegroundColor Cyan

    # Explorer settings
    if ($Settings.Explorer) {
        try {
            $explorerPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"

            if ($null -ne $Settings.Explorer.ShowHiddenFiles) {
                Set-ItemProperty -Path $explorerPath -Name "Hidden" -Value $Settings.Explorer.ShowHiddenFiles -ErrorAction SilentlyContinue
            }
            if ($null -ne $Settings.Explorer.ShowFileExtensions) {
                Set-ItemProperty -Path $explorerPath -Name "HideFileExt" -Value $Settings.Explorer.ShowFileExtensions -ErrorAction SilentlyContinue
            }

            Write-Host "  Restored Explorer settings" -ForegroundColor Gray
        } catch {
            Write-Warning "Failed to restore Explorer settings: $_"
        }
    }

    # Desktop settings
    if ($Settings.Desktop) {
        try {
            $desktopPath = "HKCU:\Control Panel\Desktop"

            if ($Settings.Desktop.Wallpaper -and (Test-Path $Settings.Desktop.Wallpaper)) {
                Set-ItemProperty -Path $desktopPath -Name "Wallpaper" -Value $Settings.Desktop.Wallpaper -ErrorAction SilentlyContinue
                # Apply wallpaper
                Add-Type -TypeDefinition @"
                    using System.Runtime.InteropServices;
                    public class Wallpaper {
                        [DllImport("user32.dll", CharSet = CharSet.Auto)]
                        public static extern int SystemParametersInfo(int uAction, int uParam, string lpvParam, int fuWinIni);
                    }
"@
                [Wallpaper]::SystemParametersInfo(0x0014, 0, $Settings.Desktop.Wallpaper, 0x0001 -bor 0x0002)
                Write-Host "  Restored wallpaper" -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Failed to restore desktop settings: $_"
        }
    }

    Write-Host "Windows settings restored" -ForegroundColor Green
}

function Restore-WiFiProfiles {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Profiles
    )

    Write-Host "Restoring WiFi profiles..." -ForegroundColor Cyan

    $restored = 0

    foreach ($profile in $Profiles) {
        try {
            if ($profile.ProfileName -and $profile.Password) {
                # Create WiFi profile XML
                $profileXml = @"
<?xml version="1.0"?>
<WLANProfile xmlns="http://www.microsoft.com/networking/WLAN/profile/v1">
    <name>$($profile.ProfileName)</name>
    <SSIDConfig>
        <SSID>
            <name>$($profile.ProfileName)</name>
        </SSID>
    </SSIDConfig>
    <connectionType>ESS</connectionType>
    <connectionMode>auto</connectionMode>
    <MSM>
        <security>
            <authEncryption>
                <authentication>WPA2PSK</authentication>
                <encryption>AES</encryption>
                <useOneX>false</useOneX>
            </authEncryption>
            <sharedKey>
                <keyType>passPhrase</keyType>
                <protected>false</protected>
                <keyMaterial>$($profile.Password)</keyMaterial>
            </sharedKey>
        </security>
    </MSM>
</WLANProfile>
"@
                $tempFile = [System.IO.Path]::GetTempFileName() + ".xml"
                $profileXml | Out-File -FilePath $tempFile -Encoding UTF8

                netsh wlan add profile filename="$tempFile" user=all 2>$null

                Remove-Item $tempFile -Force
                $restored++
                Write-Host "  Restored: $($profile.ProfileName)" -ForegroundColor Gray
            }
        } catch {
            Write-Warning "Failed to restore WiFi profile $($profile.ProfileName): $_"
        }
    }

    Write-Host "Restored $restored WiFi profiles" -ForegroundColor Green
    return $restored
}

function Restore-AppConfigs {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$BackupPath,
        [hashtable]$Options = @{}
    )

    Write-Host "Restoring application configurations..." -ForegroundColor Cyan

    $appConfigPath = Join-Path $BackupPath "AppConfigs"
    if (-not (Test-Path $appConfigPath)) {
        Write-Warning "No app configs found at $appConfigPath"
        return
    }

    # VS Code
    if ($Options.vscode -ne $false) {
        $vscodeBackup = Join-Path $appConfigPath "VSCode"
        if (Test-Path $vscodeBackup) {
            $vscodeDest = "$env:APPDATA\Code\User"
            if (-not (Test-Path $vscodeDest)) {
                New-Item -Path $vscodeDest -ItemType Directory -Force | Out-Null
            }

            Copy-Item -Path "$vscodeBackup\*" -Destination $vscodeDest -Recurse -Force -ErrorAction SilentlyContinue
            Write-Host "  Restored VS Code settings" -ForegroundColor Gray

            # Install extensions
            $extensionsFile = Join-Path $vscodeBackup "extensions.txt"
            if (Test-Path $extensionsFile) {
                $extensions = Get-Content $extensionsFile
                $codeCmd = Get-Command code -ErrorAction SilentlyContinue
                if ($codeCmd) {
                    foreach ($ext in $extensions) {
                        if ($ext.Trim()) {
                            code --install-extension $ext.Trim() 2>$null
                        }
                    }
                    Write-Host "  Installed VS Code extensions" -ForegroundColor Gray
                }
            }
        }
    }

    # Git
    if ($Options.git_config -ne $false) {
        $gitBackup = Join-Path $appConfigPath "Git"
        if (Test-Path $gitBackup) {
            Copy-Item -Path "$gitBackup\.gitconfig" -Destination $env:USERPROFILE -Force -ErrorAction SilentlyContinue
            Copy-Item -Path "$gitBackup\.gitignore_global" -Destination $env:USERPROFILE -Force -ErrorAction SilentlyContinue
            Write-Host "  Restored Git configuration" -ForegroundColor Gray
        }
    }

    # SSH
    if ($Options.ssh_config -ne $false) {
        $sshBackup = Join-Path $appConfigPath "SSH"
        if (Test-Path $sshBackup) {
            $sshDest = "$env:USERPROFILE\.ssh"
            if (-not (Test-Path $sshDest)) {
                New-Item -Path $sshDest -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path "$sshBackup\*" -Destination $sshDest -Force -ErrorAction SilentlyContinue
            Write-Host "  Restored SSH configuration" -ForegroundColor Gray
        }
    }

    # Windows Terminal
    if ($Options.terminal -ne $false) {
        $termBackup = Join-Path $appConfigPath "WindowsTerminal"
        if (Test-Path $termBackup) {
            $termDest = "$env:LOCALAPPDATA\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState"
            if (Test-Path $termDest) {
                Copy-Item -Path "$termBackup\settings.json" -Destination $termDest -Force -ErrorAction SilentlyContinue
                Write-Host "  Restored Windows Terminal settings" -ForegroundColor Gray
            }
        }
    }

    # PowerShell Profile
    if ($Options.powershell -ne $false) {
        $psBackup = Join-Path $appConfigPath "PowerShell"
        if (Test-Path $psBackup) {
            $psDir = Split-Path $PROFILE -Parent
            if (-not (Test-Path $psDir)) {
                New-Item -Path $psDir -ItemType Directory -Force | Out-Null
            }
            Copy-Item -Path "$psBackup\*" -Destination $psDir -Force -ErrorAction SilentlyContinue
            Write-Host "  Restored PowerShell profile" -ForegroundColor Gray
        }
    }

    # Browser bookmarks
    if ($Options.browser_bookmarks -ne $false) {
        # Chrome
        $chromeBackup = Join-Path $appConfigPath "Chrome"
        if (Test-Path $chromeBackup) {
            $chromeDest = "$env:LOCALAPPDATA\Google\Chrome\User Data\Default"
            if (Test-Path $chromeDest) {
                Copy-Item -Path "$chromeBackup\Bookmarks" -Destination $chromeDest -Force -ErrorAction SilentlyContinue
                Write-Host "  Restored Chrome bookmarks" -ForegroundColor Gray
            }
        }

        # Edge
        $edgeBackup = Join-Path $appConfigPath "Edge"
        if (Test-Path $edgeBackup) {
            $edgeDest = "$env:LOCALAPPDATA\Microsoft\Edge\User Data\Default"
            if (Test-Path $edgeDest) {
                Copy-Item -Path "$edgeBackup\Bookmarks" -Destination $edgeDest -Force -ErrorAction SilentlyContinue
                Write-Host "  Restored Edge bookmarks" -ForegroundColor Gray
            }
        }
    }

    Write-Host "Application configurations restored" -ForegroundColor Green
}

function Start-FullRestore {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath,
        [hashtable]$Options = @{}
    )

    Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║                    ReWin Migration Tool                        ║
║                    Configuration Restore                         ║
╚══════════════════════════════════════════════════════════════════╝

"@ -ForegroundColor Cyan

    # Load migration package
    $packageFile = Join-Path $PackagePath "migration_package.json"
    if (-not (Test-Path $packageFile)) {
        Write-Error "Migration package not found at: $packageFile"
        return
    }

    $package = Get-Content $packageFile -Raw | ConvertFrom-Json

    # Load config backup if exists
    $configBackupFile = Join-Path $PackagePath "config_backup.json"
    $configBackup = $null
    if (Test-Path $configBackupFile) {
        $configBackup = Get-Content $configBackupFile -Raw | ConvertFrom-Json
    }

    # Restore configurations based on selections
    if ($configBackup) {
        if ($package.configs.env_vars -and $configBackup.EnvironmentVariables) {
            Restore-EnvironmentVariables -EnvVars @{
                User = $configBackup.EnvironmentVariables.User
                System = $configBackup.EnvironmentVariables.System
            } -Options $Options
        }

        if ($package.configs.scheduled_tasks -and $configBackup.ScheduledTasks) {
            Restore-ScheduledTasks -Tasks $configBackup.ScheduledTasks -Options $Options
        }

        if ($configBackup.Services) {
            Restore-Services -Services $configBackup.Services -Options $Options
        }

        if ($package.configs.network -and $configBackup.Network) {
            Restore-NetworkSettings -NetworkConfig @{
                Hosts = $configBackup.Network.Hosts
                DNSServers = $configBackup.Network.DNSServers
            } -Options $Options
        }

        if ($package.configs.file_assoc -and $configBackup.FileAssociations) {
            Restore-FileAssociations -Associations $configBackup.FileAssociations -Options $Options
        }

        if ($package.configs.explorer -and $configBackup.WindowsSettings) {
            Restore-WindowsSettings -Settings @{
                Explorer = $configBackup.WindowsSettings.Explorer
                Desktop = $configBackup.WindowsSettings.Desktop
            } -Options $Options
        }
    }

    # Restore WiFi profiles
    if ($package.licenses.include_wifi -and $package.licenses.wifi_profiles) {
        Restore-WiFiProfiles -Profiles $package.licenses.wifi_profiles
    }

    # Restore app configs
    Restore-AppConfigs -BackupPath $PackagePath -Options $package.configs

    Write-Host @"

╔══════════════════════════════════════════════════════════════════╗
║                    RESTORE COMPLETE                              ║
╚══════════════════════════════════════════════════════════════════╝

Configuration restoration complete!

Next steps:
1. Run the software installation scripts
2. Restart your computer to apply all changes
3. Manually install any remaining software

"@ -ForegroundColor Green
}

function Resolve-RestoreManualDownloads {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackagePath
    )

    <#
    Called during restore to regenerate manual_downloads.md with fresh URLs
    and architecture-aware compatibility filtering.
    #>

    Write-Host "Resolving manual downloads at restore time..." -ForegroundColor Cyan

    # Load migration package
    $packageFile = Join-Path $PackagePath 'migration_package.json'
    if (-not (Test-Path $packageFile)) {
        Write-Warning "Migration package not found at $packageFile"
        return
    }

    $package = Get-Content $packageFile | ConvertFrom-Json
    $software = $package.software

    # Import resolver module
    $resolverPath = Split-Path $PROFILE -Parent
    $resolverModule = Join-Path $resolverPath 'manual_download_resolver.ps1'

    if (-not (Test-Path $resolverModule)) {
        # Try to find it in script directory
        $scriptDir = Split-Path $MyInvocation.MyCommand.Path -Parent
        $resolverModule = Join-Path $scriptDir 'manual_download_resolver.ps1'
    }

    if (Test-Path $resolverModule) {
        . $resolverModule
        $manualDownloadPath = Join-Path $PackagePath 'manual_downloads.md'
        $resolved = Resolve-ManualDownloads -Software $software -OutputPath $manualDownloadPath
        Write-Host "Manual downloads report generated at: $manualDownloadPath" -ForegroundColor Green
    } else {
        Write-Warning "Manual download resolver not found. Skipping automatic URL resolution."
    }
}

# Functions are available when dot-sourced
