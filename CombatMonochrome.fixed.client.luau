-- VERSION 4.1: body-based player selection, then independent Head/Torso aiming.
-- COMBAT UI: siempre selecciona al jugador mas cercano a la mira dentro del FOV.
-- Target lock ON = apuntado directo; OFF = usa Smoothness.
-- Sticky OFF: holds the current valid target through jitter; deliberate mouse movement permits retargeting.

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
S.Noclip=false
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
local title=label(panel,"kurnio.wtf | review-1",9,4,410,19,12)
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
local open=button(gui,"kurnio.wtf [+]",18,100,116,23)
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

for i,name in ipairs({"Aimbot","ESP","Rage Bot","Armas","Jugador","Settings"}) do
	local page=new("ScrollingFrame",{Name=name,Position=UDim2.fromOffset(9,62),
		Size=UDim2.fromOffset(542,510),BackgroundTransparency=1,BorderSizePixel=0,
		ScrollBarThickness=3,CanvasSize=UDim2.fromOffset(0,name=="Settings" and 824 or name=="Rage Bot" and 1540 or 510),
		ScrollingDirection=Enum.ScrollingDirection.Y,Visible=name==UI.Tab},panel)
	theme(page,"ScrollBarImageColor3","Accent")
	pages[name]=page
	local tab=button(panel,name,9+(i-1)*88,35,83,21,function()
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
local c=group(pages.Aimbot,"Targeting",4,257,258,146)
number(c,"FOV radius (px)",9,15,239,function()return S.FOV end,function(v)S.FOV=math.round(v)end,20,600)
number(c,"Smoothness",9,58,239,function()return S.Smooth end,function(v)S.Smooth=math.round(v)end,0,100)
check(c,"Team check",8,106,240,function()return S.TeamCheck end,
	function(v)S.TeamCheck=v;stickyTarget=nil;target=nil end)
local d=group(pages.Aimbot,"Information",276,191,258,126)
label(d,"Stable lock; strong mouse to switch.",9,13,239,18,11,"Muted")
label(d,"Target part is independent.",9,34,239,18,11,"Muted")
label(d,"Mouse mode centers on the cursor.",9,55,239,18,11,"Muted")
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
settingsActions.Copy=button(main,"Copy game link",9,90,239,20)
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

local rageConfig=new("Folder",{Name="SpectatorSettings"},gui)
rageConfig:SetAttribute("TargetKey","Sin asignar")
local targetBinding=false
local targetControls=group(pages["Rage Bot"],"OBJETIVO",4,13,530,200)
local observing=false
local observedCamera,previousSubject
local selectKeyButton=button(targetControls,"Target Selection [Sin asignar] - cambiar tecla",9,16,508,25,function()
 targetBinding=not targetBinding;binding=false;menuBinding=false
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
do
local gunGroup=group(pages.Armas,"Armas",4,13,530,160)
local weaponStatus=label(gunGroup,"Elige un arma.",9,109,508,25,12,"Muted")
local busy=false
local function requestWeapon(name)
 if busy then return end
 local remote=game:GetService("ReplicatedStorage"):FindFirstChild("AdminPanelGiveWeapon")
 if not remote or not remote:IsA("RemoteFunction") then
  weaponStatus.Text="Falta instalar el script de entrega en el servidor.";return
 end
 busy=true;weaponStatus.Text="Pidiendo "..name.."..."
 local ok,result=pcall(function()return remote:InvokeServer(name)end)
 busy=false
 if weaponStatus.Parent then weaponStatus.Text=ok and tostring(result) or "Error al pedir el arma." end
end
for i,name in ipairs({"M4A1","Remington 870"}) do
 button(gunGroup,name,9,18+(i-1)*43,508,31,function()requestWeapon(name)end)
end
end
local positionGroup=group(pages.Jugador,"Posicion",4,13,530,100)
local positionLabel=label(positionGroup,"",9,20,508,25,12)
on(R.Heartbeat,function() if pages.Jugador.Visible then local _,root=body(me.Character);positionLabel.Text=root and tostring(root.Position) or "Sin personaje" end end)
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
label(credits,"kurnio.wtf - custom build",9,15,239,18)
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
local watermarkText=label(watermark,"kurnio.wtf | review-1",6,3,353,18,11)

local function activeRows()
	local rows={}
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
	local desired=alive and (driving or (UI.DisableMovement and panel.Visible))
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
 copyText("https://www.roblox.com/games/"..game.PlaceId)
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
		watermarkText.Text=string.format("kurnio.wtf | review-1 | %s | %d fps",me.Name,math.round(frames/fpsClock))
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
		sectionInfo.Text=S.TeamCheck and ("TEAM CHECK ON / "..teammates.." EXCLUDED") or "AIM / ALL TEAMS"
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
	endObserve()
	S.Enabled,target,stickyTarget=false,nil,nil
	stopBot()
	note("Detenido.")
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
        targetBinding=false;endObserve()
        binding=false;menuBinding=false;heldAim=false;S.Aim=false;stopAll();refresh();return
    end
    if U:GetFocusedTextBox() then return end
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
-- Aimbot: immediate acquisition with mouse-intent retargeting.
R:BindToRenderStep("SimpleCombatAim",Enum.RenderPriority.Camera.Value+1,function(dt)
	local camera=workspace.CurrentCamera
	if not alive or not camera then return end
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
  local alpha=S.Lock and not manualMove and 1 or aimAlpha(S.Smooth,S.Lock,manualMove,dt)
			local ray=camera:ViewportPointToRay(center.X,center.Y)
			local localRay=camera.CFrame:VectorToObjectSpace(ray.Direction)
			local correction=CFrame.lookAt(Vector3.zero,localRay):Inverse()
			local goal=CFrame.lookAt(camera.CFrame.Position,selected.Position)*correction
			camera.CFrame=camera.CFrame:Lerp(goal,alpha)
	end
	 stroke.Color=target and UI.Theme.Accent or UI.Theme.Muted
	if os.clock()<messageUntil then status.Text=message
	elseif not S.Enabled then status.Text="Desactivado"
	elseif target and not selected then status.Text=S.Part.." oculto: "..target.Name
	elseif target then status.Text="Objetivo: "..target.Name.." | "..S.Part
	elseif S.Mode then status.Text=botTarget and ("Buscando: "..botTarget.Name) or "Buscando objetivos..."
	elseif S.Aim then status.Text="Sin objetivo visible dentro del FOV"
	else status.Text="Activa Aimbot" end
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
