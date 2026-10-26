import QtQuick
import QtQuick.Effects
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

  // Window class -> icon URL, and terminal program -> icon URL or "". Cleared
  // whenever desktop entries change.
  property var iconCache: ({})
  property var programIconCache: ({})

  Connections {
    target: DesktopEntries.applications
    function onValuesChanged() {
      root.iconCache = ({})
      root.programIconCache = ({})
    }
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

  // An icon name or absolute path -> URL, or "" when there's no such icon.
  function iconPath(name) {
    if (name.charAt(0) === "/") return Util.fileUrl(name)
    if (/^[A-Za-z0-9][A-Za-z0-9._+-]{0,127}$/.test(name))
      return Quickshell.iconPath(name, true) || Quickshell.iconPath(name.toLowerCase(), true)
    return ""
  }

  function iconSource(cls) {
    if (root.iconCache[cls] !== undefined) return root.iconCache[cls]

    var entry = cls ? root.entryForClass(cls) : null
    var source = root.iconPath(entry ? String(entry.icon || "") : cls)
    if (!source) source = Quickshell.iconPath("application-x-executable", true)

    root.iconCache[cls] = source
    return source
  }

  // Icon for a program running in a terminal, or "" to keep the terminal's
  // own: the desktop entry named after it (nvim, btop), a launcher that runs
  // it in a terminal (Disk Usage for dua), or a theme icon of the same name.
  function programIcon(program) {
    if (root.programIconCache[program] !== undefined) return root.programIconCache[program]

    var key = program.toLowerCase()
    var word = new RegExp("(^|[\\s\"'/])" + key.replace(/[.*+?^${}()|[\]\\]/g, "\\$&") + "([\\s\"']|$)")
    var values = DesktopEntries.applications.values || []
    var entry = null
    for (var i = 0; i < values.length && !entry; i++) {
      if (String(values[i].id || "").replace(/\.desktop$/, "").split(".").pop().toLowerCase() === key) entry = values[i]
    }
    for (var j = 0; j < values.length && !entry; j++) {
      var exec = String(values[j].execString || "").toLowerCase()
      if ((values[j].runInTerminal || / -e /.test(exec)) && word.test(exec)) entry = values[j]
    }

    var source = entry ? root.iconPath(String(entry.icon || "")) : ""
    if (!source) source = root.iconPath(program)
    root.programIconCache[program] = source
    return source
  }

  // Terminal windows running Claude Code, keyed by address (no 0x), mapped to
  // the session's state: idle, working or input. They are plain terminals to
  // Hyprland, so agent-scan.sh looks for a `claude` process under each window
  // and reads the state claude-status.sh records from Claude Code's hooks.
  property var claudeWindows: ({})
  // Windows with a `hermes` process under them (the CLI in a terminal), keyed
  // and valued the same way, from hermes-status.sh.
  property var hermesWindows: ({})
  property bool hermesWindowWorking: false
  // The program in the foreground of each terminal window (nvim, btop...),
  // keyed the same way, from the same scan. Shells aren't listed.
  property var terminalPrograms: ({})
  property string scanKey: ""
  property bool agentScanPending: false
  property bool claudeAnimating: false

  // Only terminals get the mascot or their program's icon, so apps that launch
  // `claude` themselves (Claude Desktop, editors) keep their own icon. Omarchy
  // opens its terminals with org.omarchy.* app ids (org.omarchy.agent for
  // omarchy-agent) or TUI.* ones, so those count too.
  readonly property var terminalClasses: ["foot", "footclient", "Alacritty", "kitty", "com.mitchellh.ghostty", "org.wezfurlong.wezterm"]

  function isTerminal(cls) {
    return root.terminalClasses.indexOf(cls) !== -1 || cls.indexOf("org.omarchy.") === 0 || cls === "TUI" || cls.indexOf("TUI.") === 0
  }

  // Two-frame animations: typing while working, waving when it needs input.
  readonly property var claudeFrames: ({
    "working": [Qt.resolvedUrl("claude-code-typing-1.svg"), Qt.resolvedUrl("claude-code-typing-2.svg")],
    "input": [Qt.resolvedUrl("claude-code-wave-1.svg"), Qt.resolvedUrl("claude-code-wave-2.svg")]
  })
  property int claudeFrame: 0

  // Only runs while some session is working or waiting.
  Timer {
    interval: 350
    repeat: true
    running: root.agentsAnimating
    onTriggered: root.claudeFrame = 1 - root.claudeFrame
  }

  // Hermes outside any window (idle, working or input), from hermes-status.sh
  // via its hooks. Its icon, also shown for terminals running the Hermes CLI,
  // turns orange and breathes while it works, and red while it waits on you.
  // The breathing steps through a few levels instead of animating smoothly, so
  // the bar isn't redrawn every frame.
  property string hermesState: "idle"
  readonly property color agentWorkingColor: "#D77757"
  readonly property color agentInputColor: "#E5484D"
  readonly property var hermesPulseLevels: [0.45, 0.6, 0.75, 0.9, 1, 0.9, 0.75, 0.6]
  property int hermesPulseStep: 0

  Timer {
    interval: 150
    repeat: true
    running: root.hermesState === "working" || root.hermesWindowWorking
    onTriggered: root.hermesPulseStep = (root.hermesPulseStep + 1) % root.hermesPulseLevels.length
  }

  function isHermes(cls) {
    return cls.split(".").pop().toLowerCase() === "hermes"
  }

  // What Hermes is doing for a window, or undefined if it has none: the app's
  // own windows, and terminals running the Hermes CLI (unless Claude Code is
  // in there too, which wins).
  function hermesStateOf(toplevel) {
    var cls = root.windowClass(toplevel)
    var state = root.hermesWindows[root.addressKey(toplevel.address)]
    if (root.isHermes(cls)) {
      var rank = ({ "idle": 0, "working": 1, "input": 2 })
      return state !== undefined && rank[state] > rank[root.hermesState] ? state : root.hermesState
    }
    if (!root.isTerminal(cls) || root.claudeState(toplevel) !== undefined) return undefined
    return state
  }

  function addressKey(address) {
    return String(address).replace(/^0x/, "")
  }

  // While it works, Claude Code starts the terminal title with a spinner (◐◑◒◓).
  // That covers sessions whose hooks can't be traced to their window, such as
  // background sessions shown through `claude`'s client, or no hooks at all.
  function titleBusy(toplevel) {
    return /^[◐-◓]/.test(String(toplevel.title || ""))
  }

  function claudeState(toplevel) {
    var state = root.claudeWindows[root.addressKey(toplevel.address)]
    if (state === "idle" && root.titleBusy(toplevel)) return "working"
    return state
  }

  // Something to animate: a hooked session, or a spinner in a Claude terminal's title.
  readonly property bool agentsAnimating: {
    if (root.claudeAnimating) return true
    var values = Hyprland.toplevels.values
    for (var i = 0; i < values.length; i++) {
      if (root.claudeWindows[root.addressKey(values[i].address)] !== undefined && root.titleBusy(values[i])) return true
    }
    return false
  }

  function iconFor(toplevel) {
    var cls = root.windowClass(toplevel)
    if (!root.isTerminal(cls)) return root.iconSource(cls)

    var state = root.claudeState(toplevel)
    if (state !== undefined) {
      var frames = root.claudeFrames[state]
      return frames ? frames[root.claudeFrame] : Qt.resolvedUrl("claude-code.svg")
    }

    if (root.hermesStateOf(toplevel) !== undefined) return root.iconSource("com.nousresearch.hermes")

    var program = root.terminalPrograms[root.addressKey(toplevel.address)]
    return (program && root.programIcon(program)) || root.iconSource(cls)
  }

  // The panel's line under a window's title: what the agent in it is doing,
  // the program running in a terminal, or else the app's name.
  function windowSubtitle(toplevel) {
    var cls = root.windowClass(toplevel)
    var doing = ({ "working": " · working", "input": " · needs your input" })
    var hermes = root.hermesStateOf(toplevel)
    if (hermes !== undefined) return "Hermes" + (doing[hermes] || "")

    if (root.isTerminal(cls)) {
      var state = root.claudeState(toplevel)
      if (state !== undefined) return "Claude Code" + (doing[state] || "")
      var program = root.terminalPrograms[root.addressKey(toplevel.address)]
      if (program) return program
    }

    var entry = cls ? root.entryForClass(cls) : null
    return entry ? String(entry.name || "") : cls
  }

  Process {
    id: agentScan
    command: ["sh", decodeURIComponent(String(Qt.resolvedUrl("agent-scan.sh")).replace(/^file:\/\//, ""))]
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var next = ({})
        var hermes = ({})
        var programs = ({})
        var animating = false
        var hermesWorking = false
        var lines = text.split("\n")
        for (var i = 0; i < lines.length; i++) {
          // "window <address> <state>", "hermes <address> <state>",
          // "prog <address> <program>" or "app hermes <state>"
          var fields = lines[i].trim().split(" ")
          if (fields[0] === "app" && fields[1] === "hermes") {
            if (root.hermesState !== fields[2]) root.hermesState = fields[2] || "idle"
          } else if (fields[0] === "window" && fields[1]) {
            next[fields[1]] = fields[2] || "idle"
            if (next[fields[1]] !== "idle") animating = true
          } else if (fields[0] === "hermes" && fields[1]) {
            hermes[fields[1]] = fields[2] || "idle"
            if (hermes[fields[1]] === "working") hermesWorking = true
          } else if (fields[0] === "prog" && fields[1] && fields.length > 2) {
            programs[fields[1]] = fields.slice(2).join(" ")
          }
        }

        root.agentStatusReady = true

        // Reassigning re-evaluates every icon, so only do it on a real change.
        function describe(map) {
          return Object.keys(map).sort().map(function(address) { return address + "=" + map[address] }).join(",")
        }
        var key = describe(next) + "|" + describe(hermes) + "|" + describe(programs)
        if (key === root.scanKey) return
        root.scanKey = key
        root.terminalPrograms = programs
        root.claudeWindows = next
        root.hermesWindows = hermes
        root.hermesWindowWorking = hermesWorking
        root.claudeAnimating = animating
        if (!animating) root.claudeFrame = 0
      }
    }
    onExited: {
      if (!root.agentScanPending) return
      root.agentScanPending = false
      agentScan.running = true
    }
  }

  Timer {
    id: agentScanDelay
    interval: 300
    onTriggered: {
      // A scan already running may predate the change; queue one more.
      if (agentScan.running) root.agentScanPending = true
      else agentScan.running = true
    }
  }

  // Rescan when windows open or close, and every few seconds for Claude Code
  // started inside an already open terminal.
  Timer {
    interval: 5000
    running: true
    repeat: true
    triggeredOnStart: true
    onTriggered: agentScanDelay.restart()
  }

  Connections {
    target: Hyprland.toplevels
    function onValuesChanged() { agentScanDelay.restart() }
  }

  // claude-status.sh and hermes-status.sh rewrite `changed` whenever a state
  // changes, so the icons follow within a moment. The scan creates the file,
  // so it's only watched after the first scan.
  readonly property string agentStatusDir: Quickshell.env("XDG_RUNTIME_DIR") ? Quickshell.env("XDG_RUNTIME_DIR") + "/agent-status" : ""
  property bool agentStatusReady: false

  FileView {
    path: root.agentStatusReady && root.agentStatusDir ? root.agentStatusDir + "/changed" : ""
    watchChanges: true
    printErrors: false
    onFileChanged: agentScanDelay.restart()
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

  // Horizontal spacing: a number sits much closer to its own icons than to the
  // workspace before it, so each workspace reads as one group.
  readonly property real labelLeadPad: Style.spaceReal(10)
  readonly property real labelTrailPad: Style.spaceReal(2.5)
  readonly property real iconPad: Style.spaceReal(2)

  // The focused workspace's cell. The accent line under it slides over when the
  // focus moves to another workspace, and otherwise just follows its cell.
  property Item focusedCell: null
  property bool lineSliding: false

  function setFocusedCell(cell) {
    if (root.focusedCell === cell) return
    root.lineSliding = root.focusedCell !== null
    lineSlideEnd.restart()
    root.focusedCell = cell
  }

  Timer {
    id: lineSlideEnd
    interval: 250
    onTriggered: root.lineSliding = false
  }

  implicitWidth: grid.implicitWidth + trailingGap
  implicitHeight: grid.implicitHeight

  // The number or icon under the pointer. Resting on one opens a panel that
  // lists its workspace's windows; the panel stays while the pointer is on
  // that workspace or on the panel, and follows it to other workspaces.
  property Item hoveredItem: null
  property Item panelGroup: null
  readonly property real panelIconSize: Math.round(root.iconSize * 1.25)

  function setHovered(item, hovered) {
    if (hovered) root.hoveredItem = item
    else if (root.hoveredItem === item) root.hoveredItem = null
  }

  function closePanel() {
    panelOpenDelay.stop()
    root.panelGroup = null
  }

  onHoveredItemChanged: {
    if (!root.hoveredItem) {
      panelOpenDelay.stop()
      panelCloseDelay.restart()
      return
    }
    panelCloseDelay.stop()
    if (panel.visible) root.panelGroup = root.hoveredItem.group
    else panelOpenDelay.restart()
  }

  onPanelGroupChanged: Qt.callLater(function() { if (panel.visible) panel.anchor.updateAnchor() })

  Timer {
    id: panelOpenDelay
    interval: 350
    onTriggered: if (root.hoveredItem) root.panelGroup = root.hoveredItem.group
  }

  Timer {
    id: panelCloseDelay
    interval: 250
    onTriggered: if (!root.hoveredItem && !panelHover.hovered) root.panelGroup = null
  }

  // A workspace number, or the scratchpad's S. Its lead pad is the gap to the
  // workspace before it, so clicking that gap still switches workspaces.
  component WorkspaceLabel: WidgetButton {
    id: workspaceLabel

    property bool focused: false
    property real leadPad: root.labelLeadPad
    // The workspace (or scratchpad) group this label heads, for the panel.
    property Item group: null

    bar: root.bar
    labelVisible: false
    onTooltipHoveredChanged: root.setHovered(workspaceLabel, tooltipHovered)
    fixedWidth: root.vertical ? root.barSize : workspaceLabel.leadPad + caption.implicitWidth + root.labelTrailPad
    fixedHeight: root.barSize

    Text {
      id: caption
      x: root.vertical ? (parent.width - width) / 2 : workspaceLabel.leadPad
      anchors.verticalCenter: parent.verticalCenter
      textFormat: Text.PlainText
      text: workspaceLabel.text
      // Current workspace: theme accent colour, in bold.
      color: workspaceLabel.focused ? Commons.Color.accent : workspaceLabel.foreground
      font.family: workspaceLabel.fontFamily
      font.pixelSize: workspaceLabel.fontSize
      font.bold: workspaceLabel.focused
      renderType: Text.NativeRendering
    }
  }

  // A window's icon, with Hermes's tint and the urgent mark; in the bar and
  // in the panel.
  component AppIcon: Item {
    id: appIcon

    required property var toplevel
    property real size: root.iconSize
    readonly property string agentState: root.hermesStateOf(toplevel) || "idle"

    implicitWidth: appIcon.size
    implicitHeight: appIcon.size

    Image {
      id: icon
      anchors.fill: parent
      fillMode: Image.PreserveAspectFit
      // Decode at physical pixels so icons stay sharp on HiDPI displays.
      sourceSize.width: Math.round(appIcon.size * Screen.devicePixelRatio)
      sourceSize.height: Math.round(appIcon.size * Screen.devicePixelRatio)
      source: root.iconFor(appIcon.toplevel)

      layer.enabled: appIcon.agentState !== "idle"
      layer.effect: MultiEffect {
        colorization: appIcon.agentState === "input" ? 1 : root.hermesPulseLevels[root.hermesPulseStep]
        colorizationColor: appIcon.agentState === "input" ? root.agentInputColor : root.agentWorkingColor
      }
    }

    // A window asking for attention (Hyprland's urgent flag) gets a red ! at
    // its icon's top right corner. Quickshell clears the flag on focus.
    Text {
      visible: appIcon.toplevel.urgent === true
      anchors.horizontalCenter: icon.right
      anchors.verticalCenter: icon.top
      anchors.verticalCenterOffset: appIcon.size * 0.2
      textFormat: Text.PlainText
      text: "!"
      color: Commons.Color.urgent
      style: Text.Outline
      styleColor: root.bar ? root.bar.background : "black"
      font.family: root.bar ? root.bar.fontFamily : Style.font.family
      font.pixelSize: Math.round(appIcon.size * 0.85)
      font.bold: true
    }
  }

  component WindowIcon: Item {
    id: windowIcon

    required property var modelData
    readonly property var toplevel: modelData
    property bool inScratchpad: false
    property Item group: null

    implicitWidth: root.vertical ? root.barSize : root.iconSize + root.iconPad * 2
    implicitHeight: root.vertical ? root.iconSize + Style.spaceReal(1) : root.barSize
    // Keeps the urgent mark above the next icon.
    z: windowIcon.modelData.urgent ? 1 : 0

    // The focused window's icon sits on a soft rounded background.
    Rectangle {
      readonly property color ink: root.bar ? root.bar.barForeground : Commons.Color.foreground

      anchors.centerIn: parent
      width: root.iconSize + Style.spaceReal(3)
      height: width
      radius: Math.round(width / 4)
      color: Qt.rgba(ink.r, ink.g, ink.b, 0.15)
      opacity: windowIcon.modelData.activated ? 1 : 0
      visible: opacity > 0

      Behavior on opacity { NumberAnimation { duration: 140; easing.type: Easing.OutCubic } }
    }

    AppIcon {
      anchors.centerIn: parent
      toplevel: windowIcon.modelData
    }

    MouseArea {
      anchors.fill: parent
      hoverEnabled: true
      cursorShape: Qt.PointingHandCursor
      onContainsMouseChanged: root.setHovered(windowIcon, containsMouse)
      onClicked: {
        root.closePanel()
        root.focusWindow(windowIcon.modelData, windowIcon.inScratchpad)
      }
    }
  }

  GridLayout {
    id: grid
    anchors.fill: parent
    anchors.rightMargin: root.trailingGap
    flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
    columnSpacing: 0
    rowSpacing: root.vertical ? Style.space(2) : 0

    Repeater {
      model: workspaceModel

      GridLayout {
        id: cell

        required property int wsId
        required property int index

        readonly property var workspace: root.workspaceById(wsId)
        readonly property bool occupied: root.windowsOf(workspace).length > 0
        readonly property bool focused: Hyprland.focusedWorkspace !== null && Hyprland.focusedWorkspace.id === wsId
        readonly property string label: wsId === 10 ? "0" : String(wsId)
        readonly property real leadPad: cell.index === 0 ? Style.spaceReal(6) : root.labelLeadPad
        // The focus line runs from the number to the last icon.
        readonly property real lineStart: cell.leadPad - Style.spaceReal(1)
        readonly property real lineEnd: cell.width - (cell.occupied ? root.iconPad : root.labelTrailPad) + Style.spaceReal(1)
        // For the panel.
        readonly property var windows: cell.workspace ? cell.workspace.toplevels : []
        readonly property string title: ""
        readonly property bool inScratchpad: false

        onFocusedChanged: if (cell.focused) root.setFocusedCell(cell)
        Component.onCompleted: if (cell.focused) root.setFocusedCell(cell)

        flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
        columnSpacing: 0
        rowSpacing: 0

        WorkspaceLabel {
          text: cell.label
          focused: cell.focused
          leadPad: cell.leadPad
          group: cell
          opacity: cell.occupied || cell.focused ? 1 : 0.5
          onPressed: function() {
            root.closePanel()
            root.focusWorkspace(cell.wsId)
          }
        }

        // The live window model, so opening or closing one window only adds or
        // removes that icon.
        Repeater {
          model: cell.windows
          WindowIcon { group: cell }
        }
      }
    }

    // Scratchpad (SUPER+S): only shown while something is parked there.
    GridLayout {
      id: scratchGroup

      readonly property bool occupied: root.scratchpadOccupied
      // For the panel.
      readonly property var windows: root.scratchpad ? root.scratchpad.toplevels : []
      readonly property string title: "Scratchpad"
      readonly property bool inScratchpad: true

      visible: root.scratchpadOccupied
      flow: root.vertical ? GridLayout.TopToBottom : GridLayout.LeftToRight
      columnSpacing: 0
      rowSpacing: 0

      WorkspaceLabel {
        text: "S"
        group: scratchGroup
        onPressed: function() {
          root.closePanel()
          root.toggleScratchpad()
        }
      }

      Repeater {
        model: scratchGroup.windows
        WindowIcon {
          inScratchpad: true
          group: scratchGroup
        }
      }
    }
  }

  // Accent line under the focused workspace (along its left side on a
  // vertical bar), between the icons' bottom and the bar's edge.
  Rectangle {
    readonly property Item cell: root.focusedCell

    visible: cell !== null && cell.focused
    color: Commons.Color.accent
    radius: 1
    x: !cell ? 0 : (root.vertical ? Style.spaceReal(1) : grid.x + cell.x + cell.lineStart)
    y: !cell ? 0 : (root.vertical ? grid.y + cell.y + Style.spaceReal(2) : Math.round(root.barSize * 0.875) - 1)
    width: !cell ? 0 : (root.vertical ? 2 : cell.lineEnd - cell.lineStart)
    height: !cell ? 0 : (root.vertical ? cell.height - Style.spaceReal(4) : 2)

    Behavior on x { enabled: root.lineSliding; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on y { enabled: root.lineSliding; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on width { enabled: root.lineSliding; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
    Behavior on height { enabled: root.lineSliding; NumberAnimation { duration: 180; easing.type: Easing.OutCubic } }
  }

  // The hover panel: one row per window of the hovered workspace, with its
  // icon, title and what's going on in it. Clicking a row focuses the window.
  PopupWindow {
    id: panel

    readonly property string position: root.bar ? root.bar.position : "top"
    readonly property real gap: 6

    visible: root.panelGroup !== null && root.panelGroup.occupied
    color: "transparent"
    implicitWidth: Math.ceil(panelBubble.implicitWidth)
    implicitHeight: Math.ceil(panelBubble.implicitHeight)

    anchor {
      item: root.panelGroup
      adjustment: PopupAdjustment.Slide
      edges: Edges.Top | Edges.Left
      gravity: panel.position === "bottom" ? (Edges.Top | Edges.Right)
        : (panel.position === "right" ? (Edges.Bottom | Edges.Left) : (Edges.Bottom | Edges.Right))
      rect.x: panel.position === "left" ? (root.panelGroup ? root.panelGroup.width : 0) + panel.gap
        : (panel.position === "right" ? -panel.gap : 0)
      rect.y: panel.position === "top" ? (root.panelGroup ? root.panelGroup.height : 0) + panel.gap
        : (panel.position === "bottom" ? -panel.gap : 0)
      rect.width: 1
      rect.height: 1
    }

    BorderSurface {
      id: panelBubble
      implicitWidth: panelColumn.implicitWidth + 12
      implicitHeight: panelColumn.implicitHeight + 12
      color: Commons.Color.tooltip.background
      borderSpec: Border.surfaceSpec("tooltip", "border", Commons.Color.tooltip.border, 1)
      radius: Style.cornerRadius

      HoverHandler {
        id: panelHover
        onHoveredChanged: {
          if (hovered) panelCloseDelay.stop()
          else panelCloseDelay.restart()
        }
      }

      ColumnLayout {
        id: panelColumn
        anchors.fill: parent
        anchors.margins: 6
        spacing: 2

        Text {
          visible: text !== ""
          Layout.leftMargin: 8
          Layout.topMargin: 2
          textFormat: Text.PlainText
          text: root.panelGroup ? root.panelGroup.title : ""
          color: Commons.Color.tooltip.text
          opacity: 0.6
          font.family: root.bar ? root.bar.fontFamily : Style.font.family
          font.pixelSize: Style.font.bodySmall
        }

        Repeater {
          model: root.panelGroup ? root.panelGroup.windows : []

          Rectangle {
            id: row

            required property var modelData
            // Under the pointer here, or its icon is under the pointer in the bar.
            readonly property bool marked: rowArea.containsMouse || (root.hoveredItem !== null && root.hoveredItem.toplevel === row.modelData)

            Layout.fillWidth: true
            implicitWidth: rowContent.implicitWidth + 16
            implicitHeight: rowContent.implicitHeight + 8
            radius: Style.cornerRadius / 2
            color: row.marked ? Qt.rgba(Commons.Color.tooltip.text.r, Commons.Color.tooltip.text.g, Commons.Color.tooltip.text.b, 0.12) : "transparent"

            RowLayout {
              id: rowContent
              anchors.left: parent.left
              anchors.leftMargin: 8
              anchors.verticalCenter: parent.verticalCenter
              spacing: 8

              AppIcon {
                toplevel: row.modelData
                size: root.panelIconSize
              }

              ColumnLayout {
                spacing: 1

                Text {
                  Layout.maximumWidth: Style.space(360)
                  textFormat: Text.PlainText
                  text: row.modelData.title || root.windowClass(row.modelData)
                  elide: Text.ElideRight
                  color: Commons.Color.tooltip.text
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.body
                }

                Text {
                  visible: text !== ""
                  Layout.maximumWidth: Style.space(360)
                  textFormat: Text.PlainText
                  text: root.windowSubtitle(row.modelData)
                  elide: Text.ElideRight
                  color: Commons.Color.tooltip.text
                  opacity: 0.6
                  font.family: root.bar ? root.bar.fontFamily : Style.font.family
                  font.pixelSize: Style.font.bodySmall
                }
              }
            }

            MouseArea {
              id: rowArea
              anchors.fill: parent
              hoverEnabled: true
              cursorShape: Qt.PointingHandCursor
              onClicked: {
                var inScratchpad = root.panelGroup ? root.panelGroup.inScratchpad : false
                root.closePanel()
                root.focusWindow(row.modelData, inScratchpad)
              }
            }
          }
        }
      }
    }
  }
}
