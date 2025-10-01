# Strato Node Setup Script for Windows
# Usage: 
#   PowerShell -ExecutionPolicy Bypass -File strato-node-windows.ps1 -ClientId "your_id" -ClientPassword "your_password"
# Or one-liner:
#   iwr -useb https://raw.githubusercontent.com/binhtruong9418/demo-deploy/main/strato-node-windows.ps1 | iex

param(
    [Parameter(Mandatory=$false)]
    [string]$ClientId = $env:CLIENT_ID,
    
    [Parameter(Mandatory=$false)]
    [string]$ClientPassword = $env:CLIENT_PASSWORD,
    
    [Parameter(Mandatory=$false)]
    [string]$DownloadUrl = "https://github.com/binhtruong9418/merkle-node/releases/latest/download/agent-node-windows.exe"
)

# Require Administrator privileges
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host ""
    Write-Host "========================================" -ForegroundColor Red
    Write-Host "  ADMINISTRATOR PRIVILEGES REQUIRED" -ForegroundColor Red
    Write-Host "========================================" -ForegroundColor Red
    Write-Host ""
    Write-Host "Please run PowerShell as Administrator:" -ForegroundColor Yellow
    Write-Host "  1. Right-click PowerShell" -ForegroundColor Cyan
    Write-Host "  2. Select 'Run as Administrator'" -ForegroundColor Cyan
    Write-Host ""
    Write-Host "Then run the command again." -ForegroundColor Yellow
    Write-Host ""
    Start-Sleep -Seconds 3
}

Write-Host ""
Write-Host "========================================" -ForegroundColor Cyan
Write-Host "   TERRA NODE INSTALLER" -ForegroundColor Cyan
Write-Host "========================================" -ForegroundColor Cyan
Write-Host ""

# Enhanced logging functions
function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Green
    [Console]::Out.Flush()
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    [Console]::Out.Flush()
    exit 1
}

# Validate required parameters - prompt if missing
if ([string]::IsNullOrWhiteSpace($ClientId)) {
    Write-Host "Client ID not provided." -ForegroundColor Yellow
    $ClientId = Read-Host "Please enter your Client ID"
    if ([string]::IsNullOrWhiteSpace($ClientId)) {
        Write-ErrorLog "Client ID is required. Usage: .\terra-node-windows.ps1 -ClientId 'your_id' -ClientPassword 'your_password'"
    }
}

if ([string]::IsNullOrWhiteSpace($ClientPassword)) {
    Write-Host "Client Password not provided." -ForegroundColor Yellow
    $SecurePassword = Read-Host "Please enter your Client Password" -AsSecureString
    $BSTR = [System.Runtime.InteropServices.Marshal]::SecureStringToBSTR($SecurePassword)
    $ClientPassword = [System.Runtime.InteropServices.Marshal]::PtrToStringAuto($BSTR)
    [System.Runtime.InteropServices.Marshal]::ZeroFreeBSTR($BSTR)
    if ([string]::IsNullOrWhiteSpace($ClientPassword)) {
        Write-ErrorLog "Client password is required. Usage: .\terra-node-windows.ps1 -ClientId 'your_id' -ClientPassword 'your_password'"
    }
}

# Get public IP
try {
    $PublicIP = (Invoke-WebRequest -Uri "https://icanhazip.com" -UseBasicParsing -TimeoutSec 5).Content.Trim()
    $ClientWithIP = "${ClientId}_${PublicIP}"
} catch {
    $ClientWithIP = $ClientId
}

Write-Log "Installing Terra Node (ID: $ClientWithIP)"

# Create setup directory
$SetupDir = "C:\ProgramData\TerraNode"
Write-Log "Creating setup directory: $SetupDir"

if (-not (Test-Path $SetupDir)) {
    New-Item -ItemType Directory -Path $SetupDir -Force | Out-Null
}

# Download node binary
$AgentPath = Join-Path $SetupDir "terra-agent.exe"
Write-Log "Downloading terra-agent ...."

