-- ExtendedHotbarLocalScript.lua
-- LocalScript (colocar em StarterPlayerScripts)
-- Versão: 1.0
-- Objetivo: adicionar 3 slots extras (total 6) à hotbar para Mobile, sem substituir o UI original.
-- Observações: acessa somente objetos seguros no client; não modifica CoreGui.

-- Serviços
local Players = game:GetService("Players")
local RunService = game:GetService("RunService")

local player = Players.LocalPlayer
if not player then
    -- Segurança: se o script for executado em ambiente diferente
    return
end

-- Configurações
local GUI_NAME = "ExtendedHotbarGui_v1" -- evita duplicação entre execuções
local SLOT_COUNT = 6
local CONTAINER_SCALE_X = 0.7 -- tamanho da hotbar em relação à largura da tela
local CONTAINER_HEIGHT = 64 -- altura em pixels (ajustável)
local SLOT_PADDING_PX = 6 -- padding entre slots

-- Variáveis de estado
local playerGui = nil
local screenGui = nil
local container = nil
local slots = {} -- tabela de frames/buttons dos slots
local updateConnections = {} -- conexões que devem ser limpas (ex: ChildAdded)
local currentEquippedTool = nil

-- Utilitários seguros
local function safeFindPlayerGui()
    -- Wait e validação segura do PlayerGui (PlayerGui pode ser recriado)
    local gui = player:FindFirstChild("PlayerGui")
    if not gui then
        gui = player:WaitForChild("PlayerGui", 5) -- timeout curto
    end
    return gui
end

local function disconnectAll(connTable)
    for i, conn in ipairs(connTable) do
        if conn and conn.Disconnect then
            pcall(function() conn:Disconnect() end)
        elseif conn and conn.disconnect then
            pcall(function() conn:disconnect() end)
        end
        connTable[i] = nil
    end
end

-- Tenta extrair um ícone da Tool de forma robusta
local function getToolIcon(tool)
    if not tool then return "" end
    -- tentativas comuns (seguras com pcall)
    local ok, icon
    ok, icon = pcall(function() return tool.TextureId end)
    if ok and icon and icon ~= "" then return icon end
    ok, icon = pcall(function() return tool.Icon end)
    if ok and icon and icon ~= "" then return icon end
    -- procurar StringValue chamado "Icon" ou "TextureId"
    local sv = tool:FindFirstChildWhichIsA("StringValue")
    if sv and sv.Value and sv.Value ~= "" then
        return sv.Value
    end
    local any = tool:FindFirstChild("Icon") or tool:FindFirstChild("TextureId")
    if any and any:IsA("StringValue") and any.Value ~= "" then
        return any.Value
    end
    -- fallback: ícone vazio (o botão ficará sem imagem)
    return ""
end

-- Recolhe a lista de tools: equipado + backpack (ordem previsível)
local function gatherToolList()
    local list = {}
    -- Equipado (ferramentas dentro do Character costumam ser as equipadas)
    local character = player.Character
    if character then
        for _, child in ipairs(character:GetChildren()) do
            if child:IsA("Tool") then
                table.insert(list, child)
            end
        end
    end
    -- Backpack (cliente pode acessar player:FindFirstChild("Backpack"))
    local backpack = player:FindFirstChild("Backpack")
    if backpack then
        for _, child in ipairs(backpack:GetChildren()) do
            if child:IsA("Tool") then
                if not table.find(list, child) then
                    table.insert(list, child)
                end
            end
        end
    end
    return list
end

-- Atualiza a seleção visual nos slots
local function updateSelectionVisuals()
    for i = 1, SLOT_COUNT do
        local slot = slots[i]
        if slot then
            local highlight = slot:FindFirstChild("Selection")
            local assignedTool = slot:GetAttribute("AssignedTool")
            if assignedTool and currentEquippedTool and assignedTool == currentEquippedTool then
                if highlight then highlight.Visible = true end
            else
                if highlight then highlight.Visible = false end
            end
        end
    end
end

-- Função para equipar uma Tool (tentativa segura)
local function equipTool(tool)
    if not tool then return end
    -- Se já estiver na Character, assume equipado (mas podemos tentar equipar)
    local character = player.Character
    if not character then return end
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if not humanoid then return end
    pcall(function()
        humanoid:EquipTool(tool)
    end)
end

