# Configuration Backup Module
# Backs up Windows configurations, environment variables, scheduled tasks, services, etc.

# Progress helper function
function Write-LiveProgress {
    param(
        [string]$Activity,
        [string]$Status,
        [int]$Current = 0,
        [int]$Total = 0,
        [datetime]$StartTime = (Get-Date),
        [switch]$Complete
    )

    if ($Complete) {
        Write-Host "`r$(' ' * 100)`r" -NoNewline  # Clear line
        return
    }

    $progressStr = ""
    if ($Total -gt 0) {
        $percent = [math]::Round(($Current / $Total) * 100)
        $elapsed = (Get-Date) - $StartTime
        $itemsPerSec = if ($elapsed.TotalSeconds -gt 0) { $Current / $elapsed.TotalSeconds } else { 0 }
        $remaining = if ($itemsPerSec -gt 0) { ($Total - $Current) / $itemsPerSec } else { 0 }
        $eta = if ($remaining -gt 0) { [timespan]::FromSeconds($remaining).ToString("mm\:ss") } else { "--:--" }

        # Progress bar
        $barWidth = 20
        $filled = [math]::Floor($percent / 100 * $barWidth)
        $empty = $barWidth - $filled
        $bar = "[" + ("=" * $filled) + (" " * $empty) + "]"

        $progressStr = "`r    $Activity $bar $percent% ($Current/$Total) ETA: $eta - $Status"
    } else {
        $progressStr = "`r    $Activity - $Status"
    }

    # Pad to overwrite previous content
    $progressStr = $progressStr.PadRight(100)
    Write-Host $progressStr -NoNewline -ForegroundColor Gray
}

function Get-EnvironmentVariables {
    [CmdletBinding()]
    param()

    $envVars = @{
        User = @{}
        System = @{}
    }

    # User environment variables
    try {
        $userEnvPath = "HKCU:\Environment"
        if (Test-Path $userEnvPath) {
            $props = Get-ItemProperty -Path $userEnvPath -ErrorAction SilentlyContinue
            $props.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                $envVars.User[$_.Name] = $_.Value
            }
        }
    } catch {}

    # System environment variables
    try {
        $sysEnvPath = "HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager\Environment"
        if (Test-Path $sysEnvPath) {
            $props = Get-ItemProperty -Path $sysEnvPath -ErrorAction SilentlyContinue
            $props.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                $envVars.System[$_.Name] = $_.Value
            }
        }
    } catch {}

    return $envVars
}

function Get-ScheduledTasksBackup {
    [CmdletBinding()]
    param()

    $tasks = @()

    # Known system task paths to exclude (will be recreated on fresh install)
    $systemTaskPaths = @(
        "\\Microsoft\\",
        "\\Windows\\",
        "\\GoogleUpdate\\",
        "\\Adobe\\",
        "\\Avast\\",
        "\\McAfee\\",
        "\\Norton\\",
        "\\Symantec\\",
        "\\NVIDIA\\",
        "\\Intel\\",
        "\\AMD\\"
    )

    # Known installer/third-party vendor names
    $installerVendors = @("Adobe", "Java", "Google", "Microsoft", "Windows", "Avast", "McAfee", "Norton", "NVIDIA", "Intel", "AMD", "Symantec")

    try {
        Write-Host "    Loading scheduled task information..." -ForegroundColor Gray -NoNewline

        # Only capture tasks that user likely created:
        # 1. Non-Microsoft paths
        # 2. Not from known installers
        # 3. Not disabled by system
        $allTasks = @(Get-ScheduledTask -ErrorAction SilentlyContinue | Where-Object {
            $task = $_
            
            # Skip Microsoft and Windows system paths
            $isSystemPath = $systemTaskPaths | Where-Object { $task.TaskPath -like "*$_*" }
            
            # Skip disabled tasks
            if ($task.State -eq "Disabled") { return $false }
            
            # Skip if system path
            if ($isSystemPath) { return $false }
            
            # Skip if installer-related
            $isInstallerTask = $installerVendors | Where-Object { $task.TaskName -like "*$_*" }
            if ($isInstallerTask) { return $false }
            
            return $true
        })
        
        Write-Host "`r$(' ' * 80)`r" -NoNewline  # Clear line

        $total = $allTasks.Count
        $current = 0
        $startTime = Get-Date

        foreach ($task in $allTasks) {
            $current++

            if ($current % 5 -eq 0 -or $current -eq $total -or $current -eq 1) {
                Write-LiveProgress -Activity "Scheduled Tasks" -Status $task.TaskName -Current $current -Total $total -StartTime $startTime
            }

            try {
                $taskInfo = Get-ScheduledTaskInfo -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue
                $taskXml = Export-ScheduledTask -TaskName $task.TaskName -TaskPath $task.TaskPath -ErrorAction SilentlyContinue

                # Categorize the task
                $category = "UserCreated"  # Default for non-system tasks that passed filtering
                
                # Check if it's a known system task from fresh Windows
                if ($task.Author -match "Microsoft|Windows|System" -or $task.Description -match "Microsoft|Windows|System") {
                    $category = "System"
                }

                $tasks += [PSCustomObject]@{
                    TaskName = $task.TaskName
                    TaskPath = $task.TaskPath
                    State = $task.State.ToString()
                    Description = $task.Description
                    Author = $task.Author
                    LastRunTime = $taskInfo.LastRunTime
                    NextRunTime = $taskInfo.NextRunTime
                    Category = $category
                    RestoreByDefault = ($category -eq "UserCreated")  # Only restore user-created tasks by default
                    XML = $taskXml
                }
            } catch {}
        }
        Write-LiveProgress -Complete
    } catch {
        Write-Host ""
        Write-Warning "Error getting scheduled tasks: $_"
    }

    return $tasks
}

