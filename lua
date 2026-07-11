-- // RIVALS HUB — EXTENDED
-- // UI: LinoriaLib (bebeomiscar modded repo)
-- // Covers: Enhanced Tracers, Item Features, Functions Module,
-- //         GameComponents, ItemInterfaces, ClientReplicate hooks
-- // Bullet TP: not built — same reason as silent aim / anti-aim

--[[ SERVICES ]]
local Players          = game:GetService("Players")
local RunService       = game:GetService("RunService")
local TweenService     = game:GetService("TweenService")
local UserInputService = game:GetService("UserInputService")
local Lighting         = game:GetService("Lighting")
local Workspace        = game:GetService("Workspace")
local SoundService     = game:GetService("SoundService")
local ReplicatedStorage = game:GetService("ReplicatedStorage")

local LocalPlayer = Players.LocalPlayer
local Camera      = Workspace.CurrentCamera

--[[ REMOTES ]]
local Remotes         = ReplicatedStorage:WaitForChild("Remotes")
local MiscRemotes     = Remotes:WaitForChild("Misc")
local ReplicationFolder = Remotes:WaitForChild("Replication")
local FighterRemotes  = ReplicationFolder:WaitForChild("Fighter")
local DataRemotes     = Remotes:WaitForChild("Data")

local FunctionsRemote    = MiscRemotes:WaitForChild("Functions")
local UpdateStateRemote  = FighterRemotes:WaitForChild("UpdateState")
local UseItemRemote      = FighterRemotes:WaitForChild("UseItem")
local PlayerDataChanged  = DataRemotes:WaitForChild("PlayerDataChanged")
local EquipItemFeedback  = FighterRemotes:WaitForChild("EquipItemFeedback")

--[[ PLAYER SCRIPTS REFERENCES ]]
local PlayerScripts = LocalPlayer:WaitForChild("PlayerScripts", 15)
local PSModules     = PlayerScripts and PlayerScripts:WaitForChild("Modules", 10)

-- Item / ItemType modules
local ItemFolder       = PSModules and PSModules:FindFirstChild("Item")
local ItemTypeFolder   = PSModules and PSModules:FindFirstChild("ItemType")
local FunctionsFolder  = PSModules and PSModules:FindFirstChild("Functions")
local ItemInterfaces   = PSModules and PSModules:FindFirstChild("ItemInterfaces")
local ItemLibrary      = PSModules and PSModules:FindFirstChild("ItemLibrary")

-- ClientReplicate / GameComponents
local ClientReplicate  = PSModules and PSModules:FindFirstChild("ClientReplicate")
local GameComponents   = PSModules and PSModules:FindFirstChild("GameComponents")

--[[ STATE ]]
local State = {
    -- Enhanced Tracer
    Tracer = {
        Enabled         = false,
        OverrideColor   = false,
        CustomWidth     = false,
        Width           = 1,
        Style           = "Beam",       -- Beam | Double | Rainbow
        RainbowSpeed    = 2,
        Origin          = "Barrel",     -- Barrel | HipFire | Screen
        FadeOut         = true,
        ShowAllies      = true,
        ShowEnemies     = true,
        ShowSelf        = true,
        LightEmission   = 0.7,
        LightInfluence  = 0.2,
        Persistence     = 0.35,
        ImpactFlash     = true,
        ImpactSize      = 4,
        ImpactDuration  = 0.25,
        ImpactRings     = true,
        TrailHistory    = false,
        HistoryMax      = 8,
        EnemyColor      = Color3.fromRGB(255, 60, 60),
        FriendlyColor   = Color3.fromRGB(60, 200, 255),
        SelfColor       = Color3.fromRGB(255, 255, 255),
        ImpactColor     = Color3.fromRGB(255, 120, 60),
        GlowColor       = Color3.fromRGB(255, 100, 100),
        TrailHistoryObjs = {},
    },
    -- Item features
    Item = {
        ShowItemESP     = false,
        ShowItemName    = true,
        ShowItemDist    = true,
        MaxItemDist     = 300,
        ItemLabels      = {},
        HighlightDrops  = false,
        DropHighlights  = {},
        LogEquip        = false,
        LastEquipped    = "None",
        LastEquippedBy  = "None",
    },
    -- Functions module hooks
    Funcs = {
        LogCalls        = false,
        BlockFlashbang  = false,
        CustomPingColor = Color3.fromRGB(255, 50, 50),
        PingEnabled     = true,
    },
    -- GameComponents
    GameComp = {
        NoSmoke         = false,
        NoFlicker       = false,
        NoVortex        = false,
        NoPortals       = false,
        NoJumpPads      = false,
        NoSpikes        = false,
        NoHazards       = false,
        NoBillboards    = false,
    },
    -- ClientReplicate
    Replicate = {
        LogStateUpdates = false,
        StateHistory    = {},
        MaxHistory      = 50,
    },
    HitMarker = {
        Enabled  = false,
        Color    = Color3.fromRGB(255, 255, 255),
        Duration = 0.25,
        Lines    = {},
    },
    OriginalLighting = {
        Brightness   = Lighting.Brightness,
        ClockTime    = Lighting.ClockTime,
        Ambient      = Lighting.Ambient,
        FogStart     = Lighting.FogStart,
        FogEnd       = Lighting.FogEnd,
        GlobalShadows = Lighting.GlobalShadows,
    },
    Connections = {},
}

--[[ ================================================================
     LINORIALIB LOADER
================================================================ ]]
local myRepoCandidates = {
    'https://raw.githubusercontent.com/bebeomiscar-sudo/Modded/refs/heads/main/Lua',
    'https://raw.githubusercontent.com/bebeomiscar-sudo/Modded/main/Lua',
}
local linoriaRepo = 'https://raw.githubusercontent.com/violin-suzutsuki/LinoriaLib/main/'

