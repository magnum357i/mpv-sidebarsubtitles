--[[

╔════════════════════════════════╗
║      MPV sidebarsubtitles      ║
║             v1.0.4             ║
╚════════════════════════════════╝

## Required ##
FFmpeg

]]

local mp      = require 'mp'
local assdraw = require 'mp.assdraw'
local options = require 'mp.options'
local utils   = require "mp.utils"
local utf8    = require 'fastutf8'

local config  = {

    width                  = 300,
    padding_x              = 14,
    padding_y              = 7,
    max_len                = 35,
    bar_width              = 3,
    bar_min_height         = 50,
    hide_loaded_subtitle   = false,
    round                  = 15,
    sort_lines             = true,
    remove_repeating_lines = true
}

options.read_options(config, "sidebarsubtitles")

local isWindows      = package.config:sub(1, 1) ~= '/'
local seperator      = isWindows and "//" or "\\"
local offset         = 1
local currentIndex   = 0
local subtitles      = {}
local tempSubtitles  = {}
local sidebarEnabled = false
local search         = {enabled = false, refresh = false, text = "", cursor = 0, timer = nil, resultTimer = nil, processing = false,}
local data           = {}
local customThemes   = {}
local paths          = {

    hash        = nil,
    temp        = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp",
    cacheFolder = "mpvsidebarsubtitles",
    filename    = "<id>"
}

local colors         = {

    background         = "161616",
    rowText            = "FFFFFF",
    rowUpperText       = "888888",
    rowHover           = "0B0B0B",
    rowSelected        = "FFFFFF",
    rowSelectedText    = "000000",
    rowBorder          = "272727",
    searchBackground   = "H676767",
    searchText         = "888888",
    searchHoverText    = "000000",
    searchSelectedText = "00FF00",
    highlight          = "00FFFF",
    scroll             = "888888"
}

local widthOverlay          = mp.create_osd_overlay("ass-events")
widthOverlay.compute_bounds = true
widthOverlay.hidden         = true

local function strip(str)

    str = str
    :gsub("%{.-%}", "")
    :gsub("\\[Nnh]", " ")
    :gsub("%s+", " ")
    :gsub("^%s*(.-)%s*$", "%1")

    return str
end

local function runCommand(args)

    return mp.command_native({

        name           = 'subprocess',
        playback_only  = false,
        capture_stdout = true,
        capture_stderr = true,
        args           = args
    })
end

local function log(str)

    if type(str) == "table" then

        print(utils.format_json(str))
    else

        print(str)
    end
end

local function runAsync(cmd, handleSuccess, handleFail)

    local proc = mp.command_native_async(cmd, function(_, result, _)

        if result.status == 0 then

            handleSuccess()
        else

            handleFail(result.stderr)
        end
    end)
end

local function tableCopy(t)

    local copy = {}

    for k, v in pairs(t) do copy[k] = v end

    return copy
end

local function calculateTextWidth(text, fontSize)

    widthOverlay.res_x, widthOverlay.res_y = data.screenWidth, data.screenHeight
    widthOverlay.data                      = "{\\bord0\\shad0\\b0\\fs"..fontSize.."}"..text
    local res                              = widthOverlay:update()

    return (res and res.x1) and (res.x1 - res.x0) or 0
end

local function getClipboard()

    return mp.get_property("clipboard/text", "")
end

local function time2ms(uTime)

    local h, m, s, cs = uTime:match("(%d+):(%d+):(%d+)%.(%d+)")

    if not h then return 0 end

    return ((tonumber(h) * 3600) + (tonumber(m) * 60) + tonumber(s)) * 1000 + (tonumber(cs) * 10)
end

local function ms2time(uMS)

    if uMS == 0 then return "0:00:00.00" end

    local tSecs = math.floor(uMS / 1000)
    local h     = math.floor(tSecs / 3600)
    local m     = math.floor((tSecs % 3600) / 60)
    local s     = tSecs % 60
    local cs    = math.floor((uMS % 1000) / 10)

    return string.format("%d:%02d:%02d.%02d", h, m, s, cs)
