# Main Scanner - Orchestrates all scanning operations
# Run this script on your current system to gather all information

param(
    [string]$OutputPath = ".\ReWin_Backup",
    [switch]$SkipPackageMapping,
    [switch]$DownloadInstallers,
    [switch]$BackupAppConfigs
)

# ============================================================================
# CTRL+C HANDLER - Allow graceful exit
# ============================================================================

$script:CancelRequested = $false

# Set up Ctrl+C handler
[Console]::TreatControlCAsInput = $false
$null = Register-EngineEvent -SourceIdentifier PowerShell.Exiting -Action {
    $script:CancelRequested = $true
} -SupportEvent

trap {
    Write-Host "`n`nScan interrupted by user (Ctrl+C)" -ForegroundColor Yellow
    Write-Host "Partial results may have been saved to the output folder." -ForegroundColor Gray
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 0
}

# Function to check if user wants to cancel
function Test-CancelRequested {
    if ([Console]::KeyAvailable) {
        $key = [Console]::ReadKey($true)
        if ($key.Key -eq 'C' -and $key.Modifiers -eq 'Control') {
            return $true
        }
    }
    return $script:CancelRequested
}

# ============================================================================
# LOGGING SYSTEM
# ============================================================================

$script:LogMessages = [System.Collections.ArrayList]::new()
$script:ErrorCount = 0
$script:WarningCount = 0

function Write-Log {
    param(
        [string]$Message,
        [ValidateSet('Info', 'Success', 'Warning', 'Error', 'Progress', 'Detail')]
        [string]$Level = 'Info',
        [switch]$NoNewLine
    )

    $timestamp = Get-Date -Format "HH:mm:ss"
    $logEntry = "[$timestamp] [$Level] $Message"
    [void]$script:LogMessages.Add($logEntry)

    $color = switch ($Level) {
        'Info'     { 'White' }
        'Success'  { 'Green' }
        'Warning'  { 'Yellow'; $script:WarningCount++ }
        'Error'    { 'Red'; $script:ErrorCount++ }
        'Progress' { 'Cyan' }
        'Detail'   { 'Gray' }
    }

    if ($NoNewLine) {
        Write-Host $Message -ForegroundColor $color -NoNewline
    } else {
        Write-Host $Message -ForegroundColor $color
    }
}

function Write-StepHeader {
    param(
        [int]$StepNumber,
        [int]$TotalSteps,
        [string]$StepName
    )

    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray
    Write-Log "[$StepNumber/$TotalSteps] $StepName" -Level Progress
    Write-Host ("=" * 60) -ForegroundColor DarkGray
}

function Write-SubProgress {
    param(
        [string]$Message,
        [int]$Current = 0,
        [int]$Total = 0
    )

    if ($Total -gt 0) {
        $percent = [math]::Round(($Current / $Total) * 100)
        Write-Log "  -> $Message ($Current/$Total - $percent%)" -Level Detail
    } else {
        Write-Log "  -> $Message" -Level Detail
    }
}

function Save-ScanLog {
    param(
        [string]$OutputPath,
        [string]$SummaryText
    )

    # Write concise summary (matches terminal output)
    if ($SummaryText) {
        $SummaryText | Out-File -FilePath "$OutputPath\scan_log.txt" -Encoding UTF8
        Write-Log "Summary saved to: $OutputPath\scan_log.txt" -Level Info
    }

    # Write detailed step-by-step log for troubleshooting
    $detailedLog = @"
================================================================================
REWIN MIGRATION TOOL - DETAILED LOG
================================================================================
Generated: $(Get-Date -Format "yyyy-MM-dd HH:mm:ss")
Computer: $env:COMPUTERNAME
User: $env:USERNAME

SUMMARY: $($script:ErrorCount) errors, $($script:WarningCount) warnings

================================================================================
DETAILED LOG
================================================================================

$($script:LogMessages -join "`n")

================================================================================
END OF LOG
================================================================================
"@

    $detailedLog | Out-File -FilePath "$OutputPath\scan_debug.txt" -Encoding UTF8
    Write-Log "Detailed log saved to: $OutputPath\scan_debug.txt" -Level Info
}

