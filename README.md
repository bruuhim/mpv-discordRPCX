<h1 align="center">
  mpv-discordRPCX
</h1>

<h4 align="center">
An mpv plugin for displaying currently playing media on Discord
<br />
Forked from <a href="https://github.com/cniw/mpv-discordRPC">mpv-discordRPC</a>
</h4>

<p align="center">
  <a href="#credits">Credits</a> •
  <a href="#key-features">Key Features</a> •
  <a href="#how-to-use">How To Use</a> •
  <a href="#configuration">Configuration</a> •
  <a href="#license">License</a>
</p>

<p align="center">
  <img src="/images/discordRPC_example.png" width=300 hspace="10">
  <img src="/images/discordRPC_blackswan.png" width=400 hspace="10">
</p>

## Credits

This project is a fork of [ujjwal-dev23/mpv-discordRPC](https://github.com/ujjwal-dev23), the original author who developed the core codebase and maintained the plugin after forking from [cniw/mpv-discordRPC](https://github.com/cniw/mpv-discordRPC).

**Bruuhim (Maintainer):** Performed major modifications and improvements, including:

- **Automatic Anime Title Detection:** Extracts and cleans anime titles from parent folder names for accurate API lookups.
- **Episode Extraction:** Reliably parses episode numbers and titles from video filenames (e.g., "03 - Everyday Life Under Dangerous Circumstances").
- **Enhanced Cover Art:** Improved fetching of official anime posters via Jikan API metadata, prioritizing anime-matched images.
- **Debug Logging:** Added comprehensive terminal output for troubleshooting extraction and API calls.
- **Stability Fixes:** Resolved Lua pattern matching errors and enhanced script reliability.

**Changelog:**
- v1.4.2: Lua pattern fixes, debug logging, improved anime detection (2023-2025).
- v1.4.1: Original release by ujjwal-dev23 with initial anime scraping.
- Initial: Based on cniw's plugin.

For feature requests or issues, please open a GitHub issue on this repository.

## Key Features

- Can fetch cover art for Music or Anime
- Support for http streams in Rich Presence
- Metadata tags (Title, Artist, Album, Genre)
- Icons for playing, paused, and buffering
- Supports Windows, Mac, and Linux
- Easy to use install script
- Support for multiple rpc wrappers
- Simple configuration file

## How To Use

> Dependencies
>
> 1. Provided by user: mpv, Discord
> 2. Included: Discord RPC, status-line,lua-discordRPC
> 3. Optional: Python, pypresence

```bash
# Clone the repository
git clone https://github.com/ujjwal-dev23/mpv-discordRPC.git
cd mpv-discordRPC.git

# Use the appropriate install script
install-linux.sh
install-win.bat
install-osx.sh
```

## Configuration

```bash
rpc_wrapper=lua-discordRPC
# Available option, to set `rpc_wrapper`:
# * lua-discordRPC
# * python-pypresence

periodic_timer=15
# Recommendation value, to set `periodic_timer`:
# value >= 1 second, if use lua-discordRPC,
# value >= 3 second, if use pypresence (for the python3::asyncio process),
# value <= 15 second, because discord-rpc updates every 15 seconds.

playlist_info=yes
# Valid value to set `playlist_info`: (yes|no)

hide_url=no
# Valid value to set `hide_url`: (yes|no)

loop_info=yes
# Valid value to set `loop_info`: (yes|no)

cover_art=yes
# Valid value to set `cover_art`: (yes|no)

mpv_version=yes
# Valid value to set `mpv_version`: (yes|no)

active=yes
# Set Discord RPC active automatically when mpv started.
# Valid value to `set_active`: (yes|no)

key_toggle=D
# Key for toggle active/inactive the Discord RPC.
# Valid value to set `key_toggle`: same as valid value for mpv key binding.
# You also can set it in input.conf by adding this next line (without double quote).
# "D script-binding mpv_discordRPC/active-toggle"

anime_scraping=yes
# Enables scraping of anime cover art, titles, and genres from Jikan API
# Valid values to set `anime_scraping`: (yes|no)
```

## You may also like...

- [cniw/mpv-discordRPC](https://github.com/cniw/mpv-discordRPC) - The source of this fork
- [noaione/mpv-discordRPC](https://github.com/noaione/mpv-discordRPC) - The original script that was the source of the source of this fork

## License

MIT

---
