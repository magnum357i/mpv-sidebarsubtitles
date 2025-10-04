local utf8 = {}

utf8.pattern = "[%z\1-\127\194-\244][\128-\191]*"

local function prev(str, pos)

    pos     = pos - 1
    local b = str:byte(pos)

    while pos > 1 and b >= 128 and b <= 191 do

        pos = pos - 1
        b   = str:byte(pos)
    end

    return pos
end

local function next(str, pos)

    local b = str:byte(pos)

    if b < 128 then

        return 1
    elseif b < 224 then

        return 2
    elseif b < 240 then

        return 3
    end

    return 4
end

local function utf8pattern(pt)

    local i, bytes = 1, #pt
    local content  = ""
    local escape   = false

    while i <= bytes do

        local start = i
        i           = i + next(pt, i)
        local char  = pt:sub(start, i - 1)

        if char == "%" then

            escape = true
        elseif escape then

            escape = false
        elseif char == "." then

            char = utf8.pattern
        end

        content = content..char
    end

    return content
end

function utf8.chars(str)

    local i, bytes = 1, #str

    return function()

        if i > bytes then return nil end

        local start = i
        i           = i + next(str, i)

        return str:sub(start, i - 1)
    end
end

function utf8.rchars(str)

    local i = #str + 1

    return function()

        if i <= 1 then return nil end

        local stop = i - 1
        i          = prev(str, i)

        return str:sub(i, stop)
    end
end

function utf8.len(str)

    local n, i, bytes = 0, 1, #str

    while i <= bytes do

        n = n + 1
        i = i + next(str, i)
    end

    return n
end

function utf8.match(str, pattern)

    local si, li = string.find(str, utf8pattern(pattern))

    if not si then return nil end

    return string.sub(str, si, li)
end

function utf8.gfind(str, pattern)

    local n, pos, bytes = 0, 1, #str
    local matches       = {}
    local si, li
    local results

    results = {string.find(str, utf8pattern(pattern))}

    if results[1] then

       while pos <= bytes do

            if not results[1] then break end

            n          = n + 1
            local size = next(str, pos)

            if pos == results[1] then

                si = n

            elseif (pos + size - 1) == results[2] then

                li = n

                if not results[3] then results[3] = string.sub(str, results[1], results[2]) end

                results[1] = si
                results[2] = li

                table.insert(matches, results)

                results = {string.find(str, utf8pattern(pattern), pos + 1)}
            end

            pos = pos + size
       end
    end

    local i = 0

    return function()

        i = i + 1

        if matches[i] then return table.unpack(matches[i]) end
    end
end

function utf8.find(str, pattern)

    local si, li = string.find(str, utf8pattern(pattern))

    if not si then return nil end

    local n, i, bytes = 0, 1, li

    while i <= bytes do

        n          = n + 1
        local size = next(str, i)

        if i == si              then si = n       end
        if (i + size - 1) == li then li = n break end

        i = i + size
    end

    return si, li
end

function utf8.sub(str,sstart,send)

    local content     = ""
    local n, i, bytes = 0, 1, #str
    local si, li      = 0, 0

    sstart = math.max(sstart, 1)

    while i <= bytes do

        n          = n + 1
        local size = next(str, i)

        if n == sstart then si = i                  end
        if n == send   then li = i + size - 1 break end

        i = i + size
    end

    if si == 0 and li == 0 then return "" end

    return str:sub(si, (li > 0) and li or bytes)
end

return utf8