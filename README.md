# Redmine Installer for Windows

This PowerShell script automates the installation and configuration of Redmine 6.1.0 on a Windows environment. It handles the download, installation of all required dependencies, database setup, and registers Redmine as a Windows service for automatic startup.

## Overview

The script performs the following actions:
- Checks for Administrator privileges.
- Installs [Chocolatey](https://chocolatey.org/) package manager if it's not already present.
- Installs all necessary software components (Ruby, MariaDB, etc.) using Chocolatey.
- Downloads and extracts the official Redmine 6.1.0 release.
- Automatically creates and configures the MariaDB database and user.
- Configures Redmine (`database.yml`, `Gemfile.local`).
- Installs required Ruby gems using Bundler.
- Initializes the Redmine database.
- Registers Redmine (running on the Puma server) as a Windows service using [NSSM](https://nssm.cc/) (the Non-Sucking Service Manager).
- Prompts to start the service upon completion.

## Target Version

- **Redmine:** 6.1.0

## Installed Software

This script uses Chocolatey to install the following required software:

- **Chocolatey:** The package manager for Windows.
- **Ruby:** v3.4.X.
- **MariaDB (mysql):** The database server for Redmine.
- **ImageMagick:** For image manipulation features in Redmine.
- **MSYS2:** A software distribution and building platform for Windows, required by some Ruby gems.
- **NSSM (Non-Sucking Service Manager):** A utility to run applications as a Windows service.

Additionally, the following Ruby gem is installed to run Redmine:
- **Puma:** A fast, concurrent web server for Ruby applications.

## Prerequisites

- **Operating System:** Windows 10, Windows 11, Windows Server 2016 or later.
- **Permissions:** You must run this script with **Administrator privileges**.
- **Internet Connection:** Required to download Redmine and all software packages.

## How to Use

1.  **Download the Script:**
    Save the PowerShell script as `install-redmine.ps1`.

2.  **Open PowerShell as Administrator:**
    -   Right-click the Start button.
    -   Select "Windows PowerShell (Admin)" or "Terminal (Admin)".

3.  **Allow Script Execution:**
    You may need to change the execution policy for the current session to run the script.
    ```powershell
    Set-ExecutionPolicy -ExecutionPolicy Bypass -Scope Process
    ```

4.  **Run the Script:**
    Navigate to the directory where you saved the script and execute it.
    ```powershell
    .\install-redmine.ps1
    ```

5.  **Follow the Prompts:**
    The script will display its progress. At the end, it will ask if you want to start the Redmine service immediately.

## Configuration

You can customize the installation by editing the variables at the top of the `install-redmine.ps1` script before running it.

```powershell
# ==============================================================================
# Target: Redmine 6.1.0 (Official Release)
# ==============================================================================

#  Set installation paths 
$InstallBaseDir = "C:\Redmine" # Main directory for Redmine and tools

# --- Environment Configuration ---
$PumaPort = 8080               # Port number for the Redmine web server
$ServiceName = "RedminePuma"   # Name for the Windows service
$MariaDbRootPassword = ""      # IMPORTANT: If your MariaDB root user has a password, set it here.
# ------------------------------------------------
```

- `$InstallBaseDir`: The base directory where Redmine and its tools (Ruby, MariaDB, etc.) will be installed.
- `$PumaPort`: The port that Redmine will be accessible on (e.g., `http://localhost:8080`).
- `$ServiceName`: The name that will be used for the Windows service.
- `$MariaDbRootPassword`: If you have previously installed MariaDB/MySQL and set a password for the `root` user, you **must** enter it here.

## Post-Installation

Once the installation is complete, you can access your new Redmine instance.

- **URL:** `http://localhost:8080` (or the port you configured in `$PumaPort`).
- **Default Login:**
  - **Username:** `admin`
  - **Password:** `admin`

> **Security Warning:** It is highly recommended that you change the administrator password immediately after your first login.

### Managing the Redmine Service

You can manage the Redmine service from a PowerShell (Admin) terminal using the service name you configured (`$ServiceName`).

- **Start the service:**
  ```powershell
  Start-Service RedminePuma
  ```

- **Stop the service:**
  ```powershell
  Stop-Service RedminePuma
  ```

- **Check the service status:**
  ```powershell
  Get-Service RedminePuma
  ```

- **Restart the service:**
  ```powershell
  Restart-Service RedminePuma
  ```

The service is configured to start automatically when Windows boots up.

## Disclaimer

This script is provided as-is. Use it at your own risk. Always test in a non-production environment before deploying to a live server. Ensure that your firewall rules allow access to the specified port if you intend to access Redmine from other machines.