--[[

╔════════════════════════════════╗
║      MPV sidebarsubtitles      ║
║             v1.0.0             ║
╚════════════════════════════════╝

## Required ##
FFmpeg

]]

local mp      = require 'mp'
local assdraw = require 'mp.assdraw'
local options = require 'mp.options'
local utils   = require "mp.utils"

local config  = {

    width                = 300,
    background_color     = "202020",
    padding              = 20,
    max_len              = 35,
    fullscreen_scale     = 1.3,
    bar_width            = 3,
    hide_loaded_subtitle = false
}

options.read_options(config, "sidebarsubtitles")

local offset         = 1
local currentIndex   = 0
local subtitles      = {}
local sidebarEnabled = false
local data           = {}
local customThemes   = {}
local paths          = {

    hash        = nil,
    temp        = os.getenv("TEMP") or os.getenv("TMPDIR") or "/tmp",
    cacheFolder = "mpvsidebarsubtitles",
    filename    = "<id>"
}

local function strip(str)

    str = str:gsub("%{.-%}", "")
    str = str:gsub("\\[Nnh]", " ")
    str = str:gsub("%s+", " ")
    str = str:gsub("^%s+", "")
    str = str:gsub("%s+$", "")

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

local function runAsync(cmd, handleSuccess, handleFail)

    local proc = mp.command_native_async(cmd, function(_, result, _)

        if result.status == 0 then

            handleSuccess()
        else

            handleFail(result.stderr)
        end
    end)
end

local function drawSidebar(mouseY)

    local gap   = ((data.screenHeight - config.padding) - data.lineHeight * data.lineCount) / data.lineCount
    local lineY = config.padding
    offset      = (offset > data.totalLines) and data.totalLines or offset
    local ass   = assdraw.ass_new()

    ass:new_event()
    ass:append(string.format("{\\1c&H%s&}", config.background_color))
    ass:append("{\\alpha&H00&}")
    ass:append("{\\bord0}")
    ass:pos(data.videoWidth, 0)
    ass:draw_start()
    ass:rect_cw(0, 0, config.width, data.screenHeight)
    ass:draw_stop()

    local isScroll = false

    if #subtitles > data.lineCount then

        local barX      = data.videoWidth + config.width - config.bar_width
        local barHeight = math.max(data.screenHeight * (data.lineCount / data.totalLines), 50)
        local barY      = (offset / data.totalLines) * (data.screenHeight - barHeight)

        ass:new_event()
        ass:append("{\\1c&HFFFFFF&\\bord0\\alpha&H80&}")
        ass:pos(barX, barY)
        ass:draw_start()
        ass:rect_cw(0, 0, config.bar_width, barHeight)
        ass:draw_stop()

        isScroll = true
    end

    for i = 1, data.lineCount do

        local selected = false

        if currentIndex == (i + offset - 1) then selected = true end

        --hover

        if mouseY and mouseY > lineY and mouseY < lineY + data.lineHeight then

            ass:new_event()
            ass:append(string.format("{\\1c&H%s&}", selected and "FFFFFF" or "000000"))

            if not selected then ass:append("{\\alpha&H80&}") end

            ass:append("{\\bord0}")
            ass:pos(data.videoWidth, lineY - config.padding / 2)
            ass:draw_start()
            ass:rect_cw(0, 0, isScroll and config.width - config.bar_width or config.width, data.lineHeight)
            ass:draw_stop()
        end

        --pattern/background

        if selected then

            ass:new_event()
            ass:append(string.format("{\\1c&H%s&}", "FFFFFF"))
            ass:append("{\\bord0}")
            ass:pos(data.videoWidth, lineY - config.padding / 2)
            ass:draw_start()
            ass:rect_cw(0, 0, isScroll and config.width - config.bar_width or config.width, data.lineHeight)
            ass:draw_stop()
        else

            if i % 2 == 0 then

                ass:new_event()
                ass:append(string.format("{\\1c&H%s&}", "000000"))
                ass:append("{\\alpha&HC8&}")
                ass:append("{\\bord0}")
                ass:pos(data.videoWidth, lineY - config.padding / 2)
                ass:draw_start()
                ass:rect_cw(0, 0, isScroll and config.width - config.bar_width or config.width, data.lineHeight)
                ass:draw_stop()
            end
        end

        if selected then

            ass:new_event()
            ass:append(string.format("{\\1c&H%s&}", "000000"))
            ass:append("{\\bord0}")
            ass:pos(data.videoWidth + 5, lineY - config.padding / 2 + data.lineHeight / 2 - 5)
            ass:draw_start()

            local triX, triY = 0, 0
            local triW, triH = 80, 100

            ass:append(string.format("m %f %f l %f %f l %f %f l %f %f", triX, triY, triX, triY + triH, triX + triW, triY + triH/2, triX, triY))
            ass:draw_stop()
        end

        --top

        ass:new_event()
        ass:append(string.format("{\\1c&H%s&}", selected and "000000" or "888888"))
        ass:append(string.format("{\\fs%s}", data.topFontSize))
        ass:append("{\\b1}")
        ass:append("{\\an7}")
        ass:append("{\\bord0}")
        ass:pos(data.videoWidth + config.padding, lineY)
        ass:append(string.format("#%d", i + offset - 1))

        ass:new_event()
        ass:append(string.format("{\\1c&H%s&}", selected and "000000" or "888888"))
        ass:append(string.format("{\\fs%s}", data.topFontSize))
        ass:append("{\\alpha&H00&\\b0\\an9\\bord0}")
        ass:pos(data.videoWidth + config.width - config.padding, lineY)
        ass:append(ms2time(subtitles[i + offset - 1].start * 1000))

        --bottom

        ass:new_event()
        ass:append(string.format("{\\1c&H%s&}", selected and "000000" or "FFFFFF"))
        ass:append(string.format("{\\fs%s}", data.bottomFontSize))
        ass:append("{\\b0}")
        ass:append("{\\an7}")
        ass:append("{\\bord0}")
        ass:pos(data.videoWidth + config.padding, lineY + data.topFontSize + 5)
        ass:append(truncate(subtitles[i + offset - 1].text, config.max_len))

        lineY = lineY + data.lineHeight + gap
    end

    mp.set_osd_ass(data.screenWidth, data.screenHeight, ass.text)
