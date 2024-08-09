-- mod-version:3
local core = require "core"
local common = require "core.common"
local command = require "core.command"
local config = require "core.config"
local keymap = require "core.keymap"
local style = require "core.style"
local View = require "core.view"
local CommandView = require "core.commandview"
local DocView = require "core.docview"

local TodoTreeView = View:extend()

local SCOPES = {
  ALL     = "all",
  FOCUSED = "focused",
}

config.plugins.todotreeview = common.merge({
  todo_tags = {"TODO", "BUG", "FIX", "FIXME", "IMPROVEMENT"},
  tag_colors = {
    TODO        = {tag=style.text, tag_hover=style.accent, text=style.text, text_hover=style.accent},
    BUG         = {tag=style.text, tag_hover=style.accent, text=style.text, text_hover=style.accent},
    FIX         = {tag=style.text, tag_hover=style.accent, text=style.text, text_hover=style.accent},
    FIXME       = {tag=style.text, tag_hover=style.accent, text=style.text, text_hover=style.accent},
    IMPROVEMENT = {tag=style.text, tag_hover=style.accent, text=style.text, text_hover=style.accent},
  },
  todo_file_color = {
    name=style.text,
    hover=style.accent
  },
  -- Paths or files to be ignored
  ignore_paths = {},

  -- Tells if the plugin should start with the nodes expanded
  todo_expanded = true,

  -- 'tag' mode can be used to group the todos by tags
  -- 'file' mode can be used to group the todos by files
  -- 'file_tag' mode can be used to group the todos by files and then by tags inside the files
  todo_mode = "tag",

  treeview_size = 200 * SCALE, -- default size

  -- Only used in file mode when the tag and the text are on the same line
  todo_separator = " - ",

  -- Text displayed when the note is empty
  todo_default_text = "blank",

  -- Scope of the displayed tags
  -- 'all' scope to show all tags from the project all the time
  -- 'focused' scope to show the tags from the currently focused file
  todo_scope = SCOPES.ALL,

  -- The config specification used by the settings gui
  config_spec = {
    name = "TodoTreeView",
    {
      label = "Todo Tags",
      description = "List of tags to parse and show in the todo panel.",
      path = "todo_tags",
      type = "list_strings",
      default = {"TODO", "BUG", "FIX", "FIXME", "IMPROVEMENT"},
    },
    {
      label = "Paths to ignore",
      description = "Paths to be ignored when parsing the tags.",
      path = "ignore_paths",
      type = "list_strings",
      default = {}
    },
    {
      label = "Groups Expanded",
      description = "Defines if the groups (Tags / Files) should start expanded.",
      path = "todo_expanded",
      type = "toggle",
      default = true,
    },
    {
      label = "Mode for the todos",
      description = "Mode for the todos to be displayed.",
      path = "todo_mode",
      type = "selection",
      default = "tag",
      values = {
        {"Tag", "tag"},
        {"File", "file"},
        {"FileTag", "file_tag"}
      }
    },
    {
      label = "Treeview Size",
      description = "Size of the todo tree view panel.",
      path = "treeview_size",
      type = "number",
      default = 200 * SCALE,
    },
    {
      label = "Todo separator",
      description = "Separator used in file mode when the tag and the text are on the same line.",
      path = "todo_separator",
      type = "string",
      default = " - ",
    },
    {
      label = "Empty Default Text",
      description = "Default text displayed for a note when it has no text.",
      path = "todo_default_text",
      type = "string",
      default = " - ",
    },
    {
      label = "Todo Scope",
      description = "Scope for the notes to be picked, all notes or currently focused file.",
      path = "todo_scope",
      type = "selection",
      default = "all",
      values = {
        {"All", "all"},
        {"Focused", "focused"},
      }
    },
  }
}, config.plugins.todotreeview)

local icon_small_font = style.icon_font:copy(10 * SCALE)

