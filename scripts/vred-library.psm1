<#PSScriptInfo
.VERSION 1.1
.GUID a7d266d8-235b-47c8-887c-6f3b7b7b11ea
.AUTHOR norman.geiersbach@autodesk.com
.COMPANYNAME Autodesk
.COPYRIGHT Autodesk, Inc. All Rights Reserved.
#>


<#
  .DESCRIPTION
  A filter that returns the current timestamp.
#>
filter Timestamp {"$(Get-Date -Format G): $_"}
Export-ModuleMember -Function Timestamp


<#
  .DESCRIPTION
  Converts a VRED release version into the product version.

  .PARAMETER Version
  The VRED product release, e.g. "2023.0.0".
#>
function Get-ProductVersion {
  param (
    [parameter(mandatory)]
    [string] $Version
  )

  $numbers = $Version.Split('.')
  $major = [int]$numbers[0] - 2008
  $minor = if ($numbers.Length -gt 1) { $numbers[1] } else { 0 }
  return "$major.$minor"
}
Export-ModuleMember -Function Get-ProductVersion


<#
  .DESCRIPTION
  Converts a VRED product version into the release version.

  .PARAMETER Version
  The VRED product version, e.g. "15.0".
#>
function Get-ReleaseVersion {
  param (
    [parameter(mandatory)]
    [string] $Version
  )

  $numbers = $Version.Split('.')
  $major = [int]$numbers[0] + 2008
  $minor = if ($numbers.Length -gt 1) { $numbers[1] } else { 0 }
  "$major.$minor.0"
}
Export-ModuleMember -Function Get-ReleaseVersion


<#
  .DESCRIPTION
  Returns the latest installed product version of VRED Core.
#>
function Get-LatestProductVersion {
  $properties = @(Get-ChildItem -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Autodesk\VREDCore | Select-Object -ExpandProperty Name | Sort)
  if ($properties.Length -eq 0) { throw "No VRED Core installations found." }
  Split-Path -Path $properties[-1] -Leaf
}
Export-ModuleMember -Function Get-LatestProductVersion


<#
  .DESCRIPTION
  Returns the latest installed release version of VRED Core.
#>
function Get-LastestReleaseVersion {
  Get-ReleaseVersion (Get-LatestProductVersion)
}
Export-ModuleMember -Function Get-LastestReleaseVersion


<#
  .DESCRIPTION
  Returns the path to executable of the specified or latest VRED Core.

  .PARAMETER Version
  The VRED product version, e.g. "15.0".
#>
function Get-ExecutablePath {
  param (
    [parameter()]
    [string] $Version = (Get-LatestProductVersion)
  )

  Get-ItemProperty -Path Registry::HKEY_LOCAL_MACHINE\SOFTWARE\Autodesk\VREDCore\$Version -Name Executable | Select-Object -ExpandProperty Executable
}
Export-ModuleMember -Function Get-ExecutablePath


<#
  .DESCRIPTION
  Trys to get the public IP address of the machine.
#>
function Get-PublicIP {
  try {
    return (Invoke-WebRequest -uri "http://ifconfig.me/ip").Content
  } catch {
    return ""
  }
}
Export-ModuleMember -Function Get-PublicIP


<#
  .DESCRIPTION
  Builds the initialization python script for VRED.

  .PARAMETER CollaborationServer
  The address of the collaboration server.

  .PARAMETER UserName
  The name of the user in the collaboration session.
#>
function Get-InitScript {
  param (
    [parameter(mandatory)]
    [string] $CollaborationServer,
    [parameter(mandatory)]
    [string] $UserName
  )

  # A script to join the collaboration session and to change the display mode to open vr as soon as an Hmd is available
@"
vrSessionService.join("$CollaborationServer", userName="$UserName", color=PySide2.QtGui.Qt.transparent, roomName="AWS", passwd="", forceVersion=False)

def testVR():
  vrOSGWidget.setDisplayMode(VR_DISPLAY_OPEN_VR)
  if(vrHMDService.isHmdActive()):
    timer.setActive(false)
    print("VR Active!")
  else:
    print("VR not yet active")
timer = vrTimer(2)
timer.connect(testVR)
timer.setActive(true)
"@
}
Export-ModuleMember -Function Get-InitScript


<#
  .DESCRIPTION
  Generates a random password of the specified length.

  .PARAMETER Length
  The length of the password.

  .PARAMETER AmountOfNonAlphanumeric
  The amount of non alphanumeric characters.
#>
function Get-RandomPassword {
  param (
      [parameter(Mandatory)]
      [int] $Length,
      [parameter()]
      [int] $AmountOfNonAlphanumeric = 1
  )
  Add-Type -AssemblyName 'System.Web'
  return [System.Web.Security.Membership]::GeneratePassword($Length, $AmountOfNonAlphanumeric)
}
Export-ModuleMember -Function Get-RandomPassword