end

local function fillData()

    data.topFontSize                    = 13
    data.bottomFontSize                 = 17
    data.screenWidth, data.screenHeight = mp.get_osd_size()
    data.videoWidth                     = data.screenWidth - config.width
    data.lineHeight                     = data.topFontSize + data.bottomFontSize * 2 + 5 + config.padding
    data.lineCount                      = math.floor((data.screenHeight - config.padding) / data.lineHeight)
    data.totalLines                     = #subtitles - data.lineCount + 1
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

        drawSidebar(1)
    else

        mp.set_osd_ass(0, 0, "")

        togglePlayerControls()
    end

    sidebarEnabled = not sidebarEnabled
end

function hash(str)

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
    local isWindows = package.config:sub(1, 1) ~= '/'
    local seperator = isWindows and "//" or "\\"

    if key == "cache" then

        fullPath = utils.join_path(paths.temp, paths.cacheFolder..seperator..paths.hash)
    elseif key == "subtitlefile" then

        fullPath = utils.join_path(paths.temp, paths.cacheFolder..seperator..paths.hash..seperator..paths.filename:gsub("<id>", mp.get_property_number("sid", 0))..".ass")
    end

    fullPath = fullPath:gsub("\\", "/")
    fullPath = mp.command_native({'expand-path', fullPath})

    return fullPath
end

local function tryGetSubtitles()

    local file = io.open(getPath("subtitlefile"), "r")

    if file then

        local content = file:read("*all")

        for line in content:gmatch("Dialogue:[^\n]+") do

            local t = {line:match("^Dialogue:%s([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),([^,]*),(.+)$")}

            if t then

                table.insert(subtitles, {start = time2ms(t[2]) / 1000, text = strip(t[10])})
            end
        end

        if #subtitles > 0 then

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

    local ok

    ok = tryGetSubtitles()

    if ok then return end

    mp.osd_message("Getting subtitles...", 9999)

    local tempPath = getPath("cache")

    if not os.rename(tempPath, tempPath) then

        runCommand({"powershell", "-NoProfile", "-Command", "mkdir", tempPath})
    end

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

