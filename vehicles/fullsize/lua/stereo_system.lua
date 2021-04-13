local M = {}

local speaker
local msgDirNotExists = "Stereo: the 'music' folder doesn't exist"
local msgStalled = "Stereo: engine is stalled"
local msgShorted = "Stereo: system shorted"
local msgEmpty = "Stereo: the 'music' folder is empty"
local tracksFolder = "music"
local guiActive = "active"
local guiShuffle = "shuffle"
local guiFile = "file"
local guiPlaying = "playing"
local cachedTracks = {}
local trackFiles = {}
local shuffleIndex
local caching
local startedTrackTime
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
local stalled
local profile = "AudioMusicLoop2D"
local shortedInWater
local shortAtTime = 0
local shortThreshold = .9
local engine
local wasPlaying

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

local function systemPlayTrack(track)
	local name = string.sub(track.name, 8, -5)
	gui.message("Stereo: now playing '" .. name .. "' " .. tostring(trackIndex) .. " - " .. tostring(#trackFiles), 5, guiPlaying)
	obj:setVolume(track.sfx, 1)
	obj:cutSFX(track.sfx)
	startedTrackTime = os.time()
	obj:playSFX(track.sfx)
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

local function appendTable(t1, t2)
	for _, v in ipairs(t2) do
		table.insert(t1, v)
	end
end

local function loadCacheAndGetFiles(directory)
	trackFiles = {}
	if speaker ~= nil then
		if FS:directoryExists(directory) then
			caching = true
			dirExists = true
			local files = FS:findFiles(directory, "*.mp3", -1, true, false)
			local wavFiles = FS:findFiles(directory, "*.wav", -1, true, false)
			appendTable(files, wavFiles)
			table.sort(files)
			for i, file in ipairs(files) do
				local tr = {}
				tr.file = file
				tr.index = i
				table.insert(trackFiles, tr)
			end
			if #files <= cacheSize then
				caching = false
			end
			if caching then
				cachePos = #files + 1 - halfCacheSize
				for i = 1, cacheSize do
					local index = luaMod(i - halfCacheSize, #files)
					cachedTracks[i] = {}
					cachedTracks[i].sfx = nil
					cachedTracks[i].name = files[index]
				end
			else
				for i = 1, #files, 1 do
					cachedTracks[i] = {}
					cachedTracks[i].sfx = nil
					cachedTracks[i].name = files[i]
				end
			end
		else
			dirExists = false
		end
	end
end

local function onInit()
	engine = powertrain.getDevice('mainEngine')
	shortedInWater = false
	stalled = false
	wasPlaying = false
	math.randomseed(os.time())
	electrics.values.stereo_system_on = 0
	trackIndex = 1
	shuffle = false
	speaker = nil
	halfCacheSize = math.floor(cacheSize/2)
	if v.data.refNodes and v.data.refNodes[0] then
		speaker = v.data.refNodes[0].ref or v.data.refNodes[0].leftCorner
	end
	loadCacheAndGetFiles(tracksFolder)
end

local function killStereoSystem()
	obj:cutSFX(cachedTracks[cacheTrackIndex()].sfx)
	electrics.values.stereo_system_on = 0
	for _, track in ipairs(cachedTracks) do
		obj:deleteSFXSource(track.sfx, true)
		track.sfx = nil
	end
end

local function toggleStereoSystem()
	if #trackFiles > 0 and not stalled and not shortedInWater then
		if electrics.values.stereo_system_on == 1 then
			wasPlaying = false
			killStereoSystem()
			gui.message("Stereo: system is now off", 5, guiActive)
			local name = string.sub(cachedTracks[cacheTrackIndex()].name, 8, -5)
			gui.message("Stereo: stopped playing '" .. name .. "'", 5, guiPlaying)
		else
			wasPlaying = true
			delayedPlay = true
			for _, track in ipairs(cachedTracks) do
				track.sfx = obj:createSFXSource(track.name, profile, track.name, speaker)
			end
			electrics.values.stereo_system_on = 1
			gui.message("Stereo: system is now on", 5, guiActive)
		end
	else
		if stalled and not shortedInWater then
			gui.message(msgStalled, 5, guiActive)
		elseif shortedInWater then
			gui.message(msgShorted, 5, guiActive)
		end
		if dirExists and #trackFiles == 0 then
			gui.message(msgEmpty, 5, guiFile)
		elseif not dirExists then
			gui.message(msgDirNotExists, 5, guiFile)
		end
	end
end

local function updateCache(incr)
	if speaker ~= nil then
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
end

local function nextTrack()
	if electrics.values.stereo_system_on == 1 then
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
	end
end

local function previousTrack()
	if electrics.values.stereo_system_on == 1 then
		if os.time() - startedTrackTime > 3 or (shuffle and not loopedOnce and trackIndex == 1) then
			systemPlayTrack(cachedTracks[cacheTrackIndex()])
		else
			obj:cutSFX(cachedTracks[cacheTrackIndex()].sfx)
			trackIndex = luaMod(trackIndex - 1, #trackFiles)
			if cacheTrackIndex() == 1 and caching then
				updateCache(-1)
			end
			systemPlayTrack(cachedTracks[cacheTrackIndex()])
		end
	end
end

local function onReset()
	if #trackFiles > 0 and electrics.values.stereo_system_on == 1 then
		for i, cached in ipairs(cachedTracks) do
			if (i ~= cacheTrackIndex() or electrics.values.stereo_system_on == 0) and cached.sfx ~= nil then
				obj:cutSFX(cached.sfx)
			end
		end
	end
	if wasPlaying and (stalled or shortedInWater) then
		shortedInWater = false
		stalled = false
		toggleStereoSystem()
	end
	shortedInWater = false
	stalled = false
end

local function scanForTracks()
	if shuffle then
		shuffle = false
		gui.message("Stereo: shuffle reset to off", 5, guiShuffle)
	end
	if electrics.values.stereo_system_on == 1 then
		electrics.values.stereo_system_on = 0
		gui.message("Stereo: system reset to off", 5, guiActive)
	end
	trackIndex = 1
	for _, cached in ipairs(cachedTracks) do
		if cached.sfx ~= nil then
			obj:cutSFX(cached.sfx)
			obj:deleteSFXSource(cached.sfx, true)
		end
	end
	local oldNum = #trackFiles
	loadCacheAndGetFiles(tracksFolder)
	if dirExists then
		if #trackFiles > oldNum then
			gui.message("Stereo: scan - found new tracks in the 'music' folder", 5, guiFile)
		else
			gui.message("Stereo: scan - nothing was added to the 'music' folder", 5, guiFile)
		end
	else
		gui.message("Stereo: scan - the 'music' folder doesn't exist", 5, guiFile)
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
	if #trackFiles > 0 and not stalled and not shortedInWater then
		shuffle = not shuffle
		if shuffle then
			loopedOnce = false
			gui.message("Stereo: shuffle mode is on", 5, guiShuffle)
			local startInd = 1
			if electrics.values.stereo_system_on == 1 then
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
				if (i ~= cacheTrackIndex() or electrics.values.stereo_system_on == 0) and cachedTracks[i].sfx ~= nil then
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
				if electrics.values.stereo_system_on == 1 then
					cachedTracks[i].sfx = obj:createSFXSource(trackFiles[rIndex].file, profile, trackFiles[rIndex].file, speaker)
				else
					cachedTracks[i].sfx = nil
				end
				cachedTracks[i].name = trackFiles[rIndex].file
				swapElements(trackFiles, rIndex, shuffleIndex)
				shuffleIndex = shuffleIndex + 1
			end
			trackIndex = 1
			cachePos = 1
		else
			gui.message("Stereo: shuffle mode is off", 5, guiShuffle)
			for i, track in ipairs(cachedTracks) do
				if (i ~= cacheTrackIndex() or electrics.values.stereo_system_on == 0) and track.sfx ~= nil then
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
					if electrics.values.stereo_system_on == 1 then
						cachedTracks[i].sfx = obj:createSFXSource(trackFiles[index].file, profile, trackFiles[index].file, speaker)
					else
						cachedTracks[i].sfx = nil
					end
					cachedTracks[i].name = trackFiles[index].file
				end
			end
		end
	else
		if stalled and not shortedInWater then
			gui.message(msgStalled, 5, guiActive)
		elseif shortedInWater then
			gui.message(msgShorted, 5, guiActive)
		end
		if dirExists and #trackFiles == 0 then
			gui.message(msgEmpty, 5, guiFile)
		elseif not dirExists then
			gui.message(msgDirNotExists, 5, guiFile)
		end
	end
end

local function updateGFX(dt)
	if delayedPlay then
		delayedPlayTime = delayedPlayTime + dt
		if delayedPlayTime > 1/15 then
			delayedPlay = false
			delayedPlayTime = 0
			systemPlayTrack(cachedTracks[cacheTrackIndex()])
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
		previousTrack()
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
				if electrics.values.stereo_system_on == 1 then
					killStereoSystem()
				end
				shortAtTime = 0
				shortedInWater = true
			end
		else
			shortAtTime = 0
		end
		if engine.isStalled ~= stalled then
			stalled = engine.isStalled
		end
		if stalled and electrics.values.stereo_system_on == 1 then
			killStereoSystem()
		end
	end
end

M.updateGFX = updateGFX
M.onInit = onInit
M.onReset = onReset
M.toggleStereoSystem = toggleStereoSystem
M.nextTrack = nextTrack
M.setNextDownTime = setNextDownTime
M.setNextUpTime = setNextUpTime
M.setPrevDownTime = setPrevDownTime
M.setPrevUpTime = setPrevUpTime
M.scanForTracks = scanForTracks
M.toggleShuffleMode = toggleShuffleMode

return M