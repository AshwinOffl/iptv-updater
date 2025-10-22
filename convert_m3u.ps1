# Read the input M3U file
$m3uContent = Get-Content -Path "C:\Users\Ashwi\input.m3u"
$outputM3u = "#EXTM3U`n"
$lastExtinf = ""

foreach ($line in $m3uContent) {
    # Store EXTINF line for channel name
    if ($line -match "^#EXTINF:-1,(.+)$") {
        $lastExtinf = $matches[1]
        $outputM3u += "$line`n"
        continue
    }

    # Keep non-play.php lines as-is (e.g., Telegram link)
    if ($line -notmatch "play\.php\?id=") {
        $outputM3u += "$line`n"
        continue
    }

    # Process play.php URLs
    if ($line -match "^http://max4kk-us-rkdyiptv\.wasmer\.app/play\.php\?id=(\d+)$") {
        $url = $line
        $id = $matches[1]
        $channelName = if ($lastExtinf) { $lastExtinf } else { "Unknown" }

        # Run curl to get the stream URL
        $verboseOutput = curl.exe -L -k -v $url 2>&1
        $output = curl.exe -L -k $url

        # Find the redirected .m3u8 URL in verbose output
        $redirectUrl = $verboseOutput | Where-Object { $_ -match "location: (http://[^ ]+\.m3u8\?token=[^ ]+)" } | ForEach-Object { $matches[1] }
        if (-not $redirectUrl) {
            Write-Host "Failed to get redirect for ID $id"
            $outputM3u += "#EXTINF:-1,$channelName`n$url`n"  # Fallback to original URL
            continue
        }

        # Get the relative path from the output
        $relativePath = $output | Where-Object { $_ -match "^tracks-v1a1/mono\.m3u8\?token=.+" }
        if ($relativePath) {
            # Combine redirect domain with relative path
            $redirectBase = $redirectUrl -replace "(index\.m3u8\?token=.+)$", ""
            $streamUrl = "$redirectBase$relativePath"
            $outputM3u += "#EXTINF:-1,$channelName`n$streamUrl`n"
        } else {
            Write-Host "Failed to get relative path for ID $id"
            $outputM3u += "#EXTINF:-1,$channelName`n$redirectUrl`n"  # Use index.m3u8 as fallback
        }
    }
}

# Save the new M3U file
$outputM3u | Out-File -FilePath "C:\Users\Ashwi\output.m3u" -Encoding UTF8
Write-Host "New M3U file saved to C:\Users\Ashwi\output.m3u"