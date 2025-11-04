local M = {}

-- Default configuration values
local tpt_script = vim.api.nvim_get_runtime_file("lua/sql-autocomplete/tpt/export_db.tpt", true)
M.defaults = {
    -- Connection parameters
    -- log_mech = nil,
    -- user = nil,
    -- tdpid = nil,
    -- pattern

    -- Path configuration
    -- Uses standard Neovim cache and data directories
    temp_dir = vim.fn.stdpath('cache') .. '/sql-autocomplete',
    data_dir = vim.fn.stdpath('data') .. '/sql-autocomplete',
    data_completion_dir = 'data',

    -- tpt_script
    tpt_script = tpt_script[1],

    -- autocompletion mode : treesitter (default) or regex
    completion_mode = 'treesitter',

    -- pattern to filter result from database autocompletion
    filter_db = nil,

}

M.options = {}

--- Merges user-provided configuration with the defaults.
--- @param opts table | nil User configuration table.
function M.setup(opts)
    local effective_defaults = vim.deepcopy(M.defaults)

    local success, td_config = pcall(require, "vim-teradata.config")
    if success then
        local options = td_config.options
        local default_user_index = options.current_user_index
        effective_defaults.user = options.users[default_user_index].user
        effective_defaults.tdpid = options.users[default_user_index].tdpid
        effective_defaults.log_mech = options.users[default_user_index].log_mech
        effective_defaults.ft = options.ft
    end

    M.options = vim.tbl_deep_extend('force', {}, effective_defaults, opts or {})

    -- Create necessary directories
    local paths = {
        M.options.temp_dir,
        M.options.data_dir,
        M.options.data_dir .. '/' .. M.options.data_completion_dir,
    }
    for _, path in ipairs(paths) do
        if vim.fn.isdirectory(path) == 0 then
            vim.fn.mkdir(path, 'p')
        end
    end
end

return M
