#!/bin/bash
# Auto-download YouTube video from MPRIS or clipboard
# Detects URL then calls shell to handle the download
# Usage: auto-download.sh

SCRIPT_DIR="$(dirname "$0")"

is_youtube_url() {
    echo "$1" | grep -q "youtube.com/watch\|youtu\.be/\|youtube.com/shorts/"
}

# Detect URL from MPRIS first
DETECTED=$("$SCRIPT_DIR/detect-url-mpri" | head -1)
URL=$(echo "$DETECTED" | jq -r '.url // empty' 2>/dev/null)
TITLE=$(echo "$DETECTED" | jq -r '.title // empty' 2>/dev/null)
SOURCE="browser"

# Fallback: check clipboard
if [ -z "$URL" ]; then
    SOURCE="clipboard"    CLIP=$(wl-paste --no-newline 2>/dev/null)
    if [ -n "$CLIP" ] && is_youtube_url "$CLIP"; then
        URL=$(echo "$CLIP" | grep -o 'https\?://[^\s]*')
    fi
fi

if [ -z "$URL" ]; then
    notify-send -a "yt-dlp" "No YouTube video found" "Nothing playing or in clipboard"
    exit 1
fi

# Clipboard URLs have no title yet; fetch it from yt-dlp
if [ -z "$TITLE" ] || [ "$TITLE" = "null" ]; then
    TITLE=$(yt-dlp --no-download --print "%(title)s" --skip-download "$URL" 2>/dev/null | head -1)
fi

if [ -n "$TITLE" ]; then
    notify-send -a "yt-dlp" "Downloading video" "$TITLE (from $SOURCE)"
else
    notify-send -a "yt-dlp" "Downloading video" "(from $SOURCE)"
fi

omarchy shell ytdl start "$URL"