function TodoTreeView:new()
  TodoTreeView.super.new(self)
  self.scrollable = true
  self.focusable = false
  self.visible = true
  self.times_cache = {}
  self.cache = {}
  self.cache_updated = false
  self.init_size = true
  self.focus_index = 0
  self.filter = ""
  self.previous_focused_file = nil

  -- Items are generated from cache according to the mode
  self.items = {}
end

local function is_file_ignored(filename)
  for _, path in ipairs(config.plugins.todotreeview.ignore_paths) do
    local s, _ = filename:find(path)
    if s then
      return true
    end
  end

  return false
end

function TodoTreeView:is_file_in_scope(filename)
  if config.plugins.todotreeview.todo_scope == SCOPES.ALL then
    return true
  elseif config.plugins.todotreeview.todo_scope == SCOPES.FOCUSED then
    if core.active_view:is(CommandView) or core.active_view:is(TodoTreeView) then
      if self.previous_focused_file then
        return self.previous_focused_file == filename
      end
    elseif core.active_view:is(DocView) then
      return core.active_view.doc.filename == filename
    end
    return true
  else
    assert(false, "Unknown scope defined ("..config.plugins.todotreeview.todo_scope..")")
  end
end

function TodoTreeView.get_all_files()
  local all_files = {}
  for _, file in ipairs(core.project_files) do
    if file.filename then
      all_files[file.filename] = file
    end
  end
  for _, file in ipairs(core.docs) do
    if file.filename and not all_files[file.filename] then
      all_files[file.filename] = {
        filename = file.filename,
        type = "file"
      }
    end
  end
  return all_files
end

function TodoTreeView:refresh_cache()
  local items = {}
  if not next(self.items) then
    items = self.items
  end
  self.updating_cache = true

  core.add_thread(function()
    for _, item in pairs(self.get_all_files()) do
      local ignored = is_file_ignored(item.filename)
      if not ignored and item.type == "file" then
        local cached = self:get_cached(item)

        if config.plugins.todotreeview.todo_mode == "file" then
          items[cached.filename] = cached
        elseif config.plugins.todotreeview.todo_mode == "file_tag" then
          local file_t = {}
          file_t.expanded = config.plugins.todotreeview.todo_expanded
          file_t.type = "file"
          file_t.tags = {}
          file_t.todos = {}
          file_t.filename = cached.filename
          file_t.abs_filename = cached.abs_filename
          items[cached.filename] = file_t
          for _, todo in ipairs(cached.todos) do
            local tag = todo.tag
            if not file_t.tags[tag] then
              local tag_t = {}
              tag_t.expanded = config.plugins.todotreeview.todo_expanded
              tag_t.type = "group"
              tag_t.todos = {}
              tag_t.tag = tag
              file_t.tags[tag] = tag_t
            end

            table.insert(file_t.tags[tag].todos, todo)
          end
        else
          for _, todo in ipairs(cached.todos) do
            local tag = todo.tag
            if not items[tag] then
              local t = {}
              t.expanded = config.plugins.todotreeview.todo_expanded
              t.type = "group"
              t.todos = {}
              t.tag = tag
              items[tag] = t
            end

            table.insert(items[tag].todos, todo)
          end
        end
      end
    end

    -- Copy expanded from old items
    if config.plugins.todotreeview.todo_mode == "tag" and next(self.items) then
      for tag, data in pairs(self.items) do
        if items[tag] then
          items[tag].expanded = data.expanded
        end
      end
    end

    self.items = items
    core.redraw = true
    self.cache_updated = true
    self.updating_cache = false
  end, self)
end


