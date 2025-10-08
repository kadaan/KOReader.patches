--[[
    This user patch adds a "header" into the reader display, similar to the footer at the bottom.
    
    It draws two items, one to the upper left, one to the upper right, and with a small padding
    between the text and the top edge. It is only drawn for "reflowable" documents like EPUB
    and not for "fixed layout" documents like PDF and CBZ.

    It is up to you to provide enough of a top margin so that your book contents are not
    obscured by the header. You'll know right away if you need to increase the top margin.

    Right now the header is configured manually, see the comments in the code below for details.
    The set of variable names I added below match their equivalents in ReaderFooter, for better
    or worse. I provided a set of "status bar items" that I thought made the most sense.
    
    If someone wanted to make a whole settings UI, I think that'd be great. Maybe even use the
    built-in ReaderFooter UI somehow? With the new "status bar presets", maybe saving one with a
    special name like "header_preset" and parsing it for what to display.
    
    But until someone does that, if what you want isn't already included here, then you can view
    the existing ReaderFooter code at the link below. Anything it can do, this can do too, but
    accessing values is a little different. The examples I've provided should give plenty of hints.

    https://github.com/koreader/koreader/blob/master/frontend/apps/reader/modules/readerfooter.lua
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

ReaderView.paintTo = function(self, bb, x, y)
    _ReaderView_paintTo_orig(self, bb, x, y)
    if self.render_mode ~= nil then return end -- Show only for epub-likes and never on pdf-likes
    -- don't change anything above this line



    -- ===========================!!!!!!!!!!!!!!!=========================== -
    -- Configure formatting options for header here, if desired
    local header_font_face = "ffont" -- this is the same font the footer uses
    -- header_font_face = "source/SourceSerif4-Regular.ttf" -- this is the serif font from Project: Title
    local header_font_size = header_settings.text_font_size or 14 -- Will use your footer setting if available
    local header_font_bold = header_settings.text_font_bold or false -- Will use your footer setting if available
    local header_font_color = Blitbuffer.COLOR_BLACK -- black is the default, but there's 15 other shades to try
    local header_top_padding = Size.padding.small -- replace small with default or large for more space at the top
    local header_use_book_margins = true -- Use same margins as book for header
    local header_margin = Size.padding.large -- Use this instead, if book margins is set to false
    local left_max_width_pct = 48 -- this % is how much space the left corner can use before "truncating..."
    local right_max_width_pct = 48 -- this % is how much space the right corner can use before "truncating..."
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
    if book_author and book_author:find("\n") then -- Show first author if multiple authors
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
    local left_corner_header = string.format("%s", book_author)
    local right_corner_header = string.format("%s", book_title)
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
    left_corner_header = getFittedText(left_corner_header, left_max_width_pct)
    right_corner_header = getFittedText(right_corner_header, right_max_width_pct)
    local left_header_text = TextWidget:new {
        text = left_corner_header,
        face = Font:getFace(header_font_face, header_font_size),
        bold = header_font_bold,
        fgcolor = header_font_color,
        padding = 0,
    }
    local right_header_text = TextWidget:new {
        text = right_corner_header,
        face = Font:getFace(header_font_face, header_font_size),
        bold = header_font_bold,
        fgcolor = header_font_color,
        padding = 0,
    }
    local dynamic_space = avail_width - left_header_text:getSize().w - right_header_text:getSize().w
    local header = CenterContainer:new {
        dimen = Geom:new{ w = screen_width, h = math.max(left_header_text:getSize().h, right_header_text:getSize().h) + header_top_padding },
        VerticalGroup:new {
            VerticalSpan:new { width = header_top_padding },
            HorizontalGroup:new {
                left_header_text,
                HorizontalSpan:new { width = dynamic_space },
                right_header_text,
            }
        },
    }
    header:paintTo(bb, x, y)
end