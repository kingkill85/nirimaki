-- Ported verbatim from basecamp/omarchy-nvim:lua/plugins/snacks-animated-scrolling-off.lua
-- Disable snacks.nvim's smooth-scroll animation. Nirimaki runs on niri
-- + Quickshell with its own opacity / blur layers; the extra easing
-- on every cursor move adds visible jitter against the translucent
-- background.
return {
  "folke/snacks.nvim",
  opts = {
    scroll = {
      enabled = false,
    },
  },
}
