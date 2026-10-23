param([string]$PythonPath=(Get-Command python -ErrorAction Stop).Source)
$ErrorActionPreference='Stop'
$fixtureRoot=Join-Path ([IO.Path]::GetTempPath()) ('aq-cache-tests-'+[guid]::NewGuid().ToString('N'))
$null=New-Item -ItemType Directory -Path $fixtureRoot
$statePath=Join-Path $fixtureRoot 'state.json'
$portPath=Join-Path $fixtureRoot 'port.txt'
'{}' | Set-Content -LiteralPath $statePath -Encoding UTF8
$server=Start-Process -FilePath $PythonPath -ArgumentList @(('"'+(Join-Path $PSScriptRoot 'http_fixture.py')+'"'),('"'+$statePath+'"'),('"'+$portPath+'"')) -WindowStyle Hidden -PassThru
try {
    $deadline=(Get-Date).AddSeconds(15)
    while (!(Test-Path -LiteralPath $portPath)) {
        if ($server.HasExited -or (Get-Date) -gt $deadline) { throw 'Synthetic HTTP server did not start.' }
        Start-Sleep -Milliseconds 100
    }
    $result=Invoke-Pester -Script @{Path=(Join-Path $PSScriptRoot 'Cache.Tests.ps1');Parameters=@{FixtureRoot=$fixtureRoot}} -PassThru
    if ($result.FailedCount -ne 0) { throw "$($result.FailedCount) cache tests failed. Fixture retained at $fixtureRoot" }
}
finally {
    if (!$server.HasExited) { $server.Kill(); $server.WaitForExit() }
    $server.Dispose()
}
