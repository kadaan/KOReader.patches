--[[
    This user patch adds a "header" into the reader display, as well as drawing items into the
    space traditinally used by the footer, aka "Status Bar".

    It mimics the style used by many print novels:
        The page numbers display at top-right
        The centered text at the top displays "author - book title"

    It is up to you to provide enough of a top margin so that your book contents are not
    obscured by the header. You'll know right away if you need to increase the top margin.

    Suggestion: Combine this with a small caps font such as LMRomanSC-Regular.otf for even
    more of a print book feel.

    Credits: This user patch was written in collaboration with reddit user hundredpercentcocoa
--]]

local Blitbuffer = require("ffi/blitbuffer")
local TextWidget = require("ui/widget/textwidget")
local CenterContainer = require("ui/widget/container/centercontainer")
local VerticalGroup = require("ui/widget/verticalgroup")
local VerticalSpan = require("ui/widget/verticalspan")
local HorizontalGroup = require("ui/widget/horizontalgroup")
local HorizontalSpan = require("ui/widget/horizontalspan")
local BD = require("ui/bidi")
local Size = require("ui/size")
local Geom = require("ui/geometry")
local Device = require("device")
local Font = require("ui/font")
local logger = require("logger")
local util = require("util")
local datetime = require("datetime")
local Screen = Device.screen
local _ = require("gettext")
local T = require("ffi/util").template
local ReaderView = require("apps/reader/modules/readerview")
local _ReaderView_paintTo_orig = ReaderView.paintTo
local header_settings = G_reader_settings:readSetting("footer")
local screen_width = Screen:getWidth()
local screen_height = Screen:getHeight()

