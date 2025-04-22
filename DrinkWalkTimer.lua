local addonName = ...
local f = CreateFrame("Frame")
local lastTick = GetTime()
local tickInterval = 2
local comboCount = 0 
local lastComboTickTime = 0

local lastPassiveSync = 0        
local PASSIVE_COOLDOWN = 6       

local sampleWindow = {}          
local SAMPLE_SIZE  = 8           
local MAX_SAMPLE_GAIN = 500      
local prevTickTime = nil          

local lastLabelText = ""
local lastBarColor = ""

local function IsDrinking()
    for i = 1, 40 do
        local name = UnitBuff("player", i)
        if name and name:lower():find("drink") then
            return true
        end
    end
    return false
end

DWT_Settings = DWT_Settings or {}

-- user option: show the bar even when mana is full
if DWT_Settings.showAtFullMana == nil then
    DWT_Settings.showAtFullMana = false   -- default: hide at 100 % mana
end

local tickBar = CreateFrame("StatusBar", "DrinkWalkTimer_Bar", UIParent, "BackdropTemplate")
tickBar:SetSize(200, 12)
tickBar:SetMinMaxValues(0, tickInterval)
tickBar:SetStatusBarTexture("Interface\\TARGETINGFRAME\\UI-StatusBar")
tickBar:SetStatusBarColor(0.6, 0.8, 1.0) 
tickBar:SetMovable(true)
tickBar:EnableMouse(true)
tickBar:RegisterForDrag("LeftButton")
tickBar:SetScript("OnDragStart", tickBar.StartMoving)
tickBar:SetScript("OnDragStop", function(self)
    self:StopMovingOrSizing()
    local point, _, _, xOfs, yOfs = self:GetPoint()
    DWT_Settings.pos = {point, xOfs, yOfs}
end)    

local bg = tickBar:CreateTexture(nil, "BACKGROUND")
bg:SetAllPoints(true)
bg:SetColorTexture(0.85, 0.85, 0.85, 0.5)

local label = tickBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")
label:SetPoint("CENTER")
label:SetText("2.00")

local comboLabel = tickBar:CreateFontString(nil, "OVERLAY", "GameFontHighlightSmall")  
comboLabel:SetPoint("BOTTOM", tickBar, "TOP", 0, 4)
comboLabel:SetText("") 

tickBar:SetValue(0)

local marker = tickBar:CreateTexture(nil, "OVERLAY")
marker:SetColorTexture(1.0, 0.8, 0.4, 0.8)  
marker:SetWidth(2)
marker:SetHeight(tickBar:GetHeight())
marker:SetPoint("LEFT", tickBar, "LEFT", 150, 0)  

tickBar:HookScript("OnSizeChanged", function(self, width)
    marker:ClearAllPoints()
    marker:SetPoint("LEFT", self, "LEFT", width * 0.75, 0)
end)
tickBar:Hide()

local comboPulse = comboLabel:CreateAnimationGroup()
local pulse = comboPulse:CreateAnimation("Scale")
pulse:SetScale(1.5, 1.5)
pulse:SetDuration(0.1)
pulse:SetOrder(1)

local shrink = comboPulse:CreateAnimation("Scale")
shrink:SetScale(0.67, 0.67)
shrink:SetDuration(0.1)
shrink:SetOrder(2)

local normalize = comboPulse:CreateAnimation("Scale")
normalize:SetScale(1.0, 1.0)
normalize:SetDuration(0.1)
normalize:SetOrder(3)

