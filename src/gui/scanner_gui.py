"""
ReWin Migration Tool - Scanner GUI
Provides a graphical interface for selecting what to migrate
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import json
import os
import shutil
import time
from pathlib import Path
import subprocess
import threading


class ScannerGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("ReWin Migration Tool - Scanner")
        self.root.geometry("900x550")

        # Data storage
        self.scan_data = None
        self.current_scan_path = None
        self.all_sw_iids = []
        self.all_store_iids = []
        self.selections = {
            'software': {},
            'store_apps': {},
            'configs': {},
            'licenses': {},
            'startup': {}
        }

        self._create_ui()
        self._apply_styles()

    def _apply_styles(self):
        style = ttk.Style()
        style.theme_use('clam')

        style.configure('Title.TLabel', font=('Segoe UI', 16, 'bold'))
        style.configure('Header.TLabel', font=('Segoe UI', 12, 'bold'))
        style.configure('TButton', padding=10)
        style.configure('Action.TButton', font=('Segoe UI', 10, 'bold'))
        style.configure('Treeview', rowheight=25)
        style.configure('Treeview.Heading', font=('Segoe UI', 10, 'bold'))

    def _open_url(self, url):
        """Open URL in default browser"""
        import webbrowser
        webbrowser.open(url)

    def _create_ui(self):
        # Main container
        main_frame = ttk.Frame(self.root, padding=10)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Header
        header_frame = ttk.Frame(main_frame)
        header_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(
            header_frame,
            text="ReWin Migration Tool",
            style='Title.TLabel'
        ).pack(side=tk.LEFT)

        # Action buttons in header
        btn_frame = ttk.Frame(header_frame)
        btn_frame.pack(side=tk.RIGHT)

        ttk.Button(
            btn_frame,
            text="Run Scanner",
            command=self._run_scanner
        ).pack(side=tk.LEFT, padx=5)

        ttk.Button(
            btn_frame,
            text="Load Scan Results",
            command=self._load_scan_results
        ).pack(side=tk.LEFT, padx=5)

        ttk.Button(
            btn_frame,
            text="Export Package",
            command=self._export_selection,
            style='Action.TButton'
        ).pack(side=tk.LEFT, padx=5)

        # Footer with author and GitHub link - pack before notebook so it doesn't get hidden
        footer_frame = ttk.Frame(main_frame, relief=tk.SUNKEN, borderwidth=1)
        footer_frame.pack(fill=tk.X, padx=0, pady=0)

        # Status bar
        self.status_var = tk.StringVar(value="Ready - Click 'Run Scanner' to scan this system or 'Load Scan Results' to load existing scan")
        status_bar = ttk.Label(main_frame, textvariable=self.status_var, relief=tk.SUNKEN)
        status_bar.pack(fill=tk.X, pady=(10, 5))

        # Notebook for different sections
        self.notebook = ttk.Notebook(main_frame)
        self.notebook.pack(fill=tk.BOTH, expand=True)

        # Create tabs
        self._create_software_tab()
        self._create_store_apps_tab()
        self._create_licenses_tab()
        self._create_configs_tab()
        self._create_summary_tab()
        self._create_quick_guide_tab()
        
        # Left side: author
        footer_label = ttk.Label(
            footer_frame,
            text="by Jany Martelli",
            font=('Segoe UI', 9),
            foreground='gray'
        )
        footer_label.pack(side=tk.LEFT, padx=10, pady=4)
        
        # Spacer to push GitHub link to right
        ttk.Label(footer_frame, text="").pack(side=tk.LEFT, expand=True)
        
        # Right side: GitHub link
        github_link = ttk.Label(
            footer_frame,
            text="https://github.com/Jany-M/ReWin",
            font=('Segoe UI', 9),
            foreground='blue',
            cursor='hand2'
        )
        github_link.pack(side=tk.RIGHT, padx=10, pady=4)
        github_link.bind('<Button-1>', lambda e: self._open_url('https://github.com/Jany-M/ReWin'))

    def _create_software_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Installed Software")

        # Controls
        control_frame = ttk.Frame(tab)
        control_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Button(control_frame, text="Select All", command=lambda: self._select_all('software')).pack(side=tk.LEFT, padx=2)
        ttk.Button(control_frame, text="Deselect All", command=lambda: self._deselect_all('software')).pack(side=tk.LEFT, padx=2)
        ttk.Button(control_frame, text="Select Winget Available", command=self._select_winget).pack(side=tk.LEFT, padx=2)

        # Search
        ttk.Label(control_frame, text="Search:").pack(side=tk.LEFT, padx=(20, 5))
        self.software_search = tk.StringVar()
        self.software_search.trace('w', lambda *args: self._filter_software())
        search_entry = ttk.Entry(control_frame, textvariable=self.software_search, width=30)
        search_entry.pack(side=tk.LEFT)

        # Treeview with checkboxes
        tree_frame = ttk.Frame(tab)
        tree_frame.pack(fill=tk.BOTH, expand=True)

        columns = ('name', 'version', 'publisher', 'install_method', 'package_id')
        self.software_tree = ttk.Treeview(tree_frame, columns=columns, show='tree headings')

        self.software_tree.heading('#0', text='Select')
        self.software_tree.heading('name', text='Software Name')
        self.software_tree.heading('version', text='Version')
        self.software_tree.heading('publisher', text='Publisher')
        self.software_tree.heading('install_method', text='Install Method')
        self.software_tree.heading('package_id', text='Package ID')

        self.software_tree.column('#0', width=50)
        self.software_tree.column('name', width=300)
        self.software_tree.column('version', width=100)
        self.software_tree.column('publisher', width=200)
        self.software_tree.column('install_method', width=100)
        self.software_tree.column('package_id', width=200)

        scrollbar = ttk.Scrollbar(tree_frame, orient=tk.VERTICAL, command=self.software_tree.yview)
        self.software_tree.configure(yscrollcommand=scrollbar.set)

        self.software_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.software_tree.bind('<Button-1>', lambda e: self._toggle_selection(e, 'software'))

    def _create_store_apps_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Store Apps")

        control_frame = ttk.Frame(tab)
        control_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Button(control_frame, text="Select All", command=lambda: self._select_all('store_apps')).pack(side=tk.LEFT, padx=2)
        ttk.Button(control_frame, text="Deselect All", command=lambda: self._deselect_all('store_apps')).pack(side=tk.LEFT, padx=2)

        # Search
        ttk.Label(control_frame, text="Search:").pack(side=tk.LEFT, padx=(20, 5))
        self.store_apps_search = tk.StringVar()
        self.store_apps_search.trace('w', lambda *args: self._filter_store_apps())
        search_entry = ttk.Entry(control_frame, textvariable=self.store_apps_search, width=30)
        search_entry.pack(side=tk.LEFT)

        tree_frame = ttk.Frame(tab)
        tree_frame.pack(fill=tk.BOTH, expand=True)

        columns = ('name', 'version', 'publisher')
        self.store_apps_tree = ttk.Treeview(tree_frame, columns=columns, show='tree headings')

        self.store_apps_tree.heading('#0', text='Select')
        self.store_apps_tree.heading('name', text='App Name')
        self.store_apps_tree.heading('version', text='Version')
        self.store_apps_tree.heading('publisher', text='Publisher')

        self.store_apps_tree.column('#0', width=50)
        self.store_apps_tree.column('name', width=400)
        self.store_apps_tree.column('version', width=150)
        self.store_apps_tree.column('publisher', width=300)

        scrollbar = ttk.Scrollbar(tree_frame, orient=tk.VERTICAL, command=self.store_apps_tree.yview)
        self.store_apps_tree.configure(yscrollcommand=scrollbar.set)

        self.store_apps_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.store_apps_tree.bind('<Button-1>', lambda e: self._toggle_selection(e, 'store_apps'))

    def _create_licenses_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="License Keys")

        # Windows Key section
        win_frame = ttk.LabelFrame(tab, text="Windows Product Key", padding=10)
        win_frame.pack(fill=tk.X, pady=5)

        self.windows_key_var = tk.StringVar(value="Not scanned")
        ttk.Label(win_frame, textvariable=self.windows_key_var, font=('Consolas', 12)).pack(anchor=tk.W)

        self.include_windows_key = tk.BooleanVar(value=True)
        ttk.Checkbutton(win_frame, text="Include in migration", variable=self.include_windows_key).pack(anchor=tk.W)

        # Office Keys section
        office_frame = ttk.LabelFrame(tab, text="Office Product Keys", padding=10)
        office_frame.pack(fill=tk.X, pady=5)

        self.office_text = tk.Text(office_frame, height=5, font=('Consolas', 10))
        self.office_text.pack(fill=tk.X)
        self.office_text.config(state=tk.DISABLED)

        self.include_office_keys = tk.BooleanVar(value=True)
        ttk.Checkbutton(office_frame, text="Include in migration", variable=self.include_office_keys).pack(anchor=tk.W)

        # WiFi Profiles
        wifi_frame = ttk.LabelFrame(tab, text="WiFi Profiles & Passwords", padding=10)
        wifi_frame.pack(fill=tk.BOTH, expand=True, pady=5)

        columns = ('profile', 'password')
        self.wifi_tree = ttk.Treeview(wifi_frame, columns=columns, show='headings', height=8)

        self.wifi_tree.heading('profile', text='Profile Name')
        self.wifi_tree.heading('password', text='Password')

        self.wifi_tree.column('profile', width=300)
        self.wifi_tree.column('password', width=300)

        self.wifi_tree.pack(fill=tk.BOTH, expand=True)

        self.include_wifi = tk.BooleanVar(value=True)
        ttk.Checkbutton(wifi_frame, text="Include in migration", variable=self.include_wifi).pack(anchor=tk.W)

    def _create_configs_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Configuration")

        # Info box explaining restoration defaults
        info_frame = ttk.LabelFrame(tab, text="Restoration Information", padding=10)
        info_frame.pack(fill=tk.X, pady=(0, 15))

        info_text = tk.Text(info_frame, font=('Segoe UI', 10), height=5, wrap=tk.WORD)
        info_text.pack(fill=tk.X)
        info_text.insert(tk.END, """During restoration, these categories will be restored by DEFAULT:
