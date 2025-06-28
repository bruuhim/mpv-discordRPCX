-- Discord Rich Presence integration for mpv Media Player
--
-- Please consult the readme for information about usage and configuration:
-- https://github.com/cniw/mpv-discordRPC


local options = require 'mp.options'
local msg = require 'mp.msg'

local animeCache = {}
local lastAnimeTitle = nil
local urlDecodedFilename = nil

-- set [options]
local o = {
	rpc_wrapper = "lua-discordRPC",
	-- Available option, to set `rpc_wrapper`:
	-- * lua-discordRPC
	-- * python-pypresence
	periodic_timer = 15,
	-- Recommendation value, to set `periodic_timer`:
	-- value >= 1 second, if use lua-discordRPC,
	-- value >= 3 second, if use pypresence (for the python3::asyncio process),
	-- value <= 15 second, because discord-rpc updates every 15 seconds.
	playlist_info = "no",
	-- Valid value to set `playlist_info`: (yes|no)
	loop_info = "no",
	-- Valid value to set `loop_info`: (yes|no)
	cover_art = "yes",
	-- Valid value to set `cover_art`: (yes|no)
	mpv_version = "yes",
	-- Valid value to set `mpv_version`: (yes|no)
	active = "yes",
	-- Set Discord RPC active automatically when mpv started.
	-- Valid value to `set_active`: (yes|no)
	key_toggle = "D",
	-- Key for toggle active/inactive the Discord RPC.
	-- Valid value to set `key_toggle`: same as valid value for mpv key binding.
	-- You also can set it in input.conf by adding this next line (without double quote).
	-- "D script-binding mpv_discordRPC/active-toggle"
	anime_scraping = "yes"
	-- Enables scraping of anime cover art, titles, and genres from Jikan API
	-- Valid values to set `anime_scraping`: (yes|no)
}
options.read_options(o)

-- set `script_info`
local script_info = {
	name = mp.get_script_name(),
	description = "Discord Rich Presence integration for mpv Media Player",
	upstream = "https://github.com/cniw/mpv-discordRPC",
	version = "1.4.1-UNKNOWN",
}

-- set `mpv_version`
local mpv_version = mp.get_property("mpv-version"):sub(5)

-- set `startTime`
local startTime = os.time(os.date("*t"))

