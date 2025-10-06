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
	version = "1.4.2",
}

-- set `mpv_version`
local mpv_version = mp.get_property("mpv-version"):sub(5)

-- set `startTime`
local startTime = os.time(os.date("*t"))

-- ULTIMATE ANIME FILENAME PARSER - Handles EVERY possible naming convention
local function extractAnimeTitle(filename)
	if not filename then return nil end

	msg.warn("[mpv_discordRPC] ===== ULTIMATE TITLE PARSER =====")
	msg.warn("[mpv_discordRPC] Input filename: '" .. filename .. "'")

	-- Remove file extension
	local name = filename:gsub("%.%w+$", "")
	msg.warn("[mpv_discordRPC] After extension removal: '" .. name .. "'")

	-- STEP 1: REMOVE ALL GROUP/SOURCE TAGS (comprehensive bracket handling)
	local groupPatterns = {
		-- Standard brackets
		"^%[([^%]]+)%]%s*",                    -- [Group]
		"^%(([^%)]+)%)%s*",                    -- (Group)
		"^{([^}]+)}%s*",                       -- {Group}
		"^【([^】]+)】%s*",                     -- 【Group】
		"^〈([^〉]+)〉%s*",                     -- 〈Group〉
		"^《([^》]+)》%s*",                     -- 《Group》
		"^『([^』]+)』%s*",                     -- 『Group』
		"^「([^」]+)」%s*",                     -- 「Group」
		-- Underscore patterns
		"^([^%[_]+_)%s*",                      -- Group_
		"^([^%[_]+__)%s*",                     -- Group__
		-- Chinese patterns
		"^%[([^%]]+字幕[^%]]*)%]%s*",          -- [XX字幕组]
		"^%[([^%]]+字幕社[^%]]*)%]%s*",        -- [XX字幕社]
		"^%[([^%]]+动漫[^%]]*)%]%s*",          -- [XX动漫组]
		-- Raw providers
		"^%[([^%]]+raws?[^%]]*)%]%s*",         -- [XX-raws]
		"^%[([^%]]+BDMV[^%]]*)%]%s*",          -- [BDMV]
		"^%[([^%]]+RAW[^%]]*)%]%s*",           -- [RAW]
		-- TV stations
		"^%[([^%]]+AT%-X[^%]]*)%]%s*",         -- [AT-X]
		"^%[([^%]]+BS11[^%]]*)%]%s*",          -- [BS11]
		"^%[([^%]]+TV[^%]]*)%]%s*",            -- [TV]
	}

	for i, pattern in ipairs(groupPatterns) do
		local original = name
		name = name:gsub(pattern, "")
		if name ~= original then
			msg.warn("[mpv_discordRPC] Removed group tag " .. i .. ": '" .. original .. "' → '" .. name .. "'")
			break -- Only remove one group tag at a time
		end
	end

	-- STEP 2: FIND AND REMOVE EPISODE + ALL TECHNICAL TAGS AFTER IT
	-- This is the critical fix - remove EVERYTHING after the episode pattern

	-- First, try to find where the episode starts in the filename
	local episodeStartPos = nil
	local episodePatterns = {
		-- Dash patterns
		"()-%s*%d+%s*[%(%)%[%]%-]",           -- " - 01 ("
		"()-%s*%d+%s*$",                      -- " - 01" at end
		"()-%s*%d+%.%d+%s*[%(%)%[%]%-]",      -- " - 11.5 ("
		"()-%s*%d+%.%d+%s*$",                 -- " - 11.5" at end
		"()-%s*%d+%s+%w+%s*[%(%)%[%]%-]",     -- " - 01 END ("
		"()-%s*%d+%s+%w+%s*$",                -- " - 01 END" at end
		-- Bracket patterns
		"()%[%s*%d+%s*%]%s*[%(%)%[%]%-]",     -- " [01] ("
		"()%[%s*%d+%s*%]%s*$",                -- " [01]" at end
		"()%[%s*%d+%.%d+%s*%]%s*[%(%)%[%]%-]", -- " [11.5] ("
		"()%[%s*%d+%.%d+%s*%]%s*$",           -- " [11.5]" at end
		"()%[%s*%d+%s+%w+%s*%]%s*[%(%)%[%]%-]", -- " [01 END] ("
		"()%[%s*%d+%s+%w+%s*%]%s*$",          -- " [01 END]" at end
		-- Alternative patterns
		"()EP%s*%d+%s*[%(%)%[%]%-]",          -- " EP01 ("
		"()EP%s*%d+%s*$",                     -- " EP01" at end
		"()Episode%s+%d+%s*[%(%)%[%]%-]",     -- " Episode 01 ("
		"()Episode%s+%d+%s*$",                -- " Episode 01" at end
		"()第%s*%d+%s*話%s*[%(%)%[%]%-]",      -- " 第01話 ("
		"()第%s*%d+%s*話%s*$",                 -- " 第01話" at end
		-- Range patterns
		"()-%s*%d+%-*%d+%s*[%(%)%[%]%-]",     -- " - 01-02 ("
		"()-%s*%d+%-*%d+%s*$",                -- " - 01-02" at end
		"()%[%s*%d+%-*%d+%s*%]%s*[%(%)%[%]%-]", -- " [01-02] ("
		"()%[%s*%d+%-*%d+%s*%]%s*$",          -- " [01-02]" at end
	}

	-- Find the earliest episode pattern match
	for i, pattern in ipairs(episodePatterns) do
		local startPos = name:match(pattern)
		if startPos then
			episodeStartPos = startPos
			msg.warn("[mpv_discordRPC] Found episode pattern " .. i .. " starting at position: " .. startPos)
			break
		end
	end

	-- If we found an episode, remove everything from that point onward
	if episodeStartPos then
		-- Extract only the title part (everything before the episode)
		local titlePart = name:sub(1, episodeStartPos - 1)
		msg.warn("[mpv_discordRPC] Extracted title part: '" .. titlePart .. "'")

		-- Clean up the title part (remove trailing separators)
		titlePart = titlePart:gsub("[_%-%.%s]+$", "")

		-- Use the cleaned title part as our base
		name = titlePart
		msg.warn("[mpv_discordRPC] After episode removal: '" .. name .. "'")
	else
		msg.warn("[mpv_discordRPC] No episode pattern found, keeping full name for cleaning")
		-- If no episode found, we'll still clean technical tags but keep the full potential title
	end

	-- STEP 3: REMOVE QUALITY/TECHNICAL TAGS (comprehensive tech tag removal)
	local techPatterns = {
		-- Resolution
		"%s+%[?%d+%s*x%s*%d+%]?%s*$",          -- [1920x1080] or 1920x1080
		"%s+%[?%d+p?]%s*$",                    -- [1080p] or 1080p
		"%s+%[?4K%]?%s*$",                     -- [4K] or 4K
		"%s+%[?2160p%]?%s*$",                  -- [2160p] or 2160p
		-- Source
		"%s+%[?BD%]?%s*$",                     -- [BD] or BD
		"%s+%[?BDRip%]?%s*$",                  -- [BDRip] or BDRip
		"%s+%[?WEB%]?%s*$",                    -- [WEB] or WEB
		"%s+%[?WEBRip%]?%s*$",                 -- [WEBRip] or WEBRip
		"%s+%[?DVDRip%]?%s*$",                 -- [DVDRip] or DVDRip
		"%s+%[?TV%]?%s*$",                     -- [TV] or TV
		"%s+%[?AT%-X%]?%s*$",                  -- [AT-X] or AT-X
		"%s+%[?BS11%]?%s*$",                   -- [BS11] or BS11
		-- Codec
		"%s+%[?x264%]?%s*$",                   -- [x264] or x264
		"%s+%[?x265%]?%s*$",                   -- [x265] or x265
		"%s+%[?AV1%]?%s*$",                    -- [AV1] or AV1
		"%s+%[?HEVC%]?%s*$",                   -- [HEVC] or HEVC
		"%s+%[?H%.264%]?%s*$",                 -- [H.264] or H.264
		"%s+%[?10bit%]?%s*$",                  -- [10bit] or 10bit
		"%s+%[?8bit%]?%s*$",                   -- [8bit] or 8bit
		"%s+%[?Hi10p%]?%s*$",                  -- [Hi10p] or Hi10p
		"%s+%[?Ma10p%]?%s*$",                  -- [Ma10p] or Ma10p
		-- Audio
		"%s+%[?FLAC%]?%s*$",                   -- [FLAC] or FLAC
		"%s+%[?AAC%]?%s*$",                    -- [AAC] or AAC
		"%s+%[?AC3%]?%s*$",                    -- [AC3] or AC3
		"%s+%[?DTS%]?%s*$",                    -- [DTS] or DTS
		"%s+%[?5%.1%]?%s*$",                   -- [5.1] or 5.1
		"%s+%[?2%.0%]?%s*$",                   -- [2.0] or 2.0
		-- Other
		"%s+%[?Multi%-Subs%]?%s*$",            -- [Multi-Subs]
		"%s+%[?Dual.Audio%]?%s*$",             -- [Dual Audio]
		"%s+%[?Softsubs%]?%s*$",               -- [Softsubs]
		"%s+%[?Hardsubs%]?%s*$",               -- [Hardsubs]
		-- Hash/CRC
		"%s+%[?[A-F0-9]{8}%]?%s*$",            -- [A1B2C3D4]
		"%s+%[?CRC32%]?%s*$",                  -- [CRC32]
		-- Size
		"%s+%[?%d+%.?%d*GB%]?%s*$",            -- [1.2GB]
		"%s+%[?%d+MB%]?%s*$",                  -- [500MB]
		-- Years
		"%s+%(?%d%d%d%d%)?%s*$",               -- (2016)
	}

	for i, pattern in ipairs(techPatterns) do
		local original = name
		name = name:gsub(pattern, "")
		if name ~= original then
			msg.warn("[mpv_discordRPC] Removed tech tag " .. i .. ": '" .. original .. "' → '" .. name .. "'")
		end
	end

	-- STEP 4: CLEAN SEPARATORS AND NORMALIZE
	-- Handle various separators
	name = name:gsub("[_.%-－—]", " ")        -- Replace separators with spaces
	name = name:gsub("%s+", " ")              -- Normalize multiple spaces
	name = name:gsub("^%s*(.-)%s*$", "%1")    -- Trim whitespace

	msg.warn("[mpv_discordRPC] After cleaning: '" .. name .. "'")

