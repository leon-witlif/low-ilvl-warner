local ADDON_NAME = "LowIlvlWarner"
local LIW = {}

_G[ADDON_NAME] = LIW

LIW.VERSION = "v1.0.0"

LIW.DB_DEFAULTS = {
    threshold   = 226,
    enableParty = true,
    enableRaid  = true,
    minimap     = { hide = false },
    warnFrame   = { x = -90, y = -150 }, -- TOPLEFT/TOPLEFT
    configFrame = { x = 394, y = -4   }, -- CENTER/CENTER
}

LIW.INSPECT_DELAY      = 10  -- seconds between inspect requests
LIW.FAST_SCAN_INTERVAL = 60  -- seconds between retries for unknown ilvls
LIW.SLOW_SCAN_INTERVAL = 120 -- seconds between full re-scans for known ilvls
