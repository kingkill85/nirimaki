-- all-themes.lua — preinstall every colorscheme plugin Nirimaki ships
-- a theme for, lazy-loaded. The active theme's spec (plugins/theme.lua
-- → ~/.config/theme/current/neovim.lua) is what actually triggers a
-- specific colorscheme; lazy.nvim then loads the matching plugin on
-- demand. So a `qs-theme-set <name>` only needs to flip the active
-- spec — no plugin install at swap time.
--
-- Ported in spirit from basecamp/omarchy-nvim:lua/plugins/all-themes.lua
-- and extended to cover Nirimaki's 22 themes.

return {
  { "bjarneo/aether.nvim",         lazy = true, priority = 1000 },
  { "ficcdaf/ashen.nvim",          lazy = true, priority = 1000 },
  { "ribru17/bamboo.nvim",         lazy = true, priority = 1000 },
  { "catppuccin/nvim",   name = "catppuccin", lazy = true, priority = 1000 },
  { "bjarneo/ethereal.nvim",       lazy = true, priority = 1000 },
  { "neanias/everforest-nvim",     lazy = true, priority = 1000 },
  { "kepano/flexoki-neovim",       lazy = true, priority = 1000 },
  { "ellisonleao/gruvbox.nvim",    lazy = true, priority = 1000 },
  { "bjarneo/hackerman.nvim",      lazy = true, priority = 1000 },
  { "rebelot/kanagawa.nvim",       lazy = true, priority = 1000 },
  { "omacom-io/lumon.nvim",        lazy = true, priority = 1000 },
  { "tahayvr/matteblack.nvim",     lazy = true, priority = 1000 },
  { "OldJobobo/miasma.nvim",       lazy = true, priority = 1000 },
  { "gthelding/monokai-pro.nvim",  lazy = true, priority = 1000 },
  { "EdenEast/nightfox.nvim",      lazy = true, priority = 1000 },
  { "OldJobobo/retro-82.nvim",     lazy = true, priority = 1000 },
  { "rose-pine/neovim",  name = "rose-pine", lazy = true, priority = 1000 },
  { "folke/tokyonight.nvim",       lazy = true, priority = 1000 },
  { "bjarneo/vantablack.nvim",     lazy = true, priority = 1000 },
  { "bjarneo/white.nvim",          lazy = true, priority = 1000 },
}
