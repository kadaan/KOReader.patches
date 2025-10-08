--[[
    This user patch modifies filenames, primarily folders (but also regular files).

    It replaces underscores with spaces and moves the common English articles (the, a, an)
    from the end of the filename back to the start. e.g. A folder named "Frog_Bucket,_The"
    would appear as "The Frog Bucket".
--]]

local logger = require("logger")
local Menu = require("ui/widget/menu")
local _getMenuText_orig = Menu.getMenuText
Menu.getMenuText = function(item)
    local menu_text = _getMenuText_orig(item)
    logger.dbg("menutext-overrides: getMenuText called, original text: '" .. tostring(menu_text) .. "'")
    if menu_text then
        -- fix underscores that were used for spaces
        menu_text = menu_text:gsub("_", " ")
        -- fix articles for titles that were changed for proper sorting
        local endings = { ', The', ', An', ', A' }
        for i, ending in ipairs(endings) do
            if menu_text:match(ending) then
                logger.dbg("menutext-overrides: matched ending '" .. ending .. "'")
                local trailing_slash = ''
                if menu_text:match('/$') then
                    trailing_slash = '/'
                    menu_text = string.sub(menu_text, 1, -2)
                end
                menu_text = string.sub(ending, 3) .. " " ..
                    string.sub(menu_text, 1, ((string.len(ending) + 1) * -1)) ..
                    trailing_slash
                logger.dbg("menutext-overrides: transformed to: '" .. tostring(menu_text) .. "'")
            end
        end
    end
    logger.dbg("menutext-overrides: returning: '" .. tostring(menu_text) .. "'")
    return menu_text
end

logger.info("User patch applied: menutext-overrides enabled")