ReaderView.paintTo = function(self, bb, x, y)
    _ReaderView_paintTo_orig(self, bb, x, y)
    if self.render_mode ~= nil then return end -- Show only for epub-likes and never on pdf-likes
    -- don't change anything above this line



    -- ===========================!!!!!!!!!!!!!!!=========================== -
    -- Configure formatting options for header here, if desired
    local header_font_face = "lmroman/LMRomanCaps10-Regular.otf" -- this is the same font the footer uses
    -- header_font_face = "source/SourceSerif4-Regular.ttf" -- this is the serif font from Project: Title
    -- header_font_face = "smallcaps/LMRomanSC-Regular.otf" -- small caps style, you must supply this font yourself
    local header_font_size = header_settings.text_font_size or 14 -- Will use your footer setting if available
    local header_font_bold = header_settings.text_font_bold or false -- Will use your footer setting if available
    local header_font_color = Blitbuffer.COLOR_BLACK -- black is the default, but there's 15 other shades to try
    -- header_font_color = Blitbuffer.COLOR_GRAY_3 -- A nice dark gray, a bit lighter than black
    local header_top_padding = Size.padding.small -- replace small with default or large for more space at the top
    local header_bottom_padding = header_settings.container_height or 7
    local header_use_book_margins = false -- Use same margins as book for header
    local header_margin = Screen:scaleBySize(17) -- Use this instead, if book margins is set to false
    local right_max_width_pct = 8 -- this % is how much space the right corner can use before "truncating..."
    local header_max_width_pct = 84 -- this % is how much space the header can use before "truncating..."
    local separator = {
        bar     = "|",
        bullet  = "•",
        dot     = "·",
        em_dash = "—",
        en_dash = "-",
    }
    -- ===========================!!!!!!!!!!!!!!!=========================== -



    -- You probably don't need to change anything in the section below this line
    -- Infos for whole book:
    local pageno = self.state.page or 1 -- Current page
    local pages = self.ui.doc_settings.data.doc_pages or 1
    local book_title = self.ui.doc_props.display_title or ""
    local page_progress = ("%d / %d"):format(pageno, pages)
    local pages_left_book  = pages - pageno
    local percentage = (pageno / pages) * 100 -- Format like %.1f in header_string below
    -- Infos for current chapter:
    local book_chapter = self.ui.toc:getTocTitleByPage(pageno) or "" -- Chapter name
    local pages_chapter = self.ui.toc:getChapterPageCount(pageno) or pages
    local pages_left = self.ui.toc:getChapterPagesLeft(pageno) or self.ui.document:getTotalPagesLeft(pageno)
    local pages_done = self.ui.toc:getChapterPagesDone(pageno) or 0
    pages_done = pages_done + 1 -- This +1 is to include the page you're looking at
    local chapter_progress = pages_done .. " ⁄⁄ " .. pages_chapter
    -- Author(s):
    local book_author = self.ui.doc_props.authors
    if book_author:find("\n") then -- Show first author if multiple authors
        book_author =  T(_("%1 et al."), util.splitToArray(book_author, "\n")[1] .. ",")
    end
    -- Clock:
    local time = datetime.secondsToHour(os.time(), G_reader_settings:isTrue("twelve_hour_clock"))
    -- Battery:
    local battery = ""
    if Device:hasBattery() then
        local powerd = Device:getPowerDevice()
        local batt_lvl = powerd:getCapacity() or 0
        local is_charging = powerd:isCharging() or false
        local batt_prefix = powerd:getBatterySymbol(powerd:isCharged(), is_charging, batt_lvl) or ""
        battery = batt_prefix .. batt_lvl .. "%"
    end
    -- You probably don't need to change anything in the section above this line



    -- ===========================!!!!!!!!!!!!!!!=========================== -
    -- What you put here will show in the header:
    -- Try to get reference page number if it exists and is enabled
    local page_display = pageno
    if self.ui.pagemap and self.ui.pagemap.has_pagemap and self.ui.pagemap.use_page_labels then
        local page_label = self.ui.pagemap:getCurrentPageLabel(true)
        if page_label and page_label ~= "" then
            page_display = page_label
        end
    end
    local right_corner_header = string.format("%s", page_display)
    local centered_header = string.format("%s %s %s", book_author, separator.en_dash, book_title)
    -- Look up "string.format" in Lua if you need help.
    -- ===========================!!!!!!!!!!!!!!!=========================== -



    -- don't change anything below this line
    local margins = 0
    local left_margin = header_margin
    local right_margin = header_margin
    if header_use_book_margins then -- Set width % based on R + L margins
        left_margin = self.document:getPageMargins().left or header_margin
        right_margin = self.document:getPageMargins().right or header_margin
    end
    margins = left_margin + right_margin
    local avail_width = screen_width - margins -- deduct margins from width
    local function getFittedText(text, max_width_pct)
        if text == nil or text == "" then
            return ""
        end
        local text_widget = TextWidget:new{
            text = text:gsub(" ", "\u{00A0}"), -- no-break-space
            max_width = avail_width * max_width_pct * (1/100),
            face = Font:getFace(header_font_face, header_font_size),
            bold = header_font_bold,
            padding = 0,
        }
        local fitted_text, add_ellipsis = text_widget:getFittedText()
        text_widget:free()
        if add_ellipsis then
            fitted_text = fitted_text .. "…"
        end
        return BD.auto(fitted_text)
    end
    right_corner_header = getFittedText(right_corner_header, right_max_width_pct)

    local right_header_text = TextWidget:new {
        text = right_corner_header,
        face = Font:getFace(header_font_face, header_font_size),
        bold = header_font_bold,
        fgcolor = header_font_color,
        padding = 0,
    }
    local dynamic_space = avail_width - right_header_text:getSize().w
    local header = CenterContainer:new { 
        dimen = Geom:new{ w = screen_width, h = right_header_text:getSize().h + header_top_padding },
        VerticalGroup:new {
            VerticalSpan:new { width = header_top_padding },
            HorizontalGroup:new {
                HorizontalSpan:new { width = dynamic_space },
                right_header_text,
            }
        },
    }
    header:paintTo(bb, x, y)
    header:free();
    centered_header = getFittedText(centered_header, header_max_width_pct)
    local header_text = TextWidget:new {
        text = centered_header,
        face = Font:getFace(header_font_face, header_font_size),
        bold = header_font_bold,
        fgcolor = header_font_color,
        padding = 0,
    }
    if pages_done == 1 then
        header_top_padding = screen_height - header_text:getSize().h - header_bottom_padding
    end
    header = CenterContainer:new {
        dimen = Geom:new{ w = screen_width, h = header_text:getSize().h + header_top_padding },
        VerticalGroup:new {
            VerticalSpan:new { width = header_top_padding },
            HorizontalGroup:new {
                HorizontalSpan:new { width = left_margin },
                header_text,
                HorizontalSpan:new { width = right_margin },
            },
        },
    }
    header:paintTo(bb, x, y)
end