import QtQuick
import qs

// VPN bar widget. Aggregates NM-managed VPN/WireGuard profiles
// (auto-listed via VpnService) and custom providers declared in
// ~/.config/nirimaki/vpns.d/<id>.json.
//
// Pill renders the shield icon plus the names of every currently-
// connected provider, comma-separated. Left-click toggles a popover
// listing every known provider with connect / disconnect and an
// optional "configure" link that launches the provider's own setup
// UI (`nm-connection-editor` for NM, the custom `setupCmd` for
// declared providers).
Item {
    id: root

    property var barWindow: null

    readonly property var active:    VpnService.activeProviders
    readonly property bool anyOn:    active.length > 0

    // Hide the pill completely when nothing is configured AND no
    // VPN package is installed. Boxes that don't use a VPN never see
    // a stray shield icon on their bar; boxes that have installed a
    // package but haven't added a connection still see the pill so
    // they have a way to drive the panel.
    //
    // The Bar's pluginLoader watches the loaded item's `implicitWidth`
    // and collapses the slot when it hits zero, so we need to zero
    // BOTH visible *and* implicitWidth here (same pattern as
    // voxtype / screen-record / notifications).
    readonly property bool hasAny:
        VpnService.providers.length > 0
        || VpnService.addableProviders.length > 0
    visible: hasAny

    implicitHeight: hasAny ? Theme.barHeight    : 0
    implicitWidth:  hasAny ? pill.implicitWidth : 0

    // Names of every active connection — used by the tooltip only.
    // For single-active we include the statusLabel ("PIA · Frankfurt")
    // so a glance gives you the region / hostname / etc.
    readonly property string activeSummary: {
        if (active.length === 0) return "";
        if (active.length === 1) {
            const p = active[0];
            return p.statusLabel && p.statusLabel !== I18n.t("vpn.state.connected")
                 ? p.name + " · " + p.statusLabel
                 : p.name;
        }
        return active.map(p => p.name).join(", ");
    }

    readonly property string icon:  anyOn ? "󰦝" : "󰦞"   // shield-check / shield-outline
    // Neutral fg when active, fgDim when off — matches audio/network/bluetooth.
    // Connected state still reads from the glyph (check vs outline).
    readonly property color  color: anyOn ? Theme.fg : Theme.fgDim

    BarPill {
        id: pill
        active: popover.popupOpen
        // Icon-only pill, matching audio/bluetooth/network. The
        // tooltip carries the "what's connected" detail; hover (or
        // tap) to see, e.g., "VPN — Tailscale · nirimaki".
        tooltipText: root.anyOn
            ? I18n.t("vpn.tooltip_on_with").replace("{0}", root.activeSummary)
            : I18n.t("vpn.tooltip_off")
        onClicked: popover.toggle()

        Text {
            anchors.verticalCenter: parent.verticalCenter
            text: root.icon
            color: root.color
            font.family: Theme.iconFamily
            font.pixelSize: Theme.iconPx
        }
    }

    BarPopover {
        id: popover
        barWindow:  root.barWindow
        anchorItem: pill

        // Re-poll on popover open so the list is fresh — user opens
        // it expecting to see the current state, not what was true
        // five seconds ago.
        onPopupOpenChanged: if (popupOpen) VpnService.refresh()

        implicitWidth:  340
        implicitHeight: card.implicitHeight + 2 * contentMargin

        Column {
            id: card
            anchors.fill: parent
            spacing: Theme.popoverSpacing

            PopoverHeader {
                icon:      root.icon
                iconColor: root.color
                title:     I18n.t("vpn.popover.title")
                subtitle:  root.anyOn
                              ? I18n.t("vpn.popover.subtitle_on")
                                    .replace("{0}", String(root.active.length))
                              : I18n.t("vpn.popover.subtitle_off")
            }

            PopoverDivider { visible: VpnService.providers.length > 0 }

            // No-providers empty state. Shown when nmcli reports no
            // VPN profiles and vpns.d is empty — clearest hint for
            // a fresh install.
            Text {
                visible: VpnService.providers.length === 0
                width: parent.width
                wrapMode: Text.WordWrap
                text: I18n.t("vpn.popover.empty")
                color: Theme.fgDim
                font.family: Theme.sansFamily
                font.pixelSize: Theme.fontPxSmall
            }

            // One row per provider, NM entries first, custom after.
            Repeater {
                model: VpnService.providers
                delegate: Item {
                    required property var modelData
                    readonly property var p: modelData
                    width: parent.width
                    height: 44

                    Row {
                        anchors.fill: parent
                        spacing: 10

                        // Icon.
                        Text {
                            anchors.verticalCenter: parent.verticalCenter
                            width: 24
                            horizontalAlignment: Text.AlignHCenter
                            text: p.icon
                            color: p.connected ? Theme.accent : Theme.fgDim
                            font.family: Theme.iconFamily
                            font.pixelSize: Theme.iconPx
                        }

                        // Name + status. Two stacked labels.
                        Column {
                            anchors.verticalCenter: parent.verticalCenter
                            width: parent.width - 24 - 10
                                 - (connectBtn.visible    ? connectBtn.width + 6    : 0)
                                 - (disconnectBtn.visible ? disconnectBtn.width + 6 : 0)
                                 - (setupBtn.visible      ? setupBtn.width + 6      : 0)
                            spacing: 1
                            Text {
                                text: p.name
                                color: Theme.fg
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPx
                                elide: Text.ElideRight
                                width: parent.width
                            }
                            Text {
                                text: p.statusLabel
                                color: p.connected ? Theme.accent : Theme.fgDim
                                font.family: Theme.sansFamily
                                font.pixelSize: Theme.fontPxSmall
                                elide: Text.ElideRight
                                width: parent.width
                            }
                        }

                        // Disconnect (only when connected).
                        Button {
                            id: disconnectBtn
                            anchors.verticalCenter: parent.verticalCenter
                            visible: p.connected
                            label: I18n.t("vpn.row.disconnect")
                            variant: Button.Urgent
                            onTriggered: VpnService.disconnect(p.id)
                        }
                        // Connect (only when disconnected).
                        Button {
                            id: connectBtn
                            anchors.verticalCenter: parent.verticalCenter
                            visible: !p.connected
                            label: I18n.t("vpn.row.connect")
                            variant: Button.Primary
                            onTriggered: VpnService.connect(p.id)
                        }
                        // Configure — opens the provider's own UI
                        // (nm-connection-editor for NM, custom
                        // setupCmd for declared providers).
                        Button {
                            id: setupBtn
                            anchors.verticalCenter: parent.verticalCenter
                            visible: p.canSetup
                            label: "⚙"
                            variant: Button.Secondary
                            onTriggered: { popover.close(); VpnService.setup(p.id); }
                        }
                    }
                }
            }

            PopoverDivider { }

            // Footer — "Manage VPNs…" deep-links to the network panel's
            // VPN tab where the install / activate / configure UX lives.
            PopoverActions {
                width: parent.width

                PopoverButton {
                    label: I18n.t("vpn.popover.manage")
                    variant: PopoverButton.Secondary
                    onTriggered: {
                        popover.close();
                        Plugins.summon("network", { focus: "vpn" });
                    }
                }
            }
        }
    }
}
