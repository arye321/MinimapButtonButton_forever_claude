local addonName, addon = ...;

local gmatch = _G.gmatch;
local sort = _G.sort;
local strfind = _G.strfind;
local strlower = _G.strlower;
local strmatch = _G.strmatch;
local tinsert = _G.tinsert;
local tremove = _G.tremove;
local executeAfter = _G.C_Timer.After;
local GetMouseFoci = _G.GetMouseFoci;
local hooksecurefunc = _G.hooksecurefunc;
local IsAltKeyDown = _G.IsAltKeyDown;
local issecurevariable = _G.issecurevariable;

local SetScale = _G.UIParent.SetScale;

local Constants = addon.import('Logic/Constants');
local SlashCommands = addon.import('Core/SlashCommands');
local HelpCommands = addon.import('Core/HelpCommands');
local Utils = addon.import('Core/Utils');
local Tooltip = addon.import('Core/Tooltip');

local anchors = Constants.anchors;

local Minimap = _G.Minimap;

local LEFTBUTTON = 'LeftButton';
local MIDDLEBUTTON = 'MiddleButton';
local RIGHTBUTTON = 'RightButton';
local ONMOUSEUP = 'OnMouseUp';

local Layout = addon.importPending('Layouts/Main');
local Blacklist = addon.importPending('Logic/Blacklist');
local options;

local buttonContainer;
local mainButton;
local logo;
local collectedButtonMap = {};
local collectedButtons = {};
local hookedButtons = {};
local originalStates = {};

local frameMethods = _G.UIParent;
local OVERRIDDEN_METHODS = {'ClearAllPoints', 'SetPoint', 'SetParent', 'SetScale'};

--##############################################################################
-- minimap button collecting
--##############################################################################

local function doNothing () end

local function updateLayoutIfVisibilityChanged (frame)
  local visibility = frame:IsShown();

  -- button might have been released after being hooked
  if (collectedButtonMap[frame] == nil) then
    return;
  end

  if (collectedButtonMap[frame] ~= visibility) then
    collectedButtonMap[frame] = visibility;
    Layout.updateLayout();
  end
end

local function hideButtons ()
  options.buttonsShown = false;
  buttonContainer:Hide();
end

local function isDescendant (parent, child)
  if (parent == child) then
    return true;
  end

  local childParent = child.GetParent and child:GetParent();

  return (childParent ~= nil and
    (childParent == parent or isDescendant(parent, childParent)));
end

local function checkButtonHover()
  if (options ~= nil and options.autoClose == true and buttonContainer:IsShown()) then
    for x, frame in ipairs(GetMouseFoci()) do
      if (isDescendant(buttonContainer, frame) or isDescendant(mainButton, frame)) then
        return;
      end
    end

    hideButtons();
  end
end

local function storeOriginalState (button)
  local state = {
    parent = button:GetParent(),
    points = {},
    strata = button:GetFrameStrata(),
    scale = button:GetScale(),
    ignoreParentScale = button:IsIgnoringParentScale(),
    onDragStart = button:GetScript('OnDragStart'),
    onDragStop = button:GetScript('OnDragStop'),
    methods = {},
  };

  for x = 1, button:GetNumPoints() do
    state.points[x] = {button:GetPoint(x)};
  end

  for _, method in ipairs(OVERRIDDEN_METHODS) do
    state.methods[method] = rawget(button, method);
  end

  originalStates[button] = state;
end

local function collectButton (button)
  -- print('collecting button:', button:GetName());

  storeOriginalState(button);

  button:SetParent(buttonContainer);
  button:SetFrameStrata(Constants.FRAME_STRATA);
  button:SetScript('OnDragStart', nil);
  button:SetScript('OnDragStop', nil);
  button:SetIgnoreParentScale(false);
  button:SetScale(options.buttonScale / 10);

  -- Hook the function on the frame itself instead of setting a script handler
  -- to execute only when the function is called and not when the frame changes
  -- visibility because the parent gets shown/hidden
  -- hooks cannot be removed, so only apply them once per button
  local alreadyHooked = hookedButtons[button];
  hookedButtons[button] = true;

  if (not alreadyHooked and
      type(button.Show) == "function" and type(button.Hide) == "function") then
    hooksecurefunc(button, 'Show', updateLayoutIfVisibilityChanged);
    hooksecurefunc(button, 'Hide', updateLayoutIfVisibilityChanged);
  end

  -- There's still a ton of addons being coded like hot garbage moving their
  -- buttons on every single frame so to prevent a billion comments stating that
  -- MBB is apparently incompatible, we try to block moving the frame
  button.ClearAllPoints = doNothing;
  button.SetPoint = doNothing;
  button.SetParent = doNothing;
  button.SetScale = doNothing;

  if (not alreadyHooked and type(button.HookScript) == "function") then
    button:HookScript('OnLeave', function (frame)
      if (collectedButtonMap[frame] ~= nil) then
        checkButtonHover();
      end
    end);
  end

  tinsert(collectedButtons, button);
  collectedButtonMap[button] = button:IsShown();
