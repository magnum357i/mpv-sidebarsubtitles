# mpv-sidebarsubtitles
![Example for Sidebarsubtitles](https://github.com/magnum357i/mpv-sidebarsubtitles/blob/main/ss1.jpg)

A plugin I made just for my own fun. You can see the subtitle content in the sidebar. This repository was created as a backup and in case it might help others.

# Installation
Just put `sidebarsubtitles` folder into your **scripts** directory, and it will work.

| Supported Themes        |
|-------------------------|
| MPV Default (not fully) |
| uosc                    |

### MPV Default
I’m not planning to shrink the controls for the default theme, please use [uosc](https://github.com/tomasklaen/uosc).

### Editing uosc

Open `uosc/main.lua`, and follow these steps to shrink the player controls:

```
# find:
    if real_width <= 0 then return end

# add below:
	local temp_width = real_width
	if sidebarsubtitles_width and sidebarsubtitles_width > 0 then real_width = sidebarsubtitles_width end



# find:
    Elements:update_proximities()
    request_render()

# add below:
	if sidebarsubtitles_width and sidebarsubtitles_width > 0 then
	display.width, display.bx = temp_width, temp_width
	end



# find:
--[[ MESSAGE HANDLERS ]]

# add below:
mp.register_script_message("sidebarsubtitles", function(value)

	sidebarsubtitles_width = tonumber(value)
end)
```

# Known Bugs
- Scale