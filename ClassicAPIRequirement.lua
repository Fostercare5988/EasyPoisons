-- Enforce VanillaForge's shared ClassicAPI support floor. EasyPoisons.lua
-- checks ns.unsupported and stays inert when this guard fails.
local addonName, ns = ...
local minimum = 11600
if type(CLASSIC_API_VERSION) ~= "number" or CLASSIC_API_VERSION < minimum then
    ns.unsupported = true
    local message = addonName .. " requires ClassicAPI 1.16.0 or later. Update ClassicAPI.dll and restart the client."
    if DEFAULT_CHAT_FRAME and type(DEFAULT_CHAT_FRAME.AddMessage) == "function" then
        DEFAULT_CHAT_FRAME:AddMessage("|cffff2020[" .. addonName .. " Fatal Error]|r " .. message, 1, 0.2, 0.2)
    end
    error(message, 0)
end
