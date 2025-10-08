--[[
    This user patch is for use with the Project: Title plugin.

    It moves trailing articles (", The", ", An", ", A") to the front of folder names
    displayed in the bottom-left footer.

    Example: "Wheel of Time, The" displays as "The Wheel of Time"
--]]

local logger = require("logger")

-- Function to process a folder name and move trailing articles to the front
local function moveTrailingArticle(name)
    -- Fix articles for titles that were changed for proper sorting
    local endings = { ', The', ', An', ', A' }
    for i, ending in ipairs(endings) do
        if name:match(ending) then
            local trailing_slash = ''
            if name:match('/$') then
                trailing_slash = '/'
                name = string.sub(name, 1, -2)
            end
            local result = string.sub(ending, 3) .. " " ..
                string.sub(name, 1, ((string.len(ending) + 1) * -1)) ..
                trailing_slash
            logger.dbg("project-title-trailing-article: transformed '" .. name .. "' to '" .. result .. "'")
            return result
        end
    end
    return name
end

-- Hook into Project: Title plugin using userpatch
local userpatch = require("userpatch")
local function patchProjectTitle(plugin)
    logger.info("project-title-trailing-article: Patching Project: Title plugin")

    -- Get the Menu widget which now has CoverMenu's updatePageInfo
    local Menu = require("ui/widget/menu")
    logger.info("project-title-trailing-article: Menu.updatePageInfo type: " .. tostring(type(Menu.updatePageInfo)))

    local orig_updatePageInfo = Menu.updatePageInfo

    Menu.updatePageInfo = function(self, select_number)
        logger.dbg("project-title-trailing-article: updatePageInfo called!")

        -- Call the original function first
        orig_updatePageInfo(self, select_number)

        -- If we have a cur_folder_text widget and a path, apply transformation
        if self.cur_folder_text and type(self.path) == "string" and self.path ~= '' then
            local current_text = self.cur_folder_text.text
            logger.dbg("project-title-trailing-article: current folder text: '" .. tostring(current_text) .. "'")

            -- Apply transformation to the folder name
            if current_text and current_text ~= "" then
                -- Remove the star prefix if present
                local has_star = current_text:match("^★ ")
                local folder_name = has_star and current_text:sub(3) or current_text

                -- Transform the folder name
                local transformed = moveTrailingArticle(folder_name)

                -- Re-add the star if it was there
                if has_star and transformed ~= folder_name then
                    transformed = "★ " .. transformed
                end

                -- Update the text if it changed
                if transformed ~= current_text then
                    logger.dbg("project-title-trailing-article: updating folder text to: '" .. transformed .. "'")
                    self.cur_folder_text:setText(transformed)
                end
            end
        end
    end

    logger.info("project-title-trailing-article: Menu.updatePageInfo override complete")
end

-- Register the patch with Project: Title plugin
userpatch.registerPatchPluginFunc("coverbrowser", patchProjectTitle)

logger.info("User patch applied: Project: Title trailing article enabled")
