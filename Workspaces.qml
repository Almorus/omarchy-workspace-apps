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
      if (id > 0 && ids.indexOf(id) === -1) ids.push(id)
    }

    ids.sort(function(left, right) { return left - right })
    return ids
  }

  // Workspace cells live in a ListModel that is patched rather than replaced,
  // so cells (and their tooltips) survive other workspaces coming and going.
  ListModel { id: workspaceModel }

  function syncWorkspaces() {
    var ids = root.workspaceIds()

    for (var i = workspaceModel.count - 1; i >= 0; i--) {
      if (ids.indexOf(workspaceModel.get(i).wsId) === -1) workspaceModel.remove(i)
    }

    // What's left is an in-order subset of ids, so fill the gaps.
    for (var j = 0; j < ids.length; j++) {
      if (j >= workspaceModel.count || workspaceModel.get(j).wsId !== ids[j]) workspaceModel.insert(j, { wsId: ids[j] })
    }
  }

  Component.onCompleted: root.syncWorkspaces()

  Connections {
    target: Hyprland.workspaces
    function onValuesChanged() { root.syncWorkspaces() }
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

    var entry = null
    try { entry = DesktopEntries.heuristicLookup(cls) } catch (e) {}
    return entry || root.fallbackEntry(cls)
  }

  // Some apps report a class their desktop entry doesn't list, e.g. Hermes is
  // com.nousresearch.hermes but its entry is hermes-desktop. Compare the class
  // and its last dotted part with each entry's id, StartupWMClass, binary and
  // name. Only whole, case-insensitive matches count, strongest field first.
  function fallbackEntry(cls) {
    if (!cls) return null
    var keys = [cls.toLowerCase()]
    var tail = cls.split(".").pop().toLowerCase()
    if (tail && keys.indexOf(tail) === -1) keys.push(tail)

    var values = DesktopEntries.applications.values || []
    var fields = [
      function(e) { return String(e.id || "").replace(/\.desktop$/, "").split(".").pop() },
      function(e) { return String(e.startupClass || "") },
      function(e) { return String((e.command && e.command[0]) || "").split("/").pop() },
      function(e) { return String(e.name || "") }
    ]
    for (var f = 0; f < fields.length; f++) {
      for (var i = 0; i < values.length; i++) {
        var value = fields[f](values[i]).toLowerCase()
        if (value && keys.indexOf(value) !== -1) return values[i]
      }
    }

    return null
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
  // plain terminals to Hyprland, so claude-scan.sh looks for a `claude`
  // process under each window.
  property var claudeWindows: ({})
  property string claudeKey: ""
  property bool claudeScanPending: false

  // Only these get the mascot, so apps that launch `claude` themselves
  // (Claude Desktop, editors) keep their own icon.
  readonly property var terminalClasses: ["foot", "footclient", "Alacritty", "kitty", "com.mitchellh.ghostty", "org.wezfurlong.wezterm"]

  function addressKey(address) {
    return String(address).replace(/^0x/, "")
  }

  function iconFor(toplevel) {
    var cls = root.windowClass(toplevel)
    if (root.terminalClasses.indexOf(cls) !== -1 && root.claudeWindows[root.addressKey(toplevel.address)] === true)
      return Qt.resolvedUrl("claude-code.svg")
    return root.iconSource(cls)
  }

  Process {
    id: claudeScan
    command: ["sh", decodeURIComponent(String(Qt.resolvedUrl("claude-scan.sh")).replace(/^file:\/\//, ""))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = ({})
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          var address = lines[i].trim()
          if (address) next[address] = true
        }

        // Reassigning re-evaluates every icon, so only do it on a real change.
        var key = Object.keys(next).sort().join(",")
        if (key === root.claudeKey) return
        root.claudeKey = key
        root.claudeWindows = next
      }
    }
    onExited: {
      if (!root.claudeScanPending) return
      root.claudeScanPending = false
      claudeScan.running = true
    }
  }

  Timer {
    id: claudeScanDelay
    interval: 300
    onTriggered: {
      // A scan already running may predate the change; queue one more.
      if (claudeScan.running) root.claudeScanPending = true
      else claudeScan.running = true
    }
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
      model: workspaceModel

      GridLayout {
        id: cell

        required property int wsId

        readonly property var workspace: root.workspaceById(wsId)
        readonly property bool occupied: root.windowsOf(workspace).length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === wsId
        readonly property string label: wsId === 10 ? "0" : String(wsId)

        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: 0
        rowSpacing: 0

        WidgetButton {
          bar: root.bar
          text: cell.label
          // Current workspace: theme accent colour.
          foreground: cell.focused ? Commons.Color.accent : (root.bar ? root.bar.barForeground : Commons.Color.foreground)
          opacity: cell.occupied || cell.focused ? 1 : 0.5
          horizontalMargin: 6
          verticalPadding: 6
          // Two-digit numbers (11+) size to their text instead.
          fixedWidth: root.vertical ? root.barSize : (cell.label.length > 1 ? -1 : Style.space(20))
          fixedHeight: root.barSize
          onPressed: function() { root.focusWorkspace(cell.wsId) }
        }

        // The live window model, so opening or closing one window only adds or
        // removes that icon.
        Repeater {
          model: cell.workspace ? cell.workspace.toplevels : []
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
        model: root.scratchpad ? root.scratchpad.toplevels : []
        WindowIcon { inScratchpad: true }
      }
    }
  }
}
