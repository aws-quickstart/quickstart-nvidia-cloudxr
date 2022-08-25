<#PSScriptInfo
.VERSION 1.0
.GUID 99043890-70d0-4691-af9f-8a315ae9deef
.AUTHOR norman.geiersbach@autodesk.com
.COMPANYNAME Autodesk
.COPYRIGHT Autodesk, Inc. All Rights Reserved.
#>

<#
.DESCRIPTION
 A script to install SteamVR, CloudXR and VRED Core on an AWS EC2 Windows instance.
#>
Param (
  [parameter(Mandatory=$true, HelpMessage="The optional AWS S3 bucket.")]
  [String]
  $S3Bucket,
  [parameter(Mandatory=$true, HelpMessage="The name of the vred core installer.")]
  [String]
  $KeyPrefix,
  [parameter(Mandatory=$false, HelpMessage="The AWS access key for the user account.")]
  [String]
  $AccessKey,
  [parameter(Mandatory=$false, HelpMessage="The AWS secret key for the user account.")]
  [String]
  $SecretKey
)

Import-Module -Name C:\cfn\scripts\vred-library.psm1 -Force

# Disable Windows Defender Realtime Protection to speed up the installation
Set-MpPreference -DisableRealtimeMonitoring $true

# Disable Windows updates to prevent a restart of the instance
Start-Process "sc.exe" -ArgumentList "stop wuauserv"
Set-ItemProperty -Path "HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate\AU" -Name NoAutoUpdate -Value 1

# Create tempoary folder
$tempPath = New-TempFolder

# Copy installer from AWS S3 bucket to temporary directory
# Find documentation here: https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/AmazonS3.html
Write-Output "Copy installer files from AWS S3 bucket '$S3Bucket' to local temp folder '$tempPath'" | Timestamp
if (![string]::IsNullOrWhiteSpace($AccessKey) -or ![string]::IsNullOrWhiteSpace($SecretKey)) {
  # Copy installer files
  Copy-S3Object -BucketName $S3Bucket -KeyPrefix $KeyPrefix -LocalFolder $tempPath -AccessKey $AccessKey -SecretKey $SecretKey
} else {
  # Copy installer files
  Copy-S3Object -BucketName $S3Bucket -KeyPrefix $KeyPrefix -LocalFolder $tempPath
}

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

# Extract SteamVR files
$steamZipPath = Join-Path $tempPath "SteamVR.zip"
$steamInstPath = "$env:USERPROFILE\Desktop\SteamVR"
Expand-Archive -LiteralPath $steamZipPath -DestinationPath $steamInstPath -Force

# Install CloudXR
Write-Output "Install CloudXR" | Timestamp
Start-Process -FilePath "$env:USERPROFILE\Desktop\3.1-CloudXR-SDK(11-12-2021)\Installer\CloudXR-Setup.exe" -ArgumentList "/S /FORCE=1" -Wait

Write-Output "Configure SteamVR" | Timestamp
$steamRegPath = Join-Path $steamInstPath "\bin\win64\vrpathreg.exe"
$steamConfigPath = "$env:USERPROFILE\AppData\Local\openvr\config"
$steamLogPath = "$env:USERPROFILE\AppData\Local\openvr\logs"
Start-Process -FilePath $steamRegPath -ArgumentList "setconfig $steamConfigPath" -Wait
Start-Process -FilePath $steamRegPath -ArgumentList "setlog $steamLogPath" -Wait
Start-Process -FilePath $steamRegPath -ArgumentList "setruntime $steamInstPath" -Wait
Start-Process -FilePath $steamRegPath -ArgumentList 'adddriver "C:\Program Files\NVIDIA Corporation\CloudXR\VRDriver\CloudXRRemoteHMD"' -Wait

Write-Output "Check SteamVR configuration" | Timestamp
Start-Process -FilePath $steamRegPath -ArgumentList "show" -Wait -NoNewWindow

# Add firewall rule for SteamVR
$steamVRServerPath = Join-Path $steamInstPath "bin\win64\vrserver.exe"
New-NetFirewallRule -DisplayName "CloudXR SteamVR Server" -Direction Inbound -Program $steamVRServerPath -Action Allow

# Start SteamVR
# https://vrcollab.com/help/install-steamvr-in-an-enterprise-or-government-use-environment/
$steamVRPath = Join-Path $steamInstPath "bin\win64\vrstartup.exe"
Start-Process -FilePath $steamVRPath
Write-Output "SteamVR started."

# Re-enable Windows Defender Realtime Protection to speed up the installation
Set-MpPreference -DisableRealtimeMonitoring $false