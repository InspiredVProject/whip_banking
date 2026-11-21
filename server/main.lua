local CORE = exports.whip_core
local sessions = {}
local tellerSessions = {}
local processing = {}
local ready = false
local spawned = {}
local bankBlipsReady = false
local bankBlipIds = {}
local BANK_KEYS = {fleeca=true,maze=true,pacific=true}
local CARD_STYLES = {classic=true,black=true,metal=true}

-- WHIP's pause-map reads names from the labels owned by whip_core/client/blips.lua.
-- Native AddBlipForCoord markers DO NOT have a name in that map, even when
-- BeginTextCommandSetBlipName or SetBlipCategory is used. Register these through
-- WHIP's own ShowBlip export so both the pause-map legend and GPS get real labels.
local function refreshBankBlips()
    if not bankBlipsReady then return end
    local options = type(Config.Blips) == 'table' and Config.Blips or {}
    local wanted = {}

    if options.Enabled ~= false then
        local sprite = math.floor(tonumber(options.Sprite) or 108)
        local colour = math.floor(tonumber(options.Colour) or 1)
        local scale = math.max(0.3, math.min(1.5, tonumber(options.Scale) or 0.78))
        local brand = type(Config.Brand) == 'string' and Config.Brand ~= '' and Config.Brand or 'Maze Bank'
        local label = type(options.LegendName) == 'string'
            and options.LegendName:match('^%s*(.-)%s*$') or ''
        if label == '' then
            label = brand:lower():gsub('(%a)([%w]*)', function(first, rest)
                return first:upper() .. rest
            end)
        end

        for i, branch in ipairs(Config.Branches or {}) do
            local point = branch.coords
            local x = point and tonumber(point.x)
            local y = point and tonumber(point.y)
            local z = point and tonumber(point.z)
            if x and y and z then
                local id = 'maze_bank_branch_' .. i
                local branchName = type(branch.name) == 'string' and branch.name ~= ''
                    and branch.name or ('Branch ' .. i)
                -- WHIP groups identical names in its legend. Default shows
                -- "Maze Bank" with a count of all branches; the optional
                -- branch-name setting lists them separately instead.
                local blipLabel = options.BranchNames == true
                    and (label .. ' - ' .. branchName) or label
                local ok, why = CORE:ShowBlip('everyone', id, {
                    coords = {x = x, y = y, z = z},
                    label = blipLabel,
                    sprite = sprite,
                    color = colour,
                    scale = scale,
                    shortRange = options.ShortRange ~= false
                })
                if ok then
                    wanted[id] = true
                else
                    print(('[whip_banking] Could not register bank blip %s: %s'):format(id, tostring(why)))
                end
            end
        end
    end

    for id in pairs(bankBlipIds) do
        if not wanted[id] then CORE:HideBlip(id) end
    end
    bankBlipIds = wanted
end

local function spawnTeller(i)
    if spawned[i] then
        CORE:DespawnNpc(spawned[i])
        spawned[i] = nil
    end
    local entry = Config.Branches[i]
    if not entry then return end
    local id, why = CORE:SpawnNpc({
        model = Config.TellerModel, coords = entry.teller, behaviour = 'stand',
        conditions = {invincible=true, canMove=false, reacts=false, flees=false}
    }, {fightBack=false})
    if id then spawned[i] = id else print('[whip_banking] Teller '..i..': '..tostring(why)) end
end

-- /whip coordinates are persisted and replicated. Move only the changed NPC at runtime,
-- avoiding duplicate networked peds and leaving all outstanding teller sessions valid.
Whip.onConfigChanged('Branches', function(_, _, path)
    refreshBankBlips()
    local i = type(path) == 'string' and tonumber(path:match('^Branches%.(%d+)%.teller$')) or nil
    if i and spawned[i] then spawnTeller(i) end
end)
Whip.onConfigChanged('Blips', refreshBankBlips)
Whip.onConfigChanged('Brand', refreshBankBlips)
Whip.onConfigChanged('TellerModel', function()
    for i = 1, #Config.Branches do if spawned[i] then spawnTeller(i) end end
end)

local function epoch() return os.time() end
local function cash(n) return math.floor(tonumber(n) or 0) end
local function amount(n, cap)
    n = tonumber(n)
    if not n or n ~= n or n < 1 or n > (cap or 999999999) or n % 1 ~= 0 then return nil end
    return n
end
local function textSafe(v, limit)
    if type(v) ~= 'string' then return '' end
    return v:gsub('[%c]', ' '):sub(1, limit or 64)
end
local function char(source)
    return CORE:GetCharId(source)
end
local function bankDefinition(key)
    return (Config.Banks or {})[key or '']
end
local function profileOf(charId)
    if not ready or not charId then return nil end
    local row = MySQL.single.await('SELECT bank_key AS bankKey, UNIX_TIMESTAMP(opened_at) AS openedAt FROM whip_banking_profiles WHERE char_id=?', {charId})
    if row and BANK_KEYS[row.bankKey] then return row end
    -- Migration: characters already holding a 1.2.x Maze Bank card keep their original account/card.
    local legacy = MySQL.scalar.await('SELECT id FROM whip_banking_cards WHERE char_id=? LIMIT 1', {charId})
    if legacy then
        MySQL.insert.await("INSERT IGNORE INTO whip_banking_profiles (char_id,bank_key) VALUES (?,'maze')", {charId})
        return {bankKey='maze',legacy=true}
    end
    return nil
end
local function bankDetails(key)
    local def=bankDefinition(key)
    if not def then return nil end
    return {key=key,name=def.name,shortName=def.shortName,colour=def.colour,
        savingsApr=tonumber(def.savingsApr) or Config.SavingsApr,
        atmDailyLimit=tonumber(def.atmDailyLimit) or Config.AtmDailyLimit,
        cardItem=def.cardItem}
