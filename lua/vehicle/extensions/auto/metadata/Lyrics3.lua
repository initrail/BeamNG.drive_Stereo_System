local M = {}

local function detectLyricsTag(file, track)
    local currentPos = file:seek()
    file:seek("set", track.endOfAudio - 9)
    local tagSize = 0
    local detect = file:read(9)
    if detect == "LYRICSEND" then
        tagSize = 9
        track.checkForLyrics = true
    elseif detect == "LYRICS200" then
        file:seek("cur", -15)
        local sizeString = file:read(6)
        tagSize = tonumber(sizeString) + 15
    end
    file:seek("set", currentPos)
    track.endOfAudio = track.endOfAudio - tagSize
end

M.detectLyricsTag = detectLyricsTag

return M