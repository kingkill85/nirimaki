pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Io

// Shared poller that produces a total update count broken down across
// three sources:
//   - pacman: official Arch repos via `checkupdates`
//   - AUR:    `paru -Qua` (no-op when paru isn't installed)
//   - nirimaki: commits ahead on origin/<branch> for this clone
//
// Single Process per source so we don't fan out parallel queries on
// multi-monitor setups (the shared pacman-contrib lock would serialise
// duplicates anyway and the bar would flicker as each finishes).
QtObject {
    id: root

    // ---- Per-source counts ----
    property int pacmanCount: 0
    property int aurCount: 0
    property int nirimakiCount: 0

    // ---- Totals consumed by the bar widget ----
    readonly property int count: pacmanCount + aurCount + nirimakiCount
    readonly property bool any: count > 0

    // ---- Refresh API ----
    function refreshLocal() {
        if (!_pacmanProc.running) _pacmanProc.running = true;
        if (!_aurProc.running)    _aurProc.running    = true;
    }
    function refreshRemote() {
        if (!_nirimakiProc.running) _nirimakiProc.running = true;
    }
    // Kept for compatibility with callers that don't distinguish.
    function refresh() {
        refreshLocal();
        refreshRemote();
    }

    // ---- Timers ----
    // Local (pacman + AUR): 30 min cadence. Inotify on pacman.log below
    // handles the immediate "I just installed updates" case so this
    // only catches newly-available updates from the mirrors.
    property Timer _localTimer: Timer {
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshLocal()
    }
    // Remote (Nirimaki repo): 1 h cadence. `git fetch` is a network
    // call and the repo doesn't update more than a few times a day —
    // longer interval keeps the noise low without hiding pushes for
    // any meaningful time.
    property Timer _remoteTimer: Timer {
        interval: 60 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refreshRemote()
    }

    // ---- Inotify on pacman.log ----
    // Any local pacman transaction appends to this log, so a write
    // means "the set of pending updates may have changed". Drives the
    // local sources only — remote count is unaffected by local pacman.
    property FileView _pacmanLog: FileView {
        path: "/var/log/pacman.log"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refreshLocal()
    }

    // ---- Processes ----
    property Process _pacmanProc: Process {
        command: ["bash", "-c", "checkupdates 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            id: pacmanOut
            waitForEnd: true
            onStreamFinished: {
                const n = parseInt(String(pacmanOut.text || "").trim(), 10);
                root.pacmanCount = (isNaN(n) || n < 0) ? 0 : n;
            }
        }
    }

    property Process _aurProc: Process {
        // `paru -Qua | wc -l` — wc always emits exactly one number,
        // even when paru isn't installed (empty pipe → 0). Cleaner
        // than `grep -c .` which exits non-zero on no matches and
        // would need an `|| echo 0` fallback.
        command: ["bash", "-c", "paru -Qua 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            id: aurOut
            waitForEnd: true
            onStreamFinished: {
                const n = parseInt(String(aurOut.text || "").trim(), 10);
                root.aurCount = (isNaN(n) || n < 0) ? 0 : n;
            }
        }
    }

    property Process _nirimakiProc: Process {
        command: ["bash", "-c", Quickshell.env("HOME") + "/.local/bin/nirimaki-update-available"]
        stdout: StdioCollector {
            id: nirimakiOut
            waitForEnd: true
            onStreamFinished: {
                const n = parseInt(String(nirimakiOut.text || "").trim(), 10);
                root.nirimakiCount = (isNaN(n) || n < 0) ? 0 : n;
            }
        }
    }
}
