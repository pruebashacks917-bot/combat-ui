-- COMBAT UI: siempre selecciona al jugador mas cercano a la mira dentro del FOV.
-- Target lock ON = apuntado directo; OFF = usa Smoothness.
-- Ninguna opcion conserva un objetivo si otro esta mas cerca.
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

local S = {Enabled=false, Aim=false, Lock=false, FOV=200, Smooth=20,
	Part="Head", Center="Crosshair", Mode=nil, Key=Enum.KeyCode.Q, Sticky=false}
local binding=false
local stickyTarget=nil
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
	local p = model and model:FindFirstChild(name)
	return p and p:IsA("BasePart") and p or nil
end
local function body(model)
	if not model or not model:IsDescendantOf(workspace) then return end
	local h = model:FindFirstChildOfClass("Humanoid")
	local root = part(model,"HumanoidRootPart") or part(model,"UpperTorso")
		or part(model,"Torso") or model.PrimaryPart
	if h and h.Health>0 and root and root:IsA("BasePart") then return h,root end
end
local function enemy(p)
	return p and p~=me and p.Parent==P and body(p.Character)~=nil
end
local function aimPart(model)
	if S.Part=="Head" then return part(model,"Head") end
	return part(model,"UpperTorso") or part(model,"Torso") or part(model,"LowerTorso")
end
local function visible(origin, model)
	local _,root = body(model)
	if not root then return false end
	local params = RaycastParams.new()
	params.FilterType = Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances = me.Character and {me.Character} or {}
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

-- UI: compact monochrome cards.
local ink,paper,gray = Color3.fromRGB(15,15,16),Color3.fromRGB(246,246,243),Color3.fromRGB(135,135,137)
local gui = new("ScreenGui",{Name="SimpleCombatUI",ResetOnSpawn=false,
	DisplayOrder=100,ZIndexBehavior=Enum.ZIndexBehavior.Sibling},pg)
local overlay = new("ScreenGui",{Name="SimpleCombatCircle",ResetOnSpawn=false,
	IgnoreGuiInset=true,DisplayOrder=90},pg)
local circle = new("Frame",{AnchorPoint=Vector2.new(.5,.5),
	BackgroundTransparency=1,Visible=false},overlay)
round(circle,10000)
local stroke = new("UIStroke",{Color=gray,Thickness=1},circle)
local dot = new("Frame",{AnchorPoint=Vector2.new(.5,.5),Position=UDim2.fromScale(.5,.5),
	Size=UDim2.fromOffset(4,4),BackgroundColor3=paper,BorderSizePixel=0},circle)
round(dot,4)

local panel = new("Frame",{AnchorPoint=Vector2.new(0,.5),Position=UDim2.new(0,20,.5,0),
	Size=UDim2.fromOffset(430,428),BackgroundColor3=paper,BorderSizePixel=0},gui)
round(panel,16)
new("UIStroke",{Color=ink,Thickness=2},panel)
local scale = new("UIScale",{},panel)
local function txt(parent,text,x,y,w,h,size,color,font)
	return new("TextLabel",{Text=text,Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(w,h),BackgroundTransparency=1,TextColor3=color or ink,
		Font=font or Enum.Font.GothamMedium,TextSize=size or 12,
		TextXAlignment=Enum.TextXAlignment.Left,TextTruncate=Enum.TextTruncate.AtEnd},parent)
end
local function smallButton(text,x,y,w,h,parent)
	local b=new("TextButton",{Text=text,Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(w,h),BackgroundColor3=ink,TextColor3=paper,
		TextSize=12,Font=Enum.Font.GothamBold,BorderSizePixel=0},parent or panel)
	round(b,9)
	return b
end
local badge=smallButton("+",16,16,34,34)
badge.Active=false
badge.AutoButtonColor=false
txt(panel,"COMBAT",60,12,140,27,22,ink,Enum.Font.GothamBlack)
txt(panel,"CONTROL PANEL",61,39,150,12,9,gray)
local activeCount=smallButton("KEY: Q",254,20,90,26)
activeCount.Active=true
activeCount.AutoButtonColor=true
local hide=smallButton("-",354,20,26,26)
local close=smallButton("X",387,20,26,26)
local open=smallButton("COMBAT  +",18,100,116,34,gui)
open.Visible=false