function Get-ServicesConfiguration {
    [CmdletBinding()]
    param()

    $services = @()

    # Known Windows/Microsoft services to skip (will be present on fresh install)
    $windowsServicePrefixes = @(
        'wua', 'wmi', 'win', 'w32', 'wscsvc', 'wer', 'wbengine', 'vss', 'usos',
        'trustedinstaller', 'tiledatamodelsvc', 'sysmain', 'spooler', 'smphost',
        'sharedaccess', 'sens', 'schedule', 'rpcss', 'rpclocator', 'remoteregistry',
        'pla', 'plugplay', 'pcasvc', 'netlogon', 'msiserver', 'mpsvc', 'msdtc',
        'lmhosts', 'lanmanworkstation', 'lanmanserver', 'ikeext', 'hidserv',
        'gpsvc', 'fontcache', 'eventlog', 'eventsystem', 'dps', 'dnscache',
        'dhcp', 'defragsvc', 'cryptsvc', 'browser', 'bits', 'bfe', 'audiosrv',
        'appinfo', 'aelookupsvc', 'wuauserv', 'wsearch', 'themes', 'tabletinputservice',
        'stisvc', 'shellhwdetection', 'seclogon', 'samss', 'rasman', 'power',
        'pnrpsvc', 'p2pimsvc', 'netman', 'napagent', 'mpssvc', 'lltdsvc', 'iphlpsvc',
        'fdrespub', 'fdphost', 'eaphost', 'dot3svc', 'diagtrack', 'cscservice',
        'clipsvc', 'cbdhsvc', 'cdpsvc', 'bthserv', 'appxsvc', 'appidsvc', 'appid'
    )

    try {
        Write-Host "    Loading service information..." -ForegroundColor Gray -NoNewline

        # Get all WMI service info in ONE call
        $wmiServices = @{}
        try {
            Get-CimInstance -ClassName Win32_Service -ErrorAction SilentlyContinue | ForEach-Object {
                $wmiServices[$_.Name] = @{
                    PathName = $_.PathName
                    Description = $_.Description
                    StartName = $_.StartName
                }
            }
        } catch {}
        Write-Host "`r$(' ' * 80)`r" -NoNewline

        # Only capture services that user likely configured:
        # 1. Disabled services (user chose to disable)
        # 2. Non-Microsoft services with custom startup
        $allServices = @(Get-Service -ErrorAction SilentlyContinue | Where-Object {
            $svc = $_
            $isWindowsService = $windowsServicePrefixes | Where-Object { $svc.Name -like "$_*" }
            $wmiInfo = $wmiServices[$svc.Name]
            $pathName = if ($wmiInfo) { $wmiInfo.PathName } else { "" }
            $isMicrosoftPath = $pathName -match 'Windows|Microsoft|System32|SysWOW64'

            # Include if: disabled by user OR is a third-party service
            ($svc.StartType -eq 'Disabled') -or
            (-not $isWindowsService -and -not $isMicrosoftPath -and $svc.StartType -ne 'Automatic')
        })

        $total = $allServices.Count
        $current = 0
        $startTime = Get-Date

        foreach ($service in $allServices) {
            $current++

            if ($current % 20 -eq 0 -or $current -eq $total) {
                Write-LiveProgress -Activity "Services" -Status $service.DisplayName -Current $current -Total $total -StartTime $startTime
            }

            try {
                $wmiInfo = $wmiServices[$service.Name]
                $pathName = if ($wmiInfo) { $wmiInfo.PathName } else { $null }

                # Categorize the service
                $category = "ThirdParty"
                if ($pathName -match 'Windows|Microsoft|System32|SysWOW64') {
                    $category = "System"
                } elseif ($service.StartType -eq 'Disabled') {
                    $category = "UserDisabled"
                }

                $services += [PSCustomObject]@{
                    Name = $service.Name
                    DisplayName = $service.DisplayName
                    Status = $service.Status.ToString()
                    StartType = $service.StartType.ToString()
                    PathName = $pathName
                    Description = if ($wmiInfo) { $wmiInfo.Description } else { $null }
                    StartName = if ($wmiInfo) { $wmiInfo.StartName } else { $null }
                    Category = $category
                    RestoreByDefault = ($category -eq "UserDisabled")  # Only restore user-disabled services by default
                }
            } catch {}
        }
        Write-LiveProgress -Complete
    } catch {
        Write-Host ""
        Write-Warning "Error getting services: $_"
    }

    return $services
}

