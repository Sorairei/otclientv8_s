local DONATION_URL = nil

local GAME_STORE_CODE = 102

local categories = {}
local offers = {}
local history = {}

local gameStoreWindow = nil
local selected = nil
local selectedOffer = nil
local changeNameWindow = nil
local gameStoreButton = nil
local msgWindow = nil
local transferWindow = nil

local premiumPoints = 0
local premiumSecondPoints = -1

local CATEGORY_NONE = -1
local CATEGORY_PREMIUM = 0
local CATEGORY_ITEM = 1
local CATEGORY_BLESSING = 2
local CATEGORY_OUTFIT = 3
local CATEGORY_MOUNT = 4
local CATEGORY_EXTRAS = 5

local searchResultCategoryId = "Search Results"

function init()
  connect( g_game, {
      onGameStart = create,
      onGameEnd = destroy
  })

  ProtocolGame.registerExtendedOpcode(GAME_STORE_CODE, onExtendedOpcode)
  if g_game.isOnline() then
    create()
  end
end

function terminate()
  disconnect( g_game, {
      onGameStart = create,
      onGameEnd = destroy
  })

  ProtocolGame.unregisterExtendedOpcode(GAME_STORE_CODE, onExtendedOpcode)
  destroy()
end

function onExtendedOpcode(protocol, code, buffer)
  local json_status, json_data = pcall(function() return json.decode(buffer) end)
  if not json_status then
    g_logger.error("SHOP json error: " .. json_data)
    return false
  end

  local action = json_data["action"]
  local data = json_data["data"]
  if not action or not data then
    return false
  end

  if action == "fetchBase" then
    onGameStoreFetchBase(data)
  elseif action == "fetchOffers" then
    onGameStoreFetchOffers(data)
  elseif action == "points" then
    onGameStoreUpdatePoints(data)
  elseif action == "history" then
    onGameStoreUpdateHistory(data)
  elseif action == "msg" then
    onGameStoreMsg(data)
  end
end

function create()
  if gameStoreWindow then
    return
  end
  gameStoreWindow = g_ui.displayUI("game_store")
  gameStoreWindow:hide()

  gameStoreButton = modules.client_topmenu.addRightGameToggleButton('gameStoreButton', tr('Store'), '/images/topbuttons/shop', toggle, false, 8)

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(GAME_STORE_CODE, json.encode({ action = "fetch", data = {} }))
  end
  createTransferWindow()
end

function destroy()
  if gameStoreButton then
    gameStoreButton:destroy()
    gameStoreButton = nil
  end

  if gameStoreWindow then
    gameStoreWindow:destroy()
    gameStoreWindow = nil
  end

  if msgWindow then
    msgWindow:destroy()
    msgWindow = nil
  end

  if changeNameWindow then
    changeNameWindow:destroy()
    changeNameWindow = nil
  end

  if transferWindow then
    transferWindow:destroy()
    transferWindow = nil
  end
  
  selected = nil
  selectedOffer = nil
end

function onGameStoreFetchBase(data)
  for i = 1, #data.categories do
    addCategory(data.categories[i])
  end

  DONATION_URL = data.url
end

function hideTransferWindow()
  if transferWindow then
    transferWindow:hide()
  end
end

function show()
  hideTransferWindow()
  if not gameStoreWindow or not gameStoreButton then
    return
  end
  
  hideHistory()
  gameStoreWindow:show()
  gameStoreWindow:raise()
  gameStoreWindow:focus()
end

function hide()
  hideTransferWindow()
  if gameStoreWindow then
    gameStoreWindow:hide()
  end
end

function showHistory()
  deselect()
  gameStoreWindow:getChildById("offers"):hide()
  gameStoreWindow:getChildById("history"):show()
end

function hideHistory()
  gameStoreWindow:getChildById("offers"):show()
  gameStoreWindow:getChildById("history"):hide()
end

local entriesPerPage = 26
local currentPage = 1
local totalPages = 1

