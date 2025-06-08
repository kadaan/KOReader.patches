-- temporary fix for https://github.com/koreader/koreader/issues/13925
local orig_string_rep = string.rep
getmetatable("").__index.rep = function(self, nb)
    if nb < math.huge then return orig_string_rep(self, nb) end
    return self
end

-- Name it "2--ui-font.lua": it NEEDS to be the 1st user patch to be executed

local Font = require("ui/font")
local _ = require("gettext")
local T = require("ffi/util").template
local FontList = require("fontlist")
local UIManager = require("ui/uimanager")
local cre = require("document/credocument"):engineInit()
local logger = require("logger")

-- UI font
local SETTING = "ui_font_name"
local DEFAULT = "Noto Sans"

local function get_bold_path(path_regular)
    local path_bold, nb_repl = path_regular:gsub("%-Regular%.", "-Bold.", 1)
    return nb_repl > 0 and path_bold
end

local UIFont = {}

function UIFont:init()
    local path_set = {}
    for _, font in ipairs(FontList.fontlist) do
        path_set[font] = true
    end

    self.font_list = {}
    self.fonts = {}
    for _, name in ipairs(cre.getFontFaces()) do
        local path_regular = cre.getFontFaceFilenameAndFaceIndex(name)
        local path_bold = get_bold_path(path_regular)
        if path_set[path_regular] and path_set[path_bold] then
            table.insert(self.font_list, name)
            self.fonts[name] = { regular = path_regular, bold = path_bold }
        end
    end

    local repl = {
        ["NotoSans-Regular.ttf"] = "regular",
        ["NotoSans-Bold.ttf"] = "bold",
    }
    self.to_be_replaced = {}
    for k, v in pairs(Font.fontmap) do
        self.to_be_replaced[k] = repl[v]
    end

    G_reader_settings:readSetting(SETTING, DEFAULT)
    self:setFont()
end

function UIFont:setFont(name)
    if name ~= G_reader_settings:readSetting(SETTING) then
        name = name or G_reader_settings:readSetting(SETTING)
        for k, v in pairs(self.to_be_replaced) do
            Font.fontmap[k] = self.fonts[name][v]
        end
        G_reader_settings:saveSetting(SETTING, name)
        return true
    end
end

function UIFont:menu()
    return {
        text_func = function() return T(_("UI font: %1"), G_reader_settings:readSetting(SETTING)) end,
        sub_item_table_func = function()
            local items = {}
            for i, name in ipairs(self.font_list) do
                table.insert(items, {
                    text = name,
                    enabled_func = function() return name ~= G_reader_settings:readSetting(SETTING) end,
                    font_func = function(size) return Font:getFace(self.fonts[name].regular, size) end,
                    callback = function()
                        if self:setFont(name) then
                            UIManager:askForRestart(_("Restart to apply the UI font change"))
                        end
                    end,
                })
            end
            return items
        end,
    }
end

UIFont:init()

-- menu
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local ReaderMenu = require("apps/reader/modules/readermenu")

local function patch(menu, order)
    table.insert(order.setting, "----------------------------")
    table.insert(order.setting, "ui_font")
    menu.menu_items.ui_font = UIFont:menu()
end

local orig_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable
function FileManagerMenu:setUpdateItemTable()
    patch(self, require("ui/elements/filemanager_menu_order"))
    orig_FileManagerMenu_setUpdateItemTable(self)
end

local orig_ReaderMenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable
function ReaderMenu:setUpdateItemTable()
    patch(self, require("ui/elements/reader_menu_order"))
    orig_ReaderMenu_setUpdateItemTable(self)
end

-- Has to be done AFTER the ui font manipulations
-- More items in the menu
local Menu = require("ui/widget/menu")
local TouchMenu = require("ui/widget/touchmenu")

local MENU_ITEMS_PLUS_PERCENT = 0.25

TouchMenu.max_per_page_default = math.floor(TouchMenu.max_per_page_default * (1 + MENU_ITEMS_PLUS_PERCENT))
Menu.items_per_page_default = math.floor(Menu.items_per_page_default * (1 + MENU_ITEMS_PLUS_PERCENT))