end

local function isButtonCollected (button)
  return (collectedButtonMap[button] ~= nil);
end

-- Gives a collected button back to wherever it was before being collected
local function releaseButton (button)
  if (not isButtonCollected(button)) then
    return false;
  end

  for index, collected in ipairs(collectedButtons) do
    if (collected == button) then
      tremove(collectedButtons, index);
      break;
    end
  end

  collectedButtonMap[button] = nil;

  local state = originalStates[button];
  originalStates[button] = nil;

  if (state ~= nil) then
    for _, method in ipairs(OVERRIDDEN_METHODS) do
      button[method] = state.methods[method];
    end

    frameMethods.SetParent(button, state.parent);
    frameMethods.SetFrameStrata(button, state.strata);
    button:SetIgnoreParentScale(state.ignoreParentScale);
    frameMethods.SetScale(button, state.scale);
    frameMethods.ClearAllPoints(button);

    for _, point in ipairs(state.points) do
      frameMethods.SetPoint(button, unpack(point));
    end

    button:SetScript('OnDragStart', state.onDragStart);
    button:SetScript('OnDragStop', state.onDragStop);
  end

  Layout.updateLayout();
  return true;
end

local function getLibDBIcon ()
  return _G.LibStub and _G.LibStub:GetLibrary('LibDBIcon-1.0', true);
end

local function collectLibIcon (button)
  if (not isButtonCollected(button) and
      not Blacklist.isButtonBlacklisted(button)) then
    collectButton(button);
    return true;
  else
    return false;
  end
end

local function collectLibDBIconButtons ()
  local LibDBIcon = getLibDBIcon();

  if (not LibDBIcon) then
    return;
  end

  if (type(LibDBIcon.RegisterCallback) ~= "function") then
    _G.geterrorhandler()("LibDBIcon is loaded but it's missing the GetButtonList function.");
    return;
  end

  for _, buttonName in ipairs(LibDBIcon:GetButtonList()) do
    local button = LibDBIcon:GetMinimapButton(buttonName);

    collectLibIcon(button);
  end
end

local function getLibMapButton ()
  return _G.LibStub and _G.LibStub:GetLibrary('LibMapButton-1.1', true);
end

local function collectLibMapButtonButtons ()
  local LibMapButton = getLibMapButton();

  if (not LibMapButton) then
    return;
  end

  for _, button in pairs(LibMapButton.buttons) do
    collectLibIcon(button);
  end
end

local function isValidFrame (frame)
  if (type(frame) ~= 'table') then
    return false;
  end

  return (frame.IsObjectType and frame:IsObjectType('Frame'));
end

local function findFrameInParent(parent, name)
  if (parent[name] ~= nil and type(parent[name]) == "table") then
    return {parent[name]}, {name};
  end

  local matches = {};
  local keys = {};

  for key, child in pairs(parent) do
    if (type(child) == "table" and strfind(strlower(key), strlower(name), 1, true)) then
      tinsert(matches, child);
      tinsert(keys, key);
    end
  end

  return matches, keys;
end

