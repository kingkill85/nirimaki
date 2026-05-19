import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Wayland

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

    Item {
        anchors.fill: parent

        // Left section
        Row {
            id: leftRow
            anchors.left: parent.left
            anchors.verticalCenter: parent.verticalCenter
            spacing: Theme.gap

            Workspaces {
                id: workspaces
                outputName: bar.modelData.name
            }

            ActiveWindow {
                id: activeWindow
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Center section, ordered like Omarchy waybar's modules-center:
        // clock → weather → update.
        Row {
            anchors.centerIn: parent
            spacing: Theme.gap

            Calendar {
                anchors.verticalCenter: parent.verticalCenter
                barWindow: bar
            }

            Weather {
                anchors.verticalCenter: parent.verticalCenter
                barWindow: bar
            }

            Updates {
                anchors.verticalCenter: parent.verticalCenter
            }

            Voxtype {
                anchors.verticalCenter: parent.verticalCenter
            }
        }

        // Right section
        Row {
            id: rightRow
            anchors.right: parent.right
            anchors.verticalCenter: parent.verticalCenter
            anchors.rightMargin: Theme.padX
            spacing: Theme.gap

            Media {
                anchors.verticalCenter: parent.verticalCenter
                barWindow: bar
            }

            ScreenRecord {
                anchors.verticalCenter: parent.verticalCenter
            }

            Tray {
                anchors.verticalCenter: parent.verticalCenter
                barWindow: bar
            }

            Notifications {
                anchors.verticalCenter: parent.verticalCenter
            }

            Bluetooth {
                anchors.verticalCenter: parent.verticalCenter
                barWindow: bar
            }

            Network {
                anchors.verticalCenter: parent.verticalCenter
                barWindow: bar
            }

            SystemStats {
                anchors.verticalCenter: parent.verticalCenter
                barWindow: bar
            }

            Audio {
                anchors.verticalCenter: parent.verticalCenter
            }
        }
    }
}