local function find_file_todos(t, filename)
  local fp = io.open(filename)
  if not fp then return t end
  local n = 1
  for line in fp:lines() do
    for _, todo_tag in ipairs(config.plugins.todotreeview.todo_tags) do
      -- Add spaces at the start and end of line so the pattern will pick
      -- tags at the start and at the end of lines
      local extended_line = " "..line.." "
      local match_str = "[^a-zA-Z_\"'`]"..todo_tag.."[^\"'a-zA-Z_`]+"
      local s, e = extended_line:find(match_str)
      if s then
        local d = {}
        d.type = "todo"
        d.tag = todo_tag
        d.filename = filename
        d.text = extended_line:sub(e+1)
        if d.text == "" then
          d.text = config.plugins.todotreeview.todo_default_text
        end
        d.line = n
        d.col = s
        table.insert(t, d)
      end
      core.redraw = true
    end
    if n % 100 == 0 then coroutine.yield() end
    n = n + 1
    core.redraw = true
  end
  fp:close()
end


function TodoTreeView:get_cached(item)
  local t = self.cache[item.filename]
  if not t then
    t = {}
    t.expanded = config.plugins.todotreeview.todo_expanded
    t.filename = item.filename
    t.abs_filename = system.absolute_path(item.filename)
    t.type = item.type
    t.todos = {}
    t.tags = {}
    find_file_todos(t.todos, t.filename)
    self.cache[t.filename] = t
  end
  return t
end


function TodoTreeView:get_name()
  return "Todo Tree"
end

function TodoTreeView:set_target_size(axis, value)
  if axis == "x" then
    config.plugins.todotreeview.treeview_size = value
    return true
  end
end

function TodoTreeView:get_item_height()
  return style.font:get_height() + style.padding.y
end


function TodoTreeView:get_cached_time(doc)
  local t = self.times_cache[doc]
  if not t then
    local info = system.get_file_info(doc.filename)
    if not info then return nil end
    self.times_cache[doc] = info.modified
  end
  return t
end


function TodoTreeView:check_cache()
  local existing_docs = {}
  for _, doc in ipairs(core.docs) do
    if doc.filename then
      existing_docs[doc.filename] = true
      local info = system.get_file_info(doc.filename)
      local cached = self:get_cached_time(doc)
      if not info and cached then
        -- document deleted
        self.times_cache[doc] = nil
        self.cache[doc.filename] = nil
        self.cache_updated = false
      elseif cached and cached ~= info.modified then
        -- document modified
        self.times_cache[doc] = info.modified
        self.cache[doc.filename] = nil
        self.cache_updated = false
      elseif not cached then
        self.cache_updated = false
      end
    end
  end

  for _, file in ipairs(core.project_files) do
    existing_docs[file.filename] = true
  end

  -- Check for docs in cache that may not exist anymore
  -- for example: (Openend from outside of project and closed)
  for filename, doc in pairs(self.cache) do
    local exists = existing_docs[filename]
    if not exists then
      self.times_cache[doc] = nil
      self.cache[filename] = nil
      self.cache_updated = false
    end
  end

  if core.project_files ~= self.last_project_files then
    self.last_project_files = core.project_files
    self.cache_updated = false
  end
end

