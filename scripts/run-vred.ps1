<#PSScriptInfo
.VERSION 1.0
.GUID 72a30cce-f70c-4994-9a3e-217e83217346
.AUTHOR norman.geiersbach@autodesk.com
.COMPANYNAME Autodesk
.COPYRIGHT Autodesk, Inc. All Rights Reserved.
#>

<#
.DESCRIPTION
 A script to start VRED Core on an AWS EC2 Windows instance.
 It handles the following tasks:
 * Set the license server Autodesk VRED
 * Download a VRED scene file to a temporary directory or
 * Copy VRED scene file from AWS S3 bucket to a temporary directory
 * Start VRED Core with scene file
 * Run python script to switch display mode as soon a HMD is available
 * Run python script to connect VRED to a collaboration session
#>
Param (
  [parameter(Mandatory=$true, HelpMessage="The address of the ADSK license server.")]
  [String]
  $LicenseServer,
  [parameter(Mandatory=$true, HelpMessage="The address of the VRED collaboration server.")]
  [String]
  $CollaborationServer,
  [parameter(Mandatory=$true, HelpMessage="The Url to the VRED scene on a web server or the path on an AWS S3 bucket.")]
  [String]
  $Scene,
  [parameter(Mandatory=$false, HelpMessage="The AWS S3 bucket.")]
  [String]
  $S3Bucket,
  [parameter(Mandatory=$false, HelpMessage="The AWS access key for the S3 user account.")]
  [String]
  $AccessKey,
  [parameter(Mandatory=$false, HelpMessage="The AWS secret key for the S3 user account.")]
  [String]
  $SecretKey
)

Import-Module -Name $PSScriptRoot\vred-library.psm1 -Force

# Add Type System.Web if not already added
try {
  [System.Web.HttpUtility]$HttpUtilityTest
} catch {
  Add-Type -AssemblyName System.Web
}

# Improve download performance by disabling the display of progress
$ProgressPreference = 'SilentlyContinue'

# Change license to new server
Set-AdskLicense $LicenseServer

# Create temp folder
$tempPath = "$env:USERPROFILE\Desktop\VRED"
[Void](New-Item -Type Directory -Path $tempPath -Force)

# Path to scene file in temp folder
$scenePath = Join-Path $tempPath $Scene

# Copy scene file from AWS S3 bucket or web server to temporary directory
if (![string]::IsNullOrWhiteSpace($S3Bucket)) {
  Write-Output "Copy scene file from AWS S3 bucket '$S3Bucket' to local temp folder" | Timestamp

  if (![string]::IsNullOrWhiteSpace($AccessKey) -or ![string]::IsNullOrWhiteSpace($SecretKey)) {
    Copy-S3Object -BucketName $S3Bucket -Key $Scene -LocalFolder $tempPath -AccessKey $AccessKey -SecretKey $SecretKey
  } else {
    Copy-S3Object -BucketName $S3Bucket -Key $Scene -LocalFolder $tempPath
  }
} elseif (Test-UriScheme($Scene, @("http", "https"))) {
  Write-Output "Download scene file from '$Scene' to local temp folder" | Timestamp

  # Extract filename from scene address and update path
  $sceneFilename = Split-Path -Path $Scene -Leaf
  $scenePath = Join-Path $tempPath $sceneFilename

  Invoke-WebRequest $Scene -OutFile $scenePath
}

# Set public IP or hostname as username for collaboration session
$collaborationName = Get-PublicIP
if ($collaborationName -eq "") { $collaborationName = hostname; }
Write-Output "Collaboration name is $collaborationName" | Timestamp

# Create post python script
$vredScript = Get-InitScript $CollaborationServer $collaborationName
$postPythonPath = Join-Path $tempPath "vred.py"
Set-Content $postPythonPath $vredScript -Encoding utf8

# Loop until VRED Core is running properly
$started = $false
$serverRunning = $false
do {
  $running = Get-Process VREDCore -ErrorAction SilentlyContinue
  if (!$running -and !$started)
  {
    # Start VRED Core
    try {
      Invoke-VredCore $scenePath $postPythonPath
      Write-Output "VRED Core is starting with scene $scenePath" | Timestamp
      $started = $true
    } catch [InvalidOperationException] {
      Write-Output "VRED Core failed to start" | Timestamp
      Write-Host -ForegroundColor Red $_
      exit 1
    }
  } elseif ($running) {
    # Check for VRED web interface
    try {
      $response = Invoke-WebRequest "http://localhost:8888/isrunning" #-SkipHttpErrorCheck
      if ($response.Content -eq "1") {
        Write-Output "VRED Core is ready to use." | Timestamp
        $serverRunning = $true
      }
    } catch {}
  } else {
    Write-Output "VRED Core has exited!" | Timestamp
    break
  }

  # Idle 2 seconds before the next check to reduce CPU load
  if (!$serverRunning) { Start-Sleep -s 2 }
} while (!$serverRunning)
