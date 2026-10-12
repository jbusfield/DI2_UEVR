-- Credits: Portions of the following code courtesy of LukasBlaster where noted

--[[
Usage
    Drop the lib folder containing this file into your project folder
    Add code like this in your script:
		local widgetModule = require('libs/widget')

    Image host widgets
		UUserWidget is abstract and Lua cannot define new widget classes, so widgetModule.createImageWidget
		borrows a loaded Widget Blueprint class to act as the host. The host is chosen automatically and generically:
		it must derive directly from UserWidget and have no Blueprint event graph, so no game logic can run against
		the replaced content. The host's original widget tree is discarded and replaced with an empty CanvasPanel
		before the image is added. The chosen class is cached and re-chosen after each level change.
		To show it in world space use widgetComponent.createImageComponent (libs/widgetcomponent).

	Available functions:

    widgetModule.createHostWidget() - creates an empty host UserWidget whose root is a CanvasPanel.
		Returns hostWidget or nil if no host widget class could be found or created.

    widgetModule.createImageWidget(imageSize) - creates a host UserWidget containing a single centered Image.
		Returns hostWidget, image or nil if no host widget class could be found or created.
		imageSize is the image's maximum dimension. The returned image is a widgetModule.Image, so use
		image:setTexture("Name.png") to change what it shows.
        example:
            local hostWidget, image = widgetModule.createImageWidget(40)

    widgetModule.destroyAll() - destroys all created images and clears the cached host widget class.
		Called automatically before level changes.
        example:
            widgetModule.destroyAll()

]]--

local uevrUtils = require('libs/uevr_utils')
local plugin = require('libs/core/plugin')

local M = {}
M.enableTextureCache = false

local currentLogLevel = LogLevel.Error
function M.setLogLevel(val)
	currentLogLevel = val
end
function M.print(text, logLevel)
    if logLevel == nil then logLevel = LogLevel.Debug end
    if logLevel <= currentLogLevel then
        uevrUtils.print("[widget] " .. text, logLevel)
    end
end

local Image = {}
Image.__index = Image
Image.createdImages = {}
Image.textureCache = {}
Image.ALIGN = {
	TOP_LEFT      = {0,   0},
	TOP_CENTER    = {0.5, 0},
	TOP_RIGHT     = {1,   0},
	CENTER_LEFT   = {0,   0.5},
	CENTER        = {0.5, 0.5},
	CENTER_RIGHT  = {1,   0.5},
	BOTTOM_LEFT   = {0,   1},
	BOTTOM_CENTER = {0.5, 1},
	BOTTOM_RIGHT  = {1,   1},
}
function Image.new(imageName, maxDim)
	local self = setmetatable({}, Image)
	if type(imageName) == "number" and maxDim == nil then
		maxDim = imageName
		imageName = nil
	end
	self.maxDim = maxDim or 128
	self.drawSize = uevrUtils.vector2D(self.maxDim, self.maxDim)
	self.image = nil
	self.slot = nil
	self.texture = nil
	if imageName then
		self:setTexture(imageName)
	end
	table.insert(Image.createdImages, self)
	return self
end
function Image.destroyAll()
	for i = 1, #Image.createdImages do
		local inst = Image.createdImages[i]
		if inst ~= nil and inst.remove ~= nil then
			inst:remove()
		end
	end
	Image.createdImages = {}
	Image.textureCache = {}
end