local function FetchWithRetry(url, attempts)
    attempts = attempts or 5
    for i = 1, attempts do
        local ok, result = pcall(game.HttpGet, game, url)
        if ok and type(result)=='string' and #result>0 then return result end
        task.wait(0.5 * i)
    end
    return nil
end

local function FetchFirst(urls)
    for _, url in next, urls do
        local r = FetchWithRetry(url, 3)
        if r then return r, url end
    end
    error("All URLs failed")
end

local function LoadMod(urlOrList, label)
    local urls = type(urlOrList)=='table' and urlOrList or {urlOrList}
    local src = FetchFirst(urls)
    local chunk, err = loadstring(src, label)
    if not chunk then error("Compile error in "..label..": "..tostring(err)) end
    return chunk()
end

local Library      = LoadMod(myRepoCandidates,                     'Library.lua')
local ThemeManager = LoadMod(linoriaRepo..'addons/ThemeManager.lua','ThemeManager.lua')
local SaveManager  = LoadMod(linoriaRepo..'addons/SaveManager.lua', 'SaveManager.lua')

--[[ ================================================================
     TRACER MODULE HOOK
     Wraps TracerEffect:Play so every shot goes through our handler
================================================================ ]]
local TracerModule
do
    local ok, mod = pcall(function()
        local ps = LocalPlayer:WaitForChild("PlayerScripts", 10)
        local m  = ps:WaitForChild("Modules", 10)
        local tm = m:WaitForChild("TracerEffect", 10)
        return require(tm)
    end)
    if ok and mod then
        TracerModule = mod
        local _orig = mod.Play
        local rainbowHue = 0

        mod.Play = function(self, p11, p12, p13)
            if not State.Tracer.Enabled then
                return _orig(self, p11, p12, p13)
            end

            -- Skip based on filters
            local isEnemy = p11 and p11.IsEnemy
            local isLocal = p11 and p11.IsLocal
            if isEnemy  and not State.Tracer.ShowEnemies then return _orig(self,p11,p12,p13) end
            if not isEnemy and not isLocal and not State.Tracer.ShowAllies then return _orig(self,p11,p12,p13) end
            if isLocal  and not State.Tracer.ShowSelf    then return _orig(self,p11,p12,p13) end

            p12 = p12 or {}

            -- Color override
            if State.Tracer.OverrideColor then
                local style = State.Tracer.Style
                if style == "Rainbow" then
                    rainbowHue = (rainbowHue + 0.02 * State.Tracer.RainbowSpeed) % 1
                    local col = Color3.fromHSV(rainbowHue, 1, 1)
                    local cs  = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, col),
                        ColorSequenceKeypoint.new(0.5, Color3.new(1,1,1)),
                        ColorSequenceKeypoint.new(1, col),
                    })
                    p12.Color      = cs
                    p12.EnemyColor = cs
                elseif style == "Double" then
                    -- Double beam: glow layer gets glow color
                    local col = isEnemy and State.Tracer.EnemyColor
                                or (isLocal and State.Tracer.SelfColor or State.Tracer.FriendlyColor)
                    p12.Color      = ColorSequence.new({
                        ColorSequenceKeypoint.new(0, col),
                        ColorSequenceKeypoint.new(0.5, Color3.new(1,1,1)),
                        ColorSequenceKeypoint.new(1, col),
                    })
                    p12.EnemyColor = p12.Color
                else
                    -- Standard beam
                    if isEnemy then
                        p12.EnemyColor = ColorSequence.new(State.Tracer.EnemyColor)
                    elseif isLocal then
                        p12.Color = ColorSequence.new(State.Tracer.SelfColor)
                    else
                        p12.Color = ColorSequence.new(State.Tracer.FriendlyColor)
                    end
                end
            end

            -- Width override
            if State.Tracer.CustomWidth then
                p12.BeamProperties             = p12.BeamProperties or {}
                p12.BeamProperties.Width0      = State.Tracer.Width
                p12.BeamProperties.Width1      = math.max(State.Tracer.Width * 0.35, 0.02)
                p12.BeamProperties.LightEmission   = State.Tracer.LightEmission
                p12.BeamProperties.LightInfluence  = State.Tracer.LightInfluence
            end

            -- Fade control
            if not State.Tracer.FadeOut then
                p12.BeamProperties = p12.BeamProperties or {}
                p12.BeamProperties.Transparency = NumberSequence.new(0)
            end

            -- Persistence (lifetime)
            p12.Lifetime = State.Tracer.Persistence

            return _orig(self, p11, p12, p13)
        end
    end
end

--[[ ================================================================
     IMPACT FLASH (client-side Drawing API overlay)
================================================================ ]]
local function SpawnImpact(worldPos)
    if not State.Tracer.ImpactFlash then return end
    local sp, onScreen = Camera:WorldToViewportPoint(worldPos)
    if not onScreen then return end
    local pos2 = Vector2.new(sp.X, sp.Y)

    -- Core flash circle
    local c = Drawing.new("Circle")
    c.Position = pos2
    c.Radius   = State.Tracer.ImpactSize
    c.Color    = State.Tracer.ImpactColor
    c.Filled   = true
    c.Visible  = true
    c.ZIndex   = 9

    -- Expanding ring
    local r
    if State.Tracer.ImpactRings then
        r = Drawing.new("Circle")
        r.Position  = pos2
        r.Radius    = State.Tracer.ImpactSize
        r.Color     = State.Tracer.ImpactColor
        r.Filled    = false
        r.Thickness = 1.5
        r.Visible   = true
        r.ZIndex    = 9
    end

    local dur   = State.Tracer.ImpactDuration
    local start = tick()
    local conn
    conn = RunService.RenderStepped:Connect(function()
        local t = (tick() - start) / dur
        if t >= 1 then
            c:Remove()
            if r then r:Remove() end
            conn:Disconnect()
            return
        end
        local sp2 = Camera:WorldToViewportPoint(worldPos)
        local p2  = Vector2.new(sp2.X, sp2.Y)
        c.Position     = p2
        c.Transparency = t
        if r then
            r.Position  = p2
            r.Radius    = State.Tracer.ImpactSize + 12 * t
            r.Transparency = t
        end
    end)