-- STEP 5: REMOVE SEASON/EPISODE INDICATORS FROM TITLE (critical for clean API search)
	local seasonEpisodePatterns = {
		-- Remove S00E00 patterns at end
		"S%d+E%d+", "S%d+E%d+$",                -- S02E01
		-- Remove standalone S00 at end
		"S%d+$", "S%d+",                          -- S02
		-- Remove E00 patterns
		"E%d+", "E%d+$",                          -- E01
		-- Remove Season N patterns at end
		"%s+Season%s+%d+$",                        -- Season 2
		"%s+%d+nd%s+Season$",                      -- 2nd Season
		"%s+%d+rd%s+Season$",                      -- 3rd Season
		"%s+%d+th%s+Season$",                      -- 4th Season
		-- Remove Part N patterns at end
		"%s+Part%s+%d+$",                          -- Part 2
		"%s+II$", "%s+III$", "%s+IV$",           -- II, III, IV
		"%s+ii$", "%s+iii$", "%s+iv$",           -- ii, iii, iv
	}

	for i, pattern in ipairs(seasonEpisodePatterns) do
		local original = name
		name = name:gsub(pattern, "")
		if name ~= original then
			msg.warn("[mpv_discordRPC] Removed S/E indicator " .. i .. ": '" .. original .. "' → '" .. name .. "'")
		end
	end

	-- STEP 6: FINAL CLEANUP
	name = name:gsub("%s+", " ")              -- Final space normalization
	name = name:gsub("^%s*(.-)%s*$", "%1")    -- Final trim

	msg.warn("[mpv_discordRPC] Final cleaned title: '" .. name .. "'")

	return name ~= "" and name or nil
