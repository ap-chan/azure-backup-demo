# Setup logging
$logFile = "$env:SystemDrive\Temp\prepare-windows-vm.log"
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

# Create directory to store installation files
New-Item -ItemType directory -Path "$env:SystemDrive\MachinePrep\files" -Force | Out-Null

#region OS Configuration (formerly DSC tasks)
# Detect Windows Server version
$osInfo = Get-CimInstance -ClassName Win32_OperatingSystem
$osBuildNumber = [int]$osInfo.BuildNumber
$osCaption = $osInfo.Caption
Write-Log "Detected OS: $osCaption (Build: $osBuildNumber)"

# Windows Server 2025 is build 26100+
$isServer2025OrNewer = $osBuildNumber -ge 26100

# Set Timezone
Write-Log "Setting timezone to Eastern Standard Time..."
Set-TimeZone -Id "Eastern Standard Time"

# Disable IE Enhanced Security Configuration (only for Server 2022 and earlier)
# Windows Server 2025 does not include Internet Explorer
if ($isServer2025OrNewer) {
    Write-Log "Windows Server 2025 or newer detected - skipping IE Enhanced Security Configuration (IE not included)."
} else {
    Write-Log "Disabling IE Enhanced Security for Administrators..."
    $AdminKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A7-37EF-4b3f-8CFC-4F3A74704073}"
    if (Test-Path $AdminKey) {
        Set-ItemProperty -Path $AdminKey -Name "IsInstalled" -Value 0
    }

    Write-Log "Disabling IE Enhanced Security for Users..."
    $UserKey = "HKLM:\SOFTWARE\Microsoft\Active Setup\Installed Components\{A509B1A8-37EF-4b3f-8CFC-4F3A74704073}"
    if (Test-Path $UserKey) {
        Set-ItemProperty -Path $UserKey -Name "IsInstalled" -Value 0
    }
}

# Wait for and initialize data disk (Disk 1)
Write-Log "Waiting for data disk (Disk 1) to be available..."
$diskReady = $false
$attempt = 0
$RetryCount = 20
$RetryIntervalSec = 30

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
    New-Partition -DiskNumber 1 -UseMaximumSize -DriveLetter F | Out-Null
    
    Write-Log "Formatting partition as NTFS with drive letter F:..."
    Format-Volume -DriveLetter F -FileSystem NTFS -NewFileSystemLabel "Data" -Confirm:$false | Out-Null
    
    Write-Log "Data disk configured successfully as F: drive."
} else {
    Write-Log "Disk 1 is already initialized."
}
#endregion

try {
    # Install RSAT Tools
    Write-Log "Installing RSAT Tools..."
    Install-WindowsFeature -IncludeAllSubFeature RSAT
}
catch {
    Write-Log "Unable to install RSAT Tools: $_"
}

try {
    # Install nuget package manager
    Write-Log "Installing nuget..."
    Install-PackageProvider -Name Nuget -Force 

    # Install Azure CLI
    Write-Log "Downloading Azure CLI..."
    $cliUri = "https://aka.ms/installazurecliwindows"
    Invoke-WebRequest -Uri $cliUri -OutFile .\AzureCLI.msi; Start-Process msiexec.exe -Wait -ArgumentList '/I AzureCLI.msi /quiet'; rm .\AzureCLI.msi

    # Install Azure PowerShell
    Write-Log "Installing Azure PowerShell..."
    Install-Module -Name Az -Scope CurrentUser -Repository PSGallery -Force
}
catch {
    Write-Log "Unable to install Azure CLI/PowerShell: $_"
}

try {
    # Create test files
    Write-Log "Creating test files..."
    New-Item 'F:\sample-files' -ItemType directory
    "This is sample file 1" | Out-File F:\sample-files\samplefile1.txt
    "This is sample file 2" | Out-File F:\sample-files\samplefile2.txt
    "This is sample file 3 and its original content" | Out-File F:\sample-files\samplefile3.txt
    Write-Log "Test files created successfully."
}   
catch {
    Write-Log "Unable to create test files: $_"
}

try {
    # Download MARS agent
    Write-Log "Downloading MARS agent..."
    $marsUri = "https://aka.ms/azurebackup_agent"
    $marsDest = "$env:SystemDrive\MachinePrep\files\mars-agent.exe"
    Invoke-WebRequest -Uri $marsUri -OutFile $marsDest

    # Install MARS agent
    Write-Log "Installing MARS agent..."
    Start-Process $marsDest -ArgumentList '/q'
    Write-Log "MARS agent installation started."
}
catch {
    Write-Log "Unable to install MARS agent: $_"
}

Write-Log "Script completed." 
