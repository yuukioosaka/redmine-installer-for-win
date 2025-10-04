# ==============================================================================
# Target: Redmine 6.1.0 (Official Release)
# ==============================================================================

#  Set installation paths 
$InstallBaseDir = "C:\Redmine"
$RedmineDir = "$($InstallBaseDir)\Redmine"
$ToolsDir = "$($InstallBaseDir)\tools"

#  Check if running with Administrator privileges 
$currentUser = New-Object Security.Principal.WindowsPrincipal ([Security.Principal.WindowsIdentity]::GetCurrent())
if (-not $currentUser.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
    Write-Host "Error: This script must be run with Administrator privileges." -ForegroundColor Red
    Write-Host "Please right-click the PowerShell script and select 'Run as Administrator', then run this script again." -ForegroundColor Yellow
    Read-Host "Press Enter to exit..."
    exit
}

$env:ChocolateyToolsLocation = $ToolsDir
Write-Host "Set the tool installation location to '$($ToolsDir)'." -ForegroundColor Green


# --- Environment Configuration ---
$RedmineVersion = "6.1.0"
$PumaPort = 8080 #  Modification 1: Port number for Puma to use 
$ServiceName = "RedminePuma" #  Modification 2: Windows service name 
$DbName = "redmine"
$DbUser = "redmine_user"
# Generate a random 16-character password
$DbPassword = -join ((65..90) + (97..122) + (48..57) | Get-Random -Count 16 | ForEach-Object { [char]$_ })
$RubyVersion = "3.4.6.1"
$MariaDbRootPassword = "" # Set your MariaDB root password here if you have one
# ------------------------------------------------

# --- Script Body ---

try {
    Set-ExecutionPolicy Bypass -Scope Process -Force -ErrorAction Stop
} catch {
    Write-Host "Failed to change the execution policy." -ForegroundColor Red
    exit
}

function Write-SectionHeader {
    param($Message)
    Write-Host "==============================================================================" -ForegroundColor Cyan
    Write-Host $Message -ForegroundColor Cyan
    Write-Host "==============================================================================" -ForegroundColor Cyan
}

function Install-ChocoPackage {
    param($PackageName, $Version = $null, [switch]$AllowDowngrade = $false)
    Write-Host "Installing [$($PackageName)]..." -ForegroundColor Yellow
    $chocoArgs = @("install", $PackageName, "-y")
    if ($Version) { $chocoArgs += "--version", $Version }
    if ($AllowDowngrade) { $chocoArgs += "--allow-downgrade" }
    & choco $chocoArgs
    if ($LASTEXITCODE -ne 0) {
        Write-Host "Failed to install [$($PackageName)]. Exiting script." -ForegroundColor Red
        exit
    }
    Write-Host "Installation of [$($PackageName)] is complete." -ForegroundColor Green
}

# --- 1. Install Chocolatey ---
Write-SectionHeader "Step 1: Prepare Chocolatey Package Manager"
if (-not (Get-Command choco -ErrorAction SilentlyContinue)) {
    Write-Host "Chocolatey is not installed. Starting installation..." -ForegroundColor Yellow
    Set-ExecutionPolicy Bypass -Scope Process -Force; [System.Net.ServicePointManager]::SecurityProtocol = [System.Net.ServicePointManager]::SecurityProtocol -bor 3072; iex ((New-Object System.Net.WebClient).DownloadString('https://community.chocolatey.org/install.ps1'))
} else {
    Write-Host "Chocolatey is already installed." -ForegroundColor Green
}

# --- 2. Install Required Components ---
Write-SectionHeader "Step 2: Install Required Components (Ruby, MariaDB, etc.)"

Install-ChocoPackage "ruby" -Version $RubyVersion -AllowDowngrade
Install-ChocoPackage "mysql"
Install-ChocoPackage "imagemagick.app"
Install-ChocoPackage "msys2"
Install-ChocoPackage "nssm" #  Modification 2: Install the service management tool (NSSM) 

# Add Ruby to the PATH for the current process and run ridk install
$env:Path = "$($ToolsDir)\Ruby33\bin;" + [System.Environment]::GetEnvironmentVariable("Path","Machine") + ";" + [System.Environment]::GetEnvironmentVariable("Path","User")
Write-Host "Updated environment variables. Running 'ridk install'..."
try {
    # Non-interactive install of MSYS2 and MINGW dev tools
    ridk install 3
} catch {
    Write-Host "Failed to run 'ridk install'. Exiting script." -ForegroundColor Red
    exit
}
Write-Host "'ridk install' completed successfully." -ForegroundColor Green


# --- 3. Download and Extract Redmine ---
Write-SectionHeader "Step 3: Download and Extract Redmine $RedmineVersion (Official Release)"
if (-not (Test-Path $RedmineDir)) {
    New-Item -ItemType Directory -Force -Path $RedmineDir | Out-Null
}

