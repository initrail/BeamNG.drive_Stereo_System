local M = {}
local fileHelper
local versionMajor
local tagSize
local tagPos
local file
local track = {}
local id3V1
local utf16_to_utf8
local frameIDs = {}
frameIDs['TIT2'] = true
frameIDs['TPE1'] = true
frameIDs['TPE2'] = true
frameIDs['TALB'] = true
frameIDs['TPOS'] = true
frameIDs['TRCK'] = true
frameIDs['TYER'] = true
frameIDs['TDRC'] = true
frameIDs['TCON'] = true
frameIDs['APIC'] = true

local function initVariables()
    utf16_to_utf8 = require('lua/vehicle/extensions/auto/utilities/utf16_to_utf8')
    id3V1 = require('lua/vehicle/extensions/auto/metadata/ID3V1')
    fileHelper = require('lua/vehicle/extensions/auto/utilities/FileHelper')
end

local function getSynchSafeNumber(file, byteCount)
    local num = 0
    local synchSafeNum = fileHelper.readNumber(file, byteCount, false)
    local mask = 0x7F000000
    for i = 1, byteCount do
        num = bit.bor(bit.lshift(num, 7), bit.rshift(bit.band(synchSafeNum, mask), 24))
        synchSafeNum = bit.lshift(synchSafeNum, 8)
    end
    return num
end

local function removeNulls(st)
    local s = ''
    for i = 1, #st do
        local ch = string.sub(st, i, i)
        if ch ~= '\0' then
            s = s .. ch
        end
    end
    return s
end

local function decodeString(frameID, data)
    local fCh = string.byte(data)
    data = string.sub(data, 2)
    local hasBom = false
    if fCh == 0x01 then
        for i = 1, #data do
            if i + 2 < #data then
                local bom = string.sub(data, i, i + 1)
                if bom == '\xFF\xFE' or bom == '\xFE\xFF' then
                    data = string.sub(data, i + 2)
                    data = bom .. data
                    hasBom = true
                    break
                end
            else
                break
            end
        end
        if string.sub(data, 3, 3) == '\0' then
            local bom = string.sub(data, 1, 2)
            data = string.sub(data, 4)
            data = bom .. data
        end
    end
    if fCh == 0x02 then
        if string.sub(data, 1, 1) == '\0' then
            data = string.sub(data, 2)
        end
    end
    if frameID ~= 'TYER' and frameID ~= 'TDRC' and frameID ~= 'TRCK' and frameID ~= 'TPOS' then
        if fCh == 0x01 then
            data = utf16_to_utf8(data)
        elseif fCh == 0x02 then
            data = utf16_to_utf8(data, true)
        end
    else
        if hasBom then
            data = string.sub(data, 3)
        end
    end
    data = removeNulls(data)
    return data
end

local function findFrames()
    while file:seek() + 10 < tagPos + tagSize do
        local frameID = file:read(4)
        if frameID == nil or #frameID ~= 4 then
            break
        end
        local breakOuter = false
        for i = 1, #frameID do
            if string.sub(frameID, i, i) == '\0' then
                breakOuter = true
                break
            end
        end
        if breakOuter then
            break
        end
        local dataSize = 0
        if versionMajor == 3 then
            dataSize = fileHelper.readNumber(file, 4, false)
        elseif versionMajor == 4 then
            dataSize = getSynchSafeNumber(file, 4)
        end
        file:seek('cur', 2)
        if frameIDs[frameID] then
            local data = nil
            if frameID == 'APIC' then
                file:seek('cur', dataSize)
            else
                data = file:read(dataSize)
            end
            if data ~= nil then
                data = decodeString(frameID, data)
                if frameID == 'TIT2' then
                    track.title = data
                end
                if frameID == 'TPE1' then
                    track.artist = data
                end
                if frameID == 'TALB' then
                    track.album = data
                end
                if frameID == 'TYER' or frameID == 'TDRC' then
                    track.year = data
                end
                if frameID == 'TRCK' then
                    track.trck = data
                end
                if frameID == 'TCON' then
                    local numString = string.match(data, '^%d+')
                    if numString ~= nil then
                        if #numString == #data then
                            local genreIndex = tonumber(numString) + 1
                            if genreIndex <= #ID3V1.ID3V1_GENRES then
                                data = ID3V1.ID3V1_GENRES[genreIndex]
                            end
                        end
                    end
                    local numStrings = string.gmatch(data, '%(%d+%)')
                    for numStr in numStrings do
                        local numStrStripped = string.match(numStr, '%d+')
                        local num = tonumber(numStrStripped) + 1
                        if num <= #ID3V1.ID3V1_GENRES then
                            data = string.gsub(data, '%(' .. numStrStripped .. '%)', ID3V1.ID3V1_GENRES[num] .. '/')
                        end
                    end
                    if string.sub(data, -1, -1) == '/' then
                        data = string.sub(data, 1, -2)
                    end
                    track.genre = data
                end
                if frameID == 'TPOS' then
                    track.albumPos = data
                end
                if frameID == 'TPE2' then
                    track.albumArtist = data
                end
            end
        else
            file:seek('cur', dataSize)
        end
    end
end

local function detectID3V2Tag(f, t, fromBack)
    file = f
    track = t
    tagPos = file:seek()
    tagSize = 0
    local detect = file:read(3)
    if detect == "ID3" or (fromBack and detect == "3DI") then
        versionMajor = fileHelper.readNumber(file, 1, true)
        if versionMajor == 3 or versionMajor == 4 then
            file:seek('cur', 1)
            local headerFlags = fileHelper.readNumber(file, 1, true)
            local unSynchronized = bit.band(headerFlags, 0x80) == 0x80
            local extendedHeader = bit.band(headerFlags, 0x40) == 0x40
            local experimental = bit.band(headerFlags, 0x20) == 0x20
            local footer = bit.band(headerFlags, 0x10) == 0x10
            tagSize = getSynchSafeNumber(file, 4)
            if footer then
                tagSize = tagSize + 20
            else
                tagSize = tagSize + 10
            end
            if fromBack then
                tagPos = track.endOfAudio - tagSize
                file:seek("set", tagPos + 10)
            end
            if not unSynchronized and not experimental then
                if extendedHeader then
                    local extendedHeaderSize = 0
                    if versionMajor == 3 then
                        extendedHeaderSize = fileHelper.readNumber(file, 4, false) + 4
                    elseif versionMajor == 4 then
                        extendedHeaderSize = getSynchSafeNumber(file, 4)
                    end
                    file:seek('cur', extendedHeaderSize - 4)
                end
                findFrames()
            end
        end
    end
    if not fromBack then
        file:seek("set", tagPos + tagSize)
    end
    return tagSize
end

local function detectID3V2TagAtBack(file, track)
    local currentPos = file:seek()
    file:seek("set", track.endOfAudio - 10)
    local tagSize = detectID3V2Tag(file, track, true)
    file:seek("set", currentPos)
    track.endOfAudio = track.endOfAudio - tagSize
end

M.initVariables = initVariables
M.detectID3V2Tag = detectID3V2Tag
M.detectID3V2TagAtBack = detectID3V2TagAtBack

return M