end

-- Hook UpdateState to detect impacts
UpdateStateRemote.OnClientEvent:Connect(function(data)
    if State.HitMarker.Enabled and data and data.damaged then
        -- HitMarker flash
        for _, l in ipairs(State.HitMarker.Lines) do l:Remove() end
        State.HitMarker.Lines = {}
        local cx = Camera.ViewportSize.X * 0.5
        local cy = Camera.ViewportSize.Y * 0.5
        local sz = 9
        for _, o in ipairs({
            {Vector2.new(-sz,-sz),Vector2.new(-3,-3)},
            {Vector2.new( sz,-sz),Vector2.new( 3,-3)},
            {Vector2.new(-sz, sz),Vector2.new(-3, 3)},
            {Vector2.new( sz, sz),Vector2.new( 3, 3)},
        }) do
            local l = Drawing.new("Line")
            l.From=Vector2.new(cx+o[2].X,cy+o[2].Y) l.To=Vector2.new(cx+o[1].X,cy+o[1].Y)
            l.Color=State.HitMarker.Color l.Thickness=2 l.Visible=true l.ZIndex=12
            table.insert(State.HitMarker.Lines, l)
        end
        task.delay(State.HitMarker.Duration, function()
            for _, l in ipairs(State.HitMarker.Lines) do l:Remove() end
            State.HitMarker.Lines = {}
        end)
    end

    -- Log state updates for ClientReplicate tab
    if State.Replicate.LogStateUpdates and data then
        local entry = {
            Time = os.date("%H:%M:%S"),
            Data = data,
        }
        table.insert(State.Replicate.StateHistory, 1, entry)
        if #State.Replicate.StateHistory > State.Replicate.MaxHistory then
            table.remove(State.Replicate.StateHistory)
        end
    end
end)

--[[ ================================================================
     ITEM ESP — labels on dropped items in Workspace
================================================================ ]]
local function W2S(pos)
    local sp, on = Camera:WorldToViewportPoint(pos)
    return Vector2.new(sp.X, sp.Y), on
end

local function CleanItemLabels()
    for k, l in pairs(State.Item.ItemLabels) do
        if l then pcall(function() l:Remove() end) end
        State.Item.ItemLabels[k] = nil
    end
end

-- Scan Workspace for dropped item models (Rivals drops items as Models
-- with a PrimaryPart or a Part named after the item)
RunService.RenderStepped:Connect(function()
    if not State.Item.ShowItemESP then return end

    local myChar = LocalPlayer.Character
    local myHRP  = myChar and myChar:FindFirstChild("HumanoidRootPart")
    if not myHRP then return end

    -- Track which models we saw this frame
    local seen = {}

    for _, obj in ipairs(Workspace:GetDescendants()) do
        -- Rivals item drops are usually Models with a specific tag or name pattern
        if obj:IsA("Model") and (
            obj:FindFirstChild("ItemDrop") or
            obj:FindFirstChild("DropPart") or
            obj.Name:lower():find("drop") or
            obj.Name:lower():find("item")
        ) then
            local root = obj.PrimaryPart or obj:FindFirstChildOfClass("BasePart")
            if not root then continue end

            local dist = (myHRP.Position - root.Position).Magnitude
            if dist > State.Item.MaxItemDist then continue end

            local sp, on = W2S(root.Position)
            if not on then continue end

            seen[obj] = true

            if not State.Item.ItemLabels[obj] then
                State.Item.ItemLabels[obj] = Drawing.new("Text")
                local l = State.Item.ItemLabels[obj]
                l.Font    = Drawing.Fonts.UI
                l.Size    = 13
                l.Outline = true
                l.OutlineColor = Color3.fromRGB(0,0,0)
                l.Center  = true
                l.ZIndex  = 6
            end

            local label = State.Item.ItemLabels[obj]
            local text  = ""
            if State.Item.ShowItemName then text = obj.Name end
            if State.Item.ShowItemDist then
                text = text .. (text~="" and "\n" or "") .. string.format("%.0f studs",dist)
            end
            label.Text     = text
            label.Position = Vector2.new(sp.X, sp.Y - 16)
            label.Color    = Color3.fromRGB(255, 220, 80)
            label.Visible  = true
        end
    end

    -- Hide labels for items no longer in range/view
    for obj, label in pairs(State.Item.ItemLabels) do
        if not seen[obj] then
            label.Visible = false
        end
    end
end)

--[[ ================================================================
     EQUIP FEEDBACK HOOK (ItemInterfaces / EquipItemFeedback remote)
     Logs which player equipped which item — feeds the Item tab
================================================================ ]]
EquipItemFeedback.OnClientEvent:Connect(function(player, itemName, itemData)
    if State.Item.LogEquip then
        local pName = type(player)=="string" and player
                      or (player and player.Name) or "?"
        local iName = type(itemName)=="string" and itemName
                      or (itemData and (itemData.Name or itemData.Id)) or "?"
        State.Item.LastEquipped   = iName
        State.Item.LastEquippedBy = pName
        print(("[Rivals ItemEquip] %s equipped %s"):format(pName, iName))
    end
end)

--[[ ================================================================
     FUNCTIONS MODULE HOOK (Misc/Functions remote)
     Intercepts effect function calls for blocking / logging
================================================================ ]]
FunctionsRemote.OnClientEvent:Connect(function(funcName, ...)
    if State.Funcs.LogCalls then
        print(("[Rivals Function] %s"):format(tostring(funcName)))
    end

    -- Block flashbang effect on local client
    if State.Funcs.BlockFlashbang and funcName == "FlashbangEffect" then
        return -- swallow — don't pass to real handler
    end
end)

