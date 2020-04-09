#define fbc -dll -x "Annoying.dll"

#include "Windows.bi"

extern "windows-ms"
' Pause the thread without locking the window
Sub TimedWait(iDelay as integer)
    Dim as MSG msg = any
    Dim as DWORD dwStartTime, dwNewTicks
    
    dwStartTime = GetTickCount()
    do
        while (PeekMessage(@msg, NULL, 0, 0, PM_REMOVE))
            TranslateMessage(@msg)
            DispatchMessage(@msg)
        wend
        
        dwNewTicks = GetTickCount()
        sleep 1,1
    loop until abs(dwStartTime-dwNewTicks) > iDelay
End Sub

Sub ShiftDown(ip as INPUT_)
    ip.ki.wScan = MapVirtualKey(VK_SHIFT, MAPVK_VK_TO_VSC)
    ip.ki.wVk = VK_SHIFT
    ip.ki.dwFlags = 0
    SendInput(1, @ip, SizeOf(ip))
    ip.ki.wScan = 0
End Sub

Sub ShiftUp(ip as INPUT_)
    ip.ki.wScan = MapVirtualKey(VK_SHIFT, MAPVK_VK_TO_VSC)
    ip.ki.wVk = VK_SHIFT
    ip.ki.dwFlags = KEYEVENTF_KEYUP
    SendInput(1, @ip, SizeOf(ip))
    ip.ki.wScan = 0
End Sub

Sub TypeWord(sInput as string)
    Dim as INPUT_ ip
    ip.type = INPUT_KEYBOARD

    For X as Integer = 0 to len(sInput)-1
        Select Case sInput[X]
        Case asc("A") to asc("Z") 'put down shift key
            ShiftDown(ip)
            
        Case asc("!"), asc("@"), asc("#"), asc("$"), asc("%"), asc("^"), _
             asc("&"), asc("*"), asc("("), asc(")"), asc("_"), asc("+"), _
             asc("|"), asc("}"), asc("{"), asc("~"), asc("<"), asc(">"), _
             asc("?"), asc(":"), asc("""")
            ShiftDown(ip)
            
        Case 13, 10
            Continue For
            
        end select
            
        ' Get scancode from ASCII and type key
        var key = VkKeyScanEx(sInput[X], 0)
        ip.ki.wVk = key
        ip.ki.dwFlags = 0
        SendInput(1, @ip, SizeOf(ip))

        TimedWait(150)
        
        ip.ki.dwFlags = KEYEVENTF_KEYUP
        SendInput(1, @ip, SizeOf(ip))
        ShiftUp(ip)
        
        TimedWait(100)
    Next X
End Sub

Sub SloppyType(sInput as string)
    Dim as INPUT_ ip
    ip.type = INPUT_KEYBOARD

    ' Type 2 letters at a time ignoring case
    For X as Integer = 0 to len(sInput)-1 step 2
        ip.ki.dwFlags = 0 ' Key down

        ip.ki.wVk = VkKeyScanEx(sInput[X], 0)
        SendInput(1, @ip, SizeOf(ip))
        
        ip.ki.wVk = VkKeyScanEx(sInput[X+1], 0)
        SendInput(1, @ip, SizeOf(ip))
        
        TimedWait(150)
        
        ip.ki.dwFlags = KEYEVENTF_KEYUP
        SendInput(1, @ip, SizeOf(ip))
        
        ip.ki.wVk = VkKeyScanEx(sInput[X], 0)
        SendInput(1, @ip, SizeOf(ip))
        
        TimedWait(100)
    Next X
End Sub

Sub ButtonMash()
    Dim as zString*11 szKeyMash
    for iX as integer = 0 to 8 step 2
        szKeyMash[iX] = (asc("a") + rnd*25) OR 1
        szKeyMash[iX+1] = (asc("a") + rnd*26) AND NOT(1)
    next iX
    
    SloppyType(szKeyMash)
End Sub

' Called by Typocat to do something annoying
Sub AnnoyProc() export
    Dim as integer iAnnoyMode = int(rnd*2)
    Select Case iAnnoyMode
    Case 0
        ButtonMash()
    Case 1
        TypeWord("Meow")
    End Select
End Sub

' Initalize the randomizer
Sub InitAnnoying() export
    randomize timer
End Sub

end extern