function Image:setTexture(imageName, path, hideIfMissing)
	if hideIfMissing == nil then hideIfMissing = true end
    if path == nil then path = "images/" end
	local function hideMissing()
		if hideIfMissing and self.image ~= nil then
			self.image:SetVisibility(1) -- Collapsed
		end
		return false
	end
	local function importTexture()
		local result = plugin.executeFunction(kismet_rendering_library, "ImportFileAsTexture2D",
			uevrUtils.get_world(), "$data/" .. path .. imageName)
		local texture = result and result.ReturnValue
		if uevrUtils.getValid(texture) == nil then return nil end
		if M.enableTextureCache then
			Image.textureCache[imageName] = texture
		end
		return texture
	end
	local texture = nil
	if M.enableTextureCache then
		texture = Image.textureCache[imageName]
		if uevrUtils.getValid(texture) == nil then
			texture = nil
			Image.textureCache[imageName] = nil
		end
	end
	if texture == nil then
		texture = importTexture()
		if texture == nil then return hideMissing() end
	end
	-- stale/recycled cache entries can pass getValid but lose Texture2D methods
	if texture.Blueprint_GetSizeX == nil or texture.Blueprint_GetSizeY == nil then
		if M.enableTextureCache then
			Image.textureCache[imageName] = nil
		end
		texture = importTexture()
		if texture == nil or texture.Blueprint_GetSizeX == nil or texture.Blueprint_GetSizeY == nil then
			return hideMissing()
		end
	end
	self.texture = texture
	local w, h = texture:Blueprint_GetSizeX(), texture:Blueprint_GetSizeY()
	if w > 0 and h > 0 then
		local scale = self.maxDim / math.max(w, h)
		self.drawSize = uevrUtils.vector2D(w * scale, h * scale)
	else
		self.drawSize = uevrUtils.vector2D(self.maxDim, self.maxDim)
	end
	if self.image ~= nil then
		self.image:SetBrushFromTexture(texture, true)
		self.image:SetBrushSize(self.drawSize)
		self.image:SetVisibility(0) -- Visible
		if self.slot ~= nil then
			self.slot:SetSize(self.drawSize)
		end
	end
	return true
end
local function setSlotLayout(slot, opts)
	opts = opts or {}

	local offset = opts.offset or opts.position or uevrUtils.vector2D(0, 0)
	local align = opts.align

	local ax, ay = 0, 0
	if align ~= nil then
		if type(align) ~= "table" or align[1] == nil then return false end
		ax, ay = align[1], align[2]
	end

	local pt = uevrUtils.vector2D(ax, ay)
	local anchors = slot:GetAnchors()
	anchors.Minimum = pt
	anchors.Maximum = pt
	slot:SetAnchors(anchors)
	slot:SetAlignment(opts.alignment or pt)
	slot:SetPosition(offset)
	slot:SetZOrder(opts.zOrder or 999)
	return true
end

function Image:setLayout(opts)
	if self.slot == nil then return end
	if setSlotLayout(self.slot, opts) then
		self.slot:SetSize(self.drawSize)
	end
end

function Image:addToWidget(widget, opts)
	if widget == nil or widget.WidgetTree == nil then return false end
	local panel = widget.WidgetTree.RootWidget
	if panel == nil or panel.AddChildToCanvas == nil then return false end
	if self.image == nil then
		self.image = uevrUtils.spawn_object("Class /Script/UMG.Image", widget.WidgetTree)
		if self.image == nil then return false end
		if self.texture ~= nil then
			self.image:SetBrushFromTexture(self.texture, true)
			self.image:SetBrushSize(self.drawSize)
		else
			self.image:SetBrushSize(self.drawSize)
			self.image:SetVisibility(1) -- Collapsed until setTexture
		end
		self.slot = panel:AddChildToCanvas(self.image)
	end
	if opts ~= nil and opts.X ~= nil then
		opts = { position = opts }
	end
	self:setLayout(opts or { position = uevrUtils.vector2D(50, 50) })
	return true
end

function Image:setPosition(position2D)
	self:setLayout({ position = position2D })
end

function Image:remove()
	if uevrUtils.getValid(self.image) ~= nil and self.image.RemoveFromParent ~= nil then
		self.image:RemoveFromParent()
	end
	self.image = nil
	self.slot = nil
	self.texture = nil
end

M.Image = Image

local Text = {}
Text.__index = Text
Text.createdTexts = {}
Text.ALIGN = Image.ALIGN
function Text.new(text)
	local self = setmetatable({}, Text)
	self.text = text or ""
	self.textBlock = nil
	self.slot = nil
	table.insert(Text.createdTexts, self)
	return self
