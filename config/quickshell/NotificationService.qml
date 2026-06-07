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

    // history: notifications parked in the center after their toast timed
    // out untouched. Newest first, capped at `historyLimit`. Unlike a plain
    // log, each record keeps its live `ref` and the notification is left
    // OPEN on the server — so its "default" action (the click-to-open-the-
    // conversation handler that Chromium routes to the webapp's service
    // worker) can still be fired later from the center. Notifications are
    // only closed on explicit discard / clear / activation.
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
        // Surface real actions to the toast as {identifier, text}, dropping
        // the two pseudo-actions Chromium injects into every webapp
        // notification:
        //   - "default"  → the body-click handler (see activate()), never a button.
        //   - "settings" → Chromium's "manage this site's notifications" entry.
        //                  Invoking it just tries to open Chromium's settings
        //                  page, which goes nowhere from an app-mode webapp
        //                  window — so it renders as a dead button (the Teams
        //                  "Einstellung" button). Drop it rather than show it.
        const acts = [];
        const src = n.actions || [];
        for (let i = 0; i < src.length; i++) {
            const id = src[i].identifier;
            if (id === "default" || id === "settings") continue;
            acts.push({ identifier: id, text: src[i].text || id });
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

    // --- ref helpers -----------------------------------------------------

    function _action(ref, id) {
        try {
            if (ref && ref.tracked) {
                const acts = ref.actions || [];
                for (let i = 0; i < acts.length; i++)
                    if (acts[i].identifier === id) return acts[i];
            }
        } catch (e) {}
        return null;
    }

    function _invoke(ref, id) {
        const a = _action(ref, id);
        if (a) { try { a.invoke(); return true; } catch (e) {} }
        return false;
    }

    // Close the notification on the server (sends NotificationClosed, which
    // Chromium turns into the webapp's `notificationclose` event).
    function _close(ref) {
        try { if (ref && ref.tracked) ref.dismiss(); } catch (e) {}
    }

    function _removePopup(idx) {
        const next = popups.slice();
        next.splice(idx, 1);
        popups = next;
    }

    // --- toast-stack actions ---------------------------------------------

    // Toast timed out untouched: keep the notification OPEN and stash it
    // (with its live ref) in the center so its default action stays firable.
    function park(idx) {
        if (idx < 0 || idx >= popups.length) return;
        const item = popups[idx];
        _removePopup(idx);
        root._toCenter(item);
    }

    // User explicitly discarded the toast (middle-click): close it for good,
    // don't park it.
    function dismiss(idx) {
        if (idx < 0 || idx >= popups.length) return;
        _close(popups[idx].ref);
        _removePopup(idx);
    }

    function dismissAll() {
        while (popups.length > 0) dismiss(0);
    }

    // Left-click on a live toast: fire the "default" action (jump to the
    // conversation), then close + drop it — a clicked notification is done.
    function activate(idx) {
        if (idx < 0 || idx >= popups.length) return;
        const ref = popups[idx].ref;
        _invoke(ref, "default");
        _close(ref);
        _removePopup(idx);
    }

    // Invoke a named (non-default) action button, then close + drop.
    function invokeAction(idx, identifier) {
        if (idx < 0 || idx >= popups.length) return;
        const ref = popups[idx].ref;
        _invoke(ref, identifier);
        _close(ref);
        _removePopup(idx);
    }

    // --- notification center ---------------------------------------------

    // Park a snapshot into the center, holding its live ref. Skips transient
    // notifications (closing them outright), and dedups by replaces-id so an
    // app that updated a toast in place leaves one entry — the superseded
    // ref is closed so Chromium doesn't keep a stale notification around.
    function _toCenter(item) {
        if (!item) return;
        if (item.transient) { _close(item.ref); return; }
        const rec = {
            id:         item.originalId,
            app:        item.app,
            appIcon:    item.appIcon,
            summary:    item.summary,
            body:       item.body,
            urgency:    item.urgency,
            timestamp:  item.timestamp,
            ref:        item.ref,
            // Clickable-to-jump only if the notification shipped a default
            // action (chat webapps do; `notify-send` theme toasts don't).
            actionable: _action(item.ref, "default") !== null
        };
        const keep = [];
        for (let i = 0; i < history.length; i++) {
            if (history[i].id === rec.id) _close(history[i].ref);
            else keep.push(history[i]);
        }
        const next = [rec].concat(keep);
        if (next.length > historyLimit) {
            for (let i = historyLimit; i < next.length; i++) _close(next[i].ref);
            next.length = historyLimit;
        }
        history = next;
    }

    // Click a center entry: fire its default action (jump to the Teams
    // conversation), close the notification, and drop the entry.
    function activateHistory(idx) {
        if (idx < 0 || idx >= history.length) return;
        const rec = history[idx];
        _invoke(rec.ref, "default");
        _close(rec.ref);
        const next = history.slice();
        next.splice(idx, 1);
        history = next;
    }

    function removeFromHistory(idx) {
        if (idx < 0 || idx >= history.length) return;
        const next = history.slice();
        const gone = next.splice(idx, 1)[0];
        if (gone) _close(gone.ref);
        history = next;
    }

    function clearHistory() {
        for (let i = 0; i < history.length; i++) _close(history[i].ref);
        history = [];
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
