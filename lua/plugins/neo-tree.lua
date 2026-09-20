return {
  "nvim-neo-tree/neo-tree.nvim",
  opts = {
    -- A project tab first opens its project sidebar, then Neo-tree. Keep the
    -- explorer alive while that layout is being assembled.
    close_if_last_window = false,
    filesystem = {
      filtered_items = {
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
      },
    },
  },
}