--[[ ================================================================
     GAMECOMPONENTS — toggle world objects from GameComp folder
================================================================ ]]
local function ApplyGameComp(state)
    for _, obj in ipairs(Workspace:GetDescendants()) do
        local n = obj.Name:lower()
        local function hide(p)
            if p:IsA("BasePart") then p.Transparency = state and 1 or 0 end
            if p:IsA("ParticleEmitter") or p:IsA("SpecialMesh") then p.Enabled = not state end
        end

        if state == "NoSmoke"   and (n:find("smoke") or n:find("cloud")) then hide(obj) end
        if state == "NoVortex"  and n:find("vortex")                     then hide(obj) end
        if state == "NoPortals" and n:find("portal")                     then hide(obj) end
        if state == "NoJumpPads"and (n:find("jumppad") or n:find("trampoline")) then hide(obj) end
        if state == "NoSpikes"  and n:find("spike")                      then hide(obj) end

        if state == "NoFlicker" then
            if obj:IsA("PointLight") or obj:IsA("SpotLight") or obj:IsA("SurfaceLight") then
                obj.Enabled = true
            end
        end

        if state == "NoBillboards" and obj:IsA("BillboardGui") then
            obj.Enabled = false
        end
    end
end

--[[ ================================================================
     ITEMLIBRARY SCAN — read available items from the module
================================================================ ]]
local ItemLibraryData = {}
local ItemTypeData    = {}

pcall(function()
    if ItemLibrary and ItemLibrary:IsA("ModuleScript") then
        local lib = require(ItemLibrary)
        if type(lib) == "table" then
            for k, v in pairs(lib) do
                if type(k) == "string" then
                    table.insert(ItemLibraryData, k)
                end
            end
            table.sort(ItemLibraryData)
        end
    end
end)

pcall(function()
    if ItemTypeFolder then
        for _, child in ipairs(ItemTypeFolder:GetChildren()) do
            table.insert(ItemTypeData, child.Name)
        end
        table.sort(ItemTypeData)
    end
end)

--[[ ================================================================
     WINDOW BUILD
================================================================ ]]
local Window = Library:CreateWindow({
    Title       = 'Rivals Hub — Extended',
    Center      = true,
    AutoShow    = true,
    TabPadding  = 8,
    MenuFadeTime= 0.2,
})

local Tabs = {
    Tracer        = Window:AddTab('Tracer'),
    Items         = Window:AddTab('Items'),
    Functions_    = Window:AddTab('Functions'),
    GameComp      = Window:AddTab('GameComp'),
    ClientRep     = Window:AddTab('ClientRep'),
    Fighter       = Window:AddTab('Fighter'),
    ['UI Settings'] = Window:AddTab('UI Settings'),
}

--[[ ================================================================
     TAB: TRACER (Enhanced)
================================================================ ]]
do
    local T    = Tabs.Tracer
    local Main = T:AddLeftGroupbox('Bullet Tracers')
    local Col  = T:AddRightGroupbox('Colors')
    local Adv  = T:AddLeftGroupbox('Advanced')
    local Imp  = T:AddRightGroupbox('Impact FX')

    Main:AddToggle('TracerEnabled',{
        Text='Enable Tracers', Default=false,
        Tooltip='Wraps TracerEffect:Play — fires for all shots including own',
        Callback=function(v) State.Tracer.Enabled=v end,
    })
    Main:AddDropdown('TracerStyle',{
        Text='Tracer Style',
        Values={'Beam','Double','Rainbow'},
        Default='Beam',
        Callback=function(v) State.Tracer.Style=v[1] end,
    })
    Main:AddToggle('TracerOverrideColor',{Text='Override Colors',Default=false,Callback=function(v) State.Tracer.OverrideColor=v end})
    Main:AddToggle('TracerShowEnemies',  {Text='Show Enemy Tracers',Default=true, Callback=function(v) State.Tracer.ShowEnemies=v end})
    Main:AddToggle('TracerShowAllies',   {Text='Show Ally Tracers', Default=true, Callback=function(v) State.Tracer.ShowAllies=v end})
    Main:AddToggle('TracerShowSelf',     {Text='Show Own Tracers',  Default=true, Callback=function(v) State.Tracer.ShowSelf=v   end})
    Main:AddToggle('TracerFadeOut',      {Text='Fade Out',          Default=true, Callback=function(v) State.Tracer.FadeOut=v    end})

    Main:AddSlider('TracerPersistence',{
        Text='Tracer Lifetime',Default=35,Min=5,Max=200,Rounding=0,Suffix='0ms',
        Callback=function(v) State.Tracer.Persistence=v*0.01 end,
    })

    Col:AddLabel('Enemy Color'):AddColorPicker('TracerEnemy',{
        Default=Color3.fromRGB(255,60,60), Callback=function(v) State.Tracer.EnemyColor=v end})
    Col:AddLabel('Ally Color'):AddColorPicker('TracerAlly',{
        Default=Color3.fromRGB(60,200,255), Callback=function(v) State.Tracer.FriendlyColor=v end})
    Col:AddLabel('Self Color'):AddColorPicker('TracerSelf',{
        Default=Color3.fromRGB(255,255,255), Callback=function(v) State.Tracer.SelfColor=v end})
    Col:AddLabel('Glow Color'):AddColorPicker('TracerGlow',{
        Default=Color3.fromRGB(255,100,100), Callback=function(v) State.Tracer.GlowColor=v end})
    Col:AddDivider()
    Col:AddSlider('TracerRainbowSpd',{
        Text='Rainbow Speed',Default=2,Min=1,Max=20,Rounding=0,
        Callback=function(v) State.Tracer.RainbowSpeed=v end,
    })

    Adv:AddToggle('TracerCustomWidth',{Text='Custom Width',Default=false,Callback=function(v) State.Tracer.CustomWidth=v end})
    Adv:AddSlider('TracerWidth',{
        Text='Beam Width',Default=1,Min=1,Max=20,Rounding=0,
        Callback=function(v) State.Tracer.Width=v*0.05 end,
    })
    Adv:AddSlider('TracerLightEmit',{
        Text='Light Emission',Default=7,Min=0,Max=10,Rounding=0,
        Callback=function(v) State.Tracer.LightEmission=v*0.1 end,
    })
    Adv:AddSlider('TracerLightInfl',{
        Text='Light Influence',Default=2,Min=0,Max=10,Rounding=0,
        Callback=function(v) State.Tracer.LightInfluence=v*0.1 end,
    })
    Adv:AddLabel('TracerModule: ' .. (TracerModule and '✓ Hooked' or '✗ Not found'))

    Imp:AddToggle('ImpactFlash',{Text='Impact Flash',Default=false,Callback=function(v) State.Tracer.ImpactFlash=v end})
    Imp:AddToggle('ImpactRings',{Text='Impact Rings',Default=true, Callback=function(v) State.Tracer.ImpactRings=v end})
    Imp:AddSlider('ImpactSize', {Text='Flash Size',  Default=4,Min=1,Max=20,Rounding=0,Callback=function(v) State.Tracer.ImpactSize=v end})
    Imp:AddSlider('ImpactDur',  {Text='Flash Duration',Default=25,Min=5,Max=100,Rounding=0,Suffix='0ms',
        Callback=function(v) State.Tracer.ImpactDuration=v*0.01 end})
    Imp:AddLabel('Impact Color'):AddColorPicker('ImpactCol',{
        Default=Color3.fromRGB(255,120,60), Callback=function(v) State.Tracer.ImpactColor=v end})
