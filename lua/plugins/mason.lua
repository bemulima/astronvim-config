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

        -- debugpy is intentionally not installed automatically for now: Mason's
        -- bundled Python 3.14 cannot bootstrap ensurepip on this host. Re-enable
        -- after the Mason package/runtime is fixed; Python debugging remains a
        -- supported optional capability.

        -- install any other package
        "tree-sitter-cli",
        "prettier",
        "eslint_d",
        "dockerfile-language-server",
        "intelephense",
        -- spectral-language-server is intentionally not installed automatically:
        -- the current Mason registry build invokes `node make package` and exits
        -- 127. Re-enable once that upstream package recipe is corrected.
      },
    },
  },
}