end
local function availableBanks()
    local out={}
    for _, key in ipairs({'fleeca','maze','pacific'}) do
        local detail=bankDetails(key)
        if detail then out[#out+1]=detail end
    end
    return out
end
local function bankAccount(id)
    local n = tonumber(id)
    if not n or n < 1 or n % 1 ~= 0 then return nil end
    return CORE:GetBankAccount(n)
end
local function myAccount(source, id, role)
    local acc = bankAccount(id)
    if not acc then return nil, 'Account not found' end
    local allowed, why = CORE:CanUseBankAccount(acc.accountId, source, role or 'view')
    if not allowed then return nil, why or 'Account access denied' end
    return acc
end
local function nearbyBranch(source)
    local ped = GetPlayerPed(source)
    if ped == 0 then return false end
    local pos = GetEntityCoords(ped)
    for i, entry in ipairs(Config.Branches) do
        local v = vector3(entry.coords.x, entry.coords.y, entry.coords.z)
        if #(pos - v) <= Config.BranchRange then return i end
    end
    return false
end
local function isTeller(source)
    local s = tellerSessions[source]
    return s and s.charId == char(source) and s.untilAt > epoch() and nearbyBranch(source) or false
end
local function push(source, message, kind)
    CORE:NotifyPlayer(source, message, kind or 'info')
end
local function reserved(source, key, fn)
    local lock = tostring(source) .. ':' .. key
    if processing[lock] then return false, 'Please wait for the previous request' end
    processing[lock] = true
    local called, a, b, c = pcall(fn)
    processing[lock] = nil
    if not called then
        print(('[whip_banking] %s: %s'):format(lock, tostring(a)))
        return false, 'The bank could not complete that request'
    end
    return a, b, c
end
local function score(charId)
    local adjustment = MySQL.scalar.await('SELECT COALESCE(SUM(points), 0) FROM whip_banking_credit WHERE char_id = ?', {charId}) or 0
    return math.max(Config.MinCredit, math.min(Config.MaxCredit, Config.DefaultCredit + tonumber(adjustment)))
end
local function changeScore(charId, points, reason)
    MySQL.insert.await('INSERT INTO whip_banking_credit (char_id, points, reason) VALUES (?, ?, ?)', {charId, points, reason})
end
local function cardRows(charId)
    return MySQL.query.await([[SELECT id, account_id AS accountId, card_number AS number, RIGHT(card_number, 4) AS last4,
      card_name AS label, COALESCE(bank_key,'maze') AS bankKey,
      COALESCE(card_style,'classic') AS cardStyle,
      COALESCE(item_name,'maze_bank_card') AS itemName,
      status, attempts, UNIX_TIMESTAMP(locked_until) AS lockedUntil,
      UNIX_TIMESTAMP(created_at) AS createdAt,
      DATE_FORMAT(DATE_ADD(created_at, INTERVAL 4 YEAR),'%m/%y') AS expires,
      UNIX_TIMESTAMP(DATE_ADD(created_at, INTERVAL 4 YEAR)) AS expiresAt
      FROM whip_banking_cards WHERE char_id=? ORDER BY id DESC]], {charId}) or {}
end
local function myLoans(charId)
    return MySQL.query.await([[SELECT id, product, principal, remaining, rate, installment, term_months AS months,
      account_id AS accountId, period_paid AS periodPaid, status,
      UNIX_TIMESTAMP(next_due) AS nextDue, UNIX_TIMESTAMP(created_at) AS createdAt
      FROM whip_banking_loans WHERE char_id=? ORDER BY id DESC]], {charId}) or {}
end
local function getBills(charId)
    return MySQL.query.await([[SELECT id, title, category, amount, status, creditor_account_id AS creditorAccountId,
      UNIX_TIMESTAMP(due_at) AS dueAt, UNIX_TIMESTAMP(created_at) AS createdAt
      FROM whip_banking_bills WHERE char_id=? ORDER BY due_at ASC, id DESC LIMIT 80]], {charId}) or {}
end
local function getSchedules(charId)
    return MySQL.query.await([[SELECT id, label, from_account_id AS fromId, to_account_id AS toId, amount, frequency_days AS days,
      status, UNIX_TIMESTAMP(next_at) AS nextAt FROM whip_banking_schedules WHERE char_id=? ORDER BY id DESC LIMIT 80]], {charId}) or {}
end
local function summary(source, player)
    local charId = player.charId
    local accounts = CORE:GetCharacterBankAccounts(charId) or {}
    local main = CORE:GetDefaultBankAccount(source)
    local tx = main and CORE:GetBankTransactions(main.accountId, 85, 0) or {}
    local total = 0
    for _, a in ipairs(accounts) do
        a.balance = cash(a.balance)
        if a.type ~= 'job' then total = total + a.balance end
    end
    local selected=profileOf(charId)
    local bankKey=selected and selected.bankKey or nil
    return {
        name = player.fullName or (player.firstName .. ' ' .. player.lastName),
        bankKey=bankKey, bank=bankDetails(bankKey), bankOptions=availableBanks(),
        bankSwitching=Config.AllowBankSwitching ~= false,
        bankSelected=bankKey ~= nil,
        charId = charId, accounts = accounts, primary = main and main.accountId or 0,
        balance = main and cash(main.balance) or 0, total = total, cash = player.cash or 0,
        transactions = tx, credit = score(charId), cards = cardRows(charId), loans = myLoans(charId),
        bills = getBills(charId), schedules = getSchedules(charId), products = Config.Loans,
        currency = Config.Currency,
        brand = (bankDefinition(bankKey) or {}).name or Config.Brand,
        cardItem = (bankDefinition(bankKey) or {}).cardItem or Config.CardItem
    }
end

local function hasPhysicalCard(source, number)
    for _, item in ipairs(Config.BankCardItems or {Config.CardItem}) do
        local found = CORE:FindAllItems(source,item) or {}
        for _, entry in ipairs(found) do
            if entry.metadata and entry.metadata.number == number then return true end
        end
    end
    return false
end

local function todayWithdrawn(charId, accountId)
    return tonumber(MySQL.scalar.await([[SELECT COALESCE(SUM(amount),0) FROM bank_transactions
      WHERE actorCharId=? AND fromAccountId=? AND type='withdraw'
      AND message='ATM withdrawal' AND createdAt>=UTC_DATE()]], {charId,accountId})) or 0
end

local function randomDigits(count)
    local out = {}
    for _ = 1, count do out[#out + 1] = tostring(math.random(0, 9)) end
    return table.concat(out)
end

local function createPhysicalCard(source,player,account,pin,key,style)
    local bank=bankDefinition(key)
    if not bank then return false,'Unknown bank' end
    if type(pin)~='string' or not pin:match('^%d%d%d%d$') then return false,'Choose a four-digit PIN' end
    style=CARD_STYLES[style] and style or 'classic'
    local number = (bank.cardPrefix or '5500') .. randomDigits(12)
    local salt = randomDigits(22)
    local item = bank.cardItems and bank.cardItems[style] or bank.cardItem
    local label = bank.name .. ' ' .. (style == 'black' and 'Cash+' or style == 'metal' and 'Metal' or 'Everyday')
    local id = MySQL.insert.await([[INSERT INTO whip_banking_cards
      (char_id,account_id,card_number,pin_salt,pin_hash,bank_key,card_style,item_name,card_name)
      VALUES (?,?,?,?,SHA2(CONCAT(?,?),256),?,?,?,?)]],
      {player.charId,account,number,salt,pin,salt,key,style,item,label})
    if not id then return false,'Could not create debit card' end
    local issueDate=os.date('!*t',epoch())
    local expiry=string.format('%02d/%02d',issueDate.month,(issueDate.year + 4) % 100)
    local where,why=CORE:AddItem(source,item,1,
      {number=number,last4=number:sub(-4),accountId=account,owner=player.fullName,
       bankKey=key,cardStyle=style,issuer=bank.name,expires=expiry,tier=label},
      {reason=bank.name .. ' issued debit card',noDrop=true})
    if not where then
        MySQL.update.await('DELETE FROM whip_banking_cards WHERE id=?',{id})
        return false,why or 'Make space in your pockets for your debit card'
    end
    return true,{id=id,number=number,last4=number:sub(-4),bankKey=key,cardStyle=style,itemName=item}
end

local function createTables()
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS whip_banking_cards (
      id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, char_id INT UNSIGNED NOT NULL,
      account_id INT UNSIGNED NOT NULL, card_number VARCHAR(19) NOT NULL UNIQUE,
      card_name VARCHAR(40) NOT NULL DEFAULT 'Everyday Debit', pin_salt VARCHAR(32) NOT NULL,
      pin_hash CHAR(64) NOT NULL, status ENUM('active','frozen','cancelled') NOT NULL DEFAULT 'active',
      attempts TINYINT UNSIGNED NOT NULL DEFAULT 0, locked_until DATETIME NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_card_char (char_id, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS whip_banking_profiles (
      char_id INT UNSIGNED NOT NULL PRIMARY KEY,
      bank_key VARCHAR(16) NOT NULL,
      opened_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      updated_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP ON UPDATE CURRENT_TIMESTAMP,
      INDEX idx_bank_key (bank_key)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    -- In-place, idempotent migrations of the existing 1.2.x cards; preserve PIN hashes.
    for _, field in ipairs({
      {'bank_key', "VARCHAR(16) NOT NULL DEFAULT 'maze'"},
      {'card_style', "VARCHAR(16) NOT NULL DEFAULT 'classic'"},
      {'item_name', "VARCHAR(80) NOT NULL DEFAULT 'maze_bank_card'"}
    }) do
      local found=MySQL.scalar.await([[SELECT COUNT(*) FROM INFORMATION_SCHEMA.COLUMNS
        WHERE TABLE_SCHEMA=DATABASE() AND TABLE_NAME='whip_banking_cards' AND COLUMN_NAME=?]],{field[1]})
      if tonumber(found)==0 then
        MySQL.query.await('ALTER TABLE whip_banking_cards ADD COLUMN '..field[1]..' '..field[2])
      end
    end
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS whip_banking_loans (
      id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, char_id INT UNSIGNED NOT NULL,
      account_id INT UNSIGNED NOT NULL, product VARCHAR(24) NOT NULL,
      principal INT UNSIGNED NOT NULL, remaining INT UNSIGNED NOT NULL,
      rate DECIMAL(5,2) NOT NULL, installment INT UNSIGNED NOT NULL,
      period_paid INT UNSIGNED NOT NULL DEFAULT 0, term_months SMALLINT UNSIGNED NOT NULL,
      status ENUM('disbursing','active','paid','late','review') NOT NULL DEFAULT 'disbursing',
      next_due DATETIME NOT NULL, last_attempt_at DATETIME NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_loan_char (char_id, status), INDEX idx_loan_due (status, next_due)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS whip_banking_loan_payments (
      id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, loan_id INT UNSIGNED NOT NULL,
      amount INT UNSIGNED NOT NULL, reference VARCHAR(64) NOT NULL UNIQUE,
      status ENUM('requested','paid','failed') NOT NULL DEFAULT 'requested',
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX idx_payment_status (status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS whip_banking_credit (
      id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, char_id INT UNSIGNED NOT NULL,
      points SMALLINT NOT NULL, reason VARCHAR(100) NOT NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP, INDEX idx_credit_char (char_id)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS whip_banking_interest (
      account_id INT UNSIGNED NOT NULL, period CHAR(7) NOT NULL,
      amount INT UNSIGNED NOT NULL, status ENUM('pending','paid') NOT NULL DEFAULT 'pending',
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      PRIMARY KEY (account_id, period)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS whip_banking_bills (
      id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, char_id INT UNSIGNED NOT NULL,
      creditor_account_id INT UNSIGNED NULL, title VARCHAR(90) NOT NULL,
      category VARCHAR(32) NOT NULL DEFAULT 'other', amount INT UNSIGNED NOT NULL,
      pay_from_id INT UNSIGNED NULL,
      status ENUM('unpaid','processing','paid','cancelled') NOT NULL DEFAULT 'unpaid',
      due_at DATETIME NOT NULL, paid_at DATETIME NULL,
      created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_bill_char (char_id, status)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    MySQL.query.await([[CREATE TABLE IF NOT EXISTS whip_banking_schedules (
      id INT UNSIGNED NOT NULL AUTO_INCREMENT PRIMARY KEY, char_id INT UNSIGNED NOT NULL,
      from_account_id INT UNSIGNED NOT NULL, to_account_id INT UNSIGNED NOT NULL,
      label VARCHAR(70) NOT NULL, amount INT UNSIGNED NOT NULL,
      frequency_days SMALLINT UNSIGNED NOT NULL, next_at DATETIME NOT NULL,
      retry_at DATETIME NULL,
      status ENUM('active','paused','cancelled') NOT NULL DEFAULT 'active',
      processing_ref VARCHAR(90) NULL, created_at TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
      INDEX idx_schedule_char (char_id), INDEX idx_schedule_due (status, next_at)
    ) ENGINE=InnoDB DEFAULT CHARSET=utf8mb4]])
    ready = true
end

local function transactionExists(accountId, reference)
    return (tonumber(MySQL.scalar.await([[SELECT COUNT(*) FROM bank_transactions
      WHERE (fromAccountId=? OR toAccountId=?) AND message=? LIMIT 1]],
      {accountId, accountId, reference})) or 0) > 0
end

local function completeLoanPayment(row, loan)
    local moved = MySQL.transaction.await({
        {query = [[UPDATE whip_banking_loans SET
            next_due=IF(period_paid+? >= installment,DATE_ADD(next_due,INTERVAL 30 DAY),next_due),
            period_paid=IF(period_paid+? >= installment,0,period_paid+?),
            remaining=GREATEST(0,remaining-?),
            status=IF(remaining=0,'paid','active') WHERE id=?]],
          values = {row.amount, row.amount, row.amount, row.amount, loan.id}},
        {query = 'UPDATE whip_banking_loan_payments SET status=? WHERE id=? AND status=?', values = {'paid', row.id, 'requested'}}
    })
    if moved then
        changeScore(loan.char_id, 3, 'Loan repayment')
        return true
    end
    return false
end

local function loanPayment(loan, toPay, actor)
    local paymentId = MySQL.insert.await('INSERT INTO whip_banking_loan_payments (loan_id,amount,reference) VALUES (?, ?, ?)',
      {loan.id, toPay, 'MB-' .. loan.id .. '-' .. epoch() .. '-' .. randomDigits(5)})
    if not paymentId then return false, 'Could not prepare repayment' end
    local row = MySQL.single.await('SELECT * FROM whip_banking_loan_payments WHERE id=?', {paymentId})
    local ok, why
    if actor then
        ok, why = CORE:BankWithdraw(loan.account_id, toPay, actor, {reason = row.reference})
    else
        ok, why = CORE:BankSystemWithdraw(loan.account_id, toPay, {reason = row.reference, actorCharId = loan.char_id})
    end
    if not ok then
        MySQL.update.await('UPDATE whip_banking_loan_payments SET status=? WHERE id=?', {'failed', paymentId})
        return false, why or 'Insufficient funds'
    end
    if not completeLoanPayment(row, loan) then
        return false, 'Payment received, but the repayment ledger needs reconciliation (do not retry)'
    end
    return true
end

local function recoverPayments()
    local rows = MySQL.query.await([[SELECT p.*, l.char_id, l.account_id, l.id AS real_loan_id
      FROM whip_banking_loan_payments p JOIN whip_banking_loans l ON l.id=p.loan_id
      WHERE p.status='requested']]) or {}
    for _, row in ipairs(rows) do
        if transactionExists(row.account_id, row.reference) then
            completeLoanPayment(row, {id = row.real_loan_id, char_id = row.char_id})
        else
            -- Safe-fail: do not charge again automatically after a crash with an ambiguous result.
            MySQL.update.await('UPDATE whip_banking_loan_payments SET status=? WHERE id=?', {'failed', row.id})
        end
    end
    local pending = MySQL.query.await("SELECT * FROM whip_banking_loans WHERE status='disbursing'") or {}
    for _, loan in ipairs(pending) do
        local ref = 'Maze loan #' .. loan.id
        local state = transactionExists(loan.account_id, ref) and 'active' or 'review'
        MySQL.update.await('UPDATE whip_banking_loans SET status=? WHERE id=?', {state, loan.id})
    end
    local bills = MySQL.query.await("SELECT * FROM whip_banking_bills WHERE status='processing'") or {}
    for _, bill in ipairs(bills) do
        local found = bill.pay_from_id and transactionExists(bill.pay_from_id, 'Maze bill #'..bill.id)
        MySQL.update.await("UPDATE whip_banking_bills SET status=?, paid_at=IF(?='paid',UTC_TIMESTAMP(),NULL) WHERE id=?",
            {found and 'paid' or 'unpaid', found and 'paid' or 'unpaid', bill.id})
    end
end

local function serveSchedule(row)
    local entitled = CORE:CanUseBankAccount(row.from_account_id, {charId=row.char_id}, 'withdraw')
    if not entitled then
        MySQL.update.await("UPDATE whip_banking_schedules SET status='paused' WHERE id=?", {row.id})
        return false
    end
    local reference = row.processing_ref
    if not reference then
        reference = ('Scheduled #%s at %s'):format(row.id, os.date('!%Y%m%d%H%M%S', epoch()))
        MySQL.update.await("UPDATE whip_banking_schedules SET processing_ref=? WHERE id=? AND processing_ref IS NULL", {reference, row.id})
    end
    local already = transactionExists(row.from_account_id, reference)
    if not already then
        local ok = CORE:BankSystemTransfer(row.from_account_id, row.to_account_id, row.amount,
          {reason=reference, actorCharId=row.char_id})
        if not ok then
            MySQL.update.await("UPDATE whip_banking_schedules SET retry_at=DATE_ADD(UTC_TIMESTAMP(),INTERVAL 12 HOUR) WHERE id=?",{row.id})
            return false
        end
    end
    MySQL.update.await([[UPDATE whip_banking_schedules SET processing_ref=NULL,retry_at=NULL,
      next_at=DATE_ADD(next_at,INTERVAL frequency_days DAY) WHERE id=?]], {row.id})
    return true
end

local function serviceDue()
    local due = MySQL.query.await([[SELECT * FROM whip_banking_loans
      WHERE status IN ('active','late') AND next_due <= UTC_TIMESTAMP()
      AND (last_attempt_at IS NULL OR last_attempt_at < DATE_SUB(UTC_TIMESTAMP(),INTERVAL 12 HOUR)) LIMIT 60]]) or {}
    for _, loan in ipairs(due) do
        local lock = 'loan:' .. loan.id
        if not processing[lock] then
            processing[lock] = true
            MySQL.update.await('UPDATE whip_banking_loans SET last_attempt_at=UTC_TIMESTAMP() WHERE id=?',{loan.id})
            local toPay = math.min(loan.remaining, math.max(1, loan.installment - loan.period_paid))
            local ok = loanPayment(loan, toPay, nil)
            if not ok and loan.status ~= 'late' then
                MySQL.update.await("UPDATE whip_banking_loans SET status='late' WHERE id=?", {loan.id})
                changeScore(loan.char_id, -12, 'Missed loan repayment')
            end
            processing[lock] = nil
        end
    end
    local schedules = MySQL.query.await([[SELECT * FROM whip_banking_schedules
      WHERE status='active' AND next_at <= UTC_TIMESTAMP()
      AND (retry_at IS NULL OR retry_at <= UTC_TIMESTAMP()) LIMIT 60]]) or {}
    for _, row in ipairs(schedules) do
        local lock = 'schedule:' .. row.id
        if not processing[lock] then
            processing[lock] = true
            serveSchedule(row)
            processing[lock] = nil
        end
    end
end

local function serviceInterest()
    if (tonumber(Config.SavingsApr) or 0) <= 0 and not (Config.Banks and ((tonumber(Config.Banks.fleeca.savingsApr) or 0) > 0 or (tonumber(Config.Banks.maze.savingsApr) or 0) > 0 or (tonumber(Config.Banks.pacific.savingsApr) or 0) > 0)) then return end
    local period = MySQL.scalar.await("SELECT DATE_FORMAT(DATE_SUB(UTC_DATE(),INTERVAL 1 MONTH),'%Y-%m')")
    if type(period) ~= 'string' then return end
    -- Only rows not yet paid for the previous completed month; safe after restarts and outages.
    local accounts = MySQL.query.await([[SELECT a.accountId, a.balance, COALESCE(p.bank_key,'maze') AS bank_key FROM bank_accounts a
      LEFT JOIN whip_banking_profiles p ON p.char_id=a.ownerCharId
      LEFT JOIN whip_banking_interest i ON i.account_id=a.accountId AND i.period=? AND i.status='paid'
      WHERE a.type='savings' AND a.closedAt IS NULL AND a.balance>0 AND i.account_id IS NULL LIMIT 100]], {period}) or {}
    for _, a in ipairs(accounts) do
        local rate = (bankDefinition(a.bank_key) or {}).savingsApr or Config.SavingsApr
        local amountDue = math.floor((tonumber(a.balance) or 0) * rate / 1200)
        MySQL.insert.await([[INSERT IGNORE INTO whip_banking_interest (account_id,period,amount)
          VALUES (?,?,?)]], {a.accountId,period,amountDue})
        local ref = 'Savings interest '..period
        local alreadyCredited=transactionExists(a.accountId,ref) or transactionExists(a.accountId,'Maze savings interest '..period)
        if amountDue > 0 and not alreadyCredited then
            local ok = CORE:BankSystemDeposit(a.accountId,amountDue,{reason=ref})
            if not ok then goto continue end
        end
        MySQL.update.await([[UPDATE whip_banking_interest SET status='paid'
          WHERE account_id=? AND period=?]], {a.accountId,period})
        ::continue::
    end
end

CreateThread(function()
    math.randomseed(epoch() + GetGameTimer())
    local ok, err = pcall(createTables)
    if not ok then print('[whip_banking] SQL setup failed: ' .. tostring(err)); return end
    recoverPayments()
    print('[whip_banking] Database ready; using WHIP native banking ledger')
    local interestTick = 0
    while true do
        Wait(60000)
        local good, why = pcall(serviceDue)
        if not good then print('[whip_banking] Payment scheduler error: ' .. tostring(why)) end
        interestTick = interestTick + 1
        if interestTick >= 60 then
            interestTick = 0
            local paid, reason = pcall(serviceInterest)
            if not paid then print('[whip_banking] Savings interest error: ' .. tostring(reason)) end
        end
    end
end)

-- WHIP keeps networked teller peds stable as entity ownership moves between clients.
Whip.register(function()
    local allCardItems={Config.CardItem}
    Whip.core:RegisterItem(Config.CardItem, {
        name='Maze Bank legacy debit card',desc='An existing Maze Bank contactless card.',
        weight=0.02,type='misc',stack=false,maxStack=1,usable=true
    })
    Whip.core:RegisterUseHandler(Config.CardItem,function(source,_,stack)
        TriggerClientEvent('whip_banking:client:cardUsed',source,stack and stack.metadata or {})
        return false
    end)
    for _, bankKey in ipairs({'fleeca','maze','pacific'}) do
        local def=Config.Banks[bankKey]
        for _,style in ipairs({'classic','black','metal'}) do
            local item=def.cardItems[style]
            allCardItems[#allCardItems+1]=item
            Whip.core:RegisterItem(item,{
                name=def.name..' '..(style=='black' and 'Cash+' or style=='metal' and 'Metal' or 'Everyday')..' debit card',
                desc='Personalised '..def.name..' contactless bank card.',
                weight=0.02,type='misc',stack=false,maxStack=1,usable=true
            })
            Whip.core:RegisterUseHandler(item,function(source,_,stack)
                TriggerClientEvent('whip_banking:client:cardUsed',source,stack and stack.metadata or {})
                return false
            end)
        end
    end
    if Config.CardAccessorySlot then
        local ok,why=Whip.core:RegisterAccessorySlot({
            slot=Config.CardAccessorySlot,accepts=allCardItems,keys=false,label='Bank Card',
            iconSvg=[[<svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="1.6"><rect x="2.5" y="5.5" width="19" height="13" rx="2"/><path d="M2.5 10h19"/><rect x="5" y="13" width="5" height="2" rx=".6"/></svg>]],
        })
        if not ok then print('[whip_banking] Card accessory slot: '..tostring(why)) end
    end
    for i, entry in ipairs(Config.Branches) do
        if not spawned[i] then spawnTeller(i) end
    end
    bankBlipsReady = true
    refreshBankBlips()

    Whip.core:SecureCallback('whip_banking:teller', {rateLimit=600}, function(source, player)
        local branch = nearbyBranch(source)
        if not branch then return false, 'Speak to a bank teller at the counter' end
        tellerSessions[source] = {charId=player.charId, untilAt=epoch()+300}
        return true, Config.Branches[branch].name
    end)

    Whip.core:SecureCallback('whip_banking:selectBank', {
      rateLimit=2500,params={{'bank','enum',{'fleeca','maze','pacific'}},
        {'pin','string',4},{'style','enum',{'classic','black','metal'}}}
    },function(source,player,bank,pin,style)
      return reserved(source,'selectBank',function()
        if not ready then return false,'Bank database is starting' end
        if not isTeller(source) then return false,'Speak to a teller before choosing a bank' end
        local old=profileOf(player.charId)
        if old and old.bankKey==bank then return false,'You already bank here. Issue a new card from the Cards tab.' end
        if old and Config.AllowBankSwitching==false then return false,'Bank switching is disabled' end
        local account=CORE:GetDefaultBankAccount(source)
        if not account then return false,'Your WHIP personal bank account is unavailable' end
        local oldCards={}
        if old then oldCards=MySQL.query.await([[SELECT card_number AS number,
            COALESCE(item_name,'maze_bank_card') AS itemName FROM whip_banking_cards
            WHERE char_id=? AND status!='cancelled']],{player.charId}) or {} end
        local created,card=createPhysicalCard(source,player,account.accountId,pin,bank,style)
        if not created then return false,card end
        local updated=MySQL.update.await([[INSERT INTO whip_banking_profiles(char_id,bank_key)
            VALUES(?,?) ON DUPLICATE KEY UPDATE bank_key=VALUES(bank_key)]],{player.charId,bank})
        if updated==nil then
            CORE:RemoveItem(source,card.itemName,1,{number=card.number},{reason='Bank registration rollback'})
            MySQL.update.await('DELETE FROM whip_banking_cards WHERE id=?',{card.id})
            return false,'Could not save your bank choice'
        end
        if #oldCards>0 then
            MySQL.update.await([[UPDATE whip_banking_cards SET status='cancelled'
              WHERE char_id=? AND id!=? AND status!='cancelled']],{player.charId,card.id})
            for _,oldCard in ipairs(oldCards) do
                CORE:RemoveItem(source,oldCard.itemName,1,{number=oldCard.number},
                  {reason='Replaced by new bank card'})
            end
        end
        sessions[source]=nil
        return true,{bank=bankDetails(bank),card=card}
      end)
    end)

    -- Lightweight one-time bank lookup for the local standby DUI. The response
    -- is authoritative for this character, not a user-provided brand name.
    Whip.core:SecureCallback('whip_banking:bankIdentity', {rateLimit=1000}, function(source, player)
        if not ready then return false, 'Bank database is starting' end
        local p=profileOf(player.charId)
        return true,{bankKey=p and p.bankKey or nil}
    end)

    -- Read-only physical debit card preview. Do not send PINs, salts, hashes,
    -- CVV or an unmasked number to the NUI. The item must still be possessed.
    Whip.core:SecureCallback('whip_banking:cardPreview', {
        rateLimit=350,params={{'number','string',19}}
    }, function(source, player, number)
        if not ready then return false, 'Bank database is starting' end
        if type(number)~='string' or not number:match('^%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d%d$') then
            return false,'Invalid bank card'
        end
        if not hasPhysicalCard(source,number) then
            return false,'This card is not in your inventory'
        end
        local card=MySQL.single.await([[SELECT id, RIGHT(card_number,4) AS last4,
            COALESCE(bank_key,'maze') AS bankKey,
            COALESCE(card_style,'classic') AS cardStyle,
            status,card_name AS label,
            DATE_FORMAT(DATE_ADD(created_at, INTERVAL 4 YEAR),'%m/%y') AS expires
            FROM whip_banking_cards WHERE char_id=? AND card_number=? LIMIT 1]],
            {player.charId,number})
        if not card or not bankDefinition(card.bankKey) then
            return false,'This card is no longer linked to your account'
        end
        return true,{id=card.id,last4=card.last4,bankKey=card.bankKey,
            cardStyle=card.cardStyle,status=card.status,label=card.label,
            expires=card.expires,holder=player.fullName or 'CARDHOLDER',
            bankName=bankDefinition(card.bankKey).name}
    end)

    Whip.core:SecureCallback('whip_banking:overview', {rateLimit=450}, function(source, player)
        if not ready then return false, 'Bank database is starting' end
        return summary(source, player)
    end)

    Whip.core:SecureCallback('whip_banking:accountCreate', {
        rateLimit=1500, params={{'kind','enum',{'savings','shared'}},{'label','string',40}}
    }, function(source, _, kind, label)
        return reserved(source, 'create', function()
            local account, why = CORE:CreateBankAccount(source, label, {type=kind})
            if not account then return false, why end
            return true, account
        end)
    end)

    Whip.core:SecureCallback('whip_banking:transfer', {
        rateLimit=900, params={{'from','id'},{'number','string',32},{'value','amount',999999999}}
    }, function(source, _, from, number, value)
        return reserved(source, 'transfer', function()
            local fromAcc, denied = myAccount(source, from, 'withdraw')
            if not fromAcc then return false, denied end
            local target = CORE:GetBankAccount({number=textSafe(number,32)})
            if not target then return false, 'Recipient account not found' end
            local ok, why = CORE:BankTransfer(from, target.accountId, value, source, {reason=((bankDefinition((profileOf(char(source)) or {}).bankKey) or {}).name or 'Bank') .. ' transfer'})
            return ok, why
        end)
    end)

    Whip.core:SecureCallback('whip_banking:issueCard', {
        rateLimit=1500, params={{'account','id'},{'pin','string',4},{'style','enum',{'classic','black','metal'}}}
    }, function(source, player, account, pin, style)
        return reserved(source, 'issue', function()
            if not isTeller(source) then return false, 'Speak to a bank teller to issue a card' end
            local p=profileOf(player.charId)
            if not p then return false,'Choose your bank first' end
            local acc, denied = myAccount(source, account, 'owner')
            if not acc then return false, denied end
            local have = MySQL.scalar.await("SELECT COUNT(*) FROM whip_banking_cards WHERE char_id=? AND status != 'cancelled'", {player.charId}) or 0
            if tonumber(have)>=Config.MaxCards then return false, 'Maximum active cards reached' end
            return createPhysicalCard(source,player,account,pin,p.bankKey,style)
        end)
    end)

    Whip.core:SecureCallback('whip_banking:cardStatus', {
        rateLimit=700, params={{'id','id'},{'status','enum',{'active','frozen','cancelled'}}}
    }, function(source, player, id, status)
        local row = MySQL.single.await('SELECT * FROM whip_banking_cards WHERE id=? AND char_id=?', {id,player.charId})
        if not row or row.status == 'cancelled' then return false, 'Card not found' end
        MySQL.update.await('UPDATE whip_banking_cards SET status=? WHERE id=? AND char_id=?', {status,id,player.charId})
        return true
    end)

    Whip.core:SecureCallback('whip_banking:pinChange', {
        rateLimit=900, params={{'id','id'},{'old','string',4},{'new','string',4}}
    }, function(source, player, id, old, new)
        return reserved(source, 'pin', function()
            if not new:match('^%d%d%d%d$') or not old:match('^%d%d%d%d$') then return false, 'PIN must be four digits' end
            local row = MySQL.single.await([[SELECT *, (pin_hash=SHA2(CONCAT(?,pin_salt),256)) AS matches
              FROM whip_banking_cards WHERE id=? AND char_id=? AND status!='cancelled']], {old,id,player.charId})
            if not row or not (row.matches == true or tonumber(row.matches) == 1) then return false, 'Current PIN incorrect' end
            local salt = randomDigits(22)
            MySQL.update.await([[UPDATE whip_banking_cards SET pin_salt=?, pin_hash=SHA2(CONCAT(?,?),256), attempts=0,locked_until=NULL WHERE id=?]],
              {salt,new,salt,id})
            return true
        end)
    end)

    Whip.core:SecureCallback('whip_banking:atmAuth', {
        rateLimit=1200, params={{'number','string',19},{'pin','string',4}}
    }, function(source, player, number, pin)
        if not pin:match('^%d%d%d%d$') then return false, 'Four-digit PIN required' end
        local row = MySQL.single.await([[SELECT *, (pin_hash=SHA2(CONCAT(?,pin_salt),256)) AS matches,
          UNIX_TIMESTAMP(locked_until) AS lockEpoch,
          UNIX_TIMESTAMP(DATE_ADD(created_at,INTERVAL 4 YEAR)) AS expiresEpoch FROM whip_banking_cards
          WHERE card_number=? AND char_id=?]], {pin,number,player.charId})
        if not row or row.status ~= 'active' then return false, 'Card blocked or not found' end
        local expiresEpoch=tonumber(row.expiresEpoch)
        if expiresEpoch and expiresEpoch <= epoch() then
            return false,'This card has expired. Request a replacement at the bank teller'
        end
        if row.lockEpoch and tonumber(row.lockEpoch) > epoch() then return false, 'PIN locked for 15 minutes' end
        if not hasPhysicalCard(source, number) then return false, 'Your bank card is not in your pockets' end
        if not (row.matches == true or tonumber(row.matches) == 1) then
            MySQL.update.await([[UPDATE whip_banking_cards SET attempts=attempts+1,
              locked_until=IF(attempts>=2, DATE_ADD(UTC_TIMESTAMP(), INTERVAL 15 MINUTE),NULL)
              WHERE id=?]], {row.id})
            return false, (row.attempts >= 2) and 'Card locked for 15 minutes' or 'Incorrect PIN'
        end
        local p=profileOf(player.charId)
        local key=row.bank_key or 'maze'
        if not p or p.bankKey~=key then return false,'This card belongs to your previous bank' end
        local acc, why = myAccount(source, row.account_id, 'view')
        if not acc then return false, why end
        MySQL.update.await('UPDATE whip_banking_cards SET attempts=0,locked_until=NULL WHERE id=?', {row.id})
        sessions[source] = {charId=player.charId, cardId=row.id, cardNumber=number,
          accountId=row.account_id, untilAt=epoch()+120,bankKey=key}
        return true, {accountId=row.account_id, balance=acc.balance, label=acc.label,
          last4=number:sub(-4), bankKey=key, brand=(bankDefinition(key) or {}).name,
          limit=math.max(0,((bankDefinition(key) or {}).atmDailyLimit or Config.AtmDailyLimit)-todayWithdrawn(player.charId,row.account_id))}
    end)

    Whip.core:SecureCallback('whip_banking:atmPreflight', {
        rateLimit=300, params={{'account','id'},{'kind','enum',{'withdraw'}},{'value','amount',999999999}}
    }, function(source, player, account, kind, value)
        local current = sessions[source]
        if not current or current.charId ~= player.charId or current.untilAt < epoch()
            or current.accountId ~= account then return false, 'Insert your bank card and enter its PIN first' end
        if not hasPhysicalCard(source, current.cardNumber) then return false, 'Bank card no longer in your pockets' end
        local cap=(bankDefinition(current.bankKey) or {}).atmDailyLimit or Config.AtmDailyLimit
        if todayWithdrawn(player.charId,account)+value > cap then
            return false, 'Your ATM daily withdrawal limit has been reached'
        end
        local _, why = myAccount(source,account,'withdraw')
        if why then return false, why end
        return true
    end)

    Whip.core:SecureCallback('whip_banking:atmStatus', {rateLimit=250}, function(source, player)
        local current=sessions[source]
        if not current or current.charId~=player.charId then return false, 'ATM session expired' end
        local cap=(bankDefinition(current.bankKey) or {}).atmDailyLimit or Config.AtmDailyLimit
        return true, math.max(0,cap-todayWithdrawn(player.charId,current.accountId))
    end)

    Whip.core:SecureCallback('whip_banking:atmEnd', {rateLimit=300}, function(source)
        sessions[source]=nil
        return true
    end)

    Whip.core:SecureCallback('whip_banking:loanApply', {
        rateLimit=2000, params={{'account','id'},{'product','enum',{'personal','vehicle','business'}},{'value','amount',100000}}
    }, function(source, player, account, product, value)
        return reserved(source, 'loan', function()
            local acc, why = myAccount(source,account,'owner')
            if not acc or not acc.isDefault then return false, why or 'Loans must use your personal account' end
            local offer
            for _, p in ipairs(Config.Loans) do if p.key == product then offer=p end end
            if not offer or value > offer.max then return false, 'Amount exceeds this loan product' end
            if score(player.charId) < offer.minScore then return false, 'Credit score below the required level' end
            local active = MySQL.scalar.await([[SELECT COUNT(*) FROM whip_banking_loans
              WHERE char_id=? AND status IN ('active','late','disbursing','review')]], {player.charId}) or 0
            if active >= Config.MaxActiveLoans then return false, 'You have reached your loan limit' end
            local installment = math.ceil((value * (1+offer.rate/100)) / offer.months)
            local debt = installment * offer.months
            local loanId = MySQL.insert.await([[INSERT INTO whip_banking_loans
              (char_id,account_id,product,principal,remaining,rate,installment,term_months,next_due)
              VALUES (?,?,?,?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 30 DAY))]],
              {player.charId,account,product,value,debt,offer.rate,installment,offer.months})
            if not loanId then return false, 'Could not prepare loan' end
            local moved, failed = CORE:BankSystemDeposit(account,value,{reason='Maze loan #'..loanId,actorCharId=player.charId})
            if not moved then
                MySQL.update.await("UPDATE whip_banking_loans SET status='review' WHERE id=?", {loanId})
                return false, failed or 'Loan funding failed; contact staff'
            end
            MySQL.update.await("UPDATE whip_banking_loans SET status='active' WHERE id=?", {loanId})
            return true, {id=loanId, installment=installment, total=debt}
        end)
    end)

    Whip.core:SecureCallback('whip_banking:loanPay', {
        rateLimit=1200, params={{'id','id'},{'value','amount',10000000}}
    }, function(source, player, id, value)
        local lock = 'loan:' .. id
        if processing[lock] then return false, 'Repayment already in progress' end
        processing[lock] = true
        local loan = MySQL.single.await([[SELECT * FROM whip_banking_loans
          WHERE id=? AND char_id=? AND status IN ('active','late')]], {id,player.charId})
        local ok, why = false, 'Loan not found'
        if loan then ok, why = loanPayment(loan, math.min(value,loan.remaining), source) end
        processing[lock] = nil
        return ok, why
    end)

    Whip.core:SecureCallback('whip_banking:billPay', {
        rateLimit=1200, params={{'id','id'},{'account','id'}}
    }, function(source, player, id, account)
        return reserved(source, 'bill:'..id, function()
            local acc, why = myAccount(source,account,'withdraw')
            if not acc then return false, why end
            local bill = MySQL.single.await('SELECT * FROM whip_banking_bills WHERE id=? AND char_id=?', {id,player.charId})
            if not bill or bill.status ~= 'unpaid' then return false, 'Bill already settled or unavailable' end
            local ref = 'Maze bill #'..id
            local claimed = MySQL.update.await("UPDATE whip_banking_bills SET status='processing',pay_from_id=? WHERE id=? AND status='unpaid'", {account,id})
            if claimed ~= 1 then return false, 'Bill payment is already in progress' end
            local success, err
            if bill.creditor_account_id then
                success, err = CORE:BankTransfer(account,bill.creditor_account_id,bill.amount,source,{reason=ref})
            else
                success, err = CORE:BankWithdraw(account,bill.amount,source,{reason=ref})
            end
            if not success then
                MySQL.update.await("UPDATE whip_banking_bills SET status='unpaid' WHERE id=?", {id})
                return false, err
            end
            MySQL.update.await("UPDATE whip_banking_bills SET status='paid',paid_at=UTC_TIMESTAMP() WHERE id=?", {id})
            return true
        end)
    end)

    Whip.core:SecureCallback('whip_banking:scheduleCreate', {
        rateLimit=1200, params={{'from','id'},{'number','string',32},{'value','amount',999999999},
          {'days','enum',{7,14,30}},{'label','string',70}}
    }, function(source, player, from, number, value, days, label)
        local acc, why = myAccount(source,from,'withdraw')
        if not acc then return false, why end
        local dest = CORE:GetBankAccount({number=number})
        if not dest or dest.accountId == from then return false, 'Choose a different recipient account' end
        local n = MySQL.scalar.await("SELECT COUNT(*) FROM whip_banking_schedules WHERE char_id=? AND status='active'", {player.charId}) or 0
        if n >= 15 then return false, 'Maximum 15 scheduled payments' end
        local id = MySQL.insert.await([[INSERT INTO whip_banking_schedules
          (char_id,from_account_id,to_account_id,label,amount,frequency_days,next_at)
          VALUES (?,?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL 1 DAY))]],
          {player.charId,from,dest.accountId,label,value,days})
        return id ~= nil, id and 'Payment scheduled' or 'Could not schedule payment'
    end)

    Whip.core:SecureCallback('whip_banking:scheduleCancel', {
        rateLimit=700, params={{'id','id'}}
    }, function(_, player, id)
        local n = MySQL.update.await([[UPDATE whip_banking_schedules SET status='cancelled'
          WHERE id=? AND char_id=? AND status='active']], {id,player.charId})
        return n > 0, n > 0 and nil or 'Scheduled payment not found'
    end)
end)

AddEventHandler('playerDropped', function()
    sessions[source] = nil
    tellerSessions[source] = nil
end)

-- Trusted server resources can issue roleplay invoices. There is intentionally NO client bill-creation event.
exports('CreateBill', function(targetSource, title, sum, creditorAccountId, dueDays, category)
    local owner = char(targetSource)
    sum = amount(sum,999999999)
    if not ready or not owner or not sum then return false, 'Invalid payer or amount' end
    title = textSafe(title,90)
    if title == '' then return false, 'Bill title required' end
    local recipient = creditorAccountId and bankAccount(creditorAccountId) or nil
    if creditorAccountId and not recipient then return false, 'Creditor bank account missing' end
    dueDays = math.max(1,math.min(365,math.floor(tonumber(dueDays) or 7)))
    local id = MySQL.insert.await([[INSERT INTO whip_banking_bills
      (char_id,creditor_account_id,title,category,amount,due_at)
      VALUES (?,?,?,?,?,DATE_ADD(UTC_TIMESTAMP(),INTERVAL ? DAY))]],
      {owner,creditorAccountId,title,textSafe(category or 'other',32),sum,dueDays})
    if id then push(targetSource,'New bank bill: '..title,'info') end
    return id or false
end)

exports('GetCreditScore', function(targetSource)
    local owner = char(targetSource)
    return owner and score(owner) or false
end)

-- Called only by trusted server resources (e.g. whip_phone) for the current character.
exports('GetBankProfile',function(source)
    if not ready then return nil end
    local charId=CORE:GetCharId(source)
    if not charId then return nil end
    local p=profileOf(charId)
    return p and bankDetails(p.bankKey) or {key='unselected',name='Choose your bank'}
end)