function Get-NetworkConfiguration {
    [CmdletBinding()]
    param()

    $networkConfig = @{
        Adapters = @()
        DNSServers = @()
        StaticRoutes = @()
        Hosts = $null
    }

    # Network adapters
    try {
        $adapters = Get-NetIPConfiguration -ErrorAction SilentlyContinue
        foreach ($adapter in $adapters) {
            $networkConfig.Adapters += [PSCustomObject]@{
                InterfaceAlias = $adapter.InterfaceAlias
                InterfaceIndex = $adapter.InterfaceIndex
                IPv4Address = $adapter.IPv4Address.IPAddress
                IPv4Gateway = $adapter.IPv4DefaultGateway.NextHop
                IPv6Address = $adapter.IPv6Address.IPAddress
                DNSServer = $adapter.DNSServer.ServerAddresses
            }
        }
    } catch {}

    # DNS client settings
    try {
        $dnsSettings = Get-DnsClientServerAddress -ErrorAction SilentlyContinue | Where-Object { $_.ServerAddresses }
        foreach ($dns in $dnsSettings) {
            $networkConfig.DNSServers += [PSCustomObject]@{
                InterfaceAlias = $dns.InterfaceAlias
                AddressFamily = $dns.AddressFamily
                ServerAddresses = $dns.ServerAddresses
            }
        }
    } catch {}

    # Static routes
    try {
        $routes = Get-NetRoute -ErrorAction SilentlyContinue | Where-Object {
            $_.RouteMetric -lt 256 -and $_.DestinationPrefix -ne "0.0.0.0/0"
        }
        foreach ($route in $routes) {
            $networkConfig.StaticRoutes += [PSCustomObject]@{
                DestinationPrefix = $route.DestinationPrefix
                NextHop = $route.NextHop
                RouteMetric = $route.RouteMetric
                InterfaceAlias = $route.InterfaceAlias
            }
        }
    } catch {}

    # Hosts file
    try {
        $hostsPath = "$env:SystemRoot\System32\drivers\etc\hosts"
        if (Test-Path $hostsPath) {
            $networkConfig.Hosts = Get-Content -Path $hostsPath -Raw -ErrorAction SilentlyContinue
        }
    } catch {}

    return $networkConfig
}

