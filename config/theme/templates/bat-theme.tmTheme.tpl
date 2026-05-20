<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<!--
  Nirimaki bat theme — rendered by qs-theme-set from the active
  theme's colors.toml. Activated via BAT_THEME=nirimaki (set in
  conf.d/tools.fish and .bashrc).
-->
<dict>
  <key>name</key>
  <string>Nirimaki</string>
  <key>settings</key>
  <array>

    <!-- Global colours -->
    <dict>
      <key>settings</key>
      <dict>
        <key>background</key><string>{{ background }}</string>
        <key>foreground</key><string>{{ foreground }}</string>
        <key>caret</key><string>{{ cursor }}</string>
        <key>lineHighlight</key><string>{{ selection_background }}</string>
        <key>selection</key><string>{{ selection_background }}</string>
        <key>selectionForeground</key><string>{{ selection_foreground }}</string>
        <key>gutter</key><string>{{ background }}</string>
        <key>gutterForeground</key><string>{{ color8 }}</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Comment</string>
      <key>scope</key><string>comment</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color8 }}</string>
        <key>fontStyle</key><string>italic</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>String</string>
      <key>scope</key><string>string</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color3 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Regex</string>
      <key>scope</key><string>string.regexp</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color6 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Number</string>
      <key>scope</key><string>constant.numeric</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color1 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Constant</string>
      <key>scope</key><string>constant.language, constant.character, constant.other</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color1 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Keyword</string>
      <key>scope</key><string>keyword, keyword.control, keyword.operator</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color5 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Storage</string>
      <key>scope</key><string>storage</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color5 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Storage type</string>
      <key>scope</key><string>storage.type</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color4 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Function</string>
      <key>scope</key><string>entity.name.function</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color2 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Class / type</string>
      <key>scope</key><string>entity.name.class, entity.name.type, entity.name.namespace</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color4 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Tag</string>
      <key>scope</key><string>entity.name.tag</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color1 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Attribute</string>
      <key>scope</key><string>entity.other.attribute-name</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color3 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Inherited class</string>
      <key>scope</key><string>entity.other.inherited-class</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color4 }}</string>
        <key>fontStyle</key><string>italic</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Support function</string>
      <key>scope</key><string>support.function</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color6 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Support type / class</string>
      <key>scope</key><string>support.type, support.class</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color4 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Variable parameter</string>
      <key>scope</key><string>variable.parameter</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color3 }}</string>
        <key>fontStyle</key><string>italic</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Variable language</string>
      <key>scope</key><string>variable.language</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color1 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Invalid</string>
      <key>scope</key><string>invalid</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ background }}</string>
        <key>background</key><string>{{ color1 }}</string>
      </dict>
    </dict>

    <!-- Markdown / markup -->
    <dict>
      <key>name</key><string>Heading</string>
      <key>scope</key><string>markup.heading</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color4 }}</string>
        <key>fontStyle</key><string>bold</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Bold</string>
      <key>scope</key><string>markup.bold</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color1 }}</string>
        <key>fontStyle</key><string>bold</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Italic</string>
      <key>scope</key><string>markup.italic</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color3 }}</string>
        <key>fontStyle</key><string>italic</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Link</string>
      <key>scope</key><string>markup.underline.link</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color6 }}</string>
        <key>fontStyle</key><string>underline</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Quote</string>
      <key>scope</key><string>markup.quote</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color8 }}</string>
        <key>fontStyle</key><string>italic</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Raw / code</string>
      <key>scope</key><string>markup.raw</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color2 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>List item</string>
      <key>scope</key><string>markup.list</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color6 }}</string></dict>
    </dict>

    <!-- Diff -->
    <dict>
      <key>name</key><string>Deleted</string>
      <key>scope</key><string>markup.deleted</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color1 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Inserted</string>
      <key>scope</key><string>markup.inserted</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color2 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Changed</string>
      <key>scope</key><string>markup.changed</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color3 }}</string></dict>
    </dict>

    <dict>
      <key>name</key><string>Diff header</string>
      <key>scope</key><string>meta.diff.header</string>
      <key>settings</key>
      <dict>
        <key>foreground</key><string>{{ color4 }}</string>
        <key>fontStyle</key><string>bold</string>
      </dict>
    </dict>

    <dict>
      <key>name</key><string>Diff range</string>
      <key>scope</key><string>meta.diff.range</string>
      <key>settings</key>
      <dict><key>foreground</key><string>{{ color5 }}</string></dict>
    </dict>

  </array>
</dict>
</plist>
