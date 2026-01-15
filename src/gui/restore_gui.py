"""
ReWin Migration Tool - Restore GUI
Post-installation restoration interface
"""

import tkinter as tk
from tkinter import ttk, filedialog, messagebox
import json
import os
import time
from pathlib import Path
import subprocess
import threading
import sys
from datetime import datetime


class RestoreGUI:
    def __init__(self, root):
        self.root = root
        self.root.title("ReWin Migration Tool - Restore")
        self.root.geometry("900x550")

        self.package_data = None
        self.package_path = None

        self._create_ui()
        self._apply_styles()
        self._auto_detect_package()

    def _apply_styles(self):
        style = ttk.Style()
        style.theme_use('clam')

        style.configure('Title.TLabel', font=('Segoe UI', 16, 'bold'))
        style.configure('Header.TLabel', font=('Segoe UI', 12, 'bold'))
        style.configure('TButton', padding=10)
        style.configure('Action.TButton', font=('Segoe UI', 10, 'bold'))
        style.configure('Big.TButton', font=('Segoe UI', 12, 'bold'), padding=15)

    def _open_url(self, url):
        """Open URL in default browser"""
        import webbrowser
        webbrowser.open(url)

    def _create_ui(self):
        main_frame = ttk.Frame(self.root, padding=20)
        main_frame.pack(fill=tk.BOTH, expand=True)

        # Header
        header = ttk.Label(main_frame, text="ReWin Migration Tool - System Restore", style='Title.TLabel')
        header.pack(pady=(0, 20))

        # Package selection
        pkg_frame = ttk.LabelFrame(main_frame, text="Migration Package", padding=10)
        pkg_frame.pack(fill=tk.X, pady=10)

        self.package_path_var = tk.StringVar(value="No package loaded")
        ttk.Label(pkg_frame, textvariable=self.package_path_var).pack(side=tk.LEFT, fill=tk.X, expand=True)
        ttk.Button(pkg_frame, text="Browse...", command=self._load_package).pack(side=tk.RIGHT)

        # Footer with author and GitHub link - pack FIRST so it doesn't get hidden
        footer_frame = ttk.Frame(main_frame, relief=tk.SUNKEN, borderwidth=1)
        footer_frame.pack(fill=tk.X, padx=0, pady=0)
        
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

        # Main content notebook
        self.notebook = ttk.Notebook(main_frame)
        self.notebook.pack(fill=tk.BOTH, expand=True, pady=10)

        self._create_overview_tab()
        self._create_software_tab()
        self._create_online_installer_lookup_tab()
        self._create_restore_options_tab()
        self._create_config_tab()
        self._create_drive_settings_tab()
        self._create_progress_tab()
        self._create_quick_guide_tab()

        # Action buttons
        btn_frame = ttk.Frame(main_frame)
        btn_frame.pack(fill=tk.X, pady=10)

        ttk.Button(btn_frame, text="Install via Winget", command=self._install_winget).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="Install via Chocolatey", command=self._install_chocolatey).pack(side=tk.LEFT, padx=5)
        ttk.Button(
            btn_frame,
            text="Full Restore",
            command=self._full_restore,
            style='Big.TButton'
        ).pack(side=tk.RIGHT, padx=5)

        # Status bar
        self.status_var = tk.StringVar(value="Ready")
        status_bar = ttk.Label(main_frame, textvariable=self.status_var, relief=tk.SUNKEN)
        status_bar.pack(fill=tk.X, pady=(10, 5))

    def _create_overview_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Overview")

        self.overview_text = tk.Text(tab, font=('Consolas', 11), wrap=tk.WORD)
        self.overview_text.pack(fill=tk.BOTH, expand=True)
        self.overview_text.insert(tk.END, """
Welcome to ReWin Migration Tool!

This tool will help you restore your software and configurations
from the migration package created on your previous system.

Steps:
1. Load your migration package (auto-detected if on USB drive - check D:, E:, F:, etc.)
2. Review the software to be installed
3. Click "Full Restore" to install everything

Or use individual buttons to:
- Install only software
- Restore only configurations

Make sure you have an internet connection for software installation.
""")
        self.overview_text.config(state=tk.DISABLED)

    def _create_software_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Software")

        # Summary
        summary_frame = ttk.Frame(tab)
        summary_frame.pack(fill=tk.X, pady=(0, 10))

        self.software_summary = tk.StringVar(value="No package loaded")
        ttk.Label(summary_frame, textvariable=self.software_summary, style='Header.TLabel').pack(anchor=tk.W)

        # Controls frame: search and filter
        control_frame = ttk.Frame(tab)
        control_frame.pack(fill=tk.X, pady=(0, 10))

        ttk.Label(control_frame, text="Search:").pack(side=tk.LEFT, padx=(0, 5))
        self.software_search = tk.StringVar()
        self.software_search.trace('w', lambda *args: self._filter_software())
        search_entry = ttk.Entry(control_frame, textvariable=self.software_search, width=30)
        search_entry.pack(side=tk.LEFT, padx=(0, 20))

        ttk.Label(control_frame, text="Filter:").pack(side=tk.LEFT, padx=(0, 5))
        self.show_all_methods = tk.BooleanVar(value=False)
        ttk.Checkbutton(
            control_frame,
            text="Show Non-Manual Only",
            variable=self.show_all_methods,
            command=self._filter_software
        ).pack(side=tk.LEFT, padx=5)

        # Software list
        tree_frame = ttk.Frame(tab)
        tree_frame.pack(fill=tk.BOTH, expand=True)

        columns = ('name', 'version', 'method', 'package_id')
        self.software_tree = ttk.Treeview(tree_frame, columns=columns, show='headings')

        self.software_tree.heading('name', text='Software')
        self.software_tree.heading('version', text='Version')
        self.software_tree.heading('method', text='Install Method')
        self.software_tree.heading('package_id', text='Package ID')

        self.software_tree.column('name', width=300)
        self.software_tree.column('version', width=100)
        self.software_tree.column('method', width=100)
        self.software_tree.column('package_id', width=200)

        scrollbar = ttk.Scrollbar(tree_frame, orient=tk.VERTICAL, command=self.software_tree.yview)
        self.software_tree.configure(yscrollcommand=scrollbar.set)

        self.software_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)
        
        # Store filtered data
        self.all_software_data = []
        self.filtered_software_items = []

        # Individual install buttons
        btn_frame = ttk.Frame(tab)
        btn_frame.pack(fill=tk.X, pady=10)

        ttk.Button(btn_frame, text="Install via Winget", command=self._install_winget).pack(side=tk.LEFT, padx=5)
        ttk.Button(btn_frame, text="Install via Chocolatey", command=self._install_chocolatey).pack(side=tk.LEFT, padx=5)

    def _create_online_installer_lookup_tab(self):
        """Create tab for bulk searching and resolving manual software download URLs"""
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Installer Lookup")

        # Header with instructions
        header_frame = ttk.Frame(tab)
        header_frame.pack(fill=tk.X, pady=(0, 15))

        ttk.Label(
            header_frame,
            text="Find Installation URLs for Software",
            font=('Segoe UI', 11, 'bold')
        ).pack(anchor=tk.W)

        ttk.Label(
            header_frame,
            text="Search for fresh download links for software not available in Winget or Chocolatey.",
            font=('Segoe UI', 9),
            foreground='gray'
        ).pack(anchor=tk.W, pady=(5, 0))

        # Search controls in single row
        control_row = ttk.Frame(tab)
        control_row.pack(fill=tk.X, pady=(0, 10))

        ttk.Button(
            control_row,
            text="Search All for Download URLs",
            command=self._search_manual_downloads
        ).pack(side=tk.LEFT, padx=5)

        # Progress info - middle part
        self.installer_search_info = tk.StringVar(value="Ready to search")
        ttk.Label(control_row, textvariable=self.installer_search_info, font=('Segoe UI', 9)).pack(side=tk.LEFT, padx=10)

        # Action button that appears when done
        self.post_search_btn = ttk.Button(
            control_row, 
            text="Open Result File", 
            command=self._open_manual_downloads_file,
            width=20
        )
        # Hidden by default
        
        # Progress bar - right part
        self.installer_progress = ttk.Progressbar(control_row, mode='determinate', length=150)
        self.installer_progress.pack(side=tk.RIGHT, padx=5)

        # Main content: Left (search results) and Right (download selection)
        content_frame = ttk.Frame(tab)
        content_frame.pack(fill=tk.BOTH, expand=True, pady=10)

        # Left: Results area with scrollbar
        results_frame = ttk.LabelFrame(content_frame, text="Found URLs", padding=10)
        results_frame.pack(side=tk.LEFT, fill=tk.BOTH, expand=True, padx=(0, 10))

        scrollbar = ttk.Scrollbar(results_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.installer_results = tk.Text(
            results_frame,
            height=12,
            wrap=tk.WORD,
            yscrollcommand=scrollbar.set,
            font=('Consolas', 8),
            state=tk.DISABLED
        )
        self.installer_results.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.config(command=self.installer_results.yview)

        # Right: Download selection area
        download_frame = ttk.LabelFrame(content_frame, text="Select URLs to Download", padding=10)
        download_frame.pack(side=tk.RIGHT, fill=tk.BOTH, expand=True, padx=(10, 0))

        # Bottom-up packing for download controls to ensure visibility
        dl_action_btn = ttk.Button(
            download_frame,
            text="Download Selected URLs",
            command=self._download_selected_urls
        )
        dl_action_btn.pack(side=tk.BOTTOM, fill=tk.X, pady=(10, 0))

        # Folder selection
        folder_frame = ttk.Frame(download_frame)
        folder_frame.pack(side=tk.BOTTOM, fill=tk.X, pady=(0, 10))

        ttk.Label(folder_frame, text="Download to:").pack(side=tk.LEFT, padx=(0, 5))
        self.download_folder = tk.StringVar(value=str(Path.home() / 'Downloads'))
        ttk.Entry(folder_frame, textvariable=self.download_folder, width=35).pack(side=tk.LEFT, padx=(0, 5))
        ttk.Button(folder_frame, text="Browse...", command=self._browse_download_folder, width=10).pack(side=tk.LEFT)

        # Explain download functionality
        ttk.Label(
            download_frame,
            text="Files will be downloaded to the folder above.\nYou can then run them manually to reinstall your software.",
            font=('Segoe UI', 8),
            foreground='gray',
            justify=tk.LEFT
        ).pack(side=tk.BOTTOM, fill=tk.X, pady=(0, 10))

        # Download selection controls
        dl_btn_frame = ttk.Frame(download_frame)
        dl_btn_frame.pack(side=tk.BOTTOM, fill=tk.X, pady=(0, 10))

        ttk.Button(dl_btn_frame, text="Select All", command=self._select_all_downloads, width=15).pack(side=tk.LEFT, padx=5)
        ttk.Button(dl_btn_frame, text="Deselect All", command=self._deselect_all_downloads, width=15).pack(side=tk.LEFT, padx=5)

        # Info at top
        self.download_info_label = ttk.Label(
            download_frame,
            text="No search results yet.\nClick 'Search All for Download URLs' to find installer links.",
            font=('Segoe UI', 9),
            foreground='gray'
        )
        self.download_info_label.pack(side=tk.TOP, anchor=tk.W, pady=(0, 10))

        # Expanding Treeview in the middle
        dl_tree_frame = ttk.Frame(download_frame)
        dl_tree_frame.pack(side=tk.TOP, fill=tk.BOTH, expand=True, pady=(0, 10))

        dl_scrollbar = ttk.Scrollbar(dl_tree_frame)
        dl_scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        self.download_selection_tree = ttk.Treeview(
            dl_tree_frame,
            columns=('url',),
            show='tree headings',
            height=10,
            yscrollcommand=dl_scrollbar.set
        )
        self.download_selection_tree.heading('#0', text='Select')
        self.download_selection_tree.heading('url', text='URL')
        self.download_selection_tree.column('#0', width=30)
        self.download_selection_tree.column('url', width=300)
        self.download_selection_tree.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        dl_scrollbar.config(command=self.download_selection_tree.yview)

        # Bind checkbox toggle
        self.download_selection_tree.bind('<Button-1>', self._toggle_download_selection)

        # Action buttons at bottom
        action_frame = ttk.Frame(tab)
        action_frame.pack(fill=tk.X, pady=(10, 0))

        ttk.Button(
            action_frame,
            text="Open Manual Downloads File",
            command=self._open_manual_downloads_file
        ).pack(side=tk.LEFT, padx=5)

        ttk.Button(
            action_frame,
            text="Clear Results",
            command=self._clear_installer_results
        ).pack(side=tk.LEFT, padx=5)

    def _clear_installer_results(self):
        """Clear the installer results text widget"""
        self.installer_results.config(state=tk.NORMAL)
        self.installer_results.delete(1.0, tk.END)
        self.installer_results.config(state=tk.DISABLED)
        self.installer_search_info.set("Ready to search")
        self.installer_progress['value'] = 0
        self.post_search_btn.pack_forget()

        for item in self.download_selection_tree.get_children():
            self.download_selection_tree.delete(item)

        self.download_info_label.config(text="No search results yet.\nClick 'Search All for Download URLs' to find installer links.\n\nThen select which URLs to download here.")

    def _toggle_download_selection(self, event):
        """Toggle checkbox selection in the download tree"""
        item = self.download_selection_tree.identify_row(event.y)
        if not item:
            return

        current = self.download_selection_tree.item(item, 'text')
        new_state = '☑' if current == '☐' else '☐'
        self.download_selection_tree.item(item, text=new_state)

    def _search_manual_downloads(self):
        """Search for manual download URLs for all software"""
        if not self.package_data or 'software' not in self.package_data:
            messagebox.showerror("Error", "No software data loaded")
            return

        software = self.package_data.get('software', [])
        if not software:
            messagebox.showerror("Error", "No software found in package")
            return

        def search():
            try:
                self._clear_installer_results()
                self.installer_search_info.set(f"Searching for download URLs for {len(software)} software items...")
                self.root.update_idletasks()

                # Load the resolver script
                src_dir = Path(__file__).parent.parent
                resolver_script = src_dir / 'restore' / 'manual_download_resolver.ps1'

                if not resolver_script.exists():
                    self._log(f"ERROR: Resolver script not found at {resolver_script}", "restore_installer_lookup_debug.txt")
                    self.installer_results.config(state=tk.NORMAL)
                    self.installer_results.insert(tk.END, f"ERROR: Resolver script not found\n{resolver_script}")
                    self.installer_results.config(state=tk.DISABLED)
                    return

                # Create temporary files
                temp_script = Path(self.package_path) / 'temp_search_downloads.ps1'
                software_json = Path(self.package_path) / 'software_search_list.json'
                manual_downloads = Path(self.package_path) / 'manual_downloads.md'

                # Write software list
                import json
                with open(software_json, 'w', encoding='utf-8') as f:
                    json.dump(software, f, indent=2)

                # Create resolver script call
                script_content = f"""
. "{resolver_script}"
$software = ConvertFrom-Json (Get-Content "{software_json}" -Raw)
$resolved = Resolve-ManualDownloads -Software $software -OutputPath "{manual_downloads}"
if ($resolved) {{
    Write-Host "Successfully resolved downloads for $($resolved.Count) items"
    $resolved | ConvertTo-Json | Write-Host
}}
"""

                with open(temp_script, 'w') as f:
                    f.write(script_content)

                # Execute search
                self._log("Starting manual download URL search...", "restore_installer_lookup_debug.txt")
                process = subprocess.Popen(
                    ['powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', str(temp_script)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    cwd=str(self.package_path)
                )

                results_text = []
                for line in process.stdout:
                    line = line.strip()
                    if line:
                        results_text.append(line)
                        self._log(line, "restore_installer_lookup_debug.txt")

                process.wait()

                # Update UI with results
                self.root.after(0, lambda: self._update_installer_results(results_text, manual_downloads))
                self._log("Manual download search complete.", "restore_installer_lookup_debug.txt")

                # Clean up temp files
                temp_script.unlink(missing_ok=True)
                software_json.unlink(missing_ok=True)

            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror("Error", f"Search failed: {str(e)}"))
                self.root.after(0, lambda: self._log(f"Error: {str(e)}", "restore_installer_lookup_debug.txt"))

        threading.Thread(target=search, daemon=True).start()

    def _update_installer_results(self, results, manual_downloads_path):
        """Update the results display with search results"""
        self.installer_results.config(state=tk.NORMAL)
        
        # Show the "Open Result File" button
        self.post_search_btn.pack(side=tk.LEFT, padx=10)

        # Clear previous selections
        for item in self.download_selection_tree.get_children():
            self.download_selection_tree.delete(item)
        
        found_urls = []
        item_count = 0
        
        if manual_downloads_path.exists():
            try:
                with open(manual_downloads_path, 'r', encoding='utf-8') as f:
                    content = f.read()
                    self.installer_results.insert(tk.END, content)
                    
                    # Extract URLs from markdown file (supporting [text](url) format)
                    import re
                    # Look for URLs inside markdown parentheses OR raw URLs
                    urls = re.findall(r'\]\((https?://[^\s\)]+|winget://[^\s\)]+)\)', content)
                    # Also catch raw URLs just in case
                    raw_urls = re.findall(r'(?:https?|winget)://[^\s\)\],]+', content)
                    all_found = list(set(urls + raw_urls))
                    # Filter out invalid/empty winget URLs
                    found_urls = [u for u in all_found if u.strip() not in ["winget://install/", "winget://install"]]
                    
                    # Count actual software entries in the markdown (lines starting with ###)
                    item_count = len(re.findall(r'^### ', content, re.MULTILINE))
                
                self.installer_search_info.set(
                    f"✓ Search complete! Found {len(found_urls)} URLs across {item_count} items."
                )
            except Exception as e:
                self.installer_results.insert(tk.END, f"Error reading results: {str(e)}\n\n")
                self.installer_search_info.set("Search complete but error reading results file")
        else:
            for line in results:
                self.installer_results.insert(tk.END, line + '\n')
            self.installer_search_info.set(f"Search complete! Processed {len(results)} items")

        # Populate download tree with found URLs
        if found_urls:
            # Filter out search URLs (Google searches used as fallback)
            selectable_urls = [url for url in found_urls if "google.com/search" not in url.lower()]
            
            if selectable_urls:
                for url in selectable_urls:
                    self.download_selection_tree.insert('', 'end', text='☐', values=(url,))
                self.download_info_label.config(text=f"✓ Found {len(selectable_urls)} direct URLs\nSelect which ones to download below:")
            else:
                self.download_info_label.config(text="No direct download URLs found (only search fallbacks).\nCheck the manual results file on the left.")
        else:
            self.download_info_label.config(text="No download URLs found in search results.\nCheck the search results on the left for more details.")

        self.installer_results.config(state=tk.DISABLED)
        self.installer_progress['value'] = 100

    def _open_manual_downloads_file(self):
        """Open the manual downloads file for viewing/editing"""
        if not self.package_path:
            messagebox.showerror("Error", "No package loaded")
            return

        manual_file = Path(self.package_path) / 'manual_downloads.md'
        if manual_file.exists():
            os.startfile(str(manual_file))
        else:
            messagebox.showinfo(
                "Info",
                "No manual downloads file found yet.\n\n" +
                "Click 'Search All for Download URLs' first to generate the file."
            )

    def _create_restore_options_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Restore Options")

        # Info box
        info_frame = ttk.LabelFrame(tab, text="What Will Be Restored", padding=10)
        info_frame.pack(fill=tk.X, pady=(0, 15))

        info_text = tk.Text(info_frame, font=('Segoe UI', 10), height=4, wrap=tk.WORD)
        info_text.pack(fill=tk.X)
        info_text.insert(tk.END, """Select which categories to restore on this system. By default, configuration
categories are enabled, while service and task restoration is disabled (they will be
recreated when you reinstall software). You can enable/disable individual categories below.""")
        info_text.config(state=tk.DISABLED)

        # Restore options
        options_frame = ttk.LabelFrame(tab, text="Restoration Categories", padding=10)
        options_frame.pack(fill=tk.BOTH, expand=True)

        # Create scrollable frame
        canvas = tk.Canvas(options_frame)
        scrollbar = ttk.Scrollbar(options_frame, orient=tk.VERTICAL, command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas)

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )
        canvas.create_window((0, 0), window=scrollable_frame, anchor=tk.NW)
        canvas.configure(yscrollcommand=scrollbar.set)

        # Restore options with defaults
        self.restore_options = {}
        options_list = [
            ('RestoreLicenseKeys', 'License Keys (Windows, Office, WiFi passwords)', True, 'Recommended: Keep enabled to restore product keys'),
            ('RestoreEnvironmentVariables', 'Environment Variables', True, 'Recommended: Keep enabled to restore PATH and custom variables'),
            ('RestoreNetwork', 'Network Settings (Hosts, DNS)', True, 'Recommended: Keep enabled to restore custom network settings'),
            ('RestoreFileAssociations', 'File Associations', True, 'Recommended: Keep enabled to restore custom file type associations'),
            ('RestoreWindowsSettings', 'Windows Settings (Display, Keyboard)', True, 'Recommended: Keep enabled to restore your Windows preferences'),
            ('RestoreScheduledTasks', 'Scheduled Tasks', False, 'Optional: Disabled by default - most tasks are system-generated'),
            ('RestoreServices', 'Service Configuration', False, 'Optional: Disabled by default - most will be recreated by software'),
        ]

        for key, name, default, tooltip in options_list:
            container = ttk.Frame(scrollable_frame)
            container.pack(fill=tk.X, pady=8, padx=5)

            self.restore_options[key] = tk.BooleanVar(value=default)
            
            # Checkbox and label
            cb = ttk.Checkbutton(container, text=name, variable=self.restore_options[key])
            cb.pack(anchor=tk.W)

            # Tooltip/description
            desc_label = ttk.Label(container, text=tooltip, foreground='gray', font=('Segoe UI', 9))
            desc_label.pack(anchor=tk.W, padx=(20, 0))

        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Preset buttons
        preset_frame = ttk.Frame(tab)
        preset_frame.pack(fill=tk.X, pady=10)

        ttk.Button(
            preset_frame,
            text="Use Recommended Defaults",
            command=self._set_recommended_options
        ).pack(side=tk.LEFT, padx=5)

        ttk.Button(
            preset_frame,
            text="Restore Everything",
            command=self._set_all_options
        ).pack(side=tk.LEFT, padx=5)

    def _set_recommended_options(self):
        """Set options to recommended defaults"""
        defaults = {
            'RestoreLicenseKeys': True,
            'RestoreEnvironmentVariables': True,
            'RestoreNetwork': True,
            'RestoreFileAssociations': True,
            'RestoreWindowsSettings': True,
            'RestoreScheduledTasks': False,
            'RestoreServices': False,
        }
        for key, value in defaults.items():
            if key in self.restore_options:
                self.restore_options[key].set(value)
        self.status_var.set("Restored recommended defaults")

    def _set_all_options(self):
        """Enable all restoration options"""
        for var in self.restore_options.values():
            var.set(True)
        self.status_var.set("All restoration options enabled")

    def _create_config_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Configuration")

        # Create scrollable frame
        canvas = tk.Canvas(tab, highlightthickness=0)
        scrollbar = ttk.Scrollbar(tab, orient=tk.VERTICAL, command=canvas.yview)
        scrollable_frame = ttk.Frame(canvas)

        scrollable_frame.bind(
            "<Configure>",
            lambda e: canvas.configure(scrollregion=canvas.bbox("all"))
        )

        canvas.create_window((0, 0), window=scrollable_frame, anchor="nw")
        canvas.configure(yscrollcommand=scrollbar.set)

        # Config options
        options_frame = ttk.LabelFrame(scrollable_frame, text="Restore Options", padding=15)
        options_frame.pack(fill=tk.X, expand=True, pady=(0, 20))

        ttk.Label(
            options_frame, 
            text="Select which settings and configurations to restore to this new system:",
            font=('Segoe UI', 10),
            foreground='gray'
        ).pack(anchor=tk.W, pady=(0, 15))

        self.config_vars = {}
        configs = [
            ('env_vars', 'Environment Variables', 'User and system path variables'),
            ('scheduled_tasks', 'Scheduled Tasks', 'Custom automated tasks'),
            ('network', 'Network Settings', 'Hosts file and DNS configurations'),
            ('file_assoc', 'File Associations', 'Default application mappings'),
            ('explorer', 'Explorer Settings', 'Taskbar, hidden files, and desktop icons'),
            ('vscode', 'VS Code Settings', 'Settings, keybindings, and extensions list'),
            ('git_config', 'Git Configuration', 'Global git settings and ignores'),
            ('ssh_config', 'SSH Configuration', 'Keys and known hosts'),
            ('terminal', 'Windows Terminal', 'Profiles and color schemes'),
            ('browser_bookmarks', 'Browser Bookmarks', 'Chrome, Edge, and Firefox bookmarks'),
            ('powershell', 'PowerShell Profile', 'Custom commands and aliases'),
            ('wifi', 'WiFi Profiles', 'Saved networks and passwords'),
        ]

        for key, name, desc in configs:
            frame = ttk.Frame(options_frame)
            frame.pack(fill=tk.X, pady=4)
            
            self.config_vars[key] = tk.BooleanVar(value=True)
            cb = ttk.Checkbutton(frame, text=name, variable=self.config_vars[key])
            cb.pack(side=tk.LEFT)
            
            ttk.Label(frame, text=f" — {desc}", font=('Segoe UI', 9), foreground='#666666').pack(side=tk.LEFT, padx=5)

        # License info
        license_frame = ttk.LabelFrame(scrollable_frame, text="License Keys", padding=15)
        license_frame.pack(fill=tk.X, expand=True, pady=(0, 10))

        ttk.Label(
            license_frame, 
            text="Your original Windows Product Key found during scan:",
            font=('Segoe UI', 9),
            foreground='gray'
        ).pack(anchor=tk.W, pady=(0, 10))

        key_display_frame = ttk.Frame(license_frame)
        key_display_frame.pack(fill=tk.X)

        self.windows_key_label = tk.StringVar(value="Not found in package")
        ttk.Label(
            key_display_frame, 
            textvariable=self.windows_key_label, 
            font=('Consolas', 12, 'bold'),
            foreground='#2e7d32'
        ).pack(side=tk.LEFT, padx=(0, 20))

        ttk.Button(
            key_display_frame, 
            text="Copy to Clipboard", 
            command=self._copy_windows_key,
            width=20
        ).pack(side=tk.LEFT)

        # Packing the canvas and scrollbar last
        canvas.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        # Mousewheel support for scrolling (only when mouse is over the canvas)
        def _on_mousewheel(event):
            canvas.yview_scroll(int(-1*(event.delta/120)), "units")
        
        def _bind_mousewheel(event):
            canvas.bind_all("<MouseWheel>", _on_mousewheel)
            
        def _unbind_mousewheel(event):
            canvas.unbind_all("<MouseWheel>")

        canvas.bind("<Enter>", _bind_mousewheel)
        canvas.bind("<Leave>", _unbind_mousewheel)

    def _create_drive_settings_tab(self):
        """Create tab for configuring installation drives on new system"""
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Drive Settings")

        # Instructions
        info_frame = ttk.Frame(tab)
        info_frame.pack(fill=tk.X, pady=(0, 15))
        
        ttk.Label(
            info_frame,
            text="Configure where to install Windows and applications on your new system.",
            font=('Segoe UI', 10),
            foreground='#0066cc'
        ).pack(anchor=tk.W)
        
        ttk.Label(
            info_frame,
            text="These settings help organize your software and data on the new system.",
            font=('Segoe UI', 9),
            foreground='gray'
        ).pack(anchor=tk.W, pady=(5, 0))

        # Drive selection frame
        drive_frame = ttk.LabelFrame(tab, text="Installation Drives", padding=10)
        drive_frame.pack(fill=tk.X, pady=10)

        # Primary drive
        ttk.Label(drive_frame, text="Primary (Windows + most apps):", font=('Segoe UI', 10, 'bold')).grid(row=0, column=0, sticky=tk.W, padx=5, pady=8)
        primary_help = ttk.Label(drive_frame, text="Where Windows OS & most software will install (usually C:)", font=('Segoe UI', 9), foreground='gray')
        primary_help.grid(row=0, column=2, sticky=tk.W, padx=5)
        self.primary_drive = ttk.Combobox(drive_frame, values=['C:', 'D:', 'E:', 'F:', 'G:'], width=15, state='readonly', font=('Segoe UI', 10))
        self.primary_drive.set('C:')
        self.primary_drive.grid(row=0, column=1, padx=5, pady=8)

        # Secondary drive
        ttk.Label(drive_frame, text="Secondary (large apps/games):", font=('Segoe UI', 10, 'bold')).grid(row=1, column=0, sticky=tk.W, padx=5, pady=8)
        secondary_help = ttk.Label(drive_frame, text="For large games or apps if you have a separate drive", font=('Segoe UI', 9), foreground='gray')
        secondary_help.grid(row=1, column=2, sticky=tk.W, padx=5)
        self.secondary_drive = ttk.Combobox(drive_frame, values=['C:', 'D:', 'E:', 'F:', 'G:'], width=15, state='readonly', font=('Segoe UI', 10))
        self.secondary_drive.set('D:')
        self.secondary_drive.grid(row=1, column=1, padx=5, pady=8)

        # Data drive
        ttk.Label(drive_frame, text="Data (documents, downloads):", font=('Segoe UI', 10, 'bold')).grid(row=2, column=0, sticky=tk.W, padx=5, pady=8)
        data_help = ttk.Label(drive_frame, text="For user files like Documents, Downloads, Pictures, etc.", font=('Segoe UI', 9), foreground='gray')
        data_help.grid(row=2, column=2, sticky=tk.W, padx=5)
        self.data_drive = ttk.Combobox(drive_frame, values=['C:', 'D:', 'E:', 'F:', 'G:'], width=15, state='readonly', font=('Segoe UI', 10))
        self.data_drive.set('D:')
        self.data_drive.grid(row=2, column=1, padx=5, pady=8)

        # Example section
        example_frame = ttk.LabelFrame(tab, text="Example Configurations", padding=10)
        example_frame.pack(fill=tk.X, pady=10)

        ttk.Label(example_frame, text="Single Drive System (most common):", font=('Segoe UI', 10, 'bold')).pack(anchor=tk.W, pady=(0, 5))
        ttk.Label(example_frame, text="Set all three to C: - everything installs on one drive", font=('Segoe UI', 9), foreground='gray').pack(anchor=tk.W, pady=(0, 10))

        ttk.Label(example_frame, text="Dual Drive System:", font=('Segoe UI', 10, 'bold')).pack(anchor=tk.W, pady=(0, 5))
        ttk.Label(example_frame, text="Primary=C:, Secondary=D:, Data=D: - OS on C:, apps & files on larger D:", font=('Segoe UI', 9), foreground='gray').pack(anchor=tk.W, pady=(0, 10))

        ttk.Label(example_frame, text="Triple Drive System:", font=('Segoe UI', 10, 'bold')).pack(anchor=tk.W, pady=(0, 5))
        ttk.Label(example_frame, text="Primary=C:, Secondary=E:, Data=F: - dedicated drive for each purpose", font=('Segoe UI', 9), foreground='gray').pack(anchor=tk.W)

    def _create_progress_tab(self):
        tab = ttk.Frame(self.notebook, padding=10)
        self.notebook.add(tab, text="Progress")

        # Progress bar
        self.progress_var = tk.DoubleVar()
        self.progress_bar = ttk.Progressbar(tab, variable=self.progress_var, maximum=100)
        self.progress_bar.pack(fill=tk.X, pady=10)

        self.progress_label = tk.StringVar(value="Ready")
        ttk.Label(tab, textvariable=self.progress_label).pack()

        # Log output
        log_frame = ttk.LabelFrame(tab, text="Log", padding=5)
        log_frame.pack(fill=tk.BOTH, expand=True, pady=10)

        self.log_text = tk.Text(log_frame, font=('Consolas', 9), height=20)
        self.log_text.pack(fill=tk.BOTH, expand=True)

        scrollbar = ttk.Scrollbar(self.log_text, command=self.log_text.yview)
        self.log_text.configure(yscrollcommand=scrollbar.set)

    def _auto_detect_package(self):
        """Auto-detect migration package on common locations"""
        search_paths = [
            Path.cwd() / 'migration_package.json',
            Path.cwd().parent / 'ReWin' / 'migration_package.json',
        ]

        # Check all drive letters for ReWin folder
        for letter in 'DEFGHIJK':
            search_paths.append(Path(f'{letter}:/ReWin/migration_package.json'))
            search_paths.append(Path(f'{letter}:/migration_package.json'))

        for path in search_paths:
            if path.exists():
                self._load_package_from_path(str(path.parent))
                return

    def _load_package(self):
        directory = filedialog.askdirectory(title="Select migration package directory")
        if directory:
            self._load_package_from_path(directory)

    def _load_package_from_path(self, path):
        try:
            package_file = Path(path) / 'migration_package.json'
            if not package_file.exists():
                messagebox.showerror("Error", "migration_package.json not found in selected directory")
                return

            with open(package_file, 'r', encoding='utf-8-sig') as f:
                self.package_data = json.load(f)

            self.package_path = path
            self.package_path_var.set(f"Loaded: {path}")

            self._populate_software_list()
            self._update_license_info()
            self._update_config_options()

            self.status_var.set(f"Package loaded from {path}")

        except Exception as e:
            messagebox.showerror("Error", f"Failed to load package: {str(e)}")

    def _populate_software_list(self):
        """Populate software tree and store all data for filtering"""
        if not self.package_data:
            return

        software = self.package_data.get('software', [])
        store_apps = self.package_data.get('store_apps', [])
        
        # Combine software and store apps for internal storage
        self.all_software_data = []
        
        for item in software:
            self.all_software_data.append(item)
        
        for store_app in store_apps:
            # Ensure store apps have required fields
            self.all_software_data.append({
                'SoftwareName': store_app.get('Name', ''),
                'Version': store_app.get('Version', ''),
                'InstallMethod': 'Store',
                'PackageFamilyName': store_app.get('PackageFamilyName', ''),
                'Publisher': store_app.get('Publisher', '')
            })
        
        # Display filtered
        self._refresh_software_display()

        # Calculate counts for summary
        winget_count = sum(1 for item in self.all_software_data if item.get('InstallMethod') == 'Winget')
        choco_count = sum(1 for item in self.all_software_data if item.get('InstallMethod') == 'Chocolatey')
        manual_count = sum(1 for item in self.all_software_data if item.get('InstallMethod') == 'Manual')
        store_count = sum(1 for item in self.all_software_data if item.get('InstallMethod') == 'Store')

        self.software_summary.set(
            f"Total: {len(self.all_software_data)} | Winget: {winget_count} | Chocolatey: {choco_count} | Store: {store_count} | Manual: {manual_count}"
        )

    def _update_license_info(self):
        if not self.package_data:
            return

        licenses = self.package_data.get('licenses', {})
        windows_key = licenses.get('windows_key', {})
        if windows_key:
            key = windows_key.get('RecommendedKey', 'Not found')
            self.windows_key_label.set(f"Windows Key: {key}")

    def _update_config_options(self):
        if not self.package_data:
            return

        configs = self.package_data.get('configs', {})
        for key, var in self.config_vars.items():
            if key in configs:
                var.set(configs[key])

    def _copy_windows_key(self):
        if self.package_data:
            licenses = self.package_data.get('licenses', {})
            windows_key = licenses.get('windows_key', {})
            key = windows_key.get('RecommendedKey', '')
            if key:
                self.root.clipboard_clear()
                self.root.clipboard_append(key)
                messagebox.showinfo("Copied", "Windows key copied to clipboard")

    def _log(self, message, debug_file=None):
        self.log_text.insert(tk.END, f"{message}\n")
        self.log_text.see(tk.END)
        self.root.update()
        
        if debug_file:
            self._write_debug(debug_file, message)

    def _write_debug(self, filename, message):
        """Write a message to a debug log file in the package directory"""
        if not self.package_path:
            return
            
        try:
            debug_path = Path(self.package_path) / filename
            timestamp = time.strftime("%Y-%m-%d %H:%M:%S")
            with open(debug_path, 'a', encoding='utf-8') as f:
                f.write(f"[{timestamp}] {message}\n")
        except:
            pass # Silently fail if cannot write to debug log

    def _install_winget(self):
        if not self.package_path:
            messagebox.showerror("Error", "No package loaded")
            return

        self.notebook.select(3)  # Switch to progress tab

        def install():
            script_path = Path(self.package_path) / 'install_winget.ps1'
            if not script_path.exists():
                self._log("Winget install script not found", "restore_debug.txt")
                return

            self._log("Starting Winget installation...", "restore_debug.txt")
            self.progress_label.set("Installing via Winget...")

            try:
                process = subprocess.Popen(
                    ['powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', str(script_path)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1
                )

                for line in process.stdout:
                    self.root.after(0, lambda l=line: self._log(l.strip(), "restore_debug.txt"))

                process.wait()
                self.root.after(0, lambda: self._log("Winget installation complete!", "restore_debug.txt"))
                self.root.after(0, lambda: self.progress_label.set("Winget installation complete"))

            except Exception as e:
                self.root.after(0, lambda: self._log(f"Error: {str(e)}", "restore_debug.txt"))

        threading.Thread(target=install, daemon=True).start()

    def _install_chocolatey(self):
        if not self.package_path:
            messagebox.showerror("Error", "No package loaded")
            return

        self.notebook.select(3)

        def install():
            script_path = Path(self.package_path) / 'install_chocolatey.ps1'
            if not script_path.exists():
                self._log("Chocolatey install script not found", "restore_debug.txt")
                return

            self._log("Starting Chocolatey installation...", "restore_debug.txt")
            self.progress_label.set("Installing via Chocolatey...")

            try:
                process = subprocess.Popen(
                    ['powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', str(script_path)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1,
                    creationflags=subprocess.CREATE_NEW_CONSOLE
                )

                process.wait()
                self.root.after(0, lambda: self._log("Chocolatey installation complete!", "restore_debug.txt"))
                self.root.after(0, lambda: self.progress_label.set("Chocolatey installation complete"))

            except Exception as e:
                self.root.after(0, lambda: self._log(f"Error: {str(e)}", "restore_debug.txt"))

        threading.Thread(target=install, daemon=True).start()

    def _restore_configs(self):
        if not self.package_path:
            messagebox.showerror("Error", "No package loaded")
            return

        self.notebook.select(3)

        def restore():
            self._log("Starting configuration restore...", "restore_debug.txt")
            self.progress_label.set("Restoring configurations...")

            try:
                # Build options dict from restore options tab
                options = {key: var.get() for key, var in self.restore_options.items()}

                script_dir = Path(__file__).parent.parent / 'restore'
                restore_script = script_dir / 'restore_config.ps1'

                # Create a temporary script to run the restore
                temp_script = Path(self.package_path) / 'temp_restore.ps1'
                with open(temp_script, 'w') as f:
                    f.write(f"""
. "{restore_script}"
Start-FullRestore -PackagePath "{self.package_path}" -Options @{{
{chr(10).join(f'    {k} = ${str(v).lower()}' for k, v in options.items())}
}}
""")

                process = subprocess.Popen(
                    ['powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', str(temp_script)],
                    stdout=subprocess.PIPE,
                    stderr=subprocess.STDOUT,
                    text=True,
                    bufsize=1
                )

                for line in process.stdout:
                    self.root.after(0, lambda l=line: self._log(l.strip(), "restore_debug.txt"))

                process.wait()

                # Clean up temp script
                temp_script.unlink(missing_ok=True)

                self.root.after(0, lambda: self._log("Configuration restore complete!", "restore_debug.txt"))
                self.root.after(0, lambda: self.progress_label.set("Configuration restore complete"))

            except Exception as e:
                self.root.after(0, lambda: self._log(f"Error: {str(e)}", "restore_debug.txt"))

        threading.Thread(target=restore, daemon=True).start()

    def _install_all_software(self):
        if not self.package_path:
            messagebox.showerror("Error", "No package loaded")
            return

        if messagebox.askyesno("Confirm", "This will install all selected software. Continue?"):
            self._install_winget()
            # Chocolatey will be installed after winget (user can click manually)

    def _full_restore(self):
        if not self.package_path:
            messagebox.showerror("Error", "No package loaded")
            return

        if messagebox.askyesno("Confirm", "This will install all software and restore all configurations. Continue?"):
            self.notebook.select(3)

            def full():
                # Install software first
                self._log("=" * 50, "restore_debug.txt")
                self._log("PHASE 1: Installing Software", "restore_debug.txt")
                self._log("=" * 50, "restore_debug.txt")

                # Winget
                script_path = Path(self.package_path) / 'install_winget.ps1'
                if script_path.exists():
                    self._log("\nInstalling via Winget...", "restore_debug.txt")
                    process = subprocess.Popen(
                        ['powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', str(script_path)],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True
                    )
                    for line in process.stdout:
                        self.root.after(0, lambda l=line: self._log(l.strip(), "restore_debug.txt"))
                    process.wait()

                # Chocolatey
                script_path = Path(self.package_path) / 'install_chocolatey.ps1'
                if script_path.exists():
                    self._log("\nInstalling via Chocolatey...", "restore_debug.txt")
                    process = subprocess.Popen(
                        ['powershell.exe', '-ExecutionPolicy', 'Bypass', '-File', str(script_path)],
                        stdout=subprocess.PIPE,
                        stderr=subprocess.STDOUT,
                        text=True
                    )
                    for line in process.stdout:
                        self.root.after(0, lambda l=line: self._log(l.strip(), "restore_debug.txt"))
                    process.wait()

                # Restore configs
                self._log("\n" + "=" * 50, "restore_debug.txt")
                self._log("PHASE 2: Restoring Configuration", "restore_debug.txt")
                self._log("=" * 50 + "\n", "restore_debug.txt")

                self.root.after(0, self._restore_configs)

            threading.Thread(target=full, daemon=True).start()

    def _create_quick_guide_tab(self):
        """Create a Quick Guide tab that displays the README"""
        tab = ttk.Frame(self.notebook)
        self.notebook.add(tab, text="Quick Guide")

        # Header
        header_frame = ttk.Frame(tab)
        header_frame.pack(fill=tk.X, padx=10, pady=10)
        ttk.Label(header_frame, text="ReWin - Quick Guide", style='Header.TLabel').pack(side=tk.LEFT)

        # Text widget with scrollbar
        text_frame = ttk.Frame(tab)
        text_frame.pack(fill=tk.BOTH, expand=True, padx=10, pady=10)

        scrollbar = ttk.Scrollbar(text_frame)
        scrollbar.pack(side=tk.RIGHT, fill=tk.Y)

        readme_text = tk.Text(text_frame, font=('Segoe UI', 10), wrap=tk.WORD, yscrollcommand=scrollbar.set)
        readme_text.pack(side=tk.LEFT, fill=tk.BOTH, expand=True)
        scrollbar.config(command=readme_text.yview)

        # Load and display README
        try:
            readme_path = Path(__file__).parent.parent.parent / 'README.md'
            if readme_path.exists():
                with open(readme_path, 'r', encoding='utf-8-sig') as f:
                    readme_content = f.read()
                readme_text.insert(tk.END, readme_content)
            else:
                readme_text.insert(tk.END, "README.md not found")
        except Exception as e:
            readme_text.insert(tk.END, f"Error loading README: {str(e)}")

        readme_text.config(state=tk.DISABLED)

    def _refresh_software_display(self):
        """Refresh the tree view with filtered software"""
        for item in self.software_tree.get_children():
            self.software_tree.delete(item)

        search_term = self.software_search.get().lower()
        show_non_manual_only = self.show_all_methods.get()

        for item in self.all_software_data:
            name = item.get('SoftwareName', '').lower()
            method = item.get('InstallMethod', 'Manual')

            # Apply search filter
            if search_term and search_term not in name:
                continue

            # Apply method filter
            if show_non_manual_only and method == 'Manual':
                continue

            # Add to tree
            display_name = item.get('SoftwareName', '')
            version = item.get('Version', '')
            pkg_id = item.get('WingetId') or item.get('ChocolateyId') or item.get('PackageFamilyName', '')

            self.software_tree.insert('', 'end', values=(display_name, version, method, pkg_id))

    def _filter_software(self):
        """Filter software list based on search and toggle"""
        self._refresh_software_display()

    def _select_all_downloads(self):
        """Select all items in download tree"""
        for item in self.download_selection_tree.get_children():
            self.download_selection_tree.item(item, text='☑')

    def _deselect_all_downloads(self):
        """Deselect all items in download tree"""
        for item in self.download_selection_tree.get_children():
            self.download_selection_tree.item(item, text='☐')

    def _browse_download_folder(self):
        """Browse for download folder"""
        from tkinter import filedialog
        folder = filedialog.askdirectory(title="Select Download Folder")
        if folder:
            self.download_folder.set(folder)

    def _download_selected_urls(self):
        """Download selected URLs to specified folder"""
        selected_urls = []
        for item in self.download_selection_tree.get_children():
            if self.download_selection_tree.item(item, 'text') == '☑':
                url = self.download_selection_tree.item(item, 'values')[0]
                selected_urls.append(url)

        if not selected_urls:
            messagebox.showinfo("Info", "No URLs selected for download")
            return

        download_folder = self.download_folder.get()
        if not download_folder or not Path(download_folder).exists():
            messagebox.showerror("Error", "Invalid download folder selected")
            return

        def download():
            try:
                import urllib.request
                for i, url in enumerate(selected_urls):
                    try:
                        if url.startswith('winget://'):
                            pkg_id = url.split('/')[-1]
                            self._log(f"Installer found via Winget: {pkg_id}", "restore_installer_lookup_debug.txt")
                            self._log(f"  Note: You can install this later via the Winget install phase.", "restore_installer_lookup_debug.txt")
                            continue

                        # Extract filename from URL
                        filename = url.split('/')[-1].split('?')[0] or 'installer.exe'
                        filepath = Path(download_folder) / filename
                        
                        self._log(f"Downloading ({i+1}/{len(selected_urls)}): {filename}", "restore_installer_lookup_debug.txt")
                        urllib.request.urlretrieve(url, filepath)
                        self._log(f"✓ Downloaded: {filename}", "restore_installer_lookup_debug.txt")
                    except Exception as e:
                        self._log(f"✗ Failed to download {url}: {str(e)}", "restore_installer_lookup_debug.txt")

                self.root.after(0, lambda: messagebox.showinfo(
                    "Complete",
                    f"Downloaded {len(selected_urls)} files to:\n{download_folder}"
                ))
            except Exception as e:
                self.root.after(0, lambda: messagebox.showerror("Error", f"Download failed: {str(e)}"))
                self._log(f"Download failed: {str(e)}", "restore_installer_lookup_debug.txt")

        threading.Thread(target=download, daemon=True).start()


def main():
    root = tk.Tk()
    app = RestoreGUI(root)
    root.mainloop()


if __name__ == '__main__':
    main()
