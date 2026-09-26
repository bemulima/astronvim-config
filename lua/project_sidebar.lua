local M = {}

local namespace = vim.api.nvim_create_namespace "project-sidebar"
local status_by_path = {}
local render_generation = 0
local project_switch_generation = 0
local sidebar_width = 30
local selected_path
local first_project_line = 5
local filter_query = ""
local filter_input

local function sidebar_buffer()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    if vim.api.nvim_buf_is_valid(bufnr) and vim.b[bufnr].project_sidebar then return bufnr end
  end

  local bufnr = vim.api.nvim_create_buf(false, true)
  vim.b[bufnr].project_sidebar = true
  vim.bo[bufnr].bufhidden = "hide"
  vim.bo[bufnr].buftype = "nofile"
  vim.bo[bufnr].filetype = "project-sidebar"
  vim.bo[bufnr].swapfile = false
  return bufnr
end

local function sidebar_window()
  for _, winid in ipairs(vim.api.nvim_list_wins()) do
    if vim.api.nvim_win_is_valid(winid) and vim.b[vim.api.nvim_win_get_buf(winid)].project_sidebar then
      return winid
    end
  end
end

local function configure_window(winid)
  vim.wo[winid].number = false
  vim.wo[winid].relativenumber = false
  vim.wo[winid].signcolumn = "no"
  vim.wo[winid].winfixwidth = true
  vim.wo[winid].wrap = false
end

local function resize_sidebar(delta)
  local winid = sidebar_window()
  if not winid or not vim.api.nvim_win_is_valid(winid) then return end

  sidebar_width = math.max(20, vim.api.nvim_win_get_width(winid) + delta)
  vim.api.nvim_win_set_width(winid, sidebar_width)
end

local function label(item)
  local info = status_by_path[item.path] or {}
  local status = info.status or "…"
  local branch = info.branch and string.format("  %s", info.branch) or ""
  return string.format("  %s %s%s", status, vim.fs.basename(item.path), branch)
end

local function selected_index(items)
  for index, item in ipairs(items) do
    if item.path == selected_path then return index end
  end
end

local function initial_index(items)
  local selected = selected_index(items)
  if selected then return selected end
  for index, item in ipairs(items) do
    if item.path == vim.t.project_root then return index end
  end
  return #items > 0 and 1 or nil
end

local function fuzzy_match(text, query)
  local position = 1
  for char in query:gmatch(".") do
    local found = text:find(char, position, true)
    if not found then return false end
    position = found + 1
  end
  return true
end

local function filtered_items()
  local all_items = require("project_sessions").catalog().items
  local query = vim.trim(filter_query):lower()
  if query == "" then return all_items, #all_items end

  local tokens = vim.split(query, "%s+", { trimempty = true })
  local matches = {}
  for _, item in ipairs(all_items) do
    local branch = (status_by_path[item.path] or {}).branch or ""
    local text = (vim.fs.basename(item.path) .. " " .. branch):lower()
    local matched = true
    for _, token in ipairs(tokens) do
      if not fuzzy_match(text, token) then
        matched = false
        break
      end
    end
    if matched then table.insert(matches, item) end
  end
  return matches, #all_items
end

local function render()
  local bufnr = sidebar_buffer()
  local items, total = filtered_items()
  local index = selected_index(items)
  if not index and filter_query == "" then
    index = initial_index(items)
    if index then selected_path = items[index].path end
  end
  local cursor = #items > 0 and first_project_line + (index and index - 1 or 0) or 1
  local winid = sidebar_window()

  local filter_hint
  if filter_query == "" then
    filter_hint = "click/j/k: switch (100ms)  [g/]g: changes  /: filter  <Enter>: tree  r: refresh  q: close"
  else
    filter_hint = string.format("Filter: %s  %d/%d  <Esc>: clear", filter_query, #items, total)
  end
  local lines = { "Projects", filter_hint, "· clean  ! changed  ? no Git  branch", "" }
  for _, item in ipairs(items) do
    table.insert(lines, label(item))
  end
  if #items == 0 then table.insert(lines, "  No matching projects") end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, namespace, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, namespace, "Comment", 1, 0, -1)
  for index, item in ipairs(items) do
    local line = index + 3
    local info = status_by_path[item.path] or {}
    local status = info.status
    if item.path == selected_path then
      -- Remains visible even while focus is in Neo-tree.
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "PmenuSel", line, 0, -1)
    end
    if status == "!" then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "NeoTreeGitModified", line, 2, 3)
    elseif status == "?" then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "NeoTreeGitUntracked", line, 2, 3)
    end
    if info.branch then
      local branch_start = #string.format("  %s %s", status or "…", vim.fs.basename(item.path)) + 2
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "String", line, branch_start, -1)
    end
  end
  vim.b[bufnr].project_sidebar_items = items
  vim.bo[bufnr].modifiable = false

  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_cursor(winid, { cursor, 0 })
  end
