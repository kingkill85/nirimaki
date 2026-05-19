pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Translation singleton. Loads two JSON dictionaries from
// ~/.config/quickshell/i18n/:
//   - <locale>.json  — translations for the active locale.
//   - en.json        — canonical English keys, used as fallback.
//
// Use:   Text { text: I18n.t("launcher.placeholder") }
//        Text { text: I18n.t("emoji.empty", filterText) }
//
// `{0}` placeholders in the value are replaced with the second arg.
QtObject {
    id: root

    // Resolved short locale ("de" / "en" / "fr"). Resolution order:
    //   1. ~/.config/quickshell/locale  (user-picked, set by the
    //      LanguagePicker overlay)
    //   2. LC_MESSAGES env
    //   3. LANG env
    //   4. Qt.locale().name
    // Long form ("de_DE.UTF-8") is normalised to the two-letter
    // language code because that's the granularity our dictionary
    // keys at.
    function _normalise(raw) {
        const s = String(raw || "").trim();
        if (!s || s === "C" || s === "POSIX") return "";
        const m = s.match(/^([a-zA-Z]{2,3})/);
        return m ? m[1].toLowerCase() : "";
    }

    function _resolveLocale() {
        // _localePref.text() may not be loaded yet at construction
        // time; the FileView's onLoaded re-runs this resolution and
        // assigns `locale`.
        const pref = _normalise(_localePref ? _localePref.text() : "");
        if (pref) return pref;
        const env = _normalise(Quickshell.env("LC_MESSAGES"))
                 || _normalise(Quickshell.env("LANG"))
                 || _normalise(Qt.locale().name);
        return env || "en";
    }

    property string locale: _resolveLocale()
    // True if `~/.config/quickshell/locale` was loaded; false means
    // the active locale came from $LANG / $LC_MESSAGES (the system
    // default). LanguagePicker uses this to highlight either the
    // "System default" entry or the user-picked one.
    property bool hasOverride: false
    property var dict: ({})
    property var fallbackDict: ({})

    function _parse(raw) {
        try {
            return JSON.parse(String(raw || "{}"));
        } catch (e) {
            // Don't blow up the shell if a translator typoed a comma;
            // fall back to empty map → `t()` returns the key.
            return {};
        }
    }

    // Looks up `key` in the active-locale dict, then in the English
    // fallback, then returns the key itself so an untranslated string
    // at least shows what it was (and is greppable). `{0}` placeholder
    // is replaced with the second argument when present.
    function t(key, arg) {
        let v = dict[key];
        if (typeof v !== "string") v = fallbackDict[key];
        if (typeof v !== "string") v = key;
        if (arg !== undefined) v = v.split("{0}").join(String(arg));
        return v;
    }

    function reload() {
        _localeFile.reload();
        _fallbackFile.reload();
    }

    property IpcHandler _ipc: IpcHandler {
        target: "i18n"
        function ping(): string  { return "ok" }
        // Quick debug helper. `quickshell ipc call -- i18n locale`
        // tells us what locale the singleton actually picked at
        // startup — useful when a string suspiciously renders in the
        // wrong language.
        function locale(): string { return root.locale }
        function reload(): string { root.reload(); return "ok" }
    }

    // User-picked locale override. One line containing a 2-letter
    // code; written by LanguagePicker. Missing file = use env.
    property FileView _localePref: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/locale"
        watchChanges: true
        printErrors: false
        onLoaded:      { root.hasOverride = true;  root.locale = root._resolveLocale(); }
        onFileChanged: reload()
        onLoadFailed:  { root.hasOverride = false; root.locale = root._resolveLocale(); }
    }

    property FileView _localeFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/i18n/"
              + root.locale + ".json"
        watchChanges: true
        printErrors: false
        onLoaded:     root.dict = root._parse(text())
        onFileChanged: reload()
        onLoadFailed:  root.dict = ({})
    }

    property FileView _fallbackFile: FileView {
        path: Quickshell.env("HOME") + "/.config/quickshell/i18n/en.json"
        watchChanges: true
        printErrors: false
        onLoaded:     root.fallbackDict = root._parse(text())
        onFileChanged: reload()
        onLoadFailed:  root.fallbackDict = ({})
    }
}