end

local function hash(str)

    local h1, h2, h3 = 0, 0, 0

    for i = 1, #str do

        local b = str:byte(i)

        h1 = (h1 * 31 + b) % 2^32
        h2 = (h2 * 37 + b) % 2^32
        h3 = (h3 * 41 + b) % 2^32
    end

    return string.format("%08x%08x%08x", h1, h2, h3)
end

local function getPath(key)

    paths.hash = paths.hash or hash(mp.get_property("path"))

    local fullPath

    if key == "cache" then

        fullPath = utils.join_path(paths.temp, paths.cacheFolder..seperator..paths.hash)
    elseif key == "subtitlefile" then

        fullPath = utils.join_path(paths.temp, paths.cacheFolder..seperator..paths.hash..seperator..paths.filename:gsub("<id>", mp.get_property_number("sid", 0))..".ass")
    elseif key == "mergedfile" then

        fullPath = utils.join_path(paths.temp, "mpvdualsubtitles"..seperator..paths.hash..seperator.."merged.ass")
    end

    fullPath = fullPath:gsub("\\", "/")
    fullPath = mp.command_native({'expand-path', fullPath})

    return fullPath
end

local function truncate(str, breakingPoint)

    if not breakingPoint and config.max_len > utf8.len(str) then return str end

    local n         = 0
    local inTags    = false
    local breaked   = false
    local chars     = {}
    local lastSpace = 0
    local k         = 0

    for c in utf8.chars(str) do table.insert(chars, c) end

    local deleteThis = false
    local l          = 1

    for i in ipairs(chars) do

        if chars[i] == "{" then inTags = true end

        if not inTags then

            k = k + 1

            if breakingPoint and breakingPoint > 0 then

                if k == config.max_len + 1 then deleteThis = true end

                if k == breakingPoint and l == 1 then

                    deleteThis = false
                    k          = 1
                    l          = l + 1
                end
            else

                if k == config.max_len + 1 then

                    if l == 1 then k = 1 end

                    l = l + 1
                end
            end

            if l > 2 then deleteThis = true end

            if not deleteThis then

                if l < 3 and chars[i] == " " then lastSpace = i end

                if k == 1 and l == 2 then

                    if chars[i] == "-" then

                        chars[i] = "\\N"..chars[i]
                    else

                        if chars[i] == " " or (chars[i + 1] and chars[i + 1] == " ") then

                            chars[i] = chars[i].."\\N"
                        else

                            if lastSpace > 0 then

                                k                = k + (i - lastSpace + 1)
                                chars[lastSpace] = chars[lastSpace].."\\N"
                            else

                                chars[i] = chars[i].."\\N"
                            end
                        end
                    end
                end
            else

                chars[i] = ""
            end

            --print("i="..i.." | k="..k.." | l="..l.." | lastSpace="..lastSpace..' | char="'..chars[i]..'"')
        end

        if chars[i] and chars[i] == "}" then inTags = false end
    end

    return table.concat(chars, "")
end

local function highlighter(str, selected)

    if search.text == "" or search.processing then return str end

    text               = str:lower()
    local searchedText = search.text:lower()
    local matches      = {}

    for si, li in utf8.gfind(text, searchedText) do

        table.insert(matches, {startIndex = si, lastIndex = li})
    end

    log(matches)


    if #matches == 0 then return str end

    local n       = 0
    local m       = 1
    local content = ""

    for c in utf8.chars(str) do

        n              = n + 1
        local preTags  = ""
        local postTags = ""

        if matches[m].startIndex == n then

            preTags = string.format("{\\c&H%s&}", colors.highlight)
        elseif matches[m].lastIndex == n then

            postTags = string.format("{\\c&H%s&}", selected and colors.rowSelectedText or colors.rowText)

            if matches[m + 1] then m = m + 1 end
        end

        content = content..preTags..c..postTags
    end

    return content
end