function Get-FileAssociations {
    [CmdletBinding()]
    param()

    $associations = @()

    try {
        # Get user file associations
        $assocPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\FileExts"
        if (Test-Path $assocPath) {
            Write-Host "    Enumerating file extensions..." -ForegroundColor Gray -NoNewline
            $extensions = @(Get-ChildItem -Path $assocPath -ErrorAction SilentlyContinue)
            Write-Host "`r$(' ' * 60)`r" -NoNewline  # Clear line

            $total = $extensions.Count
            $current = 0
            $startTime = Get-Date

            foreach ($ext in $extensions) {
                $current++

                # Update progress every 50 items to avoid slowdown
                if ($current % 50 -eq 0 -or $current -eq $total) {
                    Write-LiveProgress -Activity "File Associations" -Status $ext.PSChildName -Current $current -Total $total -StartTime $startTime
                }

                try {
                    $userChoice = Get-ItemProperty -Path "$($ext.PSPath)\UserChoice" -ErrorAction SilentlyContinue
                    if ($userChoice.ProgId) {
                        $associations += [PSCustomObject]@{
                            Extension = $ext.PSChildName
                            ProgId = $userChoice.ProgId
                            Hash = $userChoice.Hash
                        }
                    }
                } catch {}
            }
            Write-LiveProgress -Complete
        }
    } catch {
        Write-Host ""
        Write-Warning "Error getting file associations: $_"
    }

    return $associations
}

function Get-WindowsSettings {
    [CmdletBinding()]
    param()

    $settings = @{
        Explorer = @{}
        Desktop = @{}
        Taskbar = @{}
        Personalization = @{}
        Power = @{}
    }

    # Explorer settings
    try {
        $explorerPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\Advanced"
        if (Test-Path $explorerPath) {
            $props = Get-ItemProperty -Path $explorerPath -ErrorAction SilentlyContinue
            $settings.Explorer = @{
                ShowHiddenFiles = $props.Hidden
                ShowFileExtensions = $props.HideFileExt
                ShowStatusBar = $props.ShowStatusBar
                LaunchTo = $props.LaunchTo
                TaskbarGlomLevel = $props.TaskbarGlomLevel
            }
        }
    } catch {}

    # Desktop settings
    try {
        $desktopPath = "HKCU:\Control Panel\Desktop"
        if (Test-Path $desktopPath) {
            $props = Get-ItemProperty -Path $desktopPath -ErrorAction SilentlyContinue
            $settings.Desktop = @{
                Wallpaper = $props.Wallpaper
                WallpaperStyle = $props.WallpaperStyle
                ScreenSaveActive = $props.ScreenSaveActive
                ScreenSaverTimeout = $props.ScreenSaveTimeout
            }
        }
    } catch {}

    # Taskbar settings
    try {
        $taskbarPath = "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Explorer\StuckRects3"
        if (Test-Path $taskbarPath) {
            $props = Get-ItemProperty -Path $taskbarPath -ErrorAction SilentlyContinue
            $settings.Taskbar.Settings = $props.Settings
        }
    } catch {}

    # Power settings
    try {
        $powerScheme = powercfg /getactivescheme 2>$null | Out-String
        $settings.Power.ActiveScheme = $powerScheme
    } catch {}

    return $settings
}

