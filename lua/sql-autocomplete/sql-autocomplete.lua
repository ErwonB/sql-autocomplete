local completion = require('sql-autocomplete.completion')

vim.api.nvim_create_autocmd('FileType', {
    pattern = { 'sql', 'teradata' },
    callback = function()
        completion.setup()
    end,
})
