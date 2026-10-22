import QtQuick
import QtQuick.Layouts
import Quickshell
import Quickshell.Hyprland
import Quickshell.Io
import qs.Commons
import qs.Commons as Commons
import qs.Ui

BarWidget {
  id: root
  moduleName: "almorus.workspace-apps"

  readonly property string scratchpadName: "special:scratchpad"
  readonly property real iconSize: Math.round(root.barSize * 0.5)

  // Window class -> icon URL. Cleared whenever desktop entries change.
  property var iconCache: ({})

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() { root.iconCache = ({}) }
  }

  function workspaceById(id) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].id === id) return values[i]
    }

    return null
  }

  function workspaceByName(name) {
    var values = Hyprland.workspaces.values
    for (var i = 0; i < values.length; i++) {
      if (values[i].name === name) return values[i]
    }

    return null
  }

  function workspaceIds() {
    var ids = [1, 2, 3, 4, 5]
    var values = Hyprland.workspaces.values

    for (var i = 0; i < values.length; i++) {
      var id = values[i].id
      if (id > 0 && id <= 10 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  function windowsOf(workspace) {
    return workspace ? workspace.toplevels.values : []
  }

  function windowClass(toplevel) {
    if (toplevel.wayland && toplevel.wayland.appId) return String(toplevel.wayland.appId)
    if (toplevel.lastIpcObject && toplevel.lastIpcObject.class) return String(toplevel.lastIpcObject.class)
    return ""
  }

  function entryForClass(cls) {
    // Omarchy web apps run as chrome-<host>__<path>-<profile>; match them to the
    // desktop entry that launches that host.
    var web = /^chrome-([^_]+)__/.exec(cls)
    if (web) {
      var host = "//" + web[1]
      var values = DesktopEntries.applications.values || []
      for (var i = 0; i < values.length; i++) {
        if (String(values[i].execString || "").indexOf(host) !== -1) return values[i]
      }
    }

    try { return DesktopEntries.heuristicLookup(cls) } catch (e) { return null }
  }

  function iconSource(cls) {
    if (root.iconCache[cls] !== undefined) return root.iconCache[cls]

    var entry = cls ? root.entryForClass(cls) : null
    var name = entry ? String(entry.icon || "") : cls
    var source = ""
    if (name.charAt(0) === "/") source = Util.fileUrl(name)
    else if (/^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/.test(name))
      source = Quickshell.iconPath(name, true) || Quickshell.iconPath(name.toLowerCase(), true)
    if (!source) source = Quickshell.iconPath("application-x-executable", true)

    root.iconCache[cls] = source
    return source
  }

  // Terminal windows running Claude Code, keyed by address (no 0x). They are
  // plain terminals to Hyprland, so look for a `claude` process under each one.
  property var claudeWindows: ({})

  function addressKey(address) {
    return String(address).replace(/^0x/, "")
  }

  function iconFor(toplevel) {
    if (root.claudeWindows[root.addressKey(toplevel.address)] === true) return Qt.resolvedUrl("claude-code.svg")
    return root.iconSource(root.windowClass(toplevel))
  }

  Process {
    id: claudeScan
    command: ["sh", "-c", "{ ps -eo pid=,ppid=,comm= | awk '{par[$1]=$2; if ($3==\"claude\") c[$1]=1} END {for (p in c) {q=par[p]; for (i=0; i<10 && q>1; i++) {print \"A \" q; q=par[q]}}}'; hyprctl clients; } | awk '$1==\"A\" {a[$2]=1; next} $1==\"Window\" {w=$2} $1==\"pid:\" && ($2 in a) {print w}'"]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = ({})
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var address = lines[i].trim()
          if (address) next[address] = true
        }
        root.claudeWindows = next
      }
    }
  }

  Timer {
    id: claudeScanDelay
    interval: 300
    onTriggered: if (!claudeScan.running) claudeScan.running = true
  }

  // Rescan when windows open or close, and every few seconds for Claude Code
  // started inside an already open terminal.
  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: claudeScanDelay.restart()
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { claudeScanDelay.restart() }
  }

  function focusWorkspace(id) {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ workspace = \"" + id + "\" })"))
  }

  function toggleScratchpad() {
    if (!root.bar) return
    root.bar.run("hyprctl dispatch " + Util.shellQuote("hl.dsp.workspace.toggle_special(\"scratchpad\")"))
  }

  function focusWindow(toplevel, inScratchpad) {
    if (!root.bar) return
    var address = String(toplevel.address)
    if (address.indexOf("0x") !== 0) address = "0x" + address
    if (!/^0x[0-9a-fA-F]+$/.test(address)) return

    var focus = "hyprctl dispatch " + Util.shellQuote("hl.dsp.focus({ window = \"address:" + address + "\" })")
    if (!inScratchpad) {
      root.bar.run(focus)
      return
    }

    // Show the scratchpad first unless it's already open, then focus the window in it.
    var toggle = "hyprctl dispatch " + Util.shellQuote("hl.dsp.workspace.toggle_special(\"scratchpad\")")
    root.bar.run("hyprctl monitors -j | grep -q '\"" + root.scratchpadName + "\"' || " + toggle + "; " + focus)
  }

  readonly property var scratchpad: root.workspaceByName(root.scratchpadName)
  readonly property bool scratchpadOccupied: root.windowsOf(root.scratchpad).length > 0

  readonly property real trailingGap: root.vertical ? 0 : Style.spaceReal(1.5)

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  component WindowIcon: Item {
    id: windowIcon

    required property var modelData
    property bool inScratchpad: false

    implicitWidth: root.vertical ? root.barSize : root.iconSize + Style.spaceReal(1)
    implicitHeight: root.vertical ? root.iconSize + Style.spaceReal(1) : root.barSize

    Image {
      anchors.centerIn: parent
      width: root.iconSize
      height: root.iconSize
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels so icons stay sharp on HiDPI displays.
      sourceSize.width: Math.round(root.iconSize * Screen.devicePixelRatio)
      sourceSize.height: Math.round(root.iconSize * Screen.devicePixelRatio)
      source: root.iconFor(windowIcon.modelData)
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onEntered: if (root.bar) root.bar.showTooltip(windowIcon, windowIcon.modelData.title || root.windowClass(windowIcon.modelData))
      onExited: if (root.bar) root.bar.hideTooltip(windowIcon)
      onClicked: {
        if (root.bar) root.bar.hideTooltip(windowIcon)
        root.focusWindow(windowIcon.modelData, windowIcon.inScratchpad)
      }
    }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    columnSpacing: root.vertical ? 0 : Style.space(1)
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: root.workspaceIds()

      GridLayout {
        id: cell

        required property int modelData

        readonly property var workspace: root.workspaceById(modelData)
        readonly property var windows: root.windowsOf(workspace)
        readonly property bool occupied: windows.length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === modelData

        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: 0
        rowSpacing: 0

        WidgetButton {
          bar: root.bar
          text: cell.modelData === 10 ? "0" : String(cell.modelData)
          // Current workspace: theme accent colour.
          foreground: cell.focused ? Commons.Color.accent : (root.bar ? root.bar.barForeground : Commons.Color.foreground)
          opacity: cell.occupied || cell.focused ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          fixedWidth: root.vertical ? root.barSize : Style.space(20)
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(cell.modelData) }
        }

        Repeater {
          model: cell.windows
          WindowIcon {}
        }
      }
    }

    // Scratchpad (SUPER+S): only shown while something is parked there.
    GridLayout {
      visible: root.scratchpadOccupied
      flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
      columnSpacing: 0
      rowSpacing: 0

      WidgetButton {
        bar: root.bar
        text: "S"
        tooltipText: "Scratchpad"
        horizontalMargin: 6
        verticalPadding: 6
        fixedWidth: root.vertical ? root.barSize : Style.space(20)
        fixedHeight: root.barSize
        onPressed: function() { root.toggleScratchpad() }
      }

      Repeater {
        model: root.windowsOf(root.scratchpad)
        WindowIcon { inScratchpad: true }
      }
    }
  }
}
