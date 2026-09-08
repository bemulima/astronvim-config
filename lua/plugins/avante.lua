return {
  "yetone/avante.nvim",
  -- Keep Lua sources and the loadable arm64 libraries on the same release.
  -- v0.2.3's published macOS artifact requires unavailable Nix libraries;
  -- v0.1.2 is a known-compatible release for this installation.
  tag = "v0.1.2",
  -- Download the release-matched arm64/LuaJIT libraries instead of compiling.
  build = "bash build.sh",
  -- Avante requires its logger while sourcing plugin/avante.lua, before opts are
  -- applied.  Set a valid numeric level at Lazy's early-init phase.
  init = function()
    if type(vim.g.avante) ~= "table" then vim.g.avante = {} end
    vim.g.avante.log_level = vim.log.levels.WARN
  end,
  opts = {
    log_level = vim.log.levels.WARN,
    provider = "deepseek",
    providers = {
      deepseek = {
        __inherited_from = "openai",
        api_key_name = "DEEPSEEK_API_KEY",
        endpoint = "https://api.deepseek.com",
        model = "deepseek-coder",
      },
    },
  },
}
