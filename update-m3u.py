import requests
import re
import time

# Read input M3U
with open("input.m3u", "r", encoding="utf-8") as f:
    lines = f.readlines()

output_m3u = "#EXTM3U\n"
last_extinf = ""

for line in lines:
    if line.startswith("#EXTINF:-1,"):
        last_extinf = line.split(",", 1)[1].strip()
        output_m3u += line
        continue
    if "play.php?id=" not in line:
        output_m3u += line
        continue
    match = re.match(r"http://max4kk-us-rkdyiptv\.wasmer\.app/play\.php\?id=(\d+)$", line.strip())
    if match:
        url = line.strip()
        id = match.group(1)
        channel_name = last_extinf if last_extinf else "Unknown"
        try:
            # Follow redirects with User-Agent
            headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
            response = requests.get(url, headers=headers, verify=False, allow_redirects=True)
            # Find redirect URL in history
            redirect_url = next((h.headers["location"] for h in response.history if ".m3u8?token=" in h.headers.get("location", "")), None)
            if not redirect_url:
                print(f"Failed to get redirect for ID {id}")
                output_m3u += f"#EXTINF:-1,{channel_name}\n{url}\n"
                continue
            # Get playlist content
            playlist = response.text
            relative_path = next((l for l in playlist.splitlines() if l.startswith("tracks-v1a1/mono.m3u8?token=")), None)
            if relative_path:
                redirect_base = redirect_url.split("index.m3u8")[0]
                stream_url = f"{redirect_base}{relative_path}"
                # Add FFmpeg wrapper for TV app compatibility
                output_m3u += f"#EXTINF:-1,{channel_name}\n#KODIPROP:inputstream=inputstream.ffmpegdirect\n#KODIPROP:inputstream.ffmpegdirect.ManifestType=HLS\npipe://ffmpeg -headers \"User-Agent: Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\" -i \"{stream_url}\" -c copy -f flv pipe:\n"
            else:
                print(f"Failed to get relative path for ID {id}")
                output_m3u += f"#EXTINF:-1,{channel_name}\n{redirect_url}\n"
            time.sleep(2)  # Avoid rate-limiting
        except Exception as e:
            print(f"Error for ID {id}: {e}")
            output_m3u += f"#EXTINF:-1,{channel_name}\n{url}\n"

# Save output M3U
with open("output.m3u", "w", encoding="utf-8") as f:
    f.write(output_m3u)
print("Updated output.m3u")
