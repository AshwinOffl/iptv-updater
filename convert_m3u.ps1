# Define file paths
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
        $lastExtinf = $line  # Store full EXTINF line
        $channelName = $matches[2]
        $tvgId = if ($lastExtinf -match 'tvg-id="([^"]+)"') { $matches[1] } else { "Unknown" }
        continue
    }

    # Process play.php URLs
    if ($line -match "^http://max4kk-us-rkdyiptv\.wasmer\.app/play\.php\?id=(\d+)$") {
        $url = $line
        $id = $matches[1]
        $channelName = if ($lastExtinf -match ",(.+)$") { $matches[1] } else { "Unknown_$id" }

        try {
            # Use curl to handle redirects
            $curlCommand = "curl -L -k -v --max-redirs 10 --connect-timeout 15 -H 'User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36' -H 'Accept: */*' -H 'Referer: http://max4kk-us-rkdyiptv.wasmer.app/' '$url'"
            $verboseOutput = & bash -c $curlCommand 2>&1
            $content = $verboseOutput | Where-Object { $_ -notmatch "^[<>]\s" } | Out-String

            # Find redirect URL
            $redirectUrl = $verboseOutput | Where-Object { $_ -match "^>\s*Location:\s*(.+)$" } | ForEach-Object { $matches[1] } | Select-Object -Last 1
            if (-not $redirectUrl) {
                $redirectUrl = $verboseOutput | Where-Object { $_ -match "^\*\s*Issue another request to this URL: '(.+)'$" } | ForEach-Object { $matches[1] } | Select-Object -Last 1
            }
            if (-not $redirectUrl) {
                throw "No redirect URL found in response"
            }

            # Check for .m3u8 URL
            if ($redirectUrl -match "\.m3u8\?token=.+$") {
                # Look for relative path like tracks-v1a1/mono.m3u8
                $contentLines = $content -split "`n"
                $relativePath = $contentLines | Where-Object { $_ -match "^[^#].*tracks-v1a1/mono\.m3u8\?token=.+" } | Select-Object -First 1
                if ($relativePath) {
                    $redirectBase = $redirectUrl -replace "(index\.m3u8\?token=.+)$", ""
                    $streamUrl = "$redirectBase$relativePath".Trim()
                    $outputM3u += "#EXTINF:-1 tvg-id=`"$tvgId`", $channelName`n$streamUrl`n"
                } else {
                    $outputM3u += "#EXTINF:-1 tvg-id=`"$tvgId`", $channelName`n$redirectUrl`n"
                }
            } else {
                Write-Warning ("ID {0}: Redirect URL is not an .m3u8: {1}" -f $id, $redirectUrl)
                $outputM3u += "#EXTINF:-1 tvg-id=`"$tvgId`", $channelName`n$redirectUrl`n"
            }
        } catch {
            Write-Error ("Failed to process ID {0} at {1} : {2}" -f $id, $url, $_)
            $outputM3u += "#EXTINF:-1 tvg-id=`"$tvgId`", $channelName`n$url`n"  # Fallback to original
        }
    } else {
        $outputM3u += "$line`n"  # Keep unmatched URLs
    }
}

# Save the new M3U file with UTF-8 BOM
try {
    Set-Content -Path $outputFile -Value $outputM3u -Encoding UTF8BOM
    Write-Host "New M3U file saved to $outputFile"
} catch {
    Write-Error "Failed to write output file $outputFile : $_"
    exit 1
}