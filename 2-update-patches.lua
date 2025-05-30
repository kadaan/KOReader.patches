local ConfirmBox = require("ui/widget/confirmbox")
local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local NetworkManager = require("ui/network/manager")
local Trapper = require("ui/trapper")
local UIManager = require("ui/uimanager")
local http = require("socket/http")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local md5 = require("ffi/MD5")

local _ = require("gettext")
local logger = require("logger")
local T = require("ffi/util").template

local UPDATES = "updates.json" -- dict of md5 of lua files
local GITHUB_REPO = "sebdelsol/KOReader.patches"
local LOCAL_PATCHES = DataStorage:getDataDir() .. "/patches/"
local ONLINE_PATCHES = "https://github.com/" .. GITHUB_REPO .. "/raw/refs/heads/main/"

-- tools
local function httpRequest(options)
    local req_ok, r_val, r_code, _, r_status_str = pcall(http.request, options)
    if req_ok and r_code == 200 then return true end
    logger.err("Network request failed: ", tostring(r_val), r_code, r_status_str)
end

local function downloadFile(url, path)
    local file, err = io.open(path, "wb")
    if file then
        local options = {
            url = url,
            method = "GET",
            headers = { ["User-Agent"] = GITHUB_REPO },
            sink = ltn12.sink.file(file),
            redirect = true,
        }
        if httpRequest(options) then return true end
        pcall(os.remove, path)
        return
    end
    logger.err("Failed to open target file for download: ", err or "Unknown error")
end

-- ui
local ui = {}

function ui:close()
    if self.shown then
        UIManager:close(self.shown)
        self.shown = nil
    end
end

function ui:info(text)
    self:close()
    self.shown = InfoMessage:new { text = text, timeout = 5 }
    UIManager:show(self.shown)
end

function ui:process(func, text)
    self:close()
    self.shown = InfoMessage:new { text = text, dismissable = false }
    UIManager:show(self.shown)
    UIManager:scheduleIn(0.1, func)
end

function ui:confirm(options)
    self:close()
    local params = {
        text = options.text,
        no_ok_button = options.one_button,
    }
    params[options.one_button and "cancel_text" or "ok_text"] = options.ok
    params[options.one_button and "cancel_callback" or "ok_callback"] = options.callback
    self.shown = ConfirmBox:new(params)
    UIManager:show(self.shown)
end

-- ota
local function isFile(path) return lfs.attributes(path, "mode") == "file" end
local function isDir(path) return lfs.attributes(path, "mode") == "directory" end
local function copy(src, dst) return os.execute('cp -vf "' .. src .. '" "' .. dst .. '"') == 0 end
local function remove(path) return os.execute('rm -vf "' .. path .. '"') == 0 end

local ota = {
    local_patches = LOCAL_PATCHES,
    local_updates = LOCAL_PATCHES .. UPDATES,
    online_patches = ONLINE_PATCHES,
    online_updates = ONLINE_PATCHES .. UPDATES,
}

function ota:updates()
    if downloadFile(self.online_updates, self.local_updates) then
        logger.info("Patch updates list downloaded")
        local updates_file = io.open(self.local_updates, "r")
        if updates_file then
            local ok, updates = pcall(json.decode, updates_file:read("*a"))
            updates = ok and updates
            if updates then logger.info("Patch updates list decoded") end
            updates_file:close()
            return updates
        end
    end
end

function ota:install(name, md5sum)
    local install = { name = name:sub(1, -5), installed = false }
    local file = self.local_patches .. name

    function install.isNew() return isFile(file) and md5.sumFile(file) ~= md5sum end

    function install.apply()
        local url = self.online_patches .. name
        local new_file = file .. ".new"
        if downloadFile(url, new_file) then
            logger.info("Patch downloaded:", new_file)
            install.installed = md5.sumFile(new_file) == md5sum and copy(new_file, file) -- validate & copy
            logger.info("Patch " .. (self.installed and "" or "NOT ") .. "installed:", file)
            remove(new_file)
        end
    end

    return install
end

function ota:installs(updates)
    local installs = {}
    for name, md5sum in pairs(updates) do
        local install = self:install(name, md5sum)
        if install.isNew() then table.insert(installs, install) end
    end

    function installs.apply()
        for _, install in ipairs(installs) do
            install.apply()
        end
    end

    function installs.text(installed, sep)
        local texts = {}
        for _, install in ipairs(installs) do
            if install.installed == installed then table.insert(texts, install.name) end
        end
        return table.concat(texts, sep or "\n· ")
    end

    function installs.empty(installed)
        for _, install in ipairs(installs) do
            if install.installed == installed then return false end
        end
        return true
    end

    return installs
end

function ota:update()
    if not isDir(self.local_patches) then
        ui:info(_("You have no patches."))
        return
    end
    if not NetworkManager:isOnline() then
        ui:info(_("Please turn on wifi and try again."))
        return
    end

    local update = function()
        local updates = self:updates()
        if not updates then
            ui:info(_("Can't download patch updates"))
            return
        end

        local installs = self:installs(updates)
        if installs.empty(false) then
            ui:info(_("No patch updates found"))
            return
        end

        local install = function()
            installs.apply()

            local texts = {}
            if not installs.empty(false) then -- some failed
                table.insert(texts, _("Patches that failed to update:"))
                table.insert(texts, installs.text(false))
            end
            if not installs.empty(true) then -- some succeded
                table.insert(texts, _("Patches updated:"))
                table.insert(texts, installs.text(true))
            end
            ui:confirm {
                text = table.concat(texts, "\n"),
                ok = _("OK"),
                one_button = true,
                callback = function()
                    if not installs.empty(true) then UIManager:askForRestart(_("You need to restart!")) end
                end,
            }
        end

        local text = installs.text(false)
        ui:confirm {
            text = _("Patch updates available:\n") .. text,
            ok = _("Update"),
            one_button = false,
            callback = function() ui:process(install, _("Install patches:\n") .. text) end,
        }
    end

    ui:process(update, _("Check for patch updates..."))
end

function ota:menu()
    return {
        text = T(_("Update %1"), GITHUB_REPO),
        callback = function() self:update() end,
    }
end

-- menu
local function patch(menu, order)
    table.insert(order.more_tools, "----------------------------")
    table.insert(order.more_tools, "patch_update")
    menu.menu_items.patch_update = ota:menu()
end

local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local orig_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

function FileManagerMenu:setUpdateItemTable()
    patch(self, require("ui/elements/filemanager_menu_order"))
    orig_FileManagerMenu_setUpdateItemTable(self)
end

local ReaderMenu = require("apps/reader/modules/readermenu")
local orig_ReaderMenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable

function ReaderMenu:setUpdateItemTable()
    patch(self, require("ui/elements/reader_menu_order"))
    orig_ReaderMenu_setUpdateItemTable(self)
end