function Get-AppSpecificConfigs {
    [CmdletBinding()]
    param(
        [string]$BackupPath
    )

    $configs = @{}
    $appDataPath = $env:APPDATA
    $localAppDataPath = $env:LOCALAPPDATA
    $userProfile = $env:USERPROFILE

    # VS Code settings
    Write-Host "    Checking VS Code..." -ForegroundColor Gray -NoNewline
    $vscodeSettings = @(
        "$appDataPath\Code\User\settings.json",
        "$appDataPath\Code\User\keybindings.json",
        "$appDataPath\Code\User\snippets"
    )

    $configs.VSCode = @{
        Paths = $vscodeSettings | Where-Object { Test-Path $_ }
        Extensions = @()
    }

    # Get VS Code extensions
    try {
        $codeCmd = Get-Command code -ErrorAction SilentlyContinue
        if ($codeCmd) {
            Write-Host "`r    Checking VS Code... listing extensions..." -ForegroundColor Gray -NoNewline
            $extensions = code --list-extensions 2>$null
            $configs.VSCode.Extensions = $extensions
        }
    } catch {}
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # Git config
    Write-Host "    Checking Git config..." -ForegroundColor Gray -NoNewline
    $gitConfigs = @(
        "$userProfile\.gitconfig",
        "$userProfile\.gitignore_global"
    )
    $configs.Git = @{
        Paths = $gitConfigs | Where-Object { Test-Path $_ }
    }
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # PowerShell profile
    Write-Host "    Checking PowerShell profile..." -ForegroundColor Gray -NoNewline
    $psProfiles = @(
        $PROFILE.AllUsersAllHosts,
        $PROFILE.AllUsersCurrentHost,
        $PROFILE.CurrentUserAllHosts,
        $PROFILE.CurrentUserCurrentHost
    )
    $configs.PowerShell = @{
        Paths = $psProfiles | Where-Object { $_ -and (Test-Path $_) }
    }
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # SSH keys
    Write-Host "    Checking SSH keys..." -ForegroundColor Gray -NoNewline
    $sshPath = "$userProfile\.ssh"
    $configs.SSH = @{
        Path = $sshPath
        Exists = Test-Path $sshPath
        Files = if (Test-Path $sshPath) { (Get-ChildItem -Path $sshPath -File -ErrorAction SilentlyContinue).Name } else { @() }
    }
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # npm global config
    Write-Host "    Checking NPM config..." -ForegroundColor Gray -NoNewline
    $npmConfig = "$userProfile\.npmrc"
    $configs.NPM = @{
        ConfigPath = $npmConfig
        Exists = Test-Path $npmConfig
        GlobalPackages = @()
    }
    try {
        $npmCmd = Get-Command npm -ErrorAction SilentlyContinue
        if ($npmCmd) {
            $globalPkgs = npm list -g --depth=0 2>$null | Out-String
            $configs.NPM.GlobalPackages = $globalPkgs
        }
    } catch {}
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # Browser bookmarks (Chrome, Firefox, Edge)
    Write-Host "    Checking browser bookmarks..." -ForegroundColor Gray -NoNewline
    $configs.Browsers = @{
        Chrome = @{
            BookmarksPath = "$localAppDataPath\Google\Chrome\User Data\Default\Bookmarks"
            Exists = Test-Path "$localAppDataPath\Google\Chrome\User Data\Default\Bookmarks"
        }
        Firefox = @{
            ProfilePath = "$appDataPath\Mozilla\Firefox\Profiles"
            Exists = Test-Path "$appDataPath\Mozilla\Firefox\Profiles"
        }
        Edge = @{
            BookmarksPath = "$localAppDataPath\Microsoft\Edge\User Data\Default\Bookmarks"
            Exists = Test-Path "$localAppDataPath\Microsoft\Edge\User Data\Default\Bookmarks"
        }
    }
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # Terminal settings (Windows Terminal)
    Write-Host "    Checking Windows Terminal..." -ForegroundColor Gray -NoNewline
    $terminalSettings = "$localAppDataPath\Packages\Microsoft.WindowsTerminal_8wekyb3d8bbwe\LocalState\settings.json"
    $configs.WindowsTerminal = @{
        SettingsPath = $terminalSettings
        Exists = Test-Path $terminalSettings
    }
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # Notepad++ settings
    $nppConfig = "$appDataPath\Notepad++"
    $configs.NotepadPlusPlus = @{
        ConfigPath = $nppConfig
        Exists = Test-Path $nppConfig
    }

    # Cursor IDE (similar to VSCode)
    Write-Host "    Checking Cursor IDE..." -ForegroundColor Gray -NoNewline
    $cursorSettings = @(
        "$appDataPath\Cursor\User\settings.json",
        "$appDataPath\Cursor\User\keybindings.json",
        "$appDataPath\Cursor\User\snippets",
        "$localAppDataPath\Cursor\mcp.json"
    )
    $configs.Cursor = @{
        Paths = $cursorSettings | Where-Object { Test-Path $_ }
        Extensions = @()
    }

    # Get Cursor extensions
    try {
        $cursorCmd = Get-Command cursor -ErrorAction SilentlyContinue
        if ($cursorCmd) {
            Write-Host "`r    Checking Cursor IDE... listing extensions..." -ForegroundColor Gray -NoNewline
            $extensions = cursor --list-extensions 2>$null
            $configs.Cursor.Extensions = $extensions
        }
    } catch {}
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # VS Code mcp.json (Model Context Protocol)
    $vscodeUserPath = "$appDataPath\Code\User"
    if (Test-Path "$vscodeUserPath\mcp.json") {
        $configs.VSCode.MCPPath = "$vscodeUserPath\mcp.json"
    }

    # Claude Desktop app
    Write-Host "    Checking Claude Desktop..." -ForegroundColor Gray -NoNewline
    $claudeSettings = @(
        "$appDataPath\Claude\settings.json",
        "$appDataPath\Claude\config.json",
        "$localAppDataPath\Claude\cache"
    )
    $configs.ClaudeDesktop = @{
        Paths = $claudeSettings | Where-Object { Test-Path $_ }
    }
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    # OpenAI Desktop app
    Write-Host "    Checking OpenAI Desktop..." -ForegroundColor Gray -NoNewline
    $openaiSettings = @(
        "$appDataPath\OpenAI\settings.json",
        "$appDataPath\OpenAI\config.json"
    )
    $configs.OpenAIDesktop = @{
        Paths = $openaiSettings | Where-Object { Test-Path $_ }
    }
    Write-Host "`r$(' ' * 60)`r" -NoNewline

    return $configs
}

