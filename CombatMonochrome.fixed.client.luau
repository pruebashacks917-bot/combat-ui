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
local panel=rect(gui,20,80,560,300,"Main")
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
local pages={}
pages.Armas=rect(panel,9,62,542,230,"Main")
label(panel,"Armas",9,35,83,21,12)
local gunGroup=group(pages.Armas,"Armas",4,13,530,205)
local weaponStatus=label(gunGroup,"Elige un destino.",9,154,508,25,12,"Muted")
local origin,owner
local function move(position,name)
 local character=me.Character
 local hum=character and character:FindFirstChildOfClass("Humanoid")
 if not hum or hum.Health<=0 or not character:FindFirstChild("HumanoidRootPart") then
  weaponStatus.Text="Necesitas un personaje vivo.";return
 end
 if position then
  origin=character:GetPivot();owner=character
  character:PivotTo(CFrame.new(position)*origin.Rotation)
  weaponStatus.Text="Destino: "..name
 elseif owner==character and origin then
  character:PivotTo(origin);origin=nil;owner=nil
  weaponStatus.Text="Posicion restaurada."
 else
  weaponStatus.Text="Primero elige un destino."
 end
end
button(gunGroup,"M4A1",9,18,508,31,function()move(Vector3.new(847,101,2229),"M4A1")end)
button(gunGroup,"Remington 870",9,61,508,31,function()move(Vector3.new(820,101,2229),"Remington 870")end)
button(gunGroup,"Volver",9,104,508,31,function()move()end)
local function toggle()
 panel.Visible=not panel.Visible;open.Visible=not panel.Visible
end
on(hide.Activated,toggle)
on(open.Activated,toggle)
local keyConnection=on(game:GetService("UserInputService").InputBegan,function(key,processed)
 if not processed and key.KeyCode==Enum.KeyCode.RightShift then toggle() end
end)
on(close.Activated,function()keyConnection:Disconnect();gui:Destroy()end)
