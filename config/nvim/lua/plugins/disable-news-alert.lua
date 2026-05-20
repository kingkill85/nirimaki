-- Ported verbatim from basecamp/omarchy-nvim:lua/plugins/disable-news-alert.lua
-- Silences the LazyVim + Neovim news popups that otherwise nag on
-- every update.
return {
  "LazyVim/LazyVim",
  opts = {
    news = {
      lazyvim = false,
      neovim = false,
    },
  },
}