• License Keys (Windows, Office, WiFi passwords)
• Environment Variables
• Network Settings (Hosts, DNS)
• File Associations
• Windows Settings (Display, Keyboard)

OPTIONAL categories (disabled by default but can be enabled during restore):
• Scheduled Tasks - Most are system-generated when you reinstall software
• Service Configuration - Most services are recreated by software installers

You can customize which categories to restore when you run the restore process.""")
        info_text.config(state=tk.DISABLED)

        # Create scrollable frame
        canvas = tk.Canvas(tab)
        scrollbar = ttk.Scrollbar(tab, orient=tk.VERTICAL, command=canvas.yview)
        scrollable = ttk.Frame(canvas)

        scrollable.bind("<Configure>", lambda e: canvas.configure(scrollregion=canvas.bbox("all")))
        canvas.create_window((0, 0), window=scrollable, anchor=tk.NW)
        canvas.configure(yscrollcommand=scrollbar.set)

        # Config options
        self.config_options = {}

        configs = [
            ('env_vars', 'Environment Variables', 'Include user and system environment variables'),
            ('scheduled_tasks', 'Scheduled Tasks', 'Include custom scheduled tasks'),
            ('services', 'Service Configuration', 'Include service startup settings'),
            ('file_assoc', 'File Associations', 'Include custom file type associations'),
            ('network', 'Network Settings', 'Include network configuration and hosts file'),
            ('explorer', 'Explorer Settings', 'Include Windows Explorer preferences'),
            ('vscode', 'VS Code Settings', 'Include VS Code settings and extensions list'),
            ('git_config', 'Git Configuration', 'Include .gitconfig and global ignores'),
            ('ssh_config', 'SSH Configuration', 'Include SSH config and known hosts'),
            ('terminal', 'Windows Terminal Settings', 'Include Windows Terminal settings'),
            ('browser_bookmarks', 'Browser Bookmarks', 'Include Chrome, Edge, Firefox bookmarks'),
            ('powershell', 'PowerShell Profile', 'Include PowerShell profile scripts'),
        ]

        for key, name, desc in configs:
            frame = ttk.Frame(scrollable)
            frame.pack(fill=tk.X, pady=2)

            self.config_options[key] = tk.BooleanVar(value=True)
            ttk.Checkbutton(frame, text=name, variable=self.config_options[key]).pack(side=tk.LEFT)
            ttk.Label(frame, text=f" - {desc}", foreground='gray').pack(side=tk.LEFT)

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

    def _create_summary_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Summary & Export")

        # Summary text
        summary_frame = ttk.LabelFrame(tab, text="Selection Summary", padding=10)
        summary_frame.pack(fill=tk.BOTH, expand=True, pady=(0, 10))

        self.summary_text = tk.Text(summary_frame, height=15, font=('Consolas', 9), wrap=tk.WORD)
        self.summary_text.pack(fill=tk.BOTH, expand=True)
        self.summary_text.insert(tk.END, "Click 'Update Summary' to see scan results\n")

        # Export buttons with wrapping text
        export_frame = ttk.Frame(tab)
        export_frame.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(
            export_frame,
            text="Update Summary",
            command=self._update_summary,
            width=20
        ).pack(side=tk.LEFT, padx=5, pady=5)

        ttk.Button(
            export_frame,
            text="Export Package",
            command=self._export_selection,
            style='Action.TButton',
            width=25
        ).pack(side=tk.LEFT, padx=5, pady=5)

    def _run_scanner(self):
        """Run the PowerShell scanner"""
        # Ask for output directory in main thread (thread-safe)
        output_dir = filedialog.askdirectory(title="Select output directory for scan results")
        if not output_dir:
            self.status_var.set("Scan cancelled")
            return

        self.status_var.set("Running system scan... (check PowerShell window)")

        def run():
            try:
                script_dir = Path(__file__).parent.parent / 'scanner'
                scanner_script = script_dir / 'main_scanner.ps1'

                # Verify script exists
                if not scanner_script.exists():
                    self.root.after(0, lambda: messagebox.showerror("Error", f"Scanner script not found: {scanner_script}"))
                    self.root.after(0, lambda: self.status_var.set("Scan failed - script not found"))
                    return

                # Use -File for proper path resolution in the script
                cmd = [
                    'powershell.exe',
                    '-NoProfile',
                    '-ExecutionPolicy', 'Bypass',
                    '-File', str(scanner_script),
                    '-OutputPath', output_dir,
                    '-BackupAppConfigs'
                ]

                # Get the project root directory for working context
                project_root = Path(__file__).parent.parent.parent

                # Run with visible console, allow output to display in PowerShell window
                process = subprocess.Popen(
                    cmd,
                    cwd=str(project_root),
                    creationflags=subprocess.CREATE_NEW_CONSOLE
                )
                process.wait()

                # Give filesystem a moment to sync
                time.sleep(1)
                
                # Close any remaining PowerShell windows associated with this process
                try:
                    subprocess.run(['taskkill', '/F', '/PID', str(process.pid)], capture_output=True)
                except:
                    pass

                # Find the latest scan directory
                scan_dirs = sorted(Path(output_dir).glob('Scan_*'), reverse=True)
                if scan_dirs:
                    self.root.after(0, lambda: self._load_scan_from_path(str(scan_dirs[0])))
                    self.root.after(0, lambda: self.status_var.set(f"Scan complete! Results loaded from {scan_dirs[0]}"))
                else:
                    self.root.after(0, lambda: self.status_var.set("Scan complete but no results found - check PowerShell window for errors"))

            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror("Error", f"Scanner error: {str(e)}"))
                self.root.after(0, lambda: self.status_var.set("Scan failed"))

        threading.Thread(target=run, daemon=True).start()

    def _load_scan_results(self):
        """Load scan results from a directory"""
        directory = filedialog.askdirectory(title="Select scan results directory")
        if directory:
            self._load_scan_from_path(directory)

    def _load_scan_from_path(self, path):
        """Load scan results from specified path"""
        try:
            self.scan_data = {}
            self.current_scan_path = path

            # Load software inventory
            software_path = Path(path) / 'software_inventory.json'
            if software_path.exists():
                with open(software_path, 'r', encoding='utf-8-sig') as f:
                    self.scan_data['software'] = json.load(f)

            # Load package mappings
            mappings_path = Path(path) / 'package_mappings.json'
            if mappings_path.exists():
                with open(mappings_path, 'r', encoding='utf-8-sig') as f:
                    self.scan_data['mappings'] = json.load(f)

            # Load license keys
            licenses_path = Path(path) / 'license_keys.json'
            if licenses_path.exists():
                with open(licenses_path, 'r', encoding='utf-8-sig') as f:
                    self.scan_data['licenses'] = json.load(f)

            # Load config backup
            config_path = Path(path) / 'config_backup.json'
            if config_path.exists():
                with open(config_path, 'r', encoding='utf-8-sig') as f:
                    self.scan_data['config'] = json.load(f)

            self._populate_ui()
            self.status_var.set(f"Loaded scan results from: {path}")

        except Exception as e:
            messagebox.showerror("Error", f"Failed to load scan results: {str(e)}")
            self.status_var.set("Failed to load scan results")

    def _populate_ui(self):
        """Populate UI with loaded data"""
        if not self.scan_data:
            return

        # Clear existing items
        for item in self.software_tree.get_children():
            self.software_tree.delete(item)
        for item in self.store_apps_tree.get_children():
            self.store_apps_tree.delete(item)
        for item in self.wifi_tree.get_children():
            self.wifi_tree.delete(item)
        
        self.all_sw_iids = []
        self.all_store_iids = []

        # Populate software tree
        if 'mappings' in self.scan_data:
            for i, item in enumerate(self.scan_data['mappings']):
                name = item.get('SoftwareName', '')
                version = item.get('Version', '')
                publisher = item.get('Publisher', '')
                method = item.get('InstallMethod', 'Manual')
                pkg_id = item.get('WingetId') or item.get('ChocolateyId') or ''

                iid = f'sw_{i}'
                self.software_tree.insert(
                    '', 'end',
                    iid=iid,
                    text='☑',
                    values=(name, version, publisher, method, pkg_id)
                )
                self.selections['software'][iid] = True
                self.all_sw_iids.append(iid)

        elif 'software' in self.scan_data:
            for i, item in enumerate(self.scan_data['software'].get('InstalledSoftware', [])):
                name = item.get('Name', '')
                version = item.get('Version', '')
                publisher = item.get('Publisher', '')

                iid = f'sw_{i}'
                self.software_tree.insert(
                    '', 'end',
                    iid=iid,
                    text='☑',
                    values=(name, version, publisher, 'Unknown', '')
                )
                self.selections['software'][iid] = True
                self.all_sw_iids.append(iid)

        # Populate store apps
        if 'software' in self.scan_data:
            for i, item in enumerate(self.scan_data['software'].get('StoreApps', [])):
                name = item.get('Name', '')
                version = item.get('Version', '')
                publisher = item.get('Publisher', '')

                iid = f'store_{i}'
                self.store_apps_tree.insert(
                    '', 'end',
                    iid=iid,
                    text='☐',
                    values=(name, version, publisher)
                )
                self.selections['store_apps'][iid] = False
                self.all_store_iids.append(iid)

        # Populate licenses
        if 'licenses' in self.scan_data:
            licenses = self.scan_data['licenses']

            # Windows key
            win_key = licenses.get('Windows', {})
            if win_key:
                key = win_key.get('RecommendedKey', 'Not found')
                self.windows_key_var.set(key)

            # Office keys
            office_keys = licenses.get('Office', [])
            self.office_text.config(state=tk.NORMAL)
            self.office_text.delete(1.0, tk.END)
            if office_keys:
                has_masked_keys = False
                for key in office_keys:
                    product = key.get('Product', 'Office')
                    productkey = key.get('ProductKey', 'N/A')
                    keytype = key.get('KeyType', '')
                    note = key.get('Note', '')
                    
                    # Check if key is masked (partial/incomplete)
                    if 'PARTIAL' in str(productkey) or '*' in str(productkey) or len(str(productkey)) < 20:
                        has_masked_keys = True
                    
                    # Display full details
                    self.office_text.insert(tk.END, f"{product}\n")
                    self.office_text.insert(tk.END, f"  Type: {keytype}\n")
                    self.office_text.insert(tk.END, f"  Key: {productkey}\n")
                    if note:
                        self.office_text.insert(tk.END, f"  Note: {note}\n")
                    self.office_text.insert(tk.END, "\n")
                
                # If keys are masked, disable restoration
                if has_masked_keys:
                    self.include_office_keys.set(False)
                    self.office_text.insert(tk.END, "\n⚠️  WARNING: Office keys are masked/partial and cannot be restored.\nIf you have Microsoft 365, simply sign in after reinstalling Office.")
            else:
                self.office_text.insert(tk.END, "No Office keys found")
            self.office_text.config(state=tk.DISABLED)

            # WiFi profiles
            wifi = licenses.get('WiFiProfiles', [])
            for profile in wifi:
                self.wifi_tree.insert(
                    '', 'end',
                    values=(profile.get('ProfileName', ''), profile.get('Password', ''))
                )

    def _toggle_selection(self, event, category):
        """Toggle selection of an item"""
        tree = getattr(self, f'{category}_tree', None)
        if not tree:
            return

        item = tree.identify_row(event.y)
        if not item:
            return

        if item in self.selections[category]:
            self.selections[category][item] = not self.selections[category][item]
            tree.item(item, text='☑' if self.selections[category][item] else '☐')

    def _select_all(self, category):
        """Select all items in category"""
        tree = getattr(self, f'{category}_tree', None)
        if not tree:
            return

        children = tree.get_children()
        if not children:
            return

        for item in children:
            # Initialize in selections dict if missing
            if item not in self.selections[category]:
                self.selections[category][item] = False
            
            self.selections[category][item] = True
            tree.item(item, text='☑')

    def _deselect_all(self, category):
        """Deselect all items in category"""
        tree = getattr(self, f'{category}_tree', None)
        if not tree:
            return

        children = tree.get_children()
        if not children:
            return

        for item in children:
            # Initialize in selections dict if missing
            if item not in self.selections[category]:
                self.selections[category][item] = True
            
            self.selections[category][item] = False
            tree.item(item, text='☐')

    def _select_winget(self):
        """Select only items available via winget"""
        for item in self.software_tree.get_children():
            values = self.software_tree.item(item, 'values')
            method = values[3] if len(values) > 3 else ''
            selected = method == 'Winget'
            self.selections['software'][item] = selected
            self.software_tree.item(item, text='☑' if selected else '☐')

    def _filter_software(self):
        """Filter software list based on search"""
        search_term = self.software_search.get().lower()
        visible_items = set(self.software_tree.get_children(''))

        for item in self.all_sw_iids:
            values = self.software_tree.item(item, 'values')
            if not values: continue
            
            name = str(values[0]).lower()
            publisher = str(values[2]).lower() if len(values) > 2 else ''

            if search_term in name or search_term in publisher:
                if item not in visible_items:
                    self.software_tree.reattach(item, '', 'end')
            else:
                if item in visible_items:
                    self.software_tree.detach(item)

    def _filter_store_apps(self):
        """Filter store apps list based on search"""
        search_term = self.store_apps_search.get().lower()
        visible_items = set(self.store_apps_tree.get_children(''))

        for item in self.all_store_iids:
            values = self.store_apps_tree.item(item, 'values')
            if not values: continue
            
            name = str(values[0]).lower()
            publisher = str(values[2]).lower() if len(values) > 2 else ''

            if search_term in name or search_term in publisher:
                if item not in visible_items:
                    self.store_apps_tree.reattach(item, '', 'end')
            else:
                if item in visible_items:
                    self.store_apps_tree.detach(item)

    def _update_summary(self):
        """Update the summary tab with current selections and scan data"""
        selected_software = sum(1 for v in self.selections['software'].values() if v)
        selected_store = sum(1 for v in self.selections['store_apps'].values() if v)
        selected_configs = sum(1 for v in self.config_options.values() if v.get())

        # Get totals from scan data
        total_software = 0
        total_store = 0
        if self.scan_data:
            if 'mappings' in self.scan_data:
                total_software = len(self.scan_data['mappings'])
            elif 'software' in self.scan_data:
                total_software = len(self.scan_data['software'].get('InstalledSoftware', []))
            
            if 'software' in self.scan_data:
                total_store = len(self.scan_data['software'].get('StoreApps', []))

        # Count by install method
        winget_count = 0
        choco_count = 0
        manual_count = 0

        for item, selected in self.selections['software'].items():
            if selected and self.software_tree:
                try:
                    values = self.software_tree.item(item, 'values')
                    method = values[3] if len(values) > 3 else ''
                    if method == 'Winget':
                        winget_count += 1
                    elif method == 'Chocolatey':
                        choco_count += 1
                    else:
                        manual_count += 1
                except:
                    pass

        summary = f"""MIGRATION SUMMARY
{'=' * 70}

