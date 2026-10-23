# Runs only download/cache operations against a synthetic loopback HTTP server.
param([Parameter(Mandatory)][string]$FixtureRoot)
$modulePath=Join-Path (Split-Path $PSScriptRoot) 'WebfileCacher\WebfileCacher.psm1'
Import-Module $modulePath -Force
$statePath=Join-Path $FixtureRoot 'state.json'
$port=Get-Content (Join-Path $FixtureRoot 'port.txt')
$url="http://127.0.0.1:$port/Secrets.aqsecrets"
function Set-Fixture($Data) { $Data | ConvertTo-Json | Set-Content -LiteralPath $statePath -Encoding UTF8 }
Describe 'Encrypted-file caching through the public API' {
    BeforeEach {
        $script:cache=Join-Path $FixtureRoot ([guid]::NewGuid().ToString('N'))
        Set-Fixture @{body='AQSECR01synthetic-only';modified='Fri, 23 Oct 2026 12:00:00 GMT'}
    }
    It 'downloads binary bytes and reuses an unchanged Last-Modified value' {
        $file=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        [IO.File]::ReadAllText($file.FullName) | Should Be 'AQSECR01synthetic-only'
        $null=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        (Get-Content $statePath -Raw | ConvertFrom-Json).gets | Should Be 1
        $cacher=Get-Cacher -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        $cacher.GetCachedFileLastModified().Kind | Should Be 'Utc'
    }
    It 'refreshes a newer bundle, including updates less than one hour apart' {
        $file=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        Set-Fixture @{body='AQSECR01replacement';modified='Fri, 23 Oct 2026 12:01:00 GMT'}
        $file=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        [IO.File]::ReadAllText($file.FullName) | Should Be 'AQSECR01replacement'
    }
    It 'preserves the previous bundle and timestamp after a truncated download' {
        $file=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        $metadata=Get-Content (Join-Path $cache 'Secrets.aqsecrets-CacheData.json') -Raw
        Set-Fixture @{body='damaged';modified='Fri, 23 Oct 2026 12:01:00 GMT';truncate=$true}
        $file=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        [IO.File]::ReadAllText($file.FullName) | Should Be 'AQSECR01synthetic-only'
        (Get-Content (Join-Path $cache 'Secrets.aqsecrets-CacheData.json') -Raw) | Should Be $metadata
        @(Get-ChildItem $cache -Filter '*.download').Count | Should Be 0
    }
    It 'falls back to an intact cache on HTTP failure' {
        $file=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        Set-Fixture @{status=404}
        $file=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        [IO.File]::ReadAllText($file.FullName) | Should Be 'AQSECR01synthetic-only'
    }
    It 'does not create a successful cache when the first request fails' {
        Set-Fixture @{status=404}
        { Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache -ErrorAction Stop } | Should Throw
        Test-Path (Join-Path $cache 'Secrets.aqsecrets') | Should Be $false
    }
    It 'refreshes each time when Last-Modified is unavailable' {
        Set-Fixture @{body='AQSECR01first';omit_modified=$true;omit_length=$true}
        $null=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        Set-Fixture @{body='AQSECR01second';omit_modified=$true;omit_length=$true}
        $file=Get-CachedFile -Name 'Secrets.aqsecrets' -URL $url -Dir $cache
        [IO.File]::ReadAllText($file.FullName) | Should Be 'AQSECR01second'
        Test-Path (Join-Path $cache 'Secrets.aqsecrets-CacheData.json') | Should Be $false
    }
}
