# License Key Extractor
# Extracts license keys from Windows, Office, and other software

function Get-WindowsProductKey {
    [CmdletBinding()]
    param()

    try {
        # Method 1: Get key from BIOS (OEM key)
        $biosKey = (Get-CimInstance -Query "SELECT * FROM SoftwareLicensingService").OA3xOriginalProductKey

        # Method 2: Get key from registry (decoded)
        $registryKey = $null
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\SoftwareProtectionPlatform"
            if (Test-Path $regPath) {
                $regValue = Get-ItemProperty -Path $regPath -Name "BackupProductKeyDefault" -ErrorAction SilentlyContinue
                if ($regValue) {
                    $registryKey = $regValue.BackupProductKeyDefault
                }
            }
        } catch {}

        # Method 3: Decode from DigitalProductId
        $decodedKey = $null
        try {
            $regPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion"
            $digitalProductId = (Get-ItemProperty -Path $regPath).DigitalProductId
            if ($digitalProductId) {
                $decodedKey = Convert-DigitalProductIdToKey -DigitalProductId $digitalProductId
            }
        } catch {}

        # Method 4: Using slmgr (partial key only)
        $partialKey = $null
        try {
            $slmgrOutput = cscript //nologo "$env:SystemRoot\System32\slmgr.vbs" /dli 2>$null | Out-String
            if ($slmgrOutput -match "Partial Product Key:\s*(\S+)") {
                $partialKey = $matches[1]
            }
        } catch {}

        return [PSCustomObject]@{
            BiosKey = $biosKey
            RegistryKey = $registryKey
            DecodedKey = $decodedKey
            PartialKey = $partialKey
            RecommendedKey = if ($biosKey) { $biosKey } elseif ($registryKey) { $registryKey } elseif ($decodedKey) { $decodedKey } else { "Partial: $partialKey" }
        }
    } catch {
        Write-Warning "Error extracting Windows key: $_"
        return $null
    }
}

function Convert-DigitalProductIdToKey {
    param(
        [byte[]]$DigitalProductId
    )

    try {
        $keyOffset = 52
        $isWin8OrNewer = [math]::Floor($DigitalProductId[66] / 6) -band 1
        $DigitalProductId[66] = ($DigitalProductId[66] -band 0xF7) -bor (($isWin8OrNewer -band 2) * 4)

        $chars = "BCDFGHJKMPQRTVWXY2346789"
        $key = ""

        for ($i = 24; $i -ge 0; $i--) {
            $current = 0
            for ($j = 14; $j -ge 0; $j--) {
                $current = $current * 256
                $current = $DigitalProductId[$j + $keyOffset] + $current
                $DigitalProductId[$j + $keyOffset] = [math]::Floor($current / 24)
                $current = $current % 24
            }
            $key = $chars[$current] + $key
        }

        if ($isWin8OrNewer) {
            $keypart1 = $key.Substring(1, $current)
            $keypart2 = $key.Substring($current + 1, $key.Length - $current - 1)
            $key = $keypart1 + "N" + $keypart2
        }

        # Format the key with dashes
        $formattedKey = ""
        for ($i = 0; $i -lt 25; $i += 5) {
            $formattedKey += $key.Substring($i, 5)
            if ($i -lt 20) { $formattedKey += "-" }
        }

        return $formattedKey
    } catch {
        return $null
    }
}

