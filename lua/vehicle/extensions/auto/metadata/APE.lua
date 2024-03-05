local M = {}

local fileHelper

local function initVariables()
    fileHelper = require('lua/vehicle/extensions/auto/utilities/FileHelper')
end

local function detectAPETag(file, fromBack)
    local tagPos = file:seek()
    local tagSize = 0
    if file:read(8) == "APETAGEX" then
        local version = fileHelper.readNumber(file, 4, true)/1000.0
        tagSize = fileHelper.readNumber(file, 4, true)
        file:seek('cur', 4)
        local flags = fileHelper.readNumber(file, 4, true)
        if version > 1 then
            if bit.band(bit.rshift(flags, 31), 0x01) == 0x01 then
                tagSize = tagSize + 32
            end
        end
    end
    if not fromBack then
        file:seek("set", tagPos + tagSize)
    end
    return tagSize
end

local function detectAPETagAtBack(file, track)
    local currentPos = file:seek()
    file:seek("set", track.endOfAudio - 32)
    local tagSize = detectAPETag(file, true)
    file:seek("set", currentPos)
    track.endOfAudio = track.endOfAudio - tagSize
end

M.initVariables = initVariables
M.detectAPETag = detectAPETag
M.detectAPETagAtBack = detectAPETagAtBack

return M