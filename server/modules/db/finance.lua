-- ============================================================
-- server/modules/db/finance.lua  (DEOBFUSCATED)
-- qs-crime-creator  —  QS Framework
-- OrganizationFinanceDB — finance overview, transactions,
-- money updates, and analytics queries.
-- ============================================================

OrganizationFinanceDB = {}

-- ──────────────────────────────────────────────────────────
-- OrganizationFinanceDB:getFinanceOverview(orgId)
--   Returns { clean_money, dirty_money, daily/weekly/monthly
--   revenue, net_profit, profit_margin, cash_flow }.
--   Creates the finance row if it doesn't exist.
-- ──────────────────────────────────────────────────────────
function OrganizationFinanceDB:getFinanceOverview(orgId)
    if not orgId then Error("OrganizationFinanceDB:getFinanceOverview", "orgId is nil") return nil end

    if not RecordManager:get("organizations", orgId) then return nil end

    local cached = db:getCache("finance_overview", orgId)
    if cached then return cached end

    -- Fetch (or create) the balance row
    local finRow = MySQL.prepare.await([[
        SELECT * FROM qs_crime_organization_finance
        WHERE organization_id = ? LIMIT 1
    ]], { orgId })

    if not finRow then
        local newId = MySQL.insert.await([[
            INSERT INTO qs_crime_organization_finance (organization_id, clean_money, dirty_money)
            VALUES (?, 0, 0)
        ]], { orgId })

        if newId then
            finRow = { id = newId, organization_id = orgId,
                       clean_money = 0, dirty_money = 0 }
        else
            return nil
        end
    end

    local cleanMoney = finRow.clean_money or 0
    local dirtyMoney = finRow.dirty_money or 0

    -- Aggregate revenue / expense metrics
    local metrics = MySQL.single.await([[
        WITH financial_metrics AS (
            SELECT
                COALESCE(SUM(CASE
                    WHEN type IN ('deposit','sale') AND status='completed' AND DATE(created_at)=CURDATE()
                    THEN amount ELSE 0 END),0) as daily_revenue,
                COALESCE(SUM(CASE
                    WHEN type IN ('deposit','sale') AND status='completed' AND created_at>=DATE_SUB(NOW(),INTERVAL 7 DAY)
                    THEN amount ELSE 0 END),0) as weekly_revenue,
                COALESCE(SUM(CASE
                    WHEN type IN ('deposit','sale') AND status='completed' AND created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)
                    THEN amount ELSE 0 END),0) as monthly_revenue,
                COALESCE(SUM(CASE
                    WHEN type IN ('withdraw','expense') AND status='completed' AND created_at>=DATE_SUB(NOW(),INTERVAL 30 DAY)
                    THEN ABS(amount) ELSE 0 END),0) as total_expenses
            FROM qs_crime_organization_transactions
            WHERE organization_id = ?
        )
        SELECT
            daily_revenue, weekly_revenue, monthly_revenue, total_expenses,
            (monthly_revenue - total_expenses) as net_profit,
            CASE WHEN monthly_revenue > 0
                THEN ((monthly_revenue - total_expenses) / monthly_revenue) * 100
                ELSE 0 END as profit_margin,
            (monthly_revenue - total_expenses) as cash_flow
        FROM financial_metrics
    ]], { orgId }) or {}

    local overview = {
        clean_money       = cleanMoney,
        dirty_money       = dirtyMoney,
        available_balance = cleanMoney,
        daily_revenue     = metrics.daily_revenue   or 0,
        weekly_revenue    = metrics.weekly_revenue  or 0,
        monthly_revenue   = metrics.monthly_revenue or 0,
        net_profit        = metrics.net_profit      or 0,
        profit_margin     = metrics.profit_margin   or 0,
        cash_flow         = metrics.cash_flow       or 0,
        last_updated      = os.date("%Y-%m-%d %H:%M:%S"),
    }

    db:saveCache("finance_overview", overview, orgId)
    return overview
end

