local _NAME = "LibProtectedCall"
local _VERSION = "1.0.0"
local _LICENSE = [[
    MIT License

    Copyright (c) 2020 Jayrgo

    Permission is hereby granted, free of charge, to any person obtaining a copy
    of this software and associated documentation files (the "Software"), to deal
    in the Software without restriction, including without limitation the rights
    to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
    copies of the Software, and to permit persons to whom the Software is
    furnished to do so, subject to the following conditions:

    The above copyright notice and this permission notice shall be included in all
    copies or substantial portions of the Software.

    THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
    IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
    FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
    AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
    LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
    OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN THE
    SOFTWARE.
]]

assert(LibMan1, format("%s requires LibMan-1.x.x.", _NAME))
assert(LibMan1:Exists("LibEvent", 1), format("%s requires LibEvent-1.x.x.", _NAME))

local LibProtectedCall --[[ , oldVersion ]] = LibMan1:New(_NAME, _VERSION, "_LICENSE", _LICENSE)
if not LibProtectedCall then return end

local tnew, tdel
do -- tnew, tdel

    local cache = setmetatable({}, {__mode = "k"})

    local next = next
    local select = select

    ---@vararg any
    ---@return table
    function tnew(...)
        local t = next(cache)
        if t then
            cache[t] = nil
            local n = select("#", ...)
            for i = 1, n do t[i] = select(i, ...) end
            return t
        end
        return {...}
    end

    local wipe = wipe

    ---@param t table
    function tdel(t) cache[wipe(t)] = true end
end

local packargs
do -- pack2
    local select = select

    ---@vararg any
    ---@return table
    function packargs(...) return {n = select("#", ...), ...} end
end

local unpackargs
do -- pack2
    local unpack = unpack

    ---@param t table
    ---@return any
    function unpackargs(t) return unpack(t, 1, t.n) end
end

local getKey
do -- getKey
    local strhash

    do -- strhash
        local fmod = math.fmod
        local strbyte = strbyte
        local strlen = strlen

        ---@param str string
        ---@return string
        function strhash(str)
            -- Source: https://wow.gamepedia.com/StringHash
            local counter = 1
            local len = strlen(str)
            for i = 1, len, 3 do
                counter = fmod(counter * 8161, 4294967279) + -- 2^32 - 17: Prime!
                (strbyte(str, i) * 16776193) + ((strbyte(str, i + 1) or (len - i + 256)) * 8372226) +
                              ((strbyte(str, i + 2) or (len - i + 256)) * 3932164)
            end
            return fmod(counter, 4294967291) -- 2^32 - 5: Prime (and different from the prime in the loop)
        end
    end

    local getstring
    do -- getstring
        local tostring = tostring

        local prefixes = setmetatable({}, {
            __index = function(t, k)
                local v = tostring(function() end) .. "%s"
                t[k] = v
                return v
            end,
        })

        local format = format
        local type = type

        ---@param arg any
        ---@return string
        function getstring(arg) return format(prefixes[type(arg)], tostring(arg)) end
    end

    local select = select
    local tconcat = table.concat

    ---@vararg any
    ---@return string
    function getKey(...)
        local keys = tnew()
        for i = 1, select("#", ...) do keys[i] = getstring(select(i, ...)) end
        local key = strhash(tconcat(keys))
        tdel(keys)
        return key
    end
end

LibProtectedCall.registry = LibProtectedCall.registry or {}
local registry = LibProtectedCall.registry

LibProtectedCall.funcs = LibProtectedCall.funcs or {}
local funcs = LibProtectedCall.funcs

local LibEvent = LibMan1:Get("LibEvent")
local wipe = wipe

local function PLAYER_REGEN_ENABLED()
    LibEvent:Unregister("PLAYER_REGEN_ENABLED", PLAYER_REGEN_ENABLED)

    for i = 1, #registry do funcs[registry[i]]() end

    wipe(funcs)
    wipe(registry)
end

local safecall = LibProtectedCall.safecall
local xsafecall = LibProtectedCall.xsafecall
local select = select

---@param x boolean
---@param func function
---@vararg any
---@return function
local function getRegFunc(x, func, ...)
    local safecall = x and xsafecall or safecall -- luacheck: ignore 431

    if select("#", ...) == 0 then
        return function() safecall(func) end
    else
        local args = packargs(...)
        return function() safecall(func, unpackargs(args)) end
    end
end

local error = error
local format = format
local tostring = tostring
local type = type
local InCombatLockdown = InCombatLockdown

