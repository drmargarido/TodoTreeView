# TodoTreeView

TODO View for https://github.com/rxi/lite


## Base Functionality

This plugin will display notes that are in the code which start with:
* TODO
* FIX
* FIXME
* BUG
* IMPROVEMENT
Extra tags can be added if you add them to the `todo_tags` config.

You can select between two modes:
* tag - To display the notes organized by the note type
* file - To display the notes organized by file

The plugin registers the following key bindings:
* ctrl+shift+t - Toggles the visibility of the view
* ctrl+shift+e - Expands all the groups
* ctrl+shift+h - Hides all the groups

You can ignore specific directories or files by using the `ignore_paths` config.

## Demo

Example of the `tag` view
![Todo plugin demo](/lite-todo-view.png)


## Instructions

1. To install the plugin just copy the `todotreeview.lua` file to the folder `data/plugins/` of the lite editor.
2. If you want to register extra tags or change the display mode to be used you
can edit your `data/user/init.lua`:
```lua
local config = require "core.config"

-- Add extra tags
table.insert(config.todo_tags, "CLEANUP")

-- Change display mode
config.todo_mode = "file"

-- Ignore directory and ignore specific file
table.insert(config.ignore_paths, "winlib/")
table.insert(config.ignore_paths, "README.md")
```
