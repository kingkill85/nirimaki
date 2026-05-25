import QtQuick

// Thin horizontal rule used between sections of a BarPopover. Same
// fgDim @ 0.25 across every popover so they all read as one family.
Rectangle {
    width: parent ? parent.width : 0
    height: 1
    color: Theme.fgDim
    opacity: 0.25
}
