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
    SOURCE="clipboard"
    CLIP=$(wl-paste --no-newline 2>/dev/null)
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

# Get current ytdl state to check if video is already busy
STATE=$(omarchy shell ytdl state 2>/dev/null)
if [ -n "$STATE" ]; then
    # Extract video ID from URL
    VIDEO_ID=$(echo "$URL" | grep -oP '(?:v=|youtu\.be/|shorts/)([\w-]{11})' | tail -1 | cut -d'/' -f2 | cut -d'=' -f2)
    
    if [ -n "$VIDEO_ID" ]; then
        # Check if this video is already downloading, queued, or in history as "done"
        IS_DOWNLOADING=$(echo "$STATE" | jq -r --arg vid "$VIDEO_ID" '.downloads[] | select(.url | contains($vid)) | select(.status == "downloading" or .status == "queued") | .status' | head -1)
        IS_DONE=$(echo "$STATE" | jq -r --arg vid "$VIDEO_ID" '.history[] | select(.url | contains($vid)) | select(.status == "done") | .status' | head -1)
        
        if [ "$IS_DOWNLOADING" = "downloading" ]; then
            if [ -n "$TITLE" ]; then
                notify-send -a "yt-dlp" "Download in progress" "$TITLE"
            else
                notify-send -a "yt-dlp" "Download in progress" "Video is already being downloaded"
            fi
            exit 0
        elif [ "$IS_DOWNLOADING" = "queued" ]; then
            if [ -n "$TITLE" ]; then
                notify-send -a "yt-dlp" "Video in queue" "$TITLE"
            else
                notify-send -a "yt-dlp" "Video in queue" "Video is already queued for download"
            fi
            exit 0
        elif [ "$IS_DONE" = "done" ]; then
            if [ -n "$TITLE" ]; then
                notify-send -a "yt-dlp" "Already downloaded" "$TITLE"
            else
                notify-send -a "yt-dlp" "Already downloaded" "Video is already in your downloads"
            fi
            exit 0
        fi
    fi
fi

# Start the download
if [ -n "$TITLE" ]; then
    notify-send -a "yt-dlp" "Downloading video" "$TITLE (from $SOURCE)"
else
    notify-send -a "yt-dlp" "Downloading video" "(from $SOURCE)"
fi

omarchy shell ytdl start "$URL"
