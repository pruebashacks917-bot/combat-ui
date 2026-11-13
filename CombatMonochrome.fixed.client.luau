-- VERSION 4.1: body-based player selection, then independent Head/Torso aiming.
-- COMBAT UI: siempre selecciona al jugador mas cercano a la mira dentro del FOV.
-- Target lock ON = apuntado directo; OFF = usa Smoothness.
-- Sticky OFF: holds the current valid target through jitter; deliberate mouse movement permits retargeting.
-- Autoplay/Kill all usan una Tool existente; el dano depende del juego.

local P = game:GetService("Players")
local R = game:GetService("RunService")
local U = game:GetService("UserInputService")
local GuiService = game:GetService("GuiService")
local PF = game:GetService("PathfindingService")
local me = assert(P.LocalPlayer, "Ejecutar en el cliente.")
local pg = me:WaitForChild("PlayerGui")
local old = pg:FindFirstChild("SimpleCombatUI")
if old then old:Destroy() end

local S = {Enabled=false, Aim=false, Lock=false, FOV=200, Smooth=0,
	Part="Head", Center="Crosshair", Mode=nil, Key=Enum.KeyCode.Q, Sticky=false, TeamCheck=false, Skeleton=false, Tracer=false, Chams=false, Names=false, Health=false,
 ThroughWalls=true, Colors={Skeleton=Color3.new(1,1,1),Tracer=Color3.new(1,1,1),Chams=Color3.new(1,1,1),Names=Color3.new(1,1,1),Health=Color3.fromRGB(100,255,150)}}
S.Activation="Toggle"
local heldAim=false
local binding=false
local stickyTarget=nil
local frameMotion,mouseIntent=Vector2.zero,Vector2.zero
local injectedMotion,injectionExpires=Vector2.zero,0
local manualUntil=0
local alive, version, target, botTarget = true, 0, nil, nil
local controls, driving, refresh = nil, false, nil
local links, message, messageUntil = {}, "", 0
local blue = Color3.fromRGB(130,130,130)


local function on(signal, fn)
	local c = signal:Connect(fn)
	table.insert(links, c)
	return c
end
local function new(class, props, parent)
	local item = Instance.new(class)
	for k,v in pairs(props) do item[k] = v end
	item.Parent = parent
	return item
end
local function round(item, radius)
	new("UICorner", {CornerRadius=UDim.new(0,radius)}, item)
end
local function note(text)
	message, messageUntil = text, os.clock()+3
end
local function part(model, name)
	local p = model and model:FindFirstChild(name,true)
	return p and p:IsA("BasePart") and p or nil
end
local function body(model)
	if not model or not model:IsDescendantOf(workspace) then return end
	local h = model:FindFirstChildWhichIsA("Humanoid",true)
	local root = part(model,"HumanoidRootPart") or part(model,"UpperTorso")
		or part(model,"Torso") or model.PrimaryPart or part(model,"Head") or model:FindFirstChildWhichIsA("BasePart",true)
	if h and h.Health>0 and h:GetState()~=Enum.HumanoidStateType.Dead
		and root and root:IsA("BasePart") then return h,root end
end
local function enemy(p)
	if not p or p==me or p.Parent~=P or not body(p.Character) then return false end
	if S.TeamCheck and not me.Neutral and not p.Neutral and me.Team and p.Team==me.Team then return false end
	return true
end
local aimParts={"Head","Torso","Left Arm","Right Arm","Left Leg","Right Leg","Random"}
local randomModel,randomPart
local limbNames={
    ["Head"]={"Head"}, ["Torso"]={"UpperTorso","Torso","LowerTorso"},
    ["Left Arm"]={"LeftUpperArm","Left Arm","LeftLowerArm","LeftHand"},
    ["Right Arm"]={"RightUpperArm","Right Arm","RightLowerArm","RightHand"},
    ["Left Leg"]={"LeftUpperLeg","Left Leg","LeftLowerLeg","LeftFoot"},
    ["Right Leg"]={"RightUpperLeg","Right Leg","RightLowerLeg","RightFoot"}}
local function aimPart(model)
    local _,root=body(model)
    if not root then return nil end
    local choice=S.Part
    if choice=="Random" then
        if randomModel~=model or not randomPart or not randomPart:IsDescendantOf(model) then
            local available={}
            for _,name in ipairs(aimParts) do
                for _,limb in ipairs(limbNames[name] or {}) do
                    local found=part(model,limb)
                    if found then table.insert(available,found);break end
                end
            end
            randomModel=model
            randomPart=#available>0 and available[math.random(#available)] or root
        end
        return randomPart
    end
    for _,name in ipairs(limbNames[choice] or {}) do
        local found=part(model,name)
        if found then return found end
    end
    return root
end
local function visible(origin, model)
	local _,root = body(model)
	if not root then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	local ignored={}
	if me.Character then table.insert(ignored,me.Character) end
	if workspace.CurrentCamera then table.insert(ignored,workspace.CurrentCamera) end
	params.FilterDescendantsInstances=ignored
	local hit = workspace:Raycast(origin,root.Position-origin,params)
	return not hit or hit.Instance:IsDescendantOf(model)
end

task.spawn(function()
	local scripts = me:WaitForChild("PlayerScripts",10)
	local module = scripts and scripts:WaitForChild("PlayerModule",10)
	if module then
		local ok,result = pcall(function() return require(module):GetControls() end)
		if ok and alive then controls=result end
	end
end)

-- UI v4.1: reference-inspired monospace tabs.
local Http=game:GetService("HttpService")
local UI={Tab="Aimbot",MenuKey=Enum.KeyCode.RightShift,DisableMovement=false,
	Indicators=true,IndicatorX=1,IndicatorY=35,Watermark=true,WatermarkPosition="Top left",
	WatermarkX=1,WatermarkY=1,MenuAlpha=0,Discord="",
	Theme={Main=Color3.fromRGB(16,16,18),Background=Color3.fromRGB(11,11,13),
		Accent=Color3.fromRGB(165,95,240),Outline=Color3.fromRGB(67,67,72),
		Text=Color3.fromRGB(225,225,230),Muted=Color3.fromRGB(145,145,155)}}
local menuBinding=false
local themeTargets,widgetUpdates,tabs,pages={},{},{},{}
local controlsHeld=false
local stopBot,stopAll,togglePanel,syncMenuControls
local gui=new("ScreenGui",{Name="SimpleCombatUI",ResetOnSpawn=false,DisplayOrder=100,
	ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)
local overlay=new("ScreenGui",{Name="SimpleCombatCircle",ResetOnSpawn=false,
	IgnoreGuiInset=true,DisplayOrder=90},pg)
local circle=new("Frame",{AnchorPoint=Vector2.new(.5,.5),BackgroundTransparency=1,Visible=false},overlay)
round(circle,10000)
local stroke=new("UIStroke",{Color=Color3.fromRGB(180,180,190),Thickness=1},circle)
local dot=new("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
	Size=UDim2.fromOffset(3,3),BackgroundColor3=Color3.new(1,1,1),BorderSizePixel=0},circle)
local function theme(item,property,role)
	item[property]=UI.Theme[role]
	table.insert(themeTargets,{item,property,role})
	return item
end
local function outline(item)
	return theme(new("UIStroke",{Thickness=1,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},item),"Color","Outline")
end
local function label(parent,text,x,y,w,h,size,role)
	return theme(new("TextLabel",{Text=text,Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(w,h),Font=Enum.Font.Code,TextSize=size or 12,
		TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd,
		BackgroundTransparency=1,BorderSizePixel=0},parent),"TextColor3",role or "Text")
end
local function rect(parent,x,y,w,h,role)
	return theme(new("Frame",{Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,h),
		BorderSizePixel=0},parent),"BackgroundColor3",role or "Main")
end
local panel=rect(gui,20,80,560,620,"Main")
panel.AnchorPoint=Vector2.new(0,.5)
panel.Position=UDim2.new(0,24,.5,0)
outline(panel)
local scale=new("UIScale",{},panel)
local title=label(panel,"Combat UI | PRISON-6",9,4,410,19,12)
rect(panel,7,27,546,2,"Accent")
local function button(parent,text,x,y,w,h,fn)
	local b=theme(new("TextButton",{Text=text,Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(w,h),Font=Enum.Font.Code,TextSize=12,
		BorderSizePixel=0,AutoButtonColor=true},parent),"BackgroundColor3","Background")
	theme(b,"TextColor3","Text"); outline(b)
	if fn then on(b.Activated,fn) end
	return b
end
local hide=button(panel,"_",502,5,21,17)
local close=button(panel,"X",529,5,21,17)
local open=button(gui,"Combat UI [+]",18,100,116,23)
open.Visible=false
local function input(parent,text,x,y,w,h,changed)
	local box=theme(new("TextBox",{Text=text,Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(w,h),Font=Enum.Font.Code,TextSize=12,ClearTextOnFocus=false,
		TextXAlignment=Enum.TextXAlignment.Left,BorderSizePixel=0},parent),"BackgroundColor3","Background")
	theme(box,"TextColor3","Text"); outline(box)
	new("UIPadding",{PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,4)},box)
	if changed then on(box.FocusLost,function() changed(box.Text,box) end) end
	return box
