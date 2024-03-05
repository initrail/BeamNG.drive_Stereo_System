local fileHelper
local track

local mpeg_bitrates = {
  { -- Version 2.5
    { 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 0 }, -- Reserved
    { 0,   8,  16,  24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160, 0 }, -- Layer 3
    { 0,   8,  16,  24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160, 0 }, -- Layer 2
    { 0,  32,  48,  56,  64,  80,  96, 112, 128, 144, 160, 176, 192, 224, 256, 0 }  -- Layer 1
  },                                                                                --
  { -- Reserved                                                                     --
    { 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 0 }, -- Invalid
    { 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 0 }, -- Invalid
    { 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 0 }, -- Invalid
    { 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 0 }  -- Invalid
  },                                                                                --
  { -- Version 2                                                                    --
    { 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 0 }, -- Reserved
    { 0,   8,  16,  24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160, 0 }, -- Layer 3
    { 0,   8,  16,  24,  32,  40,  48,  56,  64,  80,  96, 112, 128, 144, 160, 0 }, -- Layer 2
    { 0,  32,  48,  56,  64,  80,  96, 112, 128, 144, 160, 176, 192, 224, 256, 0 }  -- Layer 1
  },                                                                                --
  { -- Version 1                                                                    --
    { 0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0,   0, 0 }, -- Reserved
    { 0,  32,  40,  48,  56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320, 0 }, -- Layer 3
    { 0,  32,  48,  56,  64,  80,  96, 112, 128, 160, 192, 224, 256, 320, 384, 0 }, -- Layer 2
    { 0,  32,  64,  96, 128, 160, 192, 224, 256, 288, 320, 352, 384, 416, 448, 0 }, -- Layer 1
  }
}

local mpeg_srates = {
    { 11025, 12000,  8000, 0 }, -- MPEG 2.5
    {     0,     0,     0, 0 }, -- Reserved
    { 22050, 24000, 16000, 0 }, -- MPEG 2
    { 44100, 48000, 32000, 0 }  -- MPEG 1
}

local mpeg_frame_samples = {
--    Rsvd     3     2     1  < Layer  v Version
    {    0,  576, 1152,  384 }, --       2.5
    {    0,    0,    0,    0 }, --       Reserved
    {    0,  576, 1152,  384 }, --       2
    {    0, 1152, 1152,  384 }  --       1
}

local mpeg_slot_size = { 0, 1, 1, 4 }

local M = {}

local function initVariables()
    fileHelper = require('lua/vehicle/extensions/auto/utilities/FileHelper')
end

local function decodeHeader(headerString)
	local headerData = {}
	local bytes = {string.byte(headerString, 1, -1)}
	headerData.version      = bit.rshift(bit.band(bytes[2], 0x18), 3) -->> 3 -- 00011000
	headerData.layer        = bit.rshift(bit.band(bytes[2], 0x06), 1) -->> 1 -- 00000110
	headerData.bitRate      = bit.rshift(bit.band(bytes[3], 0xF0), 4) -->> 4 -- 11110000
	headerData.frequency    = bit.rshift(bit.band(bytes[3], 0x0C), 2) -->> 2 -- 00001100
	headerData.padded       = bit.rshift(bit.band(bytes[3], 0x02), 1) -->> 1 -- 00000010
    headerData.mode         = bit.rshift(bit.band(bytes[4], 0xC0), 6) -->> 6 -- 11000000
    if headerData.version == 1 or headerData.layer == 0 or headerData.bitRate == 0 or headerData.bitRate == 15 or headerData.frequency == 3 then
        return nil
    end
	return headerData
end

local function frameSize(headerData)
	local bitRate = mpeg_bitrates[headerData.version + 1][headerData.layer + 1][headerData.bitRate + 1] * 1000
	local sampleRate = mpeg_srates[headerData.version + 1][headerData.frequency + 1]
	local samples = mpeg_frame_samples[headerData.version + 1][headerData.layer + 1]
	local slotSize = mpeg_slot_size[headerData.layer + 1]
    local seconds = samples/sampleRate
    local coefficient = samples/8/slotSize
    if headerData.version == 3 and headerData.layer == 3 then
        track.version1LayerI = true
    end
	local fSize = (math.floor(coefficient*bitRate/sampleRate) + headerData.padded)*slotSize
	return fSize, seconds
end

local function calculateDuration(file, t)
    track = t
    if file:seek() ~= track.fileSeek then
        file:seek("set", track.fileSeek)
    end
    local inc = 0
    while inc < 100 do
        inc = inc + 1
        if file:seek() < track.endOfAudio then
            local headerString = fileHelper.peek(file, 4)
            if headerString ~= nil and #headerString == 4 then
                if track.checkForLyrics then
                    if headerString == "LYRI" then
                        local lyricsBegin = fileHelper.peek(file, 11)
                        if lyricsBegin == "LYRICSBEGIN" then
                            track.endOfAudio = file:seek()
                            break
                        end
                    end
                end
                local headerFlag = {string.byte(headerString, 1, 2)}
                if headerFlag[1] == 0xFF and bit.band(headerFlag[2], 0xE0) == 0xE0 then
                    local header = decodeHeader(headerString)
                    if header ~= nil then
                        local sizeOfFrame, seconds = frameSize(header)
                        track.duration = track.duration + seconds
                        file:seek("cur", sizeOfFrame)
                    else
                        file:seek("cur", 1)
                    end
                else
                    file:seek("cur", 1)
                end
            else
                file:seek("cur", 1)
            end
        else
            track.calculating = false
            if track.duration == 0 then
                track.duration = 0/0
            end
            break
        end
    end
    track.fileSeek = file:seek()
end

M.initVariables = initVariables
M.calculateDuration = calculateDuration

return M