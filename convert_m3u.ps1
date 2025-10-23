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
$lastChannelName = ""
$lastGroupTitle = ""

foreach ($line in $m3uContent) {
    $line = $line.Trim()

    # Capture EXTINF line for channel name and group-title
    if ($line -match "^#EXTINF:-?\d+.*group-title=""([^""]*)""[^,]*,(.+)$") {
        $lastGroupTitle = $matches[1]
        $lastChannelName = $matches[2]
        $outputM3u += "$line`n"
        continue
    } elseif ($line -match "^#EXTINF:-?\d*,(.+)$") {
        $lastChannelName = $matches[1]
        $lastGroupTitle = ""
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
        $channelName = if ($lastChannelName) { $lastChannelName } else { "Unknown_$id" }

        try {
            # Use Windows curl.exe
            $curlCommand = "curl.exe -L -k -v --max-redirs 10 --connect-timeout 15 " +
                           "-H `"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36 (KHTML, like Gecko) Chrome/117.0.0.0 Safari/537.36`" " +
                           "-H `"Accept: */*`" " +
                           "-H `"Referer: http://max4kk-us-rkdyiptv.wasmer.app/`" `"$url`""

            $verboseOutput = & cmd /c $curlCommand 2>&1
            $content = $verboseOutput | Where-Object { $_ -notmatch "^[<>]\s" } | Out-String

            # Extract last Location header
            $redirectUrl = $verboseOutput | Where-Object { $_ -match "^>\s*Location:\s*(.+)$" } |
                           ForEach-Object { $matches[1] } | Select-Object -Last 1

            if (-not $redirectUrl) {
                throw "No redirect URL found"
            }

            # Check for .m3u8 and relative paths
            if ($redirectUrl -match "\.m3u8\?token=.+$") {
                $contentLines = $content -split "`n"
                $relativePath = $contentLines | Where-Object { $_ -match "^[^#].*tracks-v1a1/mono\.m3u8\?token=.+" } | Select-Object -First 1
                if ($relativePath) {
                    $redirectBase = $redirectUrl -replace "(index\.m3u8\?token=.+)$", ""
                    $streamUrl = "$redirectBase$relativePath".Trim()
                } else {
                    $streamUrl = $redirectUrl
                }

                # Output with group-title if exists
                if ($lastGroupTitle) {
                    $outputM3u += "#EXTINF:-1 group-title=""$lastGroupTitle"",$channelName`n$streamUrl`n"
                } else {
                    $outputM3u += "#EXTINF:-1,$channelName`n$streamUrl`n"
                }

            } else {
                # fallback
                if ($lastGroupTitle) {
                    $outputM3u += "#EXTINF:-1 group-title=""$lastGroupTitle"",$channelName`n$url`n"
                } else {
                    $outputM3u += "#EXTINF:-1,$channelName`n$url`n"
                }
            }
        } catch {
            Write-Warning ("ID {0}: Failed to process URL {1}, using original" -f $id, $url)
            if ($lastGroupTitle) {
                $outputM3u += "#EXTINF:-1 group-title=""$lastGroupTitle"",$channelName`n$url`n"
            } else {
                $outputM3u += "#EXTINF:-1,$channelName`n$url`n"
            }
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
