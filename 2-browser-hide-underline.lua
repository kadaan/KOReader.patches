-- based on https://gist.github.com/ebanDev/ad067c912db947dc15a2e0c4a0a99240
-- It uses KOReader's userpatch tools instead of relying on hacks, so it's compatible with other patches to CoverBrowser

local Blitbuffer = require("ffi/blitbuffer")
local userpatch = require("userpatch")

local function patchCoverBrowser(plugin)
    local MosaicMenu = require("mosaicmenu")
    local MosaicMenuItem = userpatch.getUpValue(MosaicMenu._updateItemsBuildUI, "MosaicMenuItem")
    if not MosaicMenuItem then return end -- protect against remnants of project title or ebanDev patches

    function MosaicMenuItem:onFocus()
        self._underline_container.color = Blitbuffer.COLOR_WHITE
        return true
    end
end

userpatch.registerPatchPluginFunc("coverbrowser", patchCoverBrowser)
