--v1.3
local utf8  = require "fastutf8"
local input = {}
local cursor, text, s_width, s_height, b_width, cached

local text_overlay          = mp.create_osd_overlay("ass-events")
text_overlay.compute_bounds = true
text_overlay.hidden         = true

local function build_lines(pre_c, post_c, o)

    return
    string.format("{\\bord0\\c&H%s&\\fs%s}", input.cursor_theme == "black" and "000000" or "FFFFFF", input.font_size)..pre_c..post_c,
    string.format("{\\bord0\\alpha&HFF&\\fs%s}", input.font_size)..pre_c..string.format("{\\alpha&H00&\\p1\\c&H%s&}m 0 0 l 1 0 l 1 %s l 0 %s{\\p0\\alpha&HFF&}", input.cursor_theme == "black" and "000000" or "FFFFFF", input.font_size, input.font_size)..post_c,
    o
end

local function filter(str)

    if input.accept_only == "" then

        return str
    elseif input.accept_only == "digits" then

        return str:gsub("%D+", "")
    elseif input.accept_only == "text" then

        return str:gsub("%d+", "")
    end
end

local function get_text_width(text)

    text_overlay.res_x, text_overlay.res_y = s_width, s_height
    text_overlay.data                      = "{\\fs"..input.font_size.."}"..text
    local res                              = text_overlay:update()

    return (res and res.x1) and (res.x1 - res.x0) or 0
end

local function get_clipboard()

    local text = mp.get_property("clipboard/text", "")
    text       = text:gsub("^%s*(.-)%s*$", "%1")
    text       = filter(text)

    return text
end

function input.get_text()

    return text
end

function input.texts()

    if text == "" then return "", string.format("{\\bord0\\p1\\c&H%s&}m 0 0 l 1 0 l 1 %s l 0 %s", input.cursor_theme == "black" and "000000" or "FFFFFF", input.font_size, input.font_size), 0 end

    if cached.text and (cached.text == text and cached.cursor == cursor) then return build_lines(cached.pre_cursor, cached.post_cursor, cached.offset) end

    local pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
    local post_cursor = utf8.sub(text, cursor + 1, 0)
    local offset      = 0

    if s_width > 0 and s_height > 0 and b_width > 0 then

        local pre_cursor_width  = get_text_width(pre_cursor)
        local search_text_width = get_text_width(pre_cursor..post_cursor)

        offset = search_text_width > b_width and math.max(0, math.min(pre_cursor_width - b_width / 2, search_text_width - b_width)) or 0
    end

    cached.text        = text
    cached.cursor      = cursor
    cached.pre_cursor  = pre_cursor
    cached.post_cursor = post_cursor
    cached.offset      = offset

    return build_lines(pre_cursor, post_cursor, offset)
end

function input.calculate_offset(width, height, bar_width)

    s_width  = width
    s_height = height
    b_width  = bar_width
end

--after_changes, edit_clipboard(text)
function input.bindings(hooks)

    local list = {

        cursorhome = {

            key  = "home",
            func = function ()

                cursor = 0

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = nil
        },

        cursorend = {

            key  = "end",
            func = function ()

                cursor = utf8.len(text)

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = nil
        },

        cursorleft = {
            key  = "left",
            func = function ()

                if text ~= "" and input.format ~= "" and cursor > 0 and string.find(utf8.sub(text, cursor, cursor), "%p") then

                    cursor = cursor - 1
                end

                cursor = cursor - 1
                cursor = math.max(cursor, 0)

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        cursorright = {

            key  = "right",
            func = function ()

                local count = utf8.len(text)
                cursor      = cursor + 1

                if text ~= "" and input.format ~= "" and string.find(utf8.sub(text, cursor + 1, cursor + 1), "%p") then

                    cursor = cursor + 1
                end

                cursor = math.min(cursor, count)

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        paste = {

            key  = "ctrl+v",
            func = function ()

                local clipboard_text = get_clipboard()

                if input.format ~= "" then

                    if hooks and hooks.edit_clipboard then clipboard_text = hooks.edit_clipboard(clipboard_text) end

                    if not string.find(clipboard_text, "^"..input.format.."$") then return end

                    text   = clipboard_text
                    cursor = utf8.len(text)

                    if hooks and hooks.after_changes then hooks.after_changes() end

                    return
                end

                local count = utf8.len(text)

                if count >= input.max_length then return end

                local pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                local post_cursor = utf8.sub(text, cursor + 1, 0)
                clipboard_text    = utf8.sub(clipboard_text, 1, input.max_length - count)
                text              = pre_cursor..clipboard_text..post_cursor
                cursor            = cursor + utf8.len(clipboard_text)

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        deletebackward = {

            key  = "bs",
            func = function ()

                if input.format ~= "" then return end

                if cursor == 0 then return end

                cursor            = cursor - 1
                cursor            = math.max(cursor, 0)
                local pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                local post_cursor = utf8.sub(text, cursor + 2, 0)
                text              = pre_cursor..post_cursor

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        deleteforward = {

            key  = "del",
            func = function ()

                if input.format ~= "" then return end

                local count = utf8.len(text)

                if count == cursor then return end

                local pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                local post_cursor = utf8.sub(text, cursor + 2, 0)
                text              = pre_cursor..post_cursor

                if hooks and hooks.after_changes then hooks.after_changes() end
            end,
            opts = {repeatable = true}
        },

        input = {

            key  = "any_unicode",
            func = function (info)

                if info.key_text and filter(info.key_text) ~= "" and (info.event == "press" or info.event == "down" or info.event == "repeat") then

                    local pre_cursor, post_cursor
                    local count = utf8.len(text)

                    if input.format == "" then

                        if count >= input.max_length then return end

                        if count == 0 then

                            text = info.key_text
                        else

                            pre_cursor  = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                            post_cursor = utf8.sub(text, cursor + 1, 0)
                            text        = pre_cursor..info.key_text..post_cursor
                        end

                        cursor = cursor + 1
                    else

                        pre_cursor     = cursor == 0 and "" or utf8.sub(text, 1, cursor)
                        post_cursor    = utf8.sub(text, cursor + 2, 0)
                        local tempText = pre_cursor..info.key_text..post_cursor

                        if not string.find(tempText, "^"..input.format.."$") or count == cursor then return end

                        text   = tempText
                        cursor = cursor + 1

                        if text ~= "" and input.format ~= "" and string.find(utf8.sub(text, cursor + 1, cursor + 1), "%p") then

                            cursor = cursor + 1
                        end
                    end

                    if hooks and hooks.after_changes then hooks.after_changes() end
                end
            end,
            opts = {repeatable = true, complex = true}
        }

    }

    return list
end

function input.default(str)

    if input.format ~= "" and not string.find(str, "^"..input.format.."$") then error("Default value does not match the required format.") end

    text   = filter(str)
    cursor = utf8.len(text)
end

function input.reset()

    input.cursor_theme = "black" --black,white
    input.font_size    = 0
    input.max_length   = 255
    input.format       = "" --regex
    input.accept_only  = "" --digits,text
    cursor             = 0
    s_width            = 0
    s_height           = 0
    b_width            = 0
    cached             = {}
end

function input.init()

    text = ""

    input.reset()
end

return input