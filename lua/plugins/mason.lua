-- Customize Mason

---@type LazySpec
return {
  -- use mason-tool-installer for automatically installing Mason packages
  {
    "WhoIsSethDaniel/mason-tool-installer.nvim",
    -- overrides `require("mason-tool-installer").setup(...)`
    opts = {
      -- Make sure to use the names found in `:Mason`
      ensure_installed = {
        -- install language servers
        "lua-language-server",

        -- install formatters
        "stylua",

        -- install debuggers
        {
          "debugpy",
          -- Ubuntu needs python3.12-venv for Mason's virtual environment.
          -- Keep Python debugging optional until that system package is available.
          condition = function()
            return vim.system({ "python3", "-c", "import ensurepip" }, { text = true }):wait().code == 0
          end,
        },

        -- install any other package
        "tree-sitter-cli",
        "prettier",
        "eslint_d",
        "dockerfile-language-server",
        "intelephense",
        "spectral-language-server",
      },
    },
  },
}
