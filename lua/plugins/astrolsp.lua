-- AstroLSP allows you to customize the features in AstroNvim's LSP configuration engine
-- Configuration documentation can be found with `:h astrolsp`

local function php_code_action()
  if vim.bo.filetype ~= "php" then
    vim.lsp.buf.code_action()
    return
  end

  local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
  local diagnostics = vim.diagnostic.get(0, { lnum = lnum })
  local action_sources = { phpactor = true, intelephense = true }
  local wanted_clients = {}

  for _, diagnostic in ipairs(diagnostics) do
    if action_sources[diagnostic.source] then wanted_clients[diagnostic.source] = true end
  end

  if next(wanted_clients) then
    vim.lsp.buf.code_action {
      filter = function(_, client_id)
        local client = vim.lsp.get_client_by_id(client_id)
        return client ~= nil and wanted_clients[client.name] == true
      end,
    }
  elseif #diagnostics > 0 then
    vim.notify("No code actions available for current PHPStan diagnostics", vim.log.levels.INFO)
  else
    vim.lsp.buf.code_action()
  end
end

---@type LazySpec
return {
  "AstroNvim/astrolsp",
  ---@type AstroLSPOpts
  opts = {
    features = {
      codelens = true,
      inlay_hints = false,
      semantic_tokens = true,
    },
    formatting = {
      format_on_save = {
        enabled = true,
        allow_filetypes = {},
        ignore_filetypes = {},
      },
      disabled = { "phpactor", "intelephense" },
      timeout_ms = 1000,
    },
    handlers = {
      -- This server has repeatedly exhausted a 4 GiB Node heap in large PHP repositories.
      stimulus_ls = false,
      -- The AstroCommunity TypeScript pack uses vtsls; avoid a duplicate ts_ls client.
      ts_ls = false,
    },
    mappings = {
      n = {
        ["<Leader>la"] = {
          php_code_action,
          desc = "LSP code action",
          cond = "textDocument/codeAction",
        },
      },
      x = {
        ["<Leader>la"] = {
          function() vim.lsp.buf.code_action() end,
          desc = "LSP code action",
          cond = "textDocument/codeAction",
        },
      },
    },
  },
}
