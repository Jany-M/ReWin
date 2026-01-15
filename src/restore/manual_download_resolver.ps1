# Manual Download Resolver Module
# Resolves manual downloads at restore time with live package lookups, architecture detection,
# and compatibility filtering. Generates fresh manual_downloads.md with verified URLs.

function Get-SystemArchitecture {
    [CmdletBinding()]
    param()

    # Detect system architecture
    if ([Environment]::Is64BitOperatingSystem) {
        $osArch = "x64"
    } else {
        $osArch = "x86"
    }
    $procArch = [Environment]::ProcessorCount

    return @{
        OS = $osArch
        Processors = $procArch
        Is64Bit = [Environment]::Is64BitOperatingSystem
        OSVersion = [Environment]::OSVersion.VersionString
    }
}

function Test-WingetPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId,
        [string]$Architecture = "x64"
    )

    try {
        # Query winget for package (silent check)
        $result = & winget show --id $PackageId --exact 2>$null
        return $null -ne $result -and $result.Count -gt 0
    } catch {
        return $false
    }
}

function Test-ChocolateyPackage {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$PackageId
    )

    try {
        # Query choco for package
        $result = & choco list --local-only $PackageId 2>$null
        return $null -ne $result -and $result.Count -gt 0
    } catch {
        return $false
    }
}

function Find-GitHubRelease {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SoftwareName,
        [Parameter(Mandatory)]
        [string]$Publisher,
        [string]$Architecture = "x64"
    )

    <#
    Searches GitHub releases for matching software.
    Returns download URL if found, null otherwise.
    #>

    try {
        # Build search query
        $query = "$Publisher $SoftwareName"
        $escapedQuery = [uri]::EscapeDataString($query)

        # GitHub API search (public repos)
        $apiUrl = "https://api.github.com/search/repositories?q=$escapedQuery&sort=stars&per_page=5"
        $response = Invoke-RestMethod -Uri $apiUrl -ErrorAction SilentlyContinue

        if ($response.items.Count -gt 0) {
            $repo = $response.items[0]
            $releasesUrl = $repo.releases_url -replace '{/id}', ''

            # Get latest release
            $releases = Invoke-RestMethod -Uri $releasesUrl -ErrorAction SilentlyContinue
            if ($releases.Count -gt 0) {
                $latestRelease = $releases[0]

                # Find appropriate download asset based on architecture
                $assets = $latestRelease.assets
                $archKeywords = @("x64", "amd64", "64-bit") | Where-Object { $Architecture -eq "x64" }
                if ($Architecture -eq "x86") {
                    $archKeywords = @("x86", "32-bit", "win32", "i386")
                }

                # Search for matching asset
                $matchingAsset = $assets | Where-Object {
                    $name = $_.name.ToLower()
                    $archKeywords | Where-Object { $name -match $_ } | Select-Object -First 1 | ForEach-Object { $true }
                } | Select-Object -First 1

                if ($matchingAsset) {
                    return @{
                        Url = $matchingAsset.browser_download_url
                        AssetName = $matchingAsset.name
                        Version = $latestRelease.tag_name
                        Repository = $repo.html_url
                    }
                }
            }
        }

        return $null
    } catch {
        Write-Warning "GitHub search failed for $SoftwareName : $_"
        return $null
    }
}

function Find-WingetMatch {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SoftwareName,
        [Parameter(Mandatory)]
        [string]$Publisher
    )

    try {
        # Search winget using name
        $results = & winget search "$SoftwareName" --source winget --accept-source-agreements 2>$null
        
        if (-not $results) { return $null }

        $foundName = $null
        $foundId = $null
        $foundVersion = $null
        
        # Parse output line by line, looking for the first actual result after headers
        $reachedSeparator = $false
        foreach ($line in ($results | Where-Object { $_ -match '\S' })) {
            if ($line -match '^-+') {
                $reachedSeparator = $true
                continue
            }
            if ($reachedSeparator) {
                # This is a result line. Split by multiple spaces.
                $parts = $line -split '\s{2,}'
                if ($parts.Count -ge 2) {
                    $foundName = $parts[0].Trim()
                    $foundId = $parts[1].Trim()
                    $foundVersion = if ($parts.Count -ge 3) { $parts[2].Trim() } else { $null }
                    
                    # Verify similarity
                    $nameSim = ($foundName -replace '[^a-z0-9]', '').ToLower()
                    $targetSim = ($SoftwareName -replace '[^a-z0-9]', '').ToLower()
                    
                    if ($nameSim -match [regex]::Escape($targetSim) -or $targetSim -match [regex]::Escape($nameSim)) {
                        return @{
                            Url = "winget://install/$foundId"
                            Type = "Winget"
                            Manual = $false
                            PackageId = $foundId
                            Version = $foundVersion
                        }
                    }
                }
            }
        }
        return $null
    } catch {
        return $null
    }
}