-- A small checker accent, rather than a full patterned background.
for i=0,55 do
	new("Frame",{Position=UDim2.fromOffset(19+i*7,63+(i%2)*3),
		Size=UDim2.fromOffset(7,3),BackgroundColor3=ink,BorderSizePixel=0},panel)
end
txt(panel,"AIM & AUTOMATION",17,77,240,13,9,gray)
local buttons,cards={},{}
local function card(key,title,subtitle,x,y)
	local shadow=new("Frame",{Position=UDim2.fromOffset(x+2,y+3),
		Size=UDim2.fromOffset(194,46),BackgroundColor3=Color3.fromRGB(185,185,182),
		BorderSizePixel=0,ZIndex=1},panel)
	round(shadow,11)
	local b=new("TextButton",{Text="",Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(194,46),BackgroundColor3=paper,
		BorderSizePixel=0,AutoButtonColor=false,ZIndex=2},panel)
	round(b,11)
	new("UIStroke",{Color=ink,Thickness=1.5,ApplyStrokeMode=Enum.ApplyStrokeMode.Border},b)
	local name=txt(b,title,10,7,121,17,12)
	local sub=txt(b,subtitle,10,25,121,12,9,gray)
	name.ZIndex,sub.ZIndex=3,3
	local track=new("Frame",{Position=UDim2.fromOffset(143,12),
		Size=UDim2.fromOffset(41,22),BackgroundColor3=Color3.fromRGB(216,216,212),
		BorderSizePixel=0,ZIndex=3},b)
	round(track,11)
	new("UIStroke",{Color=ink,Thickness=1},track)
	local word=txt(track,"OFF",20,0,19,22,7,ink,Enum.Font.GothamBold)
	word.ZIndex=4
	local knob=new("Frame",{Position=UDim2.fromOffset(2,2),
		Size=UDim2.fromOffset(18,18),BackgroundColor3=paper,BorderSizePixel=0,ZIndex=5},track)
	round(knob,9)
	new("UIStroke",{Color=ink,Thickness=1},knob)
	cards[key]={Button=b,Title=name,Sub=sub,Track=track,Knob=knob,Word=word}
	buttons[key]=b
	return b
end
card("Enabled","Toggle","Main switch",16,97)
card("Aim","Aimbot","Nearest to the reticle",220,97)
card("Lock","Target lock","Instant aim",16,151)
local auto=card("Auto","Autoplay","Move + attack",220,151)
local kill=card("All","Kill all","One pass",16,205)

local function choice(key,title,x,y,value)
	local b=new("TextButton",{Text="",Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(194,46),BackgroundColor3=Color3.fromRGB(232,232,228),
		BorderSizePixel=0,AutoButtonColor=true},panel)
	round(b,10)
	txt(b,title,10,5,174,14,9,gray)
	local valueLabel=txt(b,value,10,21,153,20,12,ink,Enum.Font.GothamBold)
	txt(b,">",174,21,12,20,12)
	buttons[key]=b
	return valueLabel
end
local partValue=choice("Part","AIM PART",220,205,S.Part)
local centerValue=choice("Center","AIM CENTER",16,259,S.Center)
local sticky=card("Sticky","Sticky","Keep current target",220,259)
local emergency=smallButton("STOP ALL",334,370,80,22)
local function number(key,title,x,y,minimum,maximum,suffix)
	local holder=new("Frame",{Position=UDim2.fromOffset(x,y),
		Size=UDim2.fromOffset(194,43),BackgroundColor3=Color3.fromRGB(232,232,228),
		BorderSizePixel=0},panel)
	round(holder,10)
	txt(holder,title,10,5,118,15,10,ink,Enum.Font.GothamBold)
	txt(holder,suffix,10,23,118,12,9,gray)
	local box=new("TextBox",{Text=tostring(S[key]),Position=UDim2.fromOffset(137,7),
		Size=UDim2.fromOffset(47,29),BackgroundColor3=paper,TextColor3=ink,
		Font=Enum.Font.GothamBold,TextSize=13,ClearTextOnFocus=false,BorderSizePixel=0},holder)
	round(box,7)
	on(box.FocusLost,function()
		local n=tonumber(box.Text)
		if n and n==n and math.abs(n)<math.huge then
			S[key]=math.clamp(math.floor(n+.5),minimum,maximum)
		end
		box.Text=tostring(S[key])
	end)
