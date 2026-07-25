local function keep_unused_imports(diagnostics)
  return vim.tbl_filter(
    function(diagnostic)
      return type(diagnostic.message) == "string" and diagnostic.message:match "imported but not used"
    end,
    diagnostics
  )
end

local function filtered_handler(method, field)
  local default_handler = vim.lsp.handlers[method]

  return function(err, result, ctx, config)
    if result and result[field] then
      result = vim.deepcopy(result)
      result[field] = keep_unused_imports(result[field])
    end

    return default_handler(err, result, ctx, config)
  end
end

return {
  handlers = {
    ["textDocument/publishDiagnostics"] = filtered_handler("textDocument/publishDiagnostics", "diagnostics"),
    ["textDocument/diagnostic"] = filtered_handler("textDocument/diagnostic", "items"),
  },
}
