import QtQuick
import qs.Commons

// The Android head mark, drawn with shapes rather than pulled from a Nerd
// Font glyph. At bar sizes a font glyph depends on whichever Nerd Font the
// theme resolved to, and renders at whatever weight that font chose; drawing
// it keeps the icon identical across themes and lets it take the bar's
// colour directly.
Item {
  id: root

  property real iconSize: Style.font.icon
  property color color: Color.foreground

  width: iconSize
  height: iconSize
  implicitWidth: iconSize
  implicitHeight: iconSize

  readonly property real domeWidth: width * 0.78
  readonly property real domeHeight: height * 0.5
  readonly property real domeY: height * 0.3

  // Antennae: thin rotated bars anchored above the dome.
  Rectangle {
    width: root.width * 0.07
    height: root.height * 0.22
    radius: width / 2
    color: root.color
    x: root.width * 0.28 - width / 2
    y: root.domeY - height * 0.78
    rotation: -28
    antialiasing: true
  }
  Rectangle {
    width: root.width * 0.07
    height: root.height * 0.22
    radius: width / 2
    color: root.color
    x: root.width * 0.72 - width / 2
    y: root.domeY - height * 0.78
    rotation: 28
    antialiasing: true
  }

  // Dome: a fully-rounded rect with its bottom corners flattened by an
  // unrounded rect overlapping the lower slice -- the same trick used for
  // the cylinder discs in DBForge's icon, just inverted.
  Rectangle {
    id: dome
    width: root.domeWidth
    height: root.domeHeight
    radius: width / 2
    color: root.color
    x: (root.width - width) / 2
    y: root.domeY
    antialiasing: true
  }
  Rectangle {
    width: root.domeWidth
    height: root.domeHeight * 0.32
    color: root.color
    x: (root.width - width) / 2
    y: root.domeY + root.domeHeight - height
    antialiasing: true
  }

}
