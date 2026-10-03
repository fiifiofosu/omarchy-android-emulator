import QtQuick
import QtQuick.Controls
import QtQuick.Layouts
import Quickshell
import Quickshell.Io
import qs.Commons
import qs.Ui
import "Model.js" as Model

// The bar widget and its panel in one component, per the Omarchy plugin
// guide's `bar-widget` contract: the manifest points at this file, and the
// panel is loaded from inside it rather than declared as a second plugin
// kind.
Panel {
  id: root
  moduleName: "io.github.fiifiofosu.android-emulator"
  ipcTarget: "io.github.fiifiofosu.android-emulator"
  manageIpc: false

  // One flat cursor over the panel: the optional "new AVD" row, then one row
  // per AVD, then the expanded profile list when open. Row count changes
  // shape as often as the AVD list does, so a single index is simpler to
  // keep in bounds than two synced ones.
  property int cursor: 0
  property bool cursorActive: false

  readonly property color foreground: bar ? bar.foreground : Color.foreground
  readonly property color urgent: bar ? bar.urgent : Color.urgent
  readonly property color dim: Qt.darker(foreground, 1.55)
  readonly property string fontFamily: bar ? bar.fontFamily : Style.font.family

  readonly property int profileRows: emu.profilesOpen ? emu.visibleProfiles.length : 0
  readonly property int rowCount: 1 + profileRows + emu.avds.length

  readonly property color barIconColor: emu.summary.running > 0 ? barForeground : Qt.darker(barForeground, 1.55)

  readonly property string tooltip: {
    if (emu.missingBinary) return "Android Emulator: emuctl not found"
    return "Android Emulator: " + Model.summaryText(emu.summary, false)
  }

  function clampCursor() {
    if (rowCount === 0) { cursor = 0; return }
    if (cursor < 0) cursor = 0
    if (cursor > rowCount - 1) cursor = rowCount - 1
  }

  function moveCursor(dx, dy) {
    cursorActive = true
    if (dy === 0) return
    cursor = cursor + dy
    clampCursor()
  }

  function setCursor(index) {
    cursorActive = true
    cursor = index
    clampCursor()
  }

  function activateCursor() {
    if (cursor === 0) { emu.toggleProfiles(); return }
    var i = cursor - 1
    if (i < profileRows) { emu.createFromProfile(emu.visibleProfiles[i].id); return }
    i -= profileRows
    if (i >= 0 && i < emu.avds.length) emu.toggleAvd(emu.avds[i])
  }

  implicitWidth: button.implicitWidth
  implicitHeight: button.implicitHeight

  onOpenedChanged: if (opened) {
    cursorActive = false
    cursor = 0
    emu.refresh()
    Qt.callLater(function() { keyCatcher.forceActiveFocus() })
  }

  Service {
    id: emu
    settings: root.settings
  }

  Connections {
    target: emu
    function onAvdsChanged() { root.clampCursor() }
  }

  IpcHandler {
    target: root.ipcTarget
    function open(): void { root.open() }
    function close(): void { root.close() }
    function show(): void { root.open() }
    function hide(): void { root.close() }
    function toggle(): void { root.toggle() }
    function refresh(): string { emu.refresh(); return "ok" }
    function status(): string { return Model.summaryText(emu.summary, false) }
  }

  BarIconButton {
    id: button
    anchors.fill: parent
    bar: root.bar
    slotSize: Style.bar.statusSlot
    tooltipText: root.tooltip
    active: emu.summary.running > 0
    iconComponent: Component {
      Item {
        AndroidIcon {
          anchors.centerIn: parent
          iconSize: Style.space(13)
          color: button.active ? button.activeColor : root.barIconColor
          opacity: emu.summary.running > 0 ? 1.0 : 0.6
        }
      }
    }

    onPressed: function(buttonCode) {
      if (buttonCode === Qt.RightButton) emu.refresh()
      else if (buttonCode === Qt.MiddleButton) emu.openDoctor()
      else root.toggle()
    }
  }

  KeyboardPanel {
    id: panel
    anchorItem: button
    owner: root
    bar: root.bar
    open: root.opened
    focusTarget: keyCatcher
    contentWidth: panel.fittedContentWidth(Style.space(400))
    contentHeight: panel.fittedContentHeight(column.implicitHeight, Style.space(520))

    PanelKeyCatcher {
      id: keyCatcher
      anchors.fill: parent
      onMoveRequested: function(dx, dy) {
        if (!root.cursorActive) { root.cursorActive = true; return }
        root.moveCursor(dx, dy)
      }
      onActivateRequested: if (root.cursorActive) root.activateCursor()
      onCloseRequested: root.close()
      onTabRequested: function(direction) { root.switchPanel(direction) }
      onTextKey: function(t) {
        var key = String(t || "").toLowerCase()
        if (key === "r") emu.refresh()
        else if (key === "d") emu.openDoctor()
        else if (key === "s") emu.openSdkManager()
      }

      Flickable {
        id: panelFlick
        anchors.fill: parent
        contentWidth: width
        contentHeight: column.implicitHeight
        clip: true
        boundsBehavior: Flickable.StopAtBounds
        flickableDirection: Flickable.VerticalFlick
        interactive: contentHeight > height
        ScrollBar.vertical: ScrollBar { policy: ScrollBar.AsNeeded }

        Column {
          id: column
          width: panelFlick.width
          spacing: Style.space(12)

          PanelHero {
            id: hero
            width: parent.width
            title: "Android Emulator"
            meta: emu.missingBinary ? "emuctl not found" : Model.summaryText(emu.summary, false)
            foreground: root.foreground
            fontFamily: root.fontFamily
            iconOpacity: emu.missingBinary ? 0.5 : 1.0
            iconComponent: Component {
              AndroidIcon {
                iconSize: Style.font.display
                color: root.foreground
              }
            }

            trailingControl: Component {
              RowLayout {
                spacing: Style.space(4)
                PanelActionButton {
                  iconText: "󰒓"
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  tooltipText: "Manage SDK packages (opens a terminal)"
                  enabled: !emu.missingBinary
                  onClicked: emu.openSdkManager()
                }
                PanelActionButton {
                  iconText: "󰓙"
                  foreground: hero.foreground
                  fontFamily: hero.fontFamily
                  tooltipText: "Run emuctl doctor (opens a terminal)"
                  enabled: !emu.missingBinary
                  onClicked: emu.openDoctor()
                }
              }
            }
          }

          Text {
            textFormat: Text.PlainText
            visible: text !== ""
            width: parent.width
            text: emu.actionStatus !== "" ? emu.actionStatus : emu.lastError
            color: emu.actionStatus === "" && emu.lastError !== "" ? root.urgent : root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          Text {
            textFormat: Text.PlainText
            visible: emu.missingBinary
            width: parent.width
            text: "Install emuctl (comes with this plugin's install.sh), or set its path in this widget's settings."
            color: root.dim
            font.family: root.fontFamily
            font.pixelSize: Style.font.bodySmall
            wrapMode: Text.WordWrap
          }

          NewAvdRow { width: parent.width }

          Column {
            visible: emu.profilesOpen
            width: parent.width
            spacing: Style.space(10)

            // The brand-style cards: one per device category (Pixel / Tablet
            // / Legacy), laid out in a single row. There's no real
            // Samsung/OEM/iPhone category to offer here -- avdmanager's
            // device list is Google's own reference hardware plus a handful
            // of old Nexus phones, nothing else -- so these three are what
            // the SDK actually has, grouped for browsing rather than one
            // long alphabetical list.
            RowLayout {
              visible: emu.profiles.grouped
              width: parent.width
              spacing: Style.space(8)

              Repeater {
                model: emu.profiles.grouped ? emu.profiles.categories : []

                CategoryCard {
                  required property string modelData
                  Layout.fillWidth: true
                  category: modelData
                  count: emu.profiles.byCategory[modelData] ? emu.profiles.byCategory[modelData].length : 0
                  selected: emu.selectedCategory === modelData
                }
              }
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: emu.visibleProfiles

                ProfileRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  profileId: modelData.id
                  profileLabel: modelData.label
                  rowIndex: index
                }
              }
            }

            Text {
              visible: emu.visibleProfiles.length === 0
              textFormat: Text.PlainText
              text: "Loading profiles…"
              color: root.dim
              font.family: root.fontFamily
              font.pixelSize: Style.font.bodySmall
            }
          }

          PanelSeparator {
            visible: emu.avds.length > 0
            foreground: root.foreground
          }

          Column {
            visible: emu.avds.length > 0
            width: parent.width
            spacing: Style.space(10)

            PanelSectionHeader {
              text: "VIRTUAL DEVICES"
              foreground: root.foreground
              fontFamily: root.fontFamily
            }

            Column {
              width: parent.width
              spacing: Style.space(6)

              Repeater {
                model: emu.avds

                AvdRow {
                  required property var modelData
                  required property int index
                  width: parent.width
                  avd: modelData
                  rowIndex: index
                }
              }
            }
          }
        }
      }
    }
  }

  component NewAvdRow: CursorSurface {
    id: newAvdRow
    hasCursor: root.cursorActive && root.cursor === 0
    foreground: root.foreground
    implicitHeight: newAvdContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(0)
      onClicked: emu.toggleProfiles()
    }

    RowLayout {
      id: newAvdContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      Text {
        textFormat: Text.PlainText
        text: emu.profilesOpen ? "󰅀" : "󰐕"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.icon
      }

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: "New virtual device"
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        elide: Text.ElideRight
      }
    }
  }

  // A brand-style card for one device category. Mouse-only (not part of the
  // keyboard cursor chain below it) -- three cards side by side don't fit the
  // single up/down cursor the row list already uses, and a click is the
  // natural way to pick one anyway.
  component CategoryCard: Rectangle {
    id: card
    property string category: ""
    property int count: 0
    property bool selected: false

    implicitHeight: cardContent.implicitHeight + Style.space(16)
    radius: Style.space(6)
    color: selected ? Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.12)
                     : Qt.rgba(root.foreground.r, root.foreground.g, root.foreground.b, 0.04)
    border.width: selected ? 1 : 0
    border.color: root.foreground

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onClicked: emu.selectCategory(card.category)
    }

    ColumnLayout {
      id: cardContent
      anchors.centerIn: parent
      spacing: Style.space(2)

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignHCenter
        text: Model.categoryLabel(card.category)
        color: root.foreground
        font.family: root.fontFamily
        font.pixelSize: Style.font.body
        font.bold: card.selected
      }

      Text {
        textFormat: Text.PlainText
        Layout.alignment: Qt.AlignHCenter
        text: card.count + (card.count === 1 ? " device" : " devices")
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.caption
      }
    }
  }

  component ProfileRow: CursorSurface {
    id: profileRow
    property string profileId: ""
    property string profileLabel: ""
    property int rowIndex: 0

    readonly property bool selected: root.cursorActive && root.cursor === 1 + rowIndex

    hasCursor: selected
    foreground: root.foreground
    implicitHeight: profileContent.implicitHeight + Style.spacing.rowPaddingX * 0.6

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(1 + profileRow.rowIndex)
      onClicked: emu.createFromProfile(profileRow.profileId)
    }

    RowLayout {
      id: profileContent
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(28)
      anchors.rightMargin: Style.space(10)

      Text {
        textFormat: Text.PlainText
        Layout.fillWidth: true
        text: profileRow.profileLabel
        color: root.dim
        font.family: root.fontFamily
        font.pixelSize: Style.font.bodySmall
        elide: Text.ElideRight
      }
    }
  }

  component AvdRow: CursorSurface {
    id: avdRow
    property var avd: null
    property int rowIndex: 0

    readonly property bool selected: root.cursorActive && root.cursor === 1 + root.profileRows + rowIndex

    hasCursor: selected
    foreground: root.foreground
    implicitHeight: rowContent.implicitHeight + Style.spacing.rowPaddingX

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: root.setCursor(1 + root.profileRows + avdRow.rowIndex)
      onClicked: emu.toggleAvd(avdRow.avd)
    }

    RowLayout {
      anchors.left: parent.left
      anchors.right: parent.right
      anchors.verticalCenter: parent.verticalCenter
      anchors.leftMargin: Style.space(10)
      anchors.rightMargin: Style.space(10)
      spacing: Style.space(8)

      ColumnLayout {
        id: rowContent
        Layout.fillWidth: true
        spacing: Style.space(1)

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: avdRow.avd ? avdRow.avd.id : ""
          color: root.foreground
          font.family: root.fontFamily
          font.pixelSize: Style.font.body
          elide: Text.ElideRight
        }

        Text {
          textFormat: Text.PlainText
          Layout.fillWidth: true
          text: Model.rowMeta(avdRow.avd)
          color: root.dim
          font.family: root.fontFamily
          font.pixelSize: Style.font.caption
          elide: Text.ElideRight
        }
      }

      ToggleSwitch {
        checked: Model.isRunning(avdRow.avd)
        busy: emu.busy
        hasCursor: avdRow.selected
        foreground: root.foreground
        Layout.alignment: Qt.AlignVCenter
        onHovered: function(on) { if (on) root.setCursor(1 + root.profileRows + avdRow.rowIndex) }
        onToggled: emu.toggleAvd(avdRow.avd)
      }
    }
  }
}
