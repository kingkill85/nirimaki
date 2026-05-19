pragma Singleton
import QtQuick
import Quickshell.Io

// Single shared `checkupdates` poller. Each Bar instance reads count
// from this singleton instead of running its own Process — three
// simultaneous `checkupdates` calls would race on the pacman-contrib
// shared lock file and only one would return a real count, leaving the
// per-monitor Updates widget visible on only one screen.
QtObject {
    id: root

    property int count: 0
    readonly property bool any: count > 0

    function refresh() {
        if (!_proc.running) _proc.running = true;
    }

    property Timer _timer: Timer {
        // 30 min cadence. Inotify on /var/log/pacman.log below handles the
        // immediate "I just installed updates" case, so this only catches
        // newly-available updates from the mirrors.
        interval: 30 * 60 * 1000
        running: true
        repeat: true
        triggeredOnStart: true
        onTriggered: root.refresh()
    }

    // Inotify-driven refresh. Any pacman transaction appends to this log,
    // so a write means "the set of pending updates may have changed" —
    // works for both interactive `paru -Syu` from the widget click and
    // external `pacman -Syu` invocations.
    property FileView _pacmanLog: FileView {
        path: "/var/log/pacman.log"
        watchChanges: true
        printErrors: false
        onFileChanged: root.refresh()
    }

    property Process _proc: Process {
        id: updProc
        command: ["bash", "-c", "checkupdates 2>/dev/null | wc -l"]
        stdout: StdioCollector {
            id: updOut
            waitForEnd: true
            onStreamFinished: {
                const n = parseInt(String(updOut.text || "").trim(), 10);
                root.count = (isNaN(n) || n < 0) ? 0 : n;
            }
        }
    }
}
