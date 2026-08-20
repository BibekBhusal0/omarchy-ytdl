import QtQuick
import Quickshell
import Quickshell.Io

Item {
  id: root

  property var shell: null
  property var manifest: null

  property bool installed: false
  property bool checkingInstallation: true
  property bool installing: false
  property string clipboardUrl: ""
  property var _clipboardCallback: null

  // Downloads are QObjects mutated in place. The panel's Repeater binds to the
  // array reference, so it keeps its delegates across progress ticks and only
  // rebuilds when an item is added or removed.
  property var downloads: []
  readonly property int downloadCount: downloads.length
  readonly property int activeCount: {
    var n = 0
    for (var i = 0; i < downloads.length; i++) {
      if (downloads[i].status === "downloading" || downloads[i].status === "merging")
        n++
    }
    return n
  }

  property var history: []
  readonly property int historyCount: history.length

  property string downloadLocation: "~/Downloads/yt-dlp"
  property string defaultQuality: "1080p"
  property string cookiesBrowser: "none"
  property string extraArgs: ""
  property bool enableHistory: true

  // Persisted across shell restarts via a small state file.
  property string selectedQuality: "1080p"
  property bool _qualityFromFile: false
  readonly property string statePath: Quickshell.env("HOME") + "/.local/state/omarchy/ytdl-quality"
  readonly property string historyPath: Quickshell.env("HOME") + "/.local/state/omarchy/ytdl-history.json"

  signal downloadsUpdated()
  signal historyUpdated()

  readonly property string scriptPath: Qt.resolvedUrl("ytdl").toString().replace(/^file:\/\//, "")

  // Download entry factory.
  Component {
    id: downloadComp
    QtObject {
      property var dwnId: -1
      property string url: ""
      property string title: ""
      property string status: "downloading"
      property real progress: 0
      property string speed: ""
      property string eta: ""
      property string filepath: ""
      property string error: ""
      property int procIdx: -1
    }
  }

  function configure(settings) {
    if (!settings) return
    if (settings.downloadLocation)
      downloadLocation = settings.downloadLocation
    if (settings.defaultQuality) {
      defaultQuality = settings.defaultQuality
      if (!root._qualityFromFile) selectedQuality = settings.defaultQuality
    }
    if (settings.cookiesBrowser)
      cookiesBrowser = settings.cookiesBrowser
    if (settings.extraArgs != null)
      extraArgs = settings.extraArgs
    if (settings.enableHistory != null)
      enableHistory = !!settings.enableHistory
  }

  function persistQuality() {
    root._qualityFromFile = true
    Quickshell.execDetached(["sh", "-c", "printf '%s' '" + root.selectedQuality + "' > " + root.statePath])
  }

  // Cycling quality in the panel also rewrites the defaultQuality setting so
  // the shell.json config, not just the in-memory selection, follows the user.
  function setDefaultQuality(q) {
    root.defaultQuality = q
    if (shell && typeof shell.mutateShellConfig === "function") {
      shell.mutateShellConfig(function(copy) {
        if (copy.bar && copy.bar.layout) {
          var sections = ["left", "center", "right"]
          for (var si = 0; si < sections.length; si++) {
            var entries = copy.bar.layout[sections[si]]
            if (!Array.isArray(entries)) continue
            for (var ei = 0; ei < entries.length; ei++) {
              if (entries[ei] && String(entries[ei].id) === "bibek.ytdl")
                entries[ei].defaultQuality = q
            }
          }
        }
        if (Array.isArray(copy.plugins)) {
          for (var pi = 0; pi < copy.plugins.length; pi++) {
            if (copy.plugins[pi] && String(copy.plugins[pi].id) === "bibek.ytdl")
              copy.plugins[pi].defaultQuality = q
          }
        }
      })
    }
  }

  function historyToJSON() {
    var out = []
    for (var i = 0; i < history.length; i++) {
      var h = history[i]
      out.push({
        dwnId: h.dwnId, url: h.url, title: h.title, status: h.status,
        progress: h.progress, speed: h.speed, eta: h.eta,
        filepath: h.filepath, error: h.error
      })
    }
    return JSON.stringify(out)
  }

  function historyFromJSON(list) {
    var out = []
    if (!Array.isArray(list)) return out
    for (var i = 0; i < list.length; i++) {
      var it = list[i] || {}
      var d = downloadComp.createObject(root)
      d.dwnId = it.dwnId !== undefined ? it.dwnId : -1
      d.url = it.url || ""
      d.title = it.title || ""
      d.status = it.status || "error"
      d.progress = it.progress || 0
      d.speed = it.speed || ""
      d.eta = it.eta || ""
      d.filepath = it.filepath || ""
      d.error = it.error || ""
      out.push(d)
    }
    return out
  }

  function persistHistory() {
    Quickshell.execDetached(["env", "YTDL_HISTORY=" + root.historyToJSON(),
      "sh", "-c", "printf %s \"$YTDL_HISTORY\" > " + root.historyPath])
  }

  FileView {
    id: historyStateFile
    path: root.historyPath
    preload: true
    printErrors: false
    onLoaded: {
      var text = String(this.text() || "").trim()
      if (!text) return
      try {
        var parsed = JSON.parse(text)
        if (Array.isArray(parsed) && parsed.length > 0) {
          root.history = root.historyFromJSON(parsed)
          root.historyUpdated()
        }
      } catch (e) { /* corrupt state file, start with empty history */ }
    }
  }

  FileView {
    id: qualityStateFile
    path: root.statePath
    preload: true
    printErrors: false
    onLoaded: {
      var v = String(text()).trim()
      if (["best", "1080p", "720p", "480p"].indexOf(v) !== -1) {
        root._qualityFromFile = true
        root.selectedQuality = v
      }
    }
  }

  function cleanUrl(url) {
    url = String(url || "").trim()
    url = url.replace(/^yt-dlp:/, "").replace(/^ytdl:/, "")
    return url
  }

  function extractVideoId(url) {
    var m = url.match(/(?:v=|youtu\.be\/|shorts\/)([\w-]{11})/)
    return m ? m[1] : null
  }

  function isYouTubeUrl(text) {
    return /(?:https?:\/\/)?(?:www\.)?(?:youtube\.com\/(?:watch\?v=|shorts\/)|youtu\.be\/)[\w-]+/.test(text)
  }

  function updateDownload(id, props) {
    for (var i = 0; i < downloads.length; i++) {
      var d = downloads[i]
      if (d.dwnId === id) {
        for (var k in props) {
          // yt-dlp opens fragmented streams with a placeholder line of
          // "100.0% of ~1.00KiB" before the real total is known, then reports
          // the true (lower) percentage. Ignore it and clamp so the bar never
          // regresses; the real 100% is set by the exit handler.
          if (k === "progress" && (props[k] >= 100 || props[k] < d.progress)) continue
          d[k] = props[k]
        }
        downloadsUpdated()
        return
      }
    }
  }

  function procAt(i) {
    if (i === 0) return dlProc0
    if (i === 1) return dlProc1
    return dlProc2
  }

  function findFreeProc() {
    for (var i = 0; i < 3; i++) {
      if (!procAt(i).running) return i
    }
    return -1
  }

  function startDownload(url, quality) {
    url = cleanUrl(url)
    if (!url) return

    for (var i = 0; i < downloads.length; i++) {
      if (downloads[i].url === url && (downloads[i].status === "downloading" || downloads[i].status === "merging"))
        return
    }

    var procIdx = findFreeProc()
    if (procIdx === -1) {
      return
    }

    var id = Date.now() + Math.floor(Math.random() * 1000)
    var q = quality || defaultQuality
    var outputTemplate = downloadLocation + "/%(title)s.%(ext)s"
    var cmd = [scriptPath, "download", url, q, outputTemplate, cookiesBrowser, extraArgs]

    var d = downloadComp.createObject(root)
    d.dwnId = id
    d.url = url
    d.title = extractVideoId(url) || url
    d.procIdx = procIdx

    downloads = downloads.concat([d])
    downloadsUpdated()

    var proc = procAt(procIdx)
    proc.downloadId = id
    proc.command = cmd
    proc.running = true

    titleProc.targetId = id
    titleProc.command = [scriptPath, "title", url, cookiesBrowser, extraArgs]
    titleProc.running = true
  }

  function retryDownload(item) {
    if (!item || !item.url) return
    removeHistoryItem(item.dwnId)
    startDownload(item.url, root.selectedQuality || defaultQuality)
  }

  function cancelDownload(id) {
    for (var i = 0; i < downloads.length; i++) {
      var d = downloads[i]
      if (d.dwnId === id) {
        if (d.procIdx >= 0) {
          var proc = procAt(d.procIdx)
          proc.downloadId = -1
          if (proc.running) proc.running = false
        }
        if (d.filepath) Quickshell.execDetached([scriptPath, "cleanup", d.filepath])
        d.status = "cancelled"
        d.progress = 0
        d.procIdx = -1
        downloads = removeById(downloads, id)
        if (root.enableHistory) {
          history = [d].concat(history)
          root.persistHistory()
        }
        downloadsUpdated()
        historyUpdated()
        return
      }
    }
  }

  function clearHistory() {
    history = []
    root.persistHistory()
    historyUpdated()
  }

  function removeHistoryItem(id) {
    history = removeById(history, id)
    root.persistHistory()
    historyUpdated()
  }

  function deleteHistoryItem(id) {
    for (var i = 0; i < history.length; i++) {
      if (history[i].dwnId === id && history[i].filepath) {
        Quickshell.execDetached(["rm", "-f", history[i].filepath])
        break
      }
    }
    root.removeHistoryItem(id)
  }

  // Drop history entries whose downloaded file has been deleted from disk.
  function pruneMissing() {
    if (!root.history.length || pruneProc.running) return
    pruneProc.command = [scriptPath, "prune-missing", root.historyPath]
    pruneProc.running = true
  }

  Process {
    id: pruneProc
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var text = String(this.text || "").trim()
        if (!text) return
        try {
          var missing = JSON.parse(text)
          if (!Array.isArray(missing) || missing.length === 0) return
          var missingMap = {}
          for (var i = 0; i < missing.length; i++) missingMap[missing[i]] = true
          var pruned = []
          var changed = false
          for (var j = 0; j < root.history.length; j++) {
            var it = root.history[j]
            if (it.filepath && missingMap[it.filepath]) {
              changed = true
              continue
            }
            pruned.push(it)
          }
          if (changed) {
            root.history = pruned
            root.persistHistory()
            root.historyUpdated()
          }
        } catch (e) { /* malformed prune output, keep history as-is */ }
      }
    }
  }

  function removeById(arr, id) {
    var result = []
    for (var i = 0; i < arr.length; i++) {
      if (arr[i].dwnId !== id) result.push(arr[i])
    }
    return result
  }

  function playFile(filepath) {
    if (!filepath) return
    Quickshell.execDetached(["xdg-open", filepath])
  }

  function openFolder(filepath) {
    if (!filepath) return
    Quickshell.execDetached(["xdg-open", filepath.replace(/\/[^\/]+$/, "")])
  }

  function onDownloadComplete(id, exitCode) {
    for (var i = 0; i < downloads.length; i++) {
      var d = downloads[i]
      if (d.dwnId === id) {
        if (exitCode === 0) {
          d.status = "done"
          d.progress = 100
        } else if (d.status !== "cancelled") {
          d.status = "error"
          if (!d.error) d.error = "yt-dlp exited with code " + exitCode
          if (d.filepath) Quickshell.execDetached([scriptPath, "cleanup", d.filepath])
        }
        d.procIdx = -1
        downloads = removeById(downloads, id)
        downloadsUpdated()
        if (d.status === "done" || d.status === "error") {
          if (root.enableHistory) {
            history = [d].concat(history)
            root.persistHistory()
          }
          historyUpdated()
        }
        return
      }
    }
  }

  function parseLine(proc, line) {
    line = String(line || "").trim()
    if (!line) return
    var id = proc.downloadId

    var destMatch = line.match(/\[download\]\s+Destination:\s+(.+)/)
    if (destMatch) {
      var full = destMatch[1].trim()
      var fname = full.replace(/^.*\//, "").replace(/\.[^.]+$/, "")
      root.updateDownload(id, { title: fname, filepath: full })
      return
    }

    var alreadyMatch = line.match(/\[download\]\s+(.+?)\s+has already been downloaded/)
    if (alreadyMatch) {
      var afull = alreadyMatch[1].trim()
      var aname = afull.replace(/^.*\//, "").replace(/\.[^.]+$/, "")
      root.updateDownload(id, { title: aname, filepath: afull, progress: 100 })
      return
    }

    var mergerRename = line.match(/\[Merger\]\s+Merging formats into "(.+)"/)
    if (mergerRename) {
      var mfull = mergerRename[1].trim()
      var mname = mfull.replace(/^.*\//, "").replace(/\.[^.]+$/, "")
      root.updateDownload(id, { status: "merging", progress: 100, title: mname, filepath: mfull })
      return
    }

    var pctMatch = line.match(/\[download\]\s+([\d.]+)%\s+of\s+~?\s*([\d.]+\S+)\s+at\s+([\d.]+\S+)\s+ETA\s+([\d:]+)/)
    if (pctMatch) {
      root.updateDownload(id, {
        progress: parseFloat(pctMatch[1]),
        speed: pctMatch[3],
        eta: pctMatch[4]
      })
      return
    }

    var pctMatchSimple = line.match(/\[download\]\s+([\d.]+)%/)
    if (pctMatchSimple) {
      root.updateDownload(id, { progress: parseFloat(pctMatchSimple[1]) })
      return
    }

    if (line.indexOf("ERROR") !== -1) {
      root.updateDownload(id, { error: line.replace(/^ERROR:\s*/, "") })
    }
  }

  // Title fetch process
  Process {
    id: titleProc
    property var targetId: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var title = String(this.text || "").trim()
        if (title && titleProc.targetId !== -1) {
          root.updateDownload(titleProc.targetId, { title: title })
          titleProc.targetId = -1
        }
      }
    }
  }

  Process {
    id: dlProc0
    objectName: "dlProc0"
    property var downloadId: -1
    property string _errBuf: ""
    stdout: SplitParser { onRead: function(line) { root.parseLine(dlProc0, line) } }
    stderr: SplitParser { onRead: function(line) { dlProc0._errBuf += line + "\n" } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && dlProc0._errBuf) {
        var errLines = String(dlProc0._errBuf).split("\n")
        for (var i = 0; i < errLines.length; i++) {
          if (errLines[i].indexOf("ERROR") !== -1) {
            root.updateDownload(downloadId, { error: errLines[i].replace(/^ERROR:\s*/, "") })
            break
          }
        }
      }
      dlProc0._errBuf = ""
      root.onDownloadComplete(downloadId, exitCode)
      downloadId = -1
    }
  }

  Process {
    id: dlProc1
    objectName: "dlProc1"
    property var downloadId: -1
    property string _errBuf: ""
    stdout: SplitParser { onRead: function(line) { root.parseLine(dlProc1, line) } }
    stderr: SplitParser { onRead: function(line) { dlProc1._errBuf += line + "\n" } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && dlProc1._errBuf) {
        var errLines = String(dlProc1._errBuf).split("\n")
        for (var i = 0; i < errLines.length; i++) {
          if (errLines[i].indexOf("ERROR") !== -1) {
            root.updateDownload(downloadId, { error: errLines[i].replace(/^ERROR:\s*/, "") })
            break
          }
        }
      }
      dlProc1._errBuf = ""
      root.onDownloadComplete(downloadId, exitCode)
      downloadId = -1
    }
  }

  Process {
    id: dlProc2
    objectName: "dlProc2"
    property var downloadId: -1
    property string _errBuf: ""
    stdout: SplitParser { onRead: function(line) { root.parseLine(dlProc2, line) } }
    stderr: SplitParser { onRead: function(line) { dlProc2._errBuf += line + "\n" } }
    onExited: function(exitCode) {
      if (exitCode !== 0 && dlProc2._errBuf) {
        var errLines = String(dlProc2._errBuf).split("\n")
        for (var i = 0; i < errLines.length; i++) {
          if (errLines[i].indexOf("ERROR") !== -1) {
            root.updateDownload(downloadId, { error: errLines[i].replace(/^ERROR:\s*/, "") })
            break
          }
        }
      }
      dlProc2._errBuf = ""
      root.onDownloadComplete(downloadId, exitCode)
      downloadId = -1
    }
  }

  // One-shot clipboard read, run when the panel opens.
  property string _clipboardBuf: ""

  function checkClipboard(callback) {
    if (clipboardProc.running) return
    root._clipboardBuf = ""
    root._clipboardCallback = callback
    clipboardProc.running = true
  }

  Process {
    id: clipboardProc
    command: ["wl-paste", "--no-newline"]
    stdout: SplitParser {
      onRead: function(data) { root._clipboardBuf += data }
    }
    onExited: function(exitCode) {
      var cb = root._clipboardCallback
      root._clipboardCallback = null
      if (exitCode !== 0) {
        if (cb) cb("")
        return
      }
      var content = String(root._clipboardBuf || "").trim()
      root._clipboardBuf = ""
      var url = ""
      if (root.isYouTubeUrl(content)) {
        var cleaned = content.match(/(https?:\/\/[^\s]+)/)
        if (cleaned) url = cleaned[1]
      }
      root.clipboardUrl = url
      if (cb) cb(url)
    }
  }

  // Installation check
  function checkInstallation() {
    if (whichProc.running) return
    root.checkingInstallation = true
    whichProc.command = [scriptPath, "check"]
    whichProc.running = true
  }

  function installInTerminal() {
    root.installing = true
    var cmd = "omarchy pkg add yt-dlp"
    Quickshell.execDetached(["omarchy", "launch", "floating", "terminal", "with", "presentation", cmd])
    installPoll.restart()
    installTimeout.restart()
  }

  Process {
    id: whichProc
    onExited: function(exitCode) {
      root.checkingInstallation = false
      root.installed = (exitCode === 0)
      if (root.installed) {
        root.installing = false
        installPoll.stop()
        installTimeout.stop()
      }
    }
  }

  Timer {
    id: installPoll
    interval: 2000
    repeat: true
    running: root.installing && !root.installed
    onTriggered: root.checkInstallation()
  }

  Timer {
    id: installTimeout
    interval: 300000
    onTriggered: {
      if (!root.installing) return
      root.installing = false
      installPoll.stop()
    }
  }

  IpcHandler {
    target: "ytdl"
    function start(url: string): void { root.startDownload(url) }
    function cancel(id: string): void { root.cancelDownload(parseInt(id)) }
    function status(): string { return JSON.stringify({downloads: root.downloadCount, active: root.activeCount}) }
    function ping(): string { return "pong" }
    function state(): string {
      var d = root.downloads.map(function(x) {
        return { id: x.dwnId, url: x.url, title: x.title, status: x.status, progress: x.progress, speed: x.speed, eta: x.eta, filepath: x.filepath }
      })
      var h = root.history.map(function(x) {
        return { id: x.dwnId, url: x.url, title: x.title, status: x.status, filepath: x.filepath, error: x.error }
      })
      return JSON.stringify({ downloads: d, history: h })
    }
  }

  Component.onCompleted: root.checkInstallation()
}