local function drawSidebar(mouseY)

    local lineY = data.screenHeight - data.contentArea
    local ass   = assdraw.ass_new()

    --background

    ass:new_event()
    ass:pos(data.videoWidth, 0)
    ass:append(string.format("{\\bord0\\1c&H%s&}", colors.background))
    ass:draw_start()
    ass:rect_cw(0, 0, config.width, data.screenHeight)
    ass:draw_stop()

    --no results found

    if #subtitles == 0 then

        ass:new_event()
        ass:pos(data.videoWidth + config.padding_x, lineY + config.padding_y)
        ass:append(string.format("{\\bord0\\an7\\b0\\1c&H%s&\\fs%s}", colors.rowText, data.bottomFontSize))
        ass:append("No results found.")
    end

    --search

    local searchBoxX, searchBoxY = data.videoWidth + config.padding_x, config.padding_y
    local searchBoxW, searchBoxH = config.width - config.padding_x * 2, data.searchBoxHeight
    local searchTextArea         = searchBoxW - data.searchBoxPaddingX
    local preCursor, postCursor
    local preCursorWidth, searchTextWidth, searchTextOffset


    if search.enabled or search.text ~= "" then

        preCursor        = search.cursor == 0 and "" or utf8.sub(search.text, 1, search.cursor)
        postCursor       = utf8.sub(search.text, search.cursor + 1, 0)
        preCursorWidth   = calculateTextWidth(preCursor, data.searchFontSize)
        searchTextWidth  = calculateTextWidth(preCursor..postCursor, data.searchFontSize)
        searchTextOffset = searchTextWidth > searchTextArea and math.max(0, math.min(preCursorWidth - searchTextArea / 2, searchTextWidth - searchTextArea)) or 0
    end

    if search.enabled then

        --box

        ass:new_event()
        ass:pos(searchBoxX, searchBoxY)
        ass:append(string.format("{\\bord0\\1c&H%s&}", colors.searchBackground))
        ass:draw_start()
        ass:round_rect_cw(0, 0, searchBoxW, searchBoxH, config.round, config.round)
        ass:draw_stop()

        --text

       ass:new_event()
       ass:pos(searchBoxX + data.searchBoxPaddingX - searchTextOffset, searchBoxY + data.searchBoxPaddingY)
       ass:append(string.format("{\\clip(%s,%s,%s,%s)\\bord0\\1c&H%s&\\fs%s}", searchBoxX + data.searchBoxPaddingX, searchBoxY, searchBoxX + searchBoxW - data.searchBoxPaddingX, searchBoxY + searchBoxH, colors.searchHoverText, data.searchFontSize))
       ass:append(preCursor..postCursor)

        --cursor

       ass:new_event()
       ass:pos(searchBoxX + data.searchBoxPaddingX - 1 - searchTextOffset, config.padding_y + data.searchBoxPaddingY)
       ass:append(string.format("{\\clip(%s,%s,%s,%s)\\bord0\\alpha&HFF&\\fs%s}", searchBoxX, searchBoxY, searchBoxX + searchBoxW, searchBoxY + searchBoxH, data.searchFontSize))
       ass:append(preCursor..string.format("{\\alpha&H00&\\p1\\c&H%s&}m 0 0 l 1 0 l 1 %s l 0 %s{\\p0\\alpha&HFF&}", colors.searchHoverText, data.searchFontSize, data.searchFontSize)..postCursor)
    else

        --box

        ass:new_event()
        ass:pos(searchBoxX, searchBoxY)
        ass:append(string.format("{\\bord0\\1c&H%s&\\alpha&HC8&}", colors.searchBackground))
        ass:draw_start()
        ass:round_rect_cw(0, 0, searchBoxW, searchBoxH, config.round, config.round)
        ass:draw_stop()

        --text

        ass:new_event()
        ass:append(string.format("{\\bord0\\1c&H%s&\\fs17}", colors.searchText))

        if search.text ~= "" then

            ass:pos(searchBoxX + data.searchBoxPaddingX - searchTextOffset, config.padding_y + data.searchBoxPaddingY)
            ass:append(string.format("{\\clip(%s,%s,%s,%s)\\bord0\\1c&H%s&\\fs%s}", searchBoxX, searchBoxY, searchBoxX + searchBoxW, searchBoxY + searchBoxH, colors.searchText, data.searchFontSize))
            ass:append(preCursor..postCursor)
        else

            ass:pos(searchBoxX + data.searchBoxPaddingX, config.padding_y + data.searchBoxPaddingY)
            ass:append("Search...")
        end

        --icon

        ass:new_event()
        ass:pos(searchBoxX + config.width - config.padding_x * 2 - 33, config.padding_y + 7)
        ass:append(string.format("{\\bord0\\1c&H%s&\\fs7\\p1\\fscx40\\fscy40}", colors.searchText))
        ass:append("m 16 0 b 24 0 32 8 32 16 b 32 24 24 32 16 32 b 8 32 0 24 0 16 b 0 8 8 0 16 0 m 30 28 l 25 32 l 33 40 l 38 36 m 6 16 b 6 22 10 26 16 26 b 22 26 26 22 26 16 b 26 10 22 6 16 6 b 10 6 6 10 6 16")
    end

    local firstRow = true

    for i = offset, offset + data.lineCount - 1 do

        local selected = false

        if not search.processing and currentIndex == i then selected = true end

        --border

        if not firstRow then

           ass:new_event()
           ass:pos(data.videoWidth, lineY)
           ass:append(string.format("{\\bord0\\1c&H%s&}", colors.rowBorder))
           ass:draw_start()
           ass:rect_cw(0, 0, config.width, data.borderHeight)
           ass:draw_stop()
        end

        --selected

        if selected then

            --box

            ass:new_event()
            ass:pos(data.videoWidth, lineY + data.borderHeight)
            ass:append(string.format("{\\bord0\\1c&H%s&}", colors.rowSelected))
            ass:draw_start()
            ass:rect_cw(0, 0, config.width, data.lineHeight - data.borderHeight)
            ass:draw_stop()

            --icon

            ass:new_event()
            ass:pos(data.videoWidth + 3, lineY + data.borderHeight + data.lineHeight / 2 - 5)
            ass:append(string.format("{\\bord0\\1c&H%s&}", colors.rowSelectedText))
            ass:draw_start()

            local triX, triY = 0, 0
            local triW, triH = 80, 100

            ass:append(string.format("m %f %f l %f %f l %f %f l %f %f", triX, triY, triX, triY + triH, triX + triW, triY + triH/2, triX, triY))
            ass:draw_stop()
        else

            --hover

            if not search.processing and mouseY and mouseY > lineY and mouseY < lineY + data.lineHeight then

                ass:new_event()
                ass:pos(data.videoWidth, lineY + data.borderHeight)
                ass:append(string.format("{\\bord0\\1c&H%s&}", selected and colors.rowSelected or colors.rowHover))
                ass:draw_start()
                ass:rect_cw(0, 0, config.width, data.lineHeight - data.borderHeight)
                ass:draw_stop()
            end
        end

        --top text

        ass:new_event()
        ass:pos(data.videoWidth + config.padding_x, lineY + config.padding_y)
        ass:append(string.format("{\\bord0\\an7\\b1\\1c&H%s&\\fs%s}", (selected) and colors.rowSelectedText or colors.rowUpperText, data.topFontSize))

        if search.processing then ass:append("{\\alpha&HC8&}") end

        ass:append(string.format("#%d", i))

        ass:new_event()
        ass:pos(data.videoWidth + config.width - config.padding_x, lineY + config.padding_y)
        ass:append(string.format("{\\b0\\an9\\bord0\\1c&H%s&\\fs%s}", selected and colors.rowSelectedText or colors.rowUpperText, data.topFontSize))

        if search.processing then ass:append("{\\alpha&HC8&}") end

        ass:append(string.format("%s - %s", ms2time(subtitles[i].startTime * 1000), ms2time(subtitles[i].endTime * 1000)))

        local text          = subtitles[i].text
        local breakingPoint = utf8.find(text, "...%-%s")

        --bottom text

        ass:new_event()
        ass:pos(data.videoWidth + config.padding_x, lineY + config.padding_y + data.topFontSize + data.lineMargin)
        ass:append(string.format("{\\bord0\\an7\\b0\\1c&H%s&\\fs%s}", selected and colors.rowSelectedText or colors.rowText, data.bottomFontSize))

        if search.processing then ass:append("{\\alpha&HC8&}") end

        text = highlighter(text, selected)
        text = truncate(text, breakingPoint and breakingPoint + 3 or breakingPoint)

        ass:append(text)

        lineY    = lineY + data.lineHeight
        firstRow = false
    end

    --scroll

    if #subtitles > data.lineCount then

        lineY            = data.screenHeight - data.contentArea + data.borderHeight
        local barX       = data.videoWidth + config.width - config.bar_width
        local barHeight  = math.max(data.maxOffset * 0.1, config.bar_min_height)
        local barY       = (data.contentArea - barHeight - data.borderHeight) * ((offset - 1) / (data.maxOffset - 1))

        ass:new_event()
        ass:pos(barX, lineY + barY)
        ass:append(string.format("{\\1c&H%s&\\bord0}", colors.scroll))
        ass:draw_start()
        ass:rect_cw(0, 0, config.bar_width, barHeight)
        ass:draw_stop()
    end

    mp.set_osd_ass(data.screenWidth, data.screenHeight, ass.text)
