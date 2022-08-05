# WebfileCacher
A Powershell module that allows you to always have an updated copy of a file from a webserver using the Last-Modified header

## Example:
```PowerShell
Import-Module WebfileCacher
Get-CachedFile -Name "test.pdf" -URL "https://www.microsoft.com/en-us/research/wp-content/uploads/2004/12/tr-2004-136.pdf" -Dir "$env:TEMP"
```
