class Cacher {
    #The name of the file once downloaded.
    [string]$FileName

    #The URL of where to get the file from
    [string]$FileURL

    #The directory that we download the file to
    [string]$BaseDir

    #The path to the json file for this cached file
    [string] hidden $FileCacheDataPath

    #The path to the downloaded file
    [string]$FilePath

    Cacher(
        [string]$FileName,
        [string]$FileURL,
        [string]$BaseDir
    ) {
        $this.FileName = $FileName
        $this.FileURL = $FileURL
        $this.BaseDir = $BaseDir

        [System.IO.Directory]::CreateDirectory($BaseDir) #Creates all directories and subdirectories in the specified path unless they already exist.

        $this.FileCacheDataPath = Join-Path $BaseDir "$FileName-CacheData.json"
        $this.FilePath = Join-Path $BaseDir $FileName
    }

    [datetime] GetLastModifiedFromWeb() {
        try {
            $headers = (Invoke-WebRequest $this.FileURL -Method Head).Headers;
            $dateStr = $headers.'Last-Modified'
            $date = [datetime]::ParseExact($dateStr, "R", $null)
            return [datetime]::SpecifyKind($date, 1)
        }
        catch {
            Write-Warning "An error occurred while trying to get last modified header from web for file '$($this.FileURL) this means that the file will be redownloaded':"
            Write-Warning $_
            return [datetime]::MaxValue
        }
    }

    [datetime] GetCachedFileLastModified() {
        if (!(Test-Path $this.FileCacheDataPath)) {
            return [datetime]::MinValue
        }
        try {
            $dateStr = (Get-Content $this.FileCacheDataPath | ConvertFrom-Json)."LastModified"
            $date = [datetime]::ParseExact($dateStr, "yyyy-MM-ddTHH:mm:ssZ", $null)
            return $date.ToUniversalTime()
        }
        catch {
            Write-Warning "Had trouble reading $($this.FileCacheDataPath), removing it and redownloading. Error:"
            Write-Warning $_
            Remove-Item $this.FileCacheDataPath
            return [datetime]::MinValue
        }
    }

    [void] SetCachedFileLastModified([datetime]$LastModified) {
        $Data = [PSCustomObject]@{
            LastModified = $LastModified.ToUniversalTime().ToString("yyyy-MM-ddTHH:mm:ssZ")
        }
        $Data | ConvertTo-Json | Out-File -FilePath $this.FileCacheDataPath
    }

    [void] DownloadUpdate() {
        Get-FileFromURL -URL $this.FileURL -Filepath $this.FilePath
        $this.SetCachedFileLastModified($this.GetLastModifiedFromWeb())
    }

    [System.IO.FileInfo]Get() {
        if (!(($this.GetCachedFileLastModified() -ge $this.GetLastModifiedFromWeb()) -and (Test-Path ($this.FilePath)))) {
            try {
                $this.DownloadUpdate()
            } catch {
                if(Test-Path ($this.FilePath)){
                    return [System.IO.FileInfo]::new($this.FilePath) #Return the cached file we have since we had an error downloading the updated one
                }
                else {
                    Write-Error "Could not get cached file. Error: $_"
                    throw
                }
            }
        }

        return [System.IO.FileInfo]::new($this.FilePath)
    }
}


<#
 .Synopsis
  Downloads a file from a URL to the FileName with progress reports using Write-Progress every second.

 .Description
  Downloads a file from a URL to the FileName with progress reports every second.

 .Parameter URL
  The URL to download from

 .Parameter Filepath
  The path of the file you would like to download