function Backup-AppConfigs {
    [CmdletBinding()]
    param(
        [string]$BackupPath
    )

    Write-Host "    Backing up application configs..." -ForegroundColor Gray

    $configs = Get-AppSpecificConfigs
    $backedUp = @()

    # Create backup directory
    $configBackupPath = Join-Path $BackupPath "AppConfigs"
    New-Item -Path $configBackupPath -ItemType Directory -Force | Out-Null

    $backupItems = @(
        @{ Name = "VS Code"; Source = $configs.VSCode.Paths; Dest = "VSCode"; Extensions = $configs.VSCode.Extensions },
        @{ Name = "Cursor IDE"; Source = $configs.Cursor.Paths; Dest = "Cursor"; Extensions = $configs.Cursor.Extensions },
        @{ Name = "Git"; Source = $configs.Git.Paths; Dest = "Git" },
        @{ Name = "PowerShell"; Source = $configs.PowerShell.Paths; Dest = "PowerShell" },
        @{ Name = "SSH"; Source = if ($configs.SSH.Exists) { @("$env:USERPROFILE\.ssh\config", "$env:USERPROFILE\.ssh\known_hosts") + (Get-ChildItem "$env:USERPROFILE\.ssh\*.pub" -ErrorAction SilentlyContinue | Select-Object -ExpandProperty FullName) } else { @() }; Dest = "SSH" },
        @{ Name = "Windows Terminal"; Source = if ($configs.WindowsTerminal.Exists) { @($configs.WindowsTerminal.SettingsPath) } else { @() }; Dest = "WindowsTerminal" },
        @{ Name = "Chrome Bookmarks"; Source = if ($configs.Browsers.Chrome.Exists) { @($configs.Browsers.Chrome.BookmarksPath) } else { @() }; Dest = "Chrome" },
        @{ Name = "Edge Bookmarks"; Source = if ($configs.Browsers.Edge.Exists) { @($configs.Browsers.Edge.BookmarksPath) } else { @() }; Dest = "Edge" },
        @{ Name = "Claude Desktop"; Source = $configs.ClaudeDesktop.Paths; Dest = "Claude" },
        @{ Name = "OpenAI Desktop"; Source = $configs.OpenAIDesktop.Paths; Dest = "OpenAI" }
    )

    $total = $backupItems.Count
    $current = 0
    $startTime = Get-Date

    foreach ($item in $backupItems) {
        $current++
        Write-LiveProgress -Activity "Copying configs" -Status $item.Name -Current $current -Total $total -StartTime $startTime

        if ($item.Source -and $item.Source.Count -gt 0) {
            $destPath = Join-Path $configBackupPath $item.Dest
            New-Item -Path $destPath -ItemType Directory -Force | Out-Null

            foreach ($sourcePath in $item.Source) {
                if ($sourcePath -and (Test-Path $sourcePath)) {
                    try {
                        $sourceItem = Get-Item $sourcePath
                        if ($sourceItem.PSIsContainer) {
                            Copy-Item -Path $sourcePath -Destination $destPath -Recurse -Force -ErrorAction SilentlyContinue
                        } else {
                            Copy-Item -Path $sourcePath -Destination $destPath -Force -ErrorAction SilentlyContinue
                        }
                        $backedUp += "$($item.Name): $(Split-Path $sourcePath -Leaf)"
                    } catch {}
                }
            }

            # Save VS Code extensions list
            if ($item.Extensions -and $item.Extensions.Count -gt 0) {
                $item.Extensions | Out-File -FilePath "$destPath\extensions.txt" -Encoding UTF8
                $backedUp += "$($item.Name): Extensions list"
            }
        }
    }

    Write-LiveProgress -Complete
    Write-Host "    Backed up $($backedUp.Count) items" -ForegroundColor Green

    return $backedUp
}

