local M = {}

local speaker
local msgDirNotExists = "Stereo: the music folder doesn't exist"
local msgShorted = "Stereo: system shorted"
local msgEmpty = "Stereo: the music folder is empty"
local msgVolumeAt = 'Stereo: volume at '
local msgVolumeMuted = 'Stereo: volume muted'
local msgShuffleOn = "Stereo: shuffle mode is on"
local tracksFolder = "music"
local guiActive = "active"
local guiShuffle = "shuffle"
local guiRepeat = "repeat_mode"
local guiFile = "file"
local guiPlaying = "playing"
local guiVolume = 'volume'
local guiTrackCount = "track count"
local cachedTracks = {}
local trackFiles = {}
local shuffleIndex
local caching
local cachePos
local cacheSize = 3
local halfCacheSize
local nextDownTime = 0
local nextUpTime = 0
local prevDownTime = 0
local prevUpTime = 0
local wasHolding
local wasHolding2
local dirExists
local shuffle
local delayedPlay = false
local delayedPlayTime = 0
local loopedOnce
local profile = "AudioMusic2D"
local shortedInWater
local shortAtTime = 0
local engine
local vehicleElectrics
local delayedVolUp = false
local paused
local delayedVolUpTime = 0
local MAX_VOLUME = 16
local DESKTOP_VOLUME = 6
local MIN_VOLUME_VALUE = .001575
local VOLUME_QUANTA = 1
local volume
local volumeDownTime
local prevVolumeDownTime
local volumeUpTime
local prevVolumeUpTime
local volumeButtonDown
local volumeButtonUp
local wasOn
local wasPlaying
local displayedDetails
local MSG_DURATION = 5
local initialized = false
local trackIndex
local isVehicle
local playDuration
local repeatMode
local restartFromBeginning
local endOfPlayList
local file
local fileIsOpen
local fileHelper
local metaString
local mp3Duration
local wavDuration
local id3V1
local id3V2
local ape
local lyrics
local displayedRecoveredMessage

local fileTypes = {}
fileTypes[".mp3"] = true
fileTypes[".wav"] = true

local function luaMod(x, mod)
	local y = x % mod
	if y == 0 then
		y = mod
	end
	return y
end

local function swapElements(arr, i1, i2)
	local copy = deepcopy(arr[i1])
	arr[i1] = deepcopy(arr[i2])
	arr[i2] = deepcopy(copy)
end