end

local function fillData()

    local mergedFile                    = io.open(getPath("mergedfile"), "r")
    local currentTitle                  = mp.get_property_native("current-tracks/sub/title", "")
    data.merged                         = (mergedFile and currentTitle == "merged.ass")
    data.searchBoxPaddingX              = 15
    data.searchBoxPaddingY              = 7
    data.searchBoxHeight                = 30
    data.searchFontSize                 = 17
    data.topFontSize                    = 13
    data.bottomFontSize                 = 17
    data.lineMargin                     = 5
    data.borderHeight                   = 1
    data.screenWidth, data.screenHeight = mp.get_osd_size()
    data.videoWidth                     = data.screenWidth - config.width
    data.lineHeight                     = data.topFontSize + data.bottomFontSize * 2 + data.lineMargin + config.padding_y * 2
    data.contentArea                    = data.screenHeight - (data.searchBoxHeight + config.padding_y * 2)
    data.lineCount                      = math.floor(data.contentArea / data.lineHeight)
    data.lineCount                      = data.lineCount > #subtitles and #subtitles or data.lineCount
    data.maxOffset                      = #subtitles - data.lineCount + 1
    local gap                           = #subtitles ~= data.lineCount and (data.contentArea - data.lineHeight * data.lineCount) / data.lineCount or 0
    data.lineHeight                     = data.lineHeight + gap