function TodoTreeView:each_item()
  self:check_cache()
  if not self.updating_cache and not self.cache_updated then
    self:refresh_cache()
  end

  return coroutine.wrap(function()
    local ox, oy = self:get_content_offset()
    local y = oy + style.padding.y
    local w = self.size.x
    local h = self:get_item_height()

    for filename, item in pairs(self.items) do
      local in_scope = item.type == "group" or self:is_file_in_scope(item.filename)
      if in_scope and #item.todos > 0 then
        coroutine.yield(item, ox, y, w, h)
        y = y + h

        for _, todo in ipairs(item.todos) do
          if item.expanded then
            local in_todo = string.find(todo.text:lower(), self.filter:lower())
            local todo_in_scope = self:is_file_in_scope(todo.filename)
            if todo_in_scope and (#self.filter == 0 or in_todo) then
              coroutine.yield(todo, ox, y, w, h)
              y = y + h
            end
          end
        end

      end
      if in_scope and item.tags then
        local first_tag = true
        for _, tag in pairs(item.tags) do
          if first_tag then
            coroutine.yield(item, ox, y, w, h)
            y = y + h
            first_tag = false
          end
          if item.expanded then
            coroutine.yield(tag, ox, y, w, h)
            y = y + h

            for _, todo in ipairs(tag.todos) do
              if item.expanded and tag.expanded then
                local in_todo = string.find(todo.text:lower(), self.filter:lower())
                local todo_in_scope = self:is_file_in_scope(todo.filename)
                if todo_in_scope and (#self.filter == 0 or in_todo) then
                  coroutine.yield(todo, ox, y, w, h)
                  y = y + h
                end
              end
            end
          end
        end
      end

    end
  end)
end


function TodoTreeView:on_mouse_moved(px, py)
  self.hovered_item = nil
  for item, x,y,w,h in self:each_item() do
    if px > x and py > y and px <= x + w and py <= y + h then
      self.hovered_item = item
      break
    end
  end
end

function TodoTreeView:goto_hovered_item()
  if not self.hovered_item then
    return
  end

  if self.hovered_item.type == "group" or self.hovered_item.type == "file" then
    return
  end

  core.try(function()
    local i = self.hovered_item
    local dv = core.root_view:open_doc(core.open_doc(i.filename))
    core.root_view.root_node:update_layout()
    dv.doc:set_selection(i.line, i.col)
    dv:scroll_to_line(i.line, false, true)
  end)
end

function TodoTreeView:on_mouse_pressed(button, x, y)
  if not self.hovered_item then
    return
  elseif self.hovered_item.type == "file"
    or self.hovered_item.type == "group" then
    self.hovered_item.expanded = not self.hovered_item.expanded
  else
    self:goto_hovered_item()
  end
end


function TodoTreeView:update()
  -- Update focus
  if core.active_view:is(DocView) then
    self.previous_focused_file = core.active_view.doc.filename
  elseif core.active_view:is(CommandView) or core.active_view:is(TodoTreeView) then
    -- Do nothing
  else
    self.previous_focused_file = nil
  end

  self.scroll.to.y = math.max(0, self.scroll.to.y)

  -- update width
  local dest = self.visible and config.plugins.todotreeview.treeview_size or 0
  if self.init_size then
    self.size.x = dest
    self.init_size = false
  else
    self:move_towards(self.size, "x", dest)
  end

  TodoTreeView.super.update(self)
end


function TodoTreeView:draw()
  self:draw_background(style.background2)

  --local h = self:get_item_height()
  local icon_width = style.icon_font:get_width("D")
  local spacing = style.font:get_width(" ") * 2
  local root_depth = 0

  for item, x,y,w,h in self:each_item() do
    local text_color = style.text
    local tag_color = style.text
    local file_color = config.plugins.todotreeview.todo_file_color.name or style.text
    if config.plugins.todotreeview.tag_colors[item.tag] then
      text_color = config.plugins.todotreeview.tag_colors[item.tag].text or style.text
      tag_color = config.plugins.todotreeview.tag_colors[item.tag].tag or style.text
    end

    -- hovered item background
    if item == self.hovered_item then
      renderer.draw_rect(x, y, w, h, style.line_highlight)
      text_color = style.accent
      tag_color = style.accent
      file_color = config.plugins.todotreeview.todo_file_color.hover or style.accent
      if config.plugins.todotreeview.tag_colors[item.tag] then
        text_color = config.plugins.todotreeview.tag_colors[item.tag].text_hover or style.accent
        tag_color = config.plugins.todotreeview.tag_colors[item.tag].tag_hover or style.accent
      end
    end

    -- icons
    local item_depth = 0
    x = x + (item_depth - root_depth) * style.padding.x + style.padding.x
    if item.type == "file" then
      local icon1 = item.expanded and "-" or "+"
      common.draw_text(style.icon_font, file_color, icon1, nil, x, y, 0, h)
      x = x + style.padding.x
      common.draw_text(style.icon_font, file_color, "f", nil, x, y, 0, h)
      x = x + icon_width
    elseif item.type == "group" then
      if config.plugins.todotreeview.todo_mode == "file_tag" then
        x = x + style.padding.x * 0.75
      end

      if item.expanded then
        common.draw_text(style.icon_font, tag_color, "-", nil, x, y, 0, h)
      else
        common.draw_text(icon_small_font, tag_color, ">", nil, x, y, 0, h)
      end
      x = x + icon_width / 2
    else
      if config.plugins.todotreeview.todo_mode == "tag" then
        x = x + style.padding.x
      else
        x = x + style.padding.x * 1.5
      end
      common.draw_text(style.icon_font, text_color, "i", nil, x, y, 0, h)
      x = x + icon_width
    end

    -- text
    x = x + spacing
    if item.type == "file" then
      common.draw_text(style.font, file_color, item.filename, nil, x, y, 0, h)
    elseif item.type == "group" then
      common.draw_text(style.font, tag_color, item.tag, nil, x, y, 0, h)
    else
      if config.plugins.todotreeview.todo_mode == "file" then
        common.draw_text(style.font, tag_color, item.tag, nil, x, y, 0, h)
        x = x + style.font:get_width(item.tag)
        common.draw_text(style.font, text_color, config.plugins.todotreeview.todo_separator..item.text, nil, x, y, 0, h)
      else
        common.draw_text(style.font, text_color, item.text, nil, x, y, 0, h)
      end
    end
  end
end

function TodoTreeView:get_item_by_index(index)
  local i = 0
  for item in self:each_item() do
    if index == i then
      return item
    end
    i = i + 1
  end
  return nil
end

function TodoTreeView:get_hovered_parent_file_tag()
  local file_parent = nil
  local file_parent_index = 0
  local group_parent = nil
  local group_parent_index = 0
  local i = 0
  for item in self:each_item() do
    if item.type == "file" then
      file_parent = item
      file_parent_index = i
    end
    if item.type == "group" then
      group_parent = item
      group_parent_index = i
    end
    if i == self.focus_index then
      if item.type == "file" or item.type == "group" then
        return file_parent, file_parent_index
      else
        return group_parent, group_parent_index
      end
    end
    i = i + 1
  end
  return nil, 0
end

function TodoTreeView:get_hovered_parent()
  local parent = nil
  local parent_index = 0
  local i = 0
  for item in self:each_item() do
    if item.type == "group" or item.type == "file" then
      parent = item
      parent_index = i
    end
    if i == self.focus_index then
      return parent, parent_index
    end
    i = i + 1
  end
  return nil, 0
end

function TodoTreeView:update_scroll_position()
  local h = self:get_item_height()
  local _, min_y, _, max_y = self:get_content_bounds()
  local start_row = math.floor(min_y / h)
  local end_row = math.floor(max_y / h)
  if self.focus_index < start_row then
    self.scroll.to.y = self.focus_index * h
  end
  if self.focus_index + 1 > end_row then
    self.scroll.to.y = (self.focus_index * h) - self.size.y + h
  end
end

-- init
local view = TodoTreeView()
local node = core.root_view:get_active_node()
view.size.x = config.plugins.todotreeview.treeview_size
node:split("right", view, {x=true}, true)

core.status_view:add_item({
  predicate = function()
    return #view.filter > 0 and core.active_view and not core.active_view:is(CommandView)
  end,
  name = "todotreeview:filter",
  alignment = core.status_view.Item.RIGHT,
  get_item = function()
    return {
      style.text,
      string.format("Filter: %s", view.filter)
    }
  end,
  position = 1,
  tooltip = "Todos filtered by",
  separator = core.status_view.separator2
})

-- register commands and keymap
local previous_view = nil
command.add(nil, {
  ["todotreeview:toggle"] = function()
    view.visible = not view.visible
  end,

  ["todotreeview:expand-items"] = function()
    for _, item in pairs(view.items) do
      item.expanded = true
    end
  end,

  ["todotreeview:hide-items"] = function()
    for _, item in pairs(view.items) do
      item.expanded = false
    end
  end,

  ["todotreeview:toggle-focus"] = function()
    if not core.active_view:is(TodoTreeView) then
      previous_view = core.active_view
      core.set_active_view(view)
      view.hovered_item = view:get_item_by_index(view.focus_index)
    else
      command.perform("todotreeview:release-focus")
    end
  end,

  ["todotreeview:filter-notes"] = function()
    local todo_view_focus = core.active_view:is(TodoTreeView)
    local previous_filter = view.filter
    local submit = function(text)
      view.filter = text
      if todo_view_focus then
        view.focus_index = 0
        view.hovered_item = view:get_item_by_index(view.focus_index)
        view:update_scroll_position()
      end
    end
    local suggest = function(text)
      view.filter = text
    end
    local cancel = function(explicit)
      view.filter = previous_filter
    end
    core.command_view:enter("Filter Notes", {
      text = view.filter,
      submit = submit,
      suggest = suggest,
      cancel = cancel
    })
  end,
})

command.add(
  function()
    return core.active_view:is(TodoTreeView)
  end, {
  ["todotreeview:previous"] = function()
    if view.focus_index > 0 then
      view.focus_index = view.focus_index - 1
      view.hovered_item = view:get_item_by_index(view.focus_index)
      view:update_scroll_position()
    end
  end,

  ["todotreeview:next"] = function()
    local next_index = view.focus_index + 1
    local next_item = view:get_item_by_index(next_index)
    if next_item then
      view.focus_index = next_index
      view.hovered_item = next_item
      view:update_scroll_position()
    end
  end,

  ["todotreeview:collapse"] = function()
    if not view.hovered_item then
      return
    end

    if view.hovered_item.type == "file" then
      view.hovered_item.expanded = false
    else
      if view.hovered_item.type == "group" and view.hovered_item.expanded then
        view.hovered_item.expanded = false
      else
        if config.plugins.todotreeview.todo_mode == "file_tag" then
          view.hovered_item, view.focus_index = view:get_hovered_parent_file_tag()
        else
          view.hovered_item, view.focus_index = view:get_hovered_parent()
        end

        view:update_scroll_position()
      end
    end
  end,

  ["todotreeview:expand"] = function()
    if not view.hovered_item then
      return
    end

    if view.hovered_item.type == "file" or view.hovered_item.type == "group" then
      if view.hovered_item.expanded then
        command.perform("todotreeview:next")
      else
        view.hovered_item.expanded = true
      end
    end
  end,

  ["todotreeview:open"] = function()
    if not view.hovered_item then
      return
    end

    view:goto_hovered_item()
    view.hovered_item = nil
  end,

  ["todotreeview:release-focus"] = function()
    core.set_active_view(
      previous_view or core.root_view:get_primary_node().active_view
    )
    view.hovered_item = nil
  end,
})

keymap.add { ["ctrl+shift+t"] = "todotreeview:toggle" }
keymap.add { ["ctrl+shift+e"] = "todotreeview:expand-items" }
keymap.add { ["ctrl+shift+h"] = "todotreeview:hide-items" }
keymap.add { ["ctrl+shift+b"] = "todotreeview:filter-notes" }
keymap.add { ["up"] = "todotreeview:previous" }
keymap.add { ["down"] = "todotreeview:next" }
keymap.add { ["left"] = "todotreeview:collapse" }
keymap.add { ["right"] = "todotreeview:expand" }
keymap.add { ["return"] = "todotreeview:open" }
keymap.add { ["escape"] = "todotreeview:release-focus" }

