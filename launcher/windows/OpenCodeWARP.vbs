Option Explicit

' ============================================================
'  Open OpenCode through the Cloudflare WARP proxy.
'  - No console window.
'  - Sets the proxy only for OpenCode and its children.
'  - Restarts the background service so it inherits the proxy.
'  - If WARP is disconnected, tries to connect; if that fails,
'    opens OpenCode without the proxy and shows a warning.
'
'  Optional environment overrides:
'    OPENCODE_APP_PATH  full path to OpenCode.exe
'    OPENCODE_CLI_PATH  full path to opencode-cli.exe
'    WARP_CLI_PATH      full path to warp-cli.exe
' ============================================================

Dim sh, fso, appPath, cliPath, warpPath, proxyUrl, stateFile, logPath
Dim svcPid, proxyOk, i, env

Set sh = CreateObject("WScript.Shell")
Set fso = CreateObject("Scripting.FileSystemObject")

appPath = sh.ExpandEnvironmentStrings("%OPENCODE_APP_PATH%")
If appPath = "%OPENCODE_APP_PATH%" Or Not fso.FileExists(appPath) Then
  appPath = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Programs\ai.opencode.desktop\OpenCode.exe"
End If

cliPath = sh.ExpandEnvironmentStrings("%OPENCODE_CLI_PATH%")
If cliPath = "%OPENCODE_CLI_PATH%" Or Not fso.FileExists(cliPath) Then
  cliPath = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\Programs\ai.opencode.desktop\resources\opencode-cli.exe"
End If

warpPath = sh.ExpandEnvironmentStrings("%WARP_CLI_PATH%")
If warpPath = "%WARP_CLI_PATH%" Or Not fso.FileExists(warpPath) Then
  warpPath = sh.ExpandEnvironmentStrings("%ProgramFiles%") & "\Cloudflare\Cloudflare WARP\warp-cli.exe"
End If

proxyUrl = "http://127.0.0.1:40000"
stateFile = sh.ExpandEnvironmentStrings("%USERPROFILE%") & "\.local\state\opencode\service.json"
logPath = sh.ExpandEnvironmentStrings("%LOCALAPPDATA%") & "\opencode-warp-retry\launcher.log"

EnsureLogDir
Log "===== launcher started ====="

If WScript.Arguments.Named.Exists("check") Then
  WScript.Echo "proxy=" & ProxyWorks()
  WScript.Quit 0
End If

If Not fso.FileExists(appPath) Then
  MsgBox "OpenCode was not found at:" & vbCrLf & appPath & vbCrLf & vbCrLf & _
         "Set OPENCODE_APP_PATH to the full path of OpenCode.exe and try again.", _
         vbCritical, "OpenCode + WARP"
  WScript.Quit 1
End If

' If the app is already open, Windows only focuses the existing window; there is
' no way to change the environment of a process that is already running.
If ProcessRunning("OpenCode.exe") Then
  MsgBox "OpenCode is already running." & vbCrLf & vbCrLf & _
         "To use WARP, quit OpenCode completely (tray icon > Quit) and open it again from this shortcut.", _
         vbExclamation, "OpenCode + WARP"
  Log "app already running; exiting"
  WScript.Quit 0
End If

' The OpenCode service keeps running in the background even after the app closes.
' If it already exists, stop it so it restarts with the proxy environment.
svcPid = RegisteredServicePid()
If svcPid > 0 And ProcessIdRunning(svcPid) Then
  Log "old service found (PID " & svcPid & "); stopping"
  If fso.FileExists(cliPath) Then
    RunHidden """" & cliPath & """ service stop"
    WaitForPidExit svcPid, 6
  End If
  If ProcessIdRunning(svcPid) Then
    Log "service stop did not exit; using taskkill"
    RunHidden "taskkill /F /PID " & svcPid
    WScript.Sleep 1000
  End If
End If

' Test the proxy for real: request the Cloudflare trace through it.
proxyOk = ProxyWorks()

If Not proxyOk Then
  Log "proxy unavailable; trying to connect WARP"
  If fso.FileExists(warpPath) Then
    RunHidden """" & warpPath & """ connect"
    For i = 1 To 10
      WScript.Sleep 1000
      If ProxyWorks() Then
        proxyOk = True
        Exit For
      End If
    Next
  End If
End If