# Configure TLS and security protocols
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12 -bor [Net.SecurityProtocolType]::Tls13

try {
    # Try with different methods
    Write-Log "Attempting download method 1 (Invoke-WebRequest)..."
    $ProgressPreference = 'SilentlyContinue'  # Speed up download
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $AgentPath -UseBasicParsing -TimeoutSec 300
    Write-Log "Download completed successfully"
} catch {
    Write-Log "Method 1 failed, trying method 2 (WebClient)..."
    try {
        $WebClient = New-Object System.Net.WebClient
        $WebClient.DownloadFile($DownloadUrl, $AgentPath)
        Write-Log "Download completed successfully using WebClient"
    } catch {
        Write-Log "Method 2 failed, trying method 3 (BITS)..."
        try {
            Import-Module BitsTransfer
            Start-BitsTransfer -Source $DownloadUrl -Destination $AgentPath
            Write-Log "Download completed successfully using BITS"
        } catch {
            Write-ErrorLog "All download methods failed. URL: $DownloadUrl. Last Error: $_. Please check: 1) File exists at URL 2) Internet connection 3) Firewall/Proxy settings"
        }
    }
}

# Create config file
$ConfigPath = Join-Path $SetupDir "config.toml"

$ConfigContent = @"
host = "127.0.0.1"
port = 8379
storage_path = "terra_data"
engine = "rwlock"
sync_interval_seconds = 30

[replication]
enabled = true
mqtt_broker = "emqx.decenter.ai"
mqtt_port = 1883
topic_prefix = "terra_kv"
client_id = "$ClientWithIP"
client_password = "$ClientPassword"
"@

Set-Content -Path $ConfigPath -Value $ConfigContent -Encoding UTF8

# Create NSSM service (Windows Service Wrapper)
Write-Log "Setting up Windows Service..."

# Check if service already exists
$ServiceName = "TerraNode"
$ExistingService = Get-Service -Name $ServiceName -ErrorAction SilentlyContinue

if ($ExistingService) {
    Write-Log "Stopping existing service..."
    Stop-Service -Name $ServiceName -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    
    Write-Log "Removing existing service..."
    sc.exe delete $ServiceName | Out-Null
    Start-Sleep -Seconds 2
}

# Download and setup NSSM (Non-Sucking Service Manager) for better service management
Write-Log "Downloading NSSM (Service Manager)..."
$NssmZip = Join-Path $env:TEMP "nssm.zip"
$NssmDir = Join-Path $SetupDir "nssm"

try {
    Invoke-WebRequest -Uri "https://nssm.cc/release/nssm-2.24.zip" -OutFile $NssmZip -UseBasicParsing
    Expand-Archive -Path $NssmZip -DestinationPath $env:TEMP -Force
    
    # Copy appropriate NSSM version (64-bit or 32-bit)
    if ([Environment]::Is64BitOperatingSystem) {
        $NssmExe = Join-Path $SetupDir "nssm.exe"
        Copy-Item "$env:TEMP\nssm-2.24\win64\nssm.exe" -Destination $NssmExe -Force
    } else {
        $NssmExe = Join-Path $SetupDir "nssm.exe"
        Copy-Item "$env:TEMP\nssm-2.24\win32\nssm.exe" -Destination $NssmExe -Force
    }
    
    Write-Log "NSSM installed successfully"
} catch {
    Write-Log "NSSM download failed, using built-in service creation"
    $NssmExe = $null
}

# Create service
Write-Log "Creating Windows service..."

