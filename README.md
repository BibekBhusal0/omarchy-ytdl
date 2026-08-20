# Omarchy Shell Plugin for yt-dlp

A YouTube video downloader for the Omarchy bar.

https://github.com/user-attachments/assets/8a63333c-689c-4793-9ed7-804d2df5b888

## Features

- **Parallel downloads**: Download up to three videos at once, with live progress
- **Clipboard detection**: Copy a YouTube link and it is detected automatically in the panel
- **History**: Past downloads are kept for easy replay

## Requirements

- Omarchy quattro
- yt-dlp (auto-installed from the panel if missing)
- wl-clipboard (preinstalled on Omarchy) for clipboard detection
- jq (preinstalled on Omarchy)
- sqlite3 (preinstalled on Omarchy), only for cookie export from Firefox-based browsers (zen, glide)

## Install

```bash
omarchy plugin add https://github.com/BibekBhusal0/omarchy-ytdl.git --enable
```

## Usage

Click the bar widget to open the panel. Copy a YouTube link and it is pasted into the input; pick a quality and press the download button (or Enter). Bind it to a key in `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER", "Y", "exec, omarchy-shell shell summon bibek.ytdl")
```

## Configuration

Options go under the plugin entry in `~/.config/omarchy/shell.json`:

```json
{
  "id": "bibek.ytdl",
  "downloadLocation": "~/Downloads/yt-dlp",
  "defaultQuality": "1080p",
  "cookiesBrowser": "none",
  "extraArgs": ""
}
```

| Setting            | Default              | Options                                                           |
| ------------------ | -------------------- | ----------------------------------------------------------------- |
| `downloadLocation` | `~/Downloads/yt-dlp` | Any directory path                                                |
| `defaultQuality`   | `1080p`              | `best`, `1080p`, `720p`, `480p`                                   |
| `cookiesBrowser`   | `none`               | `none`, `firefox`, `chromium`, `chrome`, `zen`, `helium`, `glide` |
| `extraArgs`        | (empty)              | Any yt-dlp flags, e.g. `--cookies-from-browser chromium`          |
| `enableHistory`    | `true`               | `true`, `false`                                                   |

### Fixing YouTube bot detection

If yt-dlp fails with "Sign in to confirm you're not a bot", log into YouTube in your browser and set `cookiesBrowser` to that browser. Cookies are only exported on demand: every download first tries without cookies and only retries with `--cookies-from-browser` if the bot check appears.

For fine-grained control, set `extraArgs` directly (e.g. `--cookies-from-browser chromium`).

## Troubleshooting

If a download fails, test yt-dlp directly in the terminal first:

```bash
yt-dlp -f "b[height<=1080]/b" "https://www.youtube.com/watch?v=..."
```

- If the yt-dlp CLI fails, report it upstream at https://github.com/yt-dlp/yt-dlp/issues or ask on the yt-dlp Discord (https://discord.gg/H5MNcFW63r).
- If the CLI works with different arguments, set them in the `extraArgs` setting above.
- Only if the CLI works but the widget does not, open an issue in this repository.

## Uninstall

```bash
omarchy plugin remove bibek.ytdl
```

## Credits

Download and panel logic based on the [omarchy-aria2](https://github.com/rawritude/omarchy-aria2) reference plugin (MIT).

Cookie export follows the [yt-dlp docs on exporting YouTube cookies](https://github.com/yt-dlp/yt-dlp/wiki/Extractors#exporting-youtube-cookies) (Unlicense).

This plugin is licensed under the [MIT License](LICENSE).

## Others

Here are my other Omarchy plugins:

- [Focusd](https://github.com/BibekBhusal0/omarchy-focusd) - pomodoro timer with streak, history and daily goal
- [Obsidian Search](https://github.com/BibekBhusal0/omarchy-obsidian-search) - fuzzy-search your Obsidian vault
- [Readest](https://github.com/BibekBhusal0/omarchy-readest) - fuzzy-search your Readest library

Please give a star if you find them useful!