function Get-OfficeProductKey {
    [CmdletBinding()]
    param()

    $officeKeys = @()
    $foundFullKey = $false

    # Office registry paths for different versions
    $officePaths = @(
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Office\16.0\Registration"; Version = "Office 2016/2019/365" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Office\15.0\Registration"; Version = "Office 2013" },
        @{ Path = "HKLM:\SOFTWARE\Microsoft\Office\14.0\Registration"; Version = "Office 2010" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\16.0\Registration"; Version = "Office 2016/2019/365 (32-bit)" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\15.0\Registration"; Version = "Office 2013 (32-bit)" },
        @{ Path = "HKLM:\SOFTWARE\WOW6432Node\Microsoft\Office\14.0\Registration"; Version = "Office 2010 (32-bit)" }
    )

    foreach ($office in $officePaths) {
        try {
            if (Test-Path $office.Path) {
                $subKeys = Get-ChildItem -Path $office.Path -ErrorAction SilentlyContinue
                foreach ($subKey in $subKeys) {
                    $props = Get-ItemProperty -Path $subKey.PSPath -ErrorAction SilentlyContinue
                    if ($props.DigitalProductId) {
                        $key = Convert-DigitalProductIdToKey -DigitalProductId $props.DigitalProductId
                        if ($key -and $key -notmatch "^\*|^N/A|^Partial") {
                            $officeKeys += [PSCustomObject]@{
                                Product = $props.ProductName
                                Version = $office.Version
                                ProductKey = $key
                                ProductId = $props.ProductID
                                KeyType = "Full"
                                Note = "Can be used for reinstallation"
                            }
                            $foundFullKey = $true
                        }
                    }
                }
            }
        } catch {
            Write-Warning "Error reading Office key from $($office.Path): $_"
        }
    }

    # Check for Office Click-to-Run configuration
    $c2rPath = "HKLM:\SOFTWARE\Microsoft\Office\ClickToRun\Configuration"
    $officeProduct = $null
    if (Test-Path $c2rPath) {
        try {
            $c2rProps = Get-ItemProperty -Path $c2rPath -ErrorAction SilentlyContinue
            $officeProduct = $c2rProps.ProductReleaseIds
        } catch {}
    }

    # Try OSPP.VBS for Office 365/2019 - only if we didn't find full keys
    if (-not $foundFullKey) {
        try {
            $osppPaths = @(
                "${env:ProgramFiles}\Microsoft Office\Office16\OSPP.VBS",
                "${env:ProgramFiles(x86)}\Microsoft Office\Office16\OSPP.VBS",
                "${env:ProgramFiles}\Microsoft Office\Office15\OSPP.VBS",
                "${env:ProgramFiles(x86)}\Microsoft Office\Office15\OSPP.VBS"
            )

            foreach ($osppPath in $osppPaths) {
                if (Test-Path $osppPath) {
                    $osppOutput = cscript //nologo "$osppPath" /dstatus 2>$null | Out-String

                    # Check if it's Microsoft 365 (subscription)
                    $isM365 = $osppOutput -match "O365|Microsoft 365|SUBSCRIPTION"

                    if ($osppOutput -match "Last 5 characters of installed product key:\s*(\S+)") {
                        $partialKey = $matches[1]

                        if ($isM365) {
                            $officeKeys += [PSCustomObject]@{
                                Product = if ($officeProduct) { $officeProduct } else { "Microsoft 365" }
                                Version = "Microsoft 365 (Subscription)"
                                ProductKey = "N/A - Account-based license"
                                ProductId = "Last 5 chars: $partialKey"
                                KeyType = "Subscription"
                                Note = "Sign in with your Microsoft account to reactivate. No product key needed."
                            }
                        } else {
                            $officeKeys += [PSCustomObject]@{
                                Product = if ($officeProduct) { $officeProduct } else { "Microsoft Office" }
                                Version = "Office 2019/2021"
                                ProductKey = "PARTIAL: *****-*****-*****-*****-$partialKey"
                                ProductId = $null
                                KeyType = "Partial"
                                Note = "Full key not stored locally. Check your Microsoft account, email receipt, or original packaging."
                            }
                        }
                    }
                    break
                }
            }
        } catch {}
    }

    # If no Office found at all, check if Office is installed
    if ($officeKeys.Count -eq 0) {
        $officeInstalled = (Test-Path "${env:ProgramFiles}\Microsoft Office") -or
                          (Test-Path "${env:ProgramFiles(x86)}\Microsoft Office")
        if ($officeInstalled) {
            $officeKeys += [PSCustomObject]@{
                Product = "Microsoft Office (Detected)"
                Version = "Unknown"
                ProductKey = "Not found"
                ProductId = $null
                KeyType = "Unknown"
                Note = "Office is installed but key could not be extracted. Check your Microsoft account or original purchase."
            }
        }
    }

    return $officeKeys
}

function Get-AdobeKeys {
    [CmdletBinding()]
    param()

    $adobeKeys = @()

    # Adobe products often store info in these locations
    $adobePaths = @(
        "HKLM:\SOFTWARE\Adobe",
        "HKLM:\SOFTWARE\WOW6432Node\Adobe"
    )

    foreach ($path in $adobePaths) {
        try {
            if (Test-Path $path) {
                $products = Get-ChildItem -Path $path -Recurse -ErrorAction SilentlyContinue
                foreach ($product in $products) {
                    $props = Get-ItemProperty -Path $product.PSPath -ErrorAction SilentlyContinue
                    if ($props.Serial -or $props.SerialNumber) {
                        $adobeKeys += [PSCustomObject]@{
                            Product = $product.Name
                            Path = $product.PSPath
                            Serial = if ($props.Serial) { $props.Serial } else { $props.SerialNumber }
                        }
                    }
                }
            }
        } catch {}
    }

    return $adobeKeys
}