end
function Text.destroyAll()
	for i = 1, #Text.createdTexts do
		local inst = Text.createdTexts[i]
		if inst ~= nil and inst.remove ~= nil then
			inst:remove()
		end
	end
	Text.createdTexts = {}
end

-- Native UEVR Lua cannot marshal FText, so SetText goes through the plugin
function Text:setText(text)
	self.text = text or ""
	if self.textBlock ~= nil then
		plugin.executeFunction(self.textBlock, "SetText", self.text)
	end
end

-- hex is "#RRGGBB" or "#RRGGBBAA"
function Text:setColor(hex)
	self.color = hex
	if self.textBlock == nil or type(hex) ~= "string" then return end
	local function channel(i, default) return (tonumber(hex:sub(i, i + 1), 16) or default) / 255 end
	local color = self.textBlock.ColorAndOpacity
	color.SpecifiedColor = uevrUtils.color_from_rgba(channel(2, 0), channel(4, 0), channel(6, 0), channel(8, 255))
	self.textBlock:SetColorAndOpacity(color)
end

-- Font and Size FName casing varies between game sessions
local function applyFont(text)
	if text.textBlock == nil or (text.fontSize == nil and text.fontPath == nil and text.typeface == nil) then return end
	local font = text.textBlock.Font or text.textBlock.font
	if text.fontSize ~= nil then
		if font.Size ~= nil then font.Size = text.fontSize else font.size = text.fontSize end
	end
	if text.fontPath ~= nil then
		local fontObject = uevrUtils.getLoadedAsset(text.fontPath)
		if fontObject ~= nil then font.FontObject = fontObject end
	end
	if text.typeface ~= nil then
		font.TypefaceFontName = uevrUtils.fname_from_string(text.typeface)
	end
	text.textBlock:SetFont(font)
end

function Text:setFontSize(size)
	self.fontSize = size
	applyFont(self)
end

-- fontPath is a font asset path e.g. "/Engine/EngineFonts/Roboto.Roboto", typeface is optional e.g. "Regular", "Bold", "Italic"
function Text:setFont(fontPath, typeface)
	self.fontPath = fontPath
	self.typeface = typeface
	applyFont(self)
end

function Text:setLayout(opts)
	if self.slot == nil then return end
	if setSlotLayout(self.slot, opts) then
		self.slot:SetAutoSize(true)
	end
end

function Text:addToWidget(widget, opts)
	if widget == nil or widget.WidgetTree == nil then return false end
	local panel = widget.WidgetTree.RootWidget
	if panel == nil or panel.AddChildToCanvas == nil then return false end
	if self.textBlock == nil then
		self.textBlock = uevrUtils.spawn_object("Class /Script/UMG.TextBlock", widget.WidgetTree)
		if self.textBlock == nil then return false end
		self.slot = panel:AddChildToCanvas(self.textBlock)
		self:setText(self.text)
		if self.color ~= nil then self:setColor(self.color) end
		applyFont(self)
	end
	if opts ~= nil and opts.X ~= nil then
		opts = { position = opts }
	end
	self:setLayout(opts or { position = uevrUtils.vector2D(50, 50) })
	return true
end

function Text:setPosition(position2D)
	self:setLayout({ position = position2D })
end

function Text:remove()
	if uevrUtils.getValid(self.textBlock) ~= nil and self.textBlock.RemoveFromParent ~= nil then
		self.textBlock:RemoveFromParent()
	end
	self.textBlock = nil
	self.slot = nil
end

M.Text = Text

