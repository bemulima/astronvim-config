-- Customize None-ls sources

---@type LazySpec
return {
  "nvimtools/none-ls.nvim",
  opts = function(_, opts)
    -- opts variable is the default configuration table for the setup function call
    local null_ls = require "null-ls"
    local null_ls_utils = require "null-ls.utils"

    -- Check supported formatters and linters
    -- https://github.com/nvimtools/none-ls.nvim/tree/main/lua/null-ls/builtins/formatting
    -- https://github.com/nvimtools/none-ls.nvim/tree/main/lua/null-ls/builtins/diagnostics

    -- Only insert new sources, do not replace the existing ones
    -- (If you wish to replace, use `opts.sources = {}` instead of the `list_insert_unique` function)
    opts.sources = require("astrocore").list_insert_unique(opts.sources, {
      -- Set a formatter
      null_ls.builtins.formatting.stylua,
      null_ls.builtins.formatting.prettier,
      null_ls.builtins.formatting.phpcsfixer.with {
        args = {
          "--no-interaction",
          "--quiet",
          "fix",
          "--config=.php-cs-fixer.dist.php",
          "$FILENAME",
        },
        cwd = function(params) return params.root end,
        prefer_local = "vendor/bin",
        condition = function()
          local root = null_ls_utils.get_root()

          return root
            and null_ls_utils.path.exists(null_ls_utils.path.join(root, ".php-cs-fixer.dist.php"))
            and null_ls_utils.path.exists(null_ls_utils.path.join(root, "vendor/bin/php-cs-fixer"))
        end,
      },
      null_ls.builtins.diagnostics.phpstan.with {
        args = {
          "analyse",
          "-c",
          "phpstan.nvim.neon",
          "--error-format",
          "json",
          "--no-progress",
          "--memory-limit=1G",
          "$FILENAME",
        },
        cwd = function(params) return params.root end,
        method = null_ls.methods.DIAGNOSTICS_ON_SAVE,
        prefer_local = "vendor/bin",
        to_temp_file = false,
        condition = function()
          local root = null_ls_utils.get_root()

          return root
            and null_ls_utils.path.exists(null_ls_utils.path.join(root, "phpstan.nvim.neon"))
            and null_ls_utils.path.exists(null_ls_utils.path.join(root, "vendor/bin/phpstan"))
        end,
      },
    })
  end,
}
