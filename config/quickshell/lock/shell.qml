//@ pragma UseQApplication
import Quickshell
import Quickshell.Wayland

// Standalone Quickshell config used only for the lock screen. Launched
// on demand by niri: `quickshell -c lock`. Locks every screen via
// ext-session-lock-v1; PAM-auth via Quickshell.Services.Pam.
ShellRoot {
    LockContext {
        id: lockContext

        onUnlocked: {
            // Drop the lock before exiting — otherwise the compositor
            // keeps showing a fallback blank lock surface forever.
            lock.locked = false;
            Qt.quit();
        }
    }

    WlSessionLock {
        id: lock
        locked: true

        WlSessionLockSurface {
            LockSurface {
                anchors.fill: parent
                context: lockContext
            }
        }
    }
}
