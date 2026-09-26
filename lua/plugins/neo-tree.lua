return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = function(_, opts)
    -- AstroNvim configures Neo-tree through an opts function. Extend its
    -- result here, rather than using an opts table that Lazy may overwrite.
    opts.close_if_last_window = false

    -- A file selected in Neo-tree must never replace the Projects picker.
    opts.open_files_do_not_replace_types = opts.open_files_do_not_replace_types or {}
    if not vim.tbl_contains(opts.open_files_do_not_replace_types, "project-sidebar") then
      table.insert(opts.open_files_do_not_replace_types, "project-sidebar")
    end

    opts.filesystem = opts.filesystem or {}
    opts.filesystem.window = opts.filesystem.window or {}
    opts.filesystem.window.mappings = opts.filesystem.window.mappings or {}
    opts.filesystem.window.mappings["<C-h>"] = function()
      local ok, sidebar = pcall(require, "project_sidebar")
      if ok and sidebar.is_open() then
        sidebar.focus()
      end
    end

    opts.filesystem.filtered_items = vim.tbl_deep_extend("force", opts.filesystem.filtered_items or {}, {
      visible = true,
      show_hidden_count = true,
      hide_dotfiles = false,
      hide_gitignored = true,
      hide_by_name = {
        -- '.git',
        -- '.DS_Store',
        -- 'thumbs.db',
      },
      never_show = {},
    })
    return opts
  end,
}
