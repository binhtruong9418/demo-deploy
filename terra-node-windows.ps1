# Strato Node Setup Script for Windows
# Usage: 
#   PowerShell -ExecutionPolicy Bypass -File terra-node-windows.ps1 -ClientId "your_id" -ClientPassword "your_password"
# Or one-liner:
#   iwr -useb https://raw.githubusercontent.com/binhtruong9418/demo-deploy/main/terra-node-windows.ps1 | iex

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
    Write-Error "This script requires Administrator privileges. Please run as Administrator."
    exit 1
}

# Enhanced logging functions
function Write-Log {
    param([string]$Message)
    Write-Host "[$(Get-Date -Format 'HH:mm:ss')] $Message" -ForegroundColor Green
}

function Write-ErrorLog {
    param([string]$Message)
    Write-Host "[ERROR] $Message" -ForegroundColor Red
    exit 1
}

# Validate required parameters
if ([string]::IsNullOrWhiteSpace($ClientId)) {
    Write-ErrorLog "Client ID is required. Usage: .\terra-node-windows.ps1 -ClientId 'your_id' -ClientPassword 'your_password'"
}

if ([string]::IsNullOrWhiteSpace($ClientPassword)) {
    Write-ErrorLog "Client password is required. Usage: .\terra-node-windows.ps1 -ClientId 'your_id' -ClientPassword 'your_password'"
}

# Get public IP
try {
    $PublicIP = (Invoke-WebRequest -Uri "https://icanhazip.com" -UseBasicParsing -TimeoutSec 5).Content.Trim()
    $ClientWithIP = "${ClientId}_${PublicIP}"
    Write-Log "Detected public IP: $PublicIP"
} catch {
    $ClientWithIP = $ClientId
    Write-Log "Could not detect public IP, using original Client ID"
}

Write-Log "Installing Strato Node (ID: $ClientWithIP)"

# Create setup directory
$SetupDir = "C:\Program Files\TerraNode"
Write-Log "Creating setup directory: $SetupDir"

if (-not (Test-Path $SetupDir)) {
    New-Item -ItemType Directory -Path $SetupDir -Force | Out-Null
}

# Download node binary
$AgentPath = Join-Path $SetupDir "terra-agent.exe"
Write-Log "Downloading strato-agent from: $DownloadUrl"

try {
    Invoke-WebRequest -Uri $DownloadUrl -OutFile $AgentPath -UseBasicParsing
    Write-Log "Download completed successfully"
} catch {
    Write-ErrorLog "Failed to download terra-agent from: $DownloadUrl. Error: $_"
}

# Create config file
$ConfigPath = Join-Path $SetupDir "config.toml"
Write-Log "Creating configuration file: $ConfigPath"

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

# Create service using New-Service
Write-Log "Creating new service..."
$ServiceParams = @{
    Name = $ServiceName
    BinaryPathName = "`"$AgentPath`" --config `"$ConfigPath`""
    DisplayName = "Terra Node Service"
    Description = "Terra distributed key-value store node"
    StartupType = "Automatic"
}

New-Service @ServiceParams | Out-Null

# Configure service recovery options
sc.exe failure $ServiceName reset= 86400 actions= restart/5000/restart/5000/restart/5000 | Out-Null

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
Write-Host "  Client ID: $ClientId" -ForegroundColor White
Write-Host "  Client ID with IP: $ClientWithIP" -ForegroundColor White
Write-Host "  Setup Directory: $SetupDir" -ForegroundColor White
Write-Host "  Service Status: $ServiceStatus" -ForegroundColor White
Write-Host ""
Write-Host "Service Management Commands:" -ForegroundColor Cyan
Write-Host "  Check status: Get-Service -Name TerraNode" -ForegroundColor Yellow
Write-Host "  View logs: Get-EventLog -LogName Application -Source TerraNode -Newest 50" -ForegroundColor Yellow
Write-Host "  Stop service: Stop-Service -Name TerraNode" -ForegroundColor Yellow
Write-Host "  Start service: Start-Service -Name TerraNode" -ForegroundColor Yellow
Write-Host "  Restart service: Restart-Service -Name TerraNode" -ForegroundColor Yellow
Write-Host ""
Write-Host "Configuration file: $ConfigPath" -ForegroundColor Cyan
Write-Host "Executable: $AgentPath" -ForegroundColor Cyan
