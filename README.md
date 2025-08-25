# sql-autocomplete

## Dependencies :
* [fzf.vim](https://github.com/junegunn/fzf.vim) from junegunn to call fzf
* [autocompletels](https://github.com/ErwonB/autocompletels)

## Setup :

Fill the 2 required variables in lua/sql-autocomplete.lua :
* _vim.g.autocompletels_ : path to the executable of autocompletels
* _vim.g.autocompletels_data_ : path to the generated data

## Usage :
`\<C-x>\<C-u>` to trigger the manual completion option

To create a custom completion with [blink.cmp](https://github.com/Saghen/blink.cmp)

 ```
 sources = {
     default = { "sql_completion", ...},
     providers = {
         sql_completion = {
             name = "SqlCompletion",
             module = "sql_completion",
         },
     },

 },
 ```

 in `${NVIM_CONFIG}/lua/sql_completion/init.lua`

 ```
 local source = {}

function source.new()
    return setmetatable({}, { __index = source })
end

function source:get_completions(_, callback)
    local items = {}
    if vim.bo.filetype == 'teradata' or vim.bo.filetype == 'sql' then
        for _, value in ipairs(require 'completion'.complete_func(0, "")) do
            table.insert(items, {
                label = value,
                kind = require("blink.cmp.types").CompletionItemKind.Text,
                insertText = value,
                insertTextFormat = vim.lsp.protocol.InsertTextFormat.PlainText,
            })
        end
    end
    callback({ items = items })
end

return source
```

3 modes handled automatically :
* Database selection
* Table selection
* Fields selection

