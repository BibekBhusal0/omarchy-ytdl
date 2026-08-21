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
  readonly property int queuedCount: {
    var n = 0
    for (var i = 0; i < downloads.length; i++) {
      if (downloads[i].status === "queued")
        n++
    }
    return n
  }

  // Playlist resolution state. Enumerated videos are queued into `downloads`
  // like any other download (status "queued") and start as procs free up.
  property string _playlistQuality: "1080p"
  property string _playlistError: ""

  // "Playlist detected" preview: name and video count for URLs carrying a
  // `list=` param, resolved lazily from the panel input.
  property string playlistInfoUrl: ""
  property string playlistInfoName: ""
  property int playlistInfoCount: 0
  property bool playlistInfoLoading: false
  property bool playlistInfoError: false
  property int _playlistInfoReq: 0

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
      property string _quality: "1080p"
      property bool _playlistItem: false
      property bool _playlistPlaceholder: false
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
    return /(?:https?:\/\/)?(?:www\.)?(?:youtube\.com\/(?:watch\?v=|shorts\/|playlist\?list=)|youtu\.be\/)[\w-]+/.test(text)
  }

  // A pure playlist URL (no video id) downloads the whole playlist. Watch URLs
  // copied from a playlist page (v=...&list=...) download just that video; the
  // "Playlist detected" panel section offers the playlist separately.
  function isPlaylistUrl(url) {
    if (!/[?&]list=/.test(url)) return false
    return !root.extractVideoId(url)
  }

  // True when `url` is already downloading or waiting in the queue. Matches by
  // video id too, so a watch URL copied with a `list=` param is seen as the
  // same download as its bare-watch twin already in progress.
  function isUrlBusy(url) {
    url = cleanUrl(url)
    var vid = root.extractVideoId(url)
    for (var i = 0; i < downloads.length; i++) {
      var d = downloads[i]
      var s = d.status
      if (s !== "downloading" && s !== "merging" && s !== "queued") continue
      if (d.url === url) return true
      if (vid && root.extractVideoId(d.url) === vid) return true
    }
    return false
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
      var p = procAt(i)
      if (!p._draining && !p.running) return i
    }
    return -1
  }

  // Self-heal proc/download desyncs that a race can leave behind (e.g. a
  // process kept running after its record was cancelled, or a promoted item
  // whose record lost its "downloading" status). If a proc has a live process
  // but no record tracks it, reattach it to the queued item for the same video
  // so it shows as active; if none matches, kill the stray process. Runs on a
  // short timer so any desync repairs itself within a tick.
  function reconcileProcs() {
    for (var i = 0; i < 3; i++) {
      var p = procAt(i)
      if (!p.running) continue
      var tracked = false
      for (var j = 0; j < downloads.length; j++) {
        if (downloads[j].status === "downloading" && downloads[j].procIdx === i) {
          tracked = true
          break
        }
      }
      if (tracked) continue
      var pvid = root.extractVideoId(p._url)
      var target = -1
      for (var k = 0; k < downloads.length; k++) {
        var q = downloads[k]
        if (q.status !== "queued") continue
        if (pvid && root.extractVideoId(q.url) === pvid) { target = k; break }
      }
      if (target >= 0) {
        var t = downloads[target]
        p.downloadId = t.dwnId
        p._errBuf = ""
        t.procIdx = i
        t.status = "downloading"
        downloadsUpdated()
      } else {
        var pid = p.processId
        if (pid && typeof pid === "number" && pid > 0)
          Quickshell.execDetached([scriptPath, "kill-tree", String(pid)])
        p._draining = true
      }
    }
  }

  function startDownload(url, quality, isPlaylistItem, knownTitle) {
    url = cleanUrl(url)
    if (!url) return
    if (!isPlaylistItem && root.isPlaylistUrl(url)) {
      root.startPlaylist(url, quality)
      return
    }

    // Skip if an active or queued entry already carries this URL. Match by
    // video id too, so a watch URL copied with a `list=` param is seen as the
    // same download as its bare-watch twin already in progress. Without this a
    // video can end up with two records (one running, one queued) and the
    // queued copy looks like it downloads by itself.
    var vid = root.extractVideoId(url)
    for (var i = 0; i < downloads.length; i++) {
      var s = downloads[i].status
      if (s !== "downloading" && s !== "merging" && s !== "queued") continue
      if (downloads[i].url === url) return
      if (vid && root.extractVideoId(downloads[i].url) === vid) return
    }

    var id = Date.now() + Math.floor(Math.random() * 1000)
    var q = quality || defaultQuality
    var outputTemplate = downloadLocation + "/%(title)s.%(ext)s"
    var cmd = [scriptPath, "download", url, q, outputTemplate, cookiesBrowser, extraArgs]

    var d = downloadComp.createObject(root)
    d.dwnId = id
    d.url = url
    d.title = knownTitle || extractVideoId(url) || url
    d.procIdx = -1
    d._quality = q
    d._playlistItem = !!isPlaylistItem

    var procIdx = findFreeProc()
    if (procIdx === -1) {
      // All three slots busy: sit in the queue until one frees up. Fetch the
      // title now so the queue shows a real name instead of a video id; the
      // Destination line only appears once the download actually runs.
      d.status = "queued"
      downloads = downloads.concat([d])
      downloadsUpdated()
      root._fetchTitle(id, url)
      return
    }

    downloads = downloads.concat([d])
    downloadsUpdated()

    var proc = procAt(procIdx)
    proc.downloadId = id
    proc._errBuf = ""
    proc._url = url
    proc.command = cmd
    proc.running = true
    d.procIdx = procIdx

    root._fetchTitle(id, url)
  }

  // Start queued downloads on any free procs, in FIFO order. Called whenever a
  // proc frees up (a download completes or is cancelled).
  function _startNextQueued() {
    for (var i = 0; i < downloads.length; i++) {
      if (downloads[i].status !== "queued") continue
      var procIdx = findFreeProc()
      if (procIdx === -1) return
      var d = downloads[i]
      var outputTemplate = downloadLocation + "/%(title)s.%(ext)s"
      var cmd = [scriptPath, "download", d.url, d._quality, outputTemplate, cookiesBrowser, extraArgs]
      var proc = procAt(procIdx)
      proc.downloadId = d.dwnId
      proc._errBuf = ""
      proc._url = d.url
      proc.command = cmd
      proc.running = true
      d.procIdx = procIdx
      d.status = "downloading"
      downloadsUpdated()
      root._fetchTitle(d.dwnId, d.url)
    }
  }

  function clearQueue() {
    var remaining = []
    for (var i = 0; i < downloads.length; i++) {
      if (downloads[i].status !== "queued") remaining.push(downloads[i])
    }
    downloads = remaining
    downloadsUpdated()
  }

  function removeQueued(id) {
    for (var i = 0; i < downloads.length; i++) {
      if (downloads[i].dwnId === id && downloads[i].status === "queued") {
        downloads = removeById(downloads, id)
        downloadsUpdated()
        return
      }
    }
  }

  function cancelAll() {
    var ids = []
    for (var i = 0; i < downloads.length; i++) {
      if (downloads[i].status === "downloading" || downloads[i].status === "merging")
        ids.push(downloads[i].dwnId)
    }
    for (var j = 0; j < ids.length; j++)
      root.cancelDownload(ids[j])
  }

  // Resolve a playlist to its individual videos, then queue them as normal
  // downloads (they start as procs free up, like any pasted video). A
  // placeholder entry gives feedback while the flat enumeration runs.
  function startPlaylist(url, quality) {
    root._playlistQuality = quality || defaultQuality
    root._playlistError = ""
    var id = Date.now() + Math.floor(Math.random() * 1000)
    var d = downloadComp.createObject(root)
    d.dwnId = id
    d.url = url
    d.title = "Resolving playlist\u2026"
    d.procIdx = -1
    d._playlistPlaceholder = true

    downloads = downloads.concat([d])
    downloadsUpdated()

    playlistProc.downloadId = id
    playlistProc.command = [scriptPath, "playlist-items", url, cookiesBrowser, extraArgs]
    playlistProc.running = true
  }

  // Resolve a playlist's title and video count for the "Playlist detected"
  // panel preview. Debounced by the panel; stale in-flight fetches are dropped
  // via a request counter, so a fast retype can't surface an old result.
  function fetchPlaylistInfo(url) {
    url = cleanUrl(url)
    // Only video URLs copied from a playlist page (v=...&list=...) need the
    // preview; a bare playlist URL downloads the whole playlist via the main
    // button already, so there is nothing to surface.
    if (!url || !/[?&]list=/.test(url) || !root.extractVideoId(url)) {
      root.clearPlaylistInfo()
      return
    }
    root._playlistInfoReq++
    if (playlistInfoProc.running) playlistInfoProc.running = false
    playlistInfoProc._req = root._playlistInfoReq
    playlistInfoProc.command = [scriptPath, "playlist-info", url, cookiesBrowser, extraArgs]
    playlistInfoProc.running = true
    root.playlistInfoUrl = url
    root.playlistInfoName = ""
    root.playlistInfoCount = 0
    root.playlistInfoLoading = true
    root.playlistInfoError = false
  }

  function clearPlaylistInfo() {
    root.playlistInfoUrl = ""
    root.playlistInfoName = ""
    root.playlistInfoCount = 0
    root.playlistInfoLoading = false
    root.playlistInfoError = false
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
        if (d.status === "queued") {
          root.downloads = root.removeById(root.downloads, id)
          root.downloadsUpdated()
          return
        }
        if (d._playlistPlaceholder) {
          if (playlistProc.running) playlistProc.running = false
          playlistProc.downloadId = -1
          root.downloads = root.removeById(root.downloads, id)
          root.downloadsUpdated()
          return
        }
        if (d.procIdx >= 0) {
          var proc = procAt(d.procIdx)
          var pid = proc.processId
          proc.downloadId = -1
          if (proc.running) {
            // Mark the proc as draining so no new download starts on it until
            // its process has actually exited (onExited clears the flag).
            proc._draining = true
            proc.running = false
          }
        }
        if (d.filepath) {
          if (pid && typeof pid === "number" && pid > 0) {
            // Kill the whole tree (shell + yt-dlp + ffmpeg), wait for it to
            // die, then drop the partials. Quickshell only SIGTERMs the direct
            // child, which would otherwise orphan yt-dlp and leave it
            // downloading in the background.
            Quickshell.execDetached([scriptPath, "cancel", String(pid), d.filepath])
          } else {
            Quickshell.execDetached([scriptPath, "cleanup", d.filepath])
          }
        }
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
        // A proc just freed up (or its exit is imminent); let a queued download
        // take its slot. Promotion is retried once the process exits.
        Qt.callLater(root._startNextQueued)
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
        // A proc just freed up; let a queued download take its slot.
        Qt.callLater(root._startNextQueued)
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

  // Title fetch process. `_fetchId` records the entry this process was started
  // for; the result is only applied if it still matches, so a stale fetch that
  // raced a new download can't overwrite the new entry's title. `_titleQueue`
  // holds pending lookups (queued items plus downloads that missed their slot)
  // and is drained one fetch at a time so every entry gets a real title.
  property var _titleQueue: []
  Process {
    id: titleProc
    property var targetId: -1
    property var _fetchId: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var title = String(this.text || "").trim()
        if (title && titleProc.targetId !== -1 && titleProc.targetId === titleProc._fetchId) {
          root.updateDownload(titleProc.targetId, { title: title })
        }
        titleProc.targetId = -1
        titleProc._fetchId = -1
        Qt.callLater(root._pumpTitle)
      }
    }
  }

  // Queue a title fetch for `id` and pump the next one if the process is free.
  // Idempotent per entry: skip requests for entries that already carry a real
  // title (playlist items, or one applied by a previous fetch or the
  // Destination line).
  function _fetchTitle(id, url) {
    if (id === -1 || !url) return
    for (var i = 0; i < downloads.length; i++) {
      var d = downloads[i]
      if (d.dwnId === id && d.title && d.title !== d.url && d.title !== root.extractVideoId(d.url))
        return
    }
    for (var j = 0; j < _titleQueue.length; j++) {
      if (_titleQueue[j].id === id) return
    }
    _titleQueue.push({ id: id, url: url })
    root._pumpTitle()
  }

  function _pumpTitle() {
    if (titleProc.running || _titleQueue.length === 0) return
    var item = _titleQueue.shift()
    titleProc.targetId = item.id
    titleProc._fetchId = item.id
    titleProc.command = [scriptPath, "title", item.url, cookiesBrowser, extraArgs]
    titleProc.running = true
  }

  // Playlist metadata fetch for the "Playlist detected" panel preview. The
  // request counter in `_req` ties results to the fetch that started them.
  Process {
    id: playlistInfoProc
    property int _req: -1
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        if (playlistInfoProc._req !== root._playlistInfoReq) return
        var parts = String(this.text || "").trim().split("\t")
        if (parts.length >= 2 && parts[0]) {
          root.playlistInfoName = parts[0]
          root.playlistInfoCount = parseInt(parts[1], 10) || 0
          root.playlistInfoError = false
        } else {
          root.playlistInfoError = true
        }
        root.playlistInfoLoading = false
      }
    }
    onExited: function(exitCode) {
      if (playlistInfoProc._req !== root._playlistInfoReq) return
      if (exitCode !== 0) {
        root.playlistInfoError = true
        root.playlistInfoLoading = false
      }
    }
  }

  // Playlist enumeration process. Flat-resolves the playlist to a JSON array
  // of {id, title, url}; each entry is then queued as its own download.
  Process {
    id: playlistProc
    property var downloadId: -1
    property string _errBuf: ""
    stdout: StdioCollector {
      waitForEnd: true
      onStreamFinished: {
        var id = playlistProc.downloadId
        playlistProc.downloadId = -1
        if (id === -1) return
        var items = []
        var text = String(this.text || "").trim()
        if (text) {
          try {
            var parsed = JSON.parse(text)
            if (Array.isArray(parsed)) {
              for (var i = 0; i < parsed.length; i++) {
                var it = parsed[i] || {}
                if (it.url) {
                  items.push({ url: it.url, title: it.title || "", quality: root._playlistQuality })
                }
              }
            }
          } catch (e) { /* malformed enumeration output, treat as empty */ }
        }
        if (items.length === 0) {
          // Resolution failed; surface the error on the placeholder entry.
          var err = root._playlistError || "Could not resolve playlist"
          for (var j = 0; j < root.downloads.length; j++) {
            var d = root.downloads[j]
            if (d.dwnId === id) {
              d.status = "error"
              d.error = err
              root.downloads = root.removeById(root.downloads, id)
              if (root.enableHistory) {
                root.history = [d].concat(root.history)
                root.persistHistory()
              }
              root.historyUpdated()
              root.downloadsUpdated()
              break
            }
          }
        } else {
          root.downloads = root.removeById(root.downloads, id)
          root.downloadsUpdated()
          // Queue every video as its own download; up to three start now and
          // the rest wait for a free slot.
          for (var k = 0; k < items.length; k++)
            root.startDownload(items[k].url, items[k].quality, true, items[k].title)
        }
      }
    }
    stderr: SplitParser {
      onRead: function(line) {
        playlistProc._errBuf += line + "\n"
        if (line.indexOf("ERROR") !== -1)
          root._playlistError = line.replace(/^ERROR:\s*/, "")
      }
    }
  }

  Process {
    id: dlProc0
    objectName: "dlProc0"
    property var downloadId: -1
    property string _errBuf: ""
    property bool _draining: false
    property string _url: ""
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
      dlProc0._url = ""
      dlProc0._draining = false
      // The process really exited now, so a queued download can take its slot.
      Qt.callLater(root._startNextQueued)
    }
  }

  Process {
    id: dlProc1
    objectName: "dlProc1"
    property var downloadId: -1
    property string _errBuf: ""
    property bool _draining: false
    property string _url: ""
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
      dlProc1._url = ""
      dlProc1._draining = false
      Qt.callLater(root._startNextQueued)
    }
  }

  Process {
    id: dlProc2
    objectName: "dlProc2"
    property var downloadId: -1
    property string _errBuf: ""
    property bool _draining: false
    property string _url: ""
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
      dlProc2._url = ""
      dlProc2._draining = false
      Qt.callLater(root._startNextQueued)
    }
  }

  // Watchdog for proc/download desyncs (see reconcileProcs). Fires rarely; the
  // cost is a scan of 3 procs and the downloads list.
  Timer {
    id: reconcileTimer
    interval: 2000
    repeat: true
    running: true
    onTriggered: root.reconcileProcs()
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