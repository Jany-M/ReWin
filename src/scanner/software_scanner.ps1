# Windows Software Scanner
# Scans all installed software from multiple sources

function Get-InstalledSoftware {
    [CmdletBinding()]
    param()

    $software = @()

    # Registry paths for installed software
    $registryPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Uninstall\*",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Uninstall\*"
    )

    foreach ($path in $registryPaths) {
        try {
            $items = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                if ($item.DisplayName -and $item.DisplayName.Trim() -ne "") {
                    $software += [PSCustomObject]@{
                        Name = $item.DisplayName
                        Version = $item.DisplayVersion
                        Publisher = $item.Publisher
                        InstallLocation = $item.InstallLocation
                        InstallDate = $item.InstallDate
                        UninstallString = $item.UninstallString
                        QuietUninstallString = $item.QuietUninstallString
                        EstimatedSize = $item.EstimatedSize
                        RegistryPath = $item.PSPath
                        Source = "Registry"
                    }
                }
            }
        } catch {
            Write-Warning "Error reading registry path: $path - $_"
        }
    }

    # Remove duplicates based on name and version
    $software = $software | Sort-Object Name, Version -Unique

    return $software
}

function Get-StoreApps {
    [CmdletBinding()]
    param()

    $apps = @()

    try {
        # Get current user's Store apps only (avoids permission errors with -AllUsers)
        # Filter only apps with valid InstallLocation (currently installed, not provisioned/staged)
        $storeApps = Get-AppxPackage -ErrorAction SilentlyContinue | Where-Object { $_.InstallLocation -and (Test-Path $_.InstallLocation) }
        foreach ($app in $storeApps) {
            $apps += [PSCustomObject]@{
                Name = $app.Name
                Version = $app.Version
                Publisher = $app.Publisher
                InstallLocation = $app.InstallLocation
                PackageFullName = $app.PackageFullName
                PackageFamilyName = $app.PackageFamilyName
                Source = "MicrosoftStore"
            }
        }
    } catch {
        Write-Warning "Error getting Store apps: $_"
    }

    return $apps
}

function Get-WingetPackages {
    [CmdletBinding()]
    param()

    $packages = @()

    try {
        # Check if winget is available
        $wingetPath = Get-Command winget -ErrorAction SilentlyContinue
        if ($wingetPath) {
            $output = winget list --accept-source-agreements 2>$null | Out-String
            $lines = $output -split "`n" | Where-Object { $_.Trim() -ne "" }

            # Skip header lines
            $dataStarted = $false
            foreach ($line in $lines) {
                if ($line -match "^-+") {
                    $dataStarted = $true
                    continue
                }
                if ($dataStarted -and $line.Trim() -ne "") {
                    # Parse the line (format varies, so we extract what we can)
                    $parts = $line -split '\s{2,}'
                    if ($parts.Count -ge 2) {
                        $packages += [PSCustomObject]@{
                            Name = $parts[0].Trim()
                            Id = if ($parts.Count -ge 3) { $parts[1].Trim() } else { "" }
                            Version = if ($parts.Count -ge 3) { $parts[2].Trim() } else { $parts[1].Trim() }
                            Source = "Winget"
                        }
                    }
                }
            }
        }
    } catch {
        Write-Warning "Error getting winget packages: $_"
    }

    return $packages
}

function Get-ChocolateyPackages {
    [CmdletBinding()]
    param()

    $packages = @()

    try {
        $chocoPath = Get-Command choco -ErrorAction SilentlyContinue
        if ($chocoPath) {
            $output = choco list --local-only 2>$null
            foreach ($line in $output) {
                if ($line -match "^(\S+)\s+(\S+)$") {
                    $packages += [PSCustomObject]@{
                        Name = $matches[1]
                        Version = $matches[2]
                        Source = "Chocolatey"
                    }
                }
            }
        }
    } catch {
        Write-Warning "Error getting Chocolatey packages: $_"
    }

    return $packages
}

function Get-PortableApps {
    [CmdletBinding()]
    param(
        [string[]]$SearchPaths = @("C:\PortableApps", "$env:USERPROFILE\PortableApps", "D:\PortableApps")
    )

    $apps = @()

    foreach ($path in $SearchPaths) {
        if (Test-Path $path) {
            $folders = Get-ChildItem -Path $path -Directory -ErrorAction SilentlyContinue
            foreach ($folder in $folders) {
                $exeFiles = Get-ChildItem -Path $folder.FullName -Filter "*.exe" -File -ErrorAction SilentlyContinue | Select-Object -First 1
                if ($exeFiles) {
                    $apps += [PSCustomObject]@{
                        Name = $folder.Name
                        Path = $folder.FullName
                        Executable = $exeFiles.FullName
                        Source = "Portable"
                    }
                }
            }
        }
    }

    return $apps
}

function Get-StartupPrograms {
    [CmdletBinding()]
    param()

    $startups = @()

    # Registry startup locations
    $startupPaths = @(
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run",
        "HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\RunOnce"
    )

    foreach ($path in $startupPaths) {
        try {
            if (Test-Path $path) {
                $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
                $props.PSObject.Properties | Where-Object { $_.Name -notmatch "^PS" } | ForEach-Object {
                    $startups += [PSCustomObject]@{
                        Name = $_.Name
                        Command = $_.Value
                        Location = $path
                        Source = "RegistryStartup"
                    }
                }
            }
        } catch {
            Write-Warning "Error reading startup path: $path - $_"
        }
    }

    # Startup folders
    $startupFolders = @(
        "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup",
        "$env:ProgramData\Microsoft\Windows\Start Menu\Programs\Startup"
    )

    foreach ($folder in $startupFolders) {
        if (Test-Path $folder) {
            $items = Get-ChildItem -Path $folder -File -ErrorAction SilentlyContinue
            foreach ($item in $items) {
                $startups += [PSCustomObject]@{
                    Name = $item.BaseName
                    Command = $item.FullName
                    Location = $folder
                    Source = "StartupFolder"
                }
            }
        }
    }

    return $startups
}

function Get-AllSoftwareInventory {
    [CmdletBinding()]
    param(
        [string]$OutputPath
    )

    Write-Host "Scanning installed software..." -ForegroundColor Cyan

    $inventory = @{
        ScanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $env:COMPUTERNAME
        WindowsVersion = (Get-CimInstance Win32_OperatingSystem).Caption
        InstalledSoftware = @(Get-InstalledSoftware)
        StoreApps = @(Get-StoreApps)
        WingetPackages = @(Get-WingetPackages)
        ChocolateyPackages = @(Get-ChocolateyPackages)
        PortableApps = @(Get-PortableApps)
        StartupPrograms = @(Get-StartupPrograms)
    }

    Write-Host "Found:" -ForegroundColor Green
    Write-Host "  - $($inventory.InstalledSoftware.Count) installed programs" -ForegroundColor White
    Write-Host "  - $($inventory.StoreApps.Count) Store apps" -ForegroundColor White
    Write-Host "  - $($inventory.WingetPackages.Count) Winget packages" -ForegroundColor White
    Write-Host "  - $($inventory.ChocolateyPackages.Count) Chocolatey packages" -ForegroundColor White
    Write-Host "  - $($inventory.PortableApps.Count) portable apps" -ForegroundColor White
    Write-Host "  - $($inventory.StartupPrograms.Count) startup programs" -ForegroundColor White

    if ($OutputPath) {
        $inventory | ConvertTo-Json -Depth 5 -Compress | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "`nInventory saved to: $OutputPath" -ForegroundColor Green
    }

    return $inventory
}

# Functions are available when dot-sourced
