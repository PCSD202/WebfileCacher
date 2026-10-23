# WebfileCacher
A Powershell module that allows you to always have an updated copy of a file from a webserver using the Last-Modified header

Version 1.2.1 uses `-UseBasicParsing` for metadata requests. Downloads are written to a temporary file beside the cache and replace it only after a complete transfer; failed updates retain the old file and its timestamp. Cache timestamps are read as UTC. Without a usable Last-Modified header the module attempts a refresh on each call and can fall back to an intact cached file.

The same API can cache an encrypted bundle without decrypting it:

```powershell
Get-CachedFile -Name 'Secrets.aqsecrets' -URL 'https://nettools.psd202.org/AutoPilotFast/Secrets.aqsecrets' -Dir 'C:\AutopilotQuick\AutopilotQuick\Cache'
```

Tests in `Tests/Invoke-CacheTests.ps1` run in Windows PowerShell 5.1 with Python available. They use a synthetic loopback HTTP server and temporary files, including newer headers, truncated transfers, failed requests, and missing headers. They do not contact production servers or perform disk preparation.

## Example:
```PowerShell
Install-Module WebfileCacher
Import-Module WebfileCacher
$URL = "https://github.com/PCSD202/AutopilotQuick/releases/latest/download/AutopilotQuick.zip"
Get-CachedFile -URL $URL -Name "AutopilotQuick.zip" -Dir "$env:TEMP\Test"
```
