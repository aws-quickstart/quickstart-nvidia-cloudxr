<#PSScriptInfo
.VERSION 1.1
.GUID 99043890-70d0-4691-af9f-8a315ae9deef
.AUTHOR norman.geiersbach@autodesk.com
.COMPANYNAME Autodesk
.COPYRIGHT Autodesk, Inc. All Rights Reserved.
#>

<#
  .DESCRIPTION
  A script that downloads, installs and configures SteamVR, CloudXR and VRED Core on an AWS EC2 Windows instance.

  .PARAMETER S3Bucket
  AWS S3 bucket to download binaries and the VRED scene file from.

  .PARAMETER InstallerPrefix
  AWS S3 bucket key prefix for the binaries and installers, e.g. "PathToBinaries/".

  .PARAMETER SceneKeyOrUrl
  The URL to the VRED scene on a web server or the key on the AWS S3 bucket, e.g. "http://example.com/vred.vpb" or "PathToScene/vred.vpb".

  .PARAMETER LicenseServer
  The address of the Autodesk license server, e.g. "127.0.0.1" or "2080@192.168.188.1".

  .PARAMETER CollaborationServer
  The address of the VRED collaboration server, e.g. "10.128.0.100".

  .PARAMETER AccessKey
  The optional AWS access key for the S3 bucket.

  .PARAMETER SecretKey
  The optional AWS secret key for the S3 bucket.
#>
Param (
  [parameter(mandatory)]
  [string] $S3Bucket,
  [parameter(mandatory)]
  [string] $InstallerPrefix,
  [parameter(mandatory)]
  [string] $SceneKeyOrUrl,
  [parameter(mandatory)]
  [string] $LicenseServer,
  [parameter(mandatory)]
  [string] $CollaborationServer,
  [parameter()]
  [string] $AccessKey,
  [parameter()]
  [string] $SecretKey
)

$dataPath = "C:\Autodesk\VRED"
$steamInstPath = "C:\SteamVR"

Import-Module -Name $PSScriptRoot\vred-library.psm1 -Force

# Improve download performance by disabling the display of progress
$ProgressPreference = 'SilentlyContinue'

# Disable Windows Defender Realtime Protection to speed up the installation
Set-MpPreference -DisableRealtimeMonitoring $true

# Disable Windows updates to prevent a restart of the instance
Start-Process "sc.exe" -ArgumentList "stop wuauserv"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name NoAutoUpdate -Value 1


####################################################################################################
# Download installer binaries
####################################################################################################

# Create tempoary folder
$tempPath = New-TempFolder

# Copy installer from AWS S3 bucket to temporary directory
Write-Output "Copy installer files from AWS S3 bucket '$S3Bucket' to local temp folder '$tempPath'" | Timestamp
if (![string]::IsNullOrWhiteSpace($AccessKey) -or ![string]::IsNullOrWhiteSpace($SecretKey)) {
  # Copy installer files
  Copy-S3Object -BucketName $S3Bucket -KeyPrefix $InstallerPrefix -LocalFolder $tempPath -AccessKey $AccessKey -SecretKey $SecretKey
} else {
  # Copy installer files
  Copy-S3Object -BucketName $S3Bucket -KeyPrefix $InstallerPrefix -LocalFolder $tempPath
}

####################################################################################################
# Install DirectX End-User Runtime Web Installer
#
# DirectX End-User Runtime Web Installer [dxwebsetup.exe] must be added to the S3 bucket folder of media and binaries.
#
# It can be downloaded from:
# https://www.microsoft.com/en-us/download/details.aspx?id=35
####################################################################################################

# Extract DirectX files
$DxExe = Join-Path $tempPath "dxwebsetup.exe"
Start-Process -FilePath $DxExe -ArgumentList "/Q" -Wait

####################################################################################################
# Install VRED Core and set the license server
####################################################################################################

# Find sfx files of VRED Core installer and sort them alphabetically
# Expects Autodesk sfx installer files e.g. Autodesk_VREDCOR_2023_0_0_Enu_Win_64bit_dlm_001_002.sfx.exe
$vredInstArchives = @(Get-Childitem -Path $tempPath -Filter "Autodesk_VREDCOR*.sfx.exe" | ForEach-Object {"$($_.FullName)"} | Sort-Object)
if ($vredInstArchives.count -eq 0) {
  Write-Output "No Autodesk VRED Core Installer archives found." | Timestamp
  exit 1
}

# Extract sfx of VRED Core installer
$vredInstSfx = $vredInstArchives[0]
Write-Output "Extract VRED Core installer '$vredInstSfx'." | Timestamp
Start-Process -FilePath $vredInstSfx -ArgumentList "-suppresslaunch -d C:\Autodesk" -Wait

# Find extraction folder
# Expects Autodesk extracted installer folder e.g. Autodesk_VREDCOR_2023_0_0_Enu_Win_64bit_dlm
$vredInstDirs = @(Get-Childitem -Path "C:\Autodesk" -Filter "Autodesk_VREDCOR*" -Directory | ForEach-Object {"$($_.FullName)"})
if ($vredInstDirs.count -eq 0) {
  Write-Output "No Autodesk VRED Core Installer directories found." | Timestamp
  exit 1
}

# Remove the unnecessary AdSSO package from the installer as a workaround to fix an installation failure that occurs from time to time
try {
  $manifestFile = Join-Path $vredInstDirs[0] "manifest\app.vredcore.xml"
  $packageRegex = '<Package.+?(?=name="AdSSO").+?(?=/>)/>'
  (Get-Content $manifestFile) -replace $packageRegex, '' | Set-Content $manifestFile
} catch {
  Write-Output "Error removing AdSSO package from VRED Core installer." | Timestamp
}

