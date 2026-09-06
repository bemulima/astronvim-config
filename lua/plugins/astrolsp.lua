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

  for _, diagnostic in ipairs(diagnostics) do
    if action_sources[diagnostic.source] then
      -- Neovim 0.12 calls `filter` with an action only, not a client id. Passing
      -- a two-argument filter therefore removed every PHP code action.
      vim.lsp.buf.code_action()
      return
    end
  end

  if #diagnostics > 0 then
    vim.notify("No code actions available for current PHPStan diagnostics", vim.log.levels.INFO)
  else
    vim.lsp.buf.code_action()
  end
end

---@type LazySpec
return {
  "AstroNvim/astrolsp",
  init = function()
    -- `mason-lspconfig` enables installed servers after AstroFile. On a startup
    -- that opens a file directly, its first FileType event has already passed.
    -- Retry that event for up to two seconds, then stop; this lets the initial
    -- project buffer attach without making LSP eager for every Neovim startup.
    vim.api.nvim_create_autocmd("User", {
      pattern = "AstroFile",
      desc = "Attach newly enabled LSPs to the initial project buffer",
      callback = function()
        local attempts = 0
        local function retry_filetype()
          attempts = attempts + 1
          if next(vim.lsp._enabled_configs) then
            for _, bufnr in ipairs(vim.api.nvim_list_bufs()) do
              if vim.api.nvim_buf_is_valid(bufnr) and vim.bo[bufnr].buftype == "" and vim.api.nvim_buf_get_name(bufnr) ~= "" then
                vim.api.nvim_exec_autocmds("FileType", { buffer = bufnr, modeline = false })
              end
            end
            return
          end
          if attempts < 20 then vim.defer_fn(retry_filetype, 100) end
        end
        vim.defer_fn(retry_filetype, 100)
      end,
    })
  end,
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
