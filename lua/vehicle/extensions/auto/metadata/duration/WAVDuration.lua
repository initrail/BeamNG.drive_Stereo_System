local fileHelper
local id3V2
local track

local M = {}

local function initVariables()
    fileHelper = require('lua/vehicle/extensions/auto/utilities/FileHelper')
    id3V2 = require('lua/vehicle/extensions/auto/metadata/ID3V2')
end

local function fail()
    track.duration = 0/0
    track.calculating = false
end

local function calculateDuration(file, t)
    track = t
    local riffHeaderFound = false
    local byteRate = 0
    while file:seek() + 8 < track.endOfAudio do
        if riffHeaderFound then
            local id = file:read(4)
            local size = fileHelper.readNumber(file, 4, true)
            if id == "fmt " then
                file:seek("cur", 8)
                byteRate = fileHelper.readNumber(file, 4, true)
                file:seek("cur", size - 12)
            elseif id == "data" then
                track.duration = track.duration + size/byteRate
                file:seek("cur", size + size % 2)
            elseif string.upper(id) == "ID3 " then
                id3V2.detectID3V2Tag(file, track, false)
            else
                file:seek("cur", size)
            end
        else
            local riffFlag = file:read(4)
            if riffFlag == "RIFF" then
                file:seek("cur", 4)
                if file:read(4) == "WAVE" then
                    riffHeaderFound = true
                else
                    fail()
                    return
                end
            else
                fail()
                return
            end
        end
    end
    track.calculating = false
end

M.initVariables = initVariables
M.calculateDuration = calculateDuration

return M