end

local function branch_from_status(output)
  local header = output:match("([^\n]+)")
  if not header or not vim.startswith(header, "## ") then return nil end
  local branch = header:sub(4)
  local no_commits = branch:match("^No commits yet on (.+)$")
  if no_commits then return no_commits end
  if branch:match("^HEAD") then return "detached" end
  return branch:match("^(.-)%.%.%.") or branch:match("^(.-) %[") or branch
end

local function refresh_git_status()
  render_generation = render_generation + 1
  local generation = render_generation
  local items = require("project_sessions").catalog().items
  for _, item in ipairs(items) do
    vim.system({ "git", "status", "--porcelain=v1", "--branch" }, { cwd = item.path, text = true }, function(result)
      if generation ~= render_generation then return end
      vim.schedule(function()
        if generation ~= render_generation then return end
        if result.code == 0 then
          local changes = result.stdout:gsub("^[^\n]*\n?", "")
          status_by_path[item.path] = {
            status = changes == "" and "·" or "!",
            branch = branch_from_status(result.stdout),
          }
        else
          status_by_path[item.path] = { status = "?" }
        end
        render()
      end)
    end)
  end
end

local function selected_item()
  local bufnr = vim.api.nvim_get_current_buf()
  local item = (vim.b[bufnr].project_sidebar_items or {})[vim.api.nvim_win_get_cursor(0)[1] - first_project_line + 1]
  if item then selected_path = item.path end
  return item
end

local function focus_projects()
  local winid = sidebar_window()
  if winid and vim.api.nvim_win_is_valid(winid) then vim.api.nvim_set_current_win(winid) end
end

local function focus_neotree()
  local ok, manager = pcall(require, "neo-tree.sources.manager")
  if not ok then return end
  local state = manager.get_state("filesystem", nil, nil)
  if state and state.winid and vim.api.nvim_win_is_valid(state.winid) then vim.api.nvim_set_current_win(state.winid) end
end

local function open_selected(focus_tree, item)
  item = item or selected_item()
  if not item then return end
  require("project_sessions").open(item.path, { keep_sidebar = not focus_tree })
  -- Neo-tree finishes its asynchronous navigation just after this mapping and
  -- otherwise restores focus to its previous window. Set the intended focus
  -- only once that navigation has completed.
  if focus_tree then
    vim.defer_fn(function()
      focus_neotree()
    end, 350)
  else
    -- Keep key-repeat events in the Projects buffer while Neo-tree redraws.
    focus_projects()
    vim.defer_fn(focus_projects, 50)
  end
end

local function focus_selected_tree()
  local item = selected_item()
  if not item then return end
  project_switch_generation = project_switch_generation + 1
  require("project_sessions").open(item.path, { keep_sidebar = true })
  vim.defer_fn(focus_neotree, 150)
end

local function switch_selected_debounced()
  local item = selected_item()
  if not item then return end
  -- Update the persistent active-row highlight immediately; Neo-tree itself
  -- changes after the debounce interval.
  render()
  project_switch_generation = project_switch_generation + 1
  local generation = project_switch_generation
  vim.defer_fn(function()
    if generation == project_switch_generation then open_selected(false, item) end
  end, 100)
end

