local config = require('sql-autocomplete.config')
local M = {}

--- Safely removes one or more files.
--- @param ... string One or more file paths to delete.
local function remove_files(...)
    for _, file in ipairs({ ... }) do
        if vim.fn.filereadable(file) == 1 then
            vim.fn.delete(file)
        end
    end
end

--- Splits a temporary CSV file into per-database files and generates a summary file.
--- @return nil
local function split_data_db_file()
    local input_filename = config.options.data_dir .. "/data_tmp.csv"
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local summary_filename = data_files_dir .. "/data.csv"

    local file_handles = {}
    local unique_dbs = {}

    local input_file = io.open(input_filename, "r")
    if not input_file then
        return vim.notify("Error: Could not open the input file: " .. input_filename, vim.log.levels.ERROR)
    end

    for line in input_file:lines() do
        local db, rest = line:match("([^,]+),(.*)")

        if db and rest then
            local handle = file_handles[db]

            if not handle then
                handle = io.open(data_files_dir .. "/" .. db .. ".csv", "w")
                file_handles[db] = handle
                unique_dbs[db] = true
            end

            if handle then
                handle:write((rest or "") .. "\n")
            else
                return vim.notify("File handle is nil. Cannot write to file.", vim.log.levels.ERROR)
            end
        end
    end
    input_file:close()

    for _, handle in pairs(file_handles) do
        handle:close()
    end

    local summary_file = io.open(summary_filename, "w")
    if summary_file then
        for db_name in pairs(unique_dbs) do
            summary_file:write(db_name .. "\n")
        end
        summary_file:close()
    else
        return vim.notify("Error: Could not open the summary file for writing: " .. summary_filename,
            vim.log.levels.ERROR)
    end
end


--- Return true if db_name is a the db files, false otherwise
--- @return boolean db_name is present.
function M.is_a_db(db_name)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local db_file = data_files_dir .. "/data.csv"
    local input_file = io.open(db_file, "r")
    if not input_file then
        return false
    end

    for line in input_file:lines() do
        if line:lower() == db_name:lower() then
            return true
        end
    end

    return false
end

--- Retrieves a list of available databases from a summary CSV file.
--- @return table | nil A list of database names.
function M.get_databases()
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local db_file = data_files_dir .. "/data.csv"
    local input_file = io.open(db_file, "r")
    if not input_file then
        -- vim.notify("Error: Could not open the input file: " .. db_file .. "\nBe sure to run TDSync command first",
        --     vim.log.levels.ERROR)
        return {}
    end

    local filter_db = config.options.filter_db
    local databases = {}
    for line in input_file:lines() do
        if filter_db == nil or filter_db == ""
            or string.find(line:lower(), filter_db:lower(), 1, true) then
            table.insert(databases, line)
        end
    end

    return databases
end

--- Retrieves a list of unique tables from a database-specific CSV file.
--- @param database string The name of the database.
--- @return table | nil A list of table names.
function M.get_tables(database)
    local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
    local db_file = data_files_dir .. "/" .. database .. ".csv"
    local input_file = io.open(db_file, "r")
    if not input_file then
        -- vim.notify("Error: Could not open the input file: " .. db_file .. "\nBe sure to run TDSync command first",
        --     vim.log.levels.ERROR)
        return {}
    end

    local unique_tables = {}
    local tables = {}
    for line in input_file:lines() do
        local tb = line:match('([^,]+)')
        if not unique_tables[tb] then
            table.insert(tables, tb)
            unique_tables[tb] = true
        end
    end
    return tables
end