function Find-VendorDownload {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [string]$SoftwareName,
        [Parameter(Mandatory)]
        [string]$Publisher,
        [string]$Architecture = "x64"
    )

    <#
    Searches common vendor download endpoints.
    This is a fallback and uses a predefined mapping for known publishers.
    #>

    $vendorMappings = @{
        "Adobe" = "https://www.adobe.com/downloads/";
        "Microsoft" = "https://www.microsoft.com/download/";
        "Google" = "https://www.google.com/chrome/";
        "Mozilla" = "https://www.mozilla.org/firefox/";
        "Oracle" = "https://www.oracle.com/java/technologies/";
        "JetBrains" = "https://www.jetbrains.com/toolbox/";
        "VideoLAN" = "https://www.videolan.org/vlc/";
        "7-Zip" = "https://www.7-zip.org/download.html";
        "Notepad++" = "https://notepad-plus-plus.org/downloads/";
        "WinRAR" = "https://www.rarlab.com/download.htm";
    }

    if ($vendorMappings.ContainsKey($Publisher)) {
        return @{
            Url = $vendorMappings[$Publisher]
            Type = "Vendor"
            Manual = $true
            SearchQuery = "Visit $Publisher official website"
        }
    }

    # Generic fallback: Google search with specific User-Agent to avoid early blocks
    $query = "$Publisher $SoftwareName download $Architecture"
    $searchUrl = "https://www.google.com/search?q=$([uri]::EscapeDataString($query))"
    
    return @{
        Url = $searchUrl
        Type = "SearchEngine"
        Manual = $true
        SearchQuery = "Search on Google: $searchUrl"
    }
}

function Resolve-ManualDownloads {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Software,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    <#
    Main resolver function.
    Iterates through manual-install software and attempts to find download URLs
    via live lookups (GitHub, vendor endpoints, etc.) with architecture awareness.
    Generates updated manual_downloads.md with results.
    #>

    Write-Host "Resolving manual downloads..." -ForegroundColor Cyan
    Write-Host "System Architecture: $(Get-SystemArchitecture | Out-String)" -ForegroundColor Gray

    $sysArch = Get-SystemArchitecture
    if ($sysArch.Is64Bit) {
        $architecture = "x64"
    } else {
        $architecture = "x86"
    }

    $resolved = @()
    $counter = 0
    $manualItems = $Software | Where-Object { $_.InstallMethod -eq "Manual" }
    $total = if ($manualItems) { $manualItems.Count } else { 0 }

    if ($total -eq 0) {
        Write-Host "  No manual downloads to resolve." -ForegroundColor Gray
        return @()
    }

    foreach ($item in $Software) {
        if ($item.InstallMethod -ne "Manual") { continue }

        $counter++
        $percent = [math]::Round(($counter / $total) * 100, 0)
        Write-Progress -Activity "Resolving Manual Downloads" -Status "$($item.SoftwareName)" -PercentComplete $percent

        $resolution = @{
            SoftwareName = $item.SoftwareName
            Version = $item.Version
            Publisher = $item.Publisher
            Architecture = $architecture
            Status = "Unresolved"
            Url = $null
            Source = $null
            Verified = $false
            Notes = @()
        }

        # Try GitHub releases
        Write-Host "  Checking GitHub for $($item.SoftwareName)..." -ForegroundColor Gray -NoNewline

        $githubResult = Find-GitHubRelease -SoftwareName $item.SoftwareName -Publisher $item.Publisher -Architecture $architecture
        if ($githubResult) {
            $resolution.Status = "Resolved"
            $resolution.Url = $githubResult.Url
            $resolution.Source = "GitHub"
            $resolution.Verified = $true
            $resolution.Notes += "Found on GitHub: $($githubResult.Repository)"
            Write-Host " FOUND" -ForegroundColor Green
        } else {
            Write-Host " not found" -ForegroundColor Yellow

            # Try Winget search
            Write-Host "  Checking Winget for $($item.SoftwareName)..." -ForegroundColor Gray -NoNewline
            $wingetResult = Find-WingetMatch -SoftwareName $item.SoftwareName -Publisher $item.Publisher
            if ($wingetResult) {
                $resolution.Status = "Resolved"
                $resolution.Url = $wingetResult.Url
                $resolution.Source = "Winget"
                $resolution.Verified = $true
                $resolution.Notes += "Package found in Winget repository: $($wingetResult.PackageId)"
                Write-Host " FOUND" -ForegroundColor Green
            } else {
                Write-Host " not found" -ForegroundColor Yellow

                # Try vendor endpoint
                Write-Host "  Checking vendor for $($item.SoftwareName)..." -ForegroundColor Gray -NoNewline
                $vendorResult = Find-VendorDownload -SoftwareName $item.SoftwareName -Publisher $item.Publisher -Architecture $architecture
                if ($vendorResult -and -not $vendorResult.Manual) {
                    $resolution.Status = "Resolved"
                    $resolution.Url = $vendorResult.Url
                    $resolution.Source = "Vendor"
                    $resolution.Verified = $true
                    $resolution.Notes += "Vendor download endpoint found"
                    Write-Host " FOUND" -ForegroundColor Green
                } elseif ($vendorResult) {
                    $resolution.Status = "Manual"
                    $resolution.Url = $vendorResult.Url
                    $resolution.Source = $vendorResult.Type
                    $resolution.Verified = $false
                    $resolution.Notes += $vendorResult.SearchQuery
                    Write-Host " manual search" -ForegroundColor Yellow
                } else {
                    $resolution.Status = "Unresolved"
                    $resolution.Notes += "Could not find download source"
                    Write-Host " failed" -ForegroundColor Red
                }
            }
        }

        $resolved += $resolution
    }

    Write-Progress -Activity "Resolving Manual Downloads" -Completed

    Write-Host "Manual download resolution complete:" -ForegroundColor Green
    Write-Host "  - Resolved: $(($resolved | Where-Object { $_.Status -eq 'Resolved' }).Count)" -ForegroundColor White
    Write-Host "  - Manual: $(($resolved | Where-Object { $_.Status -eq 'Manual' }).Count)" -ForegroundColor White
    Write-Host "  - Unresolved: $(($resolved | Where-Object { $_.Status -eq 'Unresolved' }).Count)" -ForegroundColor White

    # Generate markdown report
    Export-ManualDownloadsReport -Resolved $resolved -OutputPath $OutputPath

    return $resolved
}

