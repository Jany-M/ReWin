# Installer Downloader
# Downloads installers for software not available in package managers

# Known download URLs for common software
$KnownDownloadUrls = @{
    # Adobe
    "Adobe Creative Cloud" = "https://creativecloud.adobe.com/apps/download/creative-cloud"
    "Adobe Acrobat Reader" = "https://get.adobe.com/reader/"

    # Microsoft
    "Microsoft Office" = "https://www.office.com/download"
    "Visual Studio" = "https://visualstudio.microsoft.com/downloads/"
    "SQL Server Management Studio" = "https://aka.ms/ssmsfullsetup"

    # Development
    "JetBrains Toolbox" = "https://www.jetbrains.com/toolbox-app/download/"
    "Android Studio" = "https://developer.android.com/studio"
    "Unity Hub" = "https://unity3d.com/get-unity/download"
    "Unreal Engine" = "https://www.unrealengine.com/download"

    # Drivers
    "NVIDIA GeForce Experience" = "https://www.nvidia.com/en-us/geforce/geforce-experience/"
    "AMD Software" = "https://www.amd.com/en/support"
    "Intel Driver Support" = "https://www.intel.com/content/www/us/en/support/detect.html"

    # Specialized
    "AutoCAD" = "https://www.autodesk.com/products/autocad/overview"
    "SolidWorks" = "https://www.solidworks.com/product/solidworks-3d-cad"
    "MATLAB" = "https://www.mathworks.com/downloads/"

    # Gaming platforms
    "Origin" = "https://www.origin.com/download"
    "Ubisoft Connect" = "https://ubisoftconnect.com/"

    # Media
    "DaVinci Resolve" = "https://www.blackmagicdesign.com/products/davinciresolve"
    "Ableton Live" = "https://www.ableton.com/en/trial/"
    "FL Studio" = "https://www.image-line.com/fl-studio-download/"

    # Utilities
    "Acronis True Image" = "https://www.acronis.com/en-us/products/true-image/"
    "Macrium Reflect" = "https://www.macrium.com/reflectfree"
}

function Get-InstallerFromUninstallString {
    [CmdletBinding()]
    param(
        [string]$UninstallString
    )

    if (-not $UninstallString) { return $null }

    # Try to extract the installer path from uninstall string
    $patterns = @(
        # MsiExec patterns
        'MsiExec\.exe\s+/[IX]\{([^}]+)\}',
        # Direct executable paths
        '"([^"]+\.exe)"',
        '([A-Z]:\\[^\s]+\.exe)'
    )

    foreach ($pattern in $patterns) {
        if ($UninstallString -match $pattern) {
            $path = $matches[1]
            if ($path -match '^[A-Z]:\\' -and (Test-Path $path)) {
                return $path
            }
        }
    }

    return $null
}

function Get-DownloadUrl {
    [CmdletBinding()]
    param(
        [string]$SoftwareName,
        [string]$Publisher
    )

    # Check known URLs
    foreach ($key in $KnownDownloadUrls.Keys) {
        if ($SoftwareName -match [regex]::Escape($key)) {
            return $KnownDownloadUrls[$key]
        }
    }

    # Try to construct URL from publisher
    if ($Publisher) {
        $publisherDomain = $Publisher -replace '\s+', '' -replace '[^\w]', ''
        $commonDomains = @(
            "https://www.$publisherDomain.com/download",
            "https://www.$publisherDomain.com/downloads",
            "https://$publisherDomain.com/download"
        )
        return $commonDomains[0]  # Return as suggestion, not verified
    }

    return $null
}

function Copy-ExistingInstaller {
    [CmdletBinding()]
    param(
        [string]$SoftwareName,
        [string]$InstallLocation,
        [string]$DestinationPath
    )

    if (-not $InstallLocation -or -not (Test-Path $InstallLocation)) {
        return $null
    }

    # Look for installers in the install location
    $installerPatterns = @("setup*.exe", "install*.exe", "*installer*.exe", "*.msi")

    foreach ($pattern in $installerPatterns) {
        $installers = Get-ChildItem -Path $InstallLocation -Filter $pattern -File -ErrorAction SilentlyContinue
        if ($installers) {
            $installer = $installers | Select-Object -First 1
            $destFile = Join-Path $DestinationPath $installer.Name
            Copy-Item -Path $installer.FullName -Destination $destFile -Force
            return $destFile
        }
    }

    return $null
}

function Get-CachedInstaller {
    [CmdletBinding()]
    param(
        [string]$SoftwareName
    )

    # Common installer cache locations
    $cachePaths = @(
        "$env:TEMP",
        "$env:USERPROFILE\Downloads",
        "$env:USERPROFILE\Desktop",
        "C:\ProgramData\Package Cache",
        "$env:LOCALAPPDATA\Temp"
    )

    $softwareClean = $SoftwareName -replace '[^\w]', '*'

    foreach ($cachePath in $cachePaths) {
        if (Test-Path $cachePath) {
            $installers = Get-ChildItem -Path $cachePath -Filter "*$softwareClean*" -Include "*.exe", "*.msi" -File -Recurse -Depth 2 -ErrorAction SilentlyContinue
            if ($installers) {
                return $installers | Select-Object -First 1
            }
        }
    }

    return $null
}

