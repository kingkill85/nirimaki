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

    // history: notifications that have left the toast stack (auto-expired,
    // clicked away, or dismissed) but are kept for later review in the
    // notification center. Newest first, capped at `historyLimit`. These
    // are plain records — the live `ref` is dropped, so actions can't be
    // re-invoked from history (it's read-only).
    property var history: []
    readonly property int historyLimit: 50

    readonly property int count: popups.length
    readonly property int historyCount: history.length

    function durationFor(urgency, expireTimeout) {
        // freedesktop notify-send default urgency is "normal"; theme
        // switch + most install/remove flows fall under normal. Bumped
        // from 3/5 → 6/10 so multi-line bodies are readable without
        // hover-to-pause. Hover still pauses the lifetime bar; click
        // still dismisses.
        //
        // Honor a client-requested timeout when one is supplied
        // (Quickshell exposes expireTimeout in seconds, -1 when unset).
        // Critical is NOT sticky-forever: Chromium maps every Teams /
        // chat webapp message (requireInteraction) onto urgency=critical,
        // so an infinite lifetime there means the toast stack only ever
        // grows until hand-dismissed. Give critical a long-but-finite
        // window instead so genuine alerts still linger noticeably.
        if (expireTimeout !== undefined && expireTimeout > 0)
            return expireTimeout * 1000;
        if (urgency === NotificationUrgency.Critical) return 20000;
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
            expireTimeout: n.expireTimeout,
            // Transient notifications (freedesktop hint) are explicitly
            // "do not persist" — they leave no trace in the center.
            transient:  n.transient || false,
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
        if (item) root._archive(item);
        const next = popups.slice();
        next.splice(idx, 1);
        popups = next;
    }

    function dismissAll() {
        while (popups.length > 0) dismiss(0);
    }

    // Move a toast snapshot into the history list. Drops the live ref
    // (history is read-only), skips transient notifications, and dedups
    // by replaces-id so an app that updates a toast in place leaves one
    // entry rather than a trail.
    function _archive(item) {
        if (!item || item.transient) return;
        const rec = {
            id:        item.originalId,
            app:       item.app,
            appIcon:   item.appIcon,
            summary:   item.summary,
            body:      item.body,
            urgency:   item.urgency,
            timestamp: item.timestamp
        };
        const pruned = history.filter(h => h.id !== item.originalId);
        const next = [rec].concat(pruned);
        if (next.length > historyLimit) next.length = historyLimit;
        history = next;
    }

    function removeFromHistory(idx) {
        if (idx < 0 || idx >= history.length) return;
        const next = history.slice();
        next.splice(idx, 1);
        history = next;
    }

    function clearHistory() { history = []; }

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
