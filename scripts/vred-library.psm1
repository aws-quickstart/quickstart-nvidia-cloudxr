<#PSScriptInfo
.VERSION 1.0
.GUID a7d266d8-235b-47c8-887c-6f3b7b7b11ea
.AUTHOR norman.geiersbach@autodesk.com
.COMPANYNAME Autodesk
.COPYRIGHT Autodesk, Inc. All Rights Reserved.
#>

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


# Invokes a new VRED Core process and loads the specified scene.
function Invoke-VredCore {
  param (
    [string]
    $ScenePath,
    [string]
    $Version = "15.0"
  )

  $vredPath = "C:\Program Files\Autodesk\VREDCore-$Version\bin\WIN64\VREDCore.exe"
  Start-Process -FilePath $vredPath -ArgumentList "$ScenePath -postpython `"print(\`"Hello AWS instance\`")`""
}
Export-ModuleMember -Function Invoke-VredCore


# The locally running VRED Core joins a collaboration session.
function Join-VredCollaboration {
  param (
    [string]
    $Address,
    [string]
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
    [string]
    $LicenseServer
  )

  Write-Output "Change license server to $LicenseServer"

  try {
    Start-Process -FilePath "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\helper\AdskLicensingInstHelper.exe" -ArgumentList "change --pk 887O1 --pv 2023.0.0.F -lm NETWORK -ls $LicenseServer" -Wait
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
    [string]
    $Address,
    [string[]]
    $Schemes
  )

  $match = $Schemes -join "|"
	$uri = $Address -as [System.URI]
	$null -ne $uri.AbsoluteURI -and $uri.Scheme -match $match
}
Export-ModuleMember -Function Test-UriScheme
