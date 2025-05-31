-- local ok, guard = pcall(require, "patches/guard")
-- if ok and guard:korDoesNotMeet("v2025.04-103") then return end -- will be needed for https://github.com/koreader/koreader/pull/13893

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
local userPatch = require("userpatch")

local _ = require("gettext")
local T = require("ffi/util").template
local logger = require("logger")

local UPDATES = "updates.json" -- dict of md5 of lua files
local GITHUB_REPO = "sebdelsol/KOReader.patches"
local LOCAL_PATCHES = DataStorage:getDataDir() .. "/patches/"
local ONLINE_PATCHES = "https://github.com/" .. GITHUB_REPO .. "/raw/refs/heads/main/"

-- download
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

-- files
local function isFile(path) return lfs.attributes(path, "mode") == "file" end
local function isDir(path) return lfs.attributes(path, "mode") == "directory" end
local function copy(src, dst) return os.execute('cp -vf "' .. src .. '" "' .. dst .. '"') == 0 end
local function remove(path) return os.execute('rm -vf "' .. path .. '"') == 0 end

-- ota
local ota = {
    local_patches = LOCAL_PATCHES,
    local_updates = LOCAL_PATCHES .. UPDATES,
    online_patches = ONLINE_PATCHES,
    online_updates = ONLINE_PATCHES .. UPDATES,
}

function ota:checkUpdates()
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

function ota:cleanBrokenInstalls()
    local broken = false
    for name, ok in pairs(userPatch.execution_status) do
        local file = self.local_patches .. name
        local old_file = file .. ".old"
        if isFile(old_file) then
            if ok then
                remove(old_file)
            elseif copy(old_file, file) then -- revert install
                logger.info("Patch reverted:", file)
                remove(old_file)
                broken = true
            end
        end
    end
    if broken then
        UIManager:askForRestart(_("Some broken patches have been reverted, you need to restart!"))
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
            local old_file = file .. ".old"
            install.installed = md5.sumFile(new_file) == md5sum -- validate
                and copy(file, old_file) -- keep a copy
                and copy(new_file, file) -- install
            logger.info("Patch " .. (self.installed and "" or "NOT ") .. "installed:", file)
            remove(new_file)
        end
    end

    return install
end

function ota:getInstalls(updates)
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

    function installs.text(installed)
        local texts = {}
        for _, install in ipairs(installs) do
            if install.installed == installed then table.insert(texts, "\n· " .. install.name) end
        end
        return table.concat(texts)
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
        local updates = self:checkUpdates()
        if not updates then
            ui:info(_("Can't download patch updates"))
            return
        end

        local installs = self:getInstalls(updates)
        if installs.empty(false) then
            ui:info(_("No patch updates found"))
            return
        end

        local install = function()
            installs.apply()

            local texts = {}
            if not installs.empty(false) then -- some failed
                table.insert(texts, _("Patches that failed to update:") .. installs.text(false))
            end
            if not installs.empty(true) then -- some succeded
                table.insert(texts, _("Patches updated:") .. installs.text(true))
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
            text = _("Patch updates available:") .. text,
            ok = _("Update"),
            one_button = false,
            callback = function() ui:process(install, _("Install patches:") .. text) end,
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

-- clean installs
local FileManager = require("apps/filemanager/filemanager")
local ReaderUI = require("apps/reader/readerui")

local orig_ReaderUI_showReader = ReaderUI.showReader
function ReaderUI:showReader(...)
    orig_ReaderUI_showReader(self, ...)
    ota:cleanBrokenInstalls()
end

local orig_FileManager_showFiles = FileManager.showFiles
function FileManager:showFiles(...)
    orig_FileManager_showFiles(self, ...)
    ota:cleanBrokenInstalls()
end

-- menu
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local ReaderMenu = require("apps/reader/modules/readermenu")

local function patch(menu, order)
    table.insert(order.more_tools, "----------------------------")
    table.insert(order.more_tools, "patch_update")
    menu.menu_items.patch_update = ota:menu()
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