function Get-AllConfigurationBackup {
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [switch]$BackupFiles
    )

    Write-Host "  Starting configuration backup..." -ForegroundColor Cyan

    $backup = @{
        BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        EnvironmentVariables = $null
        ScheduledTasks = @()
        Services = @()
        Network = $null
        FileAssociations = @()
        WindowsSettings = $null
        AppConfigs = $null
    }

    # Environment variables (fast)
    Write-Host "  -> Environment variables..." -ForegroundColor Gray
    try {
        $backup.EnvironmentVariables = Get-EnvironmentVariables
        $count = ($backup.EnvironmentVariables.User.Keys.Count) + ($backup.EnvironmentVariables.System.Keys.Count)
        Write-Host "     Found $count variables" -ForegroundColor Green
    } catch {
        Write-Warning "     Error: $_"
        $backup.EnvironmentVariables = @{ User = @{}; System = @{} }
    }

    # Scheduled tasks (can be slow)
    Write-Host "  -> Scheduled tasks..." -ForegroundColor Gray
    try {
        $backup.ScheduledTasks = @(Get-ScheduledTasksBackup)
        Write-Host "     Found $($backup.ScheduledTasks.Count) custom tasks" -ForegroundColor Green
    } catch {
        Write-Warning "     Error: $_"
    }

    # Services (can be slow due to WMI)
    Write-Host "  -> Services configuration..." -ForegroundColor Gray
    try {
        $backup.Services = @(Get-ServicesConfiguration)
        Write-Host "     Found $($backup.Services.Count) services" -ForegroundColor Green
    } catch {
        Write-Warning "     Error: $_"
    }

    # Network (fast)
    Write-Host "  -> Network settings..." -ForegroundColor Gray
    try {
        $backup.Network = Get-NetworkConfiguration
        Write-Host "     Network config backed up" -ForegroundColor Green
    } catch {
        Write-Warning "     Error: $_"
        $backup.Network = @{}
    }

    # File associations (can be slow)
    Write-Host "  -> File associations..." -ForegroundColor Gray
    try {
        $backup.FileAssociations = @(Get-FileAssociations)
        Write-Host "     Found $($backup.FileAssociations.Count) associations" -ForegroundColor Green
    } catch {
        Write-Warning "     Error: $_"
    }

    # Windows settings (fast)
    Write-Host "  -> Windows settings..." -ForegroundColor Gray
    try {
        $backup.WindowsSettings = Get-WindowsSettings
        Write-Host "     Windows settings backed up" -ForegroundColor Green
    } catch {
        Write-Warning "     Error: $_"
        $backup.WindowsSettings = @{}
    }

    # App configs (moderate)
    Write-Host "  -> App-specific configs..." -ForegroundColor Gray
    try {
        $backup.AppConfigs = Get-AppSpecificConfigs
        Write-Host "     App configs scanned" -ForegroundColor Green
    } catch {
        Write-Warning "     Error: $_"
        $backup.AppConfigs = @{}
    }

    # Backup files if requested
    if ($BackupFiles -and $OutputPath) {
        try {
            $backedUpFiles = Backup-AppConfigs -BackupPath (Split-Path $OutputPath -Parent)
            $backup.BackedUpFiles = $backedUpFiles
        } catch {
            Write-Warning "     Error backing up files: $_"
        }
    }

    # Save to file
    if ($OutputPath) {
        Write-Host "  Saving to JSON..." -ForegroundColor Gray -NoNewline
        $backup | ConvertTo-Json -Depth 5 -Compress | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host " done." -ForegroundColor Green
        Write-Host "  Configuration saved to: $OutputPath" -ForegroundColor Green
    }

    return $backup
}

# Functions are available when dot-sourced