end

-- Extract season information for API search variations
local function extractSeasonInfo(filename)
	if not filename then return nil end

	local seasonPatterns = {
		"S(%d+)",                    -- S2, S03
		"Season%s+(%d+)",           -- Season 2
		"(%d+)nd%s+Season",         -- 2nd Season
		"(%d+)rd%s+Season",         -- 3rd Season
		"(%d+)th%s+Season",         -- 4th Season
		"(%d+)nd%s+Sea",            -- 2nd Sea (partial)
		"(%d+)rd%s+Sea",            -- 3rd Sea (partial)
		"(%d+)th%s+Sea"             -- 4th Sea (partial)
	}

	for _, pattern in ipairs(seasonPatterns) do
		local season = filename:match(pattern)
		if season then
			return tonumber(season)
		end
	end

	return nil
end



-- Helper function to get readable pattern names for logging
local function getPatternName(index, targetSeason)
	local patterns = {
		[1] = "exactly '" .. targetSeason .. "' at end",
		[2] = "'II' at end",
		[3] = "'III' at end",
		[4] = "'IV' at end",
		[5] = "'Season " .. targetSeason .. "' in title/synonyms",
		[6] = "'S" .. targetSeason .. "' in title/synonyms",
		[7] = "'Part " .. targetSeason .. "' in title/synonyms",
		[8] = "'2nd Season' in title/synonyms",
		[9] = "'3rd Season' in title/synonyms",
		[10] = "'4th Season' in title/synonyms",
		[11] = "'second season' in title/synonyms",
		[12] = "'third season' in title/synonyms",
		[13] = "'fourth season' in title/synonyms",
	}
	return patterns[index] or "season pattern " .. index
end

