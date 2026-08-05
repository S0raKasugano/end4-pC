#!/usr/bin/env python3
import sys
import urllib.request
import urllib.parse
import json

import re

def parse_line_to_words(line_text, line_duration, line_start_time):
    elrc_pattern = r'<(\d{2}):(\d{2}\.\d{2,3})>'
    matches = list(re.finditer(elrc_pattern, line_text))
    
    words = []
    if matches:
        for i in range(len(matches)):
            m = matches[i]
            mins, secs = m.groups()
            time_sec = int(mins) * 60 + float(secs)
            
            start_idx = m.end()
            end_idx = matches[i+1].start() if i + 1 < len(matches) else len(line_text)
            text = line_text[start_idx:end_idx]
            
            if i + 1 < len(matches):
                next_mins, next_secs = matches[i+1].groups()
                next_time_sec = int(next_mins) * 60 + float(next_secs)
                duration = next_time_sec - time_sec
            else:
                duration = 0.5
                
            # Cap duration for character flow so it doesn't crawl during long gaps
            max_duration = len(text.strip()) * 0.1 # 100ms per character
            if duration > max_duration + 0.2:
                duration = max_duration
                
            words.append({
                "text": text,
                "startTime": (time_sec - line_start_time) * 1000,
                "duration": duration * 1000
            })
    else:
        parts = re.split(r'(\s+)', line_text)
        words_raw = []
        current = ""
        for p in parts:
            if p.strip() == "":
                current += p
                words_raw.append(current)
                current = ""
            else:
                current += p
        if current:
            words_raw.append(current)
            
        total_chars = sum(len(w.strip()) for w in words_raw)
        if total_chars == 0:
            return words
            
        # Realistic singing speed: ~100ms per character (approx 10 chars per second). 
        # We don't want to stretch a 3-second phrase over a 15-second gap.
        actual_sing_time = min(line_duration * 1000, total_chars * 100.0)
            
        for w in words_raw:
            char_count = len(w.strip())
            if char_count == 0:
                continue
            ratio = char_count / total_chars
            words.append({
                "text": w,
                "duration": actual_sing_time * ratio
            })
            
    start_time = 0
    for w in words:
        w["startTime"] = start_time
        start_time += w["duration"]
        
    return words

def _parse_lrc(lrc_text: str) -> list:
    lines = []
    for raw in lrc_text.splitlines():
        raw = raw.strip()
        if not raw:
            continue
        try:
            tag_end = raw.index("]")
            time_str = raw[1:tag_end]
            text = raw[tag_end + 1:].strip()
            mins, secs = time_str.split(":")
            timestamp = int(mins) * 60 + float(secs)
            lines.append({"time": timestamp, "text": text})
        except Exception:
            continue
            
    lines = sorted(lines, key=lambda x: x["time"])
    
    for i in range(len(lines)):
        if i + 1 < len(lines):
            line_duration = lines[i+1]["time"] - lines[i]["time"]
        else:
            line_duration = 5.0
            
        lines[i]["duration"] = line_duration * 1000
        clean_text = re.sub(r'<[^>]+>', '', lines[i]["text"])
        lines[i]["words"] = parse_line_to_words(lines[i]["text"], line_duration, lines[i]["time"])
        if lines[i]["words"]:
            last_word = lines[i]["words"][-1]
            total_word_time = last_word["startTime"] + last_word["duration"]
            if total_word_time > lines[i]["duration"]:
                lines[i]["duration"] = total_word_time
        lines[i]["text"] = clean_text
        
    return lines

def _is_match(d: dict, title: str, artist: str) -> bool:
    if not d.get("syncedLyrics"):
        return False
    r_title  = (d.get("trackName")  or "").lower()
    r_artist = (d.get("artistName") or "").lower()
    t = title.lower()
    a = artist.lower()
    title_match = (t in r_title or r_title in t or
                   any(word in r_title for word in t.split() if len(word) > 3))
    artist_match = (a in r_artist or r_artist in a or
                    any(word in r_artist for word in a.split() if len(word) > 3))
    return title_match and artist_match

def fetch_lrclib(title: str, artist: str, duration: float) -> list:
    urls = [
        f"https://lrclib.net/api/get?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}&duration={int(duration)}",
        f"https://lrclib.net/api/search?track_name={urllib.parse.quote(title)}&artist_name={urllib.parse.quote(artist)}",
        f"https://lrclib.net/api/search?q={urllib.parse.quote(title + ' ' + artist)}",
    ]
    for url in urls:
        try:
            with urllib.request.urlopen(url, timeout=15) as r:
                data = json.loads(r.read().decode())
            if isinstance(data, list):
                data = next((d for d in data if _is_match(d, title, artist)), None)
            if data and _is_match(data, title, artist):
                lines = _parse_lrc(data["syncedLyrics"])
                if lines:
                    return lines
        except Exception:
            continue
    return []

def fetch_lyricsplus(title: str, artist: str, duration: float) -> list:
    urls = [
        f"https://lyricsplus.prjktla.my.id/v2/lyrics/get?title={urllib.parse.quote(title)}&artist={urllib.parse.quote(artist)}",
        f"https://lyricsplus.binimum.org/v2/lyrics/get?title={urllib.parse.quote(title)}&artist={urllib.parse.quote(artist)}"
    ]
    for url in urls:
        try:
            req = urllib.request.Request(url, headers={'User-Agent': 'Mozilla/5.0'})
            with urllib.request.urlopen(req, timeout=10) as r:
                data = json.loads(r.read().decode())
            
            items = []
            if isinstance(data, dict):
                if "data" in data and isinstance(data["data"], list):
                    items = data["data"]
                else:
                    items = [data]
            elif isinstance(data, list):
                items = data
                
            for item in items:
                lrc = item.get("synced") or item.get("lrc") or item.get("syncedLyrics")
                if lrc:
                    lines = _parse_lrc(lrc)
                    if lines:
                        return lines
        except Exception:
            continue
    return []

def fetch_unison(title: str, artist: str, duration: float) -> list:
    # Unison API requires authenticated client headers or is often self-hosted.
    # Returns empty for now to act as a safe stub if specified in priority list.
    return []

def main():
    if len(sys.argv) < 4:
        print("no_info", flush=True)
        sys.exit(0)
    title    = sys.argv[1]
    artist   = sys.argv[2]
    duration = float(sys.argv[3])
    
    providers_arg = "lrclib,lyricsplus,unison"
    if len(sys.argv) >= 5:
        providers_arg = sys.argv[4]
        
    providers = [p.strip().lower() for p in providers_arg.split(",") if p.strip()]
    if not providers:
        providers = ["lrclib", "lyricsplus", "unison"]
    
    lines = []
    for provider in providers:
        if provider == "lrclib":
            lines = fetch_lrclib(title, artist, duration)
        elif provider == "lyricsplus":
            lines = fetch_lyricsplus(title, artist, duration)
        elif provider == "unison":
            lines = fetch_unison(title, artist, duration)
            
        if lines:
            break

    if not lines:
        print("not_found", flush=True)
        sys.exit(0)
    print(json.dumps(lines), flush=True)

if __name__ == "__main__":
    main()