#>
function Get-FileFromURL {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory, Position = 0)]
        [System.Uri]$URL,
        [Parameter(Mandatory, Position = 1)]
        [string]$Filepath
    )

    process {
        try {
            $request = [System.Net.HttpWebRequest]::Create($URL)
            $request.set_Timeout(5000) # 5 second timeout
            $request.Proxy = $null
            $response = $request.GetResponse()
            $total_bytes = $response.ContentLength
            $response_stream = $response.GetResponseStream()

            try {
                # 256KB works better on my machine for 1GB and 10GB files
                # See https://www.microsoft.com/en-us/research/wp-content/uploads/2004/12/tr-2004-136.pdf
                # Cf. https://stackoverflow.com/a/3034155/10504393
                $buffer = New-Object -TypeName byte[] -ArgumentList (256KB)
                $target_stream = [System.IO.File]::Create($Filepath, (256KB), [System.IO.FileOptions]::SequentialScan)

                $timer = New-Object -TypeName timers.timer
                $timer.Interval = 1000 # Update progress every second
                $timer_event = Register-ObjectEvent -InputObject $timer -EventName Elapsed -Action {
                    $Global:update_progress = $true
                }
                $timer.Start()

                do {
                    $count = $response_stream.Read($buffer, 0, $buffer.length)
                    $target_stream.Write($buffer, 0, $count)
                    $downloaded_bytes = $downloaded_bytes + $count

                    if ($Global:update_progress) {
                        $percent = $downloaded_bytes / $total_bytes
                        $status = @{
                            completed  = "{0,6:p2} Completed" -f $percent
                            downloaded = "{0:n0} MB of {1:n0} MB" -f ($downloaded_bytes / 1MB), ($total_bytes / 1MB)
                            speed      = "{0,7:n0} KB/s" -f (($downloaded_bytes - $prev_downloaded_bytes) / 1KB)
                            eta        = "eta {0:hh\:mm\:ss}" -f (New-TimeSpan -Seconds (($total_bytes - $downloaded_bytes) / ($downloaded_bytes - $prev_downloaded_bytes)))
                        }
                        $progress_args = @{
                            Activity        = "Downloading $URL"
                            Status          = "$($status.completed) ($($status.downloaded)) $($status.speed) $($status.eta)"
                            PercentComplete = $percent * 100
                        }
                        Write-Progress @progress_args

                        $prev_downloaded_bytes = $downloaded_bytes
                        $Global:update_progress = $false
                    }
                } while ($count -gt 0)
                Write-Progress -Completed -Activity "Downloading $URL"
            }
            finally {
                if ($timer) { $timer.Stop() }
                if ($timer_event) { Unregister-Event -SubscriptionId $timer_event.Id }
                if ($target_stream) { $target_stream.Dispose() }
                # If file exists and $count is not zero or $null, than script was interrupted by user
                if ((Test-Path $Filepath) -and $count) { Remove-Item -Path $Filepath }
            }
        }
        finally {
            if ($response) { $response.Dispose() }
            if ($response_stream) { $response_stream.Dispose() }
        }
    }
}


<#
 .Synopsis
  Gets a cacher object, so you can use Get() or to see when the cache was last updated.

 .Description
  Gets a cacher object with the parameters.
  Cacher objects allow you to always have an updated copy of a file by only downloading it when the Last-Modified header from the webserver changes.
  Creates a file along with the file it downloaded named like this: $FileName-CacheData.json

 .Parameter FileURL
  The URL to download from

 .Parameter FileName
  The name of the file with extension you would like to download.

 .Parameter BaseDir
  The directory you would like the file downloaded into

#>
function Get-Cacher {
    param (
        [Alias('Name')]
        [Parameter(Mandatory)]
        [string]$FileName,

        [Alias('URL')]
        [Parameter(Mandatory)]
        [string]$FileURL,

        [Alias('Dir')]
        [Parameter(Mandatory)]
        [string]$BaseDir
    )
    return [Cacher]::new($FileName, $FileURL, $BaseDir)
}

<#
 .Synopsis
  Gets the path to the cached file. If the file does not exist or the cached version is older it is downloaded.

 .Description
  Makes sure that the file given by the parameters is up to date, downloading the updated version if necessary, and returning the FileInfo for it.
  Creates a file along with the file it downloaded named like this: $FileName-CacheData.json

 .Outputs
  System.IO.FileInfo

 .Parameter FileURL
  The URL to download from

 .Parameter FileName
  The name of the file with extension you would like to download.

 .Parameter BaseDir
  The directory you would like the file downloaded into

 .Example
  Get-CachedFile -Name "test.pdf" -URL "https://www.microsoft.com/en-us/research/wp-content/uploads/2004/12/tr-2004-136.pdf" -Dir "$env:TEMP"

#>
function Get-CachedFile {
    param (
        [Alias('Name')]
        [Parameter(Mandatory)]
        [string]$FileName,

        [Alias('URL')]
        [Parameter(Mandatory)]
        [string]$FileURL,

        [Alias('Dir')]
        [Parameter(Mandatory)]
        [string]$BaseDir
    )
    return (Get-Cacher -Name $FileName -URL $FileURL -Dir $BaseDir).Get()
}

Export-ModuleMember -Function Get-FileFromURL, Get-Cacher, Get-CachedFile
