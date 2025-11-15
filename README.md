# sql-autocomplete

## Dependencies :
* [fzf.vim](https://github.com/junegunn/fzf.vim) from junegunn to call fzf
* _tbuild_ : Teradata Tools and Utilities

## Setup :

Database connection can be taken directly from [vim-teradata](https://github.com/ErwonB/vim-teradata) configuration
Otherwise, provide following value in the setup :
* log_mech : logon mechanism (TD2, LDAP ...)
* user : DB username
* tdpid : hostname or IP of TD server

Optinal parameters :
* filter_db : used to filter databases matching this param
* completion_mode : treesitter(default)/regex

[treesitter to use](https://github.com/ErwonB/tree-sitter-teradata)

_sql-autocomplete_ relies on exported data file to do the completion, run the _TDSync_ command to generate them

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
        for _, value in ipairs(require 'sql-autocomplete.completion'.complete_func(0, "")) do
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

