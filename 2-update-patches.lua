local DataStorage = require("datastorage")
local InfoMessage = require("ui/widget/infomessage")
local NetworkManager = require("ui/network/manager")
local UIManager = require("ui/uimanager")
local http = require("socket/http")
local json = require("json")
local lfs = require("libs/libkoreader-lfs")
local ltn12 = require("ltn12")
local md5 = require("ffi/MD5")

local _ = require("gettext")
local logger = require("logger")
local T = require("ffi/util").template

local UPDATES = "updates.json"
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

local message = {}

function message:close()
    if self.shown then
        UIManager:close(self.shown)
        self.shown = nil
    end
end

function message:show(text, timeout)
    self:close()
    self.shown = InfoMessage:new { text = text, timeout = timeout }
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
    message:show(_("Can't download patch updates..."), 5)
end

function ota:installPatch(url, patch_file, md5sum)
    local new_patch_file = patch_file .. ".new"
    if downloadFile(url, new_patch_file) then
        logger.info("Patch downloaded:", new_patch_file)
        local installed = md5.sumFile(new_patch_file) == md5sum and copy(new_patch_file, patch_file)
        remove(new_patch_file)
        logger.info("Patch " .. (installed and "" or "NOT ") .. "installed:", patch_file)
        return installed
    end
end

function ota:installUpdates(updates)
    local updated = {}
    for name, md5sum in pairs(updates) do
        local patch_file = self.local_patches .. name
        if
            isFile(patch_file)
            and md5.sumFile(patch_file) ~= md5sum
            and self:installPatch(self.online_patches .. name, patch_file, md5sum)
        then
            table.insert(updated, name:sub(1, -5))
        end
    end
    return updated
end

function ota:update()
    if not isDir(self.local_patches) then return end -- no patches
    if not NetworkManager:isOnline() then
        message:show(_("Please turn on wifi and try again."), 5)
        return
    end

    message:show(_("Check for patch updates..."))
    UIManager:scheduleIn(1, function()
        local updates = self:checkUpdates()
        if updates then
            updated = self:installUpdates(updates)
            if #updated > 0 then
                message:close()
                table.insert(updated, 1, _("Patch updated:"))
                UIManager:askForRestart(table.concat(updated, "\n· "))
            else
                message:show(_("No patch updates found..."))
            end
        end
    end)
end

function ota:menu()
    return {
        text = T(_("Update %1"), GITHUB_REPO),
        callback = function() self:update() end,
    }
end

-- menu
local FileManagerMenu = require("apps/filemanager/filemanagermenu")
local FileManagerMenuOrder = require("ui/elements/filemanager_menu_order")
local orig_FileManagerMenu_setUpdateItemTable = FileManagerMenu.setUpdateItemTable

function FileManagerMenu:setUpdateItemTable()
    table.insert(FileManagerMenuOrder.more_tools, "----------------------------")
    table.insert(FileManagerMenuOrder.more_tools, "patch_update")
    self.menu_items.patch_update = ota:menu()
    orig_FileManagerMenu_setUpdateItemTable(self)
end

local ReaderMenu = require("apps/reader/modules/readermenu")
local ReaderMenuOrder = require("ui/elements/reader_menu_order")
local orig_ReaderMenu_setUpdateItemTable = ReaderMenu.setUpdateItemTable

function ReaderMenu:setUpdateItemTable()
    table.insert(ReaderMenuOrder.more_tools, "----------------------------")
    table.insert(ReaderMenuOrder.more_tools, "patch_update")
    self.menu_items.patch_update = ota:menu()
    orig_ReaderMenu_setUpdateItemTable(self)
end