if ($NssmExe -and (Test-Path $NssmExe)) {
    # Use NSSM for better service management
    Write-Log "Using NSSM for service creation..."

    
    & $NssmExe install $ServiceName "`"$AgentPath`"" --config "`"$ConfigPath`"" 2>&1 | Out-Null
    & $NssmExe set $ServiceName DisplayName "Terra Node Service" 2>&1 | Out-Null
    & $NssmExe set $ServiceName Description "Terra distributed key-value store node running in background" 2>&1 | Out-Null
    & $NssmExe set $ServiceName Start SERVICE_AUTO_START 2>&1 | Out-Null
    & $NssmExe set $ServiceName AppDirectory "`"$SetupDir`"" 2>&1 | Out-Null
    & $NssmExe set $ServiceName AppStdout "`"$SetupDir\service.log`"" 2>&1 | Out-Null
    & $NssmExe set $ServiceName AppStderr "`"$SetupDir\service-error.log`"" 2>&1 | Out-Null
    & $NssmExe set $ServiceName AppRotateFiles 1 2>&1 | Out-Null
    & $NssmExe set $ServiceName AppRotateBytes 1048576 2>&1 | Out-Null
    
    Write-Log "Service created with NSSM"
} else {
    # Fallback to built-in service creation
    Write-Log "Using built-in service creation..."
    
    $ServiceParams = @{
        Name = $ServiceName
        BinaryPathName = "`"$AgentPath`" --config `"$ConfigPath`""
        DisplayName = "Terra Node Service"
        Description = "Terra distributed key-value store node running in background"
        StartupType = "Automatic"
    }
    
    New-Service @ServiceParams | Out-Null
}

# Configure service recovery options
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null

# Set service to run in background (no console window)
sc.exe config $ServiceName type= own | Out-Null

# Start the service
Write-Log "Starting Terra Node service..."
try {
    Start-Service -Name $ServiceName
    Start-Sleep -Seconds 3
    
    $Service = Get-Service -Name $ServiceName
    if ($Service.Status -eq "Running") {
        Write-Log "Terra Node service started successfully"
        $ServiceStatus = "Running"
    } else {
        Write-Log "Warning: Service status is $($Service.Status)"
        $ServiceStatus = $Service.Status
    }
} catch {
    Write-Log "Warning: Failed to start service. Error: $_"
    $ServiceStatus = "Failed"
}

# Create firewall rule for port 8379 (optional)
Write-Log "Configuring firewall..."
try {
    $FirewallRule = Get-NetFirewallRule -DisplayName "Terra Node" -ErrorAction SilentlyContinue
    if (-not $FirewallRule) {
        New-NetFirewallRule -DisplayName "Terra Node" -Direction Inbound -Protocol TCP -LocalPort 8379 -Action Allow | Out-Null
        Write-Log "Firewall rule created for port 8379"
    }
} catch {
    Write-Log "Warning: Could not create firewall rule. You may need to configure it manually."
}

# Display installation summary
Write-Log "Installation completed!"
Write-Host ""
Write-Host "Terra Node Details:" -ForegroundColor Cyan
Write-Host "  Client ID: $ClientWithIP" -ForegroundColor White
Write-Host "  Setup Directory: $SetupDir" -ForegroundColor White
Write-Host "  Service Status: $ServiceStatus" -ForegroundColor White
Write-Host "  Service Type: Background (No Console Window)" -ForegroundColor White
Write-Host ""
Write-Host "Service Management Commands:" -ForegroundColor Cyan
Write-Host "  Check status: Get-Service -Name TerraNode" -ForegroundColor Yellow
Write-Host "  Stop service: Stop-Service -Name TerraNode" -ForegroundColor Yellow
Write-Host "  Start service: Start-Service -Name TerraNode" -ForegroundColor Yellow
Write-Host "  Restart service: Restart-Service -Name TerraNode" -ForegroundColor Yellow
Write-Host ""
Write-Host "Log Files:" -ForegroundColor Cyan
Write-Host "  Standard output: $SetupDir\service.log" -ForegroundColor Yellow
Write-Host "  Error output: $SetupDir\service-error.log" -ForegroundColor Yellow
Write-Host ""
Write-Host "Configuration file: $ConfigPath" -ForegroundColor Cyan
Write-Host "Executable: $AgentPath" -ForegroundColor Cyan
Write-Host ""
[Console]::Out.Flush()
