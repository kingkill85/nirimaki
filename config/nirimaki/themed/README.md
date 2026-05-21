# Per-user theme template overrides

Drop a file here matching a shipped template name (without
`.sample`) and `nirimaki-theme-set` will use your version instead of
the one in `config/theme/templates/`. Same `{{ key }}` substitution
applies.

Examples:

```
~/.config/nirimaki/themed/foot.ini.tpl       overrides config/theme/templates/foot.ini.tpl
~/.config/nirimaki/themed/starship.toml.tpl  overrides config/theme/templates/starship.toml.tpl
~/.config/nirimaki/themed/lazygit.yml.tpl    overrides config/theme/templates/lazygit.yml.tpl
```

When you switch themes, `nirimaki-theme-set` checks this dir before
falling back to the repo template. Your overrides survive `git pull`.

If you want to add a *new* template (not an override), drop it here
under any name — it's rendered into `~/.config/theme/current/<base>`
the same way as the built-in templates.