-----------------------------------------------------------------
-- Inspiration and portions of the following code courtesy of LukasBlaster
local hostWidgetClassName = nil
-- UUserWidget is abstract and Lua cannot define new widget classes, so borrow a loaded Widget Blueprint class.
-- Direct UserWidget children with no ubergraph have no native or Blueprint logic to run against the replaced tree.
local function getGenericUserWidgetClassName()
	if hostWidgetClassName ~= nil then return hostWidgetClassName end
	local userWidgetName = "Class /Script/UMG.UserWidget"
	local blueprintClass = uevrUtils.get_class("Class /Script/UMG.WidgetBlueprintGeneratedClass")
	-- Including defaults yields a CDO for every loaded widget class, live or not
	for _, widget in pairs(uevrUtils.find_all_instances(userWidgetName, true) or {}) do
		local cls = widget:get_class()
		local super = cls:get_super_struct()
        --check that the widget we are trying to hijack does not aleady have blueprint functions or c++ functions
        --that might cause unexpected behavior. If no widgets are found using this restriction for some reason this check could be relaxed
		--native classes have no UberGraphFunction field at all, so require a Blueprint class
		if super ~= nil and super:get_full_name() == userWidgetName and cls:is_a(blueprintClass) and cls.UberGraphFunction == nil then
			hostWidgetClassName = cls:get_full_name()
			M.print("Using host widget class " .. hostWidgetClassName)
			return hostWidgetClassName
		end
	end
	M.print("No host widget class found", LogLevel.Warning)
end

-- Creates an empty host UserWidget. The host's original tree is replaced with a fresh CanvasPanel root
function M.createHostWidget()
	local className = getGenericUserWidgetClassName()
	if className == nil then return nil end
	local hostWidget = uevrUtils.getValid(uevrUtils.createWidget(className))
	if hostWidget == nil then return nil end
	hostWidget.WidgetTree.RootWidget = uevrUtils.spawn_object("Class /Script/UMG.CanvasPanel", hostWidget.WidgetTree)
	return hostWidget
end

-- Creates a host UserWidget containing a centered Image
function M.createImageWidget(imageSize)
	local hostWidget = M.createHostWidget()
	if hostWidget == nil then return nil end
	local image = Image.new(imageSize)
	image:addToWidget(hostWidget, { align = Image.ALIGN.CENTER })
	return hostWidget, image
end
-----------------------------------------------------------------

function M.destroyAll()
	Image.destroyAll()
	Text.destroyAll()
	hostWidgetClassName = nil
end

uevrUtils.registerPreLevelChangeCallback(function()
	M.destroyAll()
end)

uevr.params.sdk.callbacks.on_script_reset(function()
	M.destroyAll()
end)




















local function normalizeWidgetName(widgetName)
    if widgetName == nil then return nil end
    if type(widgetName) == "string" then return widgetName end
    if type(widgetName) == "table" and widgetName.to_string ~= nil then
        local ok, str = pcall(function() return widgetName:to_string() end)
        if ok then return str end
    end
    if type(widgetName) == "userdata" and widgetName.to_string ~= nil then
        local ok, str = pcall(function() return widgetName:to_string() end)
        if ok then return str end
    end
    return tostring(widgetName)
end

local function traverseWidgetDescendants(rootWidget, visitor)
    if uevrUtils.getValid(rootWidget) == nil then return end
    if visitor == nil then return end

    local visited = {}

    local function visit(widget, depth)
        if uevrUtils.getValid(widget) == nil then return end

        local key = tostring(widget)
        if visited[key] then return end
        visited[key] = true

        if visitor(widget, depth or 0) == false then return false end

        -- UPanelWidget
        if widget.GetChildrenCount ~= nil and widget.GetChildAt ~= nil then
            local count = widget:GetChildrenCount()
            if count ~= nil and count > 0 then
                for i = 0, count - 1 do
                    if visit(widget:GetChildAt(i), (depth or 0) + 1) == false then
                        return false
                    end
                end
            end
        end

        -- UContentWidget
        if widget.GetContent ~= nil then
            if visit(widget:GetContent(), (depth or 0) + 1) == false then
                return false
            end
        end
    end

    visit(rootWidget, 0)
end

