# 🚀 ReWin - Windows Migration Made Easy

*Too lazy to setup a new Windows system? Scan, backup, and restore everything in minutes.*

**Migrate your entire Windows setup effortlessly:**
- Scan your current system → Copy folder → Install Windows fresh → Restore everything
- No complex bootable USB workflows, no confusing menus
- All your software, settings, licenses, and configs - **exactly as you left them**

***Tested on Windows 11***

**TODO:**
- improve online lookup of software not on knrepos - for now just google search links are provided for each, in `manual_downloads.md` (produced by the restore tool on request, in your chosen ouput folder).

---

## ⚠️ Important - Please Read

**This tool is designed for clean installations:**
- ✅ **Perfect for:** Fresh Windows installs, new hardware, system rebuilds
- ❌ **Not for:** Running on already-configured systems you're actively using

**Use at your own risk:**
- This tool modifies system settings and installs software
- **Only use the Restore function RIGHT AFTER installing fresh Windows**
- Don't restore on systems you've been using for a while - it may overwrite settings
- Always test on non-critical systems first
- Keep backups and a bootable Windows USB handy

**The author assumes no responsibility for data loss or system damage.**

---

## ✨ Features

- ✅ **Complete System Scanner** - Finds ALL installed software (Registry, Store, Winget, Chocolatey, Portable apps)
- ✅ **License Key Extraction** - Windows product key, WiFi passwords, Office keys
- ✅ **Smart Config Backup** - Environment variables, tasks, services, file associations, app configs
- ✅ **Automatic Username Path Replacement** - Paths update automatically if you use a different username
- ✅ **Package Manager Integration** - Auto-maps software to Winget/Chocolatey for one-click reinstall
- ✅ **Live Download URL Resolver** - Finds fresh download links with architecture detection (GitHub, Winget, & Official Vendor sites)
- ✅ **Persistent Debug Logging** - Full audit trail for both scan and restore processes
- ✅ **Selective Restore** - Choose exactly what to restore with GUI checkboxes
- ✅ **Simple Workflow** - No bootable USB complexity, just scan → copy → restore

---

### 📋 Step 1: Scan Your Current System

**Before you reinstall Windows or switch hardware:**

1. **Right-click** `Launch-Scanner-GUI.vbs` → **Run as Administrator**  
2. Click **"Run Scanner"** and select where to save the scan
3. Wait for scan to complete (PowerShell window closes automatically)
4. Click **"Export Migration Package"** in the GUI
5. **Save the output folder** to:
   - USB drive (easiest)
   - Cloud storage (OneDrive, Dropbox, Google Drive)
   - External hard drive
   - Network location

**✅ What gets scanned:**
- All installed software (Registry, Store, Winget, Chocolatey, portable apps)
- Windows product key + WiFi passwords
- Environment variables + PATH settings
- Browser bookmarks (Chrome, Edge)
- VS Code, Git, SSH, Terminal configurations
- Application settings (VS Code, Cursor IDE, Claude, OpenAI)
- System preferences and file associations

---

### 💿 Step 2: Install Fresh Windows

**On your new system or after format:**

1. **Boot and install** Windows normally
2. **Complete Windows setup** (use any username you want - it auto-adjusts!)

**💡 Tip:** Don't worry if you use a different username than your old system - ReWin automatically updates all file paths in environment variables to match your new username.

---

### 🔄 Step 3: Restore Everything

**On your fresh Windows installation:**

1. **Copy your saved scan folder** to the new system
2. **Copy this ReWin project** to the new system  
3. **Right-click** `Launch-Restore-GUI.vbs` → **Run as Administrator**  

