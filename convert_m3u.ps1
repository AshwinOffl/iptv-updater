# Define file paths (relative to repo root)
$m3uFile = "input.m3u"
$outputFile = "output.m3u"

# Read the input M3U file
try {
    $m3uContent = Get-Content -Path $m3uFile -ErrorAction Stop
} catch {
    Write-Error "Failed to read input file $m3uFile : $_"
    exit 1
}

$outputM3u = "#EXTM3U`n"
$lastExtinf = ""

foreach ($line in $m3uContent) {
    $line = $line.Trim()

    # Store EXTINF line for channel name and attributes
    if ($line -match "^#EXTINF:-?\d*(.+),(.+)$") {
        $lastExtinf = $line
        $outputM3u += "$line`n"
        continue
    }

    # Keep non-play.php lines as-is
    if ($line -notmatch "play\.php\?id=") {
        $outputM3u += "$line`n"
        continue
    }

    # Process play.php URLs
    if ($line -match "^http://max4kk-us-rkdyiptv\.wasmer\.app/play\.php\?id=(\d+)$") {
        $url = $line
        $id = $matches[1]
        $channelName = if ($lastExtinf -match ",(.+)$") { $matches[1] } else { "Unknown_$id" }

        try {
            # Use curl to handle redirects and capture headers/content (Linux)
            $curlCommand = "curl -L -k -v --max-redirs 10 --connect-timeout 15 -H 'User-Agent: Mozilla/5.0 (X11; Linux x86_64) Chrome/117.0.0.0 Safari/537.36' -H 'Accept: */*' -H 'Referer: http://max4kk-us-rkdyiptv.wasmer.app/' '$url'"

            # Capture verbose output and content
            $verboseOutput = & bash -c $curlCommand 2>&1
            $content = $verboseOutput | Where-Object { $_ -notmatch "^[<>]\s" } | Out-String
            $headers = $verboseOutput | Where-Object { $_ -match "^[<>]\s" } | Out-String

            Write-Host ("ID {0}: Headers:`n{1}" -f $id, $headers)

            # Find redirect URL
            $redirectUrl = $verboseOutput | Where-Object { $_ -match "^>\s*Location:\s*(.+)$" } | ForEach-Object { $matches[1] } | Select-Object -Last 1
            if (-not $redirectUrl) {
                $redirectUrl = $verboseOutput | Where-Object { $_ -match "^\*\s*Issue another request to this URL: '(.+)'$" } | ForEach-Object { $matches[1] } | Select-Object -Last 1
            }
            if (-not $redirectUrl) {
                throw "No redirect URL found in response"
            }

            Write-Host ("ID {0}: Redirect URL: {1}" -f $id, $redirectUrl)

            # Check if redirect URL is an .m3u8
            if ($redirectUrl -match "\.m3u8\?token=.+$") {
                $contentLines = $content -split "`n"
                $relativePath = $contentLines | Where-Object { $_ -match "^[^#].*tracks-v1a1/mono\.m3u8\?token=.+" } | Select-Object -First 1
                if ($relativePath) {
                    $redirectBase = $redirectUrl -replace "(index\.m3u8\?token=.+)$", ""
                    $streamUrl = "$redirectBase$relativePath".Trim()
                    $outputM3u += "#EXTINF:-1$($lastExtinf -replace ',.*$', ''),$channelName`n$streamUrl`n"
                    Write-Host ("ID {0}: Stream URL: {1}" -f $id, $streamUrl)
                } else {
                    Write-Warning ("ID {0}: No tracks-v1a1/mono.m3u8 path found, using redirect URL" -f $id)
                    $outputM3u += "#EXTINF:-1$($lastExtinf -replace ',.*$', ''),$channelName`n$redirectUrl`n"
                }
            } else {
                Write-Warning ("ID {0}: Redirect URL is not an .m3u8: {1}" -f $id, $redirectUrl)
                $outputM3u += "#EXTINF:-1$($lastExtinf -replace ',.*$', ''),$channelName`n$url`n"
            }
        } catch {
            Write-Error ("Failed to process ID {0} at {1} : {2}" -f $id, $url, $_)
            $outputM3u += "#EXTINF:-1$($lastExtinf -replace ',.*$', ''),$channelName`n$url`n"
        }
    } else {
        $outputM3u += "$line`n"
    }
}

# Save the new M3U file with UTF-8 BOM
try {
    $utf8Bom = New-Object System.Text.UTF8Encoding($true)
    [IO.File]::WriteAllText($outputFile, $outputM3u, $utf8Bom)
    Write-Host "✅ New M3U file saved to $outputFile"
} catch {
    Write-Error "Failed to write output file $outputFile : $_"
    exit 1
}