local function getWidgetTypeName(widget)
    local w = uevrUtils.getValid(widget)
    if w == nil then return "<invalid>" end
    if w.get_class == nil then return "<no_class>" end

    local ok, class = pcall(function() return w:get_class() end)
    if not ok or class == nil then return "<unknown_class>" end

    -- Prefer concise names (e.g. "Button") but fall back to full name if needed.
    if class.get_name ~= nil then
        local okName, name = pcall(function() return class:get_name() end)
        if okName and name ~= nil and name ~= "" then return name end
    end

    local short = uevrUtils.getShortName(class)
    if short ~= nil and short ~= "" then return short end

    if class.get_full_name ~= nil then
        local okFull, full = pcall(function() return class:get_full_name() end)
        if okFull and full ~= nil and full ~= "" then return full end
    end

    return tostring(class)
end

-- Replacement for UWidgetTree::FindWidget
-- Finds the first widget whose short name matches `widgetName`.
function M.findWidget(widgetTree, widgetName)
    local tree = uevrUtils.getValid(widgetTree)
    if tree == nil or uevrUtils.getValid(tree.RootWidget) == nil then
        return nil
    end

    local targetName = normalizeWidgetName(widgetName)
    if targetName == nil or targetName == "" then
        return nil
    end

    local found = nil
    traverseWidgetDescendants(tree.RootWidget, function(widget)
        if uevrUtils.getShortName(widget) == targetName then
            found = widget
            return false
        end
    end)

    return found
end

-- Replacement for UUserWidget::GetWidgetFromName
-- Finds the first widget whose short name matches `widgetName`.
function M.getWidgetFromName(userWidget, widgetName)
    local uw = uevrUtils.getValid(userWidget)
    if uw == nil then
        return nil
    end

    local tree = uevrUtils.getValid(uw.WidgetTree)
    if tree == nil then
        return nil
    end

    return M.findWidget(tree, widgetName)
end

local parametersFileName = "widget_parameters"
local function saveParameters(parameters)
	M.print("Saving widget parameters " .. parametersFileName)
	json.dump_file(parametersFileName .. ".json", parameters, 4)
end

-- Traverses a UUserWidget's widget tree and logs short names of all descendants.
-- Uses UPanelWidget:GetChildrenCount/GetChildAt and UContentWidget:GetContent when available.
function M.logWidgetDescendants(userWidget, logLevel)
    if logLevel == nil then logLevel = LogLevel.Info end
    if uevrUtils.getValid(userWidget) == nil then
        M.print("userWidget is invalid", LogLevel.Warning)
        return
    end

    local tree = userWidget.WidgetTree
    if uevrUtils.getValid(tree) == nil or uevrUtils.getValid(tree.RootWidget) == nil then
        M.print("userWidget has no WidgetTree/RootWidget", LogLevel.Warning)
        return
    end

    traverseWidgetDescendants(tree.RootWidget, function(widget, depth)
        local indent = string.rep("  ", depth or 0)
        local widgetName = uevrUtils.getShortName(widget)
        local widgetType = getWidgetTypeName(widget)
        M.print(indent .. widgetName .. " [" .. widgetType .. "]", logLevel)
    end)
end

local ESlateVisibility = {
    Visible = 0,
    Collapsed = 1,
    Hidden = 2,
    HitTestInvisible = 3,
    SelfHitTestInvisible = 4,
}

local function asNumber(v, fallback)
    if type(v) == "number" then return v end
    if type(v) == "string" then
        local n = tonumber(v)
        if n ~= nil then return n end
    end
    return fallback
end

local function asVector2(value)
    if value == nil then return nil end
    if type(value) == "table" then
        local x = value.X or value.x or value[1]
        local y = value.Y or value.y or value[2]
        return uevrUtils.vector_2(asNumber(x, 0), asNumber(y, 0))
    end
    return value
end

local function asLinearColor(value)
    if value == nil then return nil end
    if type(value) == "table" then
        local r = value.R or value.r or value[1]
        local g = value.G or value.g or value[2]
        local b = value.B or value.b or value[3]
        local a = value.A or value.a or value[4]
        return uevrUtils.color_from_rgba(asNumber(r, 1), asNumber(g, 1), asNumber(b, 1), asNumber(a, 1))
    end
    return value
end

local function makeField(id, label, kind, opts)
    opts = opts or {}
    opts.id = id
    opts.label = label
    opts.kind = kind
    return opts
end

