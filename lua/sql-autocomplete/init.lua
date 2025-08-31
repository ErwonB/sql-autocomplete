local utils = require('sql-autocomplete.utils')
local config = require('sql-autocomplete.config')

local M = {}

--- Sets up the plugin configuration and autocommands for SQL filetypes.
--- @param user_config table User-provided configuration options.
--- @return nil
function M.setup(user_config)
    config.setup(user_config)
    vim.api.nvim_create_autocmd("FileType", {
        pattern = config.options.ft,
        callback = function()
            -- Set completefunc for SQL files
            vim.api.nvim_set_option_value('completefunc', "v:lua.require'sql-autocomplete.completion'.complete_func",
                { buf = 0 })

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