---@param x boolean
---@param func function
---@vararg any
local function Call(x, func, ...)
    if type(func) ~= "function" then
        error(format("Usage: %s:%sCall(func[, ...]): 'func' - function expected got %s", tostring(LibProtectedCall),
                     x and "x" or "", type(func)), 3)
    end

    if InCombatLockdown() then
        local regKey = getKey(func, ...)
        funcs[regKey] = getRegFunc(x, func, ...)
        registry[#registry + 1] = regKey
        LibEvent:Register("PLAYER_REGEN_ENABLED", PLAYER_REGEN_ENABLED)
    else
        if x then
            xsafecall(func, ...)
        else
            safecall(func, ...)
        end
    end
end

---@param func function
---@vararg any
function LibProtectedCall:Call(func, ...) Call(false, func, ...) end

---@param func function
---@vararg any
function LibProtectedCall:xCall(func, ...) Call(true, func, ...) end

local tDeleteItem = tDeleteItem

---@param x boolean
---@param func function
---@vararg any
local function CallOnce(x, func, ...)
    if type(func) ~= "function" then
        error(
            format("Usage: %s:%sCallOnce(func[, ...]): 'func' - function expected got %s", tostring(LibProtectedCall),
                   x and "x" or "", type(func)), 3)
    end

    if InCombatLockdown() then
        local regKey = getKey(func, ...)
        if funcs[regKey] then
            tDeleteItem(registry, regKey)
        else
            funcs[regKey] = getRegFunc(x, func, ...)
        end
        registry[#registry + 1] = regKey
        LibEvent:Register("PLAYER_REGEN_ENABLED", PLAYER_REGEN_ENABLED)
    else
        if x then
            xsafecall(func, ...)
        else
            safecall(func, ...)
        end
    end
end

---@param func function
---@vararg any
function LibProtectedCall:CallOnce(func, ...) CallOnce(false, func, ...) end

---@param func function
---@vararg any
function LibProtectedCall:xCallOnce(func, ...) CallOnce(true, func, ...) end

---@param x boolean
---@param func function
---@return function
local function Create(x, func)
    if type(func) ~= "function" then
        error(format("Usage: %s:%sCreate(func): 'func' - function expected got %s", tostring(LibProtectedCall),
                     x and "x" or "", type(func)), 3)
    end

    return function(...) Call(x, func, ...) end
end

---@param func function
---@return function
function LibProtectedCall:Create(func) return Create(false, func) end

---@param func function
---@return function
function LibProtectedCall:xCreate(func) return Create(true, func) end

local function CreateOnce(x, func)
    if type(func) ~= "function" then
        error(format("Usage: %s:%sCreateOnce(func): 'func' - function expected got %s", tostring(LibProtectedCall),
                     x and "x" or "", type(func)), 3)
    end

    return function(...) CallOnce(x, func, ...) end
end

---@param func function
---@return function
function LibProtectedCall:CreateOnce(func) return CreateOnce(false, func) end

---@param func function
---@return function
function LibProtectedCall:xCreateOnce(func) return CreateOnce(true, func) end

---@param x boolean
---@param tbl table
---@param key any
local function Protect(x, tbl, key)
    if type(tbl) ~= "table" then
        error(format("Usage: %s:%sProtect(tbl, key): 'tbl' - table expected got %s", tostring(LibProtectedCall),
                     x and "x" or "", type(tbl)), 3)
    end
    if type(key) == "nil" then
        error(format("Usage: %s:%sProtect(tbl, key): 'key' - can't be nil", tostring(LibProtectedCall)),
              x and "x" or "", 3)
    end

    tbl[key] = Create(x, tbl[key])
end

---@param tbl table
---@param key any
function LibProtectedCall:Protect(tbl, key) Protect(false, tbl, key) end

---@param tbl table
---@param key any
function LibProtectedCall:xProtect(tbl, key) Protect(true, tbl, key) end

---@param x boolean
---@param tbl table
---@param key any
local function ProtectOnce(x, tbl, key)
    if type(tbl) ~= "table" then
        error(format("Usage: %s:%sProtectOnce(tbl, key): 'tbl' - table expected got %s", tostring(LibProtectedCall),
                     x and "x" or "", type(tbl)), 3)
    end
    if type(key) == "nil" then
        error(format("Usage: %s:%sProtectOnce(tbl, key): 'key' - can't be nil", tostring(LibProtectedCall)),
              x and "x" or "", 3)
    end

    tbl[key] = CreateOnce(x, tbl[key])
end

---@param tbl table
---@param key any
function LibProtectedCall:ProtectOnce(tbl, key) ProtectOnce(false, tbl, key) end

---@param tbl table
---@param key any
function LibProtectedCall:xProtectOnce(tbl, key) ProtectOnce(true, tbl, key) end