local function searchButtonByName (name)
  local parent = _G;
  local matches = nil;
  local keys = nil;
  local path = nil;

  for frameName in gmatch(name, '[^.]+') do
    matches, keys = findFrameInParent(parent, frameName);

    if (#matches == 0 or #matches > 1) then
      return matches, path, keys;
    end

    parent = matches[1];
    path = path and path .. "." .. keys[1] or keys[1];
  end

  return matches, path, keys;
end

local function getFoundButtonPaths (path, keys)
  local results = {};

  for _, key in ipairs(keys) do
    tinsert(results, path and path .. "." .. key or key);
  end

  return results;
end

local function getButtonByName (buttonName)
  local parent = _G;

  for frameName in gmatch(buttonName, '[^.]+') do
    parent = parent[frameName];

    if (type(parent) ~= 'table') then
      return nil;
    end
  end

  return parent;
end

local function collectWhitelistedButtons ()
  for buttonName in pairs(options.whitelist) do
    local button = getButtonByName(buttonName);

    if (isValidFrame(button) and not isButtonCollected(button) and
        not Blacklist.isButtonBlacklisted(button)) then
      collectButton(button);
    end
  end
end

local function isTomCatsButton (frameName)
  return (strmatch(frameName, '^TomCats-') ~= nil);
end

local function nameEndsWithNumber (frameName)
  return (strmatch(frameName, '%d$') ~= nil);
end

local function nameMatchesButtonPattern (frameName)
  local patterns = {
    '^LibDBIcon10_', -- keep this in, some buttons are manually named to be detected
    'MinimapButton',
    'MinimapFrame',
    'MinimapIcon',
    '[-_]Minimap[-_]',
    'Minimap$',
  };

  for _, pattern in ipairs(patterns) do
    if (strmatch(frameName, pattern) ~= nil) then
      return true;
    end
  end

  return false;
end

local function nameMatchesPinPattern (frameName)
  local patterns = {
    "^HandyNotes",
    "^TomTom",
    "^HereBeDragons",
    "^Questie",
    "^GatherMate",
    "^pin",
    "^Pin",
    "^EasyFind",
  };

  for _, pattern in ipairs(patterns) do
    if (strmatch(frameName, pattern) ~= nil) then
      return true;
    end
  end

  return false;
end

local function isMinimapButton (frame)
  local frameName = Utils.getFrameName(frame);

  if (not frameName) then
    return false;
  end;

  if (issecurevariable(_G, frameName)) then
    return false;
  end

  -- Some TomCats buttons end with the current year so we need to check that
  -- before nameEndsWithNumber
  if (isTomCatsButton(frameName)) then
    return true;
  end

  if (nameEndsWithNumber(frameName)) then
    return false;
  end

  return (nameMatchesButtonPattern(frameName) and not nameMatchesPinPattern(frameName));
end

local function shouldButtonBeCollected (button)
  if (isButtonCollected(button) or
      not isValidFrame(button) or
      Blacklist.isButtonBlacklisted(button) or
      button:IsForbidden() or
      button:IsProtected()) then
    return false;
  end

  return isMinimapButton(button);
end

local function scanMinimapChildren ()
  for _, child in ipairs({Minimap:GetChildren()}) do
    if (shouldButtonBeCollected(child)) then
      collectButton(child);
    end
  end
end

local function buttonSortFunc (a, b)
  return ((a:GetName() or '') < (b:GetName() or ''));
end

local function sortCollectedButtons ()
  sort(collectedButtons, buttonSortFunc);
end

local function collectMinimapButtonsAndUpdateLayout ()
  local previousCount = #collectedButtons;

  collectLibDBIconButtons();
  collectLibMapButtonButtons();
  collectWhitelistedButtons();
  scanMinimapChildren();

  if (#collectedButtons > previousCount) then
    sortCollectedButtons();
    Layout.updateLayout();
  end
end

--##############################################################################
-- main button setup
--##############################################################################

local function showButtons ()
  options.buttonsShown = true;
  buttonContainer:Show();
end

local function toggleButtons ()
  collectMinimapButtonsAndUpdateLayout();

  if (buttonContainer:IsShown()) then
    hideButtons();
  else
    showButtons();
  end
end

local function setDefaultPosition ()
  mainButton:ClearAllPoints();
  mainButton:SetPoint(anchors.CENTER, _G.UIParent, anchors.CENTER, 0, 0);
end

local function storeMainButtonPosition ()
  options.position = {mainButton:GetPoint()};
end

local function stopMovingMainButton ()
  mainButton:SetScript(ONMOUSEUP, nil);
  mainButton:SetMovable(false);
  mainButton:StopMovingOrSizing();
  storeMainButtonPosition();

  if (mainButton.hasTooltip) then
    Tooltip.removeTooltip(mainButton);
  end
end

local function moveMainButton ()
  mainButton:SetScript(ONMOUSEUP, stopMovingMainButton);
  mainButton:SetMovable(true);
  mainButton:StartMoving();
end

local function initMainButton ()
  mainButton = _G.CreateFrame('Frame', addonName .. 'Button', _G.UIParent,
      _G.BackdropTemplateMixin and 'BackdropTemplate');
  mainButton:SetParent(_G.UIParent);
  mainButton:SetFrameStrata(Constants.FRAME_STRATA);
  mainButton:SetFrameLevel(Constants.FRAME_LEVEL);
  setDefaultPosition();
  mainButton:SetClampedToScreen(true);
  mainButton:Show();

  mainButton:SetScript('OnMouseDown', function (_, button)
    if (button == MIDDLEBUTTON or IsAltKeyDown()) then
      moveMainButton();
    elseif (button == LEFTBUTTON) then
      toggleButtons();
    elseif (button == RIGHTBUTTON) then
      local ButtonManager = addon.import('Features/ButtonManager');

      collectMinimapButtonsAndUpdateLayout();
      ButtonManager.toggle();
    end
  end);

  mainButton:SetScript('OnLeave', checkButtonHover);
end

local function initButtonContainer ()
  buttonContainer = _G.CreateFrame('Frame', nil, _G.UIParent,
    _G.BackdropTemplateMixin and 'BackdropTemplate');
  buttonContainer:SetParent(mainButton);
  buttonContainer:SetFrameLevel(Constants.FRAME_LEVEL);
  buttonContainer:Hide();

  buttonContainer:SetScript('OnLeave', checkButtonHover);
end

local function initLogo ()
  logo = mainButton:CreateTexture(nil, 'ARTWORK');
  logo:SetTexture('Interface\\AddOns\\' .. addonName ..
      '\\Media\\Logo.blp');

  logo:SetPoint(anchors.CENTER, mainButton, anchors.CENTER, 0, 0);
  logo:SetSize(Constants.LOGO_SIZE, Constants.LOGO_SIZE);
end

local function initFrames ()
  initMainButton();
  initButtonContainer();
  initLogo();
end

initFrames();

--##############################################################################
-- initialization
--##############################################################################

local function applyScale ()
  mainButton:SetScale(options.scale / 10);
end

local function applyButtonScale ()
  for _, button in ipairs(collectedButtons) do
    SetScale(button, options.buttonScale / 10);
  end

  Layout.updateLayout();
end

local function addDraggingTooltip ()
  Tooltip.createTooltip(mainButton, {
      'You can drag the button using the middle mouse button',
      'or any mouse button while holding ALT.',
      'Right-click to choose which buttons are collected.',
    });
end

local function restoreOptions ()
  if (options.position == nil) then
    addDraggingTooltip();
  else
    mainButton:ClearAllPoints();
    mainButton:SetPoint(unpack(options.position));
  end

  applyScale();

  if (options.buttonsShown == true) then
    buttonContainer:Show();
  end
end

local function hookLibDBIconButtons ()
  local LibDBIcon = getLibDBIcon();

  if (not LibDBIcon) then
    return;
  end

  if (type(LibDBIcon.RegisterCallback) ~= "function") then
    _G.geterrorhandler()("LibDBIcon is loaded but it's missing the RegisterCallback function.");
    return;
  end

  LibDBIcon.RegisterCallback(addonName, 'LibDBIcon_IconCreated', function (_, button)
    if (collectLibIcon(button)) then
      Layout.updateLayout();
    end
  end);
end

addon.import('Core/Events').registerEvent('PLAYER_LOGIN', function ()
  options = addon.import('Logic/Options').getAll();
  restoreOptions();

  hookLibDBIconButtons();

  --[[ executing on next frame to wait for addons that create minimap buttons
       on PLAYER_LOGIN ]]
  executeAfter(0, collectMinimapButtonsAndUpdateLayout);
  -- rescanning buttons after a second for special candidates like Questie
  executeAfter(1, collectMinimapButtonsAndUpdateLayout);

  return true;
end);

--##############################################################################
-- slash commands
--##############################################################################

SlashCommands.addHandlerName(addonName);
SlashCommands.addHandlerName('mbb');

local function printButtonLists ()
  if (#collectedButtons > 0) then
    Utils.printAddonMessage('Buttons currently being collected:');

    for _, button in ipairs(collectedButtons) do
      print(button:GetName());
    end
  end

  if (options ~= nil and next(options.whitelist) ~= nil) then
    Utils.printAddonMessage('Buttons currently being manually collected:');
    Utils.printTableKeys(options.whitelist);
  end

  if (options ~= nil and next(options.blacklist) ~= nil) then
    Utils.printAddonMessage('Buttons currently being ignored:');
    Utils.printTableKeys(options.blacklist);
  end
end

local function resetPosition ()
  setDefaultPosition();
  addDraggingTooltip();
end

SlashCommands.addCommand('list', printButtonLists);
HelpCommands.addHelper('list', 'This command lists all buttons that are currently being collected and ignored.')

SlashCommands.addCommand('reset', resetPosition);
HelpCommands.addHelper('reset', 'This command resets the main buttons position to the middle of the screen.');

--##############################################################################
-- shared data
--##############################################################################

addon.export('Logic/Main', {
  buttonContainer = buttonContainer,
  mainButton = mainButton,
  logo = logo,
  collectedButtons = collectedButtons,
  resetPosition = resetPosition,
  applyScale = applyScale,
  hideButtons = hideButtons,
  applyButtonScale = applyButtonScale,
  collectMinimapButtonsAndUpdateLayout = collectMinimapButtonsAndUpdateLayout,
  searchButtonByName = searchButtonByName,
  getFoundButtonPaths = getFoundButtonPaths,
  isValidFrame = isValidFrame,
  isButtonCollected = isButtonCollected,
  releaseButton = releaseButton,
  getButtonByName = getButtonByName,
});
