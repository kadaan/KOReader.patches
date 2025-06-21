local BD = require("ui/bidi")
local FileChooser = require("ui/widget/filechooser")
-- local logger = require("logger")

local Icon = {
    home = "home",
    up = BD.mirroredUILayout() and "back.top.rtl" or "back.top",
}

function FileChooser:_changeLeftIcon(icon, func)
    local titlebar = self.title_bar
    titlebar.left_icon = icon
    titlebar.left_icon_tap_callback = func
    if titlebar.left_button then
        titlebar.left_button:setIcon(icon)
        titlebar.left_button.callback = func
    end
end

local orig_FileChooser_genItemTable = FileChooser.genItemTable

function FileChooser:genItemTable(...)
    local item_table = orig_FileChooser_genItemTable(self, ...)
    if self.name == "filemanager" then
        self._left_tap_callback = self._left_tap_callback or self.title_bar.left_icon_tap_callback
        if #item_table > 0 and item_table[1].is_go_up then
            self:_changeLeftIcon(Icon.up, function() self:onFolderUp() end)
            table.remove(item_table, 1)
        else
            self:_changeLeftIcon(Icon.home, self._left_tap_callback)
        end
    end
    return item_table
end
