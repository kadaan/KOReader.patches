local AlphaContainer = require("ui/widget/container/alphacontainer")
local BD = require("ui/bidi")
local Blitbuffer = require("ffi/blitbuffer")
local BottomContainer = require("ui/widget/container/bottomcontainer")
local CenterContainer = require("ui/widget/container/centercontainer")
local Device = require("device")
local FileChooser = require("ui/widget/filechooser")
local Font = require("ui/font")
local FrameContainer = require("ui/widget/container/framecontainer")
local ImageWidget = require("ui/widget/imagewidget")
local LineWidget = require("ui/widget/linewidget")
local OverlapGroup = require("ui/widget/overlapgroup")
local RightContainer = require("ui/widget/container/rightcontainer")
local Size = require("ui/size")
local TextBoxWidget = require("ui/widget/textboxwidget")
local TextWidget = require("ui/widget/textwidget")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local userpatch = require("userpatch")
local util = require("util")

local Screen = Device.screen

-- local logger = require("logger")

local FolderCover = {
    name = ".cover",
    exts = { ".jpg", ".jpeg", ".png", ".webp", ".gif" },
}

local function findCover(dir_path)
    local path = dir_path .. "/" .. FolderCover.name
    for _, ext in ipairs(FolderCover.exts) do
        local fname = path .. ext
        if util.fileExists(fname) then return fname end
    end
end

local function toKey(...)
    local keys = {}
    for _, key in pairs { ... } do
        if type(key) == "table" then
            table.insert(keys, "table")
            for k, v in pairs(key) do
                table.insert(keys, tostring(k))
                table.insert(keys, tostring(v))
            end
        else
            table.insert(keys, tostring(key))
        end
    end
    return table.concat(keys, "")
end

local orig_FileChooser_getList = FileChooser.getList
local cached_list = {}

function FileChooser:getList(path, collate)
    local key = toKey(path, collate, self.show_filter.status)
    cached_list[key] = cached_list[key] or { orig_FileChooser_getList(self, path, collate) }
    return table.unpack(cached_list[key])
end

local function capitalize(sentence)
    local words = {}
    for word in sentence:gmatch("%S+") do
        table.insert(words, word:sub(1, 1):upper() .. word:sub(2):lower())
    end
    return table.concat(words, " ")
end

local Folder = {
    edge = {
        thick = Screen:scaleBySize(2.5),
        margin = Size.line.medium,
        color = Blitbuffer.COLOR_GRAY_4,
        width = 0.97,
    },
    face = {
        border_size = Size.border.thick,
        alpha = 0.75,
        nb_items_font_size = 20,
        nb_items_margin = Screen:scaleBySize(5),
        dir_max_font_size = 25,
    },
}