end

local function detectUOSC()

    local scriptPath = mp.command_native({'expand-path', '~~/scripts/uosc'})
    local f          = io.open(scriptPath..'/main.lua', 'r')

    if f then

        f:close()

        return true
    end

    return false
end

local function togglePlayerControls(mode)

    if defaultSubMargin == nil then defaultSubMargin = mp.get_property("sub-use-margins") end

    if sidebarEnabled then

        if config.hide_loaded_subtitle then mp.set_property_native("sub-visibility", "yes") end

        mp.set_property("sub-use-margins", defaultSubMargin)
        mp.commandv("set", "video-margin-ratio-right", 0)

        if customThemes.uosc then

            mp.commandv('script-message-to', 'uosc', 'sidebarsubtitles', 0)

        else

            mp.command("script-message osc-visibility auto")
        end
    else

        if config.hide_loaded_subtitle then mp.set_property_native("sub-visibility", "no") end

        mp.set_property("sub-use-margins", "no")
        mp.commandv("set", "video-margin-ratio-right", config.width / data.screenWidth)

        if customThemes.uosc then

            mp.commandv('script-message-to', 'uosc', 'sidebarsubtitles', data.videoWidth)

        else

            mp.command("script-message osc-visibility never")
        end
    end
end

local function initSidebar()

    fillData()

    if not sidebarEnabled then

        togglePlayerControls()

        drawSidebar()
    else

        mp.set_osd_ass(0, 0, "")

        togglePlayerControls()
    end

    sidebarEnabled = not sidebarEnabled
