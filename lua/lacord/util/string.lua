--- String utilities.
-- @module util.string
-- @alias _ENV

local setmetatable, getmetatable = setmetatable,getmetatable
local global_string = string
local min = math.min
local unpack = table.unpack
local type = type

local _ENV = {}

getmetatable"".__mod = function(s, v)
    if type(v) == 'table' then return s:format(unpack(v))
    else return s:format(v)
    end
end

--- Check if a string starts with the given string `s`.
-- @string self The subject string.
-- @string s The starting value.
-- @treturn boolean
function startswith(self, s )
    return self:sub(1, #s) == s
end

--- Check if a string ends with the given string `s`.
-- @string self The subject string.
-- @string s The ending value.
-- @treturn boolean
function endswith(self, s )
    return self:sub(-#s) == s
end

--- Returns the rest of the subject string after the starting value `pre`.
-- @string self The subject string.
-- @string pre The starting string.
-- @treturn string
-- @usage
--  ("123456"):suffix("123") --> "456"
function suffix (self, pre)
    return startswith(self, pre) and self:sub(#pre+1) or self
end

--- Returns the start of the subject before the ending value `pre`.
-- @string self The subject string.
-- @string pre The ending string.
-- @treturn string
-- @usage
--  ("123456"):prefix("456") --> "123"
function prefix (self, pre)
    return endswith(self, pre) and self:sub(1,-(#pre+1)) or self
end

levenshtein_cache = setmetatable({},{__mode = "k"})

local cache_key = ("%s\0%s")

--- Computes the Levenshtein distance between two strings.
-- @string str1
-- @string str2
-- @treturn number The Levenshtein distance.
function levenshtein(str1, str2)
    if str1 == str2 then return 0 end

	local len1 = #str1
	local len2 = #str2
	if len1 == 0 then
		return len2
	elseif len2 == 0 then
		return len1
    end

    local key = cache_key:format(str1,str2)
    local cached = levenshtein_cache[key]
    if cached then
        return cached
    end

	local matrix = {}
	for i = 0, len1 do
		matrix[i] = {[0] = i}
	end
	for j = 0, len2 do
		matrix[0][j] = j
	end
	for i = 1, len1 do
		for j = 1, len2 do
            local char1 =  str1:byte(i)
            local char2 =  str2:byte(j)
            local cost = char1 == char2 and 0 or 1
            matrix[i][j] = min(matrix[i-1][j] + 1, matrix[i][j-1] + 1, matrix[i-1][j-1] + cost)
		end
    end
    local result= matrix[len1][len2]
    levenshtein_cache[key] = result
	return result
end

function inject()
    for k, v in pairs(_ENV) do
        global_string[k] = v
    end
end


--- Shorthand for formatting a string.
-- If `value` is a `table` it is unpacked into the format.
-- @function string:__mod
-- @param value A value to format into str.
-- @usage
--  "%d" % 2 --> "2"
--  "%d, %d, %d" % {1, 2, 3} --> "1, 2, 3"

return _ENV