<#
  .DESCRIPTION
  Returns the script root or a default fallback.
#>
function Get-ScriptRoot {
  if ($PSScriptRoot -eq "" -Or $PSScriptRoot -eq $null) { return "C:\cfn\scripts" }
  $PSScriptRoot
}
Export-ModuleMember -Function Get-ScriptRoot


<#
  .DESCRIPTION
  Invokes a new VRED Core process and loads the scene and post python script if specified.

  .PARAMETER ScenePath
  The Path to the scene to load with VRED.

  .PARAMETER PostPython
  The Path to a post python script to load with VRED.

  .PARAMETER Version
  The product version of VRED to set the license for.
  If not set, it will use the latest installed version of VRED Core.
#>
function Invoke-VredCore {
  param (
    [parameter()]
    [string] $ScenePath,
    [parameter()]
    [string] $PostPython,
    [parameter()]
    [string] $Version = (Get-LatestProductVersion)
  )

  $vredPath = Get-ExecutablePath $Version
  Start-Process -FilePath $vredPath -ArgumentList "$ScenePath $PostPython"
}
Export-ModuleMember -Function Invoke-VredCore


<#
  .DESCRIPTION
  Creates a temporary folder and returns the full path to it.
#>
function New-TempFolder {
  $tempPath = Join-Path $Env:Temp $(New-Guid)
  Write-Output "Create temporary folder $tempPath" | Out-Null
  New-Item -Type Directory -Path $tempPath | Out-Null
  $tempPath
}
Export-ModuleMember -Function New-TempFolder


<#
  .DESCRIPTION
  Sets the Autodesk license server for the specified VRED Core version.

  .PARAMETER LicenseServer
  The license server address, e.g. "127.0.0.1" or "2080@192.168.188.1".

  .PARAMETER ReleaseVersion
  The release version of VRED to set the license for.
  If not set, it will use the latest installed version of VRED Core.
#>
function Set-AdskLicense {
  param (
    [parameter(mandatory)]
    [string] $LicenseServer,
    [parameter()]
    [string] $ReleaseVersion = (Get-LastestReleaseVersion)
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

  Write-Output "Change license server to $LicenseServer" | Timestamp

  try {
    Start-Process -FilePath "C:\Program Files (x86)\Common Files\Autodesk Shared\AdskLicensing\Current\helper\AdskLicensingInstHelper.exe" -ArgumentList "change --pk $productKey --pv $productVersion -lm NETWORK -ls $LicenseServer" -Wait
  } catch [InvalidOperationException] {
    Write-Output "Change license server failed"
    Write-Host -ForegroundColor Red $_
    throw $_
  }
}
Export-ModuleMember -Function Set-AdskLicense


<#
  .DESCRIPTION
  Enable Auto-Logon next time when the server reboots.

  .PARAMETER DefaultUsername
  The name of the user to logon.

  .PARAMETER DefaultPassword
  The password of the user to logon.

  .PARAMETER AutoLogonCount
  The number of auto-logons.
#>
function Set-AutoLogon{
  param (
    [parameter(mandatory)]
    [string] $DefaultUsername,
    [parameter(mandatory)]
    [string] $DefaultPassword,
    [parameter()]
    [string] $AutoLogonCount = "1"
  )

  try
  {
    $RegPath = "HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion\Winlogon"

    Set-ItemProperty $RegPath "AutoAdminLogon" -Value "1" -type String
    Set-ItemProperty $RegPath "DefaultUsername" -Value "$DefaultUsername" -type String
    Set-ItemProperty $RegPath "DefaultPassword" -Value "$DefaultPassword" -type String
    Set-ItemProperty $RegPath "AutoLogonCount" -Value "$AutoLogonCount" -type DWord
  }
  catch
  {
    Write-Output "Set Auto-logon failed"
    Write-Host -ForegroundColor Red $_
    throw $_
  }
}
Export-ModuleMember -Function Set-AutoLogon


<#
  .DESCRIPTION
  Returns true if the specified address matches one of the specified schemes.

  .PARAMETER Address
  The address to test.

  .PARAMETER Schemes
  The schemes to test against.
#>
function Test-UriScheme {
  param (
    [parameter(mandatory)]
    [string] $Address,
    [parameter(mandatory)]
    [String[]] $Schemes
  )

  $match = $Schemes -join "|"
	$uri = $Address -as [System.URI]
	$null -ne $uri.AbsoluteURI -and $uri.Scheme -match $match
}
Export-ModuleMember -Function Test-UriScheme
