local M = {}

local root_markers = { ".git", "go.mod", "package.json", "composer.json", "Makefile" }

local function session_cwd(data)
  if data and data.global and data.global.cwd then return data.global.cwd end
  if data and data.tab_scoped and data.tabs and data.tabs[1] then return data.tabs[1].cwd end
end

local function project_path(data)
  for _, buffer in ipairs((data and data.buffers) or {}) do
    if buffer.name and buffer.name ~= "" then
      local directory = vim.fs.dirname(buffer.name)
      if directory then
        local marker = vim.fs.find(root_markers, { path = directory, upward = true })[1]
        return marker and vim.fs.dirname(marker) or directory
      end
    end
  end
  return session_cwd(data)
end

local function session_label(item)
  if item.path and item.path ~= "" then
    local project = vim.fn.fnamemodify(item.path, ":t")
    if project == "" then project = item.path end
    return string.format("%s  —  %s", project, item.path)
  end
  return item.name
end

---Show every directory session with a readable project name and absolute path.
function M.select()
  local resession = require "resession"
  local files = require "resession.files"
  local util = require "resession.util"
  local items = {}
  local labels = {}

  for _, name in ipairs(resession.list { dir = "dirsession" }) do
    local ok, data = pcall(files.load_json_file, util.get_session_file(name, "dirsession"))
    local item = { name = name, path = ok and project_path(data) or nil }
    item.label = session_label(item)
    labels[item.label] = (labels[item.label] or 0) + 1
    table.insert(items, item)
  end

  -- A few old snapshots contain the same project buffers under two session names.
  -- Keep both selectable and distinguish only those duplicates.
  for _, item in ipairs(items) do
    if labels[item.label] > 1 then item.label = string.format("%s  [%s]", item.label, item.name) end
  end

  if #items == 0 then
    vim.notify("No saved project sessions", vim.log.levels.WARN)
    return
  end

  vim.ui.select(items, {
    kind = "resession_load",
    prompt = "Load project session",
    format_item = function(item) return item.label end,
  }, function(selected)
    if selected then resession.load(selected.name, { dir = "dirsession" }) end
  end)
end

return M
