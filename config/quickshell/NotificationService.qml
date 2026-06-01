pragma Singleton
import QtQuick
import Quickshell
import Quickshell.Services.Notifications

// Slim notification daemon. Just the popup list — no DND, no on-disk
// history, no image cache. Pattern adapted from Omarchy's Service.qml
// (which is much bigger; we can grow toward it later).
QtObject {
    id: root

    // popups: currently showing toasts. Each: { id, originalId, app, summary,
    // body, urgency, timestamp, ref }.
    property var popups: []

    readonly property int count: popups.length

    function durationFor(urgency) {
        // freedesktop notify-send default urgency is "normal"; theme
        // switch + most install/remove flows fall under normal. Bumped
        // from 3/5 → 6/10 so multi-line bodies are readable without
        // hover-to-pause. Hover still pauses the lifetime bar; click
        // still dismisses. Critical stays sticky.
        if (urgency === NotificationUrgency.Critical) return 0;
        if (urgency === NotificationUrgency.Low)      return 6000;
        return 10000;
    }

    function snapshot(n) {
        // Surface non-default actions to the toast as {identifier, text}.
        // The "default" action is the body-click handler (see activate())
        // so it never becomes a button.
        const acts = [];
        const src = n.actions || [];
        for (let i = 0; i < src.length; i++) {
            if (src[i].identifier === "default") continue;
            acts.push({ identifier: src[i].identifier, text: src[i].text || src[i].identifier });
        }
        return {
            id:         n.id,
            originalId: n.id,
            app:        n.appName  || "",
            appIcon:    n.appIcon  || "",
            summary:    n.summary  || "",
            body:       n.body     || "",
            urgency:    n.urgency,
            actions:    acts,
            timestamp:  Date.now(),
            ref:        n
        };
    }

    function dismiss(idx) {
        if (idx < 0 || idx >= popups.length) return;
        const item = popups[idx];
        if (item && item.ref) {
            try { if (item.ref.tracked) item.ref.dismiss(); } catch (e) {}
        }
        const next = popups.slice();
        next.splice(idx, 1);
        popups = next;
    }

    function dismissAll() {
        while (popups.length > 0) dismiss(0);
    }

    // Fire the notification's "default" action (freedesktop convention:
    // the action invoked when the body is clicked) then dismiss. Lets a
    // click on a chat toast open the right conversation instead of just
    // clearing it. No-op for notifications that ship no default action.
    function activate(idx) {
        if (idx < 0 || idx >= popups.length) return;
        const item = popups[idx];
        if (item && item.ref) {
            try {
                if (item.ref.tracked) {
                    const acts = item.ref.actions || [];
                    for (let i = 0; i < acts.length; i++) {
                        if (acts[i].identifier === "default") { acts[i].invoke(); break; }
                    }
                }
            } catch (e) {}
        }
        dismiss(idx);
    }

    // Invoke a named (non-default) action button, then dismiss.
    function invokeAction(idx, identifier) {
        if (idx < 0 || idx >= popups.length) return;
        const item = popups[idx];
        if (item && item.ref) {
            try {
                if (item.ref.tracked) {
                    const acts = item.ref.actions || [];
                    for (let i = 0; i < acts.length; i++) {
                        if (acts[i].identifier === identifier) { acts[i].invoke(); break; }
                    }
                }
            } catch (e) {}
        }
        dismiss(idx);
    }

    property NotificationServer _server: NotificationServer {
        keepOnReload:           false
        imageSupported:         false
        // Chromium's NotificationPlatformBridgeLinux refuses to use the
        // freedesktop daemon unless GetCapabilities advertises BOTH "body"
        // and "actions" — otherwise it falls back to its own in-window
        // message center (MISSING_REQUIRED_CAPABILITIES). Every webapp runs
        // in Chromium, so this must stay true for their notifications to
        // reach this toast at all.
        actionsSupported:       true
        bodyMarkupSupported:    true
        bodyHyperlinksSupported: false
        persistenceSupported:   true

        onNotification: (n) => {
            // Without `tracked = true` the Notification object is destroyed
            // as soon as this signal handler returns.
            n.tracked = true;
            const snap = root.snapshot(n);
            // Replace any existing toast with the same originalId so chat
            // apps that reuse replaces_id update in place.
            const existing = root.popups.filter(p => p.originalId !== snap.originalId);
            root.popups = [snap].concat(existing);
        }
    }
}
