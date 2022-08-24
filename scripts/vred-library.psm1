<#PSScriptInfo
.VERSION 1.0
.GUID a7d266d8-235b-47c8-887c-6f3b7b7b11ea
.AUTHOR norman.geiersbach@autodesk.com
.COMPANYNAME Autodesk
.COPYRIGHT Autodesk, Inc. All Rights Reserved.
#>

# Converts a VRED release version into the product version.
function Get-ProductVersion {
  param (
    [parameter(Mandatory=$true, HelpMessage="The VRED release version, e.g. 2023.0.0")]
    [String]
    $Version
  )

  $numbers = $Version.Split('.')
  $major = [int]$numbers[0] - 2008
  $minor = if ($numbers.Length -gt 1) { $numbers[1] } else { 0 }
  return "$major.$minor"
}
Export-ModuleMember -Function Get-ProductVersion


# Converts a VRED product version into the release version.
function Get-ReleaseVersion {
  param (
    [parameter(Mandatory=$true, HelpMessage="The VRED product version, e.g. 15.0")]
    [String]
    $Version
  )

  $numbers = $Version.Split('.')
  $major = [int]$numbers[0] + 2008
  $minor = if ($numbers.Length -gt 1) { $numbers[1] } else { 0 }
  "$major.$minor.0"
}
Export-ModuleMember -Function Get-ReleaseVersion


# Returns the latest installed product version of VRED Core.
function Get-LatestProductVersion {
  $properties = @(Get-ChildItem -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Autodesk\VREDCore | Select-Object -ExpandProperty Name | Sort)
  if ($properties.Length -eq 0) { throw "No VRED Core installations found." }
  Split-Path -Path $properties[-1] -Leaf
}
Export-ModuleMember -Function Get-LatestProductVersion


# Returns the latest installed release version of VRED Core.
function Get-LastestReleaseVersion {
  Get-ReleaseVersion (Get-LatestProductVersion)
}
Export-ModuleMember -Function Get-LastestReleaseVersion


# Returns the path to executable of the specified or latest VRED Core.
function Get-ExecutablePath {
  param (
    [parameter(Mandatory=$false, HelpMessage="The VRED product version, e.g. 15.0")]
    [String]
    $Version = (Get-LatestProductVersion)
  )

  Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Autodesk\VREDCore\$Version -Name Executable | Select-Object -ExpandProperty Executable
}
Export-ModuleMember -Function Get-ExecutablePath


# Trys to get the public IP address of the machine.
function Get-PublicIP {
  try {
    return (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
  } catch {
    return ""
  }
}
Export-ModuleMember -Function Get-PublicIP


# Initializes VRED Core for CloudXR.
function Initialize-VredForCloudXR {
  Write-Output "VRED Core initialize by script"

  try {
    # A script to change the display mode to open vr as soon as an Hmd is active
    $script = 'exec """\ndef testVR():\n    vrOSGWidget.setDisplayMode(VR_DISPLAY_OPEN_VR)\n    if(vrHMDService.isHmdActive()):\n        timer.setActive(false)\n        print("VR Active!")\n    else:\n        print("VR not yet active")\n\ntimer = vrTimer(2)\ntimer.connect(testVR)\ntimer.setActive(true)\n"""'
    Invoke-WebRequest "http://localhost:8888/python?value=$([System.Web.HTTPUtility]::UrlEncode($script))" | Out-Null #-SkipHttpErrorCheck
  } catch {
    Write-Output "Run initialization script failed"
    Write-Host -ForegroundColor Red $_
    throw $_
  }
}
Export-ModuleMember -Function Initialize-VredForCloudXR


# Timestamp filter
filter Timestamp {"$(Get-Date -Format G): $_"}
Export-ModuleMember -Function Timestamp


# Invokes a new VRED Core process and loads the specified scene.
function Invoke-VredCore {
  param (
    [parameter(Mandatory=$false, HelpMessage="Path to the scene to load with VRED.")]
    [String]
    $ScenePath,
    [parameter(Mandatory=$false, HelpMessage="The VRED product version to start.")]
    [String]
    $Version = (Get-LatestProductVersion)
  )

  $vredPath = Get-ExecutablePath $Version
  Start-Process -FilePath $vredPath -ArgumentList "$ScenePath -postpython `"print(\`"Hello AWS instance\`")`""
}
Export-ModuleMember -Function Invoke-VredCore


# The locally running VRED Core joins a collaboration session.
function Join-VredCollaboration {
  param (
    [String]
    $Address,
    [String]
    $UserName = "AWS1"
  )

  Write-Output "VRED Core join collaboration session $Address"

  try {
    # A script to change the display mode to open vr as soon as an Hmd is active
    $script = 'vrSessionService.join("' + $Address + '", userName="' + $UserName + '", color=PySide2.QtGui.Qt.transparent, roomName="AWS", passwd="", forceVersion=False)'
    Invoke-WebRequest "http://localhost:8888/python?value=$([System.Web.HTTPUtility]::UrlEncode($script))" | Out-Null #-SkipHttpErrorCheck
  } catch {
    Write-Output "Run initialization script failed"
    Write-Host -ForegroundColor Red $_
    throw $_
  }
}
Export-ModuleMember -Function Join-VredCollaboration


# Creates a temporary folder and returns the full path to it.
function New-TempFolder {
  $tempPath = Join-Path $Env:Temp $(New-Guid)
  Write-Output "Create temporary folder $tempPath" | Out-Null
  New-Item -Type Directory -Path $tempPath | Out-Null
  $tempPath
}
Export-ModuleMember -Function New-TempFolder


# Sets the instance wide Autodesk license server.
function Set-AdskLicense {
  param (
    [parameter(Mandatory=$true, HelpMessage="The license server.")]
    [String]
    $LicenseServer,
    [parameter(Mandatory=$false, HelpMessage="The VRED release version, e.g. 2023.0.0")]
    [String]
    $ReleaseVersion = (Get-LastestReleaseVersion)
  )

  $productKey = "887O1"
  $productVersion = "($ReleaseVersion).F"

  try {
    $major = [int]$ReleaseVersion.Split('.')[0]
    $pkChar = [int][char]'O'
    $pkChar += $major - 2023
    $productKey = "887" + [char]$pkChar + "1"
    $productVersion = "$major.0.0.F"
  } catch [InvalidOperationException] {
    Write-Output "Invalid VRED version"
    Write-Host -ForegroundColor Red $_
    throw $_
  }

  Write-Output "Change license server to $LicenseServer"

  try {
    Start-Process -FilePath "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\helper\AdskLicensingInstHelper.exe" -ArgumentList "change --pk $productKey --pv $productVersion -lm NETWORK -ls $LicenseServer" -Wait
  } catch [InvalidOperationException] {
    Write-Output "Change license server failed"
    Write-Host -ForegroundColor Red $_
    throw $_
  }
}
Export-ModuleMember -Function Set-AdskLicense


# Returns true if the specified address matches one of the specified schemes.
function Test-UriScheme {
  param (
    [String]
    $Address,
    [String[]]
    $Schemes
  )

  $match = $Schemes -join "|"
	$uri = $Address -as [System.URI]
	$null -ne $uri.AbsoluteURI -and $uri.Scheme -match $match
}
Export-ModuleMember -Function Test-UriScheme