end

local function tryGetSubtitles()

    local file

    if data.merged then

        file = io.open(getPath("mergedfile"), "r")
    else

        local currentSubtitle = mp.get_property_native("current-tracks/sub", "")

        if currentSubtitle.external then

            local sourceFile = currentSubtitle["external-filename"]
            local targetFile = getPath("subtitlefile")

            if currentSubtitle.codec == "ass" then

                if isWindows then

                    runCommand({"powershell", "-NoProfile", "-Command", string.format("Copy-Item -LiteralPath \"%s\" -Destination \"%s\" -Force", sourceFile, targetFile)})
                else

                    runCommand({"cp", sourceFile, targetFile})
                end
            elseif currentSubtitle.codec == "subrip" then

                runCommand({"ffmpeg", "-i", sourceFile, "-c:s", "ass", targetFile})
            end
        end

        file = io.open(getPath("subtitlefile"), "r")
    end

    if file then

        local content  = file:read("*all")
        local prevLine = {}

        for line in content:gmatch("Dialogue:[^\n]+") do

            local t = {line:match("^Dialogue:%s([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.+)$")}

            if t then

                local deleteThis = false
                t[10]            = strip(t[10])

                if data.merged and t[4] ~= "Primary" then deleteThis = true end

                if config.remove_repeating_lines and prevLine then

                    if prevLine[10] == t[10] and (prevLine[2] == t[2] or prevLine[3] == t[2]) then deleteThis = true end
                end

                if not deleteThis then table.insert(subtitles, {startTime = time2ms(t[2]) / 1000, endTime = time2ms(t[3]) / 1000, text = t[10]}) end

                prevLine = t
            end
        end

        if #subtitles > 0 then

            if config.sort_lines then

                table.sort(subtitles, function(a, b)

                    return tonumber(a.startTime) < tonumber(b.startTime)
                end)
            end

            mp.osd_message("")

            initSidebar()

            return true
        end

        mp.osd_message("The subtitle format is invalid.")

        return true
    end

    mp.osd_message("Subtitle not found!")

    return false
end

local function initSidebarWhenSubtitlesLoaded()

    local tempPath = getPath("cache")

    if not os.rename(tempPath, tempPath) then

        runCommand({"powershell", "-NoProfile", "-Command", "mkdir", tempPath})
    end

    local ok

    ok = tryGetSubtitles()

    if ok then return end

    mp.osd_message("Getting subtitles...", 9999)

    local args = {}

    table.insert(args, "ffmpeg")
    table.insert(args, "-i")
    table.insert(args, mp.get_property("path"))

    table.insert(args, "-map")
    table.insert(args, string.format("0:s:%s", mp.get_property_number("sid", 0) - 1))
    table.insert(args, "-c:s")
    table.insert(args, "ass")
    table.insert(args, getPath("subtitlefile"))

    table.insert(args, "-vn")
    table.insert(args, "-an")
    table.insert(args, "-dn")
    table.insert(args, "-y")

    local ffmpegCommand = {

        name           = "subprocess",
        capture_stdout = true,
        capture_stderr = true,
        playback_only  = false,
        args           = args
    }

    local onSubtitleFail = function (result)

        if string.match(result, "No such file or directory") then

            mp.osd_message("No such file or directory.", 3)
        elseif string.match(result, "Failed to set value") then

            mp.osd_message("Wrong subtitle id.", 3)
        else

            h.log(result)
            mp.osd_message("See the console for details.", 3)
        end
    end

    runAsync(ffmpegCommand, function()

        tryGetSubtitles()
    end, onSubtitleFail)
