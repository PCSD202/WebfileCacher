# WebfileCacher
A Powershell module that allows you to always have an updated copy of a file from a webserver using the Last-Modified header

## Example:
```PowerShell
Install-Module WebfileCacher
Import-Module WebfileCacher
$URL = "https://github.com/PCSD202/AutopilotQuick/releases/latest/download/AutopilotQuick.zip"
Get-CachedFile -URL $URL -Name "AutopilotQuick.zip" -Dir "$env:TEMP\Test"
```
