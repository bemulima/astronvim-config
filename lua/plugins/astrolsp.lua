-- AstroLSP allows you to customize the features in AstroNvim's LSP configuration engine
-- Configuration documentation can be found with `:h astrolsp`
-- NOTE: We highly recommend setting up the Lua Language Server (`:LspInstall lua_ls`)
--       as this provides autocomplete and documentation while editing

---@type LazySpec
return {
  "AstroNvim/astrolsp",
  ---@type AstroLSPOpts
  opts = {
    -- Configuration table of features provided by AstroLSP
    features = {
      codelens = true, -- enable/disable codelens refresh on start
      inlay_hints = false, -- enable/disable inlay hints on start
      semantic_tokens = true, -- enable/disable semantic token highlighting
    },
    -- customize lsp formatting options
    formatting = {
      -- control auto formatting on save
      format_on_save = {
        enabled = true, -- enable or disable format on save globally
        allow_filetypes = { -- enable format on save for specified filetypes only
          -- "go",
        },
        ignore_filetypes = { -- disable format on save for specified filetypes
          -- "python",
        },
      },
      disabled = { -- disable formatting capabilities for the listed language servers
        -- disable lua_ls formatting capability if you want to use StyLua to format your lua code
        -- "lua_ls",
      },
      timeout_ms = 1000, -- default format timeout
      -- filter = function(client) -- fully override the default formatting function
      --   return true
      -- end
    },
    -- enable servers that you already have installed without mason
    servers = {
      -- "pyright"
    },
    -- customize language server configuration options passed to `lspconfig`
    ---@diagnostic disable: missing-fields
    config = {
      -- clangd = { capabilities = { offsetEncoding = "utf-8" } },
    },
    -- customize how language servers are attached
    handlers = {
      -- a function without a key is simply the default handler, functions take two parameters, the server name and the configured options table for that server
      -- function(server, opts) require("lspconfig")[server].setup(opts) end

      -- the key is the server that is being setup with `lspconfig`
      -- rust_analyzer = false, -- setting a handler to false will disable the set up of that language server
      -- pyright = function(_, opts) require("lspconfig").pyright.setup(opts) end -- or a custom handler function can be passed
    },
    -- Configure buffer local auto commands to add when attaching a language server
    autocmds = {
      -- first key is the `augroup` to add the auto commands to (:h augroup)
      lsp_codelens_refresh = {
        -- Optional condition to create/delete auto command group
        -- can either be a string of a client capability or a function of `fun(client, bufnr): boolean`
        -- condition will be resolved for each client on each execution and if it ever fails for all clients,
        -- the auto commands will be deleted for that buffer
        cond = "textDocument/codeLens",
        -- cond = function(client, bufnr) return client.name == "lua_ls" end,
        -- list of auto commands to set
        {
          -- events to trigger
          event = { "InsertLeave", "BufEnter" },
          -- the rest of the autocmd options (:h nvim_create_autocmd)
          desc = "Refresh codelens (buffer)",
          callback = function(args)
            if require("astrolsp").config.features.codelens then vim.lsp.codelens.refresh { bufnr = args.buf } end
          end,
        },
      },
    },
    -- mappings to be set up on attaching of a language server
    mappings = {
      n = {
        ["<Leader>la"] = {
          function()
            if vim.bo.filetype ~= "php" then
              vim.lsp.buf.code_action()
              return
            end

            local lnum = vim.api.nvim_win_get_cursor(0)[1] - 1
            local diagnostics = vim.diagnostic.get(0, { lnum = lnum })
            local has_diagnostics = #diagnostics > 0
            local action_sources = { phpactor = true, intelephense = true }
            local wanted_clients = {}

            for _, diagnostic in ipairs(diagnostics) do
              if action_sources[diagnostic.source] then wanted_clients[diagnostic.source] = true end
            end

            if next(wanted_clients) ~= nil then
              vim.lsp.buf.code_action {
                filter = function(client) return wanted_clients[client.name] == true end,
              }
              return
            end

            if has_diagnostics then
              vim.notify("No code actions available for current PHPStan diagnostics", vim.log.levels.INFO)
              return
            end

            vim.lsp.buf.code_action()
          end,
          desc = "LSP code action",
          cond = "textDocument/codeAction",
        },
        -- a `cond` key can provided as the string of a server capability to be required to attach, or a function with `client` and `bufnr` parameters from the `on_attach` that returns a boolean
        gD = {
          function() vim.lsp.buf.declaration() end,
          desc = "Declaration of current symbol",
          cond = "textDocument/declaration",
        },
        ["<Leader>uY"] = {
          function() require("astrolsp.toggles").buffer_semantic_tokens() end,
          desc = "Toggle LSP semantic highlight (buffer)",
          cond = function(client)
            return client.supports_method "textDocument/semanticTokens/full" and vim.lsp.semantic_tokens ~= nil
          end,
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
    -- A custom `on_attach` function to be run after the default `on_attach` function
    -- takes two parameters `client` and `bufnr`  (`:h lspconfig-setup`)
    on_attach = function(client, bufnr)
      if client.name == "phpactor" or client.name == "intelephense" then
        client.server_capabilities.documentFormattingProvider = false
        client.server_capabilities.documentRangeFormattingProvider = false
      end

      if client.name == "phpactor" then
        local default_publish_diagnostics = vim.lsp.handlers["textDocument/publishDiagnostics"]

        client.handlers["textDocument/publishDiagnostics"] = function(err, result, ctx, config)
          if result and result.diagnostics then
            result = vim.deepcopy(result)
            result.diagnostics = vim.tbl_filter(function(diagnostic)
              return type(diagnostic.message) == "string" and diagnostic.message:match("imported but not used")
            end, result.diagnostics)
          end

          return default_publish_diagnostics(err, result, ctx, config)
        end

        if client.handlers["textDocument/diagnostic"] then
          local default_pull_diagnostics = client.handlers["textDocument/diagnostic"]

          client.handlers["textDocument/diagnostic"] = function(err, result, ctx, config)
            if result and result.items then
              result = vim.deepcopy(result)
              result.items = vim.tbl_filter(function(diagnostic)
                return type(diagnostic.message) == "string" and diagnostic.message:match("imported but not used")
              end, result.items)
            end

            return default_pull_diagnostics(err, result, ctx, config)
          end
        end

        if vim.lsp.diagnostic and vim.lsp.diagnostic.get_namespace then
          local namespace = vim.lsp.diagnostic.get_namespace(client.id)
          vim.diagnostic.reset(namespace, bufnr)
        end
      end

      -- this would disable semanticTokensProvider for all clients
      -- client.server_capabilities.semanticTokensProvider = nil
    end,
  },
}