-- Atualiza ícones e atributos dos slots conforme tools disponíveis
local function refreshSlots()
    local tools = gatherToolList()
    for i = 1, SLOT_COUNT do
        local slot = slots[i]
        if not slot then break end
        local tool = tools[i]
        slot:SetAttribute("AssignedTool", tool) -- armazenamos referência (pode ser nil)
        local img = slot:FindFirstChild("Icon")
        local countLabel = slot:FindFirstChild("CountLabel")
        if tool then
            -- definir ícone
            local iconId = getToolIcon(tool)
            if img and iconId and iconId ~= "" then
                img.Image = iconId
                img.ImageColor3 = Color3.new(1,1,1)
                img.Visible = true
            else
                -- se sem ícone, podemos tentar usar um placeholder ou deixar vazio
                if img then
                    img.Image = "" -- sem imagem
                    img.Visible = false
                end
            end
            -- contagem (caso tenha stack/count) - a maioria das Tools não tem count; deixamos oculto por padrão
            if countLabel then
                countLabel.Text = ""
                countLabel.Visible = false
            end
        else
            -- sem tool: limpar visual
            if img then
                img.Image = ""
                img.Visible = false
            end
            if countLabel then
                countLabel.Text = ""
                countLabel.Visible = false
            end
        end
    end
    updateSelectionVisuals()
end

-- Cria a GUI sem duplicar; estilo simples para combinar com Hotbar padrão
local function createGui()
    playerGui = safeFindPlayerGui()
    if not playerGui then
        warn("[ExtendedHotbar] PlayerGui não encontrado; GUI não criada.")
        return
    end

    -- Evitar criar múltiplas cópias
    local existing = playerGui:FindFirstChild(GUI_NAME)
    if existing then
        screenGui = existing
        -- tenta reapontar container/slots caso já existam
        container = screenGui:FindFirstChild("HotbarContainer")
        if container then
            for i = 1, SLOT_COUNT do
                local slot = container:FindFirstChild("Slot"..i)
                if slot then
                    slots[i] = slot
                end
            end
        end
        return
    end

    -- Criar ScreenGui
    screenGui = Instance.new("ScreenGui")
    screenGui.Name = GUI_NAME
    screenGui.ResetOnSpawn = false
    screenGui.Parent = playerGui

    -- Container principal
    container = Instance.new("Frame")
    container.Name = "HotbarContainer"
    container.BackgroundTransparency = 1
    container.Size = UDim2.new(CONTAINER_SCALE_X, 0, 0, CONTAINER_HEIGHT)
    container.AnchorPoint = Vector2.new(0.5, 1)
    container.Position = UDim2.new(0.5, 0, 1, -80) -- 80px acima da linha inferior (ajustável)
    container.Parent = screenGui

    -- Layout horizontal
    local listLayout = Instance.new("UIListLayout")
    listLayout.Padding = UDim.new(0, SLOT_PADDING_PX)
    listLayout.FillDirection = Enum.FillDirection.Horizontal
    listLayout.HorizontalAlignment = Enum.HorizontalAlignment.Center
    listLayout.VerticalAlignment = Enum.VerticalAlignment.Center
    listLayout.SortOrder = Enum.SortOrder.LayoutOrder
    listLayout.Parent = container

    -- Criar slots
    for i = 1, SLOT_COUNT do
        local btn = Instance.new("ImageButton")
        btn.Name = "Slot"..i
        btn.BackgroundColor3 = Color3.fromRGB(28, 28, 28)
        btn.BackgroundTransparency = 0.15
        btn.BorderSizePixel = 0
        btn.Size = UDim2.new(1 / SLOT_COUNT, 0, 1, 0) -- divide proporcionalmente o container
        btn.AutoButtonColor = false
        btn.Parent = container

        -- Ícone interno
        local icon = Instance.new("ImageLabel")
        icon.Name = "Icon"
        icon.BackgroundTransparency = 1
        icon.Size = UDim2.new(0.9, 0, 0.9, 0)
        icon.Position = UDim2.new(0.5, 0, 0.5, 0)
        icon.AnchorPoint = Vector2.new(0.5, 0.5)
        icon.Image = ""
        icon.ScaleType = Enum.ScaleType.Fit
        icon.Parent = btn

        -- Selection highlight (borda)
        local selection = Instance.new("Frame")
        selection.Name = "Selection"
        selection.AnchorPoint = Vector2.new(0.5, 0.5)
        selection.Position = UDim2.new(0.5, 0, 0.5, 0)
        selection.Size = UDim2.new(0.95, 0, 0.95, 0)
        selection.BackgroundTransparency = 1
        selection.BorderColor3 = Color3.fromRGB(255, 204, 51)
        selection.BorderSizePixel = 2
        selection.Visible = false
        selection.Parent = btn

        -- Count label (caso queira mostrar quantidade)
        local count = Instance.new("TextLabel")
        count.Name = "CountLabel"
        count.Size = UDim2.new(0, 24, 0, 18)
        count.Position = UDim2.new(1, -26, 1, -20)
        count.AnchorPoint = Vector2.new(0, 0)
        count.BackgroundTransparency = 0.4
        count.BackgroundColor3 = Color3.fromRGB(0, 0, 0)
        count.TextColor3 = Color3.new(1, 1, 1)
        count.TextScaled = true
        count.Text = ""
        count.Visible = false
        count.Parent = btn

        -- Clique / toque (Activated funciona para touch)
        btn.Activated:Connect(function()
            local assignedTool = btn:GetAttribute("AssignedTool")
            if assignedTool and assignedTool:IsA("Tool") then
                equipTool(assignedTool)
            end
        end)

        slots[i] = btn
    end
