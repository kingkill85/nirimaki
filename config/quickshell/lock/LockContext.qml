import QtQuick
import Quickshell
import Quickshell.Services.Pam

// Shared state for the LockSurface instances (one per screen). Holds
// the typed password buffer, drives the PamContext, broadcasts result.
Scope {
    id: root
    signal unlocked()
    signal failed()

    property string currentText: ""
    property bool   unlockInProgress: false
    property bool   showFailure: false

    onCurrentTextChanged: showFailure = false

    function tryUnlock() {
        if (currentText === "") return;
        root.unlockInProgress = true;
        pam.start();
    }

    PamContext {
        id: pam
        // Reuse the system's "login" PAM service — the exact same stack
        // gtklock/login/sddm authenticate against. Our previous attempt
        // (configDirectory: "pam", config: "password.conf") used a
        // RELATIVE path which PAM resolves from quickshell's CWD
        // (= $HOME when spawned by niri), so our custom config was
        // never loaded. Using the system service avoids that entirely.
        config: "login"

        onPamMessage: {
            if (pam.responseRequired) pam.respond(root.currentText);
        }

        onCompleted: result => {
            if (result == PamResult.Success) {
                root.unlocked();
            } else {
                root.currentText = "";
                root.showFailure = true;
            }
            root.unlockInProgress = false;
        }
    }
}
