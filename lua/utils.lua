local M = {}

-- Query databases
function M.get_databases()
    local command = string.format('%s --path %s', vim.g.autocompletels, vim.g.autocompletels_data)
    local handle = io.popen(command)

    if not handle then
        vim.notify("Failed to execute command: " .. command, vim.log.levels.ERROR)
        return {}
    end

    local result = handle:read('*a')
    local success = handle:close()

    if not result then
        vim.notify("Failed to read output from command: " .. command, vim.log.levels.ERROR)
        return {}
    end

    if not success then
        vim.notify("Failed to close handle after reading command output", vim.log.levels.WARN)
    end
    result = string.gsub(result, "\n", "")

    -- Parse the result and return a list of databases
    local databases = {}
    for line in result:gmatch('[^,]+') do
        table.insert(databases, line)
    end
    return databases
end

-- Query tables in a database
function M.get_tables(database)
    local command = string.format('%s --path %s --db %s', vim.g.autocompletels, vim.g.autocompletels_data, database)
    local handle = io.popen(command)

    if not handle then
        vim.notify("Failed to execute command: " .. command, vim.log.levels.ERROR)
        return {}
    end

    local result = handle:read('*a')
    local success = handle:close()

    if not result then
        vim.notify("Failed to read output from command: " .. command, vim.log.levels.ERROR)
        return {}
    end

    if not success then
        vim.notify("Failed to close handle after reading command output", vim.log.levels.WARN)
    end

    result = string.gsub(result, "\n", "")

    local tables = {}
    for line in result:gmatch('[^,]+') do
        table.insert(tables, line)
    end

    return tables
end

-- Query columns in a table
function M.get_columns(table_db_tb)
    local command_parts = {}
    for _, item in ipairs(table_db_tb) do
        table.insert(command_parts, string.format('--db %s --tb %s', item.db_name, item.tb_name))
    end

    local command = string.format('%s --path %s %s', vim.g.autocompletels, vim.g.autocompletels_data,
        table.concat(command_parts, ' '))
    local handle = io.popen(command)

    if not handle then
        vim.notify("Failed to execute command: " .. command, vim.log.levels.ERROR)
        return {}
    end

    local result = handle:read('*a')
    local success = handle:close()

    if not result then
        vim.notify("Failed to read output from command: " .. command, vim.log.levels.ERROR)
        return {}
    end

    if not success then
        vim.notify("Failed to close handle after reading command output", vim.log.levels.WARN)
    end

    result = string.gsub(result, "\n", "")

    local columns = {}
    for line in result:gmatch('[^,]+') do
        table.insert(columns, line)
    end

    return columns
end

return M