local function tryGetProperty(obj, key)
    local ok, v = pcall(function() return obj[key] end)
    if ok then return v end
    return nil
end

local function serializeValue(value)
    local t = type(value)
    if value == nil or t == "number" or t == "string" or t == "boolean" then
        return value
    end

    if t == "table" then
        -- Assume already JSON-friendly.
        return value
    end

    -- UObjects (widgets, assets, etc.)
    if t == "userdata" and value.get_class ~= nil then
        return {
            object = uevrUtils.getShortName(value),
            class = getWidgetTypeName(value),
        }
    end

    -- Try common struct-ish shapes (FVector2D, FLinearColor, etc.)
    if t == "userdata" then
        local x = tryGetProperty(value, "X")
        local y = tryGetProperty(value, "Y")
        if type(x) == "number" and type(y) == "number" then
            return { X = x, Y = y }
        end

        local r = tryGetProperty(value, "R")
        local g = tryGetProperty(value, "G")
        local b = tryGetProperty(value, "B")
        local a = tryGetProperty(value, "A")
        if type(r) == "number" and type(g) == "number" and type(b) == "number" then
            return { R = r, G = g, B = b, A = (type(a) == "number" and a or 1.0) }
        end
    end

    return tostring(value)
end

local function safeCall(fn)
    if fn == nil then return false, nil end
    return pcall(fn)
end

