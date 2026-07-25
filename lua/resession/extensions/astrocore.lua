local M = {}

local function is_valid_bufnr(bufnr) return type(bufnr) == "number" and vim.api.nvim_buf_is_valid(bufnr) end

local function map_and_filter_bufs(bufs, new_bufnrs)
  local mapped = {}
  if type(bufs) ~= "table" then return mapped end
  for _, bufnr in ipairs(bufs) do
    local new_bufnr = new_bufnrs[bufnr]
    if is_valid_bufnr(new_bufnr) then table.insert(mapped, new_bufnr) end
  end
  return mapped
end

---@param opts resession.Extension.OnSaveOpts
function M.on_save(opts)
  local data = { bufnrs = {}, tabs = {} }
  local buf_utils = require "astrocore.buffer"

  data.current_buf = buf_utils.current_buf
  data.last_buf = buf_utils.last_buf

  for new_tabpage, tabpage in ipairs(vim.api.nvim_list_tabpages()) do
    if tabpage == opts.tabpage then data.tabpage = new_tabpage end
    local tab_bufs = vim.t[tabpage].bufs or {}
    local bufs = {}
    for _, bufnr in ipairs(tab_bufs) do
      if is_valid_bufnr(bufnr) then
        table.insert(bufs, bufnr)
        local name = vim.api.nvim_buf_get_name(bufnr)
        if name ~= "" then data.bufnrs[name] = bufnr end
      end
    end
    data.tabs[new_tabpage] = bufs
  end

  return data
end

function M.on_post_load(data)
  local new_bufnrs = {}
  local new_tabpages = vim.api.nvim_list_tabpages()
  for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
    local name = vim.api.nvim_buf_get_name(bufnr)
    if name ~= "" then
      local old_bufnr = data.bufnrs[name]
      if old_bufnr then new_bufnrs[old_bufnr] = bufnr end
    end
  end

  if not data.tabpage then
    for tabpage, tabs in pairs(data.tabs or {}) do
      local new_tabpage = new_tabpages[tabpage]
      if new_tabpage then vim.t[new_tabpage].bufs = map_and_filter_bufs(tabs, new_bufnrs) end
    end
  else
    vim.t.bufs = map_and_filter_bufs((data.tabs or {})[data.tabpage], new_bufnrs)
  end

  local buf_utils = require "astrocore.buffer"
  local current_buf, last_buf = new_bufnrs[data.current_buf], new_bufnrs[data.last_buf]
  if is_valid_bufnr(current_buf) then buf_utils.current_buf = current_buf end
  if is_valid_bufnr(last_buf) then buf_utils.last_buf = last_buf end

  require("astrocore").event "BufsUpdated"

  if is_valid_bufnr(current_buf) and is_valid_bufnr(last_buf) then
    if vim.opt.bufhidden:get() == "wipe" and vim.fn.bufnr() ~= buf_utils.current_buf then
      vim.cmd.b(buf_utils.current_buf)
    end
  end
end

return M