end

local function toggleSidebar()

    if customThemes.uosc == nil then customThemes.uosc = detectUOSC() end

    if #subtitles == 0 then

        initSidebarWhenSubtitlesLoaded()

        return
    end

    initSidebar()
end

local function findIndexByTime()

    local startTime = mp.get_property_number("sub-start")

    if not startTime then return 0 end

    local index = 0

    --visible rows

    if data.lineCount and data.lineCount > 0 then

        for i = offset, offset + data.lineCount - 1 do

            if math.floor(subtitles[i].startTime) == math.floor(startTime) then

                index = i

                break
            end
        end

        if index > 0 then return index end
    end

    --fhe first row not shown on screen at the current offset

    if subtitles[offset + data.lineCount] and math.floor(subtitles[offset + data.lineCount].startTime) == math.floor(startTime) then

        index  = offset + data.lineCount
        offset = index

        return index
    end

    --last resort, searching from the beginning

    for i in ipairs(subtitles) do

        if math.floor(subtitles[i].startTime) == math.floor(startTime) then

            index = i

            break
        end
    end

    if index > 0 then offset = index end

    return index
end

local function cursorInSidebarSearch()

    if not sidebarEnabled then return end

    local x, y = mp.get_mouse_pos()

    return x >= (data.videoWidth + config.padding_x) and x <= (data.videoWidth + config.width - config.padding_x) and y >= config.padding_y and y <= (config.padding_y + data.searchBoxHeight)
end

local function cursorInSidebar()

    if not sidebarEnabled then return end

    local x, y = mp.get_mouse_pos()

    return x >= data.videoWidth and x <= data.videoWidth + config.width
end

local function searchResults()

    if #tempSubtitles == 0 then tempSubtitles = tableCopy(subtitles) end

    subtitles          = {}
    local searchedText = search.text:lower()
    local c            = 0

    for i in ipairs(tempSubtitles) do

        if string.find(tempSubtitles[i].text:lower(), searchedText, 1, true) then

            table.insert(subtitles, tempSubtitles[i])
        end
    end

    search.processing = false
    offset            = 1

    fillData()
    drawSidebar()

    if #tempSubtitles == #subtitles then tempSubtitles = {} end
end

local function enter()

    search.processing = true

    if search.resultTimer then search.resultTimer:kill() end

    search.resultTimer = mp.add_timeout(3, searchResults)
end

