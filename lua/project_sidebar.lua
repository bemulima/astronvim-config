local M = {}

local namespace = vim.api.nvim_create_namespace "project-sidebar"
local status_by_path = {}
local render_generation = 0
local project_switch_generation = 0

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

local function label(item)
  local status = status_by_path[item.path] or "…"
  local active = vim.t.project_root == item.path
  return string.format("%s %s %s", active and "▶" or " ", status, vim.fs.basename(item.path))
end

local function render()
  local bufnr = sidebar_buffer()
  local items = require("project_sessions").catalog().items
  local cursor = 1
  local winid = sidebar_window()
  if winid then cursor = vim.api.nvim_win_get_cursor(winid)[1] end

  local lines = { "Projects", "j/k: switch (100ms)  <Enter>: tree  r: refresh  q: close", "· clean  ! changed  ? no Git", "" }
  for _, item in ipairs(items) do
    table.insert(lines, label(item))
  end

  vim.bo[bufnr].modifiable = true
  vim.api.nvim_buf_set_lines(bufnr, 0, -1, false, lines)
  vim.api.nvim_buf_clear_namespace(bufnr, namespace, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, namespace, "Title", 0, 0, -1)
  vim.api.nvim_buf_add_highlight(bufnr, namespace, "Comment", 1, 0, -1)
  for index, item in ipairs(items) do
    local line = index + 3
    local status = status_by_path[item.path]
    if status == "!" then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "NeoTreeGitModified", line, 2, 3)
    elseif status == "?" then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "NeoTreeGitUntracked", line, 2, 3)
    elseif vim.t.project_root == item.path then
      vim.api.nvim_buf_add_highlight(bufnr, namespace, "Visual", line, 0, -1)
    end
  end
  vim.b[bufnr].project_sidebar_items = items
  vim.bo[bufnr].modifiable = false

  if winid and vim.api.nvim_win_is_valid(winid) then
    vim.api.nvim_win_set_cursor(winid, { math.min(math.max(cursor, 1), #lines), 0 })
  end
end

local function refresh_git_status()
  render_generation = render_generation + 1
  local generation = render_generation
  local items = require("project_sessions").catalog().items
  for _, item in ipairs(items) do
    vim.system({ "git", "status", "--porcelain" }, { cwd = item.path, text = true }, function(result)
      if generation ~= render_generation then return end
      vim.schedule(function()
        if generation ~= render_generation then return end
        if result.code == 0 then
          status_by_path[item.path] = result.stdout == "" and "·" or "!"
        else
          status_by_path[item.path] = "?"
        end
        render()
      end)
    end)
  end
end

local function selected_item()
  local bufnr = vim.api.nvim_get_current_buf()
  return (vim.b[bufnr].project_sidebar_items or {})[vim.api.nvim_win_get_cursor(0)[1] - 3]
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
      local winid = sidebar_window()
      if winid and vim.api.nvim_win_is_valid(winid) then vim.api.nvim_win_close(winid, true) end
      focus_neotree()
    end, 350)
  else
    -- Keep key-repeat events in the Projects buffer while Neo-tree redraws.
    focus_projects()
    vim.defer_fn(focus_projects, 50)
  end
end

local function switch_selected_debounced()
  local item = selected_item()
  if not item then return end
  project_switch_generation = project_switch_generation + 1
  local generation = project_switch_generation
  vim.defer_fn(function()
    if generation == project_switch_generation then open_selected(false, item) end
  end, 100)
end

local function move_and_switch(delta)
  local bufnr = vim.api.nvim_get_current_buf()
  local items = vim.b[bufnr].project_sidebar_items or {}
  if #items == 0 then return end
  local current = vim.api.nvim_win_get_cursor(0)[1]
  local line = math.min(math.max(current + delta, 4), #items + 3)
  vim.api.nvim_win_set_cursor(0, { line, 0 })
  switch_selected_debounced()
end

function M.show()
  local bufnr = sidebar_buffer()
  local winid = sidebar_window()
  if not winid then
    vim.cmd("topleft 30vsplit")
    winid = vim.api.nvim_get_current_win()
    vim.api.nvim_win_set_buf(winid, bufnr)
    configure_window(winid)
  end
  render()
  refresh_git_status()
  vim.defer_fn(M.ensure_leftmost, 0)
end

---Keep Projects as the far-left sidebar, with Neo-tree immediately to its right.
function M.ensure_leftmost()
  local winid = sidebar_window()
  if not winid or vim.api.nvim_win_get_position(winid)[2] == 0 then return end

  local bufnr = vim.api.nvim_win_get_buf(winid)
  local cursor = vim.api.nvim_win_get_cursor(winid)
  vim.api.nvim_win_close(winid, true)
  vim.cmd("topleft 30vsplit")
  winid = vim.api.nvim_get_current_win()
  vim.api.nvim_win_set_buf(winid, bufnr)
  configure_window(winid)
  vim.api.nvim_win_set_cursor(winid, cursor)
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

function M.setup()
  local bufnr = sidebar_buffer()
  vim.keymap.set("n", "<CR>", function()
    project_switch_generation = project_switch_generation + 1
    open_selected(true)
  end, { buffer = bufnr, desc = "Focus selected project tree" })
  vim.keymap.set("n", "j", function() move_and_switch(vim.v.count1) end, { buffer = bufnr, desc = "Next project" })
  vim.keymap.set("n", "k", function() move_and_switch(-vim.v.count1) end, { buffer = bufnr, desc = "Previous project" })
  vim.keymap.set("n", "r", M.refresh, { buffer = bufnr, desc = "Refresh projects and Git status" })
  vim.keymap.set("n", "q", function()
    project_switch_generation = project_switch_generation + 1
    M.toggle()
  end, { buffer = bufnr, desc = "Close project sidebar" })
end

return M