# ============================================================================
# SCRIPT INITIALIZATION
# ============================================================================

# Get script directory - handle both direct execution and dot-sourcing
$ScriptDir = $null
if ($MyInvocation.MyCommand.Path) {
    $ScriptDir = Split-Path -Parent $MyInvocation.MyCommand.Path
} elseif ($PSScriptRoot) {
    $ScriptDir = $PSScriptRoot
} else {
    # Fallback: try to find the script directory based on known structure
    $possiblePaths = @(
        "$env:USERPROFILE\ReWin\src\scanner",
        ".\src\scanner",
        "..\scanner",
        "..\.\scanner"
    )
    foreach ($path in $possiblePaths) {
        if (Test-Path "$path\software_scanner.ps1") {
            $ScriptDir = $path
            break
        }
    }
}

if (-not $ScriptDir -or -not (Test-Path $ScriptDir)) {
    Write-Host "ERROR: Cannot determine script directory." -ForegroundColor Red
    Write-Host "Please run this script directly using: powershell -File main_scanner.ps1" -ForegroundColor Yellow
    Write-Host "`nPress any key to exit..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
    exit 1
}

# Import modules with error handling
$modulesToLoad = @(
    @{ Name = "Software Scanner"; Path = "$ScriptDir\software_scanner.ps1" },
    @{ Name = "License Extractor"; Path = "$ScriptDir\license_extractor.ps1" },
    @{ Name = "Package Mapper"; Path = "$ScriptDir\package_mapper.ps1" },
    @{ Name = "Config Backup"; Path = "$ScriptDir\..\backup\config_backup.ps1" },
    @{ Name = "Installer Downloader"; Path = "$ScriptDir\..\backup\installer_downloader.ps1" }
)

Write-Host "Loading modules..." -ForegroundColor Gray
foreach ($module in $modulesToLoad) {
    try {
        if (Test-Path $module.Path) {
            . $module.Path
            Write-Host "  [OK] $($module.Name)" -ForegroundColor Green
        } else {
            Write-Host "  [MISSING] $($module.Name): $($module.Path)" -ForegroundColor Red
        }
    } catch {
        Write-Host "  [ERROR] $($module.Name): $_" -ForegroundColor Red
    }
}

# ============================================================================
# MAIN SCANNER FUNCTION
# ============================================================================