local function jump_to_changed_project(direction)
  local items = vim.b[vim.api.nvim_get_current_buf()].project_sidebar_items or {}
  if #items == 0 then return end

  local current = selected_index(items)
  for offset = 1, #items do
    local index
    if current then
      index = ((current - 1 + direction * offset) % #items) + 1
    else
      index = direction > 0 and offset or #items - offset + 1
    end
    if (status_by_path[items[index].path] or {}).status == "!" then
      selected_path = items[index].path
      render()
      switch_selected_debounced()
      return
    end
  end
  vim.notify("No projects with Git changes", vim.log.levels.INFO)
end

local function move_and_switch(delta)
  local bufnr = vim.api.nvim_get_current_buf()
  local items = vim.b[bufnr].project_sidebar_items or {}
  if #items == 0 then return end
  local index = selected_index(items)
  local line
  if index then
    line = math.min(math.max(first_project_line + index - 1 + delta, first_project_line), #items + first_project_line - 1)
  else
    line = delta > 0 and first_project_line or #items + first_project_line - 1
  end
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  switch_selected_debounced()
end

local function clear_filter()
  if filter_query == "" then return end
  filter_query = ""
  render()
end

local function open_filter()
  if filter_input and filter_input:valid() then
    vim.api.nvim_set_current_win(filter_input.win)
    return
  end

  local ok, snacks = pcall(require, "snacks")
  if not ok or not snacks.input then
    vim.notify("Snacks input is unavailable", vim.log.levels.WARN)
    return
  end

  local sidebar_win = sidebar_window()
  if not sidebar_win then return end
  filter_input = snacks.input({
    prompt = "Filter projects",
    default = filter_query,
    win = {
      relative = "win",
      win = sidebar_win,
      row = 1,
      col = 0,
      width = vim.api.nvim_win_get_width(sidebar_win),
      border = "single",
    },
  }, function(value)
    filter_input = nil
    filter_query = value or ""
    render()
  end)
  filter_input:on({ "TextChangedI", "TextChanged" }, function()
    if filter_input and filter_input:valid() then
      filter_query = filter_input:text()
      render()
    end
  end, { buf = true })
end

local function click_project()
  local mouse = vim.fn.getmousepos()
  local winid = mouse.winid
  if not winid or winid == 0 or not vim.api.nvim_win_is_valid(winid) then return end
  local bufnr = vim.api.nvim_win_get_buf(winid)
  if not vim.b[bufnr].project_sidebar then return end

  local items = vim.b[bufnr].project_sidebar_items or {}
  if mouse.line < first_project_line or mouse.line > #items + first_project_line - 1 then return end
  vim.api.nvim_set_current_win(winid)
  vim.api.nvim_win_set_cursor(winid, { mouse.line, math.max(mouse.column - 1, 0) })
  switch_selected_debounced()
end

function M.show()
  local bufnr = sidebar_buffer()
  local winid = sidebar_window()
  if not winid then
    -- Opening the picker always starts on the active project. The fallback to
    -- the first catalog item is handled by render when there is no active root.
    selected_path = vim.t.project_root
    vim.cmd("topleft " .. sidebar_width .. "vsplit")
    winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    configure_window(winid)
    vim.api.nvim_win_set_width(winid, sidebar_width)
  end
  render()
  refresh_git_status()
  M.ensure_leftmost()
end

---Keep Projects as the far-left sidebar, with Neo-tree immediately to its right.
function M.ensure_leftmost()
  local winid = sidebar_window()
  if not winid or vim.api.nvim_win_get_position(winid)[2] == 0 then return end

  -- Moving the existing window preserves its buffer, cursor, and user-set
  -- width. Recreating it with :vsplit caused the visible width jump.
  sidebar_width = vim.api.nvim_win_get_width(winid)
  vim.api.nvim_win_call(winid, function() vim.cmd "wincmd H" end)
  if vim.api.nvim_win_is_valid(winid) then
    configure_window(winid)
    vim.api.nvim_win_set_width(winid, sidebar_width)
  end
end

function M.toggle()
  local winid = sidebar_window()
  if winid then
    vim.api.nvim_win_close(winid, true)
  else
    M.show()
  end
end

function M.refresh()
  require("project_sessions").refresh()
  status_by_path = {}
  render()
  refresh_git_status()
end

---Refresh dirty indicators when the panel is visible, without rescanning roots.
function M.update_git_status()
  if sidebar_window() then refresh_git_status() end
end

function M.is_open() return sidebar_window() ~= nil end

function M.focus() focus_projects() end

function M.setup()
  local bufnr = sidebar_buffer()
  vim.keymap.set("n", "<CR>", function()
    project_switch_generation = project_switch_generation + 1
    open_selected(true)
  end, { buffer = bufnr, desc = "Focus selected project tree" })
  vim.keymap.set("n", "l", focus_selected_tree, { buffer = bufnr, desc = "Focus selected project tree" })
  vim.keymap.set("n", "<LeftMouse>", click_project, { buffer = bufnr, desc = "Switch clicked project" })
  vim.keymap.set("n", "<C-Left>", function() resize_sidebar(-2) end, { buffer = bufnr, desc = "Narrow projects" })
  vim.keymap.set("n", "<C-Right>", function() resize_sidebar(2) end, { buffer = bufnr, desc = "Widen projects" })
  vim.keymap.set("n", "j", function() move_and_switch(vim.v.count1) end, { buffer = bufnr, desc = "Next project" })
  vim.keymap.set("n", "k", function() move_and_switch(-vim.v.count1) end, { buffer = bufnr, desc = "Previous project" })
  vim.keymap.set("n", "]g", function() jump_to_changed_project(1) end, { buffer = bufnr, desc = "Next changed project" })
  vim.keymap.set("n", "[g", function() jump_to_changed_project(-1) end, { buffer = bufnr, desc = "Previous changed project" })
  vim.keymap.set("n", "/", open_filter, { buffer = bufnr, desc = "Filter projects" })
  vim.keymap.set("n", "<Esc>", clear_filter, { buffer = bufnr, desc = "Clear project filter" })
  vim.keymap.set("n", "r", M.refresh, { buffer = bufnr, desc = "Refresh projects and Git status" })
  vim.keymap.set("n", "q", function()
    project_switch_generation = project_switch_generation + 1
    M.toggle()
  end, { buffer = bufnr, desc = "Close project sidebar" })
end

return M
