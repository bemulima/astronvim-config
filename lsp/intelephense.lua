---@type vim.lsp.Config
return {
  settings = {
    intelephense = {
      files = { maxSize = 5000000 },
      diagnostics = {
        undefined = true,
        deprecated = true,
      },
    },
  },
}