function Get-CommonSoftwareKeys {
    [CmdletBinding()]
    param()

    $keys = @()

    # Common software registry locations for license keys
    $softwareKeyPaths = @(
        @{ Name = "WinRAR"; Paths = @("HKCU:\SOFTWARE\WinRAR", "HKLM:\SOFTWARE\WinRAR") },
        @{ Name = "7-Zip"; Paths = @("HKCU:\SOFTWARE\7-Zip", "HKLM:\SOFTWARE\7-Zip") },
        @{ Name = "VMware"; Paths = @("HKLM:\SOFTWARE\VMware, Inc.", "HKLM:\SOFTWARE\WOW6432Node\VMware, Inc.") },
        @{ Name = "JetBrains"; Paths = @("HKCU:\SOFTWARE\JetBrains") },
        @{ Name = "Sublime Text"; Paths = @("HKCU:\SOFTWARE\Sublime Text") },
        @{ Name = "Visual Studio"; Paths = @("HKLM:\SOFTWARE\Microsoft\VisualStudio", "HKLM:\SOFTWARE\WOW6432Node\Microsoft\VisualStudio") }
    )

    foreach ($software in $softwareKeyPaths) {
        foreach ($path in $software.Paths) {
            try {
                if (Test-Path $path) {
                    $props = Get-ItemProperty -Path $path -ErrorAction SilentlyContinue
                    $licenseProps = $props.PSObject.Properties | Where-Object {
                        $_.Name -match "license|serial|key|registration|product" -and
                        $_.Name -notmatch "^PS"
                    }
                    foreach ($prop in $licenseProps) {
                        $keys += [PSCustomObject]@{
                            Software = $software.Name
                            Property = $prop.Name
                            Value = $prop.Value
                            Path = $path
                        }
                    }
                }
            } catch {}
        }
    }

    return $keys
}

function Get-WiFiPasswords {
    [CmdletBinding()]
    param()

    $wifiProfiles = @()

    try {
        $profiles = netsh wlan show profiles 2>$null | Select-String "All User Profile\s*:\s*(.+)$" | ForEach-Object { $_.Matches.Groups[1].Value.Trim() }

        foreach ($profile in $profiles) {
            try {
                $keyContent = netsh wlan show profile name="$profile" key=clear 2>$null | Out-String
                $password = $null
                if ($keyContent -match "Key Content\s*:\s*(.+)$") {
                    $password = $matches[1].Trim()
                }
                $wifiProfiles += [PSCustomObject]@{
                    ProfileName = $profile
                    Password = $password
                }
            } catch {}
        }
    } catch {
        Write-Warning "Error retrieving WiFi passwords: $_"
    }

    return $wifiProfiles
}

function Get-AllLicenseKeys {
    [CmdletBinding()]
    param(
        [string]$OutputPath
    )

    Write-Host "Extracting license keys..." -ForegroundColor Cyan

    $licenses = @{
        ExtractionDate = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
        ComputerName = $env:COMPUTERNAME
        Windows = Get-WindowsProductKey
        Office = @(Get-OfficeProductKey)
        Adobe = @(Get-AdobeKeys)
        OtherSoftware = @(Get-CommonSoftwareKeys)
        WiFiProfiles = @(Get-WiFiPasswords)
    }

    Write-Host "Extracted:" -ForegroundColor Green
    Write-Host "  - Windows key: $(if ($licenses.Windows.RecommendedKey) { 'Found' } else { 'Not found' })" -ForegroundColor White
    Write-Host "  - Office keys: $($licenses.Office.Count)" -ForegroundColor White
    Write-Host "  - Adobe serials: $($licenses.Adobe.Count)" -ForegroundColor White
    Write-Host "  - Other software keys: $($licenses.OtherSoftware.Count)" -ForegroundColor White
    Write-Host "  - WiFi profiles: $($licenses.WiFiProfiles.Count)" -ForegroundColor White

    if ($OutputPath) {
        $licenses | ConvertTo-Json -Depth 5 | Out-File -FilePath $OutputPath -Encoding UTF8
        Write-Host "`nLicenses saved to: $OutputPath" -ForegroundColor Green
    }

    return $licenses
}

# Functions are available when dot-sourced
