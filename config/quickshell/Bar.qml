import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

// One per screen. The three Rows are pure plugin hosts now —
// no hardcoded widgets. Order within each section is the positional
// order in ~/.config/nirimaki/shell.json's `bar.layout.{left,center,right}`
// arrays; when shell.json is absent the loader falls back to deriving
// order from the per-plugin `mount`+`after`/`before` fields in
// plugin.json.
//
// setSource passes init props down so plugins can declare
// `property var barWindow` (for popover positioning),
// `property string outputName` (workspaces et al.), and
// `property var settings` (inline per-entry shell.json settings) —
// silently ignored by plugins that don't declare them.
PanelWindow {
    id: bar
    required property ShellScreen modelData
    screen: modelData

    anchors {
        top: true
        left: true
        right: true
    }
    implicitHeight: Theme.barHeight
    color: Theme.bg
    exclusionMode: ExclusionMode.Auto

    // Toggled by `quickshell ipc call shell toggleBar` (Mod+Shift+Space).
    // Hiding unmaps the layer surface, which releases the exclusive zone
    // so windows reflow over the freed strip — like Omarchy's waybar toggle.
    visible: Plugins.barVisible

    // Single template for every mount. setSource would reject unknown
    // properties — we use onLoaded with a feature-detect instead so
    // plugins only opt into the host context they actually need.
    // Plugins declare `property var barWindow` and/or `property string
    // outputName` when relevant.
    Component {
        id: pluginLoader

        Loader {
            required property var modelData
            anchors.verticalCenter: parent.verticalCenter
            source: Plugins.entryUrl(modelData)
            onLoaded: {
                if (!item) return;
                if ("barWindow"  in item) item.barWindow  = bar;
                if ("outputName" in item) item.outputName = bar.modelData.name;
                if ("settings"   in item) item.settings   = modelData.settings || ({});
            }
        }
    }

    Item {
        anchors.fill: parent

        Row {
            id: leftRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            Repeater {
                model: Plugins.byMount["bar.left"] || []
                delegate: pluginLoader
            }
        }

        Row {
            anchors.centerIn: parent
            spacing: Theme.gap

            Repeater {
                model: Plugins.byMount["bar.center"] || []
                delegate: pluginLoader
            }
        }

        Row {
            id: rightRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Theme.padX
            spacing: Theme.gap

            Repeater {
                model: Plugins.byMount["bar.right"] || []
                delegate: pluginLoader
            }
        }
    }
}