# Start installation of VRED Core
$vredInstPath = Join-Path $vredInstDirs[0] "deploymentInstall.bat"
Write-Output "Run VRED Core installer '$vredInstPath'." | Timestamp
Start-Process -FilePath $vredInstPath -Wait
Write-Output "VRED Core installation completed." | Timestamp

# Change license to new server
Set-AdskLicense $LicenseServer


####################################################################################################
# Download scene and create python script for VRED initialization
####################################################################################################

# Create data folder
[Void](New-Item -Type Directory -Path $dataPath -Force)

# Path to scene file in temp folder
$scenePath = Join-Path $dataPath $SceneKeyOrUrl

# Copy scene file from AWS S3 bucket or web server to temporary directory
if (![string]::IsNullOrWhiteSpace($S3Bucket)) {
  Write-Output "Copy scene file from AWS S3 bucket '$S3Bucket' to local temp folder" | Timestamp

  if (![string]::IsNullOrWhiteSpace($AccessKey) -or ![string]::IsNullOrWhiteSpace($SecretKey)) {
    Copy-S3Object -BucketName $S3Bucket -Key $SceneKeyOrUrl -LocalFolder $dataPath -AccessKey $AccessKey -SecretKey $SecretKey
  } else {
    Copy-S3Object -BucketName $S3Bucket -Key $SceneKeyOrUrl -LocalFolder $dataPath
  }
} elseif (Test-UriScheme($SceneKeyOrUrl, @("http", "https"))) {
  Write-Output "Download scene file from '$SceneKeyOrUrl' to local temp folder" | Timestamp

  # Extract filename from scene address and update path
  $sceneFilename = Split-Path -Path $SceneKeyOrUrl -Leaf
  $scenePath = Join-Path $dataPath $sceneFilename

  Invoke-WebRequest $SceneKeyOrUrl -OutFile $scenePath
}

# Set public IP or hostname as username for collaboration session
$collaborationName = Get-PublicIP
if ($collaborationName -eq "") { $collaborationName = hostname; }
Write-Output "Collaboration name is $collaborationName" | Timestamp

# Create post python script
$vredScript = Get-InitScript $CollaborationServer $collaborationName
$postPythonPath = Join-Path $dataPath "vred.py"
Set-Content $postPythonPath $vredScript -Encoding utf8


####################################################################################################
# Install and configure SteamVR and CloudXR
####################################################################################################

# Extract SteamVR files
$steamZipPath = Join-Path $tempPath "SteamVR.zip"
Expand-Archive -LiteralPath $steamZipPath -DestinationPath $steamInstPath -Force

# Install CloudXR
$cxrInstPath = "$env:USERPROFILE\Desktop\3.1-CloudXR-SDK(11-12-2021)"
if ($Env:CloudXR_SDK -ne $null) {
  $cxrInstPath = $Env:CloudXR_SDK
}
Write-Output "Install CloudXR from $cxrInstPath" | Timestamp
Start-Process -FilePath (Join-Path $cxrInstPath "Installer\CloudXR-Setup.exe") -ArgumentList "/S /FORCE=1" -Wait

# Add firewall rule for SteamVR
$steamVRServerPath = Join-Path $steamInstPath "bin\win64\vrserver.exe"
New-NetFirewallRule -DisplayName "CloudXR SteamVR Server" -Direction Inbound -Program $steamVRServerPath -Action Allow | Out-Null


####################################################################################################
# Create local user account, enable auto-logon and create a scheduled task to startup everything
####################################################################################################

# Create a new local administrator account and enable auto-logon
$userName = "CloudXRAdmin"
try {
  $password = $(Get-RandomPassword 24)
  $user = New-LocalUser -Password $(ConvertTo-SecureString -AsPlainText -Force $password) -Name $userName -FullName $userName -Description "Administrator for CloudXR, SteamVR and VRED" -AccountNeverExpires:$true
  Add-LocalGroupMember -Group administrators -Member $user
  Set-AutoLogon $userName $password 65535
} catch {
  Write-Output "Create a local administrator and enable auto-logon failed:`n$Error" | Timestamp
}

# Register a scheduled task
try {
  Write-Output "Create a scheduled task to run VRED at logon of $env:ComputerName\$userName" | Timestamp
  $taskName = "PSStartVRED"
  $taskPrincipal = New-ScheduledTaskPrincipal -UserId "$env:ComputerName\$userName" -Logontype Interactive -RunLevel Highest
  $taskAction = New-ScheduledTaskAction `
      -Execute "powershell.exe" `
      -Argument "-File $PSScriptRoot\run-vred.ps1"

  $jobTrigger = New-JobTrigger -AtLogOn -User "$env:ComputerName\$userName"
  Register-ScheduledJob -Trigger $jobTrigger -FilePath "$PSScriptRoot\run-vred.ps1" -Name $taskName | Out-Null
  Set-ScheduledTask -TaskName $taskName `
      -TaskPath Microsoft\Windows\PowerShell\ScheduledJobs `
      -Action $taskAction `
      -Principal $taskPrincipal `
      | Out-Null
} catch {
  Write-Output "Create a scheduled task failed:`n$Error" | Timestamp
}

# Re-enable Windows Defender Realtime Protection to speed up the installation
Set-MpPreference -DisableRealtimeMonitoring $false

Write-Output "Installation and configuration completed" | Timestamp