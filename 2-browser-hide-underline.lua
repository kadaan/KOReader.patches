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
