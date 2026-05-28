# Nirimaki — default MIME applications.
#
# install.sh writes this to ~/.config/mimeapps.list with __BROWSER__
# replaced by the active default browser's .desktop name (from
# `xdg-settings get default-web-browser`).
#
# Why install.sh maintains this file: xdg-settings only populates
# the core scheme handlers. Real-world HTML opens also route through
# application/xhtml+xml, application/x-extension-*, and
# x-scheme-handler/{about,unknown,chrome} — without seeding those,
# a fresh box silently falls back to whatever .desktop matches first
# in /usr/share/applications/mimeinfo.cache, which is often wrong.
#
# Re-runnable: the user can switch default browser later
# (`nirimaki browser default …` or `xdg-settings set …`) and re-run
# install.sh's MIME step to re-template against the new browser.

[Default Applications]
x-scheme-handler/claude-cli=claude-code-url-handler.desktop
text/html=__BROWSER__
x-scheme-handler/http=__BROWSER__
x-scheme-handler/https=__BROWSER__
x-scheme-handler/about=__BROWSER__
x-scheme-handler/unknown=__BROWSER__
x-scheme-handler/chrome=__BROWSER__
application/xhtml+xml=__BROWSER__
application/x-extension-htm=__BROWSER__
application/x-extension-html=__BROWSER__
application/x-extension-shtml=__BROWSER__
application/x-extension-xhtml=__BROWSER__
application/x-extension-xht=__BROWSER__
video/mp4=mpv.desktop
video/x-matroska=mpv.desktop
video/webm=mpv.desktop
video/x-msvideo=mpv.desktop
video/quicktime=mpv.desktop
video/mpeg=mpv.desktop
video/x-flv=mpv.desktop
video/3gpp=mpv.desktop
video/ogg=mpv.desktop
video/x-ogm+ogg=mpv.desktop