local function extractAnimeInfo(filename)
	-- Remove file extension
	local nameOnly = filename:gsub("%.%w+$", "")
	local patterns = {
		-- [Group] Title - S##E## [Quality]
		"^%[([^%]]+)%]%s*(.-)%s*%-%s*(S%d+E%d+[v%d]*)%s*%[",
		-- [Group] Title S##E## [Quality] (no dash)
		"^%[([^%]]+)%]%s*(.-)%s+(S%d+E%d+[v%d]*)%s*%[",
		-- [Group] Title - S##E## (Quality)
		"^%[([^%]]+)%]%s*(.-)%s*%-%s*(S%d+E%d+[v%d]*)%s*%(",
		-- [Group] Title S##E## (Quality) (no dash)
		"^%[([^%]]+)%]%s*(.-)%s+(S%d+E%d+[v%d]*)%s*%(",
		-- [Group] Title - S##E##
		"^%[([^%]]+)%]%s*(.-)%s*%-%s*(S%d+E%d+[v%d]*)",
		-- [Group] Title S##E## (no dash)
		"^%[([^%]]+)%]%s*(.-)%s+(S%d+E%d+[v%d]*)$",
		-- [Group] Title - Episode [Quality]
		"^%[([^%]]+)%]%s*(.-)%s*%-%s*(%d+[v%d]*)%s*%[",
		-- [Group] Title Episode [Quality] (no dash - like Beatrice-Raws)
		"^%[([^%]]+)%]%s*(.-)%s+(%d+[v%d]*)%s*%[",
		-- [Group] Title - Episode (Quality)
		"^%[([^%]]+)%]%s*(.-)%s*%-%s*(%d+[v%d]*)%s*%(",
		-- [Group] Title Episode (Quality) (no dash)
		"^%[([^%]]+)%]%s*(.-)%s+(%d+[v%d]*)%s*%(",
		-- [Group] Title - Episode
		"^%[([^%]]+)%]%s*(.-)%s*%-%s*(%d+[v%d]*)",
		-- [Group] Title Episode (no dash)
		"^%[([^%]]+)%]%s*(.-)%s+(%d+[v%d]*)$",
		-- [Group] Title - Special (combined: OVA|OAD|ONA|Movie|Special)
		"^%[([^%]]+)%]%s*(.-)%s*%-%s*(OVA|OAD|ONA|Movie|Special)",
		-- [Group] Title Special (no dash, combined: OVA|OAD|ONA|Movie|Special)
		"^%[([^%]]+)%]%s*(.-)%s+(OVA|OAD|ONA|Movie|Special)",
		-- Title - S##E## [Quality]
		"^(.-)%s*%-%s*(S%d+E%d+[v%d]*)%s*%[",
		-- Title S##E## [Quality] (no dash)
		"^(.-)%s+(S%d+E%d+[v%d]*)%s*%[",
		-- Title - S##E## (Quality)
		"^(.-)%s*%-%s*(S%d+E%d+[v%d]*)%s*%(",
		-- Title S##E## (Quality) (no dash)
		"^(.-)%s+(S%d+E%d+[v%d]*)%s*%(",
		-- Title - S##E##
		"^(.-)%s*%-%s*(S%d+E%d+[v%d]*)$",
		-- Title S##E## (no dash)
		"^(.-)%s+(S%d+E%d+[v%d]*)$",
		-- Title - Episode (Quality)
		"^(.-)%s*%-%s*(%d+[v%d]*)%s*%(",
		-- Title Episode (Quality) (no dash)
		"^(.-)%s+(%d+[v%d]*)%s*%(",
		-- Title - Episode [Quality]
		"^(.-)%s*%-%s*(%d+[v%d]*)%s*%[",
		-- Title Episode [Quality] (no dash)
		"^(.-)%s+(%d+[v%d]*)%s*%[",
		-- Title - Episode
		"^(.-)%s*%-%s*(%d+[v%d]*)$",
		-- Title Episode (no dash)
		"^(.-)%s+(%d+[v%d]*)$",
		-- Title - Special (combined: OVA|OAD|ONA|Movie|Special)
		"^(.-)%s*%-%s*(OVA|OAD|ONA|Movie|Special)"
	}

	for _, pattern in ipairs(patterns) do
		local group, title, episode = nameOnly:match(pattern)

		-- Handle patterns with release groups (3 captures)
		if title and episode then
			title = title:gsub("^%s*(.-)%s*$", "%1") -- Trim
			title = title:gsub("_", " ")          -- Replace underscores
			return {
				title = title,
				episode = episode
			}
			-- Handle patterns without release groups (2 captures)
		elseif group and title and not episode then
			group = group:gsub("^%s*(.-)%s*$", "%1")
			group = group:gsub("_", " ")
			return {
				title = group,
				episode = title -- In this case, 'title' variable contains the episode
			}
		end
	end

	return nil
end


local function getAnimeData(animeTitle)
	if not animeTitle or animeTitle == "" then
		return nil
	end

	-- Check cache first
	if animeCache[animeTitle] then
		return animeCache[animeTitle]
	end

	local utils = require "mp.utils"

	local encodedTitle = animeTitle:gsub(" ", "%%20")
	local url = string.format("https://api.jikan.moe/v4/anime?q=%s&limit=1", encodedTitle)
	local result = utils.subprocess({
		args = { "curl", "-s", url },
		capture_stdout = true,
		capture_stderr = true
	})

	if result.status == 0 and result.stdout then
		local data = utils.parse_json(result.stdout)
		if data and data.data and #data.data > 0 then
			lastAnimeTitle = animeTitle
			animeCache[animeTitle] = data.data[1]
			return data.data[1]
		end
	end

	return nil