if ((Get-ChildItem -Path $RedmineDir).Count -eq 0) {
    Write-Host "Downloading Redmine v$($RedmineVersion)..." -ForegroundColor Yellow
    $RedmineUrl = "https://www.redmine.org/releases/redmine-$($RedmineVersion).zip"
    $ZipFile = "$($env:TEMP)\redmine.zip"
    Invoke-WebRequest -Uri $RedmineUrl -OutFile $ZipFile

    Write-Host "Extracting Redmine... ($RedmineDir)" -ForegroundColor Yellow
    $tempDir = New-Item -ItemType Directory -Path (Join-Path $env:TEMP ([System.Guid]::NewGuid().ToString()))
    Expand-Archive -Path $ZipFile -DestinationPath $tempDir.FullName -Force
    Move-Item -Path "$($tempDir.FullName)\redmine-$($RedmineVersion)\*" -Destination $RedmineDir
    Remove-Item -Path $tempDir.FullName -Recurse -Force
    Remove-Item -Path $ZipFile -Force
    Write-Host "Redmine extraction complete." -ForegroundColor Green
} else {
    Write-Host "Directory '$RedmineDir' already contains files. Skipping download and extraction." -ForegroundColor Green
}
cd $RedmineDir

# --- 4. Initial Database Setup ---
Write-SectionHeader "Step 4: Automatic Database Initialization"
Write-Host "Starting MariaDB service..." -ForegroundColor Yellow
try {
    # The service may not exist, so ignore errors on Get-Service
    if (Get-Service -Name "MySQL" -ErrorAction SilentlyContinue) {
        Start-Service -Name "MySQL" -ErrorAction Stop
    } else {
        Write-Host "MariaDB(MySQL) service not found. Please check if the Chocolatey installation completed successfully." -ForegroundColor Yellow
    }
} catch {
    Write-Host "Failed to start MariaDB(MySQL) service." -ForegroundColor Red
    exit
}

Write-Host "Automatically creating Redmine database and user..." -ForegroundColor Yellow
$SqlCommands = @"
CREATE DATABASE IF NOT EXISTS $DbName CHARACTER SET utf8mb4;
CREATE USER IF NOT EXISTS '$DbUser'@'localhost';
SET PASSWORD FOR '$DbUser'@'localhost' = '$DbPassword';
GRANT ALL PRIVILEGES ON $DbName.* TO '$DbUser'@'localhost';
FLUSH PRIVILEGES;
"@
try {
    $mysqlArgs = @("-u", "root", "--default-character-set=utf8mb4")
    if (-not [string]::IsNullOrEmpty($MariaDbRootPassword)) {
        $mysqlArgs += "-p$($MariaDbRootPassword)"
    }
    $SqlCommands | & mysql @mysqlArgs
    
    if ($LASTEXITCODE -ne 0) { throw "Failed to execute mysql command." }
    Write-Host "Automatic database setup complete." -ForegroundColor Green
    Write-Host "    - Redmine Database: $DbName"
    Write-Host "    - Redmine User: $DbUser"
    Write-Host "    - Redmine User Password: $DbPassword" -ForegroundColor Green
} catch {
    Write-Host "Automatic database setup failed: $($_.Exception.Message)" -ForegroundColor Red
    Write-Host "[VERIFY] Is the value of `$MariaDbRootPassword` at the beginning of the script correct?" -ForegroundColor Yellow
    exit
}


# --- 5. Redmine Configuration ---
Write-SectionHeader "Step 5: Redmine Configuration"

Write-Host "Creating `config/database.yml`..." -ForegroundColor Yellow
$DbConfig = @"
production:
  adapter: mysql2
  database: $DbName
  host: localhost
  username: $DbUser
  password: "$DbPassword"
  encoding: utf8mb4
"@
Copy-Item "config/database.yml.example" "config/database.yml" -Force
Set-Content -Path "config/database.yml" -Value $DbConfig
Write-Host "Created `config/database.yml`." -ForegroundColor Green

Write-Host "Creating `Gemfile.local` to add puma..." -ForegroundColor Yellow
Set-Content -Path "Gemfile.local" -Value "gem 'puma'"
Write-Host "Created `Gemfile.local`." -ForegroundColor Green

Write-Host "Installing Bundler..." -ForegroundColor Yellow
gem install bundler
Write-Host "Installing required Gems for Redmine... (This may take several minutes)" -ForegroundColor Yellow
bundle config set --local path "vendor/bundle"
bundle install
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to install Gems. Exiting script." -ForegroundColor Red
    exit
}
Write-Host "Gem installation complete." -ForegroundColor Green

Write-Host "Generating secret token..." -ForegroundColor Yellow
bundle exec rake generate_secret_token

Write-Host "Creating database tables..." -ForegroundColor Yellow
$env:RAILS_ENV = "production"
bundle exec rake db:migrate
if ($LASTEXITCODE -ne 0) {
    Write-Host "Database migration failed. Exiting script." -ForegroundColor Red
    exit
}
Write-Host "Database table creation complete." -ForegroundColor Green

