# TodoTreeView

TODO View for https://github.com/rxi/lite


## Base Functionality

This plugin will display notes that are in the code which start with:
* TODO
* FIX
* FIXME
* BUG
* IMPROVEMENT
Extra tags can be added if you add them to the `todo_tags` config. You can also
configure their colors using the `tag_colors` field if wanted.

You can select between two modes:
* tag - To display the notes organized by the note type
* file - To display the notes organized by file

The plugin registers the following key bindings:
* ctrl+shift+t - Toggles the visibility of the view
* ctrl+shift+e - Expands all the groups
* ctrl+shift+h - Hides all the groups
* ctrl+shift+b - Filters the notes

You can ignore specific directories or files by using the `ignore_paths` config.

## Demo

Example of the `tag` view
![Todo plugin demo](/lite-todo-view.png)


## Instructions

1. To install the plugin just copy the `todotreeview.lua` file (or the
`todotreeview-xl.lua` if you are using lite-xl) to the folder `data/plugins/`
of the lite editor.
2. If you want to register extra tags or change the display mode or update any
other of the settings you can edit your `data/user/init.lua` file (run the
`core:open-user-module` command to open the user file if using lite-xl):
```lua
local config = require "core.config"
local common = require "core.common"

-- Add extra tags
table.insert(config.todo_tags, "CLEANUP")

-- Set colors for the new tag
config.tag_colors = {
  CLEANUP = {
    tag={common.color("#008000")},
    tag_hover={common.color("#00d000")},
    text={common.color("#004000")},
    text_hover={common.color("#008000")},
  }
}

-- Set the file color when in file mode
config.todo_file_color = {
  name={common.color("#A267d9")},
  hover={common.color("#6DaE46")},
}

-- Change display mode
config.todo_mode = "file"

-- Change the separator between the tag and the text in file mode
config.todo_separator = " -> "

-- Change the default text if the note is empty
config.todo_default_text = "---"

-- Ignore directory and ignore specific file
table.insert(config.ignore_paths, "winlib/")
table.insert(config.ignore_paths, "README.md")
```