-- BULLETPROOF UNIVERSAL SEASON MATCHING - No hardcoded IDs, works for ANY anime
local function findBestSeasonMatch(results, targetSeason, baseTitle)
	msg.warn("[mpv_discordRPC] ===== BULLETPROOF SEASON MATCHING =====")
	msg.warn("[mpv_discordRPC] Target season: " .. targetSeason)
	msg.warn("[mpv_discordRPC] Base title: '" .. baseTitle .. "'")
	msg.warn("[mpv_discordRPC] Total API results: " .. #results)

	-- STEP 1: STRICT TV TYPE FILTERING
	local tvResults = {}
	for i, anime in ipairs(results) do
		local animeType = anime.type or "Unknown"
		if animeType == "TV" then
			table.insert(tvResults, anime)
		end
	end

	msg.warn("[mpv_discordRPC] Filtered to " .. #tvResults .. "/" .. #results .. " TV type results")

	if #tvResults == 0 then
		msg.warn("[mpv_discordRPC] No TV results found - falling back to first result")
		return results[1]
	end

	-- STEP 2: PREPARE CLEAN BASE TITLE
	local baseTitle_clean = baseTitle:lower():gsub("season%s+%d+", ""):gsub("s%d+", ""):gsub("part%s+%d+", "")

	-- STRICT SEASON INDICATORS - must appear at title end or in title for exact match
	local seasonIndicators = {
		-- Number at end: "Anime 2"
		"%s+" .. targetSeason .. "%s*$",
		-- Roman numerals at end: "Anime II", "Anime III", etc.
		targetSeason == 2 and "%s+ii%s*$" or nil,
		targetSeason == 3 and "%s+iii%s*$" or nil,
		targetSeason == 4 and "%s+iv%s*$" or nil,
		-- Full season phrases anywhere in title
		"%s+season%s+" .. targetSeason .. "%s*",
		"%s+s" .. targetSeason .. "%s*",
		"%s+part%s+" .. targetSeason .. "%s*",
		-- Ordinal phrases anywhere
		targetSeason .. "nd%s+season%s*",
		targetSeason .. "rd%s+season%s*",
		targetSeason .. "th%s+season%s*",
		-- Word-based at end
		targetSeason == 2 and "%s+second%s+season%s*$" or nil,
		targetSeason == 3 and "%s+third%s+season%s*$" or nil,
		targetSeason == 4 and "%s+fourth%s+season%s*$" or nil,
	}

	-- Remove nil patterns
	for i = #seasonIndicators, 1, -1 do
		if seasonIndicators[i] == nil then
			table.remove(seasonIndicators, i)
		end
	end

	-- STEP 3: SCORE ALL TV RESULTS
	local scoredResults = {}

	for i, anime in ipairs(tvResults) do
		local title_at_end = (anime.title_english or anime.title or ""):lower()
		local title_at_synonyms = ""
		if anime.synonyms and type(anime.synonyms) == "table" then
			for j, synonym in ipairs(anime.synonyms) do
				title_at_synonyms = title_at_synonyms .. " " .. synonym:lower()
			end
		end

		local combined_searchable = title_at_end .. title_at_synonyms

		msg.warn("[mpv_discordRPC] Analyzing TV entry " .. i .. ":")
		msg.warn("[mpv_discordRPC]   Title: '" .. title_at_end .. "'")
		msg.warn("[mpv_discordRPC]   Synonyms: '" .. title_at_synonyms .. "'")

		local score = 0
		local matchFound = false
		local matchDetails = {}
		local baseTitleMatch = false

		-- Check for base title match (remove season info from title for comparison)
		local title_no_season = title_at_end:gsub("season%s+%d+", ""):gsub("s%d+", ""):gsub("part%s+%d+", "")
		if title_no_season:find(baseTitle_clean) or baseTitle_clean:find(title_no_season) then
			score = score + 20 -- Strong boost for title match
			matchDetails.titleMatch = "base title"
			baseTitleMatch = true
			msg.warn("[mpv_discordRPC]   ✅ Base title match (+" .. 20 .. ")")
		else
			-- Check for partial title match if exact doesn't work
			local title_words = {}
			for word in baseTitle_clean:gmatch("%S+") do
				table.insert(title_words, word)
			end
			local title_words_found = 0
			for _, word in ipairs(title_words) do
				if title_no_season:find(word) then
					title_words_found = title_words_found + 1
				end
			end
			if title_words_found >= 2 then -- At least 2 words match
				score = score + 10
				matchDetails.titleMatch = "partial words"
				baseTitleMatch = true
				msg.warn("[mpv_discordRPC]   ✅ Partial title match (+" .. 10 .. ")")
			end
		end

		-- STEP 4: CHECK SEASON INDICATORS AT TITLE END OR KEY WORDS
		for j, pattern in ipairs(seasonIndicators) do
			if combined_searchable:find(pattern) then
				matchFound = true
				local patternScore = 15 -- Base score for season match
				local patternName = getPatternName(j, targetSeason)
				table.insert(matchDetails, patternName)
				score = score + patternScore
				msg.warn("[mpv_discordRPC]   ✅ Season pattern '" .. patternName .. "' (+" .. patternScore .. ")")
				break
			end
		end

		-- STEP 5: PREFER EXACT TITLE + SEASON COMBINATIONS
		if baseTitleMatch and matchFound then
			score = score + 25 -- Huge boost for perfect combination
			msg.warn("[mpv_discordRPC]   ⭐ PERFECT: Title + Season (+" .. 25 .. ")")
		end

		-- STEP 6: STORE SCORED RESULT
		if score > 0 then
			table.insert(scoredResults, {
				anime = anime,
				score = score,
				details = matchDetails,
				hasTitleMatch = baseTitleMatch,
				hasSeasonMatch = matchFound
			})
			msg.warn("[mpv_discordRPC]   📊 Total score: " .. score)
		else
			msg.warn("[mpv_discordRPC]   ❌ No matches")
		end
	end

	-- STEP 7: SELECT BEST MATCH
	if #scoredResults > 0 then
		-- Sort by score (highest first), then by MAL ID (lowest first for ties)
		table.sort(scoredResults, function(a, b)
			if a.score == b.score then
				return a.anime.mal_id < b.anime.mal_id
			else
				return a.score > b.score
			end
		end)

		local bestMatch = scoredResults[1]
		local anime = bestMatch.anime

		msg.warn("[mpv_discordRPC] ===== BEST MATCH SELECTED =====")
		msg.warn("[mpv_discordRPC] Selected: '" .. (anime.title_english or anime.title) .. "'")
		msg.warn("[mpv_discordRPC] MAL ID: " .. anime.mal_id)
		msg.warn("[mpv_discordRPC] Score: " .. bestMatch.score)
		msg.warn("[mpv_discordRPC] Match criteria: " .. table.concat(bestMatch.details, ", "))
		msg.warn("[mpv_discordRPC] Has title match: " .. (bestMatch.hasTitleMatch and "YES" or "NO"))
		msg.warn("[mpv_discordRPC] Has season match: " .. (bestMatch.hasSeasonMatch and "YES" or "NO"))

		if #scoredResults > 1 then
			msg.warn("[mpv_discordRPC] Other candidates:")
			for i = 2, math.min(3, #scoredResults) do
				local candidate = scoredResults[i]
				msg.warn("[mpv_discordRPC]   #" .. i .. ": '" .. (candidate.anime.title_english or candidate.anime.title) .. "' (score: " .. candidate.score .. ")")
			end
		end

		return anime
	end

	-- STEP 8: FALLBACK TO FIRST TV RESULT
	local fallback = tvResults[1]
	msg.warn("[mpv_discordRPC] ===== FALLBACK: FIRST TV RESULT =====")
	msg.warn("[mpv_discordRPC] Selected: '" .. (fallback.title_english or fallback.title) .. "'")
	msg.warn("[mpv_discordRPC] MAL ID: " .. fallback.mal_id)
	msg.warn("[mpv_discordRPC] Selection reason: No title or season matches found")
	return fallback
end

-- ULTIMATE EPISODE EXTRACTOR - Handles EVERY possible episode format
local function extractEpisodeFromFilename(filename)
	if not filename then return "No episode info" end

	-- Remove file extension
	local name = filename:gsub("%.%w+$", "")
	msg.warn("[mpv_discordRPC] ===== ULTIMATE EPISODE EXTRACTOR =====")
	msg.warn("[mpv_discordRPC] Processing filename: '" .. name .. "'")

	-- STEP 1: COMPREHENSIVE EPISODE PATTERNS (try in order of specificity)

	-- Pattern 1.1: DASH + DIGITS (most common)
	-- Examples: "Title - 01", "Title - 1", "Title - 12"
	local dashDigits = name:match("%-%s*(%d+)%s*[%(%)%[%]%-]")
	if dashDigits and tonumber(dashDigits) <= 2000 then
		msg.warn("[mpv_discordRPC] Dash + digits matched: '" .. dashDigits .. "'")
		return "Episode " .. dashDigits
	end

	-- Pattern 1.2: DASH + DECIMAL (special episodes)
	-- Examples: "Title - 11.5", "Title - 13.75"
	local dashDecimal = name:match("%-%s*(%d+%.%d+)%s*[%(%)%[%]%-]")
	if dashDecimal then
		msg.warn("[mpv_discordRPC] Dash + decimal matched: '" .. dashDecimal .. "'")
		return "Episode " .. dashDecimal
	end

	-- Pattern 1.3: DASH + DIGITS + SPECIAL TEXT
	-- Examples: "Title - 47 END", "Title - 1 SP", "Title - 13 OVA"
	local dashSpecialPatterns = {
		"%-%s*(%d+%s+END)%s*[%(%)%[%]%-]",      -- " - 47 END"
		"%-%s*(%d+%s+SP)%s*[%(%)%[%]%-]",       -- " - 1 SP"
		"%-%s*(%d+%s+OVA)%s*[%(%)%[%]%-]",      -- " - 13 OVA"
		"%-%s*(%d+%s+SPECIAL)%s*[%(%)%[%]%-]",  -- " - 11 SPECIAL"
		"%-%s*(%d+%s+FINAL)%s*[%(%)%[%]%-]",   -- " - 25 FINAL"
	}

	for i, pattern in ipairs(dashSpecialPatterns) do
		local match = name:match(pattern)
		if match then
			msg.warn("[mpv_discordRPC] Dash + special pattern " .. i .. " matched: '" .. match .. "'")
			return "Episode " .. match
		end
	end

	-- Pattern 2.1: BRACKET + DIGITS
	-- Examples: "Title [01]", "Title [1]", "Title [12]"
	local bracketDigits = name:match("%[%s*(%d+)%s*%]%s*[%(%)%[%]%-]")
	if bracketDigits and tonumber(bracketDigits) <= 2000 then
		msg.warn("[mpv_discordRPC] Bracket + digits matched: '" .. bracketDigits .. "'")
		return "Episode " .. bracketDigits
	end

	-- Pattern 2.2: BRACKET + DECIMAL
	-- Examples: "Title [11.5]", "Title [13.75]"
	local bracketDecimal = name:match("%[%s*(%d+%.%d+)%s*%]%s*[%(%)%[%]%-]")
	if bracketDecimal then
		msg.warn("[mpv_discordRPC] Bracket + decimal matched: '" .. bracketDecimal .. "'")
		return "Episode " .. bracketDecimal
	end

	-- Pattern 2.3: BRACKET + DIGITS + SPECIAL TEXT
	-- Examples: "Title [08 SP]", "Title [13 OVA]", "Title [25 FINAL]"
	local bracketSpecialPatterns = {
		"%[%s*(%d+%s+END)%s*%]%s*[%(%)%[%]%-]",     -- " [47 END]"
		"%[%s*(%d+%s+SP)%s*%]%s*[%(%)%[%]%-]",      -- " [1 SP]"
		"%[%s*(%d+%s+OVA)%s*%]%s*[%(%)%[%]%-]",     -- " [13 OVA]"
		"%[%s*(%d+%s+SPECIAL)%s*%]%s*[%(%)%[%]%-]", -- " [11 SPECIAL]"
		"%[%s*(%d+%s+FINAL)%s*%]%s*[%(%)%[%]%-]",  -- " [25 FINAL]"
	}

	for i, pattern in ipairs(bracketSpecialPatterns) do
		local match = name:match(pattern)
		if match then
			msg.warn("[mpv_discordRPC] Bracket + special pattern " .. i .. " matched: '" .. match .. "'")
			return "Episode " .. match
		end
	end

	-- Pattern 3.1: ALTERNATIVE PREFIXES
	-- Examples: "Title EP01", "Title Episode 01", "Title 第01話"
	local altPrefixPatterns = {
		"EP%s*(%d+)%s*[%(%)%[%]%-]",           -- " EP01"
		"Episode%s+(%d+)%s*[%(%)%[%]%-]",      -- " Episode 01"
		"第%s*(%d+)%s*話%s*[%(%)%[%]%-]",       -- " 第01話"
		"الحلقة%s+(%d+)%s*[%(%)%[%]%-]",        -- " الحلقة 01" (Arabic)
	}

	for i, pattern in ipairs(altPrefixPatterns) do
		local match = name:match(pattern)
		if match and tonumber(match) <= 2000 then
			msg.warn("[mpv_discordRPC] Alternative prefix pattern " .. i .. " matched: '" .. match .. "'")
			return "Episode " .. match
		end
	end

	-- Pattern 4.1: RANGE PATTERNS
	-- Examples: "Title - 01-02", "Title [01-02]", "Title - 1~3"
	local rangePatterns = {
		"%-%s*(%d+%-%d+)%s*[%(%)%[%]%-]",      -- " - 01-02"
		"%[%s*(%d+%-%d+)%s*%]%s*[%(%)%[%]%-]", -- " [01-02]"
		"%-%s*(%d+~%d+)%s*[%(%)%[%]%-]",       -- " - 1~3"
	}

	for i, pattern in ipairs(rangePatterns) do
		local match = name:match(pattern)
		if match then
			msg.warn("[mpv_discordRPC] Range pattern " .. i .. " matched: '" .. match .. "'")
			return "Episode " .. match
		end
	end

	-- Pattern 5.1: SEASONAL FORMAT
	-- Examples: "S01E03", "S1E12"
	local seasonalPatterns = {
		"S(%d+)E(%d+)",                        -- "S01E03"
		"S(%d+)E(%d+%.%d+)",                   -- "S01E03.5"
		"S(%d+)E(%d+%s+END)",                  -- "S01E25 END"
	}

	for i, pattern in ipairs(seasonalPatterns) do
		local match = name:match(pattern)
		if match then
			msg.warn("[mpv_discordRPC] Seasonal pattern " .. i .. " matched: '" .. match .. "'")
			return "Episode " .. match
		end
	end

	-- STEP 2: EXTRACT AFTER LAST DASH AND ANALYZE (fallback method)
	local afterDash = name:match(".-%s*%-([^%-]*)$")
	if afterDash then
		local cleaned = afterDash:gsub("^%s*", ""):gsub("%s*$", "")
		msg.warn("[mpv_discordRPC] After last dash: '" .. cleaned .. "'")

		-- Stop at technical info
		local episodePart = cleaned:gsub("%s*[%(%)%[%]].*", "")
		msg.warn("[mpv_discordRPC] Episode part after cleanup: '" .. episodePart .. "'")

		-- Try to extract episode from the beginning of this part
		local fallbackPatterns = {
			"^(%d+)",                    -- "01"
			"^(%d+%.%d+)",               -- "11.5"
			"^(%d+%s+END)",              -- "47 END"
			"^(%d+%s+SP)",               -- "1 SP"
			"^(%d+%s+OVA)",              -- "13 OVA"
			"^(%d+%s+SPECIAL)",          -- "11 SPECIAL"
			"^(%d+%s+FINAL)",            -- "25 FINAL"
		}

		for i, pattern in ipairs(fallbackPatterns) do
			local match = episodePart:match(pattern)
			if match and tonumber(match:match("%d+")) <= 2000 then
				msg.warn("[mpv_discordRPC] Fallback pattern " .. i .. " matched: '" .. match .. "'")
				return "Episode " .. match
			end
		end
	end

	-- STEP 3: ULTRA PERMISSIVE LAST RESORT (catch edge cases)
	-- Look for any reasonable number that could be an episode
	local ultraPermissive = name:match(".*[%-_]%s*(%d+)[%s%-].*")
	if ultraPermissive and tonumber(ultraPermissive) <= 2000 and tonumber(ultraPermissive) >= 1 then
		msg.warn("[mpv_discordRPC] Ultra permissive matched: '" .. ultraPermissive .. "'")
		return "Episode " .. ultraPermissive
	end

	-- STEP 4: CONTEXT ANALYSIS (look for numbers that aren't technical)
	-- Extract all numbers and use context to determine which is the episode
	local numbers = {}
	for num in name:gmatch("(%d+)") do
		if tonumber(num) <= 2000 and tonumber(num) >= 1 then
			table.insert(numbers, num)
		end
	end

	if #numbers > 0 then
		-- Use the first reasonable number (usually the episode)
		local candidate = numbers[1]
		msg.warn("[mpv_discordRPC] Context analysis found candidate: '" .. candidate .. "'")
		return "Episode " .. candidate
	end

	-- No episode found (likely a movie or single file)
	msg.warn("[mpv_discordRPC] No episode pattern detected - likely movie or single file")
	return "No episode info"
end




-- Enhanced anime data fetching with canonical ID lookup and comprehensive logging
local function getAnimeData(animeTitle, seasonNumber)
	if not animeTitle or animeTitle == "" then
		return nil
	end

	-- Check cache first (include season in cache key for season-specific results)
	local cacheKey = seasonNumber and (animeTitle .. "_S" .. seasonNumber) or animeTitle
	if animeCache[cacheKey] then
		msg.warn("[mpv_discordRPC] Using cached data for: '" .. cacheKey .. "'")
		return animeCache[cacheKey]
	end

	local utils = require "mp.utils"

	-- STEP 1: SEASON-AWARE SEARCH VARIATIONS
	local searchVariations = {animeTitle}

	if seasonNumber and seasonNumber > 1 then
		-- Add season-specific search terms
		local seasonTerms = {
			animeTitle .. " Season " .. seasonNumber,
			animeTitle .. " S" .. seasonNumber,
			animeTitle .. " " .. seasonNumber .. "nd Season",
			animeTitle .. " " .. seasonNumber .. "rd Season",
			animeTitle .. " " .. seasonNumber .. "th Season",
		}

		-- Add ordinal suffixes for seasons 2-4
		if seasonNumber == 2 then
			table.insert(seasonTerms, animeTitle .. " Second Season")
			table.insert(seasonTerms, animeTitle .. " 2nd Season")
		elseif seasonNumber == 3 then
			table.insert(seasonTerms, animeTitle .. " Third Season")
			table.insert(seasonTerms, animeTitle .. " 3rd Season")
		elseif seasonNumber == 4 then
			table.insert(seasonTerms, animeTitle .. " Fourth Season")
			table.insert(seasonTerms, animeTitle .. " 4th Season")
		end

		-- Add generic season search
		table.insert(seasonTerms, animeTitle .. " season")

		-- Add all season terms to search variations
		for _, term in ipairs(seasonTerms) do
			table.insert(searchVariations, term)
		end
	end

	-- STEP 3: TRY EACH SEARCH VARIATION WITH COMPREHENSIVE LOGGING
	for i, searchTerm in ipairs(searchVariations) do
		msg.warn("[mpv_discordRPC] ===== API SEARCH ATTEMPT " .. i .. " =====")
		msg.warn("[mpv_discordRPC] Search term: '" .. searchTerm .. "'")
		local encodedTitle = searchTerm:gsub(" ", "%%20")
		local url = string.format("https://api.jikan.moe/v4/anime?q=%s&limit=15", encodedTitle) -- Increased limit for better matching

		local result = utils.subprocess({
			args = { "curl", "-s", url },
			capture_stdout = true,
			capture_stderr = true
		})

		if result.status == 0 and result.stdout then
			local data = utils.parse_json(result.stdout)
			if data and data.data and #data.data > 0 then
				msg.warn("[mpv_discordRPC] API returned " .. #data.data .. " results")

				-- Log all results with full metadata for debugging
				for j, anime in ipairs(data.data) do
					msg.warn("[mpv_discordRPC] Result " .. j .. ":")
					msg.warn("[mpv_discordRPC]   Title: '" .. (anime.title_english or anime.title) .. "'")
					msg.warn("[mpv_discordRPC]   MAL ID: " .. anime.mal_id)
					msg.warn("[mpv_discordRPC]   Type: " .. (anime.type or "Unknown"))
					msg.warn("[mpv_discordRPC]   Status: " .. (anime.status or "Unknown"))
					if anime.synonyms and #anime.synonyms > 0 then
						msg.warn("[mpv_discordRPC]   Synonyms: " .. table.concat(anime.synonyms, ", "))
					end
				end

				-- If we have a specific season, filter results for season matches
				if seasonNumber and seasonNumber > 1 then
					local bestMatch = findBestSeasonMatch(data.data, seasonNumber, animeTitle)
					if bestMatch then
						msg.warn("[mpv_discordRPC] ===== SEASON MATCH SELECTED =====")
						msg.warn("[mpv_discordRPC] Selected: '" .. (bestMatch.title_english or bestMatch.title) .. "'")
						msg.warn("[mpv_discordRPC] MAL ID: " .. bestMatch.mal_id)
						msg.warn("[mpv_discordRPC] Match reason: Season-aware filtering")
						animeCache[cacheKey] = bestMatch
						return bestMatch
					end
				else
					-- No specific season, return first result
					local firstResult = data.data[1]
					msg.warn("[mpv_discordRPC] ===== FIRST RESULT SELECTED =====")
					msg.warn("[mpv_discordRPC] Selected: '" .. (firstResult.title_english or firstResult.title) .. "'")
					msg.warn("[mpv_discordRPC] MAL ID: " .. firstResult.mal_id)
					msg.warn("[mpv_discordRPC] Match reason: No specific season requested")
					animeCache[cacheKey] = firstResult
					return firstResult
				end
			end
		end

		msg.warn("[mpv_discordRPC] No results for search attempt " .. i)
	end

	msg.warn("[mpv_discordRPC] ===== NO API RESULTS FOUND =====")
	msg.warn("[mpv_discordRPC] Searched for: '" .. animeTitle .. "'")
	if seasonNumber then
		msg.warn("[mpv_discordRPC] Season: " .. seasonNumber)
	end
	msg.warn("[mpv_discordRPC] All search variations failed")
	return nil
end



-- Generate comprehensive season search patterns for any target season
local function generateSeasonPatterns(targetSeason)
	local patterns = {
		-- Basic numeric patterns
		"season " .. targetSeason,
		"s" .. targetSeason,
		tostring(targetSeason),  -- Just the number

		-- Ordinal number patterns
		targetSeason .. "nd season",
		targetSeason .. "rd season",
		targetSeason .. "th season",

		-- Word patterns
		"second season", "third season", "fourth season",
		"fifth season", "sixth season",

		-- Abbreviated patterns
		"2nd season", "3rd season", "4th season",
		"5th season", "6th season",

		-- Part patterns
		"part " .. targetSeason,
		"part ii", "part iii", "part iv",
		"part v", "part vi",

		-- Special patterns
		"final season", "last season",
	}

	-- Add target-season specific patterns
	if targetSeason == 2 then
		table.insert(patterns, "second season")
		table.insert(patterns, "2nd season")
		table.insert(patterns, "ii")
	elseif targetSeason == 3 then
		table.insert(patterns, "third season")
		table.insert(patterns, "3rd season")
		table.insert(patterns, "iii")
	elseif targetSeason == 4 then
		table.insert(patterns, "fourth season")
		table.insert(patterns, "4th season")
		table.insert(patterns, "iv")
	elseif targetSeason == 5 then
		table.insert(patterns, "fifth season")
		table.insert(patterns, "5th season")
		table.insert(patterns, "v")
	elseif targetSeason == 6 then
		table.insert(patterns, "sixth season")
		table.insert(patterns, "6th season")
		table.insert(patterns, "vi")
	end

	return patterns
end

-- Calculate score for different pattern types
local function getPatternScore(pattern, targetSeason)
	-- Higher scores for more specific patterns
	if pattern:find("season " .. targetSeason) then
		return 15  -- "season 2" - most specific
	elseif pattern:find("^" .. targetSeason .. "$") then
		return 12  -- "2" - exact number
	elseif pattern:find("s" .. targetSeason) then
		return 10  -- "s2" - abbreviated
	elseif pattern:find(targetSeason .. "nd season") or pattern:find(targetSeason .. "rd season") or pattern:find(targetSeason .. "th season") then
		return 8   -- "2nd season" - ordinal
	elseif pattern:find("second season") or pattern:find("third season") or pattern:find("fourth season") then
		return 6   -- "second season" - word form
	else
		return 4   -- Generic patterns
	end
end

-- Calculate title similarity score (excluding season indicators)
local function calculateTitleSimilarity(animeTitle, baseTitle, targetSeason)
	local baseTitleClean = baseTitle:lower():gsub("season%s+%d+", ""):gsub("s%d+", ""):gsub("part%s+%d+", "")
	local animeTitleClean = animeTitle:gsub("season%s+%d+", ""):gsub("s%d+", ""):gsub("part%s+%d+", "")

	-- Exact match gets highest score
	if animeTitleClean == baseTitleClean then
		return 10
	-- Partial match gets medium score
	elseif animeTitleClean:find(baseTitleClean) or baseTitleClean:find(animeTitleClean) then
		return 5
	-- No match gets zero
	else
		return 0
	end
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
	local timeNow = os.time()
	local elapsed = mp.get_property_number("time-pos")
	local duration = mp.get_property_number("duration")
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
			-- Anime scraping for streams disabled, as focus is on folder/filename parsing
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
		-- Force anime detection and visible debug output
		msg.warn("[mpv_discordRPC] ===== STARTING ANIME DETECTION =====")
		local path = mp.get_property("path")
		msg.warn("[mpv_discordRPC] Folder path: " .. tostring(path))
		local filename = urlDecodedFilename or (path and path:match("([^/\\]+)$") or "")
		msg.warn("[mpv_discordRPC] Filename: " .. tostring(filename))

		-- Extract clean anime title from filename using improved fansub pattern matching
		local cleanAnimeTitle = extractAnimeTitle(filename)
		msg.warn("[mpv_discordRPC] Cleaned anime title: " .. tostring(cleanAnimeTitle))

		-- Extract season information for API search variations
		local seasonNumber = extractSeasonInfo(filename)
		msg.warn("[mpv_discordRPC] Detected season: " .. tostring(seasonNumber))

		-- Extract episode from filename (episode extraction label)
		local episodeFromFilename = extractEpisodeFromFilename(filename)
		msg.warn("[mpv_discordRPC] Episode info: " .. tostring(episodeFromFilename))

		local animeData = nil
		local searchTitle = cleanAnimeTitle

		if cleanAnimeTitle then
			msg.warn("[mpv_discordRPC] ===== SEASON-AWARE API LOOKUP =====")
			msg.warn("[mpv_discordRPC] Base title: '" .. cleanAnimeTitle .. "'")
			msg.warn("[mpv_discordRPC] Detected season: " .. (seasonNumber or "None"))

			-- Use the enhanced season-aware API lookup
			animeData = getAnimeData(cleanAnimeTitle, seasonNumber)

			if animeData then
				msg.warn("[mpv_discordRPC] Season-aware API lookup successful!")
				msg.warn("[mpv_discordRPC] Final API result: '" .. (animeData.title_english or animeData.title) .. "'")
			else
				msg.warn("[mpv_discordRPC] Season-aware API lookup failed, no results found")
			end
		else
			msg.warn("[mpv_discordRPC] No anime title extracted from filename")
		end

		if animeData and animeData.images then
			largeImageKey = animeData.images.webp.large_image_url or animeData.images.jpg.large_image_url
			largeImageText = animeData.title_english or animeData.title
			msg.warn("[mpv_discordRPC] Cover art set from API")
		end

		-- Set main details (top line) to official anime title (or cleaned title if no API)
		local newDetails = (animeData and (animeData.title_english or animeData.title)) or cleanAnimeTitle or details
		msg.warn("[mpv_discordRPC] Details set to: " .. tostring(newDetails))
		details = newDetails

		-- Set state (bottom line) to episode from filename
		local newState = episodeFromFilename or "No episode info"
		msg.warn("[mpv_discordRPC] State set to: " .. tostring(newState))
		state = newState

		msg.warn("[mpv_discordRPC] ===== SENDING TO DISCORD =====")
	end
	-- set `presence`
	local presence = {
		state = state,
		details = details,
		largeImageKey = largeImageKey,
		largeImageText = largeImageText,
		smallImageKey = smallImageKey,
		smallImageText = smallImageText,
	}
	-- Set timestamps for playing media
	if play and elapsed and duration then
		presence.startTimestamp = math.floor(timeNow - elapsed)
		presence.endTimestamp = math.floor(timeNow - elapsed + duration)
	end
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
			presence.state, presence.details, presence.startTimestamp or "none", presence.endTimestamp or "none",
			presence.largeImageKey, presence.largeImageText, presence.smallImageKey, presence.smallImageText, o.periodic_timer)
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

-- Force update on file load
mp.register_event("file-loaded", function()
	main()
end)

-- run `main` function periodically
mp.add_periodic_timer(o.periodic_timer, main)
