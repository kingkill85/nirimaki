-- theme.lua — proxy that returns the currently-active Nirimaki theme's
-- plugin spec. qs-theme-set rewrites ~/.config/theme/current/neovim.lua
-- on every theme swap; this proxy re-dofile()s that path so a single
-- `:Lazy reload theme` (or our NirimakiReloadTheme()) picks up the new
-- spec via the User LazyReload autocmd in
-- plugins/nirimaki-theme-hotreload.lua.
--
-- Omarchy's equivalent uses a filesystem symlink at the same path. The
-- dofile approach is portable — install.sh doesn't need to create a
-- machine-specific symlink.

local p = vim.fn.expand("~/.config/theme/current/neovim.lua")
if vim.fn.filereadable(p) == 1 then
  local ok, spec = pcall(dofile, p)
  if ok and type(spec) == "table" then
    return spec
  end
end
-- Fallback: empty spec so LazyVim boots cleanly without a current theme.
return {}
