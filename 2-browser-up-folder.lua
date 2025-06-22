local BD = require("ui/bidi")
local FileChooser = require("ui/widget/filechooser")
local logger = require("logger")

local Icon = {
    home = "home",
    up = BD.mirroredUILayout() and "back.top.rtl" or "back.top",
}

local HideFolderSetting = "filemanager_hide_folder"

function FileChooser:_changeLeftIcon(icon, func)
    local titlebar = self.title_bar
    titlebar.left_icon = icon
    titlebar.left_icon_tap_callback = func
    if titlebar.left_button then
        titlebar.left_button:setIcon(icon)
        titlebar.left_button.callback = func
    end
end

function FileChooser:_isEmptyDir(item)
    if item.attr and item.attr.mode == "directory" then
        local sub_dirs, dir_files = self:getList(item.path, {})
        local empty = #dir_files == 0
        if empty then -- recurse in sub dirs
            for _, sub_dir in ipairs(sub_dirs) do
                if not self:_isEmptyDir(sub_dir) then
                    empty = false
                    break
                end
            end
        end
        return empty
    end
end

local orig_FileChooser_genItemTable = FileChooser.genItemTable

function FileChooser:genItemTable(...)
    local item_table = orig_FileChooser_genItemTable(self, ...)
    if self._dummy or not self.name == "filemanager" then return item_table end

    local items = {}
    local is_sub_folder = false
    for _, item in ipairs(item_table) do
        if item.is_go_up then
            is_sub_folder = true
        elseif not (G_reader_settings:readSetting(HideFolderSetting) and self:_isEmptyDir(item)) then
            table.insert(items, item)
        end
    end
    if #items == 0 then
        self:onFolderUp()
        return
    end

    self._left_tap_callback = self._left_tap_callback or self.title_bar.left_icon_tap_callback
    if is_sub_folder then
        self:_changeLeftIcon(Icon.up, function() self:onFolderUp() end)
    else
        self:_changeLeftIcon(Icon.home, self._left_tap_callback)
    end
    return items
end

-- Patch filemanager menu
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
local _ = require("gettext")

local orig_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

function FileManagerMenu:setUpdateItemTable()
    table.insert(
        FileManagerMenuOrder.filemanager_settings,
        #FileManagerMenuOrder.filemanager_settings - 1,
        "hide_empty_folder"
    )
    self.menu_items.hide_empty_folder = {
        text = _("Hide empty folder"),
        checked_func = function() return G_reader_settings:readSetting(HideFolderSetting, false) end,
        callback = function(touchmenu_instance)
            G_reader_settings:toggle(HideFolderSetting)
            self.ui.file_chooser:refreshPath()
        end,
    }
    orig_FileManagerMenu_setUpdateItemTable(self)
end
