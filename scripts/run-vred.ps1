<#PSScriptInfo
.VERSION 1.1
.GUID 72a30cce-f70c-4994-9a3e-217e83217346
.AUTHOR norman.geiersbach@autodesk.com
.COMPANYNAME Autodesk
.COPYRIGHT Autodesk, Inc. All Rights Reserved.
#>

<#
  .DESCRIPTION
   A script to start SteamVR and VRED Core on an AWS EC2 Windows instance.
#>

$dataPath = "C:\Autodesk\VRED"
$steamInstPath = "C:\SteamVR"
$log = Join-Path $dataPath "auto-start-$(Get-Date -Format "yyyyMMdd-HHmmss").log"

# Create data folder
[Void](New-Item -Type Directory -Path $dataPath -Force)

# Create log file
Set-Content -Path $log -Value @"
Start SteamVR and VRED Core
Current user: $env:UserName
Location: $(Get-Location)
Script root: $PSScriptRoot

"@

try
{
  # Load script module
  if ($PSScriptRoot -eq "" -or $PSScriptRoot -eq $null) {
    Import-Module -Name C:\cfn\scripts\vred-library.psm1 -Force
  } else {
    Import-Module -Name $PSScriptRoot\vred-library.psm1 -Force
  }

  # Configure SteamVR
  Add-Content $log ("Configure SteamVR .." | Timestamp)
  $steamRegPath = Join-Path $steamInstPath "\bin\win64\vrpathreg.exe"
  $steamConfigPath = "$env:USERPROFILE\AppData\Local\openvr\config"
  $steamLogPath = "$env:USERPROFILE\AppData\Local\openvr\logs"
  Start-Process -FilePath $steamRegPath -ArgumentList "setconfig $steamConfigPath" -Wait
  Start-Process -FilePath $steamRegPath -ArgumentList "setlog $steamLogPath" -Wait
  Start-Process -FilePath $steamRegPath -ArgumentList "setruntime $steamInstPath" -Wait
  Start-Process -FilePath $steamRegPath -ArgumentList 'adddriver "C:\Program Files\NVIDIA Corporation\CloudXR\VRDriver\CloudXRRemoteHMD"' -Wait

  Add-Content $log ("Check SteamVR configuration .." | Timestamp)
  Start-Process -FilePath $steamRegPath -ArgumentList "show" -Wait -NoNewWindow

  # Start SteamVR
  $steamVRPath = Join-Path $steamInstPath "bin\win64\vrstartup.exe"
  Start-Process -FilePath $steamVRPath
  Add-Content $log ("SteamVR started." | Timestamp)

  # Find a scene file recursively in the data folder
  $scenes = @(Get-ChildItem -Path $dataPath -Filter *.vpb -File -Recurse -ErrorAction SilentlyContinue | ForEach-Object {"$($_.FullName)"})
  if ($scenes.count -eq 0) {
    Add-Content $log ("No VRED scene file found at $dataPath." | Timestamp)
    exit 1
  }

  # Path to python script
  $postPythonPath = Join-Path $dataPath "vred.py"

  # Start VRED Core with first scene file found
  Invoke-VredCore $scenes[0] $postPythonPath
  Add-Content $log ("VRED Core is starting with scene `"$($scenes[0])`"" | Timestamp)
} catch {
  Add-Content $log ("Auto-start VRED Core failed:`n$Error" | Timestamp)
  throw $_
}