end
number("FOV","FOV",16,316,20,600,"Radius / pixels")
number("Smooth","SMOOTHNESS",220,316,0,100,"0 instant - 100 slow")
local status=txt(panel,"Ready",17,370,307,20,11,ink)
new("Frame",{Position=UDim2.fromOffset(16,399),Size=UDim2.fromOffset(398,1),
	BackgroundColor3=Color3.fromRGB(205,205,200),BorderSizePixel=0},panel)
txt(panel,"Drag COMBAT to move / Right Shift: menu / Backspace: stop",17,405,396,15,9,gray)

refresh=function()
	local count=0
	for key,c in pairs(cards) do
		local enabled
		if key=="Auto" then enabled=S.Mode=="Auto"
		elseif key=="All" then enabled=S.Mode=="All"
		else enabled=S[key] end
		if enabled then count=count+1 end
		c.Button.BackgroundColor3=enabled and ink or paper
		c.Title.TextColor3=enabled and paper or ink
		c.Sub.TextColor3=enabled and Color3.fromRGB(185,185,185) or gray
		c.Track.BackgroundColor3=enabled and paper or Color3.fromRGB(216,216,212)
		c.Knob.BackgroundColor3=enabled and ink or paper
		c.Knob.Position=UDim2.fromOffset(enabled and 21 or 2,2)
		c.Word.Position=UDim2.fromOffset(enabled and 3 or 20,0)
		c.Word.Text=enabled and "ON" or "OFF"
	end
	partValue.Text=S.Part
	centerValue.Text=S.Center
	activeCount.Text=binding and "PRESS A-Z" or ("KEY: "..S.Key.Name)
end

-- Movement

local function stopBot()
	version=version+1
	S.Mode,botTarget=nil,nil
	local h=body(me.Character)
	if h then h:Move(Vector3.zero) end
	if driving and controls then pcall(function() controls:Enable() end) end
	driving=false
	refresh()
end
local function stopAll()
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
	local effective=S.Enabled and (S.Aim or S.Mode~=nil)
	S.Aim=not effective
	if S.Aim then S.Enabled=true else target=nil; stopBot() end
	refresh()
	note(S.Aim and "Aimbot ON" or "Aimbot OFF")
end
on(activeCount.Activated,function()
	binding=not binding
	refresh()
	note(binding and "Pulsa una letra A-Z. Escape cancela." or "Asignacion cancelada.")
end)
local dragHeader=new("Frame",{Position=UDim2.fromOffset(54,6),
	Size=UDim2.fromOffset(190,50),BackgroundTransparency=1,Active=true,ZIndex=10},panel)
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
on(buttons.Part.Activated,function()
	S.Part=S.Part=="Head" and "Torso" or "Head"; refresh()
end)
on(buttons.Center.Activated,function()
	S.Center=S.Center=="Crosshair" and "Cursor" or "Crosshair"; refresh()
end)
on(kill.Activated,function() startBot("All") end)
on(auto.Activated,function() startBot("Auto") end)
local function togglePanel()
	panel.Visible=not panel.Visible
	open.Visible=not panel.Visible