local function cacheTrackIndex()
	if caching then
		return luaMod(trackIndex - cachePos + 1, #trackFiles)
	else
		return trackIndex
	end
end

local function displayTrack(state)
    local trStr = 'Stereo: '
    local trNum = 'track ' .. tostring(trackIndex) .. ' of ' .. tostring(#trackFiles)
    local meta = '\n' .. metaString
    if state == 'playing' then
        trStr = trStr .. 'now playing ' .. trNum .. meta
    elseif state == 'pausing' then
        trStr = trStr .. trNum .. ' is paused' .. meta
    elseif state == 'current' then
        trStr = trStr .. state .. ' ' .. trNum .. meta
    elseif state == 'stopping' then
        trStr = trStr .. 'stopped playing ' .. trNum .. meta
    elseif state == 'resetting' then
        trStr = trStr .. 'reset ' .. trNum .. ' to beginning' .. meta
    elseif state == 'resuming' then
        trStr = trStr .. state .. ' ' .. trNum .. meta
    end
    gui.message(trStr, MSG_DURATION, guiPlaying)
    if state == 'playing' or state == 'resuming' then
        if trackFiles[trackIndex].version1LayerI then
            gui.message('Stereo: Warning - ' .. string.sub(trackFiles[trackIndex].file, 8) .. ' contains at least one MPEG-1 Layer I frame and thus might not be supported by FMOD', MSG_DURATION, 'warning')
        end
        if trackFiles[trackIndex].duration ~= trackFiles[trackIndex].duration then
            gui.message('Stereo: Error - could not obtain the duration of ' .. string.sub(trackFiles[trackIndex].file, 8), MSG_DURATION, 'error')
        end
    end
end

local function displayRepeatMode()
    local repeatModeString = ""
    if repeatMode == 1 then
        repeatModeString = "Stereo: repeat mode is off"
    elseif repeatMode == 2 then
        repeatModeString = "Stereo: repeat mode is playlist"
    elseif repeatMode == 3 then
        repeatModeString = "Stereo: repeat mode is song"
    end
    gui.message(repeatModeString, MSG_DURATION, guiRepeat)
end

local function displayState(notifyDirectoryIssues)
    if isVehicle then
        if shortedInWater then
            gui.message(msgShorted, MSG_DURATION, guiActive)
        elseif vehicleElectrics.values.ignition ~= true then
            gui.message("Stereo: ignition is off", MSG_DURATION, guiActive)
        elseif not notifyDirectoryIssues then
            gui.message('Stereo: system is off', MSG_DURATION, guiActive)
        end
        if notifyDirectoryIssues then
            if dirExists and #trackFiles == 0 then
                gui.message(msgEmpty, MSG_DURATION, guiFile)
            elseif not dirExists then
                gui.message(msgDirNotExists, MSG_DURATION, guiFile)
            end
        end
    end
end

local function toggleRepeatMode()
	if #trackFiles > 0 and vehicleElectrics.values.ignition == true and not shortedInWater and isVehicle then
        repeatMode = repeatMode + 1
        if repeatMode == 4 then
            repeatMode = 1
        end
        displayRepeatMode()
    else
        displayState(true)
    end
end

local function buildMetaDataString()
    metaString = ""
    local track = trackFiles[trackIndex]
    if track.title ~= nil then
        metaString = metaString .. "Title: " .. track.title
    end
    if track.artist ~= nil then
        metaString = metaString .. "\nArtist: " .. track.artist
    end
    if track.album ~= nil then
        metaString = metaString .. "\nAlbum: " .. track.album
    end
    if track.trck ~= nil then
        metaString = metaString .. "\nTrack: " .. track.trck
    end
    if track.genre ~= nil then
        metaString = metaString .. "\nGenre: " .. track.genre
    end
    if track.year ~= nil then
        metaString = metaString .. "\nYear: " .. track.year
    end
end

local function displayDetails()
    if electrics.values.stereoSystemOn == 1 then
        displayedDetails = true
        if volume >= 1 then
            gui.message(msgVolumeAt .. tostring(volume) .. ' - ' .. tostring(MAX_VOLUME), MSG_DURATION, guiVolume)
        else
            gui.message(msgVolumeMuted, MSG_DURATION, guiVolume) 
        end
        if shuffle then
            gui.message(msgShuffleOn, MSG_DURATION, guiShuffle)
        end
        displayRepeatMode()
        if not delayedPlay then
            if paused and not endOfPlayList then
                displayTrack('pausing')
            elseif endOfPlayList then
                gui.message("Stereo: reached the end of the playlist", MSG_DURATION, guiPlaying)
            end
        end
    end
end

local function increaseVolume()
    if electrics.values.stereoSystemOn == 1 and isVehicle then
        if volume < MAX_VOLUME and volume >= VOLUME_QUANTA then
            volume = volume + VOLUME_QUANTA
        elseif volume < VOLUME_QUANTA then
            volume = VOLUME_QUANTA
        end
        if not paused then
            obj:setVolume(cachedTracks[cacheTrackIndex()].sfx, volume)
        end
        gui.message(msgVolumeAt .. tostring(volume) .. ' - ' .. tostring(MAX_VOLUME), MSG_DURATION, guiVolume)
    else
        displayState(false)
    end
end

local function decreaseVolume()
    if electrics.values.stereoSystemOn == 1 and isVehicle then
        if volume > VOLUME_QUANTA then
            volume = volume - VOLUME_QUANTA
        elseif volume == VOLUME_QUANTA then
            volume = MIN_VOLUME_VALUE
        end
        if not paused then
            obj:setVolume(cachedTracks[cacheTrackIndex()].sfx, volume)
        end
        if volume >= 1 then
            gui.message(msgVolumeAt .. tostring(volume) .. ' - ' .. tostring(MAX_VOLUME), MSG_DURATION, guiVolume)
        else
            gui.message(msgVolumeMuted, MSG_DURATION, guiVolume)
        end
    else
        displayState(false)
    end
end

local function decreaseVolumeButtonDown()
    volumeDownTime = os.time()
    prevVolumeDownTime = volumeDownTime
    volumeButtonDown = true
end

local function decreaseVolumeButtonUp()
    volumeDownTime = 0
    volumeButtonDown = false
end

local function increaseVolumeButtonDown()
    volumeUpTime = os.time()
    prevVolumeUpTime = volumeUpTime
    volumeButtonUp = true
end

local function increaseVolumeButtonUp()
    volumeUpTime = 0
    volumeButtonUp = false
end

local function getMetaData(fromShuffle)
    if fileIsOpen then
        file:close()
        fileIsOpen = false
    end
    if trackFiles[trackIndex].gettingMetaData then
        file = io.open(trackFiles[trackIndex].file, 'rb')
        fileIsOpen = true
        if trackFiles[trackIndex].endOfAudio == -1 then
            trackFiles[trackIndex].endOfAudio = fileHelper.fileSize(file)
            trackFiles[trackIndex].fileSeek = 0
        end
    end
    if trackFiles[trackIndex].detectedTags then
        buildMetaDataString()
        if electrics.values.stereoSystemOn == 1 then
            if fromShuffle then
                displayTrack('current')
            elseif not fromShuffle then
                displayTrack('playing')
            end
        end
    end
end

local function systemPlayTrack(track)
    wasPlaying = true
    endOfPlayList = false
    restartFromBeginning = false
	obj:setVolume(track.sfx, volume)
    obj:setPitch(track.sfx, 1)
	obj:cutSFX(track.sfx)
    getMetaData(false)
	obj:playSFX(track.sfx)
    paused = false
    playDuration = 0
end

local function setNextDownTime()
	nextDownTime = os.time()
end

local function setPrevDownTime()
	prevDownTime = os.time()
end

local function setNextUpTime()
	if wasHolding then
		wasHolding = false
	else
		nextUpTime = os.time()
	end
end

local function setPrevUpTime()
	if wasHolding2 then
		wasHolding2 = false
	else
		prevUpTime = os.time()
	end
end

local function loadCacheAndGetFiles(directory)
	trackFiles = {}
    if fileIsOpen then
        file:close()
        fileIsOpen = false
    end
	if FS:directoryExists(directory) then
		caching = true
		dirExists = true
		local files = FS:findFiles(directory, "*.*", -1, true, false)
        local i = 1
		for _, file in ipairs(files) do
			local extension = string.lower(string.sub(file, -4))
			if fileTypes[extension] then
				local tr = {}
				tr.file = file
				tr.index = i
                tr.duration = 0
                tr.gettingMetaData = true
                tr.calculating = true
                tr.fileType = extension
                tr.detectedTags = false
                tr.title = string.sub(file, 8, -5)
                tr.artist = nil
                tr.album = nil
                tr.trck = nil
                tr.year = nil
                tr.genre = nil
                tr.albumArtist = nil
                tr.albumPos = nil
                tr.checkForLyrics = false
                tr.version1LayerI = false
                tr.version1LayerIDisplayed = false
                tr.endOfAudio = -1
                tr.fileSeek = -1
				table.insert(trackFiles, tr)
                i = i + 1
			end
		end
		if #trackFiles <= cacheSize then
			caching = false
		end
		if caching then
			cachePos = #trackFiles + 1 - halfCacheSize
			for i = 1, cacheSize do
				local index = luaMod(i - halfCacheSize, #trackFiles)
				cachedTracks[i] = {}
				cachedTracks[i].sfx = nil
				cachedTracks[i].name = trackFiles[index].file
			end
		else
			for i = 1, #trackFiles, 1 do
				cachedTracks[i] = {}
				cachedTracks[i].sfx = nil
				cachedTracks[i].name = trackFiles[i].file
			end
		end
	else
		dirExists = false
	end
end

local function init()
    local dataString = readFile(v.vehicleDirectory .. 'info.json')
    isVehicle = false
    if dataString then
        dataString = string.lower(dataString)
        local data = jsonDecode(dataString)
        if data.type then
            if data.type == 'car' or data.type == 'truck' or data.type == 'automation' or data.type == 'traffic' then
                isVehicle = true
            end
        end
        vehicleElectrics = require("electrics")
        engine = powertrain.getDevice('mainEngine')
        shortedInWater = false
        restartFromBeginning = false
        electrics.values.stereoSystemOn = 0
        mp3Duration = require('lua/vehicle/extensions/auto/metadata/duration/MP3Duration')
        wavDuration = require('lua/vehicle/extensions/auto/metadata/duration/WAVDuration')
        id3V1 = require('lua/vehicle/extensions/auto/metadata/ID3V1')
        id3V2 = require('lua/vehicle/extensions/auto/metadata/ID3V2')
        ape = require('lua/vehicle/extensions/auto/metadata/APE')
        lyrics = require('lua/vehicle/extensions/auto/metadata/Lyrics3')
        ape.initVariables()
        id3V2.initVariables()
        mp3Duration.initVariables()
        wavDuration.initVariables()
        fileHelper = require('lua/vehicle/extensions/auto/utilities/FileHelper')
        wasOn = false
        fileIsOpen = false
        wasPlaying = false
        paused = true
        shuffle = false
        repeatMode = 2
        displayedDetails = false
        playDuration = 0
        endOfPlayList = false
        math.randomseed(os.time())
        trackIndex = 1
        halfCacheSize = math.floor(cacheSize/2)
        volume = DESKTOP_VOLUME
        if isVehicle then
            loadCacheAndGetFiles(tracksFolder)
            if v.data.refNodes and v.data.refNodes[0] then
                speaker = v.data.refNodes[0].ref or v.data.refNodes[0].leftCorner
            end
        else
            isVehicle = false
        end
    end
end

local function killStereoSystem()
	electrics.values.stereoSystemOn = 0
	wasPlaying = false
    paused = true
    wasOn = false
	for _, track in ipairs(cachedTracks) do
        obj:cutSFX(track.sfx)
		obj:deleteSFXSource(track.sfx, true)
		track.sfx = nil
	end
end

local function toggleStereoSystem()
	if #trackFiles > 0 and vehicleElectrics.values.ignition == true and not shortedInWater and isVehicle then
		if electrics.values.stereoSystemOn == 1 then
			killStereoSystem()
			gui.message("Stereo: system is now off", MSG_DURATION, guiActive)
            displayTrack('stopping')
		else
			electrics.values.stereoSystemOn = 1
            wasOn = true
			delayedPlay = true
            displayDetails()
			for _, track in ipairs(cachedTracks) do
				track.sfx = obj:createSFXSource(track.name, profile, track.name, speaker)
			end
			gui.message("Stereo: system is now on", MSG_DURATION, guiActive)
		end
	else
        displayState(true)
	end
end

local function updateCache(incr)
	if incr == 1 then
		cachePos = luaMod(cachePos + halfCacheSize, #trackFiles)
		obj:deleteSFXSource(cachedTracks[1].sfx, true)
		for i = 1, cacheSize - halfCacheSize do
			cachedTracks[i] = deepcopy(cachedTracks[i + halfCacheSize])
		end
		if shuffleIndex == 2 and shuffle then
			obj:deleteSFXSource(cachedTracks[cacheTrackIndex()].sfx, true)
			cachedTracks[cacheTrackIndex()].sfx = obj:createSFXSource(trackFiles[trackIndex].file, profile, trackFiles[trackIndex].file, speaker)
			cachedTracks[cacheTrackIndex()].name = trackFiles[trackIndex].file
			delayedPlay = true
		end
		local index = luaMod(trackIndex + 1, #trackFiles)
		cachedTracks[3].sfx = obj:createSFXSource(trackFiles[index].file, profile, trackFiles[index].file, speaker)
		cachedTracks[3].name = trackFiles[index].file
	elseif incr == -1 then
		cachePos = luaMod(cachePos - halfCacheSize, #trackFiles)
		obj:deleteSFXSource(cachedTracks[3].sfx, true)
		for i = cacheSize, cacheSize - halfCacheSize, -1 do
			cachedTracks[i] = deepcopy(cachedTracks[i - halfCacheSize])
		end
		local index = luaMod(trackIndex - 1, #trackFiles)
		cachedTracks[1].sfx = obj:createSFXSource(trackFiles[index].file, profile, trackFiles[index].file, speaker)
		cachedTracks[1].name = trackFiles[index].file
	end
end

local function nextTrack()
	if electrics.values.stereoSystemOn == 1 and isVehicle then
		obj:cutSFX(cachedTracks[cacheTrackIndex()].sfx)
		local newCachePos = trackIndex
		trackIndex = luaMod(trackIndex + 1, #trackFiles)
		local swap = true
		if trackIndex == #trackFiles and shuffle then
			loopedOnce = true
			swap = false
		end
		if trackIndex == shuffleIndex and shuffle then
			if shuffleIndex ~= 1 then
				shuffleIndex = luaMod(shuffleIndex + 1, #trackFiles)
			end
			if swap then
				local maxIndex = #trackFiles
				if shuffleIndex < newCachePos then
					maxIndex = cachePos
				end
				local tmpShuffleIndex = shuffleIndex
				local moreRandom = math.random(1, 2)
				if moreRandom == 2 then
					tmpShuffleIndex = math.random(shuffleIndex, maxIndex)
				end
				local rIndex = math.random(tmpShuffleIndex, maxIndex)
				swapElements(trackFiles, rIndex, shuffleIndex)
			end
			if shuffleIndex == 1 and swap then
				shuffleIndex = luaMod(shuffleIndex + 1, #trackFiles)
			end
		end
		if shuffle and not caching and #cachedTracks == cacheSize and trackIndex == 1 then
			for i = 1, 2 do
				local rIndex = math.random(1, 2)
				if rIndex == 1 then
					swapElements(cachedTracks, i, i + 1)
					swapElements(trackFiles, i, i + 1)
				end
			end
		end
		if cacheTrackIndex() == cacheSize and caching then
			updateCache(1)
		end
		if not delayedPlay then
			systemPlayTrack(cachedTracks[cacheTrackIndex()])
		end
	else
        displayState(false)
    end
end

local function previousTrack(playOnRepeat)
	if electrics.values.stereoSystemOn == 1 and isVehicle then
        if (playDuration >= 3) or (shuffle and not loopedOnce and trackIndex == 1) or playOnRepeat then
            if not paused or playOnRepeat then
                systemPlayTrack(cachedTracks[cacheTrackIndex()])
            else
                playDuration = 0
                restartFromBeginning = true
                endOfPlayList = false
                displayTrack('resetting')
            end
        else
            obj:cutSFX(cachedTracks[cacheTrackIndex()].sfx)
            trackIndex = luaMod(trackIndex - 1, #trackFiles)
            if cacheTrackIndex() == 1 and caching then
                updateCache(-1)
            end
            systemPlayTrack(cachedTracks[cacheTrackIndex()])
        end
	else
        displayState(false)
    end
end

local function playPause(userPlayPaused)
	if electrics.values.stereoSystemOn == 1 and isVehicle then
        if not paused then
            if userPlayPaused then
                displayTrack('pausing')
                wasPlaying = false
            end
            paused = true
			obj:setVolume(cachedTracks[cacheTrackIndex()].sfx, MIN_VOLUME_VALUE)
			obj:setPitch(cachedTracks[cacheTrackIndex()].sfx, 0)
		else
            if restartFromBeginning then
                systemPlayTrack(cachedTracks[cacheTrackIndex()])
            else
                obj:setPitch(cachedTracks[cacheTrackIndex()].sfx, 1)
            end
            paused = false
			delayedVolUp = true
            wasPlaying = true
            displayTrack('resuming')
		end
    else
        displayState(false)
    end
end

local function onReset()
    if wasOn then
        for i, cached in ipairs(cachedTracks) do
            if i ~= cacheTrackIndex() or endOfPlayList or restartFromBeginning then
                obj:cutSFX(cached.sfx)
            end
        end
	end
    if shortedInWater then
        shortedInWater = false
        displayedRecoveredMessage = true
        gui.message("Stereo: system recovered", MSG_DURATION, guiActive)
        displayDetails()
    end
end

local function scanForTracks()
    if isVehicle then
        if dirExists then
            gui.message("Stereo: scan - there were " .. tostring(#trackFiles) .. " track(s) detected in the music folder\nScanning for newly added tracks...", MSG_DURATION, guiTrackCount)
        end
        wasPlaying = false
        displayedDetails = false
        if shuffle then
            shuffle = false
            gui.message("Stereo: shuffle mode reset to off", MSG_DURATION, guiShuffle)
        end
        if wasOn then
            gui.message("Stereo: system reset to off", MSG_DURATION, guiActive)
            killStereoSystem()
        end
        trackIndex = 1
        local oldNum = #trackFiles
        loadCacheAndGetFiles(tracksFolder)
        if dirExists then
            if #trackFiles > oldNum then
                local dif = #trackFiles - oldNum
                gui.message("Stereo: scan - found " .. tostring(dif) .. " new track(s) in the music folder\nthere are now " .. tostring(#trackFiles) .. " track(s) in the music folder", MSG_DURATION, guiFile)
            elseif #trackFiles < oldNum then
                local dif = oldNum - #trackFiles
                gui.message("Stereo: scan - " .. tostring(dif) .. " track(s) were removed from the music folder\nthere are now " .. tostring(#trackFiles) .. " track(s) in the music folder", MSG_DURATION, guiFile)
            else
                gui.message("Stereo: scan - no new tracks were added to the music folder", MSG_DURATION, guiFile)
            end
        else
            gui.message("Stereo: scan - the music folder doesn't exist", MSG_DURATION, guiFile)
        end
    end
end

local function operator(first, second)
	if first.index < second.index then
		return true
	else
		return false
	end
end

local function toggleShuffleMode()
	if #trackFiles > 0 and vehicleElectrics.values.ignition == true and not shortedInWater and isVehicle then
		shuffle = not shuffle
		if shuffle then
			loopedOnce = false
			gui.message(msgShuffleOn, MSG_DURATION, guiShuffle)
			local startInd = 1
			if electrics.values.stereoSystemOn == 1 then
				if cacheTrackIndex() ~= 1 then
					obj:deleteSFXSource(cachedTracks[1].sfx, true)
					cachedTracks[1] = deepcopy(cachedTracks[cacheTrackIndex()])
					cachedTracks[cacheTrackIndex()].sfx = nil
					swapElements(trackFiles, 1, trackIndex)
				end
				startInd = 2
			end
			shuffleIndex = startInd
			for i = startInd, #cachedTracks do
				if (i ~= cacheTrackIndex() or electrics.values.stereoSystemOn == 0) and cachedTracks[i].sfx ~= nil then
					obj:deleteSFXSource(cachedTracks[i].sfx, true)
				end
			end
			for i = startInd, #cachedTracks do
				local tmpShuffleIndex = shuffleIndex
				local moreRandom = math.random(1, 2)
				if moreRandom == 2 then
					tmpShuffleIndex = math.random(shuffleIndex, #trackFiles)
				end
				local rIndex = math.random(tmpShuffleIndex, #trackFiles)
				if electrics.values.stereoSystemOn == 1 then
					cachedTracks[i].sfx = obj:createSFXSource(trackFiles[rIndex].file, profile, trackFiles[rIndex].file, speaker)
				else
					cachedTracks[i].sfx = nil
				end
				cachedTracks[i].name = trackFiles[rIndex].file
				swapElements(trackFiles, rIndex, shuffleIndex)
				shuffleIndex = shuffleIndex + 1
			end
			if caching then
				shuffleIndex = 3
			end
			trackIndex = 1
			cachePos = 1
		else
			gui.message("Stereo: shuffle mode is off", MSG_DURATION, guiShuffle)
			for i, track in ipairs(cachedTracks) do
				if (i ~= cacheTrackIndex() or electrics.values.stereoSystemOn == 0) and track.sfx ~= nil then
					obj:deleteSFXSource(track.sfx, true)
				end
			end
			local copy = deepcopy(cachedTracks[cacheTrackIndex()])
			trackIndex = trackFiles[trackIndex].index
			cachePos = luaMod(trackIndex - halfCacheSize, #trackFiles)
			cachedTracks[cacheTrackIndex()] = deepcopy(copy)
			table.sort(trackFiles, operator)
            for i = 1, #cachedTracks do
				local index = i
				if caching then
					index = luaMod(cachePos + i - 1, #trackFiles)
				end
				if i ~= cacheTrackIndex() then
					if electrics.values.stereoSystemOn == 1 then
						cachedTracks[i].sfx = obj:createSFXSource(trackFiles[index].file, profile, trackFiles[index].file, speaker)
					else
						cachedTracks[i].sfx = nil
					end
					cachedTracks[i].name = trackFiles[index].file
				end
			end
		end
        getMetaData(true)
	else
        displayState(true)
	end
end

local function detectedTagsAtBack()
    local oldEnd = trackFiles[trackIndex].endOfAudio
    id3V1.detectID3V1Tag(file, trackFiles[trackIndex])
    id3V2.detectID3V2TagAtBack(file, trackFiles[trackIndex])
    ape.detectAPETagAtBack(file, trackFiles[trackIndex])
    lyrics.detectLyricsTag(file, trackFiles[trackIndex])
    if trackFiles[trackIndex].checkForLyrics then
        return false
    end
    return oldEnd ~= trackFiles[trackIndex].endOfAudio
end

local function detectedTagsAtFront()
    local oldPos = file:seek()
    id3V2.detectID3V2Tag(file, trackFiles[trackIndex], false)
    ape.detectAPETag(file, false)
    trackFiles[trackIndex].fileSeek = file:seek()
    return oldPos ~= file:seek()
end

local function checkForEndOfTrack(dt)
    if not paused then
        playDuration = playDuration + dt
        if playDuration >= trackFiles[trackIndex].duration and not trackFiles[trackIndex].calculating then
            paused = true
            wasPlaying = false
            if repeatMode == 1 then
                if trackIndex ~= #trackFiles then
                    nextTrack()
                else
                    endOfPlayList = true
                    obj:cutSFX(cachedTracks[cacheTrackIndex()].sfx)
                    gui.message("Stereo: reached the end of the playlist", MSG_DURATION, guiPlaying)
                end
            elseif repeatMode == 2 then
                nextTrack()
            elseif repeatMode == 3 then
                previousTrack(true)
            end
        end
    end
end

local function getMetaDataFromFile()
    if #trackFiles > 0 and trackFiles[trackIndex].gettingMetaData and fileIsOpen then
        if trackFiles[trackIndex].calculating and (trackFiles[trackIndex].detectedTags or trackFiles[trackIndex].fileType == '.wav') then
            if trackFiles[trackIndex].version1LayerI and not trackFiles[trackIndex].version1LayerIDisplayed then
                trackFiles[trackIndex].version1LayerIDisplayed = true
                gui.message('Stereo: Warning - ' .. string.sub(trackFiles[trackIndex].file, 8) .. ' contains at least one MPEG-1 Layer I frame and thus might not be supported by FMOD', MSG_DURATION, 'warning')
            end
            if trackFiles[trackIndex].fileType == ".mp3" then
                mp3Duration.calculateDuration(file, trackFiles[trackIndex])
            elseif trackFiles[trackIndex].fileType == ".wav" then
                wavDuration.calculateDuration(file, trackFiles[trackIndex])
            end
            if not trackFiles[trackIndex].calculating then
                trackFiles[trackIndex].gettingMetaData = false
                if trackFiles[trackIndex].duration ~= trackFiles[trackIndex].duration then
                    gui.message('Stereo: Error - could not obtain the duration of ' .. string.sub(trackFiles[trackIndex].file, 8), MSG_DURATION, 'error')
                end
                file:close()
                fileIsOpen = false
                if trackFiles[trackIndex].fileType == '.wav' then
                    trackFiles[trackIndex].detectedTags = true
                    buildMetaDataString()
                    if electrics.values.stereoSystemOn == 1 then
                        displayTrack('playing')
                    end
                end
            end
        elseif trackFiles[trackIndex].fileType == '.mp3' and not trackFiles[trackIndex].detectedTags then
            while detectedTagsAtBack() do
            end
            while detectedTagsAtFront() do
            end
            trackFiles[trackIndex].detectedTags = true
            buildMetaDataString()
            if electrics.values.stereoSystemOn == 1 then
                displayTrack('playing')
            end
        end
    end
end

local function updateGFX(dt)
    if not initialized then
        init()
        initialized = true
    end
    if isVehicle then
        if (vehicleElectrics.values.ignition ~= true or shortedInWater) and wasOn then
            displayedDetails = false
        end
        if (vehicleElectrics.values.ignition ~= true or shortedInWater) and electrics.values.stereoSystemOn == 1 then
            if not paused then
                playPause(false)
            end
            electrics.values.stereoSystemOn = 0
            if not shortedInWater then
                wasPlaying = true
            end
            if not shortedInWater then
                gui.message("Stereo: ignition turned off", MSG_DURATION, guiActive)
            end
        elseif vehicleElectrics.values.ignition == true and not shortedInWater and wasOn and electrics.values.stereoSystemOn == 0 then
            electrics.values.stereoSystemOn = 1
            if wasPlaying then
                playPause(false)
            end
            if not displayedRecoveredMessage then
                gui.message("Stereo: ignition turned on", MSG_DURATION, guiActive)
            end
            displayDetails()
        end
        if displayedRecoveredMessage then
            displayedRecoveredMessage = false
        end
        checkForEndOfTrack(dt)
        getMetaDataFromFile()
        if delayedPlay then
            delayedPlayTime = delayedPlayTime + dt
            if delayedPlayTime > 1/15 then
                delayedPlay = false
                delayedPlayTime = 0
                systemPlayTrack(cachedTracks[cacheTrackIndex()])
            end
        end
        if delayedVolUp then
            delayedVolUpTime = delayedVolUpTime + dt
            if delayedVolUpTime > 1/4 then
                delayedVolUp = false
                delayedVolUpTime = 0
                obj:setVolume(cachedTracks[cacheTrackIndex()].sfx, volume)
            end
        end
        if os.time() - nextDownTime > 1 and nextUpTime == 0 and nextDownTime ~= 0 then
            nextDownTime = 0
            wasHolding = true
            toggleStereoSystem()
        elseif nextUpTime ~= 0 and nextDownTime ~= 0 then
            nextDownTime = 0
            nextUpTime = 0
            nextTrack()
        end
        if os.time() - prevDownTime > 1 and prevUpTime == 0 and prevDownTime ~= 0 then
            prevDownTime = 0
            wasHolding2 = true
            toggleShuffleMode()
        elseif prevUpTime ~= 0 and prevDownTime ~= 0 then
            prevDownTime = 0
            prevUpTime = 0
            previousTrack(false)
        end
        if volumeButtonDown then
            if volumeDownTime == os.time() then
                decreaseVolume()
            end
            volumeDownTime = volumeDownTime + dt
            if volumeDownTime - prevVolumeDownTime > .15 then
                prevVolumeDownTime = prevVolumeDownTime + .15
                decreaseVolume()
            end
        end
        if volumeButtonUp then
            if volumeUpTime == os.time() then
                increaseVolume()
            end
            volumeUpTime = volumeUpTime + dt
            if volumeUpTime - prevVolumeUpTime > .15 then
                prevVolumeUpTime = prevVolumeUpTime + .15
                increaseVolume()
            end
        end
        if not dirExists then
            if FS:directoryExists(tracksFolder) then
                dirExists = true
            end
        end
        if engine then
            local isFlooding = engine.canFlood
            for _, n in ipairs(engine.waterDamageNodes) do
                isFlooding = isFlooding and obj:inWater(n)
                if not isFlooding then
                    break
                end
            end
            if isFlooding and not shortedInWater then
                shortAtTime = shortAtTime + dt
                if shortAtTime > 4 then
                    shortAtTime = 0
                    shortedInWater = true
                    gui.message(msgShorted, MSG_DURATION, guiActive)
                end
            else
                shortAtTime = 0
            end
        end
    end
end

M.updateGFX = updateGFX
M.onReset = onReset
M.toggleStereoSystem = toggleStereoSystem
M.setNextDownTime = setNextDownTime
M.setNextUpTime = setNextUpTime
M.setPrevDownTime = setPrevDownTime
M.setPrevUpTime = setPrevUpTime
M.scanForTracks = scanForTracks
M.toggleShuffleMode = toggleShuffleMode
M.playPause = playPause
M.decreaseVolumeButtonUp = decreaseVolumeButtonUp
M.decreaseVolumeButtonDown = decreaseVolumeButtonDown
M.increaseVolumeButtonUp = increaseVolumeButtonUp
M.increaseVolumeButtonDown = increaseVolumeButtonDown
M.toggleRepeatMode = toggleRepeatMode

return M