end

-- Observadores para mudanças nas ferramentas / respawn
local function hookToolEventsForCharacter(character)
    -- desconectar conexões anteriores relacionadas ao character
    disconnectAll(updateConnections)

    -- observar Tool equipados via ChildAdded no Character
    local conn1 = character.ChildAdded:Connect(function(child)
        if child:IsA("Tool") then
            -- se uma tool foi adicionada ao character, é provável que seja equipada
            currentEquippedTool = child
            refreshSlots()
        end
    end)
    table.insert(updateConnections, conn1)

    -- observar Tool removidos do Character
    local conn2 = character.ChildRemoved:Connect(function(child)
        if child:IsA("Tool") then
            if currentEquippedTool == child then
                currentEquippedTool = nil
            end
            -- atraso pequeno para sincronizar com backpack
            delay(0.1, refreshSlots)
        end
    end)
    table.insert(updateConnections, conn2)

    -- conectar Equip/Unequip em Tools já presentes no character (para maior precisão)
    for _, child in ipairs(character:GetChildren()) do
        if child:IsA("Tool") then
            -- Tool.Equipped -> atualiza highlighted
            local equipConn
            equipConn = child.Equipped:Connect(function()
                currentEquippedTool = child
                refreshSlots()
            end)
            table.insert(updateConnections, equipConn)

            local unequipConn
            unequipConn = child.Unequipped:Connect(function()
                if currentEquippedTool == child then
                    currentEquippedTool = nil
                end
                refreshSlots()
            end)
            table.insert(updateConnections, unequipConn)
        end
    end

    -- também observar humanoid (opcional)
    local humanoid = character:FindFirstChildOfClass("Humanoid")
    if humanoid then
        local healthConn = humanoid.Died:Connect(function()
            currentEquippedTool = nil
            refreshSlots()
        end)
        table.insert(updateConnections, healthConn)
    end
end

local function hookBackpackEvents()
    local backpack = player:FindFirstChild("Backpack")
    if not backpack then
        backpack = player:WaitForChild("Backpack", 5)
    end
    if not backpack then
        return
    end

    -- ChildAdded/Removed -> atualizar hotbar
    local connA = backpack.ChildAdded:Connect(function()
        -- pequeno atraso para garantir que objeto esteja pronto
        delay(0.05, refreshSlots)
    end)
    table.insert(updateConnections, connA)

    local connB = backpack.ChildRemoved:Connect(function()
        delay(0.05, refreshSlots)
    end)
    table.insert(updateConnections, connB)
end

-- Inicialização principal e monitoramento de respawn / PlayerGui recriação
local function init()
    -- Criar GUI (ou reaproveitar se já existir)
    createGui()

    -- Se não houver container/slots por algum motivo, aborta com aviso
    if not container then
        warn("[ExtendedHotbar] Container não criado.")
        return
    end

    -- Atualiza periodicamente / on render para manter sincronia (leve)
    -- Use RunService.Heartbeat com baixa frequência para evitar custo alto
    local updateTick = 0
    local updateInterval = 0.35
    local hbConn
    hbConn = RunService.Heartbeat:Connect(function(dt)
        updateTick = updateTick + dt
        if updateTick >= updateInterval then
            updateTick = 0
            refreshSlots()
        end
    end)
    table.insert(updateConnections, hbConn)

    -- Character respawn handling
    if player.Character then
        hookToolEventsForCharacter(player.Character)
    end
    local charConn = player.CharacterAdded:Connect(function(char)
        -- limpar conexões antigas relacionadas ao character
        disconnectAll(updateConnections)
        hookToolEventsForCharacter(char)
        hookBackpackEvents()
        -- recriar GUI se por algum motivo foi removido
        createGui()
        refreshSlots()
    end)
    table.insert(updateConnections, charConn)

    -- PlayerGui pode ser recriado; observa e garante que nossa GUI exista
    playerGui = safeFindPlayerGui()
    if playerGui then
        local guiConn = playerGui.ChildRemoved:Connect(function(child)
            if child and child.Name == GUI_NAME then
                -- recriar GUI
                delay(0.05, function()
                    createGui()
                    refreshSlots()
                end)
            end
        end)
        table.insert(updateConnections, guiConn)
    end

    -- Hook backpack events e atualizar inicial
    hookBackpackEvents()
    refreshSlots()
end

-- Execução
-- Protege para evitar execuções duplicadas caso o LocalScript rode múltiplas vezes
local alreadyRunning = false
if alreadyRunning then return end
alreadyRunning = true

-- Tenta iniciar; espera PlayerGui e Character quando necessário
spawn(function()
    -- garantir PlayerGui disponível
    playerGui = safeFindPlayerGui()
    if not playerGui then
        warn("[ExtendedHotbar] PlayerGui não disponível.")
    end
    init()
end)