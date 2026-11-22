local addonName, addon = ...;

local CreateFrame = _G.CreateFrame;
local sort = _G.sort;
local strfind = _G.strfind;
local strgsub = _G.gsub;
local strlower = _G.strlower;
local tinsert = _G.tinsert;
local wipe = _G.wipe;
local PlaySound = _G.PlaySound;

-- uses the SOUNDKIT name where available and falls back to the raw sound kit id
local function playSound (soundKitName, fallbackId)
  local soundKit = _G.SOUNDKIT and _G.SOUNDKIT[soundKitName] or fallbackId;

  if (PlaySound ~= nil and soundKit ~= nil) then
    PlaySound(soundKit);
  end
end

local Main = addon.import('Logic/Main');
local Utils = addon.import('Core/Utils');
local options = addon.import('Logic/Options').getAll();

local module = addon.export('Features/ButtonManager', {});

local WINDOW_WIDTH = 320;
local WINDOW_HEIGHT = 420;
local ROW_HEIGHT = 24;
local ICON_SIZE = 20;
local FALLBACK_ICON = 'Interface\\Icons\\INV_Misc_QuestionMark';

-- textures that are part of the usual minimap button frame and not the icon
local IGNORED_TEXTURES = {
  [136430] = true, -- Interface\Minimap\MiniMap-TrackingBorder
  [136467] = true, -- Interface\Minimap\UI-Minimap-Background
  [136477] = true, -- Interface\Minimap\UI-Minimap-ZoomButton-Highlight
};

local window;
local searchBox;
local scrollChild;
local emptyText;
local rows = {};
local entries = {};

--##############################################################################
-- data
--##############################################################################

local function getDisplayName (name)
  local displayName = strgsub(name, '^LibDBIcon10_', '');

  return displayName;
end

local function isIgnoredTexture (texture)
  if (texture == nil) then
    return true;
  end

  if (IGNORED_TEXTURES[texture]) then
    return true;
  end

  if (type(texture) == 'string') then
    local lower = strlower(texture);

    return (strfind(lower, 'trackingborder', 1, true) ~= nil or
        strfind(lower, 'minimap-background', 1, true) ~= nil or
        strfind(lower, 'highlight', 1, true) ~= nil);
  end

  return false;
end

local function getIconTexture (frame)
  if (frame == nil) then
    return nil;
  end

  for _, key in ipairs({'icon', 'Icon', 'texture', 'Texture'}) do
    local region = frame[key];

    if (type(region) == 'table' and region.GetTexture and
        not isIgnoredTexture(region:GetTexture())) then
      return region;
    end
  end

  if (type(frame.GetRegions) ~= 'function') then
    return nil;
  end

  for _, region in ipairs({frame:GetRegions()}) do
    if (region.IsObjectType and region:IsObjectType('Texture') and
        region:GetDrawLayer() ~= 'HIGHLIGHT' and
        not isIgnoredTexture(region:GetTexture())) then
      return region;
    end
  end

  return nil;
end

local function buildEntries ()
  local seen = {};

  wipe(entries);

  for _, button in ipairs(Main.collectedButtons) do
    local name = Utils.getFrameName(button);

    if (name ~= nil and not seen[name]) then
      seen[name] = true;
      tinsert(entries, {
        name = name,
        displayName = getDisplayName(name),
        frame = button,
      });
    end
  end

  for name in pairs(options.blacklist) do
    if (not seen[name]) then
      seen[name] = true;

      local frame = Main.getButtonByName(name);

      tinsert(entries, {
        name = name,
        displayName = getDisplayName(name),
        frame = Main.isValidFrame(frame) and frame or nil,
      });
    end
  end

  sort(entries, function (a, b)
    return strlower(a.displayName) < strlower(b.displayName);
  end);
end

local function isIncluded (entry)
  return (options.blacklist[entry.name] == nil);
end

local function setIncluded (entry, included)
  if (included) then
    options.blacklist[entry.name] = nil;
    Main.collectMinimapButtonsAndUpdateLayout();

    if (entry.frame ~= nil and not Main.isButtonCollected(entry.frame)) then
      -- the button isn't detected automatically, so collect it manually
      options.whitelist[entry.name] = true;
      Main.collectMinimapButtonsAndUpdateLayout();
    end
  else
    options.blacklist[entry.name] = true;

    if (entry.frame ~= nil) then
      Main.releaseButton(entry.frame);
    end
  end
end

--##############################################################################
-- rows
--##############################################################################