-- ──────────────────────────────────────────────────────────
-- OrganizationFinanceDB:getTransactions(orgId, limit, offset)
-- ──────────────────────────────────────────────────────────
function OrganizationFinanceDB:getTransactions(orgId, limit, offset)
    if not orgId then Error("OrganizationFinanceDB:getTransactions", "orgId is nil") return {} end
    limit  = limit  or 50
    offset = offset or 0

    local cacheKey = orgId .. "_" .. limit .. "_" .. offset
    local cached   = db:getCache("transactions", cacheKey)
    if cached then return cached end

    local rows = MySQL.query.await([[
        SELECT * FROM qs_crime_organization_transactions
        WHERE organization_id = ?
        ORDER BY created_at DESC
        LIMIT ? OFFSET ?
    ]], { orgId, limit, offset }) or {}

    local result = {}
    for _, row in pairs(rows) do
        local meta = (row.metadata and json.decode(row.metadata)) or {}
        result[#result + 1] = {
            id          = row.id,
            type        = row.type,
            amount      = row.amount or 0,
            description = row.description or "",
            date        = row.created_at,
            created_at  = row.created_at,
            identifier  = row.identifier,
            name        = row.name,
            reference   = row.reference,
            status      = row.status or "completed",
            metadata    = meta,
        }
    end

    db:saveCache("transactions", result, cacheKey)
    return result
end

-- ──────────────────────────────────────────────────────────
-- OrganizationFinanceDB:createTransaction(orgId, data)
--   data: { type, amount, money_type, description, reference,
--           identifier, name, status, metadata }
-- ──────────────────────────────────────────────────────────
function OrganizationFinanceDB:createTransaction(orgId, data)
    if not orgId then Error("OrganizationFinanceDB:createTransaction", "orgId is nil") return false, nil end
    if not data then Error("OrganizationFinanceDB:createTransaction", "data is nil") return false, nil end

    local metaJson = data.metadata and json.encode(data.metadata) or nil

    local newId = MySQL.insert.await([[
        INSERT INTO qs_crime_organization_transactions (
            organization_id, type, amount, money_type, description, reference,
            identifier, name, status, metadata
        ) VALUES (?, ?, ?, ?, ?, ?, ?, ?, ?, ?)
    ]], {
        orgId,
        data.type,
        data.amount,
        data.money_type   or "money",
        data.description  or "",
        data.reference,
        data.identifier,
        data.name,
        data.status       or "completed",
        metaJson,
    })

    if newId then
        db:clearCache("transactions",      orgId)
        db:clearCache("finance_overview",  orgId)
        Debug("OrganizationFinanceDB:createTransaction",
            "Created transaction:", newId, "for organization:", orgId)
        return true, newId
    end

    Error("OrganizationFinanceDB:createTransaction",
        "Failed to create transaction for organization:", orgId)
    return false, nil
end

-- ──────────────────────────────────────────────────────────
-- OrganizationFinanceDB:updateMoney(orgId, amount, type, moneyType)
--   type:      "deposit" | "withdraw"
--   moneyType: "clean"   | "dirty"
-- ──────────────────────────────────────────────────────────
function OrganizationFinanceDB:updateMoney(orgId, amount, txType, moneyType)
    if not orgId then Error("OrganizationFinanceDB:updateMoney", "orgId is nil") return false end
    if not amount then Error("OrganizationFinanceDB:updateMoney", "amount is nil") return false end
    if not txType then Error("OrganizationFinanceDB:updateMoney", "txType is nil") return false end
    if not moneyType then Error("OrganizationFinanceDB:updateMoney", "moneyType is nil") return false end

    -- Fetch / create finance row
    local finRow = MySQL.prepare.await([[
        SELECT * FROM qs_crime_organization_finance
        WHERE organization_id = ? LIMIT 1
    ]], { orgId })

    if not finRow then
        local newId = MySQL.insert.await([[
            INSERT INTO qs_crime_organization_finance (organization_id, clean_money, dirty_money)
            VALUES (?, 0, 0)
        ]], { orgId })

        if newId then
            finRow = { id = newId, organization_id = orgId,
                       clean_money = 0, dirty_money = 0 }
        else
            Error("OrganizationFinanceDB:updateMoney",
                "Failed to create finance record for organization:", orgId)
            return false
        end
    end

    local delta   = (txType == "withdraw") and -amount or amount
    local colName = (moneyType == "dirty") and "dirty_money" or "clean_money"
    local current = finRow[colName] or 0
    local newVal  = current + delta

    local ok = MySQL.update.await(
        "UPDATE qs_crime_organization_finance SET " .. colName .. " = ? WHERE organization_id = ?",
        { newVal, orgId }
    )

    if not ok then
        Error("OrganizationFinanceDB:updateMoney",
            "Failed to update " .. colName .. " for organization:", orgId)
        return false
    end

    db:clearCache("finance_overview", orgId)
    db:clearCache("finance",          orgId)
    RecordManager:clearCache("organizations")

    Debug("OrganizationFinanceDB:updateMoney",
        "Updated " .. colName .. " for organization:", orgId,
        "amount:", delta, "type:", txType, "moneyType:", moneyType, "new amount:", newVal)

    return true