f:SetScript("OnUpdate", function(_, elapsed)
    local currentMana = UnitPower("player", 0)
    local maxMana = UnitPowerMax("player", 0)
    local inCombat = UnitAffectingCombat("player")
    local isDead = UnitIsDeadOrGhost("player")
    if inCombat or isDead or (currentMana >= maxMana and not DWT_Settings.showAtFullMana) then
        tickBar:Hide()
        return
    end
    tickBar:Show()
    
    local now = GetTime()
    local diff = now - lastTick
    while diff >= tickInterval do
        diff = diff - tickInterval   
    end
    if comboCount > 0 and now - lastComboTickTime > tickInterval + 0.25 then
        comboCount = 0
        comboLabel:SetText("")
    end
    
    tickBar:SetValue(diff)

    local newLabelText = string.format("%.2f", tickInterval - diff)
    if newLabelText ~= lastLabelText then
        label:SetText(newLabelText)
        lastLabelText = newLabelText
    end
    
    local colorCode
    if tickInterval - diff < 0.25 then
        colorCode = "green"
    elseif tickInterval - diff < 0.50 then
        colorCode = "yellow"
    else
        colorCode = "blue"
    end

    if colorCode ~= lastBarColor then
        lastBarColor = colorCode
        if colorCode == "green" then
            tickBar:SetStatusBarColor(0.6, 1.0, 0.6)
        elseif colorCode == "yellow" then
            tickBar:SetStatusBarColor(1.0, 1.0, 0.6)
        else
            tickBar:SetStatusBarColor(0.6, 0.8, 1.0)
        end
    end
end)

f:RegisterEvent("PLAYER_LOGIN")
f:RegisterEvent("UNIT_POWER_UPDATE")
f:RegisterEvent("PLAYER_REGEN_ENABLED")   
f:RegisterEvent("PLAYER_ENTERING_WORLD")   

f:SetScript("OnEvent", function(_, event, arg)
    if event == "PLAYER_LOGIN" then

        if DWT_Settings.pos then
            local point, x, y = unpack(DWT_Settings.pos)
            tickBar:SetPoint(point, UIParent, point, x, y)
        else
            tickBar:SetPoint("CENTER")
        end
        C_Timer.After(0.1, function()
            local width = tickBar:GetWidth()
            marker:SetPoint("LEFT", tickBar, "LEFT", width * 0.75, 0)
        end)
    elseif event == "PLAYER_ENTERING_WORLD" then
        prevTickTime   = nil
        lastPassiveSync = 0
    elseif event == "PLAYER_REGEN_ENABLED" then
        lastPassiveSync = 0
    elseif event == "UNIT_POWER_UPDATE" and arg == "player" then
        local currentMana = UnitPower("player", 0)
        local previousMana = f.lastMana or currentMana
        local drinking = IsDrinking()
        local now = GetTime()
        
        local gap = now - lastTick

        if (not drinking) and currentMana < UnitPowerMax("player", 0) then
            if gap >= tickInterval*0.9 and gap <= tickInterval*1.1 then
                if now - lastPassiveSync > PASSIVE_COOLDOWN then
                    lastTick = now                
                    lastPassiveSync = now
                end
            end
        end

        local delta = 0
        local manaGain = currentMana - previousMana
        if currentMana > previousMana then
            if prevTickTime then
                delta = now - prevTickTime
            end

            if delta > 1.5 and delta < 2.5 and manaGain < MAX_SAMPLE_GAIN and prevTickTime then
                table.insert(sampleWindow, delta)
                if #sampleWindow > SAMPLE_SIZE then
                    table.remove(sampleWindow, 1)
                end
                local sorted = { unpack(sampleWindow) }
                table.sort(sorted)
                local median = sorted[ math.ceil(#sorted / 2) ]
                if math.abs(median - tickInterval) > 0.03 then
                    tickInterval = median
                end
            end

            if delta > 1.5 and delta < 2.5 then
                lastTick = now
            end

            if drinking then
                comboCount = comboCount + 1
                lastComboTickTime = now
                comboLabel:SetText("Combo: " .. comboCount)
                if comboPulse:IsPlaying() then comboPulse:Stop() end
                comboPulse:Play()
            else
                comboCount = 0
                comboLabel:SetText("")
            end

            prevTickTime = now
        end
        f.lastMana = currentMana
    end
end)

---------------------------------------------------------------------------
-- Slash command:  /dwt full   → toggles showing the bar at 100 % mana
---------------------------------------------------------------------------
SLASH_DWT1 = "/dwt"
SlashCmdList["DWT"] = function(msg)
    msg = (msg or ""):lower():match("^%s*(.-)%s*$")
    if msg == "full" or msg == "showfull" then
        DWT_Settings.showAtFullMana = not DWT_Settings.showAtFullMana
        print(addonName .. ": Show bar at full mana is now " ..
              (DWT_Settings.showAtFullMana and "ON" or "OFF"))
    else
        print("DrinkWalkTimer commands:")
        print("  /dwt full   - toggle showing the bar at 100% mana")
    end
end