local function updateRow (row, entry)
  row.entry = entry;
  row.label:SetText(entry.displayName);
  row.check:SetChecked(isIncluded(entry));

  local iconRegion = getIconTexture(entry.frame);

  if (iconRegion ~= nil) then
    row.icon:SetTexture(iconRegion:GetTexture());
    row.icon:SetTexCoord(iconRegion:GetTexCoord());
  else
    row.icon:SetTexture(FALLBACK_ICON);
    row.icon:SetTexCoord(0, 1, 0, 1);
  end

  if (isIncluded(entry)) then
    row.label:SetTextColor(1, 1, 1);
    row.icon:SetDesaturated(false);
  else
    row.label:SetTextColor(0.5, 0.5, 0.5);
    row.icon:SetDesaturated(true);
  end
end

local function onRowToggled (row)
  local entry = row.entry;

  if (entry == nil) then
    return;
  end

  setIncluded(entry, not isIncluded(entry));
  updateRow(row, entry);
end

local function createRow (index)
  local row = CreateFrame('Button', nil, scrollChild);

  row:SetHeight(ROW_HEIGHT);
  row:SetPoint('TOPLEFT', scrollChild, 'TOPLEFT', 0, -(index - 1) * ROW_HEIGHT);
  row:SetPoint('RIGHT', scrollChild, 'RIGHT', 0, 0);

  local highlight = row:CreateTexture(nil, 'HIGHLIGHT');
  highlight:SetAllPoints();
  highlight:SetColorTexture(1, 1, 1, 0.08);

  row.check = CreateFrame('CheckButton', nil, row, 'UICheckButtonTemplate');
  row.check:SetSize(ROW_HEIGHT, ROW_HEIGHT);
  row.check:SetPoint('LEFT', row, 'LEFT', 0, 0);
  row.check:SetScript('OnClick', function ()
    onRowToggled(row);
  end);

  row.icon = row:CreateTexture(nil, 'ARTWORK');
  row.icon:SetSize(ICON_SIZE, ICON_SIZE);
  row.icon:SetPoint('LEFT', row.check, 'RIGHT', 4, 0);

  row.label = row:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight');
  row.label:SetPoint('LEFT', row.icon, 'RIGHT', 6, 0);
  row.label:SetPoint('RIGHT', row, 'RIGHT', -4, 0);
  row.label:SetJustifyH('LEFT');
  row.label:SetWordWrap(false);

  row:SetScript('OnClick', onRowToggled);

  row:SetScript('OnEnter', function (self)
    if (self.entry == nil) then
      return;
    end

    _G.GameTooltip:SetOwner(self, 'ANCHOR_RIGHT');
    _G.GameTooltip:AddLine(self.entry.displayName);
    _G.GameTooltip:AddLine(self.entry.name, 0.7, 0.7, 0.7);

    if (self.entry.frame == nil) then
      _G.GameTooltip:AddLine('Button is not currently loaded.', 1, 0.5, 0.5);
    end

    _G.GameTooltip:Show();
  end);

  row:SetScript('OnLeave', function ()
    _G.GameTooltip:Hide();
  end);

  rows[index] = row;
  return row;
end

local function matchesSearch (entry, search)
  if (search == '') then
    return true;
  end

  return (strfind(strlower(entry.displayName), search, 1, true) ~= nil or
      strfind(strlower(entry.name), search, 1, true) ~= nil);
end