-- Returns a list of editable fields/actions for a widget.
-- This is intended as a backend for a future GUI-based widget editor.
--
-- Field format (convention):
--   {
--     id = "visibility",
--     label = "Visibility",
--     kind = "enum" | "number" | "bool" | "color" | "vector2" | "asset" | "action" | "readonly",
--     get = function() return ... end,          -- optional
--     set = function(value) ... end,           -- optional
--     options = { {label=..., value=...}, ...} -- for enum
--     min/max/step                             -- for number
--   }
function M.getEditableFields(widget)
    local w = uevrUtils.getValid(widget)
    if w == nil then return {} end

    local fields = {}

    -- Always include some identity info
    table.insert(fields, makeField("name", "Name", "readonly", {
        get = function() return uevrUtils.getShortName(w) end,
    }))
    table.insert(fields, makeField("type", "Type", "readonly", {
        get = function() return getWidgetTypeName(w) end,
    }))

    -- Base UWidget fields (use functions where possible)
    if w.SetVisibility ~= nil or w.Visibility ~= nil then
        table.insert(fields, makeField("visibility", "Visibility", "enum", {
            options = {
                { label = "Visible", value = ESlateVisibility.Visible },
                { label = "Collapsed", value = ESlateVisibility.Collapsed },
                { label = "Hidden", value = ESlateVisibility.Hidden },
                { label = "HitTestInvisible", value = ESlateVisibility.HitTestInvisible },
                { label = "SelfHitTestInvisible", value = ESlateVisibility.SelfHitTestInvisible },
            },
            get = function()
                return w.Visibility
            end,
            set = function(value)
                local v = asNumber(value, ESlateVisibility.Visible)
                if w.SetVisibility ~= nil then
                    w:SetVisibility(v)
                else
                    w.Visibility = v
                end
            end,
        }))
    end

    if w.SetIsEnabled ~= nil or w.bIsEnabled ~= nil or w.GetIsEnabled ~= nil then
        table.insert(fields, makeField("enabled", "Enabled", "bool", {
            get = function()
                if w.GetIsEnabled ~= nil then
                    return w:GetIsEnabled()
                end
                return w.bIsEnabled
            end,
            set = function(value)
                local b = value == true
                if w.SetIsEnabled ~= nil then
                    w:SetIsEnabled(b)
                else
                    w.bIsEnabled = b
                end
            end,
        }))
    end

    if w.SetRenderOpacity ~= nil or w.RenderOpacity ~= nil or w.GetRenderOpacity ~= nil then
        table.insert(fields, makeField("renderOpacity", "Render Opacity", "number", {
            min = 0.0,
            max = 1.0,
            step = 0.01,
            get = function()
                if w.GetRenderOpacity ~= nil then
                    return w:GetRenderOpacity()
                end
                return w.RenderOpacity
            end,
            set = function(value)
                local v = asNumber(value, 1.0)
                if w.SetRenderOpacity ~= nil then
                    w:SetRenderOpacity(v)
                else
                    w.RenderOpacity = v
                end
            end,
        }))
    end

    if w.RemoveFromParent ~= nil then
        table.insert(fields, makeField("removeFromParent", "Remove From Parent", "action", {
            invoke = function() w:RemoveFromParent() end,
        }))
    end

    if w.ForceLayoutPrepass ~= nil then
        table.insert(fields, makeField("forceLayoutPrepass", "Force Layout Prepass", "action", {
            invoke = function() w:ForceLayoutPrepass() end,
        }))
    end

    -- UImage adapter (first pass)
    local looksLikeImage = (w.SetBrushFromTexture ~= nil) or (w.SetBrushSize ~= nil) or (w.SetColorAndOpacity ~= nil) or (w.Brush ~= nil and w.ColorAndOpacity ~= nil)
    if looksLikeImage then
        -- ColorAndOpacity (FLinearColor)
        if w.SetColorAndOpacity ~= nil or w.ColorAndOpacity ~= nil then
            table.insert(fields, makeField("imageColorAndOpacity", "Image Color+Opacity", "color", {
                get = function()
                    return w.ColorAndOpacity
                end,
                set = function(value)
                    local c = asLinearColor(value)
                    if c == nil then return end
                    if w.SetColorAndOpacity ~= nil then
                        w:SetColorAndOpacity(c)
                    else
                        w.ColorAndOpacity = c
                    end
                end,
            }))
        end

        -- Brush size
        if w.SetBrushSize ~= nil or w.GetBrushSize ~= nil or (w.Brush ~= nil and w.Brush.ImageSize ~= nil) then
            table.insert(fields, makeField("brushSize", "Brush Size", "vector2", {
                get = function()
                    if w.GetBrushSize ~= nil then
                        return w:GetBrushSize()
                    end
                    if w.Brush ~= nil then
                        return w.Brush.ImageSize
                    end
                    return nil
                end,
                set = function(value)
                    local v = asVector2(value)
                    if v == nil then return end
                    if w.SetBrushSize ~= nil then
                        w:SetBrushSize(v)
                    elseif w.Brush ~= nil then
                        w.Brush.ImageSize = v
                    end
                end,
            }))
        end

        -- Brush resource (texture)
        if w.SetBrushFromTexture ~= nil then
            table.insert(fields, makeField("setBrushFromTexture", "Set Brush From Texture", "asset", {
                assetClass = "Class /Script/Engine.Texture2D",
                set = function(assetPath)
                    if type(assetPath) ~= "string" or assetPath == "" then return end
                    local tex = uevrUtils.getLoadedAsset(assetPath)
                    if tex ~= nil then
                        w:SetBrushFromTexture(tex, true)
                    end
                end,
            }))
        end

        -- Brush resource (material)
        if w.SetBrushFromMaterial ~= nil then
            table.insert(fields, makeField("setBrushFromMaterial", "Set Brush From Material", "asset", {
                assetClass = "Class /Script/Engine.MaterialInterface",
                set = function(assetPath)
                    if type(assetPath) ~= "string" or assetPath == "" then return end
                    local mat = uevrUtils.getLoadedAsset(assetPath)
                    if mat ~= nil then
                        w:SetBrushFromMaterial(mat)
                    end
                end,
            }))
        end

        if w.GetDynamicMaterial ~= nil then
            table.insert(fields, makeField("getDynamicMaterial", "Get Dynamic Material", "action", {
                invoke = function() return w:GetDynamicMaterial() end,
            }))
        end
    end

    return fields
end