local function patchCoverBrowser(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then return end -- Protect against remnants of project title
    local BookInfoManager = userpatch.getUpValue(MosaicMenuItem.update, "BookInfoManager")
    local original_update = MosaicMenuItem.update

    function MosaicMenuItem:update(...)
        original_update(self, ...)
        if self._foldercover_processed or self.menu.no_refresh_covers or not self.do_cover_image then
            return
        end

        if self.entry.is_file or self.entry.file or not self.mandatory then return end -- it's a file
        local dir_path = self.entry and self.entry.path
        if not dir_path then return end

        self._foldercover_processed = true

        local cover_file = findCover(dir_path) --custom
        if cover_file then
            local success, w, h = pcall(function()
                local tmp_img = ImageWidget:new { file = cover_file, scale_factor = 1 }
                tmp_img:_render()
                local orig_w = tmp_img:getOriginalWidth()
                local orig_h = tmp_img:getOriginalHeight()
                tmp_img:free()
                return orig_w, orig_h
            end)
            if success then
                self:_setFolderCover { file = cover_file, w = w, h = h }
                return
            end
        end

        self.menu._dummy = true
        local entries = self.menu:genItemTableFromPath(dir_path) -- sorted
        self.menu._dummy = false
        if not entries then return end

        for _, entry in ipairs(entries) do
            if entry.is_file or entry.file then
                local bookinfo = BookInfoManager:getBookInfo(entry.path, true)
                if
                    bookinfo
                    and bookinfo.cover_bb
                    and bookinfo.has_cover
                    and bookinfo.cover_fetched
                    and not bookinfo.ignore_cover
                    and not BookInfoManager.isCachedCoverInvalid(bookinfo, self.menu.cover_specs)
                then
                    self:_setFolderCover {
                        data = bookinfo.cover_bb,
                        w = bookinfo.cover_w,
                        h = bookinfo.cover_h,
                    }
                    break
                end
            end
        end
    end

    function MosaicMenuItem:_setFolderCover(img)
        local top_h = 2 * (Folder.edge.thick + Folder.edge.margin)
        local target_w, target_h =
            self.width - 2 * Folder.face.border_size, self.height - 2 * Folder.face.border_size - top_h
        local _, _, scale_factor = BookInfoManager.getCachedCoverSize(img.w, img.h, target_w, target_h)
        local image = ImageWidget:new { file = img.file, image = img.data, scale_factor = scale_factor }
        local size = image:getSize()
        local dimen = { w = size.w + 2 * Folder.face.border_size, h = size.h + 2 * Folder.face.border_size }
        local directory, nbitems = self:_getTextBoxes { w = size.w, h = size.h }
        local size = nbitems:getSize()
        local nb_size = math.max(size.w, size.h)

        local widget = VerticalGroup:new {
            VerticalSpan:new { width = math.max(0, math.ceil((self.height - (top_h + dimen.h)) * 0.5)) },
            LineWidget:new {
                background = Folder.edge.color,
                dimen = { w = math.floor(dimen.w * (Folder.edge.width ^ 2)), h = Folder.edge.thick },
            },
            VerticalSpan:new { width = Folder.edge.margin },
            LineWidget:new {
                background = Folder.edge.color,
                dimen = { w = math.floor(dimen.w * Folder.edge.width), h = Folder.edge.thick },
            },
            VerticalSpan:new { width = Folder.edge.margin },
            OverlapGroup:new {
                dimen = { w = self.width, h = self.height - top_h },
                FrameContainer:new {
                    padding = 0,
                    bordersize = Folder.face.border_size,
                    image,
                    overlap_align = "center",
                },
                CenterContainer:new {
                    dimen = dimen,
                    FrameContainer:new {
                        padding = 0,
                        bordersize = Folder.face.border_size,
                        AlphaContainer:new { alpha = Folder.face.alpha, directory },
                    },
                    overlap_align = "center",
                },
                BottomContainer:new {
                    dimen = dimen,
                    RightContainer:new {
                        dimen = {
                            w = dimen.w - Folder.face.nb_items_margin,
                            h = nb_size + Folder.face.nb_items_margin * 2 + math.ceil(nb_size * 0.125),
                        },
                        FrameContainer:new {
                            padding = 0,
                            padding_bottom = math.ceil(nb_size * 0.125),
                            radius = math.ceil(nb_size * 0.5),
                            background = Blitbuffer.COLOR_WHITE,
                            CenterContainer:new { dimen = { w = nb_size, h = nb_size }, nbitems },
                        },
                    },
                    overlap_align = "center",
                },
            },
        }
        if self._underline_container[1] then self._underline_container[1]:free(true) end
        self._underline_container[1] = widget
    end

    function MosaicMenuItem:_getTextBoxes(dimen)
        local nbitems = TextWidget:new {
            text = self.mandatory:match("(%d+) \u{F016}") or "", -- nb books
            face = Font:getFace("cfont", Folder.face.nb_items_font_size),
            bold = true,
            padding = 0,
        }

        local text = self.text
        if text:match("/$") then text = text:sub(1, -2) end -- remove "/"
        text = BD.directory(capitalize(text))
        local available_height = dimen.h - 2 * nbitems:getSize().h
        local dir_font_size = Folder.face.dir_max_font_size
        local directory

        while true do
            if directory then directory:free(true) end
            directory = TextBoxWidget:new {
                text = text,
                face = Font:getFace("cfont", dir_font_size),
                width = dimen.w,
                alignment = "center",
                bold = true,
            }
            if directory:getSize().h <= available_height then break end
            dir_font_size = dir_font_size - 1
            if dir_font_size < 10 then -- don't go too low
                directory:free()
                directory.height = available_height
                directory.height_adjust = true
                directory.height_overflow_show_ellipsis = true
                directory:init()
                break
            end
        end

        return directory, nbitems
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