If proxyOk Then
  Log "proxy OK; opening OpenCode with WARP"
  Set env = sh.Environment("PROCESS")
  env("HTTP_PROXY") = proxyUrl
  env("HTTPS_PROXY") = proxyUrl
  env("ALL_PROXY") = proxyUrl
  env("NO_PROXY") = "localhost,127.0.0.1,::1"
Else
  Log "proxy still unavailable; opening without WARP"
  MsgBox "The WARP proxy is not responding." & vbCrLf & vbCrLf & _
         "OpenCode will open WITHOUT WARP now." & vbCrLf & vbCrLf & _
         "Check that WARP is connected and in proxy mode:" & vbCrLf & _
         "  warp-cli mode proxy" & vbCrLf & _
         "  warp-cli connect", _
         vbExclamation, "OpenCode + WARP"
End If

sh.CurrentDirectory = fso.GetParentFolderName(appPath)
sh.Run """" & appPath & """", 1, False
Log "OpenCode started"
WScript.Quit 0

' ==================== helpers ====================

Sub EnsureLogDir()
  On Error Resume Next
  Dim dir
  dir = fso.GetParentFolderName(logPath)
  If Not fso.FolderExists(dir) Then fso.CreateFolder dir
  Err.Clear
  On Error GoTo 0
End Sub

Sub Log(msg)
  On Error Resume Next
  Dim f
  Set f = fso.OpenTextFile(logPath, 8, True)
  f.WriteLine Now & "  " & msg
  f.Close
  Err.Clear
  On Error GoTo 0
End Sub

Sub RunHidden(cmd)
  On Error Resume Next
  sh.Run cmd, 0, True
  Err.Clear
  On Error GoTo 0
End Sub

Function ProcessRunning(name)
  Dim wmi, col, p
  ProcessRunning = False
  On Error Resume Next
  Set wmi = GetObject("winmgmts:\\.\root\cimv2")
  If Err.Number <> 0 Then Exit Function
  Set col = wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE Name='" & name & "'")
  If Err.Number = 0 Then
    For Each p In col
      ProcessRunning = True
      Exit For
    Next
  End If
  Err.Clear
  On Error GoTo 0
End Function

Function ProcessIdRunning(pid)
  Dim wmi, col
  ProcessIdRunning = False
  If pid <= 0 Then Exit Function
  On Error Resume Next
  Set wmi = GetObject("winmgmts:\\.\root\cimv2")
  Set col = wmi.ExecQuery("SELECT ProcessId FROM Win32_Process WHERE ProcessId=" & pid)
  If Err.Number = 0 Then
    If col.Count > 0 Then ProcessIdRunning = True
  End If
  Err.Clear
  On Error GoTo 0
End Function

Sub WaitForPidExit(pid, seconds)
  Dim n
  For n = 1 To seconds * 2
    If Not ProcessIdRunning(pid) Then Exit Sub
    WScript.Sleep 500
  Next
End Sub

Function RegisteredServicePid()
  Dim f, txt, parts, s, i, ch
  RegisteredServicePid = 0
  On Error Resume Next
  If Not fso.FileExists(stateFile) Then Exit Function
  Set f = fso.OpenTextFile(stateFile, 1)
  txt = f.ReadAll
  f.Close
  parts = Split(txt, """pid"":")
  If UBound(parts) >= 1 Then
    s = ""
    For i = 1 To Len(parts(1))
      ch = Mid(parts(1), i, 1)
      If ch >= "0" And ch <= "9" Then
        s = s & ch
      ElseIf Len(s) > 0 Then
        Exit For
      End If
    Next
    If Len(s) > 0 Then RegisteredServicePid = CLng(s)
  End If
  Err.Clear
  On Error GoTo 0
End Function

Function ProxyWorks()
  Dim wh, txt
  ProxyWorks = False
  On Error Resume Next
  Set wh = CreateObject("WinHttp.WinHttpRequest.5.1")
  If Err.Number <> 0 Then Exit Function
  wh.SetTimeouts 1500, 1500, 2500, 4000
  wh.SetProxy 2, "127.0.0.1:40000"
  wh.Open "GET", "https://www.cloudflare.com/cdn-cgi/trace", False
  wh.Send
  If Err.Number = 0 Then
    txt = wh.ResponseText
    If InStr(1, txt, "warp=on", vbTextCompare) > 0 Then ProxyWorks = True
  End If
  Err.Clear
  On Error GoTo 0
End Function