end
on(hide.Activated,togglePanel)
on(open.Activated,togglePanel)
on(close.Activated,function() gui:Destroy() end)
on(U.InputBegan,function(input,processed)
	if U:GetFocusedTextBox() or GuiService.MenuIsOpen then return end
	if binding then
		-- Mouse buttons can never become the aimbot binding.
		if input.UserInputType~=Enum.UserInputType.Keyboard then return end
		if input.KeyCode==Enum.KeyCode.Escape then
			binding=false
			note("Asignacion cancelada.")
		elseif input.KeyCode.Name:match("^[A-Z]$") then
			S.Key=input.KeyCode
			binding=false
			note("Tecla del aimbot: "..S.Key.Name)
		else
			note("Solo letras A-Z; no se admiten botones del mouse.")
		end
		refresh()
		return
	end
	if processed then return end
	if input.KeyCode==Enum.KeyCode.Backspace then stopAll()
	elseif input.KeyCode==Enum.KeyCode.RightShift then togglePanel()
	elseif input.UserInputType==Enum.UserInputType.Keyboard and input.KeyCode==S.Key then toggleAim() end
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

local function pickClosest(camera,center)
	local params=RaycastParams.new()
	params.FilterType=Enum.RaycastFilterType.Exclude
	params.FilterDescendantsInstances=me.Character and {me.Character,camera} or {camera}
	local origin=camera.CFrame.Position
	local function clearAt(model,position)
		local hit=workspace:Raycast(origin,position-origin,params)
		return not hit or hit.Instance:IsDescendantOf(model)
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
			local requested=aimPart(model)
			if requested then
				local _,root=body(model)
				local score=math.huge
				-- Detect the character's visible body area, independently of Head/Torso aim.
				if p==direct then score=0
				else
					for _,limb in ipairs(model:GetChildren()) do
						if limb:IsA("BasePart") and limb.Name~="HumanoidRootPart"
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
					local screen=camera:WorldToViewportPoint(requested.Position)
					local point=nil
					if screen.Z>0 and clearAt(model,requested.Position) then point=requested end
					table.insert(candidates,{Player=p,Point=point,Score=score,
						Depth=(root.Position-origin).Magnitude,Visible=true,Direct=p==direct})
				end
			end
		end
	end
	local chosen=chooseCandidate(candidates,S.FOV,S.Sticky and stickyTarget or nil)
	stickyTarget=S.Sticky and chosen and chosen.Player or nil
	if chosen then return chosen.Player,chosen.Point,chosen.Score end
	return nil,nil,nil
end


-- Aimbot: nueva seleccion cada frame, sin conservar el objetivo anterior.
R:BindToRenderStep("SimpleCombatAim",Enum.RenderPriority.Camera.Value+1,function(dt)
	local camera=workspace.CurrentCamera
	if not alive or not camera then return end
	scale.Scale=math.max(.3,math.min(1,
		(camera.ViewportSize.Y-70)/428,(camera.ViewportSize.X-40)/430))
	local center=S.Center=="Cursor" and U:GetMouseLocation() or camera.ViewportSize*.5
	circle.Position=UDim2.fromOffset(center.X,center.Y)
	circle.Size=UDim2.fromOffset(S.FOV*2,S.FOV*2)
	circle.Visible=S.Enabled
	local selected=nil
	target=nil
	if S.Enabled and (S.Aim or S.Mode~=nil) and body(me.Character)
		and not binding and not dragInput and not GuiService.MenuIsOpen and not U:GetFocusedTextBox() then
		target,selected=pickClosest(camera,center)
	else stickyTarget=nil
	end
	 if selected and (selected.Position-camera.CFrame.Position).Magnitude>.01 then
		local ray=camera:ViewportPointToRay(center.X,center.Y)
		local localRay=camera.CFrame:VectorToObjectSpace(ray.Direction)
		local correction=CFrame.lookAt(Vector3.zero,localRay):Inverse()
		local goal=CFrame.lookAt(camera.CFrame.Position,selected.Position)*correction
		local seconds=S.Smooth/100*.45
		local alpha=(S.Lock or seconds==0) and 1 or 1-math.exp(-dt/seconds)
		camera.CFrame=camera.CFrame:Lerp(goal,alpha)
	end
	stroke.Color=target and Color3.fromRGB(250,250,248) or blue
	if os.clock()<messageUntil then status.Text=message
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
	for _,c in ipairs(links) do c:Disconnect() end
	overlay:Destroy()
end)
refresh()
