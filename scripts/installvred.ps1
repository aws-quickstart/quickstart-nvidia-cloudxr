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
.EXAMPLE
Set-ExecutionPolicy -ExecutionPolicy RemoteSigned -Scope Process
.\vred-core.ps1 2080@212.227.12.188 http://dam.eitido.de/genesis.vpb
#> 
Param (
  [parameter(Mandatory=$true, HelpMessage="The address of the ADSK license server.")]
  [String]
  $licenseServer,
  [parameter(Mandatory=$true, HelpMessage="The address to a VRED scene file. It can be an URI or a path in a AWS S3 bucket.")]
  [String]
  $sceneAddress,
  [parameter(Mandatory=$false, HelpMessage="The optional AWS S3 bucket.")]
  [String]
  $s3Bucket
)

# Path to VRED Core executable
$vredPath = "C:\Program Files\Autodesk\VREDCore-14.3\bin\WIN64\VREDCore.exe"

# Extract filename from scene address
$sceneFilename = Split-Path -Path $sceneAddress -Leaf

# Creates a temporary folder and returns the path to the specified file
function CreateTempFolderFor($file) {
  $tempPath = Join-Path $Env:Temp $(New-Guid)
  Write-Output "Create temporary folder $tempPath" | Out-Null
  New-Item -Type Directory -Path $tempPath | Out-Null
  Join-Path $tempPath $file
}

# Helper do determine whether the specified address is a valid http or https URI
function IsURIWeb($address) {
	$uri = $address -as [System.URI]
	$uri.AbsoluteURI -ne $null -and $uri.Scheme -match 'http|https'
}

# Initializes VRED Core by running a python script
function InitializeVredByScript() {
  Write-Output "VRED Core initialize by script"
  try {
    # A script to change the display mode to open vr as soon as an Hmd is active
    $script = 'exec """\ndef testVR():\n    vrOSGWidget.setDisplayMode(VR_DISPLAY_OPEN_VR)\n    if(vrHMDService.isHmdActive()):\n        timer.setActive(false)\n        print("VR Active!")\n    else:\n        print("VR not yet active")\n\ntimer = vrTimer(2)\ntimer.connect(testVR)\ntimer.setActive(true)\n"""'
    Invoke-WebRequest "http://localhost:8888/python?value=$([System.Web.HTTPUtility]::UrlEncode($script))" | Out-Null #-SkipHttpErrorCheck
  } catch {
    Write-Output "Run initialization script failed"
    Write-Host -ForegroundColor Red $_
  }
}

# Connect VRED Core to a collaboration session
function ConnectVredToCollaborationSession($address) {
  Write-Output "VRED Core connect to collaboration session"
  try {
    # A script to change the display mode to open vr as soon as an Hmd is active
    $script = 'vrSessionService.join("' + $address + '", userName="' + $address + '", color=PySide2.QtGui.Qt.transparent, roomName="AWS", passwd="", forceVersion=False)'
    Invoke-WebRequest "http://localhost:8888/python?value=$([System.Web.HTTPUtility]::UrlEncode($script))" | Out-Null #-SkipHttpErrorCheck
  } catch {
    Write-Output "Run initialization script failed"
    Write-Host -ForegroundColor Red $_
  }
}

# Change license to new server
Write-Output "Change license server to $licenseServer"
try {
  Start-Process -FilePath "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\helper\AdskLicensingInstHelper.exe" -ArgumentList "change --pk 887N1 --pv 2022.0.0.F -lm NETWORK -ls $licenseServer"  
} catch [InvalidOperationException] {
  Write-Output "Change license server failed"
  Write-Host -ForegroundColor Red $_
}

# Set default path to scene file
$scenePath = $sceneAddress

# Copy scene file from AWS S3 bucket or URI to temporary directory
if (![string]::IsNullOrWhiteSpace($s3Bucket)) {
  # Find documentation here: https://docs.aws.amazon.com/AWSEC2/latest/WindowsGuide/AmazonS3.html
  $scenePath = CreateTempFolderFor($sceneFilename)
  Write-Output "Copy scene file from AWS S3 bucket '$s3Bucket' to local temp folder"
  #Copy-S3Object -BucketName $s3Bucket -Key $filename -LocalFile $scenePath
} elseif (IsURIWeb($sceneAddress)) {
  # Download file from server
  $scenePath = CreateTempFolderFor($sceneFilename)
  Write-Output "Download scene file from URI '$sceneAddress' to local temp folder"
  # Improve performance by disabling the display of progress
  $ProgressPreference = 'SilentlyContinue'
  Invoke-WebRequest $sceneAddress -OutFile $scenePath
}

# Loop until VRED Core is running properly
$started = $false
$serverRunning = $false
do {
  $running = Get-Process VREDCore -ErrorAction SilentlyContinue
  if (!$running -and !$started)
  {
    # Start VRED Core
    try {
      Start-Process -FilePath $vredPath -ArgumentList "$scenePath -postpython `"print(\`"Hello AWS instance\`")`"" #-PassThru
      Write-Output "VRED Core is starting with scene $scenePath"
      $started = $true
    } catch [InvalidOperationException] {
      Write-Output "VRED Core failed to start"
      Write-Host -ForegroundColor Red $_
      exit 1
    }
  } elseif ($running) {
    # Check for VRED web interface
    try {
      $response = Invoke-WebRequest "http://localhost:8888/isrunning" #-SkipHttpErrorCheck
      if ($response.Content -eq "1") {
        Write-Output "VRED Core is ready to use."
        $serverRunning = $true
      }
    } catch {}

    # Run initial python script if running
    if ($serverRunning) {
      InitializeVredByScript
      ConnectVredToCollaborationSession "localhost"
    }
  } else {
    Write-Output "VRED Core has exited!"
    break
  }

  # Idle 2 seconds before the next check to reduce CPU load
  if (!$serverRunning) { Start-Sleep -s 2 }
} while (!$serverRunning)
