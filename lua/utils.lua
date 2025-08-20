local M = {}

-- Query databases
function M.get_databases()
    local command = string.format('%s --path %s', vim.g.autocompletels, vim.g.autocompletels_data)
    local handle = io.popen(command)
    local result = handle:read('*a')
    handle:close()
    result = string.gsub(result, "\n", "")

    -- Parse the result and return a list of columns
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
    local result = handle:read('*a')
    handle:close()
    result = string.gsub(result, "\n", "")

    -- Parse the result and return a list of tables
    local tables = {}
    for line in result:gmatch('[^,]+') do
        table.insert(tables, line)
    end
    return tables
end

-- Query columns in a table
function M.get_columns(table_db_tb)
    local command = ""
    for _, item in ipairs(table_db_tb) do
        command = command .. "--db " .. item.db_name .. " --tb " .. item.tb_name .. " "
    end

    command = string.format('%s --path %s %s', vim.g.autocompletels, vim.g.autocompletels_data, command)
    local handle = io.popen(command)
    local result = handle:read('*a')
    handle:close()
    result = string.gsub(result, "\n", "")

    -- Parse the result and return a list of columns
    local columns = {}
    for line in result:gmatch('[^,]+') do
        table.insert(columns, line)
    end
    return columns
end

return M
