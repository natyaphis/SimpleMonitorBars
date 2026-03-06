
local _, ns = ...

ns.defaults = {
    monitorBars = {
        locked = false,
        nextID = 1,
        bars = {},
    },

    minimap = {
        hide = false,
    },
}

local function DeepCopy(src)
    if type(src) ~= "table" then return src end
    local t = {}
    for k, v in pairs(src) do
        t[k] = DeepCopy(v)
    end
    return t
end

ns.DeepCopy = DeepCopy
