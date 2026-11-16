local me=game:GetService("Players").LocalPlayer
local pg=me:WaitForChild("PlayerGui")
local function new(class,props,parent)
 local item=Instance.new(class)
 for key,value in pairs(props) do item[key]=value end
 item.Parent=parent
 return item
end
local function on(signal,fn)return signal:Connect(fn)end
local UI={}
UI.Theme={Main=Color3.fromRGB(16,16,18),Background=Color3.fromRGB(11,11,13),
 Accent=Color3.fromRGB(165,95,240),Outline=Color3.fromRGB(67,67,72),
 Text=Color3.fromRGB(225,225,230),Muted=Color3.fromRGB(145,145,155)}
local themeTargets={}
local gui=new("ScreenGui",{Name="SimpleCombatUI",ResetOnSpawn=false,DisplayOrder=100,
	ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)
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
local panel=rect(gui,20,80,560,350,"Main")
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
local function group(parent,titleText,x,y,w,h)
	local f=rect(parent,x,y,w,h,"Main"); outline(f)
	rect(f,5,0,w-10,1,"Accent")
	local name=label(f," "..titleText.." ",8,-8,math.min(w-16,#titleText*7+14),16,12)
	name.BackgroundTransparency=0; theme(name,"BackgroundColor3","Main")
	return f
end
local U=game:GetService("UserInputService")
local widgetUpdates={}
local function refresh()
 for _,update in ipairs(widgetUpdates) do update() end
end
local function note(message) title.Text=message end
UI.MenuAlpha=0
local function input(parent,text,x,y,w,h,changed)
	local box=theme(new("TextBox",{Text=text,Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(w,h),Font=Enum.Font.Code,TextSize=12,ClearTextOnFocus=false,
		TextXAlignment=Enum.TextXAlignment.Left,BorderSizePixel=0},parent),"BackgroundColor3","Background")
	theme(box,"TextColor3","Text"); outline(box)
	new("UIPadding",{PaddingLeft=UDim.new(0,4),PaddingRight=UDim.new(0,4)},box)
	if changed then on(box.FocusLost,function() changed(box.Text,box) end) end
	return box
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
local pages={}
for i,name in ipairs({"Armas","Settings"}) do
 local page=rect(panel,9,62,542,280,"Main")
 pages[name]=page;page.Visible=name=="Armas"
 button(panel,name,9+(i-1)*88,35,83,21,function()
  for key,item in pairs(pages) do item.Visible=key==name end
 end)
end
local gunGroup=group(pages.Armas,"Armas",4,13,530,205)
local weaponStatus=label(gunGroup,"Elige un destino.",9,154,508,25,12,"Muted")
local origin,owner,trip
local move
move=function(position,name)
 local character=me.Character
 local hum=character and character:FindFirstChildOfClass("Humanoid")
 if not hum or hum.Health<=0 or not character:FindFirstChild("HumanoidRootPart") then
  weaponStatus.Text="Necesitas un personaje vivo.";return
 end
 if position then
  if not origin or owner~=character then origin=character:GetPivot();owner=character end
  local token={};trip=token
  character:PivotTo(CFrame.new(position)*origin.Rotation)
  weaponStatus.Text=name.." - regreso en 2 segundos."
  task.delay(2,function()
   if trip==token and owner==me.Character then move() end
  end)
 elseif owner==character and origin then
  character:PivotTo(origin);origin=nil;owner=nil;trip=nil
  weaponStatus.Text="Posicion restaurada."
 else
  weaponStatus.Text="Primero elige un destino."
 end
end
button(gunGroup,"M4A1",9,18,508,31,function()move(Vector3.new(847,101,2229),"M4A1")end)
button(gunGroup,"Remington 870",9,61,508,31,function()move(Vector3.new(820,101,2229),"Remington 870")end)
button(gunGroup,"Volver",9,104,508,31,function()move()end)
local themeGroup=group(pages.Settings,"Theme",276,13,258,265)
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
local main=group(pages.Settings,"Main",4,13,258,134)
local menuKey=Enum.KeyCode.RightShift
local binding=false
label(main,"Open / close",9,12,130,20)
local keyButton
keyButton=button(main,"[RightShift]",139,12,109,20,function()
 binding=true;keyButton.Text="Pulsa una tecla"
end)
button(main,"Rejoin server",9,46,239,22,function()
 local ok=pcall(function()
  game:GetService("TeleportService"):TeleportToPlaceInstance(game.PlaceId,game.JobId,me)
 end)
 if not ok then note("No se pudo volver al servidor.") end
end)
button(main,"Unload",9,83,239,22,function()gui:Destroy()end)
refresh()
local function toggle()
 panel.Visible=not panel.Visible;open.Visible=not panel.Visible
end
on(hide.Activated,toggle)
on(open.Activated,toggle)
local keyConnection=on(game:GetService("UserInputService").InputBegan,function(key,processed)
 if processed then return end
 if binding and key.UserInputType==Enum.UserInputType.Keyboard then
  menuKey=key.KeyCode;binding=false;keyButton.Text="["..menuKey.Name.."]"
 elseif key.KeyCode==menuKey then toggle() end
end)
on(gui.Destroying,function()
 keyConnection:Disconnect()
 if trip and owner==me.Character and owner.Parent then owner:PivotTo(origin) end
 trip=nil
end)
on(close.Activated,function()gui:Destroy()end)