4. **In the Restore GUI:**
   - **Overview tab:** Understand what will happen
   - **Software tab:** Review what will be installed (399+ items)
   - **Online Installer Lookup tab:** Find fresh download URLs for software not in package managers
   - **Restore Options tab:** Select what to restore:
     - ✅ **Enabled by default:** Licenses, Env Vars, Network, File Associations, Windows Settings
     - ⬜ **Optional:** Scheduled Tasks, Service Configuration
   - **Configuration tab:** See all backed-up configurations
   - **Drive Settings tab:** Choose where to install apps/data (C:, D:, etc.)
   - **Progress tab:** Monitor restoration progress
   
5. **Online Installer Lookup tab (for manual downloads):**
   - Click **"Search All for Download URLs"** to bulk search for software
   - Tool finds fresh download links via **GitHub API, Winget fuzzy matching, and official vendor mappings**
   - Architecture-specific links detected (x64/x86)
   - Results saved to `manual_downloads.md` and appear in the **Select to Download** list
   - Batch download selected installers directly to your choose folder

6. **Click "Full Restore"** and wait:
   - Installs software via Winget
   - Installs software via Chocolatey
   - Restores WiFi passwords
   - Restores environment variables (with username auto-replacement)
   - Applies Windows settings
   - Restores file associations

7. **Done!** Your system is restored with all your software, settings, and configurations.

---

## 🎯 What This Tool Does

**Scans & Backs Up:**
- ✅ All installed software from Registry, Store, Winget, Chocolatey
- ✅ Windows + Office product keys, WiFi passwords
- ✅ Environment variables (PATH, custom vars)
- ✅ VS Code, Git, SSH, Terminal, PowerShell configs
- ✅ Browser bookmarks (Chrome, Edge)
- ✅ Application settings (Cursor, Claude, OpenAI Desktop)
- ✅ Scheduled tasks, services, file associations
- ✅ Maps software to Winget/Chocolatey for automated reinstall

**Restores on Fresh Windows:**
- ✅ Auto-installs all your software via package managers
- ✅ Provides fresh download URLs for manual installs
- ✅ Restores WiFi passwords automatically
- ✅ Restores environment variables with **automatic username path replacement**
- ✅ Applies Windows settings and preferences
- ✅ Restores all app configurations
- ✅ Selectively restore only what you want (GUI checkboxes)

---

## 🔑 License Keys - What Gets Extracted

| Product | What's Saved | Notes |
|---------|-------------|-------|
| **Windows** | Full product key | Extracted from BIOS/Registry |
| **Office 2010-2016** | Full product key | Volume license keys |
| **Office 2019/2021 Retail** | Partial key (last 5 chars) | Check your email receipt or Microsoft account |
| **Office 365/Microsoft 365** | Account info only | Just sign in with your Microsoft account |
| **WiFi Networks** | Full passwords | All saved WiFi profiles |

**💡 Office Note:** Microsoft 365 users don't need product keys - just reinstall Office and sign in with your account.

---

## ⚙️ Advanced Options

### Quick Software Install (No Config Restore)
Only reinstall software, skip settings:
```cmd
ReWin.bat → [4] Quick Install
```
- Installs all software via Winget/Chocolatey
- Skips environment variables, WiFi, app configs
- Fastest option for clean slate with same software

### Direct Launcher Shortcuts
```cmd
Launch-Scanner-GUI.bat        # Opens scanner GUI
Launch-Restore-GUI.bat        # Opens restore GUI (needs admin)
```

### Manual Command Line
```powershell
# Scan only
.\src\scanner\main_scanner.ps1 -OutputPath "C:\Backup"

# Restore only configs (no software install)
.\src\restore\restore_config.ps1 -ScanFolder "C:\Backup\Scan_..."

# Refresh manual download URLs
.\src\restore\manual_download_resolver.ps1 -ScanFolder "C:\Backup\Scan_..."
```

---

## 🛠️ System Requirements

- Fresh Windows 10/11
- PowerShell 5.1+
- Python 3.8+ (for GUI)
- Admin rights
- Internet connection (***Restore on New System only***)

---

## 📦 Complete Scan Output

After scanning, your migration package contains:

