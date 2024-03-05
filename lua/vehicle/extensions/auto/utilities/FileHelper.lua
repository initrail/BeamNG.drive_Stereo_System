local M = {}

local function peek(file, bytes)
	local pos = file:seek()
	local bytes = file:read(bytes)
	file:seek("set", pos)
	return bytes
end

local function fileSize(file)
	local size = file:seek("end")
	file:seek("set", 0)
	return size
end

local function readNumber(file, byteCount, littleEndian)
    local bytes = {string.byte(file:read(byteCount), 1, -1)}
    local num = 0
    local bitCount = byteCount * 8 - 8
    if littleEndian then
        bitCount = 0
    end
    for i = 1, byteCount do
        if bytes[i] ~= nil then
            num = num + bit.lshift(bytes[i], bitCount)
            if littleEndian then
                bitCount = bitCount + 8
            else
                bitCount = bitCount - 8
            end
        end
    end
    return num
end

M.peek = peek
M.fileSize = fileSize
M.readNumber = readNumber

return M