SCAN RESULTS (from most recent scan):
  • Total Installed Programs: {total_software}
  • Total Store Apps: {total_store}

SELECTED FOR MIGRATION:
  • Installed Programs: {selected_software} / {total_software}
  • Microsoft Store Apps: {selected_store} / {total_store}

INSTALL METHODS FOR SELECTED SOFTWARE:
  • Via Winget: {winget_count}
  • Via Chocolatey: {choco_count}
  • Manual Install: {manual_count}

CONFIGURATION BACKUP:
  • Config Categories: {selected_configs}

LICENSE & SETTINGS BACKUP:
  • Windows Product Key: {'✓ Included' if self.include_windows_key.get() else '✗ Excluded'}
  • Office Product Keys: {'✓ Included' if self.include_office_keys.get() else '✗ Excluded'}
  • WiFi Profiles & Passwords: {'✓ Included' if self.include_wifi.get() else '✗ Excluded'}

{'=' * 70}

Click 'Export Package' to create the migration file.
"""
        self.summary_text.config(state=tk.NORMAL)
        self.summary_text.delete(1.0, tk.END)
        self.summary_text.insert(tk.END, summary)
        self.summary_text.config(state=tk.DISABLED)

    def _export_selection(self):
        """Export the current selection as a migration package"""
        output_dir = filedialog.askdirectory(title="Select output directory for migration package")
        if not output_dir:
            return

        try:
            package = {
                'export_date': '',
                'drives': {
                    'primary': 'C:',
                    'secondary': 'D:',
                    'data': 'D:'
                },
                'software': [],
                'store_apps': [],
                'configs': {},
                'licenses': {}
            }

            # Export selected software
            if 'mappings' in self.scan_data:
                for item, selected in self.selections['software'].items():
                    if selected:
                        idx = int(item.split('_')[1])
                        if idx < len(self.scan_data['mappings']):
                            package['software'].append(self.scan_data['mappings'][idx])
            elif 'software' in self.scan_data and 'InstalledSoftware' in self.scan_data['software']:
                sw_list = self.scan_data['software'].get('InstalledSoftware', [])
                for item, selected in self.selections['software'].items():
                    if selected:
                        idx = int(item.split('_')[1])
                        if idx < len(sw_list):
                            sw_item = sw_list[idx]
                            package['software'].append({
                                'SoftwareName': sw_item.get('Name', ''),
                                'Version': sw_item.get('Version', ''),
                                'Publisher': sw_item.get('Publisher', ''),
                                'InstallMethod': 'Manual'
                            })

            # Export selected store apps
            if 'software' in self.scan_data and 'StoreApps' in self.scan_data['software']:
                for item, selected in self.selections['store_apps'].items():
                    if selected:
                        idx = int(item.split('_')[1])
                        store_apps_list = self.scan_data['software'].get('StoreApps', [])
                        if idx < len(store_apps_list):
                            store_app = store_apps_list[idx]
                            package['store_apps'].append({
                                'Name': store_app.get('Name', ''),
                                'Version': store_app.get('Version', ''),
                                'Publisher': store_app.get('Publisher', ''),
                                'PackageFamilyName': store_app.get('PackageFamilyName', '')
                            })

            # Export config selections
            for key, var in self.config_options.items():
                package['configs'][key] = var.get()

            # Export license selections
            package['licenses']['include_windows'] = self.include_windows_key.get()
            package['licenses']['include_office'] = self.include_office_keys.get()
            package['licenses']['include_wifi'] = self.include_wifi.get()

            if self.include_windows_key.get() and 'licenses' in self.scan_data:
                package['licenses']['windows_key'] = self.scan_data['licenses'].get('Windows', {})

            if self.include_office_keys.get() and 'licenses' in self.scan_data:
                package['licenses']['office_keys'] = self.scan_data['licenses'].get('Office', [])

            if self.include_wifi.get() and 'licenses' in self.scan_data:
                package['licenses']['wifi_profiles'] = self.scan_data['licenses'].get('WiFiProfiles', [])

            # Save package
            package_path = Path(output_dir) / 'migration_package.json'
            with open(package_path, 'w', encoding='utf-8') as f:
                json.dump(package, f, indent=2, default=str)

            # Generate install scripts
            self._generate_install_scripts(package, output_dir)

            # Copy source data files to export directory for portability
            if self.current_scan_path:
                source_path = Path(self.current_scan_path)
                dest_path = Path(output_dir)
                
                # Check if source and destination are different
                if source_path.resolve() != dest_path.resolve():
                    # Files to copy
                    files_to_copy = [
                        'config_backup.json',
                        'license_keys.json',
                        'software_inventory.json',
                        'package_mappings.json',
                        'scan_summary.json',
                        'scan_log.txt'
                    ]
                    
                    for filename in files_to_copy:
                        src_file = source_path / filename
                        if src_file.exists():
                            shutil.copy2(src_file, dest_path / filename)
                    
                    # Copy AppConfigs folder
                    src_configs = source_path / 'AppConfigs'
                    dest_configs = dest_path / 'AppConfigs'
                    if src_configs.exists():
                        if dest_configs.exists():
                            shutil.rmtree(dest_configs)
                        shutil.copytree(src_configs, dest_configs)

            messagebox.showinfo("Success", f"Migration package exported to:\n{output_dir}")
            self.status_var.set(f"Package exported to: {output_dir}")

        except Exception as e:
            messagebox.showerror("Error", f"Failed to export package: {str(e)}")

    def _generate_install_scripts(self, package, output_dir):
        """Generate PowerShell install scripts"""
        # Winget install script
        winget_pkgs = [s['WingetId'] for s in package['software'] if s.get('WingetId')]
        if winget_pkgs:
            script = """# ReWin - Winget Installation Script