end
local function group(parent,titleText,x,y,w,h)
	local f=rect(parent,x,y,w,h,"Main"); outline(f)
	rect(f,5,0,w-10,1,"Accent")
	local name=label(f," "..titleText.." ",8,-8,math.min(w-16,#titleText*7+14),16,12)
	name.BackgroundTransparency=0; theme(name,"BackgroundColor3","Main")
	return f
end
local function check(parent,titleText,x,y,w,get,set)
	local b=new("TextButton",{Text="",Position=UDim2.fromOffset(x,y),Size=UDim2.fromOffset(w,21),
		BackgroundTransparency=1,AutoButtonColor=false},parent)
	local square=rect(b,2,6,9,9,"Background"); outline(square)
	local text=label(b,titleText,17,0,w-17,21,12)
	table.insert(widgetUpdates,function()
		square.BackgroundColor3=get() and UI.Theme.Accent or UI.Theme.Background
	end)
	on(b.Activated,function() set(not get()); refresh() end)
	return b
end
local function number(parent,titleText,x,y,w,get,set,minimum,maximum)
	label(parent,titleText,x,y,w-60,19,12)
	local box=input(parent,tostring(get()),x+w-56,y,56,19,function(text,b)
		local n=tonumber(text)
		if n and n==n and math.abs(n)<math.huge then set(math.clamp(n,minimum,maximum)) end
		b.Text=tostring(get()); refresh()
	end)
	local track=rect(parent,x,y+24,w,5,"Background")
	local fill=rect(track,0,0,w,5,"Accent")
	local hit=new("TextButton",{Text="",BackgroundTransparency=1,
		Position=UDim2.fromOffset(x,y+20),Size=UDim2.fromOffset(w,13),ZIndex=3},parent)
	local held=nil
	local function slide(position)
		local ratio=math.clamp((position.X-track.AbsolutePosition.X)/math.max(1,track.AbsoluteSize.X),0,1)
		local value=minimum+(maximum-minimum)*ratio
		set(maximum<=1 and math.round(value*100)/100 or math.round(value));refresh()
	end
	on(hit.InputBegan,function(event)
		if event.UserInputType==Enum.UserInputType.MouseButton1 or event.UserInputType==Enum.UserInputType.Touch then
			held=event;slide(event.Position)
		end
	end)
	on(U.InputChanged,function(event)
		if held and (event==held or (held.UserInputType==Enum.UserInputType.MouseButton1
			and event.UserInputType==Enum.UserInputType.MouseMovement)) then slide(event.Position) end
	end)
	on(U.InputEnded,function(event)
		if event==held or (held and event.UserInputType==Enum.UserInputType.MouseButton1) then held=nil end
	end)
	table.insert(widgetUpdates,function()
		if not box:IsFocused() then box.Text=tostring(get()) end
		fill.Size=UDim2.new((get()-minimum)/(maximum-minimum),0,1,0)
	end)
end
local dropdown=nil
local function closeDropdown()
    if dropdown then dropdown:Destroy();dropdown=nil end
end
local function cycle(parent,titleText,x,y,w,values,get,set)
    label(parent,titleText,x,y,w,17,12)
    local b=button(parent,"",x,y+19,w,20)
    on(b.Activated,function()
        local wasOpen=dropdown and dropdown:GetAttribute("Owner")==titleText
        closeDropdown()
        if wasOpen then return end
        local layer=new("TextButton",{Text="",AutoButtonColor=false,BackgroundTransparency=1,
            Size=UDim2.fromScale(1,1),ZIndex=200},gui)
        dropdown=layer;layer:SetAttribute("Owner",titleText)
        on(layer.Activated,closeDropdown)
        local factor=b.AbsoluteSize.X/w
        local width=b.AbsoluteSize.X
        local rowHeight=24*factor
        local height=#values*rowHeight+4
        local pos=b.AbsolutePosition
        local area=gui.AbsoluteSize
        local popup=rect(layer,math.clamp(pos.X,0,math.max(0,area.X-width)),
            math.clamp(pos.Y+b.AbsoluteSize.Y+2,0,math.max(0,area.Y-height)),width,height,"Background")
        popup.ZIndex=201;outline(popup)
        for i,value in ipairs(values) do
            local option=button(popup,(value==get() and "[x] " or "[ ] ")..tostring(value),
                2,2+(i-1)*rowHeight,width-4,rowHeight,function()
                    set(value);closeDropdown();refresh()
                end)
            option.ZIndex=202;option.TextSize=math.max(9,12*factor)
            option.TextXAlignment=Enum.TextXAlignment.Left
            if value==get() then option.TextColor3=UI.Theme.Accent end
        end
    end)
    table.insert(widgetUpdates,function() b.Text=tostring(get()).."  v" end)
    return b
end
local function colorHex(c)
	return string.format("%02X%02X%02X",math.round(c.R*255),math.round(c.G*255),math.round(c.B*255))
end
local function parseColor(value)
	local hex=type(value)=="string" and value:gsub("%s",""):gsub("^#","") or ""
	if #hex~=6 or not hex:match("^%x+$") then return nil end
	return Color3.fromRGB(tonumber(hex:sub(1,2),16),tonumber(hex:sub(3,4),16),tonumber(hex:sub(5,6),16))
end
local function colorField(parent,titleText,x,y,w,get,set)
	label(parent,titleText,x,y,w-99,20,12)
	local swatch=rect(parent,x+w-94,y+4,15,12,"Accent")
	local box=input(parent,colorHex(get()),x+w-73,y,73,20,function(value,b)
		local c=parseColor(value)
		if c then set(c) else note("Color HEX: usa 6 digitos, ejemplo A55FF0.") end
		b.Text=colorHex(get()); refresh()
	end)
	table.insert(widgetUpdates,function()
		swatch.BackgroundColor3=get()
		if not box:IsFocused() then box.Text=colorHex(get()) end
	end)
end
local function applyTheme()
	for _,entry in ipairs(themeTargets) do
		if entry[1].Parent then entry[1][entry[2]]=UI.Theme[entry[3]] end
	end
	panel.BackgroundTransparency=UI.MenuAlpha
end

for i,name in ipairs({"Aimbot","ESP","Rage Bot","Settings"}) do
	local page=new("ScrollingFrame",{Name=name,Position=UDim2.fromOffset(9,62),
		Size=UDim2.fromOffset(542,510),BackgroundTransparency=1,BorderSizePixel=0,
		ScrollBarThickness=3,CanvasSize=UDim2.fromOffset(0,name=="Settings" and 824 or name=="Rage Bot" and 1540 or 510),
		ScrollingDirection=Enum.ScrollingDirection.Y,Visible=name==UI.Tab},panel)
	theme(page,"ScrollBarImageColor3","Accent")
	pages[name]=page
	local tab=button(panel,name,9+(i-1)*92,35,86,21,function()
		UI.Tab=name
		for key,p in pairs(pages) do p.Visible=key==name end
		refresh()
	end)
	tabs[name]=tab
end
local espPage=pages.ESP
local sectionInfo=label(panel,"",10,579,438,16,11,"Muted")
local status=label(panel,"Ready",10,598,438,16,11)
local emergency=button(panel,"STOP ALL",458,581,91,29)

-- Existing combat controls retain their handlers.
local buttons={}
local a=group(pages.Aimbot,"Aimbot",4,13,258,226)
buttons.Enabled=check(a,"Master enabled",8,12,240,function()return S.Enabled end,function()end)
buttons.Aim=check(a,"Enabled",8,35,240,function()return S.Aim end,function()end)
-- Existing handlers below own these two state changes.
buttons.Lock=check(a,"Direct aim",8,58,240,function()return S.Lock end,function()end)
local sticky=check(a,"Sticky target",8,81,240,function()return S.Sticky end,function()end)
label(a,"Activation key",9,110,100,20)
local activeCount=button(a,"[Q]",130,110,118,20)
buttons.Center=cycle(a,"Aim mode",9,140,239,{"Camera","Mouse"},
	function()return S.Center=="Cursor" and "Mouse" or "Camera" end,
	function(v) S.Center=v=="Mouse" and "Cursor" or "Crosshair";target=nil;stickyTarget=nil end)
buttons.Part=cycle(a,"Target part",9,181,239,aimParts,function()return S.Part end,function(v)S.Part=v;randomModel=nil;randomPart=nil end)
cycle(pages.Aimbot,"Activation",280,345,239,{"Toggle","Hold"},function()return S.Activation end,
    function(v) S.Activation=v;S.Aim=false;heldAim=false;target=nil;stickyTarget=nil end)
local b=group(pages.Aimbot,"Automation",276,13,258,157)
local auto=check(b,"Autoplay",8,12,240,function()return S.Mode=="Auto" end,function()end)
local kill=check(b,"Kill all / one pass",8,35,240,function()return S.Mode=="All" end,function()end)
label(b,"Uses the equipped Tool.",9,66,239,18,11,"Muted")
label(b,"Damage depends on the game.",9,84,239,18,11,"Muted")
label(b,"Backspace stops all features.",9,112,239,18,11,"Muted")
local c=group(pages.Aimbot,"Targeting",4,257,258,146)
number(c,"FOV radius (px)",9,15,239,function()return S.FOV end,function(v)S.FOV=math.round(v)end,20,600)
number(c,"Smoothness",9,58,239,function()return S.Smooth end,function(v)S.Smooth=math.round(v)end,0,100)
check(c,"Team check",8,106,240,function()return S.TeamCheck end,
	function(v)S.TeamCheck=v;stickyTarget=nil;target=nil end)
local d=group(pages.Aimbot,"Information",276,191,258,126)
label(d,"Stable lock; strong mouse to switch.",9,13,239,18,11,"Muted")
label(d,"Target part is independent.",9,34,239,18,11,"Muted")
label(d,"Mouse mode needs a free cursor.",9,55,239,18,11,"Muted")
label(d,"Drag the title bar to move.",9,87,239,18,11,"Muted")

local effects=group(pages.ESP,"Visuals",4,13,258,205)
local colors=group(pages.ESP,"Colors",276,13,258,205)
for i,entry in ipairs({{"Skeleton","Skeleton"},{"Tracer","Tracer"},{"Chams","Chams"},{"Names","Names"},{"Health","Health"}}) do
	local key,titleText=entry[1],entry[2]
	check(effects,titleText,8,14+(i-1)*30,240,function()return S[key] end,
		function(v)S[key]=v;if v then S.Enabled=true end end)
	colorField(colors,titleText,9,14+(i-1)*30,239,function()return S.Colors[key]end,
		function(v)S.Colors[key]=v end)
end
local filters=group(pages.ESP,"Filters",4,239,258,100)
check(filters,"Team check",8,14,240,function()return S.TeamCheck end,
	function(v)S.TeamCheck=v;stickyTarget=nil;target=nil end)
check(filters,"Show through walls",8,40,240,function()return S.ThroughWalls end,function(v)S.ThroughWalls=v end)
label(filters,"Wall setting affects ESP only.",9,69,239,17,11,"Muted")
local info=group(pages.ESP,"Indicators",276,239,258,100)
label(info,"All visual effects share one",9,15,239,18,11,"Muted")
label(info,"entry in the active list: ESP.",9,35,239,18,11,"Muted")
label(info,"Names and health remain in-game.",9,68,239,18,11,"Muted")

-- Settings modeled on the supplied references.
local settingsActions={}
local main=group(pages.Settings,"Main",4,13,258,230)
label(main,"Open / close",9,12,130,20)
local menuKeyButton=button(main,"[RIGHTSHIFT]",139,12,109,20,function()
	menuBinding=not menuBinding;binding=false;refresh()
end)
check(main,"Disable movement if open",8,36,240,function()return UI.DisableMovement end,
	function(v)UI.DisableMovement=v;if syncMenuControls then syncMenuControls(true) end end)
settingsActions.Rejoin=button(main,"Rejoin server",9,65,239,20)
settingsActions.Copy=button(main,"Copy join script",9,90,239,20)
settingsActions.Unload=button(main,"Unload",9,115,239,20,function()gui:Destroy()end)
label(main,"Discord invite (optional)",9,144,239,17,11,"Muted")
local discordBox=input(main,"",9,164,239,19,function(value)UI.Discord=value end)
settingsActions.JoinDiscord=button(main,"Join Discord",9,190,116,20)
settingsActions.CopyDiscord=button(main,"Copy Discord",132,190,116,20)

local keys=group(pages.Settings,"Keybinds",4,265,258,137)
check(keys,"Keybind indicator",8,12,240,function()return UI.Indicators end,function(v)UI.Indicators=v end)
number(keys,"Position X (%)",9,42,239,function()return UI.IndicatorX end,function(v)UI.IndicatorX=v end,0,100)
number(keys,"Position Y (%)",9,85,239,function()return UI.IndicatorY end,function(v)UI.IndicatorY=v end,0,100)

local water=group(pages.Settings,"Watermark",4,424,258,184)
check(water,"Enabled",8,12,240,function()return UI.Watermark end,function(v)UI.Watermark=v end)
cycle(water,"Position",9,40,239,{"Top left","Top right","Custom"},
	function()return UI.WatermarkPosition end,function(v)UI.WatermarkPosition=v end)
number(water,"Custom X (%)",9,88,239,function()return UI.WatermarkX end,function(v)UI.WatermarkX=v end,0,100)
number(water,"Custom Y (%)",9,131,239,function()return UI.WatermarkY end,function(v)UI.WatermarkY=v end,0,100)

local themeGroup=group(pages.Settings,"Theme",276,265,258,265)
local presets={"Purple","Blue","Red"}
local preset="Purple"
cycle(themeGroup,"Presets",9,12,239,presets,function()return preset end,function(v)
	preset=v
	UI.Theme.Accent=v=="Red" and Color3.fromRGB(220,60,70)
		or v=="Blue" and Color3.fromRGB(75,140,220) or Color3.fromRGB(165,95,240)
	applyTheme()
end)
for i,entry in ipairs({{"Main","Main color"},{"Accent","Accent color"},{"Background","Background"},
	{"Outline","Outline color"},{"Text","Text color"},{"Muted","Secondary text"}}) do
	local key,titleText=entry[1],entry[2]
	colorField(themeGroup,titleText,9,61+(i-1)*24,239,function()return UI.Theme[key]end,
		function(v)UI.Theme[key]=v;applyTheme()end)
end
number(themeGroup,"Menu transparency",9,214,239,function()return UI.MenuAlpha end,
	function(v)UI.MenuAlpha=v;applyTheme()end,0,.65)

-- Private weapon integration: attributes are consumed by CombatWeapon.client.luau.
local rageConfig=new("Folder",{Name="RageSettings"},gui)
local rageDefaults={Enabled=false,Aimbot=true,SilentAim=false,AutoShoot=false,AutoWall=false,
 Wallbang=false,Prediction=false,PredictionTime=0,NoRecoil=true,NoSpread=false,HitChance=0,
 FOV=200,Selection="Manual",TargetKey="Sin asignar",RageKey="Sin asignar",SelectedUserId=0,Hitbox="Head",VisibilityCheck=true,AutoSwitch=true,
 RapidFire=false,Aim360=false,TeamCheck=true,TeleportTarget=true,Visualize=true,Strafe=false,StrafeRadius=5,StrafeSpeed=90,ClosestPart=false,IgnoreProtected=false,
 LimitDistance=false,MaxDistance=800,ReactionTime=0,ForgetTime=1,FullAuto=false,FireRatePercent=100,
 NotifyHit=true,NotifyDuration=2,NotifyText="Hit {NAME} for {DMG} in {PART} ({WEAPON})"}
for key,value in pairs(rageDefaults) do rageConfig:SetAttribute(key,value) end
local rageLeft=group(pages["Rage Bot"],"Private weapon",4,435,258,350)
local rageRight=group(pages["Rage Bot"],"Targeting",276,435,258,475)
local rageFlags={{"Enabled","Rage Bot enabled"},{"Aimbot","Aimbot"},{"SilentAim","Silent Aim"},
 {"AutoShoot","Auto Shoot"},{"AutoWall","Auto Wall"},{"Wallbang","Wallbang"},
 {"Prediction","Target Prediction"},{"NoRecoil","No Recoil (weapon has none)"},
 {"NoSpread","No Spread"},{"VisibilityCheck","Visibility Check"},
 {"AutoSwitch","Auto Switch Target"},{"RapidFire","Rapid Fire"},{"Aim360","360 Aim"},{"TeamCheck","Team Check"}}
for i,entry in ipairs(rageFlags) do
 local key,text=entry[1],entry[2]
 check(rageLeft,text,8,12+(i-1)*23,240,function()return rageConfig:GetAttribute(key)end,
  function(value)
   rageConfig:SetAttribute(key,value)
   if key=="Enabled" and value then S.Aim=false;heldAim=false;target=nil;stickyTarget=nil;if stopBot then stopBot() end end
  end)
end
number(rageRight,"FOV (px)",9,15,239,function()return rageConfig:GetAttribute("FOV")end,
 function(v)rageConfig:SetAttribute("FOV",v)end,20,600)
number(rageRight,"Hit Chance (%)",9,60,239,function()return rageConfig:GetAttribute("HitChance")end,
 function(v)rageConfig:SetAttribute("HitChance",v)end,0,100)
cycle(rageRight,"Target Selection",9,105,239,{"Manual","Crosshair","Distance","Health"},
 function()return rageConfig:GetAttribute("Selection")end,function(v)rageConfig:SetAttribute("Selection",v)end)
cycle(rageRight,"Hitbox Selection",9,155,239,aimParts,
 function()return rageConfig:GetAttribute("Hitbox")end,function(v)rageConfig:SetAttribute("Hitbox",v)end)
number(rageRight,"Prediction time (s)",9,210,239,function()return rageConfig:GetAttribute("PredictionTime")end,
 function(v)rageConfig:SetAttribute("PredictionTime",v)end,0,.25)
local rageBinding=false
local targetBinding=false
local targetControls=group(pages["Rage Bot"],"OBJETIVO",4,13,530,200)
local rageGhost=nil
local observing=false
local observedCamera,previousSubject
local selectKeyButton=button(targetControls,"Target Selection [Sin asignar] - cambiar tecla",9,16,508,25,function()
 targetBinding=not targetBinding;rageBinding=false;binding=false;menuBinding=false
end)
local rageKeyButton=button(targetControls,"Rage ON/OFF [Sin asignar]",9,151,508,25,function()
 rageBinding=not rageBinding;targetBinding=false;binding=false;menuBinding=false
end)
local selectedLabel=label(targetControls,"Objetivo: ninguno",9,51,508,20,11,"Muted")
local observeButton
local function endObserve()
 observing=false
 rageConfig:SetAttribute("Observing",false)
 if observedCamera and observedCamera==workspace.CurrentCamera then
  local own=me.Character and me.Character:FindFirstChildOfClass("Humanoid")
  if previousSubject and previousSubject.Parent then observedCamera.CameraSubject=previousSubject
  elseif own then observedCamera.CameraSubject=own end
 end
 observedCamera=nil;previousSubject=nil
end
local function selectedPlayer()
 local id=rageConfig:GetAttribute("SelectedUserId")
 return id and id~=0 and P:GetPlayerByUserId(id) or nil
end
observeButton=button(targetControls,"Observar objetivo",9,81,250,25,function()
 if observing then endObserve();return end
 local p=selectedPlayer();local h=p and body(p.Character)
 local camera=workspace.CurrentCamera
 if not h or not camera then note("Selecciona un jugador vivo primero.");return end
 observedCamera=camera;previousSubject=camera.CameraSubject;observing=true
 rageConfig:SetAttribute("Observing",true)
 camera.CameraSubject=h
end)
button(targetControls,"Quitar objetivo",274,81,243,25,function()
 rageConfig:SetAttribute("SelectedUserId",0);endObserve()
end)
local function selectRageTarget(p)
 if not p or p==me or p.Parent~=P then return end
 rageConfig:SetAttribute("SelectedUserId",p.UserId)
 rageConfig:SetAttribute("Selection","Manual")

 refresh()
 note("Objetivo seleccionado: "..p.Name..". Rage no cambia de estado.")
end
label(targetControls,"Mouse sobre jugador + tecla: selecciona sin hacer clic.",9,119,508,22,11,"Muted")

local serverGroup=group(pages["Rage Bot"],"JUGADORES DEL SERVIDOR",4,231,530,180)
local serverList=new("ScrollingFrame",{Position=UDim2.fromOffset(8,14),Size=UDim2.fromOffset(514,156),
 BackgroundTransparency=1,BorderSizePixel=0,ScrollBarThickness=4,CanvasSize=UDim2.fromOffset(0,0)},serverGroup)
local listConnections={}
local function rebuildServerList(exclude)
 for _,connection in ipairs(listConnections) do connection:Disconnect() end
 table.clear(listConnections)
 serverList:ClearAllChildren()
 local players=P:GetPlayers()
 table.sort(players,function(a,b)return a.Name:lower()<b.Name:lower()end)
 local index=0
 for _,p in ipairs(players) do
  if p~=me and p~=exclude then
   local row=button(serverList,p.DisplayName.." (@"..p.Name..")",2,index*29,502,25)
   row.TextXAlignment=Enum.TextXAlignment.Left
   table.insert(listConnections,row.Activated:Connect(function()selectRageTarget(p)end))
   index+=1
  end
 end
 serverList.CanvasSize=UDim2.fromOffset(0,index*29)
 if index==0 then label(serverList,"No hay otros jugadores.",4,0,490,25,12,"Muted") end
end
on(P.PlayerAdded,function()rebuildServerList()end)
on(P.PlayerRemoving,function(p)
 if rageConfig:GetAttribute("SelectedUserId")==p.UserId then rageConfig:SetAttribute("SelectedUserId",0);endObserve() end
 rebuildServerList(p)
end)
on(gui.Destroying,function()for _,connection in ipairs(listConnections) do connection:Disconnect() end end)
rebuildServerList()
on(R.Heartbeat,function()
 local p=selectedPlayer()
 if p and not body(p.Character) then rageConfig:SetAttribute("SelectedUserId",0);p=nil end
 rageKeyButton.Text=rageBinding and "Pulsa tecla Rage ON/OFF..." or "Rage ON/OFF ["..rageConfig:GetAttribute("RageKey").."] - cambiar tecla"
 selectedLabel.Text="Objetivo: "..(p and p.Name or "ninguno")
 selectKeyButton.Text=targetBinding and "Pulsa la nueva tecla... (Esc cancela)" or "Target Selection ["..rageConfig:GetAttribute("TargetKey").."] - cambiar tecla"
 observeButton.Text=observing and "Dejar de observar" or "Observar objetivo"
 if observing then
  local h=p and body(p.Character)
  rageConfig:SetAttribute("Observing",true)
  if not h or workspace.CurrentCamera~=observedCamera then endObserve()
  else observedCamera.CameraSubject=h end
 end
end)
on(gui.Destroying,endObserve)
check(rageRight,"TP al objetivo",8,266,240,function()return rageConfig:GetAttribute("TeleportTarget")end,function(v)rageConfig:SetAttribute("TeleportTarget",v)end)
check(rageRight,"Copia local controlable",8,294,240,function()return rageConfig:GetAttribute("Visualize")end,function(v)rageConfig:SetAttribute("Visualize",v)end)
label(rageRight,"Copia local: WASD + Espacio.",9,334,239,30,11,"Muted")
do
 local getting=false
 button(rageRight,"Conseguir Remington 870",9,383,239,26,function()
  if getting then return end
  local h,root=body(me.Character);if not root then note("Personaje no disponible.");return end
  local items=workspace:FindFirstChild("Prison_ITEMS")
  local giver=items and items:FindFirstChild("giver")
  local gun=giver and giver:FindFirstChild("Remington 870")
  local pickup=gun and gun:FindFirstChild("ITEMPICKUP")
  local remoteFolder=workspace:FindFirstChild("Remote")
  local remote=remoteFolder and remoteFolder:FindFirstChild("ItemHandler")
  if not pickup or not pickup:IsA("BasePart") or not remote or not remote:IsA("RemoteFunction") then note("No se encontro el pickup o ItemHandler.");return end
  -- Stop before taking the return snapshot, so it is the user's controlled position.
  local proxyRoot=rageGhost and rageGhost:FindFirstChild("HumanoidRootPart")
  local returnPosition=proxyRoot and proxyRoot.CFrame or root.CFrame
  rageConfig:SetAttribute("Enabled",false);endObserve()
  task.defer(function()
   local _,currentRoot=body(me.Character);if not currentRoot then return end
   local character=me.Character;local saved=returnPosition;getting=true
   local returned=false
   local function back()
    if returned then return end;returned=true
    if me.Character==character and currentRoot.Parent then currentRoot.CFrame=saved;currentRoot.AssemblyLinearVelocity=Vector3.zero end
    getting=false
   end
   task.delay(3,back)
   local ok=pcall(function()
    currentRoot.CFrame=pickup.CFrame*CFrame.new(0,3,0)
    task.wait(.15);remote:InvokeServer(pickup)
   end)
   back()
   local bag=me:FindFirstChildOfClass("Backpack")
   local obtained=(bag and bag:FindFirstChild("Remington 870")) or (me.Character and me.Character:FindFirstChild("Remington 870"))
   note(obtained and "Remington recibida; posicion restaurada." or (ok and "Solicitud enviada; arma aun no confirmada." or "No se pudo pedir el arma; posicion restaurada."))
  end)
 end)
end

-- Local controllable proxy. The server still sees the original character at the target.
do
 local sourceCharacter=nil
 local savedSubject,savedType,proxyCamera
 local proxyHumanoid=nil
 local motors={}
 local nextTeleport=0
 local orbitAngle=0
 local orbitTarget=nil
 local orbitTime=os.clock()
 local function clearProxy()
  if not rageGhost then return end
  local _,realRoot=body(me.Character)
  local proxyRoot=rageGhost:FindFirstChild("HumanoidRootPart")
  if realRoot and proxyRoot and sourceCharacter==me.Character then
   realRoot.CFrame=proxyRoot.CFrame
   realRoot.AssemblyLinearVelocity=Vector3.zero;realRoot.AssemblyAngularVelocity=Vector3.zero
  end
  if observing then endObserve() end
  if proxyCamera and proxyCamera==workspace.CurrentCamera then
   local own=me.Character and me.Character:FindFirstChildOfClass("Humanoid")
   proxyCamera.CameraSubject=(savedSubject and savedSubject.Parent and savedSubject) or own
   if savedType then proxyCamera.CameraType=savedType end
  end
  rageGhost:Destroy();rageGhost=nil;sourceCharacter=nil;proxyHumanoid=nil
  table.clear(motors);syncMenuControls(true)
 end
 local function buildProxy(character)
  clearProxy()
  local old=character.Archivable;character.Archivable=true
  local ok,clone=pcall(function()return character:Clone()end)
  character.Archivable=old
  if not ok or not clone then note("No se pudo crear la copia local.");return end
  for _,item in ipairs(clone:GetDescendants()) do
   if item:IsA("LuaSourceContainer") or item:IsA("Tool") or item:IsA("Sound") or item:IsA("ParticleEmitter") or item:IsA("Trail") then item:Destroy() end
  end
  for _,item in ipairs(clone:GetDescendants()) do
   if item:IsA("BasePart") then
    item.Anchored=false;item.CanTouch=false;item.CanQuery=false
    item.AssemblyLinearVelocity=Vector3.zero;item.AssemblyAngularVelocity=Vector3.zero
    item.Transparency=math.max(item.Transparency,.2)
   elseif item:IsA("Motor6D") and (item.Name:find("Hip") or item.Name:find("Shoulder")) then
    table.insert(motors,{Part=item,Base=item.C0,Sign=item.Name:find("Left") and 1 or -1})
   end
  end
  proxyHumanoid=clone:FindFirstChildOfClass("Humanoid")
  if not proxyHumanoid then clone:Destroy();return end
  proxyHumanoid.DisplayDistanceType=Enum.HumanoidDisplayDistanceType.None
  proxyHumanoid.PlatformStand=false;proxyHumanoid.Sit=false;proxyHumanoid.AutoRotate=true
  proxyHumanoid.WalkSpeed=16
  clone.Name="CombatLocalProxy";clone.Parent=workspace
  rageGhost=clone;sourceCharacter=character
  proxyCamera=workspace.CurrentCamera
  if proxyCamera then
   savedSubject=proxyCamera.CameraSubject;savedType=proxyCamera.CameraType
   if not observing then proxyCamera.CameraType=Enum.CameraType.Custom;proxyCamera.CameraSubject=proxyHumanoid end
  end
  syncMenuControls(true)
  note("Copia local: WASD y Espacio. Los demas ven tu personaje real junto al objetivo.")
 end
 on(R.Heartbeat,function()
  local p=selectedPlayer()
  local own,root=body(me.Character)
  local other,otherRoot
  if p then other,otherRoot=body(p.Character) end
  if not alive or not rageConfig:GetAttribute("Enabled") or not own or not other then clearProxy();nextTeleport=0;return end
  -- Create the proxy BEFORE teleporting, preserving the user's starting location.
  if rageConfig:GetAttribute("Visualize") then
   if sourceCharacter~=me.Character or not rageGhost or not rageGhost.Parent then buildProxy(me.Character) end
  else clearProxy() end
  if rageGhost then own:Move(Vector3.zero) end
  local now=os.clock()
  local dt=math.clamp(now-orbitTime,0,.1);orbitTime=now
  if rageConfig:GetAttribute("Strafe") then
   if orbitTarget~=p then
    local offset=root.Position-otherRoot.Position
    orbitAngle=math.atan2(offset.Z,offset.X);orbitTarget=p
   end
   orbitAngle=(orbitAngle+math.rad(rageConfig:GetAttribute("StrafeSpeed") or 90)*dt)%(math.pi*2)
   if now>=nextTeleport then
    nextTeleport=now
    local radius=math.clamp(rageConfig:GetAttribute("StrafeRadius") or 5,3,20)
    local offset=Vector3.new(math.cos(orbitAngle)*radius,0,math.sin(orbitAngle)*radius)
    local position=otherRoot.Position+offset
    local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
    local excluded={me.Character,p.Character}
    if rageGhost then table.insert(excluded,rageGhost) end
    params.FilterDescendantsInstances=excluded
    local wall=workspace:Raycast(otherRoot.Position,offset,params)
    local floor=workspace:Raycast(position+Vector3.new(0,5,0),Vector3.new(0,-15,0),params)
    if not wall and floor and floor.Normal.Y>.6 then
     position=Vector3.new(position.X,floor.Position.Y+own.HipHeight+root.Size.Y*.5,position.Z)
     local desired=CFrame.lookAt(position,Vector3.new(otherRoot.Position.X,position.Y,otherRoot.Position.Z))
     root.CFrame=root.CFrame:Lerp(desired,1-math.exp(-dt*18))
     root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
    end
   end
  elseif rageConfig:GetAttribute("TeleportTarget") and now>=nextTeleport then
   orbitTarget=nil;nextTeleport=now+.2
   if (root.Position-otherRoot.Position).Magnitude>7 then
    local position=otherRoot.Position-otherRoot.CFrame.LookVector*4
    root.CFrame=CFrame.lookAt(position,Vector3.new(otherRoot.Position.X,position.Y,otherRoot.Position.Z))
    root.AssemblyLinearVelocity=Vector3.zero;root.AssemblyAngularVelocity=Vector3.zero
   end
  end
 end)
 on(R.RenderStepped,function()
  if not rageGhost or not proxyHumanoid then return end
  local camera=workspace.CurrentCamera
  if not camera then return end
  local movement=Vector3.zero
  if not observing and not GuiService.MenuIsOpen and not U:GetFocusedTextBox() and not (UI.DisableMovement and panel.Visible) then
   local x=(U:IsKeyDown(Enum.KeyCode.D) and 1 or 0)-(U:IsKeyDown(Enum.KeyCode.A) and 1 or 0)
   local z=(U:IsKeyDown(Enum.KeyCode.W) and 1 or 0)-(U:IsKeyDown(Enum.KeyCode.S) and 1 or 0)
   local look=Vector3.new(camera.CFrame.LookVector.X,0,camera.CFrame.LookVector.Z)
   local right=Vector3.new(camera.CFrame.RightVector.X,0,camera.CFrame.RightVector.Z)
   if look.Magnitude>.001 then look=look.Unit else look=Vector3.new(0,0,-1) end
   if right.Magnitude>.001 then right=right.Unit else right=Vector3.new(1,0,0) end
   movement=right*x+look*z
   if movement.Magnitude>1 then movement=movement.Unit end
   if U:IsKeyDown(Enum.KeyCode.Space) and proxyHumanoid.FloorMaterial~=Enum.Material.Air then proxyHumanoid.Jump=true end
  end
  proxyHumanoid:Move(movement,false)
  local swing=movement.Magnitude>.05 and math.sin(os.clock()*10)*.5 or 0
  for _,motor in ipairs(motors) do
   if motor.Part.Parent then motor.Part.C0=motor.Base*CFrame.Angles(swing*motor.Sign,0,0) end
  end
  if not observing then camera.CameraType=Enum.CameraType.Custom;camera.CameraSubject=proxyHumanoid end
 end)
 on(rageConfig.AttributeChanged,function(key)
  if (key=="Enabled" and not rageConfig:GetAttribute("Enabled")) or (key=="Visualize" and not rageConfig:GetAttribute("Visualize")) then clearProxy() end
 end)
 on(gui.Destroying,clearProxy)
end

local orbitGroup=group(pages["Rage Bot"],"Strafe / Fake Position",4,1325,530,190)
check(orbitGroup,"Strafe: orbitar al objetivo",8,14,510,function()return rageConfig:GetAttribute("Strafe")end,function(v)rageConfig:SetAttribute("Strafe",v)end)
number(orbitGroup,"Distancia (studs)",9,48,505,function()return rageConfig:GetAttribute("StrafeRadius")end,function(v)rageConfig:SetAttribute("StrafeRadius",v)end,3,20)
number(orbitGroup,"Velocidad (grados/s)",9,92,505,function()return rageConfig:GetAttribute("StrafeSpeed")end,function(v)rageConfig:SetAttribute("StrafeSpeed",v)end,15,360)
label(orbitGroup,"Fake Position es una copia LOCAL; no altera la posicion del servidor.",9,135,505,40,11,"Muted")
local advanced=group(pages["Rage Bot"],"Targeting avanzado",4,940,258,350)
local weaponOptions=group(pages["Rage Bot"],"Arma / impactos",276,940,258,350)
for i,entry in ipairs({{"ClosestPart","Closest part"},{"IgnoreProtected","Ignore protected"},{"LimitDistance","Limit distance"}}) do
 local key,titleText=entry[1],entry[2]
 check(advanced,titleText,8,12+(i-1)*25,240,function()return rageConfig:GetAttribute(key)end,function(v)rageConfig:SetAttribute(key,v)end)
end
for i,entry in ipairs({{"MaxDistance","Max distance",1,800},{"ReactionTime","Reaction time (s)",0,2},{"ForgetTime","Forget time (s)",0,5}}) do
 local key,titleText,minimum,maximum=entry[1],entry[2],entry[3],entry[4]
 number(advanced,titleText,9,100+(i-1)*48,239,function()return rageConfig:GetAttribute(key)end,function(v)rageConfig:SetAttribute(key,v)end,minimum,maximum)
end
label(advanced,"Manual selection never switches",9,258,239,20,11,"Muted")
label(advanced,"to an unselected player.",9,279,239,20,11,"Muted")
check(weaponOptions,"Full auto",8,12,240,function()return rageConfig:GetAttribute("FullAuto")end,function(v)rageConfig:SetAttribute("FullAuto",v)end)
number(weaponOptions,"Firerate (%)",9,44,239,function()return rageConfig:GetAttribute("FireRatePercent")end,function(v)rageConfig:SetAttribute("FireRatePercent",v)end,25,200)
check(weaponOptions,"Notify confirmed hit",8,87,240,function()return rageConfig:GetAttribute("NotifyHit")end,function(v)rageConfig:SetAttribute("NotifyHit",v)end)
number(weaponOptions,"Notify duration (s)",9,123,239,function()return rageConfig:GetAttribute("NotifyDuration")end,function(v)rageConfig:SetAttribute("NotifyDuration",v)end,1,10)
input(weaponOptions,rageConfig:GetAttribute("NotifyText"),9,168,239,23,function(v)rageConfig:SetAttribute("NotifyText",v:sub(1,180))end)
label(weaponOptions,"{NAME} {DMG} {PART} {WEAPON}",9,198,239,20,11,"Muted")
-- Prison Life adapter: only the three fields evidenced by the supplied example.
local prisonStatus="Prison Life: adaptador preparado"
local gunAdapterStatus="GunStates: buscando arma..."
do
 local records={}
 local pending={}
 local clock=0
 local function desiredGunValues(original,enabled,noSpread,fullAuto,rapid,percent)
  local values={}
  if not enabled then return values end
  if noSpread and type(original.Spread)=="number" then values.Spread=0 end
  if fullAuto and type(original.AutoFire)=="boolean" then values.AutoFire=true end
  if type(original.FireRate)=="number" and original.FireRate>0 then
   local multiplier=math.clamp(tonumber(percent) or 100,25,200)/100
   if rapid then multiplier=math.max(multiplier,2) end
   if multiplier~=1 then values.FireRate=math.max(.01,original.FireRate/multiplier) end
  end
  return values
 end
 local function update(record,enabled)
  local desired=desiredGunValues(record.Original,enabled,
   rageConfig:GetAttribute("NoSpread"),rageConfig:GetAttribute("FullAuto"),
   rageConfig:GetAttribute("RapidFire"),rageConfig:GetAttribute("FireRatePercent"))
  local ok,err=pcall(function()
   for key,last in pairs(record.Applied) do
    if desired[key]==nil then
     if record.Data[key]==last then record.Data[key]=record.Original[key] end
     record.Applied[key]=nil
    end
   end
   for key,value in pairs(desired) do
    record.Data[key]=value;record.Applied[key]=value
   end
  end)
  record.Error=not ok and tostring(err) or nil
 end
 local function enabled()
  return alive and rageConfig:GetAttribute("Enabled")==true and not rageConfig:GetAttribute("Observing")
 end
 local function inspect(tool)
  if not tool:IsA("Tool") then return end
  local module=tool:FindFirstChild("GunStates")
  if not module or not module:IsA("ModuleScript") or records[module] or pending[module] then return end
  pending[module]=true
  task.spawn(function()
   local ok,data=pcall(require,module)
   if not alive then return end
   if not ok or type(data)~="table" then
    records[module]={Error="No se pudo leer GunStates",Tool=tool};return
   end
   local record={Data=data,Tool=tool,Original={Spread=data.Spread,AutoFire=data.AutoFire,FireRate=data.FireRate},Applied={}}
   records[module]=record;update(record,enabled())
  end)
 end
 local function refreshGuns()
  local equipped=me.Character and me.Character:FindFirstChildOfClass("Tool")
  for module,record in pairs(records) do
   if record.Data then update(record,enabled() and record.Tool.Parent~=nil) end
   if not module.Parent or not record.Tool.Parent then records[module]=nil;pending[module]=nil end
  end
  local backpack=me:FindFirstChildOfClass("Backpack")
  for _,container in ipairs({backpack or false,me.Character or false}) do
   if container then for _,tool in ipairs(container:GetChildren()) do inspect(tool) end end
  end
  local module=equipped and equipped:FindFirstChild("GunStates")
  local record=module and records[module]
  if record and record.Error then gunAdapterStatus="GunStates: no se pudo modificar."
  elseif record and record.Data then
   gunAdapterStatus="GunStates: "..equipped.Name..(enabled() and " / ajustes locales activos" or " / valores restaurados")
  elseif module then gunAdapterStatus="GunStates: leyendo modulo..."
  else gunAdapterStatus="Equipa un arma con GunStates. Sin conexion al disparo." end
 end
 on(rageConfig.AttributeChanged,function(key)
  if table.find({"Enabled","Observing","NoSpread","FullAuto","RapidFire","FireRatePercent"},key) then refreshGuns() end
 end)
 on(R.Heartbeat,function(dt)
  clock+=dt;if clock>=.4 then clock=0;refreshGuns() end
 end)
 on(gui.Destroying,function()
  for _,record in pairs(records) do if record.Data then update(record,false) end end
 end)
 refreshGuns()
end

local integrationStatus=label(weaponOptions,"Comprobando arma...",9,238,239,60,11,"Muted")
integrationStatus.TextWrapped=true
local RS=game:GetService("ReplicatedStorage")
local hitConnected=false
on(R.Heartbeat,function()
 local tool=me.Character and me.Character:FindFirstChildOfClass("Tool")
 local ready=RS:GetAttribute("CombatWeaponProtocol")==2 and tool and tool:GetAttribute("CombatWeaponClientReady")
 integrationStatus.Text=ready and "Arma conectada. Modificadores: Studio / propietario privado." or ((RS:FindFirstChild("GunRemotes") and tool and tool:GetAttribute("ToolType")=="Gun") and prisonStatus or gunAdapterStatus)
 local event=RS:FindFirstChild("CombatConfirmedHit")
 if not hitConnected and event and event:IsA("RemoteEvent") then
  hitConnected=true
  on(event.OnClientEvent,function(name,damage,partName,weapon)
   if not rageConfig:GetAttribute("NotifyHit") then return end
   local values={NAME=tostring(name),DMG=string.format("%.1f",tonumber(damage) or 0),PART=tostring(partName),WEAPON=tostring(weapon)}
   local text=rageConfig:GetAttribute("NotifyText"):gsub("{(%w+)}",function(key)return values[key] or "{"..key.."}"end)
   note(text);messageUntil=os.clock()+rageConfig:GetAttribute("NotifyDuration")
  end)
 end
end)

local configGroup=group(pages.Settings,"Configuration",276,13,258,230)
label(configGroup,"Config name",9,12,239,17)
local configName=input(configGroup,"default",9,33,239,20)
label(configGroup,"Config list",9,60,239,17)
local configSelect=button(configGroup,"none  >",9,80,239,20)
settingsActions.Load=button(configGroup,"Load",9,108,116,20)
settingsActions.Save=button(configGroup,"Save",132,108,116,20)
settingsActions.Create=button(configGroup,"Create",9,133,116,20)
settingsActions.Delete=button(configGroup,"Delete",132,133,116,20)
settingsActions.Refresh=button(configGroup,"Refresh list",9,158,239,20)
local storageLabel=label(configGroup,"Session storage",9,193,239,17,11,"Muted")

local credits=group(pages.Settings,"Credits",276,552,258,104)
label(credits,"Combat UI - custom build",9,15,239,18)
label(credits,"UI inspired by your references.",9,40,239,18,11,"Muted")
label(credits,"v4.1 / client-side interface",9,68,239,18,11,"Muted")
local help=group(pages.Settings,"Controls",4,630,258,146)
label(help,"Keyboard + mouse buttons supported.",9,14,239,18,11,"Muted")
label(help,"Escape cancels / stops everything.",9,36,239,18,11,"Muted")
label(help,"UI settings do not change",9,65,239,18,11,"Muted")
label(help,"the targeting or damage rules.",9,84,239,18,11,"Muted")
label(help,"Config load stops automation.",9,115,239,18,11,"Muted")

-- Side indicator: ESP is deliberately a single line.
local indicator=rect(gui,8,180,236,140,"Main")
outline(indicator);rect(indicator,0,0,236,2,"Accent")
label(indicator,"keybinds / active",7,6,222,18,12)
local activeLabel=label(indicator,"",7,29,222,150,11)
activeLabel.TextYAlignment=Enum.TextYAlignment.Top
activeLabel.TextTruncate=Enum.TextTruncate.None
local watermark=rect(gui,8,8,365,23,"Background")
outline(watermark);rect(watermark,0,0,365,1,"Accent")
local watermarkText=label(watermark,"Combat UI | PRISON-6",6,3,353,18,11)

local function activeRows()
	local rows={}
	if rageConfig:GetAttribute("Enabled") then table.insert(rows,"[-] Rage Bot") end
	if S.Enabled then
		if S.Aim or S.Mode then
			table.insert(rows,"["..S.Key.Name.."] "..(S.Center=="Cursor" and "mouse" or "camera").." aimbot ("..S.Activation..")")
		end
		if S.Sticky then table.insert(rows,"[-] sticky target") end
		if S.Lock then table.insert(rows,"[-] direct aim") end
		if S.Mode then table.insert(rows,"[-] "..(S.Mode=="Auto" and "autoplay" or "kill all")) end
		if S.Skeleton or S.Tracer or S.Chams or S.Names or S.Health then table.insert(rows,"[-] ESP") end
		if S.TeamCheck then table.insert(rows,"[-] team check") end
	end
	if #rows==0 then table.insert(rows,"no active features") end
	return rows
end
local function refreshHUD()
	local area=gui.AbsoluteSize
	local rows=activeRows()
	local height=35+#rows*17
	indicator.Size=UDim2.fromOffset(236,height)
	indicator.Position=UDim2.fromOffset(math.clamp(area.X*UI.IndicatorX/100,0,math.max(0,area.X-236)),
		math.clamp(area.Y*UI.IndicatorY/100,0,math.max(0,area.Y-height)))
	indicator.Visible=UI.Indicators
	activeLabel.Size=UDim2.fromOffset(222,#rows*17)
	activeLabel.Text=table.concat(rows,"\n")
	local x,y=8,8
	if UI.WatermarkPosition=="Top right" then x=math.max(0,area.X-373)
	elseif UI.WatermarkPosition=="Custom" then x=area.X*UI.WatermarkX/100;y=area.Y*UI.WatermarkY/100 end
	watermark.Position=UDim2.fromOffset(math.clamp(x,0,math.max(0,area.X-365)),
		math.clamp(y,0,math.max(0,area.Y-23)))
	watermark.Visible=UI.Watermark
end
refresh=function()
	for _,fn in ipairs(widgetUpdates) do fn() end
	for name,tab in pairs(tabs) do
		tab.TextColor3=name==UI.Tab and UI.Theme.Accent or UI.Theme.Text
	end
	activeCount.Text=binding and "[PRESS KEY]" or ("["..S.Key.Name.."]")
	menuKeyButton.Text=menuBinding and "[PRESS KEY]" or ("["..UI.MenuKey.Name.."]")
	refreshHUD()
end
syncMenuControls=function(force)
	local desired=alive and (rageGhost~=nil or driving or (UI.DisableMovement and panel.Visible))
	if controls and (force or desired~=controlsHeld) then
		local ok=pcall(function()if desired then controls:Disable() else controls:Enable() end end)
		if ok then controlsHeld=desired end
	end
end


do
-- Configurations use JSON only; no downloaded config code is executed.
local configStore={Configs={},Themes={}}
local selectedConfig,selectedTheme=nil,nil
local configFile="CombatUI-configs.json"
local persistent=type(readfile)=="function" and type(writefile)=="function"
local boolKeys={"Enabled","Aim","Lock","Sticky","TeamCheck","Skeleton","Tracer","Chams","Names","Health","ThroughWalls"}
local uiBoolKeys={"DisableMovement","Indicators","Watermark"}
local uiNumberLimits={IndicatorX={0,100},IndicatorY={0,100},WatermarkX={0,100},WatermarkY={0,100},MenuAlpha={0,.65}}
local function validName(name)
	return type(name)=="string" and #name>0 and #name<=32 and name:match("^[%w_-]+$")~=nil
end
local function snapshot()
	local data={Version=4,State={FOV=S.FOV,Smooth=S.Smooth,Part=S.Part,Center=S.Center,Key=S.Key.Name,Activation=S.Activation},
		Colors={},Interface={MenuKey=UI.MenuKey.Name,WatermarkPosition=UI.WatermarkPosition,Discord=UI.Discord},Theme={}}
	for _,key in ipairs(boolKeys) do data.State[key]=S[key] end
	for key,value in pairs(S.Colors) do data.Colors[key]=colorHex(value) end
	for _,key in ipairs(uiBoolKeys) do data.Interface[key]=UI[key] end
	for key in pairs(uiNumberLimits) do data.Interface[key]=UI[key] end
	for key,value in pairs(UI.Theme) do data.Theme[key]=colorHex(value) end
	return data
end
local function keyboardKey(name)
	if type(name)~="string" then return nil end
	local ok,key=pcall(function()return Enum.KeyCode[name]end)
	if not ok or not key or key==Enum.KeyCode.Unknown or key==Enum.KeyCode.Escape then return nil end
	if key.Name:match("^Mouse") or key.Name:match("^Button") or key.Name:match("^Thumbstick")
		or key.Name:match("^DPad") then return nil end
	return key
end
local function decodeConfig(data)
	assert(type(data)=="table" and data.Version==4,"Unsupported config version")
	assert(type(data.State)=="table" and type(data.Interface)=="table"
		and type(data.Colors)=="table" and type(data.Theme)=="table","Incomplete config")
	local clean={State={},Interface={},Colors={},Theme={}}
	for _,key in ipairs(boolKeys) do
		assert(type(data.State[key])=="boolean","Invalid switch: "..key)
		clean.State[key]=data.State[key]
	end
	for key,limits in pairs({FOV={20,600},Smooth={0,100}}) do
		local value=data.State[key]
		assert(type(value)=="number" and value==value and math.abs(value)<math.huge,"Invalid number")
		clean.State[key]=math.clamp(math.round(value),limits[1],limits[2])
	end
	assert(table.find(aimParts,data.State.Part)~=nil,"Invalid target part")
	assert(data.State.Center=="Crosshair" or data.State.Center=="Cursor","Invalid aim mode")
	clean.State.Part,clean.State.Center=data.State.Part,data.State.Center
	local mouseKeys={MouseButton1=Enum.UserInputType.MouseButton1,MouseButton2=Enum.UserInputType.MouseButton2,MouseButton3=Enum.UserInputType.MouseButton3}
    clean.State.Key=assert(mouseKeys[data.State.Key] or keyboardKey(data.State.Key),"Invalid aimbot key")
    clean.State.Activation=data.State.Activation or "Toggle"
    assert(clean.State.Activation=="Hold" or clean.State.Activation=="Toggle","Invalid activation mode")
	clean.Interface.MenuKey=assert(keyboardKey(data.Interface.MenuKey),"Invalid menu key")
	for key in pairs(S.Colors) do clean.Colors[key]=assert(parseColor(data.Colors[key]),"Invalid ESP color") end
	for key in pairs(UI.Theme) do clean.Theme[key]=assert(parseColor(data.Theme[key]),"Invalid theme color") end
	for _,key in ipairs(uiBoolKeys) do
		assert(type(data.Interface[key])=="boolean","Invalid interface switch")
		clean.Interface[key]=data.Interface[key]
	end
	for key,limits in pairs(uiNumberLimits) do
		local value=data.Interface[key]
		assert(type(value)=="number" and value==value and math.abs(value)<math.huge,"Invalid interface number")
		clean.Interface[key]=math.clamp(value,limits[1],limits[2])
	end
	assert(table.find({"Top left","Top right","Custom"},data.Interface.WatermarkPosition),"Invalid watermark position")
	clean.Interface.WatermarkPosition=data.Interface.WatermarkPosition
	assert(type(data.Interface.Discord)=="string" and #data.Interface.Discord<=256,"Invalid Discord URL")
	clean.Interface.Discord=data.Interface.Discord
	return clean
end
local function sortedKeys(map)
	local keys={}
	for key in pairs(map) do if validName(key) then table.insert(keys,key) end end
	table.sort(keys)
	return keys
end
local function updateConfigList()
	local keys=sortedKeys(configStore.Configs)
	if not selectedConfig or not configStore.Configs[selectedConfig] then selectedConfig=keys[1] end
	configSelect.Text=(selectedConfig or "none").."  >"
	storageLabel.Text=persistent and "Storage: local JSON file" or "Storage: this session only"
end
local function writeStore()
	if persistent then
		local ok=pcall(function()writefile(configFile,Http:JSONEncode(configStore))end)
		if not ok then persistent=false;note("File storage unavailable; kept in this session.") end
	end
	updateConfigList()
end
local function readStore()
	if not persistent then updateConfigList();return end
	if type(isfile)=="function" then
		local ok,exists=pcall(isfile,configFile)
		if ok and not exists then updateConfigList();return end
	end
	local ok,data=pcall(function()
		local raw=readfile(configFile)
		assert(type(raw)=="string" and #raw<=524288,"Config file too large")
		return Http:JSONDecode(raw)
	end)
	if ok and type(data)=="table" and type(data.Configs)=="table" and type(data.Themes)=="table" then
		local cleaned={Configs={},Themes={}}
		for _,category in ipairs({"Configs","Themes"}) do
			local count=0
			for name,value in pairs(data[category]) do
				if validName(name) and type(value)=="table" and count<50 then
					cleaned[category][name]=value;count=count+1
				end
			end
		end
		configStore=cleaned
	end
	updateConfigList()
end
local function saveConfig(createOnly)
	local name=configName.Text
	if not validName(name) then note("Config name: letters, numbers, _ or -; max 32.");return end
	if createOnly and configStore.Configs[name] then note("Config already exists; use Save.");return end
	if not configStore.Configs[name] and #sortedKeys(configStore.Configs)>=50 then note("Maximum 50 configs.");return end
	configStore.Configs[name]=snapshot();selectedConfig=name;writeStore()
	note(persistent and "Config saved." or "Config saved for this session.")
end
on(configSelect.Activated,function()
	local names=sortedKeys(configStore.Configs)
	if #names==0 then return end
	local index=table.find(names,selectedConfig) or 0
	selectedConfig=names[index%#names+1]
	configName.Text=selectedConfig;updateConfigList()
end)
on(settingsActions.Create.Activated,function()saveConfig(true)end)
on(settingsActions.Save.Activated,function()saveConfig(false)end)
on(settingsActions.Load.Activated,function()
	local data=selectedConfig and configStore.Configs[selectedConfig]
	if not data then note("Select a config first.");return end
	local ok,clean=pcall(decodeConfig,data)
	if not ok then note("Config rejected: "..tostring(clean));return end
	stopAll()
	for key,value in pairs(clean.State) do S[key]=value end
	for key,value in pairs(clean.Interface) do UI[key]=value end
	S.Colors=clean.Colors;UI.Theme=clean.Theme
	S.Mode=nil;stickyTarget=nil;frameMotion=Vector2.zero;mouseIntent=Vector2.zero
	binding=false;menuBinding=false;discordBox.Text=UI.Discord
	applyTheme();refresh();syncMenuControls(true)
	note("Config loaded; automation remains stopped.")
end)
on(settingsActions.Delete.Activated,function()
	if not selectedConfig then return end
	configStore.Configs[selectedConfig]=nil;selectedConfig=nil;writeStore();note("Config deleted.")
end)
on(settingsActions.Refresh.Activated,function()readStore();note("Config list refreshed.")end)

local themeLibrary=group(pages.Settings,"Custom themes",276,678,258,136)
local themeName=input(themeLibrary,"my_theme",9,14,239,20)
local themeSelect=button(themeLibrary,"none  >",9,40,239,20)
local function refreshThemes()
	local names=sortedKeys(configStore.Themes)
	if not selectedTheme or not configStore.Themes[selectedTheme] then selectedTheme=names[1] end
	themeSelect.Text=(selectedTheme or "none").."  >"
end
on(themeSelect.Activated,function()
	local names=sortedKeys(configStore.Themes)
	if #names==0 then return end
	local index=table.find(names,selectedTheme) or 0
	selectedTheme=names[index%#names+1];themeName.Text=selectedTheme;refreshThemes()
end)
button(themeLibrary,"Save theme",9,68,116,20,function()
	local name=themeName.Text
	if not validName(name) then note("Theme name: letters, numbers, _ or -.");return end
	if not configStore.Themes[name] and #sortedKeys(configStore.Themes)>=50 then note("Maximum 50 themes.");return end
	configStore.Themes[name]=snapshot().Theme;selectedTheme=name;writeStore();refreshThemes();note("Theme saved.")
end)
button(themeLibrary,"Load theme",132,68,116,20,function()
	local data=selectedTheme and configStore.Themes[selectedTheme]
	if not data then return end
	local colors={}
	for key in pairs(UI.Theme) do
		colors[key]=parseColor(data[key])
		if not colors[key] then note("Invalid theme color.");return end
	end
	UI.Theme=colors;applyTheme();refresh();note("Theme loaded.")
end)
button(themeLibrary,"Delete theme",9,95,239,20,function()
	if selectedTheme then configStore.Themes[selectedTheme]=nil;selectedTheme=nil;writeStore();refreshThemes() end
end)
on(settingsActions.Refresh.Activated,refreshThemes)
readStore();refreshThemes()
local function copyText(text)
	if type(setclipboard)~="function" then note("Clipboard is unavailable in this environment.");return false end
	local ok=pcall(setclipboard,text)
	note(ok and "Copied to clipboard." or "Clipboard request failed.")
	return ok
end
on(settingsActions.Copy.Activated,function()
	copyText('loadstring(game:HttpGet("https://raw.githubusercontent.com/pruebashacks917-bot/combat-ui/refs/heads/main/CombatMonochrome.fixed.client.luau"))()')
end)
local function discordURL()
	if UI.Discord:match("^https://discord%.gg/[%w%-]+$") or UI.Discord:match("^https://discord%.com/invite/[%w%-]+$") then return UI.Discord end
	note("Enter your own https://discord.gg/ invite first.")
	return nil
end
on(settingsActions.CopyDiscord.Activated,function()
	local url=discordURL();if url then copyText(url) end
end)
on(settingsActions.JoinDiscord.Activated,function()
	local url=discordURL();if not url then return end
	local ok=pcall(function()GuiService:OpenBrowserWindow(url)end)
	if not ok then copyText(url);note("Open the copied invite in your browser.") end
end)
on(settingsActions.Rejoin.Activated,function()
	if game.JobId=="" then note("Rejoin is available in a live server.");return end
	local ok=pcall(function()game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId,game.JobId,me)end)
	if not ok then note("The game rejected the rejoin request.") end
end)

-- HUD and menu control have their own update path, even when all features are off.
local hudClock,fpsClock,frames=0,0,0
R:BindToRenderStep("SimpleCombatHUD",Enum.RenderPriority.Last.Value,function(dt)
	if not alive then return end
	syncMenuControls()
	hudClock=hudClock+dt;fpsClock=fpsClock+dt;frames=frames+1
	if hudClock>=.1 then refreshHUD();hudClock=0 end
	if fpsClock>=.5 then
		watermarkText.Text=string.format("Combat UI | PRISON-6 | %s | %d fps",me.Name,math.round(frames/fpsClock))
		fpsClock,frames=0,0
	end
end)

end

local function updateESPCounts()
	local eligible,teammates,unready=0,0,0
	for _,p in ipairs(P:GetPlayers()) do
		if p~=me then
			if not body(p.Character) then unready=unready+1
			elseif S.TeamCheck and not me.Neutral and not p.Neutral and me.Team and p.Team==me.Team then
				teammates=teammates+1
			else eligible=eligible+1 end
		end
	end
	if espPage.Visible then
		sectionInfo.Text="ESP: "..eligible.." / TEAM EXCLUDED: "..teammates.." / NOT READY: "..unready
	else
		sectionInfo.Text=S.TeamCheck and ("TEAM CHECK ON / "..teammates.." EXCLUDED") or "AIM & AUTOMATION / ALL TEAMS"
	end
end
local espWorld=new("Folder",{Name="CombatLocalESP"},workspace)
local espRecords={}
local bonePairs={
	{"Head","UpperTorso"},{"UpperTorso","LowerTorso"},
	{"UpperTorso","LeftUpperArm"},{"LeftUpperArm","LeftLowerArm"},{"LeftLowerArm","LeftHand"},
	{"UpperTorso","RightUpperArm"},{"RightUpperArm","RightLowerArm"},{"RightLowerArm","RightHand"},
	{"LowerTorso","LeftUpperLeg"},{"LeftUpperLeg","LeftLowerLeg"},{"LeftLowerLeg","LeftFoot"},
	{"LowerTorso","RightUpperLeg"},{"RightUpperLeg","RightLowerLeg"},{"RightLowerLeg","RightFoot"},
	{"Head","Torso"},{"Torso","Left Arm"},{"Torso","Right Arm"},{"Torso","Left Leg"},{"Torso","Right Leg"}
}
local function espRecord(p)
	local record=espRecords[p]
	if record then return record end
	local container=new("Frame",{Name="ESP_"..p.UserId,Size=UDim2.fromScale(1,1),
		BackgroundTransparency=1,Visible=false},overlay)
	record={Container=container,Lines={}}
	for _,key in ipairs({"Names","Health"}) do
		record[key]=new("TextLabel",{AnchorPoint=Vector2.new(.5,1),
			Size=UDim2.fromOffset(220,16),BackgroundTransparency=1,
			Font=Enum.Font.Code,TextSize=12,TextStrokeColor3=Color3.new(0,0,0),
			TextStrokeTransparency=.15,TextColor3=S.Colors[key],Visible=false,
			TextTruncate=Enum.TextTruncate.AtEnd},container)
	end
	for i=1,#bonePairs+1 do
		record.Lines[i]=new("Frame",{AnchorPoint=Vector2.new(.5,.5),
			BorderSizePixel=0,Visible=false},container)
	end
	record.Highlight=new("Highlight",{Name="ESP_"..p.UserId,Enabled=false,
		FillTransparency=.6,OutlineTransparency=0},espWorld)
	espRecords[p]=record
	return record
end
local function removeESP(p)
	local record=espRecords[p]
	if record then
		record.Highlight:Destroy()
		record.Container:Destroy()
		espRecords[p]=nil
	end
end
on(P.PlayerRemoving,removeESP)
local function drawLine(frame,a,b,color)
	local delta=b-a
	if delta.Magnitude<.1 then frame.Visible=false; return end
	frame.Position=UDim2.fromOffset((a.X+b.X)*.5,(a.Y+b.Y)*.5)
	frame.Size=UDim2.fromOffset(delta.Magnitude,1.5)
	frame.Rotation=math.deg(math.atan2(delta.Y,delta.X))
	frame.BackgroundColor3=color
	frame.Visible=true
end
local function project(camera,position)
	local point=camera:WorldToViewportPoint(position)
	if point.Z<=.05 then return nil end
	return Vector2.new(point.X,point.Y)
end
R:BindToRenderStep("SimpleCombatESP",Enum.RenderPriority.Camera.Value+2,function()
	local camera=workspace.CurrentCamera
	if not camera or not alive then return end
	updateESPCounts()
	for _,record in pairs(espRecords) do
		record.Container.Visible=false
		record.Highlight.Enabled=false
	end
	if not S.Enabled or not (S.Skeleton or S.Tracer or S.Chams or S.Names or S.Health) then return end
	for _,p in ipairs(P:GetPlayers()) do
		if enemy(p) then
			local model=p.Character
			local _,root=body(model)
			local record=espRecord(p)
			record.Highlight.Adornee=model
			record.Highlight.Enabled=S.Chams
			record.Highlight.DepthMode=S.ThroughWalls and Enum.HighlightDepthMode.AlwaysOnTop
				or Enum.HighlightDepthMode.Occluded
			record.Highlight.FillColor=S.Colors.Chams
			record.Highlight.OutlineColor=S.Colors.Chams
			local canDraw=S.ThroughWalls or visible(camera.CFrame.Position,model)
			if canDraw then
				record.Container.Visible=true
				record.Names.Visible=false
				record.Health.Visible=false
				local h=body(model)
				local head=part(model,"Head") or root
				local anchor=project(camera,head.Position+Vector3.new(0,head.Size.Y*.5+.7,0))
				if anchor then
					record.Names.Text=p.DisplayName==p.Name and p.Name or (p.DisplayName.." (@"..p.Name..")")
					record.Names.TextColor3=S.Colors.Names
					record.Names.Position=UDim2.fromOffset(anchor.X,anchor.Y-(S.Health and 17 or 0))
					record.Names.Visible=S.Names
					record.Health.Text=string.format("%d / %d HP",math.ceil(math.max(0,h.Health)),math.ceil(h.MaxHealth))
					record.Health.TextColor3=S.Colors.Health
					record.Health.Position=UDim2.fromOffset(anchor.X,anchor.Y)
					record.Health.Visible=S.Health
				end
				for _,line in ipairs(record.Lines) do line.Visible=false end
				if S.Skeleton then
					for i,pair in ipairs(bonePairs) do
						local first,second=part(model,pair[1]),part(model,pair[2])
						if first and second then
							local a,b=project(camera,first.Position),project(camera,second.Position)
							if a and b then drawLine(record.Lines[i],a,b,S.Colors.Skeleton) end
						end
					end
				end
				if S.Tracer then
					local endpoint=project(camera,root.Position)
					if endpoint then
						drawLine(record.Lines[#bonePairs+1],
							Vector2.new(camera.ViewportSize.X*.5,16),
							endpoint,S.Colors.Tracer)
					end
				end
			end
		end
	end
end)

-- Movement

stopBot=function()
	version=version+1
	S.Mode,botTarget=nil,nil
	local h=body(me.Character)
	if h then h:Move(Vector3.zero) end
	driving=false
	syncMenuControls(true)
	refresh()
end
stopAll=function()
	rageConfig:SetAttribute("Enabled",false)
	endObserve()
	S.Enabled,target,stickyTarget=false,nil,nil
	stopBot()
	note("Detenido.")
end
local function nearestWorld(ignored)
	local _,root=body(me.Character)
	if not root then return end
	local best,dist=nil,500
	for _,p in ipairs(P:GetPlayers()) do
		if enemy(p) and (not ignored[p] or ignored[p]<os.clock()) then
			local _,other=body(p.Character)
			local d=(other.Position-root.Position).Magnitude
			if d<dist then best,dist=p,d end
		end
	end
	return best
end
local function attack(h)
	local c=me.Character
	if not c then return false end
	local tool=c:FindFirstChildOfClass("Tool")
	if not tool then
		local bag=me:FindFirstChildOfClass("Backpack")
		tool=bag and bag:FindFirstChildOfClass("Tool")
		if tool then h:EquipTool(tool) end
	end
	if not tool then return false end
	if not tool.Enabled then return true end
	return pcall(function() tool:Activate() end)
end
local function startBot(mode)
	if S.Mode==mode then stopBot(); return end
	stopBot()
	if not controls or not body(me.Character) then
		note("Personaje o controles no disponibles."); return
	end
	if not pcall(function() controls:Disable() end) then
		note("No se pudo controlar al personaje."); return
	end
	driving,S.Enabled,S.Mode=true,true,mode
	local token,queue,ignored=version,{},{}
	if mode=="All" then
		for _,p in ipairs(P:GetPlayers()) do
			if enemy(p) then table.insert(queue,p) end
		end
	end
	refresh()
	task.spawn(function()
		local current,points,index=nil,nil,2
		local nextPath,lastAttack,lastProgress=0,0,os.clock()
		local lastPosition,attackStart=nil,nil
		local function active()
			return alive and S.Enabled and S.Mode==mode and version==token
		end
		local function skip()
			if current then
				ignored[current]=os.clock()+8
				if mode=="All" and queue[1]==current then table.remove(queue,1) end
			end
			current,botTarget,points,attackStart=nil,nil,nil,nil
		end
		local ok,err=pcall(function()
			while active() do
				local h,root=body(me.Character)
				if not h or h.Sit then break end
				if current and not enemy(current) then skip() end
				if not current then
					if mode=="All" then
						while queue[1] and not enemy(queue[1]) do table.remove(queue,1) end
						current=queue[1]
						if not current then note("Recorrido terminado."); break end
					else current=nearestWorld(ignored) end
					botTarget,lastPosition,lastProgress=current,root.Position,os.clock()
					nextPath,points,attackStart=0,nil,nil
				end
				if current then
					local _,other=body(current.Character)
					if not other then skip() else
						local now=os.clock()
						local near=(other.Position-root.Position).Magnitude<=6
						if near and visible(root.Position,current.Character) then
							h:Move(Vector3.zero)
							points,lastProgress=nil,now
							attackStart=attackStart or now
							if now-lastAttack>=.25 then
								lastAttack=now
								if not attack(h) then note("Necesitas un arma Tool compatible.") end
							end
							if now-attackStart>15 then skip() end
						else
							attackStart=nil
							if (root.Position-lastPosition).Magnitude>1 then
								lastPosition,lastProgress=root.Position,now
							end
							if now-lastProgress>5 then skip(); h:Move(Vector3.zero)
							else
								if now>=nextPath then
									nextPath=now+1.2
									local path=PF:CreatePath({AgentRadius=2,AgentHeight=5,
										AgentCanJump=true,WaypointSpacing=4})
									local computed=pcall(function()
										path:ComputeAsync(root.Position,other.Position)
									end)
									if not active() then return end
									if computed and path.Status==Enum.PathStatus.Success then
										points,index=path:GetWaypoints(),2
									else skip(); h:Move(Vector3.zero) end
								end
								if points then
									local point=points[index]
									if point then
										local d=point.Position-root.Position
										if Vector2.new(d.X,d.Z).Magnitude<2.5 and math.abs(d.Y)<5 then
											index=index+1; point=points[index]
										end
									end
									if point then
										if point.Action==Enum.PathWaypointAction.Jump then h.Jump=true end
										h:MoveTo(point.Position)
									else nextPath=0 end
								end
							end
						end
					end
				else h:Move(Vector3.zero) end
				task.wait(.1)
			end
		end)
		if not ok then warn("Combat UI: "..tostring(err)); note("Autoplay detenido por un error.") end
		if version==token then stopBot() end
	end)
end

-- Keyboard binding and draggable header.
local function toggleAim()
	stickyTarget=nil; mouseIntent=Vector2.zero; frameMotion=Vector2.zero
	local effective=S.Enabled and (S.Aim or S.Mode~=nil)
	S.Aim=not effective
	if S.Aim then S.Enabled=true else target=nil; stopBot() end
	refresh()
	note(S.Aim and "Aimbot ON" or "Aimbot OFF")
end
on(activeCount.Activated,function()
	binding=not binding; menuBinding=false
	refresh()
	note(binding and "Pulsa la tecla que quieras. Escape cancela; mouse permitido." or "Asignacion cancelada.")
end)
local dragHeader=new("Frame",{Position=UDim2.fromOffset(7,3),
	Size=UDim2.fromOffset(480,21),BackgroundTransparency=1,Active=true,ZIndex=10},panel)
local dragInput,dragStart,dragPosition
on(dragHeader.InputBegan,function(input)
	if input.UserInputType==Enum.UserInputType.MouseButton1
		or input.UserInputType==Enum.UserInputType.Touch then
		dragInput,dragStart,dragPosition=input,input.Position,panel.Position
	end
end)
on(U.InputChanged,function(input)
	if not dragInput then return end
	local mouse=dragInput.UserInputType==Enum.UserInputType.MouseButton1
	if input~=dragInput and not (mouse and input.UserInputType==Enum.UserInputType.MouseMovement) then return end
	local delta=input.Position-dragStart
	local area=gui.AbsoluteSize
	local size=panel.AbsoluteSize
	local x=dragPosition.X.Scale*area.X+dragPosition.X.Offset+delta.X
	local y=dragPosition.Y.Scale*area.Y+dragPosition.Y.Offset+delta.Y
	x=math.clamp(x,6,math.max(6,area.X-size.X-6))
	y=math.clamp(y,size.Y*.5+6,math.max(size.Y*.5+6,area.Y-size.Y*.5-6))
	panel.Position=UDim2.fromOffset(x,y)
end)
on(U.InputEnded,function(input)
	if input==dragInput or (dragInput and
		dragInput.UserInputType==Enum.UserInputType.MouseButton1 and
		input.UserInputType==Enum.UserInputType.MouseButton1) then dragInput=nil end
end)

-- Buttons
on(emergency.Activated,stopAll)
on(sticky.Activated,function() S.Sticky=not S.Sticky; stickyTarget=nil; refresh() end)
on(buttons.Enabled.Activated,function()
	S.Enabled=not S.Enabled
	if not S.Enabled then target=nil; stickyTarget=nil; stopBot() end
	refresh()
end)
on(buttons.Aim.Activated,toggleAim)
on(buttons.Lock.Activated,function() S.Lock=not S.Lock; refresh() end)
on(kill.Activated,function() startBot("All") end)
on(auto.Activated,function() startBot("Auto") end)
togglePanel=function()
	closeDropdown()
	panel.Visible=not panel.Visible
	open.Visible=not panel.Visible
	syncMenuControls(true)
end
on(hide.Activated,togglePanel)
on(open.Activated,togglePanel)
on(close.Activated,function() gui:Destroy() end)
local function matchesAim(input)
    return input.KeyCode==S.Key or input.UserInputType==S.Key
end
on(U.InputBegan,function(input,processed)
    if input.KeyCode==Enum.KeyCode.Escape then
        closeDropdown()
        targetBinding=false;rageBinding=false;endObserve()
        binding=false;menuBinding=false;heldAim=false;S.Aim=false;stopAll();refresh();return
    end
    if U:GetFocusedTextBox() then return end
    if rageBinding then
        if input.UserInputType==Enum.UserInputType.Keyboard and input.KeyCode~=Enum.KeyCode.Unknown then
            if input.KeyCode==S.Key or input.KeyCode==UI.MenuKey or input.KeyCode==Enum.KeyCode.Backspace or input.KeyCode.Name==rageConfig:GetAttribute("TargetKey") then
                note("Tecla ocupada. Elige una diferente.");return
            end
            rageConfig:SetAttribute("RageKey",input.KeyCode.Name);rageBinding=false
        end
        return
    end
    if not binding and not menuBinding and not targetBinding and not GuiService.MenuIsOpen
        and input.UserInputType==Enum.UserInputType.Keyboard and input.KeyCode.Name==rageConfig:GetAttribute("RageKey") then
        local enable=not rageConfig:GetAttribute("Enabled")
        if enable and not selectedPlayer() then note("Selecciona un objetivo primero.");return end
        rageConfig:SetAttribute("Enabled",enable)
        if not enable then endObserve() end
        note(enable and "Rage ON" or "Rage OFF");refresh();return
    end
    if targetBinding then
        if input.UserInputType==Enum.UserInputType.Keyboard and input.KeyCode~=Enum.KeyCode.Unknown then
            if input.KeyCode==S.Key or input.KeyCode==UI.MenuKey or input.KeyCode==Enum.KeyCode.Backspace or input.KeyCode.Name==rageConfig:GetAttribute("RageKey") then
                note("Elige otra tecla: esa activa Aimbot, el menu o Stop All.");return
            end
            rageConfig:SetAttribute("TargetKey",input.KeyCode.Name);targetBinding=false
        end
        return
    end
    if input.UserInputType==Enum.UserInputType.Keyboard and input.KeyCode.Name==rageConfig:GetAttribute("TargetKey")
        and not binding and not menuBinding and not GuiService.MenuIsOpen then
        local hit=me:GetMouse().Target
        local chosen=nil
        while hit and hit~=workspace do
            if hit:IsA("Model") then chosen=P:GetPlayerFromCharacter(hit);if chosen then break end end
            hit=hit.Parent
        end
        if chosen and chosen~=me and body(chosen.Character) then
            if rageConfig:GetAttribute("TeamCheck") and me.Team and me.Team==chosen.Team and not me.Neutral and not chosen.Neutral then
                note("Team Check excluye a ese jugador.");return
            end
            selectRageTarget(chosen)
            rageConfig:SetAttribute("Selection","Manual")
            note("Objetivo seleccionado: "..chosen.Name);refresh()
        else note("Pon el mouse directamente sobre un jugador vivo.") end
        return
    end
    if menuBinding then
        if input.UserInputType==Enum.UserInputType.Keyboard and input.KeyCode~=Enum.KeyCode.Unknown then
            if input.KeyCode.Name==rageConfig:GetAttribute("TargetKey") or input.KeyCode.Name==rageConfig:GetAttribute("RageKey") then note("Esa tecla pertenece a Target Selection.");return end
            UI.MenuKey=input.KeyCode;menuBinding=false;refresh()
        end
        return
    end
    if binding then
        local kind=input.UserInputType
        if kind==Enum.UserInputType.Keyboard and (input.KeyCode.Name==rageConfig:GetAttribute("TargetKey") or input.KeyCode.Name==rageConfig:GetAttribute("RageKey")) then
            note("Esa tecla pertenece a Target Selection. Elige otra.");return
        end
        if kind==Enum.UserInputType.Keyboard and input.KeyCode~=Enum.KeyCode.Unknown then S.Key=input.KeyCode
        elseif kind==Enum.UserInputType.MouseButton1 or kind==Enum.UserInputType.MouseButton2 or kind==Enum.UserInputType.MouseButton3 then S.Key=kind
        else return end
        binding=false;heldAim=false;S.Aim=false;refresh();return
    end
    if GuiService.MenuIsOpen then return end
    if matchesAim(input) then
        -- Ignore clicks on our interface without consuming weapon input.
        if input.UserInputType~=Enum.UserInputType.Keyboard then
            local pos=U:GetMouseLocation()
            for _,item in ipairs(pg:GetGuiObjectsAtPosition(pos.X,pos.Y)) do
                if item:IsDescendantOf(gui) then return end
            end
        end
        if S.Activation=="Hold" then heldAim=true;S.Enabled=true;S.Aim=true;refresh()
        else toggleAim() end
        return
    end
    if processed then return end
    if input.KeyCode==Enum.KeyCode.Backspace then heldAim=false;S.Aim=false;stopAll()
    elseif input.KeyCode==UI.MenuKey then togglePanel() end
end)
on(U.InputEnded,function(input)
    if heldAim and matchesAim(input) then
        heldAim=false;S.Aim=false;target=nil;stickyTarget=nil;stopBot();refresh()
    end
end)
on(U.WindowFocusReleased,function()
    heldAim=false;S.Aim=false;stopAll();refresh()
end)
on(U.InputChanged,function(input)
	if input.UserInputType==Enum.UserInputType.MouseMovement
		and not binding and not menuBinding and not dragInput and not U:GetFocusedTextBox()
		and not GuiService.MenuIsOpen then
		local delta=Vector2.new(input.Delta.X,input.Delta.Y)
		if os.clock()<injectionExpires and (delta-injectedMotion).Magnitude<=2 then
			injectedMotion=Vector2.zero
		else frameMotion=frameMotion+delta end
	end
end)

on(me.CharacterRemoving,function() target=nil; stickyTarget=nil; stopBot() end)

-- Screen-space selection with visibility and direct-reticle priority.
local function chooseCandidate(candidates,radius,locked)
	local best
	for _,c in ipairs(candidates) do
		if c.Visible and c.Score<=radius then
			if locked and c.Player==locked then return c end
			if not best or (c.Direct and not best.Direct)
				or (c.Direct==best.Direct and (c.Score<best.Score
				or (c.Score==best.Score and c.Depth<best.Depth))) then best=c end
		end
	end
	return best
end

local function pickClosest(camera,center,intentSwitch)
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances=me.Character and {me.Character,camera} or {camera}
	local origin=camera.CFrame.Position
	local function clearAt(model,position)
		local hit=workspace:Raycast(origin,position-origin,params)
		return not hit or hit.Instance:IsDescendantOf(model)
	end
	-- Latch one character for this activation. Cursor movement and FOV edges
	-- cannot silently replace it with another player.
	if stickyTarget then
		if not enemy(stickyTarget) then
			stickyTarget=nil;randomModel=nil;randomPart=nil
			return nil,nil,nil
		end
		local selected=aimPart(stickyTarget.Character)
		if selected then
			local screen=camera:WorldToViewportPoint(selected.Position)
			if screen.Z>0 and clearAt(stickyTarget.Character,selected.Position) then
				return stickyTarget,selected,0
			end
		end
		return stickyTarget,nil,nil
	end
	local ray=camera:ViewportPointToRay(center.X,center.Y)
	local hit=workspace:Raycast(ray.Origin,ray.Direction*10000,params)
	local direct
	if hit then
		local ancestor=hit.Instance
		while ancestor and ancestor~=workspace do
			if ancestor:IsA("Model") then
				direct=P:GetPlayerFromCharacter(ancestor)
				if direct then break end
			end
			ancestor=ancestor.Parent
		end
	end
	local candidates={}
	for _,p in ipairs(P:GetPlayers()) do
		if enemy(p) then
			local model=p.Character
			do
				local _,root=body(model)
				local score=math.huge
				-- Detect the character's visible body area, independently of Head/Torso aim.
				if p==direct then score=0
				else
					for _,limb in ipairs(model:GetDescendants()) do
						if limb:IsA("BasePart") and limb.Name~="HumanoidRootPart"
							and not limb:FindFirstAncestorWhichIsA("Accessory") and not limb:FindFirstAncestorWhichIsA("Tool")
							and limb.Transparency<1 and clearAt(model,limb.Position) then
							local minX,minY,maxX,maxY=math.huge,math.huge,-math.huge,-math.huge
							local inFront=true
							local half=limb.Size*.5
							for x=-1,1,2 do for y=-1,1,2 do for z=-1,1,2 do
								local corner=limb.CFrame:PointToWorldSpace(Vector3.new(half.X*x,half.Y*y,half.Z*z))
								local screen=camera:WorldToViewportPoint(corner)
								if screen.Z<=0 then inFront=false end
								minX,minY=math.min(minX,screen.X),math.min(minY,screen.Y)
								maxX,maxY=math.max(maxX,screen.X),math.max(maxY,screen.Y)
							end end end
							if inFront and maxX>=0 and maxY>=0
								and minX<=camera.ViewportSize.X and minY<=camera.ViewportSize.Y then
								local closest=Vector2.new(math.clamp(center.X,minX,maxX),
									math.clamp(center.Y,minY,maxY))
								score=math.min(score,(closest-center).Magnitude)
							end
						end
					end
				end
				if score<=S.FOV then
					table.insert(candidates,{Player=p,Score=score,
						Depth=(root.Position-origin).Magnitude,Visible=true,Direct=p==direct})
				end
			end
		end
	end
	local keepCurrent=S.Sticky or not intentSwitch
	local chosen=chooseCandidate(candidates,S.FOV,keepCurrent and stickyTarget or nil)
	stickyTarget=chosen and chosen.Player or nil
	if chosen then
		-- Head/Torso is resolved ONLY AFTER selecting the player.
		-- An unavailable or blocked aim part never substitutes a different player.
		local requested=aimPart(chosen.Player.Character)
		local point=nil
		if requested then
			local screen=camera:WorldToViewportPoint(requested.Position)
			if screen.Z>0 and clearAt(chosen.Player.Character,requested.Position) then point=requested end
		end
		return chosen.Player,point,chosen.Score
	end
	return nil,nil,nil
end


local function aimAlpha(smooth,instant,manual,dt)
	-- User input always takes priority, including with Sticky or Direct aim.
	if manual then return 1-math.exp(-dt*.6) end
	local seconds=.08+smooth/100*.45
	return 1-math.exp(-dt/(instant and .06 or seconds))
end

-- Mouse output never writes Camera.CFrame.
local mouseFeedback=nil
local mouseFault=nil
local function applyMouseAim(camera,point,alpha)
	if mouseFault then return mouseFault end
	if U.MouseBehavior~=Enum.MouseBehavior.Default
		or U:IsMouseButtonPressed(Enum.UserInputType.MouseButton2)
		or U:IsMouseButtonPressed(Enum.UserInputType.MouseButton3) then
		return "Mouse bloqueado por el juego; necesita cursor libre."
	end
	if type(mousemoverel)~="function" then
		return "Este entorno no permite mover el cursor."
	end
	local screen,onScreen=camera:WorldToViewportPoint(point.Position)
	if not onScreen or screen.Z<=0 then return nil end
	local cursor=U:GetMouseLocation()
	local errorVector=Vector2.new(screen.X,screen.Y)-cursor
	if mouseFeedback and mouseFeedback.Point==point then
		local actual=cursor-mouseFeedback.Cursor
		local requested=mouseFeedback.Requested
		local blocked=requested.Magnitude>=2 and actual.Magnitude<.25
		local diverging=errorVector.Magnitude>mouseFeedback.Error+6
		local reversed=actual.Magnitude>1 and actual:Dot(requested)<0
		local failures=(blocked or diverging or reversed) and mouseFeedback.Failures+1 or 0
		if failures>=3 then
			mouseFault="Mouse sin respuesta estable. Suelta el boton; el juego puede controlar la mira."
			injectedMotion=Vector2.zero
			return mouseFault
		end
		mouseFeedback.Failures=failures
	end
	-- Relative input can be amplified by the host. Damped, bounded corrections
	-- avoid alternating full-distance overshoots; no saved cursor is restored.
	local delta=errorVector*math.min(alpha,.35)
	if delta.Magnitude>24 then delta=delta.Unit*24 end
	local dx,dy=math.round(delta.X),math.round(delta.Y)
	if dx==0 and dy==0 then return nil end
	injectedMotion=Vector2.new(dx,dy)
	injectionExpires=os.clock()+.08
	local ok=pcall(mousemoverel,dx,dy)
	if not ok then injectedMotion=Vector2.zero; return "El entorno rechazo el movimiento del mouse." end
	mouseFeedback={Point=point,Cursor=cursor,Requested=Vector2.new(dx,dy),
		Error=errorVector.Magnitude,Failures=mouseFeedback and mouseFeedback.Point==point and mouseFeedback.Failures or 0}
	return nil
end

-- Prison Life attribute/GunRemotes adapter, based on the supplied Hybrid script.
do
 local RS=game:GetService("ReplicatedStorage")
 local originals=setmetatable({},{__mode="k"})
 local currentTool,currentPlayer,currentPart=nil,nil,nil
 local acquiredAt,nextShot,nextScan=0,0,0
 local rayOriginal,rayHook,rayFunction
 local hookState="Silent: sin comprobar"
 local running=true
 local randomChoice,randomOwner
 local function active()
  return alive and running and rageConfig:GetAttribute("Enabled") and (not observing or rageGhost~=nil)
   and not GuiService.MenuIsOpen and not U:GetFocusedTextBox()
 end
 local function restore(tool,record)
  for key,value in pairs(record.Applied) do
   if tool:GetAttribute(key)==value then tool:SetAttribute(key,record.Original[key]) end
  end
  table.clear(record.Applied)
 end
 local function modify(tool)
  local record=originals[tool]
  if not record then record={Original={},Applied={}};originals[tool]=record end
  local wanted={}
  local rate=tool:GetAttribute("FireRate")
  if type(rate)=="number" and rate>0 then
   record.Original.FireRate=record.Original.FireRate or rate
   local multiplier=math.clamp(rageConfig:GetAttribute("FireRatePercent") or 100,25,200)/100
   if rageConfig:GetAttribute("RapidFire") then multiplier=math.max(2,multiplier) end
   if multiplier~=1 then wanted.FireRate=math.max(.01,record.Original.FireRate/multiplier) end
  end
  if rageConfig:GetAttribute("NoSpread") and type(tool:GetAttribute("Spread"))=="number" then
   if record.Original.Spread==nil then record.Original.Spread=tool:GetAttribute("Spread") end
   wanted.Spread=0
  end
  if rageConfig:GetAttribute("FullAuto") and type(tool:GetAttribute("AutoFire"))=="boolean" then
   if record.Original.AutoFire==nil then record.Original.AutoFire=tool:GetAttribute("AutoFire") end
   wanted.AutoFire=true
  end
  for key,value in pairs(record.Applied) do
   if wanted[key]==nil then
    if tool:GetAttribute(key)==value then tool:SetAttribute(key,record.Original[key]) end
    record.Applied[key]=nil
   end
  end
  for key,value in pairs(wanted) do tool:SetAttribute(key,value);record.Applied[key]=value end
 end
 local function eligible(p)
  if not p or p==me or p.Parent~=P or not body(p.Character) then return false end
  if rageConfig:GetAttribute("TeamCheck") and me.Team and me.Team==p.Team and not me.Neutral and not p.Neutral then return false end
  return not (rageConfig:GetAttribute("IgnoreProtected") and p.Character:FindFirstChildOfClass("ForceField"))
 end
 local function pickPart(p,camera)
  local names=limbNames[rageConfig:GetAttribute("Hitbox")]
  if names and not rageConfig:GetAttribute("ClosestPart") then
   for _,name in ipairs(names) do local found=part(p.Character,name);if found then return found end end
   return nil
  end
  local available={}
  for _,list in pairs(limbNames) do
   for _,name in ipairs(list) do local found=part(p.Character,name);if found then table.insert(available,found);break end end
  end
  if #available==0 then return nil end
  if rageConfig:GetAttribute("ClosestPart") then
   local best,score=nil,math.huge
   for _,limb in ipairs(available) do
    local pos,shown=camera:WorldToViewportPoint(limb.Position)
    local d=(Vector2.new(pos.X,pos.Y)-camera.ViewportSize*.5).Magnitude
    if shown and d<score then best,score=limb,d end
   end
   return best
  end
  if randomOwner~=p or not randomChoice or not randomChoice:IsDescendantOf(p.Character) then
   randomOwner=p;randomChoice=available[math.random(#available)]
  end
  return randomChoice
 end
 local function clear(p,limb,camera)
  local params=RaycastParams.new();params.FilterType=Enum.RaycastFilterType.Exclude
  local ignored={me.Character,camera}
  if rageGhost then table.insert(ignored,rageGhost) end
  params.FilterDescendantsInstances=ignored
  local head=part(me.Character,"Head")
  local origin=rageGhost and head and head.Position or camera.CFrame.Position
  local hit=workspace:Raycast(origin,limb.Position-origin,params)
  return not hit or hit.Instance:IsDescendantOf(p.Character)
 end
 local function candidate(p,camera,manual)
  if not eligible(p) then return nil end
  local limb=pickPart(p,camera);if not limb then return nil end
  local distance=(limb.Position-camera.CFrame.Position).Magnitude
  if rageConfig:GetAttribute("LimitDistance") and distance>rageConfig:GetAttribute("MaxDistance") then return nil end
  local screen,shown=camera:WorldToViewportPoint(limb.Position)
  local score=(Vector2.new(screen.X,screen.Y)-camera.ViewportSize*.5).Magnitude
  if not manual and not rageConfig:GetAttribute("Aim360") and (not shown or score>rageConfig:GetAttribute("FOV")) then return nil end
  if rageConfig:GetAttribute("VisibilityCheck") and not clear(p,limb,camera) then return nil end
  local criterion=rageConfig:GetAttribute("Selection")
  if criterion=="Distance" then score=distance elseif criterion=="Health" then local h=body(p.Character);score=h.Health end
  return limb,score
 end
 local function acquire(camera)
  if rageConfig:GetAttribute("Selection")=="Manual" then
   local p=selectedPlayer();local limb=candidate(p,camera,true)
   return limb and p or nil,limb
  end
  if currentPlayer then
   local limb=candidate(currentPlayer,camera,true)
   if limb then return currentPlayer,limb end
   if not rageConfig:GetAttribute("AutoSwitch") then return nil end
  end
  local best,selected,score=nil,nil,math.huge
  for _,p in ipairs(P:GetPlayers()) do
   local limb,d=candidate(p,camera,false)
   if limb and d<score then best,selected,score=p,limb,d end
  end
  return best,selected
 end
 local function installHook()
  if rayOriginal or type(hookfunction)~="function" then
   if not rayOriginal then hookState="Silent: hookfunction no disponible" end
   return
  end
  local found
  if type(filtergc)=="function" then
   local ok,result=pcall(filtergc,"function",{Name="castRay"},true)
   if ok then found=type(result)=="function" and result or type(result)=="table" and result[1] end
  end
  if not found and type(getgc)=="function" then
   local ok,items=pcall(getgc,true)
   if ok then for _,fn in pairs(items) do
    if type(fn)=="function" then
     local success,name=pcall(function()return debug.info(fn,"n")end)
     if success and name=="castRay" then found=fn;break end
    end
   end end
  end
  if type(found)~="function" then hookState="Silent: castRay no encontrado";return end
  rayHook=function(...)
   if active() and rageConfig:GetAttribute("SilentAim") and (rageConfig:GetAttribute("HitChance") or 0)==0 and currentPart and eligible(currentPlayer)
    and currentPart:IsDescendantOf(currentPlayer.Character) and os.clock()-acquiredAt>=(rageConfig:GetAttribute("ReactionTime") or 0) then
    local camera=workspace.CurrentCamera
    if camera and (not rageConfig:GetAttribute("VisibilityCheck") or clear(currentPlayer,currentPart,camera)) then
     return currentPart,currentPart.Position
    end
   end
   return rayOriginal(...)
  end
  local ok,original=pcall(hookfunction,found,rayHook)
  if ok and type(original)=="function" then rayOriginal=original;rayFunction=found;hookState="Silent: castRay conectado (sin validar impactos)"
  else hookState="Silent: no se pudo conectar" end
 end
 on(R.RenderStepped,function()
  if RS:GetAttribute("CombatWeaponProtocol")==2 then return end -- Existing private kit owns its output.
  local tool=me.Character and me.Character:FindFirstChildOfClass("Tool")
  local remotes=RS:FindFirstChild("GunRemotes")
  local shoot=remotes and remotes:FindFirstChild("ShootEvent")
  local compatible=tool and tool:GetAttribute("ToolType")=="Gun" and shoot and shoot:IsA("RemoteEvent")
  if not compatible or not active() then
   for weapon,record in pairs(originals) do if weapon.Parent then restore(weapon,record) end end
   currentTool,currentPlayer,currentPart=nil,nil,nil
   prisonStatus=compatible and "Prison Life: detectado / pausado" or "Prison Life: equipa arma ToolType=Gun + GunRemotes"
   return
  end
  if tool~=currentTool then
   for weapon,record in pairs(originals) do if weapon.Parent then restore(weapon,record) end end
   currentTool=tool;nextShot=0
  end
  modify(tool)
  local camera=workspace.CurrentCamera;if not camera then return end
  local p,limb=acquire(camera)
  if p~=currentPlayer then acquiredAt=os.clock() end
  local retained=currentPlayer
  currentPlayer,currentPart=p,limb
  if not p and retained and not rageConfig:GetAttribute("AutoSwitch") and rageConfig:GetAttribute("Selection")~="Manual" then
   currentPlayer=retained
  end
  prisonStatus="Prison Life: atributos + ShootEvent detectados"
  if rageConfig:GetAttribute("SilentAim") then
   if os.clock()>=nextScan then nextScan=os.clock()+5;task.spawn(installHook) end
   prisonStatus=hookState
   if (rageConfig:GetAttribute("HitChance") or 0)>0 then prisonStatus="Silent pausado: Hit Chance no estimable; usa 0" end
  end
  if not limb or os.clock()-acquiredAt<(rageConfig:GetAttribute("ReactionTime") or 0) then return end
  local point=limb.Position
  if rageConfig:GetAttribute("Prediction") then point+=limb.AssemblyLinearVelocity*(rageConfig:GetAttribute("PredictionTime") or 0) end
  if not observing and not rageGhost and rageConfig:GetAttribute("Aimbot") and not rageConfig:GetAttribute("SilentAim") then
   if (point-camera.CFrame.Position).Magnitude>.001 then camera.CFrame=CFrame.lookAt(camera.CFrame.Position,point) end
  end
  if not rageConfig:GetAttribute("AutoShoot") or os.clock()<nextShot then return end
  local ammo=tool:GetAttribute("Local_CurrentAmmo") or tool:GetAttribute("CurrentAmmo")
  if type(ammo)~="number" or ammo<=0 then prisonStatus="Prison Life: sin municion o atributo desconocido";return end
  if (rageConfig:GetAttribute("HitChance") or 0)>0 then
   prisonStatus="Hit Chance: estimacion no disponible para esta arma; usa 0";return
  end
  local head=part(me.Character,"Head");if not head then return end
  local bullets=math.clamp(math.floor(tonumber(tool:GetAttribute("ProjectileCount")) or 1),1,20)
  local payload={}
  for i=1,bullets do payload[i]={head.Position,point,limb} end
  nextShot=os.clock()+math.max(.05,tonumber(tool:GetAttribute("FireRate")) or .12)
  local ok=pcall(function()shoot:FireServer(payload)end)
  if ok then tool:SetAttribute("Local_CurrentAmmo",math.max(0,ammo-1)) else prisonStatus="ShootEvent rechazo la llamada local" end
 end)
 on(gui.Destroying,function()
  running=false;currentPart=nil;currentPlayer=nil
  for weapon,record in pairs(originals) do if weapon.Parent then restore(weapon,record) end end
  -- The hook becomes a pass-through. Restoring blindly could overwrite another script's hook.
 end)
end

-- Aimbot: immediate acquisition with mouse-intent retargeting.
R:BindToRenderStep("SimpleCombatAim",Enum.RenderPriority.Camera.Value+1,function(dt)
	local camera=workspace.CurrentCamera
	if not alive or not camera then return end
	if not S.Enabled or not (S.Aim or S.Mode) or S.Center~="Cursor" then
		mouseFeedback=nil;mouseFault=nil
	end
	scale.Scale=math.max(.3,math.min(1,
		(camera.ViewportSize.Y-70)/620,(camera.ViewportSize.X-40)/560))
	if not UI.Placed then
        local width=560*scale.Scale
        panel.Position=UDim2.new(0,math.clamp((camera.ViewportSize.X-width)*.5+100,10,math.max(10,camera.ViewportSize.X-width-10)),.5,0)
        UI.Placed=true
    end
    local currentMotion=frameMotion
	frameMotion=Vector2.zero
	mouseIntent=mouseIntent*math.exp(-dt/0.08)+currentMotion
	if currentMotion.Magnitude>.5 then manualUntil=os.clock()+.12 end
	local manualMove=os.clock()<manualUntil
	local intentSwitch=not S.Sticky and mouseIntent.Magnitude>=28
	if intentSwitch then mouseIntent=Vector2.zero end
	local center=S.Center=="Cursor" and U:GetMouseLocation() or camera.ViewportSize*.5
	circle.Position=UDim2.fromOffset(center.X,center.Y)
	circle.Size=UDim2.fromOffset(S.FOV*2,S.FOV*2)
	circle.Visible=S.Enabled
	local selected=nil
	target=nil
	if not observing and not rageConfig:GetAttribute("Enabled") and S.Enabled and (S.Aim or S.Mode~=nil) and body(me.Character)
		and not binding and not menuBinding and not dragInput and not GuiService.MenuIsOpen and not U:GetFocusedTextBox() then
		target,selected=pickClosest(camera,center,intentSwitch)
	else stickyTarget=nil; mouseIntent=Vector2.zero
	end
	 local aimIssue=nil
	-- Revalidate immediately before output; never steer toward a dead character.
	if target and not enemy(target) then
		target,selected,stickyTarget=nil,nil,nil
		randomModel,randomPart=nil,nil
	end
	if selected and (selected.Position-camera.CFrame.Position).Magnitude>.01 then
		local alpha=1
		if S.Center=="Cursor" then
			aimIssue=applyMouseAim(camera,selected,alpha)
		else
			-- Translation/jumping must not introduce smoothing lag off the reticle.
			-- Deliberate mouse input still receives the reduced assistance above.
			if not manualMove then alpha=1 end
			local ray=camera:ViewportPointToRay(center.X,center.Y)
			local localRay=camera.CFrame:VectorToObjectSpace(ray.Direction)
			local correction=CFrame.lookAt(Vector3.zero,localRay):Inverse()
			local goal=CFrame.lookAt(camera.CFrame.Position,selected.Position)*correction
			camera.CFrame=camera.CFrame:Lerp(goal,alpha)
		end
	end
	 stroke.Color=target and UI.Theme.Accent or UI.Theme.Muted
	if os.clock()<messageUntil then status.Text=message
	elseif aimIssue then status.Text=aimIssue
	elseif not S.Enabled then status.Text="Desactivado"
	elseif target and not selected then status.Text=S.Part.." oculto: "..target.Name
	elseif target then status.Text="Objetivo: "..target.Name.." | "..S.Part
	elseif S.Mode then status.Text=botTarget and ("Buscando: "..botTarget.Name) or "Buscando objetivos..."
	elseif S.Aim then status.Text="Sin objetivo visible dentro del FOV"
	else status.Text="Activa Aimbot o Autoplay" end
end)

on(gui.Destroying,function()
	if not alive then return end
	alive,S.Enabled=false,false
	stopBot()
	R:UnbindFromRenderStep("SimpleCombatAim")
	R:UnbindFromRenderStep("SimpleCombatESP")
	R:UnbindFromRenderStep("SimpleCombatHUD")
	espWorld:Destroy()
	for _,c in ipairs(links) do c:Disconnect() end
	overlay:Destroy()
end)
refresh()