end

local function urlDecode(str)
	str = str:gsub("+", " ")
	str = str:gsub("%%(%x%x)", function(hex)
		return string.char(tonumber(hex, 16))
	end)
	return str
end

local function main()
	-- set `details`
	local details = mp.get_property("media-title")
	local metadataTitle = mp.get_property_native("metadata/by-key/Title")
	local metadataArtist = mp.get_property_native("metadata/by-key/Artist")
	local metadataAlbum = mp.get_property_native("metadata/by-key/Album")
	if metadataTitle ~= nil then
		details = metadataTitle
	end
	if metadataArtist ~= nil then
		details = ("%s\nby %s"):format(details, metadataArtist)
	end
	if metadataAlbum ~= nil then
		details = ("%s\non %s"):format(details, metadataAlbum)
	end
	if details == nil then
		details = "No file"
	end
	-- set `state`, `smallImageKey`, and `smallImageText`
	local state, smallImageKey, smallImageText
	local idle = mp.get_property_bool("idle-active")
	local coreIdle = mp.get_property_bool("core-idle")
	local pausedFC = mp.get_property_bool("paused-for-cache")
	local pause = mp.get_property_bool("pause")
	local play = coreIdle and false or true
	if idle then
		state = "(Idle)"
		smallImageKey = "player_stop"
		smallImageText = "Idle"
	elseif pausedFC then
		state = ""
		smallImageKey = "player_pause"
		smallImageText = "Buffering"
	elseif pause then
		state = ""
		smallImageText = "Paused"
		smallImageKey = "player_pause"
	elseif play then
		state = "(Playing) "
		smallImageKey = "player_play"
		smallImageText = "Playing"
	end
	if not idle then
		-- set `playlist_info`
		local playlist = ""
		if o.playlist_info == "yes" then
			playlist = (" - Playlist: [%s/%s]"):format(mp.get_property("playlist-pos-1"),
				mp.get_property("playlist-count"))
		end
		-- set `loop_info`
		local loop = ""
		if o.loop_info == "yes" then
			local loopFile = mp.get_property_bool("loop-file") == false and "" or "file"
			local loopPlaylist = mp.get_property_bool("loop-playlist") == false and "" or "playlist"
			if loopFile ~= "" then
				if loopPlaylist ~= "" then
					loop = ("%s, %s"):format(loopFile, loopPlaylist)
				else
					loop = loopFile
				end
			elseif loopPlaylist ~= "" then
				loop = loopPlaylist
			else
				loop = "disabled"
			end
			loop = (" - Loop: %s"):format(loop)
		end
		state = state .. mp.get_property("options/term-status-msg")
		smallImageText = ("%s%s%s"):format(smallImageText, playlist, loop)
	end
	-- set time
	local timeNow = os.time(os.date("*t"))
	local timeRemaining = os.time(os.date("*t", mp.get_property("playtime-remaining")))
	local timeUp = timeNow + timeRemaining
	-- set `largeImageKey` and `largeImageText`
	local largeImageKey = "mpv"
	local largeImageText = "mpv Media Player"
	-- set `mpv_version`
	if o.mpv_version == "yes" then
		largeImageText = mpv_version
	end
	-- set `cover_art`
	if o.cover_art == "yes" then
		local catalogs = require("catalogs")
		for i in pairs(catalogs) do
			local title = catalogs[i].title
			for j in pairs(title) do
				local lower_title = title[j] ~= nil and title[j]:lower() or ""
				local lower_details = details ~= nil and details:lower() or ""
				if lower_details:find(lower_title, 1, true) ~= nil then
					local number = catalogs[i].number
					largeImageKey = ("coverart_%s"):format(number):gsub("[ /~]", "_"):lower()
					largeImageText = title[j]
				end
			end
			local album = catalogs[i].album
			for j in pairs(album) do
				local lower_album = album[j] ~= nil and album[j]:lower() or ""
				local lower_metadataAlbum = metadataAlbum ~= nil and metadataAlbum:lower() or ""
				if lower_album == lower_metadataAlbum then
					local artist = catalogs[i].artist
					for k in pairs(artist) do
						local lower_artist = artist[k] ~= nil and artist[k]:lower() or ""
						local lower_metadataArtist = metadataArtist ~= nil and metadataArtist:lower() or ""
						if lower_artist == lower_metadataArtist then
							local number = catalogs[i].number
							largeImageKey = ("coverart_%s"):format(number):gsub("[ /~]", "_"):lower()
							largeImageText = album[j]
						end
					end
				end
			end
		end
	end
	-- streaming mode
	local url = mp.get_property("path")
	local stream = mp.get_property("stream-path")
	if url ~= nil then
		-- checking protocol: http, https
		if string.match(url, "^https?://.*") ~= nil then
			largeImageKey = "mpv_stream"
			if string.len(url) < 128 then
				largeImageText = url
			end
			if o.anime_scraping == "yes" and (string.match(url, "%.mkv$") or string.match(url, "%.mp4$") or string.match(url, "%.avi$") or string.match(url, "%.webm$")) then
				local encodedFilename = lastAnimeTitle or url:match("([^/]+)$")

				if encodedFilename ~= lastAnimeTitle then
					urlDecodedFilename = urlDecode(encodedFilename)

					lastAnimeTitle = extractAnimeInfo(urlDecodedFilename).title
				end
			end
		end
		-- checking site: YouTube, Crunchyroll, SoundCloud, LISTEN.moe
		if string.match(url, "www.youtube.com/watch%?v=([a-zA-Z0-9-_]+)&?.*$") ~= nil or string.match(url, "youtu.be/([a-zA-Z0-9-_]+)&?.*$") ~= nil then
			largeImageKey = "youtube" -- alternative "youtube_big" or "youtube-2"
			largeImageText = "YouTube"
		elseif string.match(url, "www.crunchyroll.com/.+/.*-([0-9]+)??.*$") ~= nil then
			largeImageKey = "crunchyroll" -- alternative "crunchyroll_big"
			largeImageText = "Crunchyroll"
		elseif string.match(url, "soundcloud.com/.+/.*$") ~= nil then
			largeImageKey = "soundcloud" -- alternative "soundcloud_big"
			largeImageText = "SoundCloud"
		elseif string.match(url, "listen.moe/.*stream$") ~= nil or string.match(url, "listen.moe/.*opus$") ~= nil or string.match(url, "listen.moe/.*fallback$") ~= nil or string.match(url, "listen.moe/.*m3u$") ~= nil then
			largeImageKey = "listen_moe" -- alternative "listen_moe_big"
			largeImageText = string.match(url, "kpop") ~= nil and "LISTEN.moe - KPOP" or "LISTEN.moe - JPOP"
		end
	end
	if o.anime_scraping == "yes" then
		-- Set Cover as Anime Poster if title can be extracted from filename
		local animeData = nil
		local animeInfo = extractAnimeInfo(urlDecodedFilename or details)
		if animeInfo and animeInfo.title then
			animeData = getAnimeData(animeInfo.title)
		end
		if animeInfo and animeData and animeData.images then
			largeImageKey = animeData.images.webp.large_image_url or animeData.images.jpg.large_image_url
			largeImageText = animeData.title_english or animeData.title
			details = string.format("%s - %s", animeInfo.title, animeInfo.episode)
			if animeData.genres and animeData.genres[1] and animeData.genres[2] and animeData.genres[3] then
				state = string.format("Genre: %s, %s, %s", animeData.genres[1].name, animeData.genres[2].name,
					animeData.genres[3].name)
			elseif animeData.genres and animeData.genres[1] and animeData.genres[2] then
				state = string.format("Genre: %s, %s", animeData.genres[1].name, animeData.genres[2].name)
			elseif animeData.genres and animeData.genres[1] then
				state = string.format("Genre: %s", animeData.genres[1].name)
			end
		end
	end
	-- set `presence`
	local presence = {
		state = state,
		details = details,
		-- startTimestamp = math.floor(startTime),
		endTimestamp = math.floor(timeUp),
		largeImageKey = largeImageKey,
		largeImageText = largeImageText,
		smallImageKey = smallImageKey,
		smallImageText = smallImageText,
	}
	if url ~= nil and stream == nil then
		presence.state = "(Loading)"
		presence.startTimestamp = math.floor(startTime)
		presence.endTimestamp = nil
	end
	if idle then
		presence = {
			state = presence.state,
			details = presence.details,
			startTimestamp = math.floor(startTime),
			-- endTimestamp = presence.endTimestamp,
			largeImageKey = presence.largeImageKey,
			largeImageText = presence.largeImageText,
			smallImageKey = presence.smallImageKey,
			smallImageText = presence.smallImageText
		}
	end
	-- run Rich Presence
	if tostring(o.rpc_wrapper) == "lua-discordRPC" then
		-- run Rich Presence with lua-discordRPC
		local appId = "448016723057049601"
		local RPC = require(o.rpc_wrapper)
		RPC.initialize(appId, true)
		if o.active == "yes" then
			presence.details = presence.details:len() > 127 and presence.details:sub(1, 127) or presence.details
			RPC.updatePresence(presence)
		else
			RPC.shutdown()
		end
	elseif tostring(o.rpc_wrapper) == "python-pypresence" then
		-- set python path
		local pythonPath
		local lib
		pythonPath = mp.get_script_directory() .. "/" .. o.rpc_wrapper .. ".py"
		lib = package.cpath:match("%p[\\|/]?%p(%a+)")
		if lib == "dll" then
			pythonPath = pythonPath:gsub("/", "\\\\")
		end
		-- run Rich Presence with pypresence
		local todo = idle and "idle" or "not-idle"
		local command = ('python "%s" "%s" "%s" "%s" "%s" "%s" "%s" "%s" "%s" "%s" "%s"'):format(pythonPath, todo,
			presence.state, presence.details, math.floor(startTime), math.floor(timeUp), presence.largeImageKey,
			presence.largeImageText, presence.smallImageKey, presence.smallImageText, o.periodic_timer)
		mp.register_event('shutdown', function()
			todo = "shutdown"
			command = ('python "%s" "%s"'):format(pythonPath, todo)
			io.popen(command)
			os.exit()
		end)
		if o.active == "yes" then
			io.popen(command)
		end
	end
end

-- print script info
msg.info(string.format(script_info.description))
msg.info(string.format("Upstream: %s", script_info.upstream))
msg.info(string.format("Version: %s", script_info.version))

-- print option values
msg.verbose(string.format("rpc_wrapper    : %s", o.rpc_wrapper))
msg.verbose(string.format("periodic_timer : %s", o.periodic_timer))
msg.verbose(string.format("playlist_info  : %s", o.playlist_info))
msg.verbose(string.format("loop_info      : %s", o.loop_info))
msg.verbose(string.format("cover_art      : %s", o.cover_art))
msg.verbose(string.format("mpv_version    : %s", o.mpv_version))
msg.verbose(string.format("active         : %s", o.active))
msg.verbose(string.format("key_toggle     : %s", o.key_toggle))

-- toggling active or inactive
mp.add_key_binding(o.key_toggle, "active-toggle", function()
		o.active = o.active == "yes" and "no" or "yes"
		local status = o.active == "yes" and "active" or "inactive"
		mp.osd_message(("[%s] Status: %s"):format(script_info.name, status))
		msg.info(string.format("Status: %s", status))
	end,
	{ repeatable = false })

-- run `main` function
mp.add_periodic_timer(o.periodic_timer, main)
