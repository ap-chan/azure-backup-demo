# configure-windows-vm.ps1
# Converted from DSC configuration - performs basic Windows VM setup
# This script replaces the DSC extension with a standard PowerShell script

param(
    [string]$SystemTimeZone = "Eastern Standard Time",
    [int]$RetryCount = 20,
    [int]$RetryIntervalSec = 30
)

$ErrorActionPreference = "Stop"

# Set up logging
$logFile = "$env:SystemDrive\Temp\configure-windows-vm.log"
$logDir = Split-Path -Path $logFile -Parent
if (-not (Test-Path $logDir)) {
    New-Item -ItemType Directory -Path $logDir -Force | Out-Null
}

function Write-Log {
    param([string]$Message)
    $timestamp = Get-Date -Format "yyyy-MM-dd HH:mm:ss"
    $logEntry = "[$timestamp] $Message"
    Add-Content -Path $logFile -Value $logEntry
}

Write-Log "Starting Windows VM configuration..."

# Detect Windows Server version
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$osBuildNumber = [int]$osInfo.BuildNumber
$osCaption = $osInfo.Caption
Write-Log "Detected OS: $osCaption (Build: $osBuildNumber)"

# Windows Server 2025 is build 26100+
$isServer2025OrNewer = $osBuildNumber -ge 26100

# Set Timezone
Write-Log "Setting timezone to $SystemTimeZone..."
Set-TimeZone -Id $SystemTimeZone

# Disable IE Enhanced Security Configuration (only for Server 2022 and earlier)
# Windows Server 2025 does not include Internet Explorer
if ($isServer2025OrNewer) {
    Write-Log "Windows Server 2025 or newer detected - skipping IE Enhanced Security Configuration (IE not included)."
} else {
    Write-Log "Disabling IE Enhanced Security for Administrators..."
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    if (Test-Path $AdminKey) {
        Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
        Write-Log "IE ESC disabled for Administrators."
    } else {
        Write-Log "IE ESC registry key for Administrators not found - skipping."
    }

    Write-Log "Disabling IE Enhanced Security for Users..."
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    if (Test-Path $UserKey) {
        Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
        Write-Log "IE ESC disabled for Users."
    } else {
        Write-Log "IE ESC registry key for Users not found - skipping."
    }
}

# Wait for and initialize data disk (Disk 1)
Write-Log "Waiting for data disk (Disk 1) to be available..."
$diskReady = $false
$attempt = 0

while (-not $diskReady -and $attempt -lt $RetryCount) {
    $attempt++
    $disk = Get-Disk -Number 1 -ErrorAction SilentlyContinue
    
    if ($disk) {
        Write-Log "Disk 1 found. Status: $($disk.OperationalStatus), Partition Style: $($disk.PartitionStyle)"
        $diskReady = $true
    } else {
        Write-Log "Attempt $attempt of $RetryCount - Disk 1 not found. Waiting $RetryIntervalSec seconds..."
        Start-Sleep -Seconds $RetryIntervalSec
    }
}

if (-not $diskReady) {
    Write-Log "ERROR: Disk 1 did not become available after $RetryCount attempts."
    throw "Disk 1 did not become available after $RetryCount attempts."
}

# Initialize and format the data disk if it's RAW
$disk = Get-Disk -Number 1
if ($disk.PartitionStyle -eq 'RAW') {
    Write-Log "Initializing Disk 1..."
    Initialize-Disk -Number 1 -PartitionStyle GPT -Confirm:$false
    
    Write-Log "Creating partition on Disk 1..."
    $partition = New-Partition -DiskNumber 1 -UseMaximumSize -DriveLetter F
    
    Write-Log "Formatting partition as NTFS with drive letter F:..."
    Format-Volume -DriveLetter F -FileSystem NTFS -NewFileSystemLabel "Data" -Confirm:$false
    
    Write-Log "Data disk configured successfully as F: drive."
} else {
    Write-Log "Disk 1 is already initialized. Checking for existing F: drive..."
    $existingVolume = Get-Volume -DriveLetter F -ErrorAction SilentlyContinue
    if ($existingVolume) {
        Write-Log "F: drive already exists."
    } else {
        Write-Log "Disk 1 initialized but F: drive not found. Manual intervention may be required."
    }
}

Write-Log "Windows VM configuration completed successfully."
