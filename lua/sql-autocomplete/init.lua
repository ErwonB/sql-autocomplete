local utils = require('sql-autocomplete.utils')
local config = require('sql-autocomplete.config')

local M = {}

local function register_td_provider()
    local ok, blink = pcall(require, 'blink.cmp')
    if not ok then return end

    local blink_config = require('blink.cmp.config')
    local provider_lib = require('blink.cmp.sources.lib.provider')
    local sources_lib = require('blink.cmp.sources.lib')

    local id = 'td_sql_completion'
    local cfg = {
        name = 'TD SQL Completion',
        module = 'sql-autocomplete.blink_provider',
        score_offset = 0,
    }

    blink_config.sources.providers[id] = cfg

    local default = blink_config.sources.default or {}
    if not vim.tbl_contains(default, id) then
        table.insert(default, id)
    end
    blink_config.sources.default = default

    sources_lib.providers[id] = provider_lib.new(id, cfg)

    if blink.reload then blink.reload(id) end
end


--- Sets up the plugin configuration and autocommands for SQL filetypes.
--- @param user_config table User-provided configuration options.
--- @return nil
function M.setup(user_config)
    config.setup(user_config)
    vim.api.nvim_create_autocmd("FileType", {
        pattern = config.options.ft,
        callback = function()
            -- register this plugin as a blink provider
            register_td_provider()
            -- Set up a keybinding to trigger completion
            vim.api.nvim_buf_set_keymap(0, 'i', '<C-x><C-u>',
                '<cmd>lua require("sql-autocomplete.completion").trigger_fzf()<CR>', {
                    noremap = true,
                    silent = true
                })

            -- Define :TDSync command
            vim.api.nvim_create_user_command('TDSync', utils.export_db_data, { nargs = 0 })
        end
    })
end

return M
