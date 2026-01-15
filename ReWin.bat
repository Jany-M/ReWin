@echo off
title ReWin Migration Tool
color 0A

echo.
echo  +====================================================================+
echo  :                                                                    :
echo  :                   R E W I N   M I G R A T I O N                   :
echo  :                         T O O L                                    :
echo  :                                                                    :
echo  :          Automated Windows Migration Solution                      :
echo  :                                                                    :
echo  :                   by Jany Martelli                                 :
echo  :          https://github.com/Jany-M/ReWin                           :
echo  :                                                                    :
echo  +====================================================================+
echo.
echo.

echo  Select an option:
echo.
echo    [1] Scan This System (Before migration)
echo    [2] Open Scanner GUI
echo    [3] Restore System (After Windows install)
echo    [4] Quick Software Install
echo    [5] Exit
echo.

set /p choice="  Enter choice (1-5): "

if "%choice%"=="1" goto scan
if "%choice%"=="2" goto scanner_gui
if "%choice%"=="3" goto restore
if "%choice%"=="4" goto quick_install
if "%choice%"=="5" exit /b

echo Invalid choice. Please try again.
pause
goto :eof

:scan
echo.
echo Starting system scan...
echo.
powershell -ExecutionPolicy Bypass -File "%~dp0src\scanner\main_scanner.ps1" -OutputPath "%~dp0output" -BackupAppConfigs
pause
goto :eof

:scanner_gui
echo.
echo Launching Scanner GUI...
echo.
REM Check for Python
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python not found. Please install Python 3.x first.
    echo Download from: https://www.python.org/downloads/
    pause
    goto :eof
)
python "%~dp0src\gui\scanner_gui.py"
pause
goto :eof

:restore
echo.
echo Launching Restore Tool...
echo.
python --version >nul 2>&1
if %errorlevel% neq 0 (
    echo Python not found. Installing via winget...
    winget install Python.Python.3.12 --accept-source-agreements --accept-package-agreements
    echo Please restart this script after Python installation.
    pause
    goto :eof
)
python "%~dp0src\gui\restore_gui.py"
pause
goto :eof

:quick_install
echo.
set /p pkgpath="Enter path to migration package folder: "
echo.
echo Installing via Winget...
powershell -ExecutionPolicy Bypass -File "%pkgpath%\install_winget.ps1"
echo.
echo Installing via Chocolatey...
powershell -ExecutionPolicy Bypass -File "%pkgpath%\install_chocolatey.ps1"
echo.
echo Installation complete!
pause
goto :eof