function Download-Installer {
    [CmdletBinding()]
    param(
        [string]$Url,
        [string]$DestinationPath,
        [string]$FileName
    )

    if (-not $Url) { return $null }

    try {
        $destFile = Join-Path $DestinationPath $FileName
        Write-Host "Downloading $FileName..." -ForegroundColor Yellow

        # Use BITS for better download handling
        $bitsJob = Start-BitsTransfer -Source $Url -Destination $destFile -ErrorAction Stop
        return $destFile
    } catch {
        # Fallback to WebClient
        try {
            $webClient = New-Object System.Net.WebClient
            $webClient.DownloadFile($Url, $destFile)
            return $destFile
        } catch {
            Write-Warning "Failed to download from $Url : $_"
            return $null
        }
    }
}

function Get-SoftwareInstallers {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$SoftwareList,
        [Parameter(Mandatory)]
        [string]$OutputPath,
        [switch]$DownloadAvailable,
        [switch]$CopyExisting
    )

    Write-Host "  Gathering installer information..." -ForegroundColor Cyan

    $installerPath = Join-Path $OutputPath "Installers"
    New-Item -Path $installerPath -ItemType Directory -Force | Out-Null

    $installerInfo = @()
    $total = $SoftwareList.Count
    $current = 0
    $startTime = Get-Date

    foreach ($software in $SoftwareList) {
        $current++
        $name = $software.SoftwareName
        if (-not $name) { $name = $software.Name }
        if (-not $name) { continue }

        # Text-based progress (every 25 items to reduce output)
        if ($current % 25 -eq 0 -or $current -eq $total -or $current -eq 1) {
            $percent = [math]::Round(($current / $total) * 100)
            $elapsed = (Get-Date) - $startTime
            $itemsPerSec = if ($elapsed.TotalSeconds -gt 0) { $current / $elapsed.TotalSeconds } else { 0 }
            $remaining = if ($itemsPerSec -gt 0) { ($total - $current) / $itemsPerSec } else { 0 }
            $eta = if ($remaining -gt 0) { [timespan]::FromSeconds($remaining).ToString("mm\:ss") } else { "--:--" }
            Write-Host "`r    Processing installers: $current/$total ($percent%) ETA: $eta - $name".PadRight(80) -NoNewline -ForegroundColor Gray
        }

        $info = [PSCustomObject]@{
            SoftwareName = $name
            Version = $software.Version
            Publisher = $software.Publisher
            InstallMethod = $software.InstallMethod
            WingetId = $software.WingetId
            ChocolateyId = $software.ChocolateyId
            DownloadUrl = $null
            InstallerPath = $null
            InstallerSource = $null
            Notes = $null
        }

        # Skip if available via package manager
        if ($software.WingetId -or $software.ChocolateyId) {
            $info.Notes = "Available via package manager"
            $installerInfo += $info
            continue
        }

        # Try to get download URL
        $info.DownloadUrl = Get-DownloadUrl -SoftwareName $name -Publisher $software.Publisher

        # Try to find cached installer
        $cached = Get-CachedInstaller -SoftwareName $name
        if ($cached) {
            if ($CopyExisting) {
                $destFile = Join-Path $installerPath $cached.Name
                Copy-Item -Path $cached.FullName -Destination $destFile -Force
                $info.InstallerPath = $destFile
                $info.InstallerSource = "Cached"
            } else {
                $info.InstallerPath = $cached.FullName
                $info.InstallerSource = "Cached (not copied)"
            }
        }

        # Try to copy from install location
        if (-not $info.InstallerPath -and $CopyExisting -and $software.InstallLocation) {
            $copied = Copy-ExistingInstaller -SoftwareName $name -InstallLocation $software.InstallLocation -DestinationPath $installerPath
            if ($copied) {
                $info.InstallerPath = $copied
                $info.InstallerSource = "InstallLocation"
            }
        }

        # Download if requested and URL available
        if (-not $info.InstallerPath -and $DownloadAvailable -and $info.DownloadUrl) {
            $fileName = "$($name -replace '[^\w]', '_').exe"
            $downloaded = Download-Installer -Url $info.DownloadUrl -DestinationPath $installerPath -FileName $fileName
            if ($downloaded) {
                $info.InstallerPath = $downloaded
                $info.InstallerSource = "Downloaded"
            }
        }

        if (-not $info.InstallerPath -and -not $info.DownloadUrl) {
            $info.Notes = "Manual download required - search online for installer"
        }

        $installerInfo += $info
    }

    Write-Host ""  # Clear the progress line

    # Summary
    $packageManager = ($installerInfo | Where-Object { $_.WingetId -or $_.ChocolateyId }).Count
    $hasInstaller = ($installerInfo | Where-Object { $_.InstallerPath }).Count
    $hasUrl = ($installerInfo | Where-Object { $_.DownloadUrl -and -not $_.InstallerPath }).Count
    $manual = ($installerInfo | Where-Object { -not $_.WingetId -and -not $_.ChocolateyId -and -not $_.InstallerPath -and -not $_.DownloadUrl }).Count

    Write-Host "Installer gathering complete:" -ForegroundColor Green
    Write-Host "  - Package manager available: $packageManager" -ForegroundColor White
    Write-Host "  - Installer files gathered: $hasInstaller" -ForegroundColor White
    Write-Host "  - Download URLs found: $hasUrl" -ForegroundColor White
    Write-Host "  - Manual download needed: $manual" -ForegroundColor White

    return $installerInfo
}

function Export-InstallerInfo {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$InstallerInfo,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    $InstallerInfo | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Installer info saved to: $OutputPath" -ForegroundColor Green

    # Manual download list now generated during restore to ensure fresh URLs and correct architecture.
    Write-Host "Manual download list will be generated during restore" -ForegroundColor Yellow
}

# Functions are available when dot-sourced