# Run this after Windows installation

Write-Host "Installing software via Winget..." -ForegroundColor Cyan

$packages = @(
"""
            for pkg in winget_pkgs:
                script += f'    "{pkg}",\n'
            script = script.rstrip(',\n') + '\n'
            script += """)

foreach ($pkg in $packages) {
    Write-Host "Installing $pkg..." -ForegroundColor Yellow
    winget install --id $pkg --accept-source-agreements --accept-package-agreements -h
}

Write-Host "Installation complete!" -ForegroundColor Green
"""
            with open(Path(output_dir) / 'install_winget.ps1', 'w', encoding='utf-8') as f:
                f.write(script)

        # Chocolatey install script
        choco_pkgs = [s['ChocolateyId'] for s in package['software']
                      if s.get('ChocolateyId') and not s.get('WingetId')]
        if choco_pkgs:
            script = """# ReWin - Chocolatey Installation Script
# Run this after Windows installation

# Install Chocolatey if not present
if (!(Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Installing Chocolatey..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force
    [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072
    iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
}

Write-Host "Installing software via Chocolatey..." -ForegroundColor Cyan

$packages = @(
"""
            for pkg in choco_pkgs:
                script += f'    "{pkg}",\n'
            script = script.rstrip(',\n') + '\n'
            script += """)

foreach ($pkg in $packages) {
    Write-Host "Installing $pkg..." -ForegroundColor Yellow
    choco install $pkg -y
}

Write-Host "Installation complete!" -ForegroundColor Green
"""
            with open(Path(output_dir) / 'install_chocolatey.ps1', 'w', encoding='utf-8') as f:
                f.write(script)

    def _create_quick_guide_tab(self):
        """Create a Quick Guide tab that displays the README"""
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text="Quick Guide")

        # Header
        header_frame = ttk.Frame(tab)
        header_frame.pack(fill=tk.X, padx=10, pady=10)
        ttk.Label(header_frame, text="ReWin - User Quick Guide", style='Header.TLabel').pack(side=tk.LEFT)

        # Text widget with scrollbar
        text_frame = ttk.Frame(tab)
        text_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        scrollbar = ttk.Scrollbar(text_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        guide_text = tk.Text(
            text_frame,
            wrap=tk.WORD,
            font=('Segoe UI', 10),
            yscrollcommand=scrollbar.set
        )
        guide_text.pack(fill=tk.BOTH, expand=True)
        scrollbar.config(command=guide_text.yview)

        # Load README content
        readme_path = Path(__file__).parent.parent.parent / 'README.md'
        if readme_path.exists():
            try:
                with open(readme_path, 'r', encoding='utf-8-sig') as f:
                    readme_content = f.read()
                guide_text.insert(tk.END, readme_content)
            except Exception as e:
                guide_text.insert(tk.END, f"Error loading README: {str(e)}")
        else:
            guide_text.insert(tk.END, "README.md not found")

        # Make text read-only
        guide_text.config(state=tk.DISABLED)


def main():
    root = tk.Tk()
    app = ScannerGUI(root)
    root.mainloop()


if __name__ == '__main__':
    main()