local searchBindings = {

    cursorhome = {
        key  = "home",
        func = function ()

            search.refresh = true
            search.cursor  = 0
        end,
        opts = nil
    },

    cursorend = {

        key  = "end",
        func = function ()

            search.refresh = true
            search.cursor  = utf8.len(search.text)
        end,
        opts = nil
    },

    cursorleft = {
        key  = "left",
        func = function ()

            search.refresh = true
            search.cursor  = search.cursor - 1
            search.cursor  = math.max(search.cursor, 0)
        end,
        opts = {repeatable = true}
    },

    cursorright = {

        key  = "right",
        func = function ()

            search.refresh  = true
            local charCount = utf8.len(search.text)
            search.cursor   = search.cursor + 1
            search.cursor   = math.min(search.cursor, charCount)
        end,
        opts = {repeatable = true}
    },

    paste = {

        key  = "ctrl+v",
        func = function ()

            search.refresh   = true
            local preCursor  = utf8.sub(search.text, 1,                 search.cursor)
            local postCursor = utf8.sub(search.text, search.cursor + 1, 0)
            local clipboard  = getClipboard()
            search.text      = preCursor..clipboard..postCursor
            search.cursor    = search.cursor + utf8.len(clipboard)

            enter()
        end,
        opts = nil
    },

    deletebackward = {

        key  = "bs",
        func = function ()

            search.refresh = true

            if search.cursor == 0 then return end

            search.cursor    = search.cursor - 1
            search.cursor    = math.max(search.cursor, 0)
            local preCursor  = search.cursor == 0 and "" or utf8.sub(search.text, 1, search.cursor)
            local postCursor = utf8.sub(search.text, search.cursor + 2, 0)
            search.text      = preCursor..postCursor

            enter()
        end,
        opts = {repeatable = true}
    },

    deleteforward = {

        key  = "del",
        func = function ()

            search.refresh  = true
            local charCount = utf8.len(search.text)

            if charCount == search.cursor then return end

            local preCursor  = search.cursor == 0 and "" or utf8.sub(search.text, 1, search.cursor)
            local postCursor = utf8.sub(search.text, search.cursor + 2, 0)
            search.text      = preCursor..postCursor

            enter()
        end,
        opts = {repeatable = true}
    },

    input = {

        key  = "ANY_UNICODE",
        func = function (info)

            if info.key_text and (info.event == "press" or info.event == "down" or info.event == "repeat") then

                search.refresh   = true
                local charCount  = utf8.len(search.text)

                if charCount == 0 then

                    search.text      = info.key_text
                else

                    local preCursor  = utf8.sub(search.text, 1,                 search.cursor)
                    local postCursor = utf8.sub(search.text, search.cursor + 1, 0)
                    search.text      = preCursor..info.key_text..postCursor
                end

                search.cursor = search.cursor + 1

                enter()
            end
        end,
        opts = {repeatable = true, complex = true}
    }
}

mp.observe_property("sub-text/ass", "native", function(_, text)

    if not search.processing and sidebarEnabled and text and text ~= "" and not cursorInSidebar() then

        local foundedIndex = findIndexByTime()

        if foundedIndex > 0 then

            currentIndex = foundedIndex

            drawSidebar()
        end
    end
end)

mp.add_forced_key_binding("mbtn_left", "sidebarsubtitles_click", function()

    if not search.processing and cursorInSidebar() then

        local lineY     = data.screenHeight - data.contentArea
        local _, mouseY =  mp.get_mouse_pos()

        for i = offset, offset + data.lineCount - 1 do

            if mouseY and mouseY > lineY and mouseY < lineY + data.lineHeight then

                currentIndex = i

                mp.commandv("seek", subtitles[i].startTime + 0.01, "absolute+exact")

                drawSidebar()
            end

            lineY = lineY + data.lineHeight
        end
    end

    if cursorInSidebarSearch() then

        search.enabled = true
        search.refresh = true

        for name, binding in pairs(searchBindings) do

            mp.add_forced_key_binding(binding.key, "sidebarsubtitles_search"..name, binding.func, binding.opts)
        end

        search.timer = mp.add_periodic_timer(0.05, function()

            if search.refresh then

                drawSidebar()

                search.refresh = false
            end
        end)
    elseif search.enabled then

        search.enabled = false

        if search.timer then search.timer:kill() end

        drawSidebar()

        for name in pairs(searchBindings) do

            mp.remove_key_binding("sidebarsubtitles_search"..name)
        end
    end
end)

mp.observe_property("mouse-pos", "native", function(_, value)

    if not search.processing and cursorInSidebar() then

        drawSidebar(value.y)
    end
end)

mp.add_forced_key_binding("wheel_up", "sidebarsubtitles_scrollup", function()

    if not search.processing and cursorInSidebar() then

        if offset > 1 then offset = offset - 1 end

        drawSidebar()
    end
end)

mp.add_forced_key_binding("wheel_down", "sidebarsubtitles_scrolldown", function()

    if not search.processing and cursorInSidebar() then

        if data.maxOffset and offset < data.maxOffset then offset = offset + 1 end

        drawSidebar()
    end
end)

mp.observe_property("sid", "number", function(_, value)

    if sidebarEnabled then toggleSidebar() end

    subtitles     = {}
    search.text   = ""
    search.cursor = 0
end)

mp.add_key_binding("h", "sidebarsubtitles", toggleSidebar)