-- Traverses a UUserWidget's widget tree and dumps a JSON-friendly table:
--
-- {
--   root = "RootWidgetName",
--   widgets = {
--     {
--       name = "Foo",
--       type = "Button",
--       depth = 2,
--       fields = {
--         visibility = { kind="enum", value=0 },
--         renderOpacity = { kind="number", value=1.0 },
--         ...
--       }
--     },
--     ...
--   }
-- }
--
-- Then writes it out using saveParameters(parameters).
function M.dumpWidgetEditableFields(userWidget)
    local uw = uevrUtils.getValid(userWidget)
    if uw == nil then
        M.print("userWidget is invalid", LogLevel.Warning)
        return nil
    end

    local tree = uw.WidgetTree
    if uevrUtils.getValid(tree) == nil or uevrUtils.getValid(tree.RootWidget) == nil then
        M.print("userWidget has no WidgetTree/RootWidget", LogLevel.Warning)
        return nil
    end

    local parameters = {
        root = uevrUtils.getShortName(tree.RootWidget),
        tree = nil,
    }

    local function buildNode(w)

        local node = {
            name = uevrUtils.getShortName(w),
            type = getWidgetTypeName(w),
            fields = {},
            children = {},
        }

        local editable = M.getEditableFields(w)
        for _, field in ipairs(editable) do
            local id = field.id or field.label or tostring(#node.fields + 1)
            local record = {
                label = field.label,
                kind = field.kind,
                hasGet = field.get ~= nil,
                hasSet = field.set ~= nil,
                hasInvoke = field.invoke ~= nil,
            }

            if field.get ~= nil then
                local ok, value = safeCall(function() return field.get() end)
                if ok then
                    record.value = serializeValue(value)
                else
                    record.error = "get_failed"
                end
            end

            if field.kind == "enum" and field.options ~= nil then
                record.options = field.options
            end

            node.fields[id] = record
        end

        return node
    end

    -- Build nested tree using traversal order + depth.
    -- Depth stack holds the latest node at each depth.
    local stack = {}
    traverseWidgetDescendants(tree.RootWidget, function(widget, depth)
        local w = uevrUtils.getValid(widget)
        if w == nil then return end

        local d = depth or 0
        local node = buildNode(w)

        if d == 0 then
            parameters.tree = node
            stack[1] = node
            return
        end

        -- Ensure stack reflects current depth.
        -- Parent of depth d is at stack[d].
        for i = #stack, d + 1, -1 do
            stack[i] = nil
        end

        local parent = stack[d]
        if parent == nil then
            -- Fallback: attach to root if depth is inconsistent.
            parent = stack[1]
        end

        if parent ~= nil then
            table.insert(parent.children, node)
        end

        stack[d + 1] = node
    end)

    saveParameters(parameters)
    M.print("Dumped widget editable fields tree to " .. parametersFileName .. ".json", LogLevel.Info)
    return parameters
end

return M

--[[
[info] CanvasPanel_0
[info]   InvisibleButton
[info]   LogoContainer
[info]     LogoImage
[info]   PressKeyPromptOverlay
[info]     PressKeyPrompt
[info]     XboxTextblockContainer
[info]       LeftSidePrompt
[info]       Image_0
[info]       RightSidePrompt
[info]   GammaSelection
[info]   ContentOverlay
[info]     MainOptions
[info]     ExtraOptions
[info]     DeliverablesOptions
[info]     MenuDLCManager
[info]     UserNameTextBlock
[info]     VersionTextBlock
[info]   AutosaveSplashOverlay
[info]     VerticalBox_0
[info]       AutosaveSplashText
[info]       SavingSpinnerWidget
[info]   CreditsWidget
[info]   LegalWidget
[info]   SavingWidget_BP
]]--
-- register_key_bind("F2", function()
-- 	local userWidget = uevrUtils.getActiveWidgetByClass("WidgetBlueprintGeneratedClass /Game/UI/Menus/MainMenu/MainMenu.MainMenu_C")
-- 	if userWidget ~= nil then
-- 		print("Main menu widget found:")
-- 		--widgetModule.logWidgetDescendants(userWidget)
-- 		widgetModule.dumpWidgetEditableFields(userWidget)
-- 	else
-- 		print("No main menu widget found")
-- 	end
-- end)