end

-- ──────────────────────────────────────────────────────────
-- OrganizationFinanceDB:updateBalance(orgId, amount, type)
--   Convenience wrapper — always targets clean_money.
-- ──────────────────────────────────────────────────────────
function OrganizationFinanceDB:updateBalance(orgId, amount, txType)
    return self:updateMoney(orgId, amount, txType, "clean")
end

-- ──────────────────────────────────────────────────────────
-- OrganizationFinanceDB:getFinanceAnalytics(orgId)
--   Returns { revenueTrends, expenseBreakdown, topSellingItems }.
-- ──────────────────────────────────────────────────────────
function OrganizationFinanceDB:getFinanceAnalytics(orgId)
    if not orgId then Error("OrganizationFinanceDB:getFinanceAnalytics", "orgId is nil") return {} end

    local cached = db:getCache("finance_analytics", orgId)
    if cached then return cached end

    local revenueTrends = MySQL.query.await([[
        SELECT DATE(created_at) as date, SUM(amount) as revenue
        FROM qs_crime_organization_transactions
        WHERE organization_id = ? AND type IN ('deposit','sale') AND status='completed'
        AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        GROUP BY DATE(created_at) ORDER BY date ASC
    ]], { orgId }) or {}

    local expenseBreakdown = MySQL.query.await([[
        SELECT type, SUM(ABS(amount)) as total_amount, COUNT(*) as transaction_count
        FROM qs_crime_organization_transactions
        WHERE organization_id = ? AND type IN ('withdraw','expense') AND status='completed'
        AND created_at >= DATE_SUB(NOW(), INTERVAL 30 DAY)
        GROUP BY type ORDER BY total_amount DESC
    ]], { orgId }) or {}

    local analytics = {
        revenueTrends    = revenueTrends,
        expenseBreakdown = expenseBreakdown,
        topSellingItems  = {},
    }

    db:saveCache("finance_analytics", analytics, orgId)
    return analytics
end

-- ──────────────────────────────────────────────────────────
-- OrganizationFinanceDB:getFinance(orgId)
--   Returns the raw finance row { clean_money, dirty_money }.
-- ──────────────────────────────────────────────────────────
function OrganizationFinanceDB:getFinance(orgId)
    if not orgId then Error("OrganizationFinanceDB:getFinance", "orgId is nil") return nil end

    local cached = db:getCache("finance", orgId)
    if cached then return cached end

    local row = MySQL.prepare.await([[
        SELECT * FROM qs_crime_organization_finance
        WHERE organization_id = ? LIMIT 1
    ]], { orgId })

    if not row then
        local newId = MySQL.insert.await([[
            INSERT INTO qs_crime_organization_finance (organization_id, clean_money, dirty_money)
            VALUES (?, 0, 0)
        ]], { orgId })

        if newId then
            row = { id = newId, organization_id = orgId,
                    clean_money = 0, dirty_money = 0 }
        else
            return nil
        end
    end

    row.clean_money = row.clean_money or 0
    row.dirty_money = row.dirty_money or 0

    db:saveCache("finance", row, orgId)
    return row
end
