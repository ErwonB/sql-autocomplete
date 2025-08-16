local completion = require('completion')

-- autocompletels location : REQUIRED
vim.g.autocompletels = "***"
vim.g.autocompletels_data = "***"


vim.api.nvim_create_autocmd('FileType', {
    pattern = 'teradata',
    callback = function()
        completion.setup()
    end,
})


vim.api.nvim_create_autocmd('FileType', {
    pattern = 'sql',
    callback = function()
        completion.setup()
    end,
})