```
Scan_2026-01-14_230046/
├── software_inventory.json        # All installed software
├── license_keys.json              # Windows key, WiFi passwords  
├── config_backup.json             # Environment vars, settings
├── scan_summary.json              # Scan statistics
├── scan_log.txt                   # Detailed scan log
├── manual_downloads.md            # Software not in package managers
├── package_mappings.json          # Winget/Choco package IDs
├── AppConfigs/                    # Application settings
│   ├── VSCode/
│   │   ├── settings.json
│   │   ├── extensions.txt
│   │   └── snippets/
│   ├── Git/
│   │   └── .gitconfig
│   ├── SSH/
│   │   ├── config
│   │   ├── known_hosts
│   │   └── *.pub keys
│   ├── Chrome/
│   │   └── Bookmarks
│   ├── Edge/
│   │   └── Bookmarks
│   └── WindowsTerminal/
│       └── settings.json
└── Installers/                    # Downloaded installers (optional)
```

---

## 📁 What's Inside

```
ReWin/
├── ReWin.bat                     # Main menu launcher
├── Launch-Scanner-GUI.bat        # Direct scanner launch
├── Launch-Restore-GUI.bat        # Direct restore launch
├── src/
│   ├── scanner/
│   │   ├── main_scanner.ps1      # Scans system
│   │   ├── software_scanner.ps1  # Finds installed software
│   │   ├── license_extractor.ps1 # Extracts keys & passwords
│   │   └── package_mapper.ps1    # Maps to Winget/Choco
│   ├── backup/
│   │   └── config_backup.ps1     # Backs up configs
│   ├── restore/
│   │   ├── restore_config.ps1    # Restores everything (with username replacement)
│   │   └── manual_download_resolver.ps1 # Finds fresh download URLs
│   └── gui/
│       ├── scanner_gui.py        # Scanner interface
│       └── restore_gui.py        # Restore interface
└── output/                       # Scan results stored here
```

---

## 🤔 FAQ & Troubleshooting

### GUI won't start?
- Install Python: `winget install Python.Python.3.12`
- Restart terminal after installation

### Software installation or restore fails?
- Check internet connection
- Review `restore_debug.txt` and `restore_installer_lookup_debug.txt` in your scan folder for detailed errors
- Review `scan_log.txt` for issues related to the initial scan
- Check `manual_downloads.md` for manual links if automation fails

### Different username on new system?
- No worries! Environment variable paths auto-update
- Example: `C:\Users\OldName\` → `C:\Users\NewName\`

### Want to restore only some things?
- Use the Restore GUI checkboxes
- Default enabled: Licenses, Env Vars, Network, File Associations, Windows Settings
- Optional: Scheduled Tasks, Service Configuration

---

## 📝 Manual Download Resolver

For software not in package managers, the resolver finds fresh download URLs:

**Features:**
- **Live lookups** from GitHub releases and vendor sites
- **Architecture detection** (x64/x86)
- **Direct download links** for verified software
- **Search fallback** for unknown software

**How to use:**
1. In Restore GUI → **Online Installer Lookup** tab
2. Click **"Search All for Download URLs"**
3. Wait for live URL searches to complete
4. View results directly in the tab or open `manual_downloads.md` to see organized links
5. Download and install manually or copy URLs as needed

**Results Organization:**
- ✅ **Ready** - Direct download URLs found
- 🔍 **Manual Search** - Google search link provided
- ❌ **Unable to Find** - Needs manual search

---

## 📄 License

**MIT License** - Free to use, modify, and redistribute (personal or commercial) with attribution.

Must include:
- Copyright notice with original author
- Copy of MIT License

See [LICENSE](LICENSE) file for full text.

---

## 👤 Author & Contact

**Jany Martelli**
- GitHub: https://github.com/Jany-M
- Email: info@shambix.com
- Website: https://www.shambix.com

**Contributing:** Fork, improve, and submit PRs! Attribution appreciated.