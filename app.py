from flask import Flask, request, redirect, Response
import requests
import re
import urllib3

# Suppress InsecureRequestWarning
urllib3.disable_warnings(urllib3.exceptions.InsecureRequestWarning)

app = Flask(__name__)

# Read input.m3u
def load_m3u():
    try:
        with open("input.m3u", "r", encoding="utf-8") as f:
            lines = f.readlines()
        m3u_data = []
        last_extinf = ""
        for line in lines:
            if line.startswith("#EXTINF:-1,"):
                last_extinf = line.split(",", 1)[1].strip()
                m3u_data.append(line)
            elif line.strip() and not line.startswith("#"):
                match = re.match(r"http://max4kk-us-rkdyiptv\.wasmer\.app/play\.php\?id=(\d+)$", line.strip())
                if match:
                    m3u_data.append({"id": match.group(1), "extinf": last_extinf, "url": line.strip()})
                else:
                    m3u_data.append(line)
        return m3u_data
    except Exception as e:
        print(f"Error reading input.m3u: {e}")
        return []

# /stream endpoint: Fetch fresh .m3u8 URL
@app.route('/stream')
def get_stream():
    channel_id = request.args.get('id')
    if not channel_id:
        return "Missing id parameter", 400

    url = f"http://max4kk-us-rkdyiptv.wasmer.app/play.php?id={channel_id}"
    try:
        headers = {"User-Agent": "Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36"}
        response = requests.get(url, headers=headers, verify=False, allow_redirects=True)
        redirect_url = next((h.headers["location"] for h in response.history if ".m3u8?token=" in h.headers.get("location", "")), None)
        if not redirect_url:
            print(f"No redirect for ID {channel_id}")
            return "Failed to get redirect", 500
        playlist = response.text
        relative_path = next((l for l in playlist.splitlines() if l.startswith("tracks-v1a1/mono.m3u8?token=")), None)
        if not relative_path:
            print(f"No relative path for ID {channel_id}")
            return "Failed to get relative path", 500
        stream_url = f"{redirect_url.split('index.m3u8')[0]}{relative_path}"
        # Add FFmpeg wrapper headers for TV apps
        response = redirect(stream_url)
        response.headers['X-KODI-Prop'] = 'inputstream=inputstream.ffmpegdirect,ManifestType=HLS'
        return response
    except Exception as e:
        print(f"Error for ID {channel_id}: {e}")
        return f"Error: {str(e)}", 500

# /playlist endpoint: Serve M3U with API URLs
@app.route('/playlist')
def get_playlist():
    m3u_data = load_m3u()
    base_url = f"{request.scheme}://{request.host}"
    output = "#EXTM3U\n"
    for item in m3u_data:
        if isinstance(item, str):
            output += item
        else:
            output += f"#EXTINF:-1 tvg-id=\"{item['id']}\" http-user-agent=\"Mozilla/5.0 (Windows NT 10.0; Win64; x64) AppleWebKit/537.36\",{item['extinf']}\n"
            output += "#KODIPROP:inputstream=inputstream.ffmpegdirect\n"
            output += "#KODIPROP:inputstream.ffmpegdirect.ManifestType=HLS\n"
            output += f"{base_url}/stream?id={item['id']}\n"
    return Response(output, mimetype='audio/mpegurl')

if __name__ == '__main__':
    app.run(debug=True)