function updateHistory()
  local historyPanel = gameStoreWindow:getChildById("history")
  local historyList = historyPanel:getChildById("list")
  historyList:destroyChildren()

  local index = ((currentPage - 1) * entriesPerPage) + 1
  for i = index, math.min(#history, index + entriesPerPage - 1) do
    local widget = g_ui.createWidget("HistoryWidget", historyList)
    widget:getChildById("date"):setText(history[i].date)
    widget:getChildById("price"):setText((history[i].price > 0 and "+" or "") .. comma_value(history[i].price))
    widget:getChildById("price"):setOn(history[i].price > 0)
    widget:getChildById("coin"):setOn(history[i].isSecondPrice)

    if history[i].count > 1 then
      widget:getChildById("description"):setText(history[i].count .. " " .. history[i].name)
    else
      widget:getChildById("description"):setText(history[i].name)
    end
  end

  historyPanel:getChildById("pageLabel"):setText("Page " .. currentPage .. "/" .. totalPages)
end

function onGameStoreUpdateHistory(historyList)
  -- date
  -- price
  -- name
  -- count
  currentPage = 1
  history = historyList
  totalPages = math.max(1, math.ceil(#history / entriesPerPage))

  local historyPanel = gameStoreWindow:getChildById("history")
  updateHistory()
  historyPanel:getChildById("nextPageButton"):setVisible(totalPages > 1)
end

function prevPage()
  if currentPage == 1 then
    return true
  end

  currentPage = currentPage - 1

  local historyPanel = gameStoreWindow:getChildById("history")
  updateHistory()
  
  historyPanel:getChildById("nextPageButton"):setVisible(currentPage < totalPages)
  historyPanel:getChildById("prevPageButton"):setVisible(currentPage > 1)
end

function nextPage()
  if currentPage == totalPages then
    return true
  end

  currentPage = currentPage + 1

  local historyPanel = gameStoreWindow:getChildById("history")
  updateHistory()

  historyPanel:getChildById("nextPageButton"):setVisible(currentPage < totalPages)
  historyPanel:getChildById("prevPageButton"):setVisible(currentPage > 1)
end

function deselect()
  if selected then
    selected:getChildById("button"):setChecked(false)
    local arrow = selected:getChildById("selectArrow")
    if arrow then
      arrow:hide()
    end

    if not selected:getChildById("subCategories") then
      selected = selected:getParent():getParent()
      selected:getChildById("expandArrow"):show()
    end

    selected:setHeight(22)
    selected:getChildById("subCategories"):hide()
  end
end

function comma_value(n)
  local left, num, right = string.match(n, "^([^%d]*%d)(%d*)(.-)$")
  return left .. (num:reverse():gsub("(%d%d%d)", "%1,"):reverse()) .. right
end

function buyPoints()
  g_platform.openUrl(DONATION_URL)
end

function onGameStoreFetchOffers(data)
  -- parent
  -- name
  -- id
  -- price
  -- isSecondPrice
  -- count
  -- description
  -- categoryId
  offers[data.category] = data.offers
  if not selected and data.category == "Premium Time" then
    select(gameStoreWindow:getChildById("categoriesList"):getChildren()[1]:getChildById("button"))
  end
end

function addCategory(data)
  -- title
  -- parent
  -- iconId
  -- categoryId
  -- description

  categories[data.title] = data

  local categoriesList = gameStoreWindow:getChildById("categoriesList")
  local category
  if data.parent then
    local parentPanel = categoriesList:getChildById(data.parent)
    category = g_ui.createWidget("ShopSubCategory", parentPanel:getChildById("subCategories"))
    parentPanel:getChildById("expandArrow"):show()
  else
    category = g_ui.createWidget("ShopCategory", categoriesList)
  end

  category:setId(data.title)
  category:getChildById("button"):setIconClip(data.iconId * 13 .. " 0 13 13")
  category:getChildById("name"):setText(data.title)
end

function onGameStoreUpdatePoints(data)
  premiumPoints = tonumber(data.points)
  premiumSecondPoints = tonumber(data.secondPoints)
  local pointsWidget = gameStoreWindow:getChildById("balance"):getChildById("value")
  pointsWidget:setText(comma_value(premiumPoints))
  
  local balanceSecondWidget = gameStoreWindow:getChildById("balanceSecond")
  if premiumSecondPoints ~= -1 then
    balanceSecondWidget:getChildById("value"):setText(comma_value(premiumSecondPoints))
    balanceSecondWidget:show()
    balanceSecondWidget:setWidth(105)
    balanceSecondWidget:setMarginLeft(6)
    transferWindow.taskPointsLabelCoin:show()
    transferWindow.taskPointsAmountScrollbar:show()
    transferWindow.taskPointsCoin:show()
    transferWindow.taskPointsBalance:show()
    transferWindow.taskPointsBalance:setText(tr('Transferable Task points: ') .. comma_value(premiumSecondPoints))
    transferWindow.taskPointsAmountScrollbar:setMaximum(premiumSecondPoints)
  else
    balanceSecondWidget:hide()
    balanceSecondWidget:setWidth(1)
    balanceSecondWidget:setMarginLeft(0)
    transferWindow.taskPointsBalance:hide()
    transferWindow.taskPointsLabelCoin:hide()
    transferWindow.taskPointsAmountScrollbar:hide()
    transferWindow.taskPointsCoin:hide()
  end

  transferWindow.coinsBalance:setText(tr('Transferable Tibia Coins: ') .. comma_value(premiumPoints))
  transferWindow.coinsAmountScrollbar:setMaximum(premiumPoints)
end

function select(self, ignoreSearch)
  hideHistory()
  if not ignoreSearch then
    eraseSearchResults()
  end

  local selfParent = self:getParent()
  local panel = selfParent:getChildById("subCategories")
  if panel then
    deselect()
    selected = selfParent

    if panel:getChildCount() > 0 then
      panel:show()
      selfParent:setHeight((panel:getChildCount() + 1) * 22)
      selfParent:getChildById("expandArrow"):hide()
      select(panel:getChildren()[1]:getChildById("button"))
    else
      self:setChecked(true)
    end
  else
    if selected then
      selected:getChildById("button"):setChecked(false)

      local arrow = selected:getChildById("selectArrow")
      if arrow then
        arrow:hide()
      end
    end

    selected = selfParent

    self:setChecked(true)
    selfParent:getChildById("selectArrow"):show()
  end

  showOffers(selfParent:getId())
end

function selectOffer(self)
  if selectedOffer then
    selectedOffer:setChecked(false)
  end

  self:setChecked(true)
  selectedOffer = self

  updateDescription(self)
end

function showOffers(id)
  local offersCache = offers[id]
  if not offersCache then
    return
  end

  local currentOutfit = g_game.getLocalPlayer():getOutfit()
  local offersPanel = gameStoreWindow:getChildById("offers")
  local offersList = offersPanel:getChildById("offersList")
  offersList:destroyChildren()

  for i = 1, #offersCache do
    local widget = offersList:getChildById(offersCache[i].name)
    local price = offersCache[i].price
    if widget then
      local additionalPriceWidget = widget:getChildById("additionalPrice")
      additionalPriceWidget:getChildById("coin"):setOn(offersCache[i].isSecondPrice)
      additionalPriceWidget:getChildById("value"):setText(comma_value(price))
      additionalPriceWidget:show()

      local additionalCountWidget = widget:getChildById("additionalCount")
      additionalCountWidget:setText(offersCache[i].count .. "x")
      additionalCountWidget:show()

      widget:getChildById("count"):show()
      widget.additionalPriceValue = price
      widget.additionalIsSecondPrice = isSecondPrice
      widget.additionalCountValue = offersCache[i].count
      
      if i == 2 then
        selectOffer(widget)
      end
    else
      local widget = g_ui.createWidget("OfferWidget", offersList)
      local priceWidget = widget:getChildById("price")
      priceWidget:getChildById("coin"):setOn(offersCache[i].isSecondPrice)
      priceWidget:getChildById("value"):setText(comma_value(price))

      widget:getChildById("name"):setText(offersCache[i].name)
      widget:getChildById("count"):setText(offersCache[i].count .. "x")
      widget:setId(offersCache[i].name)
      widget.data = offersCache[i]
      widget.categoryId = id

      local imagePanel = widget:getChildById("imagePanel")

      if type(offersCache[i].id) == "string" then
        local image = imagePanel:getChildById("image")
        image:show()
        image:setImageSource("/images/store/" .. offersCache[i].id)
      elseif type(offersCache[i].id) == "number" then
        local categoryId = offersCache[i].categoryId
        widget.offerCategoryId = categoryId
        if categoryId == CATEGORY_ITEM then
          local item = imagePanel:getChildById("item")
          item:show()
          item:setItemId(offersCache[i].id)
        elseif categoryId == CATEGORY_OUTFIT then
          local outfit = imagePanel:getChildById("outfit")
          currentOutfit.type = offersCache[i].id
          outfit:show()
          outfit:setOutfit(currentOutfit)
        elseif categoryId == CATEGORY_MOUNT then
          local mount = imagePanel:getChildById("mount")
          mount:show()
          mount:setOutfit({ type = offersCache[i].id })
        end
      end
      
      if i == 1 then
        selectOffer(widget)
      end
    end
  end
end

function updateDescription(self)
  local offersPanel = gameStoreWindow:getChildById("offers")
  local offerDetails = offersPanel:getChildById("offerDetails")
  offerDetails:show()
  offerDetails:getChildById("name"):setText(self.data.name)

  local descriptionPanel = offerDetails:getChildById("description")
  local widget = descriptionPanel:getChildren()[1]
  if not widget then
    widget = g_ui.createWidget("OfferDescripionLabel", descriptionPanel)
  end

  local description = categories[self.categoryId].description
  if not description or description == "" then
    description = self.data.description
  end

  widget:setText(description)

  local buyButton = offerDetails:getChildById("buyButton")
  local priceWidget = offerDetails:getChildById("price")
  local additionalBuyButton = offerDetails:getChildById("additionalBuyButton")
  local additionalPriceWidget = offerDetails:getChildById("additionalPrice")
  
  priceWidget:setOn(self.data.isSecondPrice)
  priceWidget:setText(comma_value(self.data.price))

  local globalPoints = self.data.isSecondPrice and premiumSecondPoints or premiumPoints
  priceWidget:setEnabled(self.data.price <= globalPoints)
  buyButton:setEnabled(self.data.price <= globalPoints)

  if self.additionalPriceValue and self.additionalCountValue then
    buyButton:setText("Buy " .. self.data.count)

    additionalPriceWidget:setEnabled(self.additionalPriceValue <= globalPoints)
    additionalBuyButton:setText("Buy " .. self.additionalCountValue)
    additionalBuyButton:show()
    additionalBuyButton:setEnabled(self.additionalPriceValue <= globalPoints)
    additionalBuyButton.price = self.additionalPriceValue
    additionalBuyButton.count = self.additionalCountValue
    buyButton.secondPrice = self.data.secondPrice
    buyButton.price = self.data.price
    buyButton.count = self.data.count

    additionalPriceWidget:setOn(self.data.isSecondPrice)
    additionalPriceWidget:setText(comma_value(self.additionalPriceValue))
    additionalPriceWidget:show()
  else
    additionalBuyButton:hide()

    buyButton.secondPrice = nil
    buyButton.price = nil
    buyButton.count = nil

    buyButton:setText("Buy")
    additionalPriceWidget:hide()
  end

  local currentOutfit = g_game.getLocalPlayer():getOutfit()
  local imagePanel = offerDetails:getChildById("imagePanel")
  local image = imagePanel:getChildById("image")
  local item = imagePanel:getChildById("item")
  local outfit = imagePanel:getChildById("outfit")
  local mount = imagePanel:getChildById("mount")
  image:hide()
  item:hide()
  outfit:hide()
  mount:hide()
  if type(self.data.id) == "string" then
    image:show()
    image:setImageSource("/images/store/" .. self.data.id)
  elseif type(self.data.id) == "number" then
    -- local categoryId = categories[self.categoryId].categoryId
    local categoryId = self.offerCategoryId
    if categoryId == CATEGORY_ITEM then
      item:show()
      item:setItemId(self.data.id)
    elseif categoryId == CATEGORY_OUTFIT then
      currentOutfit.type = self.data.id
      outfit:show()
      outfit:setOutfit(currentOutfit)
    elseif categoryId == CATEGORY_MOUNT then
      mount:show()
      mount:setOutfit({ type = self.data.id })
    end
  end
end

function onOfferBuy(self)
  if not selectedOffer then
    displayInfoBox("Error", "Something went wrong, make sure to select category and offer.")
    return
  end

  hide()

  local title = "Purchase Confirmation"
  local msg
  if self.count and self.count > 1 then
    msg = "Do you want to buy " .. self.count .. "x " .. selectedOffer.data.name .. " for " .. comma_value(self.price) .. " points?"
  else
    msg = "Do you want to buy " .. selectedOffer.data.name .. " for " .. comma_value(selectedOffer.data.price) .. " points?"
  end

  if selectedOffer.data.name == "Name Change" then
    msgWindow = displayGeneralBox( title, msg, {
      { text = "Yes", callback = changeName },
      { text = "No",  callback = buyCanceled },
      anchor = AnchorHorizontalCenter
    }, changeName, buyCanceled)
  else
    msgWindow = displayGeneralBox( title, msg, {
      { text = "Yes", callback = buyConfirmed },
      { text = "No",  callback = buyCanceled },
      anchor = AnchorHorizontalCenter
    }, buyConfirmed, buyCanceled)
  end
  
  if self.count and self.count > 1 then
    msgWindow.count = self.count
    msgWindow.price = self.price
  else
    msgWindow.count = selectedOffer.data.count
    msgWindow.price = selectedOffer.data.price
  end
end

function buyConfirmed()
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(GAME_STORE_CODE, json.encode({ action = "purchase", data = {
      count = msgWindow.count,
      price = msgWindow.price,
      name = selectedOffer.data.name,
      id = selectedOffer.data.id,
      parent = selectedOffer.data.parent
    }}))
  end
  
  msgWindow:destroy()
  msgWindow = nil
end

function buyCanceled()
  msgWindow:destroy()
  msgWindow = nil
  show()
end

function changeName()
  msgWindow:destroy()
  msgWindow = nil
  if changeNameWindow then
    return
  end

  changeNameWindow = g_ui.displayUI("changename")
end

function confirmChangeName()
  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(GAME_STORE_CODE, json.encode({ action = "purchase", data = {
      count = selectedOffer.data.count,
      price = selectedOffer.data.price,
      name = selectedOffer.data.name,
      id = selectedOffer.data.id,
      parent = selectedOffer.data.parent,
      nick = changeNameWindow:getChildById("targetName"):getText()
    }}))

    changeNameWindow:destroy()
    changeNameWindow = nil
  end
end

function cancelChangeName()
  changeNameWindow:destroy()
  changeNameWindow = nil
end

function onGameStoreMsg(data)
  local type = data.type
  local text = data.msg

  local title = nil
  local close = false
  if type == "info" then
    title = "Store Information"
    close = data.close
  elseif type == "error" then
    title = "Store Error"
    close = true
  end

  if close then
    hideHistory()
    hide()
  end

  displayInfoBoxWithCallback(title, text, { { text = "Ok", callback = defaultCallback } }, function() show() end)
end

function displayInfoBoxWithCallback(title, message, callback)
  local messageBox
  local defaultCallback = function()
    if callback then
      show()
    end
    messageBox:ok()
  end

  messageBox = UIMessageBox.display(title, message, { { text = 'Ok', callback = defaultCallback } }, defaultCallback, defaultCallback)
  return messageBox
end

function changeCoinsAmount(value)
  transferWindow:getChildById("coinsAmountLabel"):setText("Amount to gift: " .. comma_value(value))
end

function changeTaskPointsAmount(value)
  transferWindow:getChildById("taskPointsAmountLabel"):setText("Amount to gift: " .. comma_value(value))
end

function confirmGiftCoins()
  if not transferWindow then
    return
  end

  local protocolGame = g_game.getProtocolGame()
  if protocolGame then
    protocolGame:sendExtendedOpcode(GAME_STORE_CODE, json.encode({ action = "transfer", data = { 
      amount = tonumber(transferWindow.coinsAmountScrollbar:getValue()), 
      amountSecond = tonumber(transferWindow.taskPointsAmountScrollbar:getValue()), 
      target = transferWindow.recipient:getText() 
    }}))
    transferWindow.recipient:setText('')
    transferWindow.coinsAmountScrollbar:setValue(0)
    transferWindow.taskPointsAmountScrollbar:setValue(0)
  end
end

function cancelGiftCoins()
  if transferWindow then
    transferWindow:hide()
    show()
  end
end

function createTransferWindow()
  if not transferWindow then
    transferWindow = g_ui.displayUI('giftcoins')
    transferWindow:hide()
  end
end

function toggle()
  if not gameStoreWindow then
    return
  end

  if gameStoreWindow:isVisible() then
    return hide()
  end

  show()
end

function toggleGiftCoins()
  if transferWindow then
    hide()
    transferWindow:show()
    transferWindow:raise()
    transferWindow:focus()
    transferWindow:setOn(premiumSecondPoints ~= -1)
  end
end

function onTypeSearch(self)
  gameStoreWindow:getChildById("searchButton"):setEnabled(#self:getText() > 2)
end

function eraseSearchResults()
  local widget = gameStoreWindow:getChildById("categoriesList"):getChildById(searchResultCategoryId)
  if widget then
    if selected == widget then
      selected = nil
    end
    widget:destroy()
  end
end

function onSearch()
  local searchTextEdit = gameStoreWindow:getChildById("searchTextEdit")
  local text = searchTextEdit:getText()
  if #text < 3 then
    return
  end

  eraseSearchResults()
  addCategory({
    title = searchResultCategoryId,
    iconId = 7,
    categoryId = CATEGORY_NONE
  })

  offers[searchResultCategoryId] = {}
  for categoryId, offerData in pairs(offers) do
    for _, offer in pairs(offerData) do
      if string.find(offer.name:lower(), text) then
       table.insert(offers[searchResultCategoryId], offer)
      end
    end
  end

  local children = gameStoreWindow:getChildById("categoriesList"):getChildren()
  select(children[#children]:getChildById("button"), true)
  searchTextEdit:clearText()
end
