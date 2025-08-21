# sql-autocomplete

## Dependencies :
* [fzf.vim](https://github.com/junegunn/fzf.vim) from junegunn to call fzf
* [autocompletels](https://github.com/ErwonB/autocompletels)

## Setup :

Fill the 2 required variables in lua/sql-autocomplete.lua :
* _vim.g.autocompletels_ : path to the executable of autocompletels
* _vim.g.autocompletels_data_ : path to the generated data

## Usage :
'\<C-x>\<C-u>' to trigger the completion option

3 modes :
* Database selection
* Table selection
* Fields selection