--- Retrieves a list of unique columns for specified tables in their respective databases.
--- Keeps a synchronous interface, but internally uses libuv worker threads.
--- Each CSV is expected to contain lines like: "table,column"
--- @param table_db_tb table[] list of { db_name = "db", tb_name = "table" }
--- @return table columns unique column names across the requested tables ({} on error)
function M.get_columns(table_db_tb)
    local uv = vim.uv or vim.loop

    -- Resolve base dir on main thread (workers cannot touch 'vim' objects)
    local data_files_dir = assert(
        config and config.options and config.options.data_dir, "config.options.data_dir not set"
    ) .. "/" .. assert(config.options.data_completion_dir, "config.options.data_completion_dir not set")

    -- Group tables by DB file so each CSV is scanned only once
    local per_db = {} ---@type table<string, {file:string, wanted:table<string,true>}>
    for _, item in ipairs(table_db_tb or {}) do
        if item and item.db_name and item.tb_name then
            local file = string.format("%s/%s.csv", data_files_dir, item.db_name)
            local entry = per_db[file]
            if not entry then
                entry = { file = file, wanted = {} }
                per_db[file] = entry
            end
            entry.wanted[item.tb_name] = true
        end
    end

    -- Nothing to do
    local job_payloads = {}
    for _, entry in pairs(per_db) do
        -- Build a string payload: "<file>\n<table1>\t<table2>\t..."
        local tnames = {}
        for tbname, _ in pairs(entry.wanted) do
            table.insert(tnames, tbname)
        end
        local payload = entry.file .. "\n" .. table.concat(tnames, "\t")
        table.insert(job_payloads, payload)
    end
    if #job_payloads == 0 then
        return {}
    end

    local acc, seen = {}, {} -- final accumulator on the main thread
    local pending = #job_payloads
    local err_msg = nil


    local work = uv.new_work(
    ---@param payload string
    ---@return string
        function(payload)
            ---@cast payload string
            -- Decode payload: "<file>\n<table1>\t<table2>\t..."
            local nl = string.find(payload, "\n", 1, true)
            if not nl then
                return "ERR\tbad-payload-no-newline"
            end
            local file = string.sub(payload, 1, nl - 1)
            local rest = string.sub(payload, nl + 1)

            -- Build wanted set from tab-separated table names
            local wanted = {}
            for name in string.gmatch(rest, "[^\t]+") do
                wanted[name] = true
            end

            -- Read file and collect unique columns across the wanted tables
            local fh = io.open(file, "r")
            if not fh then
                return "ERR\tCould not open the input file: " .. file .. "\nBe sure to run TDSync first"
            end

            local seen_cols = {}
            local cols = {}
            for line in fh:lines() do
                -- Expect "table,column"
                local tb, field = line:match('([^,]+),([^,]+)')
                if tb and field and wanted[tb] then
                    field = field:gsub("%s+$", "")
                    if not seen_cols[field] then
                        seen_cols[field] = true
                        cols[#cols + 1] = field
                    end
                end
            end
            fh:close()

            -- Marshal result as "OK\t<col1>\t<col2>\t..."
            return "OK\t" .. table.concat(cols, "\t")
        end,

        ---@param res string
        function(res)
            if err_msg then
                return
            end
            if type(res) ~= "string" or #res == 0 then
                err_msg = "Worker returned invalid result"
                return
            end
            if res:sub(1, 3) == "ERR" then
                err_msg = res:sub(5) -- strip "ERR\t"
                return
            end
            -- Merge "OK\t<col1>\t<col2>..." into global unique set
            local payload = res:sub(4)
            for col in payload:gmatch("[^\t]+") do
                if col ~= "" and not seen[col] then
                    seen[col] = true
                    table.insert(acc, col)
                end
            end
            pending = pending - 1
        end
    )

    -- Queue jobs (each argument MUST be a string)
    for _, payload in ipairs(job_payloads) do
        work:queue(payload)
    end

    -- Wait synchronously until all jobs done or error (keeps your call style)
    -- You can tune timeout (ms) if you want; here we allow up to 60s.
    local ok = vim.wait(60000, function()
        return pending == 0 or err_msg ~= nil
    end, 50)

    if not ok and not err_msg then
        err_msg = "Timeout while collecting columns"
    end

    if err_msg then
        return {}
    end

    return acc
end

-- --- Retrieves a list of unique columns for specified tables in their respective databases.
-- --- @param table_db_tb table A list of tables with associated database names (e.g., { db_name = "db", tb_name = "table" }).
-- --- @return table | nil A list of column names.
-- function M.get_columns(table_db_tb)
--     local data_files_dir = config.options.data_dir .. "/" .. config.options.data_completion_dir
--     local unique_columns = {}
--     local columns = {}
--     for _, item in ipairs(table_db_tb) do
--         local db_file = data_files_dir .. "/" .. item.db_name .. ".csv"
--         local input_file = io.open(db_file, "r")
--         if not input_file then
--             -- vim.notify(
--             --     "Error: Could not open the input file: " .. db_file .. "\nBe sure to run TDSync command first",
--             -- vim.log.levels.ERROR)
--             return {}
--         end
--
--         for line in input_file:lines() do
--             local tb, field = line:match('([^,]+),([^,]+)')
--             if tb == item.tb_name then
--                 field = field:gsub("%s+$", "")
--                 if not unique_columns[field] then
--                     table.insert(columns, field)
--                     unique_columns[field] = true
--                 end
--             end
--         end
--     end
--
--     return columns
-- end

--- Checks if required external commands are executable.
--- @param commands table A list of command names to check (e.g., {'rg', 'bat'}).
--- @return boolean, string True if all exist, otherwise false and an error message.
function M.check_executables(commands)
    for _, cmd in ipairs(commands) do
        if vim.fn.executable(cmd) == 0 then
            return false, string.format('Error: %s is not installed or not in your PATH.', cmd) --
        end
    end
    return true, ""
end

--- Runs a Teradata export script and processes the resulting data into structured files.
--- @return nil
function M.export_db_data()
    local user = config.options.user
    local tdpid = config.options.tdpid
    local logon_mech = config.options.log_mech
    local tpt_script = config.options.tpt_script

    local data_tmp = config.options.data_dir

    local ok, msg = M.check_executables({ 'tbuild' })
    if not ok then
        return vim.notify(msg, vim.log.levels.ERROR)
    end

    if not user or not tdpid or not tpt_script or not logon_mech then
        return vim.notify("Missing TD env variables", vim.log.levels.ERROR)
    end

    local tbuild_command = "tbuild -f " ..
        tpt_script ..
        " -u \"user='" ..
        user .. "', logon_mech='" .. logon_mech .. "', tdpid='" .. tdpid .. "', data_path='" .. data_tmp .. "'\""

    local data_tmp_file = data_tmp .. "/data_tmp.csv"
    remove_files(data_tmp_file)
    local tpt_result = vim.fn.system(tbuild_command)
    local exit_code = vim.v.shell_error
    if exit_code ~= 0 then
        return vim.notify("tbuild command failed : " .. tpt_result, vim.log.levels.ERROR)
    end

    split_data_db_file()
    remove_files(data_tmp_file)
end

return M