function Start-FullScan {
    [CmdletBinding()]
    param(
        [string]$OutputPath,
        [switch]$SkipPackageMapping,
        [switch]$DownloadInstallers,
        [switch]$BackupAppConfigs
    )

    # Clear previous log
    $script:LogMessages.Clear()
    $script:ErrorCount = 0
    $script:WarningCount = 0

    Write-Host @"

 +====================================================================+
 :                                                                    :
 :                   ReWin Migration Tool                           :
 :                     System Scanner v1.0                            :
 :                                                                    :
 +====================================================================+

"@ -ForegroundColor Cyan

    Write-Host "  Press Ctrl+C at any time to cancel the scan" -ForegroundColor DarkGray
    Write-Host ""

    # Create output directory
    $timestamp = Get-Date -Format "yyyy-MM-dd_HHmmss"
    $fullOutputPath = Join-Path $OutputPath "Scan_$timestamp"

    try {
        New-Item -Path $fullOutputPath -ItemType Directory -Force | Out-Null
        Write-Log "Output directory created: $fullOutputPath" -Level Success
    } catch {
        Write-Log "Failed to create output directory: $_" -Level Error
        Write-Host "`nPress any key to exit..." -ForegroundColor Gray
        $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")
        return
    }

    Write-Log "Scan started at $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')" -Level Info
    Write-Log "Computer: $env:COMPUTERNAME | User: $env:USERNAME" -Level Info

    $scanResults = @{
        ScanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $env:COMPUTERNAME
        UserName = $env:USERNAME
        WindowsVersion = $null
        OutputPath = $fullOutputPath
        Errors = @()
    }

    # Get Windows version
    try {
        $scanResults.WindowsVersion = (Get-CimInstance Win32_OperatingSystem).Caption
        Write-Log "Windows: $($scanResults.WindowsVersion)" -Level Info
    } catch {
        Write-Log "Could not detect Windows version: $_" -Level Warning
        $scanResults.WindowsVersion = "Unknown"
    }

    $totalSteps = 5
    $softwareInventory = $null
    $licenses = $null
    $configBackup = $null
    $packageMappings = $null
    $installerInfo = $null

    # ========================================================================
    # STEP 1: Scan installed software
    # ========================================================================
    Write-StepHeader -StepNumber 1 -TotalSteps $totalSteps -StepName "Scanning Installed Software"

    try {
        Write-SubProgress "Scanning Windows Registry for installed programs..."
        $installedSoftware = Get-InstalledSoftware
        Write-Log "  Found $($installedSoftware.Count) installed programs" -Level Success

        Write-SubProgress "Scanning Microsoft Store apps..."
        $storeApps = Get-StoreApps
        Write-Log "  Found $($storeApps.Count) Store apps" -Level Success

        Write-SubProgress "Checking Winget packages..."
        $wingetPackages = @()
        try {
            $wingetPackages = Get-WingetPackages
            Write-Log "  Found $($wingetPackages.Count) Winget packages" -Level Success
        } catch {
            Write-Log "  Winget not available or error: $_" -Level Warning
        }

        Write-SubProgress "Checking Chocolatey packages..."
        $chocoPackages = @()
        try {
            $chocoPackages = Get-ChocolateyPackages
            Write-Log "  Found $($chocoPackages.Count) Chocolatey packages" -Level Success
        } catch {
            Write-Log "  Chocolatey not available or error: $_" -Level Warning
        }

        Write-SubProgress "Scanning for portable apps..."
        $portableApps = Get-PortableApps
        Write-Log "  Found $($portableApps.Count) portable apps" -Level Success

        Write-SubProgress "Scanning startup programs..."
        $startupPrograms = Get-StartupPrograms
        Write-Log "  Found $($startupPrograms.Count) startup programs" -Level Success

        $softwareInventory = @{
            ScanDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ComputerName = $env:COMPUTERNAME
            WindowsVersion = $scanResults.WindowsVersion
            InstalledSoftware = @($installedSoftware)
            StoreApps = @($storeApps)
            WingetPackages = @($wingetPackages)
            ChocolateyPackages = @($chocoPackages)
            PortableApps = @($portableApps)
            StartupPrograms = @($startupPrograms)
        }

        # Save to file
        Write-SubProgress "Saving software inventory..."
        Write-Host "    Writing JSON..." -ForegroundColor Gray -NoNewline
        $softwareInventory | ConvertTo-Json -Depth 5 -Compress | Out-File -FilePath "$fullOutputPath\software_inventory.json" -Encoding UTF8
        Write-Host " done." -ForegroundColor Green
        Write-Log "Software inventory saved" -Level Success

        $scanResults.Software = $softwareInventory

    } catch {
        Write-Log "ERROR in software scanning: $_" -Level Error
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
        $scanResults.Errors += "Step 1 (Software): $_"
    }

    # ========================================================================
    # STEP 2: Extract license keys
    # ========================================================================
    Write-StepHeader -StepNumber 2 -TotalSteps $totalSteps -StepName "Extracting License Keys"

    try {
        Write-SubProgress "Extracting Windows product key..."
        $windowsKey = $null
        try {
            $windowsKey = Get-WindowsProductKey
            if ($windowsKey.RecommendedKey) {
                Write-Log "  Windows key found" -Level Success
            } else {
                Write-Log "  Windows key not found in registry/BIOS" -Level Warning
            }
        } catch {
            Write-Log "  Error extracting Windows key: $_" -Level Warning
        }

        Write-SubProgress "Extracting Office product keys..."
        $officeKeys = @()
        try {
            $officeKeys = Get-OfficeProductKey
            Write-Log "  Found $($officeKeys.Count) Office installation(s)" -Level Success
        } catch {
            Write-Log "  Error extracting Office keys: $_" -Level Warning
        }

        Write-SubProgress "Scanning for Adobe serials..."
        $adobeKeys = @()
        try {
            $adobeKeys = Get-AdobeKeys
            Write-Log "  Found $($adobeKeys.Count) Adobe product(s)" -Level Success
        } catch {
            Write-Log "  Error scanning Adobe: $_" -Level Warning
        }

        Write-SubProgress "Scanning for other software keys..."
        $otherKeys = @()
        try {
            $otherKeys = Get-CommonSoftwareKeys
            Write-Log "  Found $($otherKeys.Count) other software key(s)" -Level Success
        } catch {
            Write-Log "  Error scanning other software: $_" -Level Warning
        }

        Write-SubProgress "Extracting WiFi passwords..."
        $wifiProfiles = @()
        try {
            $wifiProfiles = Get-WiFiPasswords
            Write-Log "  Found $($wifiProfiles.Count) WiFi profile(s)" -Level Success
        } catch {
            Write-Log "  Error extracting WiFi passwords (may need admin): $_" -Level Warning
        }

        $licenses = @{
            ExtractionDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ComputerName = $env:COMPUTERNAME
            Windows = $windowsKey
            Office = @($officeKeys)
            Adobe = @($adobeKeys)
            OtherSoftware = @($otherKeys)
            WiFiProfiles = @($wifiProfiles)
        }

        # Save to file
        Write-SubProgress "Saving license keys..."
        $licenses | ConvertTo-Json -Depth 5 | Out-File -FilePath "$fullOutputPath\license_keys.json" -Encoding UTF8
        Write-Log "License keys saved" -Level Success

        $scanResults.Licenses = $licenses

    } catch {
        Write-Log "ERROR in license extraction: $_" -Level Error
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
        $scanResults.Errors += "Step 2 (Licenses): $_"
    }

    # ========================================================================
    # STEP 3: Backup configurations
    # ========================================================================
    Write-StepHeader -StepNumber 3 -TotalSteps $totalSteps -StepName "Backing Up System Configuration"

    try {
        Write-SubProgress "Backing up environment variables..."
        $envVars = $null
        try {
            $envVars = Get-EnvironmentVariables
            $envCount = ($envVars.User.Keys.Count) + ($envVars.System.Keys.Count)
            Write-Log "  Found $envCount environment variables" -Level Success
        } catch {
            Write-Log "  Error backing up env vars: $_" -Level Warning
            $envVars = @{ User = @{}; System = @{} }
        }

        Write-SubProgress "Backing up scheduled tasks..."
        $tasks = @()
        try {
            $tasks = Get-ScheduledTasksBackup
            Write-Log "  Found $($tasks.Count) custom scheduled tasks" -Level Success
        } catch {
            Write-Log "  Error backing up scheduled tasks: $_" -Level Warning
        }

        Write-SubProgress "Backing up services configuration..."
        $services = @()
        try {
            $services = Get-ServicesConfiguration
            Write-Log "  Found $($services.Count) service configurations" -Level Success
        } catch {
            Write-Log "  Error backing up services: $_" -Level Warning
        }

        Write-SubProgress "Backing up network settings..."
        $network = $null
        try {
            $network = Get-NetworkConfiguration
            Write-Log "  Network configuration backed up" -Level Success
        } catch {
            Write-Log "  Error backing up network config: $_" -Level Warning
            $network = @{}
        }

        Write-SubProgress "Backing up file associations..."
        $fileAssoc = @()
        try {
            $fileAssoc = Get-FileAssociations
            Write-Log "  Found $($fileAssoc.Count) file associations" -Level Success
        } catch {
            Write-Log "  Error backing up file associations: $_" -Level Warning
        }

        Write-SubProgress "Backing up Windows settings..."
        $winSettings = $null
        try {
            $winSettings = Get-WindowsSettings
            Write-Log "  Windows settings backed up" -Level Success
        } catch {
            Write-Log "  Error backing up Windows settings: $_" -Level Warning
            $winSettings = @{}
        }

        Write-SubProgress "Scanning app-specific configs..."
        $appConfigs = $null
        try {
            $appConfigs = Get-AppSpecificConfigs
            Write-Log "  App configs scanned" -Level Success
        } catch {
            Write-Log "  Error scanning app configs: $_" -Level Warning
            $appConfigs = @{}
        }

        $configBackup = @{
            BackupDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
            ComputerName = $env:COMPUTERNAME
            UserName = $env:USERNAME
            EnvironmentVariables = $envVars
            ScheduledTasks = @($tasks)
            Services = @($services)
            Network = $network
            FileAssociations = @($fileAssoc)
            WindowsSettings = $winSettings
            AppConfigs = $appConfigs
        }

        # Backup app config files if requested
        if ($BackupAppConfigs) {
            Write-SubProgress "Copying application config files..."
            try {
                $backedUpFiles = Backup-AppConfigs -BackupPath $fullOutputPath
                $configBackup.BackedUpFiles = $backedUpFiles
                Write-Log "  Copied $($backedUpFiles.Count) config files" -Level Success
            } catch {
                Write-Log "  Error copying config files: $_" -Level Warning
            }
        }

        # Save to file - use depth 5 to avoid slow serialization of complex objects
        Write-SubProgress "Saving configuration backup (this may take a moment)..."
        Write-Host "    Converting to JSON..." -ForegroundColor Gray -NoNewline
        $jsonContent = $configBackup | ConvertTo-Json -Depth 5 -Compress
        Write-Host " done. Writing file..." -ForegroundColor Gray -NoNewline
        $jsonContent | Out-File -FilePath "$fullOutputPath\config_backup.json" -Encoding UTF8
        Write-Host " done." -ForegroundColor Green
        Write-Log "Configuration backup saved" -Level Success

        $scanResults.Configuration = $configBackup

    } catch {
        Write-Log "ERROR in configuration backup: $_" -Level Error
        Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
        $scanResults.Errors += "Step 3 (Config): $_"
    }

    # ========================================================================
    # STEP 4: Map to package managers
    # ========================================================================
    Write-StepHeader -StepNumber 4 -TotalSteps $totalSteps -StepName "Mapping Software to Package Managers"

    if (-not $SkipPackageMapping -and $softwareInventory) {
        try {
            $softwareList = $softwareInventory.InstalledSoftware
            $total = $softwareList.Count
            $current = 0
            $mappings = @()

            Write-Log "Mapping $total programs to package managers..." -Level Info

            foreach ($software in $softwareList) {
                $current++
                $name = $software.Name
                if (-not $name) { continue }

                # Show progress every 20 items
                if ($current % 20 -eq 0 -or $current -eq $total) {
                    Write-SubProgress "Processing software" -Current $current -Total $total
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
                foreach ($key in $WingetMappings.Keys) {
                    if ($name -match [regex]::Escape($key)) {
                        $mapping.WingetId = $WingetMappings[$key]
                        $mapping.InstallMethod = "Winget"
                        break
                    }
                }

                # Check chocolatey mappings if no winget
                if (-not $mapping.WingetId) {
                    foreach ($key in $ChocolateyMappings.Keys) {
                        if ($name -match [regex]::Escape($key)) {
                            $mapping.ChocolateyId = $ChocolateyMappings[$key]
                            $mapping.InstallMethod = "Chocolatey"
                            break
                        }
                    }
                }

                $mappings += $mapping
            }

            $packageMappings = $mappings

            # Summary
            $wingetCount = ($mappings | Where-Object { $_.WingetId }).Count
            $chocoCount = ($mappings | Where-Object { $_.ChocolateyId -and -not $_.WingetId }).Count
            $manualCount = ($mappings | Where-Object { $_.InstallMethod -eq "Manual" }).Count

            Write-Log "Winget available: $wingetCount" -Level Success
            Write-Log "Chocolatey only: $chocoCount" -Level Success
            Write-Log "Manual install needed: $manualCount" -Level Warning

            # Save and generate scripts
            Write-SubProgress "Saving package mappings and generating install scripts..."
            Export-PackageMappings -Mappings $packageMappings -OutputPath "$fullOutputPath\package_mappings.json"
            Write-Log "Package mappings saved" -Level Success

            $scanResults.PackageMappings = $packageMappings

        } catch {
            Write-Log "ERROR in package mapping: $_" -Level Error
            Write-Log "Stack trace: $($_.ScriptStackTrace)" -Level Error
            $scanResults.Errors += "Step 4 (Mapping): $_"
        }
    } else {
        Write-Log "Skipping package mapping (disabled or no software data)" -Level Warning
    }

    # ========================================================================
    # STEP 5: Installer Information (Moved to Restore Phase)
    # ========================================================================
    # NOTE: Manual download resolution now happens at RESTORE TIME via manual_download_resolver.ps1
    # This provides fresh URLs, architecture detection, and live GitHub/vendor lookups.
    # The scan phase is now lightweight - no installer gathering needed.
    Write-StepHeader -StepNumber 5 -TotalSteps $totalSteps -StepName "Installer Information (Deferred to Restore)"
    Write-Log "Manual download resolution deferred to restore phase" -Level Info
    Write-Log "  - Users can click 'Refresh Manual Downloads' in restore GUI" -Level Info
    Write-Log "  - Fresh URLs resolved at restore time with architecture detection" -Level Info

    # ========================================================================
    # FINALIZE
    # ========================================================================
    Write-Host ""
    Write-Host ("=" * 60) -ForegroundColor DarkGray

    # Save scan summary (lightweight version without full data)
    try {
        $summary = @{
            ScanDate = $scanResults.ScanDate
            ComputerName = $scanResults.ComputerName
            UserName = $scanResults.UserName
            WindowsVersion = $scanResults.WindowsVersion
            OutputPath = $scanResults.OutputPath
            Errors = $scanResults.Errors
            Stats = @{
                InstalledSoftware = if ($softwareInventory) { $softwareInventory.InstalledSoftware.Count } else { 0 }
                StoreApps = if ($softwareInventory) { $softwareInventory.StoreApps.Count } else { 0 }
                WingetPackages = if ($softwareInventory) { $softwareInventory.WingetPackages.Count } else { 0 }
                ChocolateyPackages = if ($softwareInventory) { $softwareInventory.ChocolateyPackages.Count } else { 0 }
                ScheduledTasks = if ($configBackup) { $configBackup.ScheduledTasks.Count } else { 0 }
                Services = if ($configBackup) { $configBackup.Services.Count } else { 0 }
                WiFiProfiles = if ($licenses) { $licenses.WiFiProfiles.Count } else { 0 }
            }
        }
        $summary | ConvertTo-Json -Depth 3 | Out-File -FilePath "$fullOutputPath\scan_summary.json" -Encoding UTF8
    } catch {
        Write-Log "Error saving scan summary: $_" -Level Error
    }

    # Generate summary report
    $errorSummary = if ($script:ErrorCount -gt 0) {
        "`n  ERRORS: $($script:ErrorCount) - Check scan_debug.txt for details"
    } else { "" }

    $warningSummary = if ($script:WarningCount -gt 0) {
        "`n  WARNINGS: $($script:WarningCount) - Some items may need attention"
    } else { "" }

    $softwareStats = if ($softwareInventory) {
        @"

SOFTWARE FOUND:
  Installed Programs:     $($softwareInventory.InstalledSoftware.Count)
  Microsoft Store Apps:   $($softwareInventory.StoreApps.Count)
  Winget Packages:        $($softwareInventory.WingetPackages.Count)
  Chocolatey Packages:    $($softwareInventory.ChocolateyPackages.Count)
  Portable Apps:          $($softwareInventory.PortableApps.Count)
  Startup Programs:       $($softwareInventory.StartupPrograms.Count)
"@
    } else { "`nSOFTWARE: Scan failed - check log" }

    $licenseStats = if ($licenses) {
        @"

LICENSE KEYS:
  Windows Key:            $(if ($licenses.Windows.RecommendedKey) { 'Found' } else { 'Not Found' })
  Office:                 $($licenses.Office.Count) installation(s)
  WiFi Profiles:          $($licenses.WiFiProfiles.Count)
  Other Software:         $($licenses.OtherSoftware.Count)
"@
    } else { "`nLICENSES: Scan failed - check log" }

    $configStats = if ($configBackup) {
        @"

CONFIGURATION:
  Environment Variables:  $($configBackup.EnvironmentVariables.User.Count + $configBackup.EnvironmentVariables.System.Count)
  Scheduled Tasks:        $($configBackup.ScheduledTasks.Count)
  Services:               $($configBackup.Services.Count)
  File Associations:      $($configBackup.FileAssociations.Count)
"@
    } else { "`nCONFIGURATION: Scan failed - check log" }

    $packageStats = if ($packageMappings) {
        @"

PACKAGE MANAGER AVAILABILITY:
  Available via Winget:   $(($packageMappings | Where-Object { $_.WingetId }).Count)
  Available via Choco:    $(($packageMappings | Where-Object { $_.ChocolateyId -and -not $_.WingetId }).Count)
  Manual Install Needed:  $(($packageMappings | Where-Object { $_.InstallMethod -eq 'Manual' }).Count)
"@
    } else { "" }

    $statusColor = if ($script:ErrorCount -gt 0) { "Red" } elseif ($script:WarningCount -gt 0) { "Yellow" } else { "Green" }
    $statusText = if ($script:ErrorCount -gt 0) { "COMPLETED WITH ERRORS" } elseif ($script:WarningCount -gt 0) { "COMPLETED WITH WARNINGS" } else { "SCAN COMPLETE" }

    # Build summary text (matches on-screen output) for scan_log.txt
    $summaryContent = @"
 +====================================================================+
 :                      $statusText                        :
 +====================================================================+

Computer: $($scanResults.ComputerName)
User: $($scanResults.UserName)
Windows: $($scanResults.WindowsVersion)
Scan Date: $($scanResults.ScanDate)

$(if ($errorSummary) { $errorSummary })
$(if ($warningSummary) { $warningSummary })
$softwareStats
$licenseStats
$configStats
$packageStats

OUTPUT FILES:
    $fullOutputPath\
        - software_inventory.json
        - license_keys.json
        - config_backup.json
        - package_mappings.json
        - install_winget.ps1
        - install_chocolatey.ps1
        - scan_log.txt  (summary)
        - scan_debug.txt (detailed)
"@

        # Save logs: summary (scan_log.txt) and full detail (scan_debug.txt)
        Save-ScanLog -OutputPath $fullOutputPath -SummaryText $summaryContent

    Write-Host @"

 +====================================================================+
 :                      $statusText                        :
 +====================================================================+

"@ -ForegroundColor $statusColor

    Write-Host "Computer: $($scanResults.ComputerName)" -ForegroundColor White
    Write-Host "User: $($scanResults.UserName)" -ForegroundColor White
    Write-Host "Windows: $($scanResults.WindowsVersion)" -ForegroundColor White
    Write-Host "Scan Date: $($scanResults.ScanDate)" -ForegroundColor White

    if ($errorSummary) { Write-Host $errorSummary -ForegroundColor Red }
    if ($warningSummary) { Write-Host $warningSummary -ForegroundColor Yellow }

    Write-Host $softwareStats -ForegroundColor White
    Write-Host $licenseStats -ForegroundColor White
    Write-Host $configStats -ForegroundColor White
    Write-Host $packageStats -ForegroundColor White

    Write-Host @"

OUTPUT FILES:
  $fullOutputPath\
    - software_inventory.json
    - license_keys.json
    - config_backup.json
    - package_mappings.json
    - install_winget.ps1
    - install_chocolatey.ps1
    - scan_log.txt    (summary)
    - scan_debug.txt  (detailed)

"@ -ForegroundColor Gray

    if ($script:ErrorCount -gt 0) {
        Write-Host "Some errors occurred during scanning." -ForegroundColor Red
        Write-Host "Check scan_debug.txt for details." -ForegroundColor Red
        Write-Host ""
    }

    Write-Host "Press any key to continue..." -ForegroundColor Gray
    $null = $Host.UI.RawUI.ReadKey("NoEcho,IncludeKeyDown")

    return $scanResults
}

# Run the scanner
if ($MyInvocation.InvocationName -ne '.') {
    Start-FullScan -OutputPath $OutputPath -SkipPackageMapping:$SkipPackageMapping -DownloadInstallers:$DownloadInstallers -BackupAppConfigs:$BackupAppConfigs
}
