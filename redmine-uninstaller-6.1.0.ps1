# ==============================================================================
# Redmine Complete Uninstallation Script
# ==============================================================================

# --- Environment Settings ---
# Adjust these values to match those set in the installation script.
$InstallBaseDir = "C:\Redmine"
$RedmineServiceName = "RedminePuma" # Redmine service name
$DbServiceName = "MySQL"            # Database (MariaDB) service name
$DbName = "redmine"
$DbUser = "redmine_user"

# !!IMPORTANT!! Enter the root user password for MariaDB(MySQL).
# If you haven't set one, leave it empty ( $MariaDbRootPassword = "" )
$MariaDbRootPassword = ""
# ------------------------------------------------

# --- Script Body ---

# Check if the script is running with administrator privileges
$currentUser = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: This script must be run with administrator privileges." -ForegroundColor Red
    Write-Host "Please right-click the PowerShell script and select 'Run as administrator'." -ForegroundColor Yellow
    Read-Host "Press Enter to exit..."
    exit
}

# Function to display section headers
function Write-SectionHeader {
    param($Message)
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
}

# Function to uninstall a Chocolatey package
function Uninstall-ChocoPackage {
    param($PackageName)
    Write-Host "Uninstalling [$($PackageName)]..." -ForegroundColor Yellow
    
    # Check if the package is installed
    $installed = choco list --local-only -r | Where-Object { $_ -like "*${PackageName}*" }
    if ($installed) {
        & choco uninstall $PackageName -y --remove-dependencies
        if ($LASTEXITCODE -ne 0) {
            Write-Host "Failed to uninstall [$($PackageName)]." -ForegroundColor Red
        } else {
            Write-Host "Uninstallation of [$($PackageName)] completed." -ForegroundColor Green
        }
    } else {
        Write-Host "[$($PackageName)] is not installed. Skipping." -ForegroundColor Gray
    }
}


Write-Host "Starting the complete uninstallation of Redmine." -ForegroundColor Yellow
Write-Host "This process is irreversible. Are you sure you want to continue?"
$confirmation = Read-Host "To continue with the uninstallation, please type 'yes':"

if ($confirmation -ne 'yes') {
    Write-Host "Uninstallation has been canceled." -ForegroundColor Green
    exit
}

# --- 1. Stop and Remove Redmine Service ---
Write-SectionHeader "Step 1: Stop and Remove Redmine Windows Service"
$service = Get-Service -Name $RedmineServiceName -ErrorAction SilentlyContinue
if ($service) {
    Write-Host "Stopping service '$($RedmineServiceName)'..." -ForegroundColor Yellow
    Stop-Service -Name $RedmineServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 3

    Write-Host "Removing service '$($RedmineServiceName)'..." -ForegroundColor Yellow
    & nssm remove $RedmineServiceName confirm
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to remove the service using NSSM. Continuing..." -ForegroundColor Red
    } else {
        Write-Host "Service removal completed." -ForegroundColor Green
    }
} else {
    Write-Host "Service '$($RedmineServiceName)' not found. Skipping." -ForegroundColor Gray
}

# --- 2. Database Cleanup ---
Write-SectionHeader "Step 2: Remove Redmine Database and Stop MySQL Service"

# If the MariaDB root password is not set, ask the user
if ([string]::IsNullOrEmpty($MariaDbRootPassword)) {
    $MariaDbRootPassword = Read-Host -Prompt "Please enter the MariaDB(MySQL) root password (if you haven't set one, just press Enter)"
}

Write-Host "Removing Redmine database ($DbName) and user ($DbUser)..." -ForegroundColor Yellow
$SqlCommands = @"
DROP DATABASE IF EXISTS $DbName;
DROP USER IF EXISTS '$DbUser'@'localhost';
FLUSH PRIVILEGES;
"@

try {
    # Find the path to mysql.exe
    $mysqlPath = Get-Command mysql.exe -ErrorAction SilentlyContinue
    if (-not $mysqlPath) {
        throw "mysql.exe not found. MariaDB might not be installed correctly."
    }

    # Check if the service is running, and if not, try to start it (for database deletion)
    if ((Get-Service -Name $DbServiceName -ErrorAction SilentlyContinue).Status -ne 'Running') {
         Write-Host "Temporarily starting service '$($DbServiceName)' to delete the database..." -ForegroundColor Yellow
         Start-Service -Name $DbServiceName -ErrorAction SilentlyContinue
         Start-Sleep -Seconds 5
    }

    $mysqlArgs = @("-u", "root")
    if (-not [string]::IsNullOrEmpty($MariaDbRootPassword)) {
        # Append the password directly after -p (no space)
        $mysqlArgs += "-p$($MariaDbRootPassword)"
    }
    
    $SqlCommands | & mysql @mysqlArgs

    if ($LASTEXITCODE -ne 0) { throw "Failed to execute mysql command. The password might be incorrect." }
    Write-Host "Database cleanup completed." -ForegroundColor Green

} catch {
    Write-Host "Database cleanup failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "You may need to manually delete the database '$($DbName)' and the user '$($DbUser)'." -ForegroundColor Yellow
    # Proceed to the service stop process even if an error occurs
}

# Stop the MySQL service
Write-Host "Stopping service '$($DbServiceName)'..." -ForegroundColor Yellow
try {
    Stop-Service -Name $DbServiceName -Force -ErrorAction Stop
    Start-Sleep -Seconds 3
    Write-Host "Service '$($DbServiceName)' stopped." -ForegroundColor Green
} catch {
    Write-Host "Failed to stop service '$($DbServiceName)': $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "Continuing may cause the package uninstallation to fail." -ForegroundColor Yellow
}


# --- 3. Uninstall Chocolatey Packages ---
Write-SectionHeader "Step 3: Uninstall Related Components"

# Uninstall the packages installed by the installation script in reverse order
Uninstall-ChocoPackage "nssm"
Uninstall-ChocoPackage "msys2"
Uninstall-ChocoPackage "imagemagick.app"
# Uninstall after stopping the service
Uninstall-ChocoPackage "mysql" 
Uninstall-ChocoPackage "ruby"


# --- 4. Remove Redmine Installation Directory ---
Write-SectionHeader "Step 4: Remove Redmine Installation Directory"
if (Test-Path $InstallBaseDir) {
    Write-Host "Completely removing directory '$($InstallBaseDir)'..." -ForegroundColor Yellow
    try {
        # Wait a moment in case a process is locking the files
        Start-Sleep -Seconds 2
        Remove-Item -Path $InstallBaseDir -Recurse -Force -ErrorAction Stop
        Write-Host "Directory removal completed." -ForegroundColor Green
    } catch {
        Write-Host "Failed to remove directory '$($InstallBaseDir)'." -ForegroundColor Red
        Write-Host "It's possible that processes like MySQL have not terminated yet." -ForegroundColor Yellow
        Write-Host "Please restart your PC and then manually delete '$($InstallBaseDir)'." -ForegroundColor White
        Write-Host "Error details: $($_.Exception.Message)"
    }
} else {
    Write-Host "Directory '$($InstallBaseDir)' not found. Skipping." -ForegroundColor Gray
}

Write-SectionHeader " Redmine uninstallation has been completed "
Read-Host "Press Enter to exit..."