local function refreshList ()
  local search = strlower(searchBox:GetText() or '');
  local count = 0;

  for _, entry in ipairs(entries) do
    if (matchesSearch(entry, search)) then
      count = count + 1;

      local row = rows[count] or createRow(count);

      updateRow(row, entry);
      row:Show();
    end
  end

  for index = count + 1, #rows do
    rows[index].entry = nil;
    rows[index]:Hide();
  end

  scrollChild:SetHeight(math.max(count * ROW_HEIGHT, 1));

  if (count == 0) then
    emptyText:SetText(#entries == 0 and 'No buttons found.' or 'No buttons match your search.');
    emptyText:Show();
  else
    emptyText:Hide();
  end
end

local function setAll (included)
  local search = strlower(searchBox:GetText() or '');

  for _, entry in ipairs(entries) do
    if (matchesSearch(entry, search) and isIncluded(entry) ~= included) then
      setIncluded(entry, included);
    end
  end

  refreshList();
end

--##############################################################################
-- window
--##############################################################################

local function createWindow ()
  window = CreateFrame('Frame', addonName .. 'ButtonManager', _G.UIParent,
      'BasicFrameTemplateWithInset');
  window:SetSize(WINDOW_WIDTH, WINDOW_HEIGHT);
  window:SetPoint('CENTER');
  window:SetFrameStrata('DIALOG');
  window:SetClampedToScreen(true);
  window:SetMovable(true);
  window:EnableMouse(true);
  window:RegisterForDrag('LeftButton');
  window:SetScript('OnDragStart', window.StartMoving);
  window:SetScript('OnDragStop', window.StopMovingOrSizing);
  window:Hide();

  tinsert(_G.UISpecialFrames, window:GetName());

  local title = window.TitleText or window:CreateFontString(nil, 'OVERLAY', 'GameFontHighlight');
  title:SetText(addonName);

  if (window.TitleText == nil) then
    title:SetPoint('TOP', window, 'TOP', 0, -5);
  end

  searchBox = CreateFrame('EditBox', nil, window, 'InputBoxTemplate');
  searchBox:SetHeight(20);
  searchBox:SetPoint('TOPLEFT', window, 'TOPLEFT', 18, -32);
  searchBox:SetPoint('TOPRIGHT', window, 'TOPRIGHT', -14, -32);
  searchBox:SetAutoFocus(false);

  local placeholder = searchBox:CreateFontString(nil, 'OVERLAY', 'GameFontDisableLeft');
  placeholder:SetPoint('LEFT', searchBox, 'LEFT', 0, 0);
  placeholder:SetText('Search...');

  searchBox:SetScript('OnTextChanged', function (self)
    placeholder:SetShown(self:GetText() == '');
    refreshList();
  end);
  searchBox:SetScript('OnEscapePressed', function (self)
    if (self:GetText() ~= '') then
      self:SetText('');
    else
      self:ClearFocus();
    end
  end);
  searchBox:SetScript('OnEnterPressed', searchBox.ClearFocus);

  local scrollFrame = CreateFrame('ScrollFrame', nil, window, 'UIPanelScrollFrameTemplate');
  scrollFrame:SetPoint('TOPLEFT', window, 'TOPLEFT', 12, -60);
  scrollFrame:SetPoint('BOTTOMRIGHT', window, 'BOTTOMRIGHT', -32, 40);

  scrollChild = CreateFrame('Frame', nil, scrollFrame);
  scrollChild:SetSize(WINDOW_WIDTH - 46, 1);
  scrollFrame:SetScrollChild(scrollChild);

  emptyText = window:CreateFontString(nil, 'OVERLAY', 'GameFontDisable');
  emptyText:SetPoint('CENTER', scrollFrame, 'CENTER', 0, 0);
  emptyText:Hide();

  local includeAll = CreateFrame('Button', nil, window, 'UIPanelButtonTemplate');
  includeAll:SetSize(130, 22);
  includeAll:SetPoint('BOTTOMLEFT', window, 'BOTTOMLEFT', 12, 10);
  includeAll:SetText('Include all');
  includeAll:SetScript('OnClick', function ()
    setAll(true);
  end);

  local excludeAll = CreateFrame('Button', nil, window, 'UIPanelButtonTemplate');
  excludeAll:SetSize(130, 22);
  excludeAll:SetPoint('BOTTOMRIGHT', window, 'BOTTOMRIGHT', -12, 10);
  excludeAll:SetText('Exclude all');
  excludeAll:SetScript('OnClick', function ()
    setAll(false);
  end);

  window:SetScript('OnShow', function ()
    playSound('IG_CHARACTER_INFO_OPEN', 839);
    buildEntries();
    refreshList();
  end);

  window:SetScript('OnHide', function ()
    playSound('IG_CHARACTER_INFO_CLOSE', 840);
  end);
end

function module.show ()
  if (window == nil) then
    createWindow();
  end

  if (window:IsShown()) then
    buildEntries();
    refreshList();
  else
    window:Show();
  end
end

function module.hide ()
  if (window ~= nil) then
    window:Hide();
  end
end

function module.toggle ()
  if (window ~= nil and window:IsShown()) then
    window:Hide();
  else
    module.show();
  end
end

local SlashCommands = addon.import('Core/SlashCommands');
local HelpCommands = addon.import('Core/HelpCommands');

SlashCommands.addCommand({'buttons', 'config'}, module.toggle);
HelpCommands.addHelper({'buttons', 'config'}, 'This command opens a window to choose which buttons are collected. You can also right-click the main button.');