function truncate(str, maxLen)

    if len(str) <= maxLen then return str end

    local lCount  = 0
    local content = ""
    local breaked = false

    for word in str:gmatch(".-%s") do

        local wLen = len(word)

        if (lCount + wLen) > (maxLen * 2) then

            content = content:gsub("%s+$", "").."..."
            break
        end

        if (lCount + wLen) > maxLen and not breaked then

            breaked = true
            content = content.."\\N"
        end

        content = content..word
        lCount  = lCount + wLen
    end

    return content
end

function len(str)

    local n = 0

    for c in str:gmatch("[%z\1-\127\194-\244][\128-\191]*") do n = n + 1 end

    return n
end

function findIndexByTime()

    local start = mp.get_property_number("sub-start")
    local index = 0

    if data.lineCount and data.lineCount > 0 then

        for i = 1, data.lineCount do

            if math.floor(subtitles[i + offset - 1].start) == math.floor(start) then

                index = i + offset - 1

                break
            end
        end
    end

    if index > 0 then return index end

    for i in ipairs(subtitles) do

        if math.floor(subtitles[i].start) == math.floor(start) then

            index = i

            break
        end
    end

    if index > 0 then offset = index end

    return index
end


function cursorInSidebar()

    if not sidebarEnabled then return end

    local screenWidth, screenHeight = mp.get_osd_size()
    local videoWidth                = screenWidth - config.width

    local x, y = mp.get_mouse_pos()

    return x >= videoWidth and x <= videoWidth + config.width
end

function time2ms(uTime)

    local h, m, s, cs = uTime:match("(%d+):(%d+):(%d+)%.(%d+)")

    if not h then return 0 end

    return ((tonumber(h) * 3600) + (tonumber(m) * 60) + tonumber(s)) * 1000 + (tonumber(cs) * 10)
end

function ms2time(uMS)

    if uMS == 0 then return "0:00:00.00" end

    local tSecs = math.floor(uMS / 1000)
    local h     = math.floor(tSecs / 3600)
    local m     = math.floor((tSecs % 3600) / 60)
    local s     = tSecs % 60
    local cs    = math.floor((uMS % 1000) / 10)

    return string.format("%d:%02d:%02d.%02d", h, m, s, cs)
end

mp.observe_property("sub-text", "native", function(_, text)

    if sidebarEnabled and text and text ~= "" and not cursorInSidebar() then

        local foundedIndex = findIndexByTime()

        if foundedIndex > 0 then

            currentIndex = foundedIndex

            drawSidebar()
        end
    end
end)

mp.add_forced_key_binding("mbtn_left", "sidebarsubtitlesclick", function()

    if cursorInSidebar() then

        local gap       = ((data.screenHeight - config.padding) - data.lineHeight * data.lineCount) / data.lineCount
        local lineY     = config.padding
        local _, mouseY =  mp.get_mouse_pos()

        for i = 1, data.lineCount do

            if mouseY and mouseY > lineY and mouseY < lineY + data.lineHeight then

                local index = offset + i - 1

                mp.commandv("seek", subtitles[index].start, "absolute+exact")
            end

            lineY = lineY + data.lineHeight + gap
        end
    end
end)


mp.observe_property("mouse-pos", "native", function(_, value)

    if cursorInSidebar() then

        drawSidebar(value.y)
    end
end)

mp.add_forced_key_binding("wheel_up", "sidebarsubtitlesscrollup", function()

    if cursorInSidebar() then

        offset = offset > 1 and offset - 1 or offset
        drawSidebar()
    end
end)

mp.add_forced_key_binding("wheel_down", "sidebarsubtitlesscrolldown", function()

    if cursorInSidebar() then

        offset = offset >= #subtitles and #subtitles or offset + 1
        drawSidebar()
    end
end)

mp.add_key_binding("h", "sidebarsubtitles", toggleSidebar)