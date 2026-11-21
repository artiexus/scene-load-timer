/*
    Load Timer - times how long 3ds Max takes to open a .max file, and
    compares the file where it lives (e.g. the network) with a copy on this PC.

    Run it:   Scripting > Run Script... > LoadTimer.ms   (or drag it into a viewport)
    Results:  load_times.js next to this script; open LoadTimer.html to see the chart.

    Timing a file RESETS the scene, so save your work first (the tool asks).
*/
(
    global LoadTimerDialog
    try (destroyDialog LoadTimerDialog) catch ()

    local here = getFilenamePath (getSourceFileName())
    local resultsFile = here + "load_times.js"
    local chartFile = here + "LoadTimer.html"

    rollout LoadTimerDialog "Load Timer" width:340
    (
        edittext edtNote "Note:" text:"" width:316 align:#left
        spinner spnRuns "Opens per location:" range:[1, 10, 3] type:#integer fieldWidth:40 align:#left
        checkbox chkLocal "Also time a copy on this PC" checked:true
        edittext edtLocal "Copy to:" text:"" width:316 align:#left
        button btnGo "Pick a .max file and time it..." width:316 height:32
        button btnChart "Open the chart" width:156 across:2
        button btnClear "Clear results" width:156
        label lblStatus "Ready." align:#left width:316 height:30

        fn say msg =
        (
            lblStatus.text = msg
            windows.processPostedMessages()
        )

        fn js s =
        (
            s = substituteString (s as string) "\\" "\\\\"
            substituteString s "\"" "\\\""
        )

        fn isNetworkPath p =
        (
            if (substring p 1 2) == "\\\\" then true
            else
            (
                try
                (
                    local di = dotNetObject "System.IO.DriveInfo" (substring p 1 1)
                    (di.DriveType.ToString()) == "Network"
                )
                catch (false)
            )
        )

        fn maxYear =
        (
            local mv = maxVersion()
            if mv.count >= 8 then mv[8] else (mv[1] / 1000 + 1998)
        )

        -- Ask Windows to forget its cached copy of the file, so every open really
        -- reads from the disk or the network. Best effort: opening a file
        -- unbuffered discards its cached pages.
        fn dropCache p =
        (
            try
            (
                local noBuffering = (dotNetClass "System.Enum").ToObject (dotNet.getType "System.IO.FileOptions") 0x20000000
                local fs = dotNetObject "System.IO.FileStream" p \
                    (dotNetClass "System.IO.FileMode").Open \
                    (dotNetClass "System.IO.FileAccess").Read \
                    (dotNetClass "System.IO.FileShare").ReadWrite \
                    4096 noBuffering
                fs.Close()
                true
            )
            catch (false)
        )

        fn record session kind loc p run secs mb =
        (
            local ss = stringStream ""
            format "MAXLOAD.push({t:\"%\",session:\"%\",note:\"%\",kind:\"%\",loc:\"%\",file:\"%\",path:\"%\",run:%,secs:%,mb:%,pc:\"%\",max:%});\n" \
                ((dotNetClass "System.DateTime").Now.ToString "yyyy-MM-dd HH:mm:ss") \
                session (js edtNote.text) kind loc (js (filenameFromPath p)) (js p) run \
                (formattedPrint secs format:".3f") (formattedPrint mb format:".1f") \
                (js sysInfo.computername) (maxYear()) to:ss
            (dotNetClass "System.IO.File").AppendAllText resultsFile (ss as string)
        )

        -- Seconds to open the file from an empty scene, or undefined if it failed.
        fn timeOpen p =
        (
            resetMaxFile #noPrompt
            gc light:true
            dropCache p
            local t0 = timeStamp()
            local ok = loadMaxFile p useFileUnits:true quiet:true
            local t1 = timeStamp()
            if ok then (t1 - t0) / 1000.0 else undefined
        )

        fn timeOpens session p loc mb runs =
        (
            local ok = true
            for r = 1 to runs while ok do
            (
                say ("Opening from " + loc + ", " + r as string + " of " + runs as string + "...")
                local secs = timeOpen p
                if secs == undefined then ok = false
                else record session "open" loc p r secs mb
            )
            ok
        )

        on LoadTimerDialog open do
        (
            edtLocal.text = sysInfo.tempdir + "max_load_timer\\"
        )

        on btnGo pressed do
        (
            local go = true
            if getSaveRequired() do
                go = queryBox "Timing a file resets the scene, and this scene has unsaved changes.\n\nThrow them away and continue?" title:"Load Timer"
            local src = if go then (getOpenFileName caption:"Pick a .max file to time" types:"3ds Max (*.max)|*.max|") else undefined
            if src != undefined do
            (
                local session = (dotNetClass "System.DateTime").Now.ToString "yyyyMMdd-HHmmss"
                local mb = (getFileSize src) / 1048576.0
                local srcLoc = if isNetworkPath src then "network" else "local"
                local runs = spnRuns.value
                local ok = timeOpens session src srcLoc mb runs
                if not ok do messageBox ("3ds Max could not open:\n" + src) title:"Load Timer"

                if ok and chkLocal.checked do
                (
                    local dir = edtLocal.text
                    if dir[dir.count] != "\\" do dir += "\\"
                    makeDir dir all:true
                    local dst = dir + filenameFromPath src
                    if (toLower dst) != (toLower src) do
                    (
                        say "Copying the file to this PC..."
                        dropCache src
                        local t0 = timeStamp()
                        local copied = try ((dotNetClass "System.IO.File").Copy src dst true; true) catch (false)
                        local copySecs = (timeStamp() - t0) / 1000.0
                        if copied then
                        (
                            record session "copy" srcLoc src 1 copySecs mb
                            timeOpens session dst "local" mb runs
                            resetMaxFile #noPrompt
                            deleteFile dst
                        )
                        else messageBox ("Could not copy the file to:\n" + dir) title:"Load Timer"
                    )
                )
                resetMaxFile #noPrompt
                say "Done. Press Open the chart."
            )
        )

        on btnChart pressed do
        (
            if doesFileExist chartFile then shellLaunch chartFile ""
            else messageBox ("LoadTimer.html should sit next to this script:\n" + here) title:"Load Timer"
        )

        on btnClear pressed do
        (
            if doesFileExist resultsFile and (queryBox "Delete every recorded time?" title:"Load Timer") do
            (
                deleteFile resultsFile
                say "Results cleared."
            )
        )
    )

    createDialog LoadTimerDialog
)