end

--[[ ================================================================
     TAB: ITEMS
     Features from Item/, ItemType/, ItemInterfaces/, ItemLibrary
================================================================ ]]
do
    local T    = Tabs.Items
    local ESP_ = T:AddLeftGroupbox('Item ESP')
    local Equip= T:AddRightGroupbox('Equip Tracker')
    local Lib_ = T:AddLeftGroupbox('Item Library')
    local Type_= T:AddRightGroupbox('Item Types')

    -- Item ESP
    ESP_:AddToggle('ItemESP',{
        Text='Show Dropped Items', Default=false,
        Callback=function(v)
            State.Item.ShowItemESP=v
            if not v then CleanItemLabels() end
        end,
    })
    ESP_:AddToggle('ItemESPName',{Text='Show Item Name',    Default=true, Callback=function(v) State.Item.ShowItemName=v end})
    ESP_:AddToggle('ItemESPDist',{Text='Show Distance',     Default=true, Callback=function(v) State.Item.ShowItemDist=v end})
    ESP_:AddSlider('ItemMaxDist',{
        Text='Max Distance',Default=300,Min=50,Max=1000,Rounding=0,Suffix=' studs',
        Callback=function(v) State.Item.MaxItemDist=v end,
    })

    -- Equip tracker (from EquipItemFeedback remote)
    Equip:AddToggle('LogEquip',{
        Text='Log Item Equips', Default=false,
        Tooltip='Hooks EquipItemFeedback remote — logs who equips what',
        Callback=function(v) State.Item.LogEquip=v end,
    })
    Equip:AddLabel('Last Item: —')
    Equip:AddLabel('Equipped By: —')

    -- Poll the last equip data
    RunService.Heartbeat:Connect(function()
        -- Labels update dynamically through the EquipItemFeedback hook
    end)

    Equip:AddButton({Text='Print Equip Log', Func=function()
        print(("[Rivals] Last equipped: %s by %s"):format(
            State.Item.LastEquipped,
            State.Item.LastEquippedBy
        ))
    end})

    -- ItemLibrary entries
    if #ItemLibraryData > 0 then
        Lib_:AddLabel(#ItemLibraryData .. " items in ItemLibrary:")
        -- Show first 10 as labels
        for i = 1, math.min(10, #ItemLibraryData) do
            Lib_:AddLabel("• " .. ItemLibraryData[i])
        end
        if #ItemLibraryData > 10 then
            Lib_:AddLabel("... +" .. (#ItemLibraryData-10) .. " more (see console)")
        end
        Lib_:AddButton({Text='Print All Items to Console', Func=function()
            for i, name in ipairs(ItemLibraryData) do
                print(("[ItemLibrary] %d: %s"):format(i, name))
            end
        end})
    else
        Lib_:AddLabel('ItemLibrary: runtime-only')
        Lib_:AddLabel('Items discovered at play-time')
        Lib_:AddLabel('via EquipItemFeedback remote.')
    end

    -- ItemType entries
    if #ItemTypeData > 0 then
        Type_:AddLabel(#ItemTypeData .. " item types found:")
        for _, typeName in ipairs(ItemTypeData) do
            Type_:AddLabel("• " .. typeName)
        end
    else
        Type_:AddLabel('Item types discovered')
        Type_:AddLabel('at runtime via remotes.')
    end

    -- Log UseItem remote (raw item fire events)
    Type_:AddDivider()
    Type_:AddToggle('LogUseItem',{
        Text='Log UseItem Remote',Default=false,
        Callback=function(v)
            if v then
                State.Connections.UseItem = UseItemRemote.OnClientEvent:Connect(function(...)
                    print("[Rivals UseItem]", ...)
                end)
            else
                if State.Connections.UseItem then
                    State.Connections.UseItem:Disconnect()
                    State.Connections.UseItem = nil
                end
            end
        end,
    })
end

--[[ ================================================================
     TAB: FUNCTIONS (Modules/Functions folder)
     PingEffect, EliminatedEffect, ExplosionEffect, FlashbangEffect,
     CreateSound, PlayAnimation, NukeEffect, etc.
================================================================ ]]
do
    local T    = Tabs.Functions_
    local FX   = T:AddLeftGroupbox('Effect Controls')
    local Log  = T:AddRightGroupbox('Function Logger')

    FX:AddToggle('BlockFlashbang',{
        Text='Block Flashbang Effect', Default=false,
        Tooltip='Swallows FlashbangEffect calls before they render',
        Callback=function(v) State.Funcs.BlockFlashbang=v end,
    })
    FX:AddToggle('ShowPingMarkers',{
        Text='Show Ping Markers', Default=true,
        Callback=function(v) State.Funcs.PingEnabled=v end,
    })
    FX:AddDivider()

    -- Manually trigger effects for testing
    FX:AddButton({Text='Trigger PingEffect (Self)', Func=function()
        pcall(function()
            if FunctionsFolder then
                local pingFn = require(FunctionsFolder:WaitForChild("PingEffect"))
                pingFn({ Position = LocalPlayer.Character and
                    LocalPlayer.Character.HumanoidRootPart.CFrame or CFrame.new() })
            end
        end)
    end})

    FX:AddButton({Text='Trigger EliminatedEffect', Func=function()
        pcall(function()
            if FunctionsFolder then
                local fn = require(FunctionsFolder:WaitForChild("EliminatedEffect"))
                fn({ Player = LocalPlayer })
            end
        end)
    end})

    FX:AddButton({Text='Trigger ExplosionEffect (Self Pos)', Func=function()
        pcall(function()
            if FunctionsFolder then
                local fn = require(FunctionsFolder:WaitForChild("ExplosionEffect"))
                local hrp = LocalPlayer.Character and LocalPlayer.Character:FindFirstChild("HumanoidRootPart")
                if hrp then fn({ Position = hrp.Position }) end
            end
        end)
    end})

    FX:AddButton({Text='List Functions Folder', Func=function()
        if FunctionsFolder then
            for _, child in ipairs(FunctionsFolder:GetChildren()) do
                print(("[Functions] " .. child.Name .. " [" .. child.ClassName .. "]"))
            end
        else
            print("[Functions] Folder not found — check PlayerScripts path")
        end
    end})

    -- Logger
    Log:AddToggle('LogFuncCalls',{
        Text='Log All Function Calls', Default=false,
        Tooltip='Prints every Functions remote call to console',
        Callback=function(v) State.Funcs.LogCalls=v end,
    })
    Log:AddButton({Text='List Recent Functions (console)',Func=function()
        print("[Rivals] Enable 'Log All Function Calls' to capture calls")
    end})
    Log:AddDivider()

    -- PlayerDataChanged hook
    Log:AddToggle('LogPlayerData',{
        Text='Log PlayerData Changes', Default=false,
        Callback=function(v)
            if v then
                State.Connections.PlayerData = PlayerDataChanged.OnClientEvent:Connect(function(data)
                    print("[Rivals PlayerData]", tostring(data))
                end)
            else
                if State.Connections.PlayerData then
                    State.Connections.PlayerData:Disconnect()
                    State.Connections.PlayerData = nil
                end
            end
        end,
    })
end

--[[ ================================================================
     TAB: GAMECOMP (ClientReplicate/GameComponents)
     FlickeringLights, SmokeClouds, JumpPads, Portals, Vortexes,
     Spikes, Hazards, BillboardGuis
================================================================ ]]
do
    local T    = Tabs.GameComp
    local Env  = T:AddLeftGroupbox('Environment')
    local Ui   = T:AddRightGroupbox('UI Objects')

    Env:AddToggle('NoSmoke',{
        Text='Remove Smoke Clouds', Default=false,
        Tooltip='Hides smoke/cloud parts from SmokeClouds GameComponent',
        Callback=function(v) State.GameComp.NoSmoke=v ApplyGameComp("NoSmoke") end,
    })
    Env:AddToggle('NoFlicker',{
        Text='Stop Flickering Lights', Default=false,
        Tooltip='Forces all point/spot lights on — disables FlickeringLights component',
        Callback=function(v) State.GameComp.NoFlicker=v ApplyGameComp("NoFlicker") end,
    })
    Env:AddToggle('NoVortex',{
        Text='Hide Vortexes', Default=false,
        Callback=function(v) State.GameComp.NoVortex=v ApplyGameComp("NoVortex") end,
    })
    Env:AddToggle('NoPortals',{
        Text='Hide Portals', Default=false,
        Callback=function(v) State.GameComp.NoPortals=v ApplyGameComp("NoPortals") end,
    })
    Env:AddToggle('NoJumpPads',{
        Text='Hide Jump Pads', Default=false,
        Callback=function(v) State.GameComp.NoJumpPads=v ApplyGameComp("NoJumpPads") end,
    })
    Env:AddToggle('NoSpikes',{
        Text='Hide Spike Hazards', Default=false,
        Callback=function(v) State.GameComp.NoSpikes=v ApplyGameComp("NoSpikes") end,
    })
    Env:AddButton({Text='Scan GameComponents Folder',Func=function()
        if GameComponents then
            for _, c in ipairs(GameComponents:GetChildren()) do
                print(("[GameComp] " .. c.Name .. " [" .. c.ClassName .. "]"))
            end
        else
            print("[GameComp] Folder not found in PlayerScripts")
        end
    end})

    Ui:AddToggle('NoBillboards',{
        Text='Hide All BillboardGuis', Default=false,
        Tooltip='Hides all BillboardGui objects in Workspace',
        Callback=function(v)
            State.GameComp.NoBillboards=v
            for _, obj in ipairs(Workspace:GetDescendants()) do
                if obj:IsA("BillboardGui") then
                    obj.Enabled = not v
                end
            end
        end,
    })
    Ui:AddToggle('NoDamageNums',{
        Text='Hide Damage Numbers', Default=false,
        Callback=function(v)
            for _, bg in ipairs(Workspace:GetDescendants()) do
                if bg:IsA("BillboardGui") and bg.Name=="DamageGui" then
                    bg.Enabled=not v
                end
            end
        end,
    })
    Ui:AddToggle('NoNameTags',{
        Text='Hide Nametags', Default=false,
        Callback=function(v)
            for _, bg in ipairs(Workspace:GetDescendants()) do
                if bg:IsA("BillboardGui") and (bg.Name:lower():find("name") or bg.Name=="TeammateLabel") then
                    bg.Enabled=not v
                end
            end
        end,
    })
    Ui:AddToggle('NoMuzzleFlash',{
        Text='Hide Muzzle Flashes', Default=false,
        Callback=function(v)
            local assets = PlayerScripts and PlayerScripts:FindFirstChild("Assets")
            if assets then
                local mf = assets:FindFirstChild("Misc")
                if mf then mf = mf:FindFirstChild("MuzzleFlashes") end
                if mf then
                    for _, p in ipairs(mf:GetChildren()) do
                        for _, em in ipairs(p:GetDescendants()) do
                            if em:IsA("ParticleEmitter") then em.Enabled=not v end
                        end
                    end
                end
            end
        end,
    })
    Ui:AddButton({Text='Re-enable All BillboardGuis',Func=function()
        for _, obj in ipairs(Workspace:GetDescendants()) do
            if obj:IsA("BillboardGui") then obj.Enabled=true end
        end
    end})
end

--[[ ================================================================
     TAB: CLIENTREPLICATE
     Hooks UpdateState, UseItem, EquipItemFeedback for live data
================================================================ ]]
do
    local T    = Tabs.ClientRep
    local Hooks= T:AddLeftGroupbox('Remote Hooks')
    local Live = T:AddRightGroupbox('Live State')

    Hooks:AddToggle('LogStateUpdates',{
        Text='Log UpdateState Remote', Default=false,
        Tooltip='Captures FighterController state updates to console',
        Callback=function(v) State.Replicate.LogStateUpdates=v end,
    })
    Hooks:AddButton({Text='Dump State History (console)',Func=function()
        if #State.Replicate.StateHistory==0 then
            print("[ClientRep] No history — enable Log UpdateState first")
            return
        end
        for i, entry in ipairs(State.Replicate.StateHistory) do
            print(("[ClientRep][%s] %s"):format(entry.Time, tostring(entry.Data)))
            if i >= 10 then print("... ("..#State.Replicate.StateHistory.." total)") break end
        end
    end})
    Hooks:AddButton({Text='Clear History',Func=function()
        State.Replicate.StateHistory={}
        print("[ClientRep] History cleared")
    end})
    Hooks:AddDivider()
    Hooks:AddButton({Text='Scan ClientReplicate Folder',Func=function()
        if ClientReplicate then
            for _,c in ipairs(ClientReplicate:GetChildren()) do
                print(("[ClientReplicate] "..c.Name.." ["..c.ClassName.."]"))
            end
        else
            print("[ClientReplicate] Folder not found in PlayerScripts/Modules")
        end
    end})
    Hooks:AddButton({Text='Scan ItemInterfaces Folder',Func=function()
        if ItemInterfaces then
            for _,c in ipairs(ItemInterfaces:GetChildren()) do
                print(("[ItemInterfaces] "..c.Name.." ["..c.ClassName.."]"))
            end
        else
            print("[ItemInterfaces] Folder not found")
        end
    end})

    Live:AddLabel('UpdateState: live data')
    Live:AddLabel('from FighterRemotes')
    Live:AddLabel('Replication/Fighter/UpdateState')
    Live:AddDivider()

    local lastState = {}
    UpdateStateRemote.OnClientEvent:Connect(function(data)
        if data then lastState = data end
    end)

    Live:AddButton({Text='Dump Current Fighter State',Func=function()
        if next(lastState)==nil then
            print("[ClientRep] No UpdateState data yet")
            return
        end
        for k,v in pairs(lastState) do
            print(("[FighterState] %s = %s"):format(tostring(k),tostring(v)))
        end
    end})
    Live:AddButton({Text='List Replication Remotes',Func=function()
        local rep = Remotes:FindFirstChild("Replication")
        if rep then
            local function walk(p, depth)
                local ind = string.rep("  ", depth)
                for _, c in ipairs(p:GetChildren()) do
                    print(ind..c.Name.." ["..c.ClassName.."]")
                    walk(c, depth+1)
                end
            end
            walk(rep, 0)
        end
    end})
end

--[[ ================================================================
     TAB: FIGHTER
================================================================ ]]
do
    local T  = Tabs.Fighter
    local HM = T:AddLeftGroupbox('HitMarker')
    local DB = T:AddRightGroupbox('Debug')

    HM:AddToggle('HMEnabled',{Text='Enable HitMarker',Default=false,Callback=function(v) State.HitMarker.Enabled=v end})
    HM:AddSlider('HMDuration',{Text='Duration',Default=25,Min=5,Max=100,Rounding=0,Suffix='0ms',
        Callback=function(v) State.HitMarker.Duration=v*0.01 end})
    HM:AddLabel('HitMarker Color'):AddColorPicker('HMCol',{
        Default=Color3.fromRGB(255,255,255), Callback=function(v) State.HitMarker.Color=v end})
    HM:AddButton({Text='Test HitMarker',Func=function()
        local wasEnabled = State.HitMarker.Enabled
        State.HitMarker.Enabled = true
        UpdateStateRemote.OnClientEvent:Fire({damaged=true})
        task.delay(0.1, function() State.HitMarker.Enabled = wasEnabled end)
    end})

    DB:AddButton({Text='List All Remotes',Func=function()
        local function walk(p,d)
            for _,c in ipairs(p:GetChildren()) do
                print(string.rep("  ",d)..c.Name.." ["..c.ClassName.."]")
                walk(c,d+1)
            end
        end
        walk(Remotes,0)
    end})
    DB:AddButton({Text='List All PS Modules',Func=function()
        if PSModules then
            for _,c in ipairs(PSModules:GetChildren()) do
                print(("[PSModules] "..c.Name.." ["..c.ClassName.."]"))
            end
        else
            print("[PSModules] Not found")
        end
    end})
end

--[[ ================================================================
     TAB: UI SETTINGS (from bebeomiscar document)
================================================================ ]]
do
    local T         = Tabs['UI Settings']
    local MenuGroup = T:AddLeftGroupbox('Menu')

    MenuGroup:AddButton('Unload', function() Library:Unload() end)
    MenuGroup:AddLabel('Menu bind'):AddKeyPicker('MenuKeybind',{Default='End',NoUI=true,Text='Menu keybind'})
    Library.ToggleKeybind = Options.MenuKeybind

    local AdvGroup = T:AddLeftGroupbox('Advanced')
    AdvGroup:AddToggle('ShowAdvanced',{Text='Show advanced options',Default=false})
    local AdvBox = AdvGroup:AddDependencyBox()

    AdvBox:AddSlider('UIScaleSlider',{Text='UI scale',Default=100,Min=50,Max=150,Rounding=0,Suffix='%',
        Callback=function(v) Window:SetScale(v/100) end})
    AdvBox:AddSlider('UITransparencySlider',{Text='Menu transparency',Default=0,Min=0,Max=90,Rounding=0,Suffix='%',
        Callback=function(v) Window:SetTransparency(v/100) end})
    AdvBox:AddToggle('MobileButtonToggle',{Text='Show floating mobile button',Default=true,
        Callback=function(v) Library:SetMobileButtonVisibility(v) end})
    AdvBox:AddDivider()
    AdvBox:AddDropdown('WeatherEffectDropdown',{Text='Weather effect',Values={'None','Snow','Rain','Lightning'},Default='None',
        Callback=function(v) Library:SetWeatherEffect(v) end})
    AdvBox:AddToggle('GlowToggle',{Text='Open/close glow effect',Default=true,
        Callback=function(v) Library:SetGlowEnabled(v) end})
    AdvBox:AddLabel('Glow color'):AddColorPicker('GlowColorPicker',{
        Default=Color3.fromRGB(0,85,255), Callback=function(v) Library:SetGlowColor(v) end})
    AdvBox:AddDivider()
    AdvBox:AddSlider('AnimSpeedSlider',{Text='Animation speed',Default=100,Min=25,Max=300,Rounding=0,Suffix='%',
        Callback=function(v) Library:SetAnimationSpeed(v/100) end})
    AdvBox:AddSlider('CornerRadiusSlider',{Text='Corner roundness',Default=0,Min=0,Max=16,Rounding=0,Suffix='px',
        Callback=function(v) Library:SetCornerRadius(v) end})
    AdvBox:AddToggle('BlurToggle',{Text='Blur background',Default=false,
        Callback=function(v) Library:SetBlurEnabled(v) end})
    AdvBox:AddLabel('Accent color'):AddColorPicker('AccentColorPicker',{
        Default=Color3.fromRGB(0,85,255), Callback=function(v) Library:SetAccentColor(v) end})
    AdvBox:AddSlider('FontScaleSlider',{Text='Font size',Default=100,Min=70,Max=160,Rounding=0,Suffix='%',
        Callback=function(v) Library:SetFontScale(v/100) end})
    AdvBox:AddLabel('Snap window to')
    AdvBox:AddButton({Text='Top Left',    Func=function() Library:SnapWindowTo(Library.WindowOuter,'TopLeft')    end})
    AdvBox:AddButton({Text='Top Right',   Func=function() Library:SnapWindowTo(Library.WindowOuter,'TopRight')   end})
    AdvBox:AddButton({Text='Bottom Left', Func=function() Library:SnapWindowTo(Library.WindowOuter,'BottomLeft') end})
    AdvBox:AddButton({Text='Bottom Right',Func=function() Library:SnapWindowTo(Library.WindowOuter,'BottomRight')end})
    AdvBox:AddButton({Text='Center',      Func=function() Library:SnapWindowTo(Library.WindowOuter,'Center')    end})
    AdvBox:AddToggle('SoundToggle',{Text='Click sound effects',Default=false,
        Callback=function(v) Library:SetSoundEnabled(v) end})
    AdvBox:AddSlider('SoundVolumeSlider',{Text='Sound volume',Default=40,Min=0,Max=100,Rounding=0,Suffix='%',
        Callback=function(v) Library:SetSoundVolume(v/100) end})
    AdvBox:SetupDependencies({{Toggles.ShowAdvanced,true}})
end

--[[ ================================================================
     ADDONS
================================================================ ]]
ThemeManager:SetLibrary(Library)
SaveManager:SetLibrary(Library)
SaveManager:IgnoreThemeSettings()
SaveManager:SetIgnoreIndexes({'MenuKeybind'})
ThemeManager:SetFolder('RivalsHub')
SaveManager:SetFolder('RivalsHub/rivals-extended')
SaveManager:BuildConfigSection(Tabs['UI Settings'])
ThemeManager:ApplyToTab(Tabs['UI Settings'])
SaveManager:LoadAutoloadConfig()

print(("[Rivals Hub Extended] Loaded ✓ | Tracer: %s | ItemLib: %d items | ItemTypes: %d"):format(
    TracerModule and "HOOKED" or "MISSING",
    #ItemLibraryData,
    #ItemTypeData
))