Write-Host "Loading default data... (Selecting 'ja' for language)" -ForegroundColor Yellow
$env:REDMINE_LANG='ja' # Sets the language for default data
bundle exec rake redmine:load_default_data
if ($LASTEXITCODE -ne 0) {
    Write-Host "Failed to load default data. Exiting script." -ForegroundColor Red
    exit
}
Write-Host "Default data loaded successfully." -ForegroundColor Green

#  Modification 2: Add Windows service registration process from here 
# --- 6. Register as a Windows Service ---
Write-SectionHeader "Step 6: Register Redmine as a Windows Service"

# If the service already exists, delete and recreate it
if (Get-Service $ServiceName -ErrorAction SilentlyContinue) {
    Write-Host "Stopping and removing existing service '$ServiceName'..." -ForegroundColor Yellow
    & nssm stop $ServiceName
    Start-Sleep -Seconds 2
    & nssm remove $ServiceName confirm
    Start-Sleep -Seconds 2
}

# Create a batch file to start the service
Write-Host "Creating a batch file to start the service..." -ForegroundColor Yellow
$BatchFilePath = Join-Path $InstallBaseDir "start_redmine.bat"
$RubyBinPath = Join-Path $ToolsDir "Ruby33\bin"
$MsysMingwBinPath = Join-Path $ToolsDir "msys64\mingw64\bin"
$MsysUsrBinPath = Join-Path $ToolsDir "msys64\usr\bin"

# Define the content of the batch file
$BatchFileContent = @"
@echo off
setlocal

REM Set environment variables required for Ruby on Rails to run
set "PATH=$RubyBinPath;$MsysMingwBinPath;$MsysUsrBinPath;%PATH%"
set "RAILS_ENV=production"

REM Change to the Redmine directory and start the Puma server
echo Starting Redmine Puma server on port $PumaPort...
cd /d "$RedmineDir"
bundle exec puma -e production -p $PumaPort
"@

Set-Content -Path $BatchFilePath -Value $BatchFileContent -Encoding Ascii
Write-Host "Batch file created: $BatchFilePath" -ForegroundColor Green

# Register the service using nssm
Write-Host "Registering '$ServiceName' as a service using nssm..." -ForegroundColor Yellow
& nssm install $ServiceName "$BatchFilePath"
if ($LASTEXITCODE -ne 0) {
    Write-Host "Service installation failed." -ForegroundColor Red
    exit
}

# Set service details
& nssm set $ServiceName AppDirectory "$RedmineDir"
& nssm set $ServiceName DisplayName "Redmine ($RedmineVersion)"
& nssm set $ServiceName Description "Redmine application server (Puma) for Redmine $RedmineVersion"
& nssm set $ServiceName Start "SERVICE_AUTO_START" # Set to start automatically
& nssm set $ServiceName AppStopMethodSkip 6 # Adjust the stop signal (allows graceful shutdown)
& nssm set $ServiceName AppStopMethodConsole 15000 # Send Ctrl+C for a clean shutdown

Write-Host "Service registration complete." -ForegroundColor Green


# --- Completion ---
Write-SectionHeader " Redmine installation and service registration complete! "
Write-Host ""

# Ask the user if they want to start the service
$startService = Read-Host "Do you want to start the Redmine service now? (Y/N)"
if ($startService -match "^[Yy]$") {
    Write-Host "Starting the Redmine service..." -ForegroundColor Green
    Start-Service $ServiceName
    Start-Sleep -Seconds 3 # Wait for the service to start
    if ((Get-Service $ServiceName).Status -eq 'Running') {
        Write-Host "Service '$ServiceName' started successfully." -ForegroundColor Green
        Write-Host "Please wait a few seconds, then access the URL below in your web browser." -ForegroundColor White
    } else {
        Write-Host "Failed to start the service. Please check the Event Viewer or logs via 'nssm edit $ServiceName'." -ForegroundColor Red
    }
} else {
    Write-Host "The service was not started. To start it manually, run the following command:" -ForegroundColor Yellow
    Write-Host "  Start-Service $ServiceName" -ForegroundColor Cyan
    Write-Host "  Or it will start automatically after a PC restart."
}

Write-Host ""
Write-Host "Redmine Access Information:" -ForegroundColor Green
Write-Host "  URL: http://localhost:$PumaPort" -ForegroundColor Cyan
Write-Host ""
Write-Host "Log in with the initial user/password." -ForegroundColor White
Write-Host "  Username: admin" -ForegroundColor White
Write-Host "  Password: admin" -ForegroundColor White
Write-Host "  Å¶ Be sure to change your password after logging in." -ForegroundColor Yellow
Write-Host ""
Write-Host "Service Management:" -ForegroundColor Green
Write-Host "  Start: Start-Service $ServiceName"
Write-Host "  Stop:  Stop-Service $ServiceName"
Write-Host "  Status: Get-Service $ServiceName"
Write-Host ""