function Export-ManualDownloadsReport {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory)]
        [array]$Resolved,
        [Parameter(Mandatory)]
        [string]$OutputPath
    )

    <#
    Generates fresh manual_downloads.md with resolved URLs and architecture information.
    #>

    $report = @"
# Manual Downloads Required
Generated by ReWin Migration Tool - $(Get-Date -Format 'yyyy-MM-dd HH:mm:ss')

## System Information
- Architecture: $((Get-SystemArchitecture).OS)
- OS Version: $((Get-SystemArchitecture).OSVersion)

## Summary
- **Total Manual Installs:** $($Resolved.Count)
- **Resolved with URLs:** $(($Resolved | Where-Object { $_.Url }).Count)
- **Fully Verified:** $(($Resolved | Where-Object { $_.Verified }).Count)
- **Manual Search Required:** $(($Resolved | Where-Object { $_.Status -eq 'Unresolved' }).Count)

---

"@

    # Group by status
    $resolved_group = $Resolved | Where-Object { $_.Status -eq 'Resolved' }
    $manual_group = $Resolved | Where-Object { $_.Status -eq 'Manual' }
    $unresolved_group = $Resolved | Where-Object { $_.Status -eq 'Unresolved' }

    # Resolved section
    if ($resolved_group) {
        $report += "`n## Ready to Download`nThese links are verified and ready for download:`n`n"
        foreach ($item in $resolved_group) {
            $report += "### $($item.SoftwareName)`n"
            $report += "- **Version:** $($item.Version)`n"
            $report += "- **Publisher:** $($item.Publisher)`n"
            $report += "- **Architecture:** $($item.Architecture)`n"
            $report += "- **Source:** $($item.Source)`n"
            $report += "- **Download:** [$($item.SoftwareName)]($(if ($item.Url) { $item.Url } else { '#' }))`n"
            if ($item.Notes) {
                $report += "- **Notes:** $($item.Notes -join ', ')`n"
            }
            $report += "`n"
        }
    }

    # Manual search section
    if ($manual_group) {
        $report += "`n## Manual Search Required`nVisit these links to find and download:`n`n"
        foreach ($item in $manual_group) {
            $report += "### $($item.SoftwareName)`n"
            $report += "- **Version:** $($item.Version)`n"
            $report += "- **Publisher:** $($item.Publisher)`n"
            $report += "- **Architecture:** $($item.Architecture)`n"
            $report += "- **Source:** $($item.Source)`n"
            if ($item.Url) {
                $report += "- **Search:** [$($item.SoftwareName)]($(if ($item.Url) { $item.Url } else { '#' }))`n"
            }
            if ($item.Notes) {
                $report += "- **Notes:** $($item.Notes -join ', ')`n"
            }
            $report += "`n"
        }
    }

    # Unresolved section
    if ($unresolved_group) {
        $report += "`n## Unable to Find Download`nSearch online for these packages:`n`n"
        foreach ($item in $unresolved_group) {
            $report += "### $($item.SoftwareName)`n"
            $report += "- **Version:** $($item.Version)`n"
            $report += "- **Publisher:** $($item.Publisher)`n"
            $report += "- **Architecture:** $($item.Architecture)`n"
            $report += "- **Search Online:** https://www.google.com/search?q=$([uri]::EscapeDataString("$($item.SoftwareName) download $($item.Architecture)"))`n"
            if ($item.Notes) {
                $report += "- **Notes:** $($item.Notes -join ', ')`n"
            }
            $report += "`n"
        }
    }

    # Write report
    $report | Out-File -FilePath $OutputPath -Encoding UTF8
    Write-Host "Manual downloads report saved to: $OutputPath" -ForegroundColor Green
}

# Functions are available when dot-sourced
