-- nirimaki-theme-hotreload.lua — wire qs-theme-set to live theme swap.
--
-- qs-theme-set writes the new active theme to
-- ~/.config/theme/current/neovim.lua, then RPCs every running nvim
-- with `:lua NirimakiReloadTheme()`. This file defines that function
-- as a global. It mirrors basecamp/omarchy-nvim's User-LazyReload
-- autocmd: re-dofile the active theme spec, unload its previous
-- module from package.loaded, clear highlights, load the new
-- colorscheme via lazy.core.loader, apply it, then re-source
-- transparency.lua so see-through panes survive the swap.

return {
  {
    name = "nirimaki-theme-hotreload",
    dir = vim.fn.stdpath("config"),
    lazy = false,
    priority = 1000,
    config = function()
      local transparency_file = vim.fn.stdpath("config") .. "/plugin/after/transparency.lua"

      _G.NirimakiReloadTheme = function()
        -- Force `plugins.theme` to be re-evaluated against the new
        -- ~/.config/theme/current/neovim.lua.
        package.loaded["plugins.theme"] = nil

        vim.schedule(function()
          local ok, theme_spec = pcall(require, "plugins.theme")
          if not ok or type(theme_spec) ~= "table" then
            return
          end

          -- Find the previous theme's plugin so we can unload its
          -- lua modules and force a fresh setup() on next load.
          local prev_plugin_name = nil
          for _, spec in ipairs(theme_spec) do
            if spec[1] and spec[1] ~= "LazyVim/LazyVim" then
              prev_plugin_name = spec.name or spec[1]
              break
            end
          end

          -- Wipe highlights so leftover groups from the old scheme
          -- don't bleed into the new one.
          vim.cmd("highlight clear")
          if vim.fn.exists("syntax_on") == 1 then
            vim.cmd("syntax reset")
          end

          -- Reset bg to dark; light schemes will flip it themselves.
          vim.o.background = "dark"

          if prev_plugin_name then
            local plugin = require("lazy.core.config").plugins[prev_plugin_name]
            if plugin and plugin.dir then
              local plugin_dir = plugin.dir .. "/lua"
              require("lazy.core.util").walkmods(plugin_dir, function(modname)
                package.loaded[modname] = nil
                package.preload[modname] = nil
              end)
            end
          end

          -- Find target colorscheme in the freshly-loaded spec and apply.
          for _, spec in ipairs(theme_spec) do
            if spec[1] == "LazyVim/LazyVim" and spec.opts and spec.opts.colorscheme then
              local colorscheme = spec.opts.colorscheme

              require("lazy.core.loader").colorscheme(colorscheme)

              vim.defer_fn(function()
                pcall(vim.cmd.colorscheme, colorscheme)
                vim.cmd("redraw!")

                if vim.fn.filereadable(transparency_file) == 1 then
                  vim.defer_fn(function()
                    vim.cmd.source(transparency_file)
                    vim.api.nvim_exec_autocmds("ColorScheme", { modeline = false })
                    vim.api.nvim_exec_autocmds("VimEnter", { modeline = false })
                    vim.cmd("redraw!")
                  end, 5)
                end
              end, 5)

              break
            end
          end
        end)
      end
    end,
  },
}
