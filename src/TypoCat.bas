''''''''''''''''''''''''''''''''''''
'           Typo The Cat           '
'                                  '
' (C) Copyright Graham Downey 2020 '
''''''''''''''''''''''''''''''''''''
#define fbc -s gui typocat.rc
#include "windows.bi"
#include "win\winuser.bi"
#include "win\shellapi.bi"
#include "dir.bi"
#include "crt.bi"

#include "DoubleBuffer.bas"

#define ShowDebug 0
Declare Function createWindowRegion(hdcSource as HDC, bmSource as BITMAP, clrTrans as COLORREF = BGR(255, 0, 255)) as HRGN
Declare Sub WinMain(hInstance as HINSTANCE, hPrevInstance as HINSTANCE, szCmdLine as PSTR, iCmdShow as Integer)
Declare Sub loadSkin(hDC as HDC, sSkinPath as string)
Declare Sub loadSettings()

Const WINDOW_WIDTH = 320, WINDOW_HEIGHT = 240
Dim shared as HWND hwndMain, hWndSkinSelect
static shared as HRGN hRgnMain, hRgnLeft, hRgnRight, hRgnBoth
Dim Shared as HINSTANCE hInstance
Dim Shared as String szAppName
Dim Shared as String szCaption

' Context menu items
enum ContextMenuCommands
    CMC_SKINS
    CMC_CUSTOMLR
    CMC_QUIT
end enum

const SKIN_CFG = "\TypoSkin.ini"
enum CatBitmaps
    CBM_WAITING = 0
    CBM_LEFT
    CBM_RIGHT
    CBM_BOTH
    CBM_LAST  
end enum
Const as integer TOTAL_CATS = CBM_LAST-1        ' Number of frames of cat animation
Dim shared as integer iCatPic = CBM_WAITING     ' Current cat pic being displayed
Dim shared as integer iSelectedSkin = -1        ' index of currently selected skin
Dim shared as string sCurSkin                   ' Directory of current skin
Dim shared as BITMAP bmCatBitmap                ' Bitmap info struct
Dim shared as HBITMAP hbmCatBitmaps(TOTAL_CATS) ' Bitmap handle for each frame

Dim shared as integer iCustomLeftRight = TRUE ' Distinguish left/right shift/ctrl

hInstance = GetModuleHandle(NULL)
szAppName = "Typo Cat"
szCaption = "Typo Cat"

'Launch into WinMain()
dim as string sCommand = ""'Command ' Command doesn't work on win32s rtlib
WinMain(hInstance, NULL, sCommand, SW_NORMAL)

#include "SkinPicker.bas"

Function WndProc (hWnd as HWND, iMsg as uLong, wParam as WPARAM, lParam as LPARAM) as LRESULT
    Static as HMENU hContextMenu
    
    Select Case iMsg
    Case WM_CREATE
        hwndMain = hWnd
        setDoubleBuffer(hWnd) ' Prevents flickering
        
        '**** Center window on desktop ****'
        Scope   'Calculate Client Area Size
            Dim as rect RcWnd = any, RcCli = Any, RcDesk = any
            GetClientRect(hWnd, @RcCli)
            GetClientRect(GetDesktopWindow(), @RcDesk)
            GetWindowRect(hWnd, @RcWnd)
            'Window Rect is in SCREEN coordinate.... make right/bottom become WID/HEI
            with RcWnd
                .right -= .left: .bottom -= .top
                .right += (.right-RcCli.right)  'Add difference cli/wnd
                .bottom += (.bottom-RcCli.bottom)   'add difference cli/wnd
                var CenterX = (RcDesk.right-.right)\2
                var CenterY = (RcDesk.bottom-.bottom)\2
                SetWindowPos(hwnd,null,CenterX,CenterY,.right,.bottom,SWP_NOZORDER)
            end with
        end Scope        

        ' Create right click context menu
        hContextMenu = CreatePopupMenu()
        AppendMenu(hContextMenu, MF_STRING, CMC_SKINS, @"Skin...")
        dim as integer iChecked = 0' Set checked state to that of iCustomLeftRight
        if iCustomLeftRight then iChecked = MF_CHECKED
        AppendMenu(hContextMenu, MF_STRING OR iChecked, CMC_CUSTOMLR, @"Distinguish left/right")
        AppendMenu(hContextMenu, MF_SEPARATOR, NULL, NULL)
        AppendMenu(hContextMenu, MF_STRING, CMC_QUIT, @"Quit") 

        ' Load cat skin
        var hDC = GetDC(hWnd)
        loadSkin(hDC, sCurSkin)
        ReleaseDC(hWnd, hDC)
        return 0
        
    Case WM_PAINT
        Dim as PAINTSTRUCT ps
        var hDC = BeginPaint(hWnd, @ps)
        hDC = iif(wParam, cast(HDC,wparam), ps.hDC) ' Required for double buffer hook
        
        ' Draw cat to window
        dim as HDC hdcMem = CreateCompatibleDC(hDC)
        var hOld = SelectObject(hdcMem, hbmCatBitmaps(iCatPic))
        with bmCatBitmap
            BitBlt(hDC, 0, 0, .bmWidth, .bmHeight, hdcMem, 0, 0, SRCCOPY)
        end with
        SelectObject(hdcMem, hOld)
        DeleteDC(hdcMem)
        
        EndPaint(hWnd, @ps)
        return 0
             
    Case WM_CONTEXTMENU
        dim as integer iX = LOWORD(lParam)
        dim as integer iY = HIWORD(lParam)
        TrackPopupMenuEx(hContextMenu, NULL, iX, iY, hWnd, NULL)
    
    Case WM_NCHITTEST
        if (GetAsyncKeyState(VK_LBUTTON) AND &H8000) then
            return HTCAPTION ' Enable dragging whenever client left clicked
        end if
        return HTCLIENT ' Right click client area sends us WM_CONTEXTMENU
    
    Case WM_DROPFILES
        var hDrop = cast(HANDLE, wParam)
        dim as zstring*256 szName
        dim as integer iChar = DragQueryFile(hDrop, 0, @szName, 256)
        
        iSelectedSkin = -1 ' No longer selected from select menu
        
        ' This assumes szName is a directory containing typoskin.ini
        var hDC = GetDC(hWnd)
        loadSkin(hDC, szName)
        ReleaseDC(hWnd, hDC)

        DragFinish(hDrop) ' Free handle
        
    Case WM_COMMAND
        Select Case HIWORD(wParam) ' wNotifyCode
        Case 0 ' Context menu clicked
            Select Case LOWORD(wParam) ' wID of menu item
            Case CMC_SKINS ' Show skin picker
                dim as RECT r, rcDesk
                GetWindowRect(hWnd, @r) ' Position window over cat window
                GetClientRect(GetDesktopWindow(), @rcDesk)
                if r.left+WINDOW_WIDTH > rcDesk.right then
                    r.left = rcDesk.right-WINDOW_WIDTH
                elseif r.left < rcDesk.left then
                    r.left = rcDesk.left
                end if
                
                if r.top+WINDOW_HEIGHT > rcDesk.bottom then
                    r.top = rcDesk.bottom-WINDOW_HEIGHT
                end if

                ShowWindow(hWnd, SW_HIDE)
                ShowWindow(hWndSkinSelect, SW_SHOW)
                SetWindowPos(hWndSkinSelect, 0, r.left, r.top, 0, 0, SWP_NOSIZE OR SWP_NOZORDER)
                
            Case CMC_CUSTOMLR
                if iCustomLeftRight then
                    CheckMenuItem(hContextMenu, CMC_CUSTOMLR, MF_UNCHECKED)
                    iCustomLeftRight = FALSE
                else
                    CheckMenuItem(hContextMenu, CMC_CUSTOMLR, MF_CHECKED)
                    iCustomLeftRight = TRUE
                end if
                
            Case CMC_QUIT
                DestroyWindow(hWnd) ' Quit when quit clicked
                
            End Select
        End Select
        
    Case WM_DESTROY
        PostQuitMessage(0)
        return 0
        
    End Select
    
    return DefWindowProc(hWnd, iMsg, wParam, lParam)
End Function

const KD_LEFT  = 1, _
      KD_RIGHT = 2, _
      KD_BOTH  = 3, _
      KD_NONE  = 0
      
' https://docs.microsoft.com/en-us/windows/win32/inputdev/virtual-key-codes
Function CheckKeyStates() as integer
    dim as integer iKeyStates = 0
    ' &HBA-&HBF for extended keys needed
    ' &HC0 = ~
    ' &HDB-DE for '"', {}, [] etc.
        
    for iK as integer = 8 to &HDE ' VK_OEM_7 ' the '"' key 
        Select Case iK   ' Skip undefined/trouble keys
        Case &H0A to &H0C, &HE, &HF, &H15 to &H1A, &H1C to &H1F, _
             &H3A to &H40, &H5E, &H88 to &H8F, &H92 to &H9F, _
             &HA6 to &HB9, &HC1 to &HDA
            Continue For
                     
        Case VK_SHIFT, VK_CONTROL, VK_MENU ' Skip if we're checking specific left/right
            if iCustomLeftRight then continue for
            
        End Select
        
        if (GetAsyncKeyState(iK) AND &H8000) then
            ' Generic shift/ctrl/menu will put down both arms
            if iK = VK_SHIFT orElse iK = VK_CONTROL orElse iK = VK_MENU then
                iKeyStates OR= KD_RIGHT OR KD_LEFT
            end if
            
            if (iK AND 1) then ' Odd keys
                iKeyStates OR= KD_RIGHT
            else               ' Even keys
                iKeyStates OR= KD_LEFT
            end if
        end if
    next iK
    return iKeyStates
End Function

' Called by Windows every ~10ms
Sub TimerProc(hWnd as HWND, uMsg as uinteger, idEvent as uinteger, dwTime as long)
    Static as integer iLastState ' Last state of cat

    'Process global key presses
    var iResult = CheckKeyStates()

    ' Set state of cat if it's changed
    if iLastState <> iResult then
        iLastState = iResult

        Dim as HRGN hRgn = CreateRectRgn(0, 0, 0, 0)
        if iResult = KD_BOTH then
            iCatPic = CBM_BOTH
            CombineRgn(hRgn, hRgnBoth, NULL, RGN_COPY)
                
        elseif iResult = KD_LEFT then
            iCatPic = CBM_LEFT
            CombineRgn(hRgn, hRgnLeft, NULL, RGN_COPY)
            
        elseif iResult = KD_RIGHT then
            iCatPic = CBM_RIGHT
            CombineRgn(hRgn, hRgnRight, NULL, RGN_COPY)
        
        else ' KD_NONE
            iCatPic = CBM_WAITING
            CombineRgn(hRgn, hRgnMain, NULL, RGN_COPY)
        end if
        
        SetWindowRgn(hWnd, hRgn, TRUE)
        InvalidateRect(hWnd, NULL, TRUE)
    end if
End Sub

Sub WinMain(hInstance as HINSTANCE, hPrevInstance as HINSTANCE, _
            szCmdLine as PSTR, iCmdShow as Integer)
      
    Dim as HWND       hWnd
    Dim as MSG        msg
    Dim as WNDCLASSEX wcls

    ' Initalize skin picker menu
    hWndSkinSelect = initPickerWindow(hInstance)
    LoadSettings() ' Load the app settings from config.ini

    ' Set up main cat window class
    wcls.cbSize        = sizeof(WNDCLASSEX)
    wcls.style         = CS_HREDRAW OR CS_VREDRAW
    wcls.lpfnWndProc   = cast(WNDPROC, @WndProc)
    wcls.cbClsExtra    = 0
    wcls.cbWndExtra    = 0
    wcls.hInstance     = hInstance
    wcls.hIcon         = LoadIcon(hInstance, "FB_PROGRAM_ICON") 
    wcls.hCursor       = LoadCursor(NULL, IDC_ARROW)
    wcls.hbrBackground = cast(HBRUSH, COLOR_BTNFACE + 1)
    wcls.lpszMenuName  = NULL
    wcls.lpszClassName = strptr(szAppName)
    wcls.hIconSm       = LoadIcon(hInstance, "FB_PROGRAM_ICON")
    
    if (RegisterClassEx(@wcls) = FALSE) then
        Print "Error! Failed to register window class ", Hex(GetLastError())
        sleep: system
    end if
    
    const WINDOW_STYLE = WS_POPUP OR WS_SYSMENU
    const WINDOW_STYLE_EX = WS_EX_TOPMOST OR WS_EX_TOOLWINDOW OR WS_EX_ACCEPTFILES
 
    hWnd = CreateWindowEx(WINDOW_STYLE_EX, _      ' Window extended style
                          szAppName, _            ' window class name
                          szCaption, _            ' Window caption
                          WINDOW_STYLE, _         ' Window style
                          CW_USEDEFAULT, _        ' Initial X position
                          CW_USEDEFAULT, _        ' Initial Y Posotion
                          WINDOW_WIDTH, _         ' Window width
                          WINDOW_HEIGHT, _        ' Window height
                          NULL, _                 ' Parent window handle
                          NULL, _                 ' Window menu handle
                          hInstance, _            ' Program instance handle
                          NULL)                   ' Creation parameters
                        
    if hWnd = NULL then system
            
    ShowWindow(hWnd, iCmdShow)
    UpdateWindow(hWnd)
    
    ' Set key checker timer
    SetTimer(hWnd, 1, 10, cast(TIMERPROC, @TimerProc))
    
    while (GetMessage(@msg, NULL, 0, 0))
        TranslateMessage(@msg)
        DispatchMessage(@msg)
    wend

    ' Delete bitmaps before quitting
    for i as integer = 0 to TOTAL_CATS
        DeleteObject(hbmCatBitmaps(i))
    next i
    
    ' Save settings to config.ini
    dim as string sCfgPath = exePath+"\config.ini"
    dim as string sSkin = "default"
    if iSelectedSkin > 0 then
        sSkin = skins(iSelectedSkin).sDir
    end if
    WritePrivateProfileString("default", "skin", sSkin, sCfgPath)
     
    dim as string sCustomLR = iif(iCustomLeftRight, "true", "false") 
    WritePrivateProfileString("default", "customLR", sCustomLR, sCfgPath)
    
    system msg.wParam
End Sub

' Create window region based on passed bitmap
Function createWindowRegion(hdcSource as HDC, bmSource as BITMAP, _
                            clrTrans as COLORREF = BGR(255, 0, 255)) as HRGN
    var hBmp = GetCurrentObject(hdcSource, OBJ_BITMAP)
    
    ' Allocate memory for raw bitmap data
    var pBmp = cast(COLORREF ptr, malloc(bmSource.bmWidth*bmSource.bmHeight*sizeOf(COLORREF)))
    
    dim as BITMAPINFO tBmpInfo
    with tBmpInfo.bmiHeader
        .biSize = sizeof(BITMAPINFOHEADER)
        .biWidth = bmSource.bmWidth
        .biHeight = -bmSource.bmHeight  ' Hurray for upside down bitmaps!
        .biBitCount = 32: .biPlanes = 1 ' Create 32bit bitmaps for easy parsing
    end with
    
    ' Copy raw bitmap data into 32bpp buffer
    GetDIBits(hdcSource, .hBmp, 0, bmSource.bmHeight, pBmp, @tBmpInfo, DIB_RGB_COLORS)
    
    ' Temp structure to store RECTs (initially allocate room fro 1022 rects)
    const InitRcs = 1024-(sizeof(RGNDATAHEADER)\sizeof(RECT)) ' allocate multiples of 4kb
    var iCurBytes = sizeof(RGNDATAHEADER), iMaxBytes = iCurBytes+InitRcs*sizeof(RECT)
    var pAlloc = malloc(iMaxBytes), iRc = 0, pRc = cast(RECT ptr, pAlloc+iCurBytes)
    
    ' Locate opaque rects
    dim as integer iX = 0
    dim as integer ipxPos = 0 ' offset of current pixel in bitmap data
    for iY as integer = 0 to bmSource.bmHeight-1
        do
            ' Skip transparent pixels
            while (iX < bmSource.bmWidth AndAlso pBmp[ipxPos] = clrTrans)
                iX += 1: ipxPos += 1
            wend
            
            ' Count how many pixels wide opaque area is
            dim as integer iLeft = iX
            while (iX < bmSource.bmWidth AndAlso pBmp[ipxPos] <> clrTrans)
                iX += 1: ipxPos += 1
            wend
            
            ' Resize RECT buffer if max reached
            if iCurBytes >= iMaxBytes then
                iMaxBytes += 512*sizeof(RECT)
                pAlloc = realloc(pAlloc, iMaxBytes)
                pRc = cast(RECT ptr, pAlloc+iCurBytes)
            end if
            
            ' Add to RECT buffer
            *pRc = type<RECT>(iLeft, iY, iX, iY+1)
            pRc += 1
            iCurBytes += sizeof(RECT)
            
        loop until (iX >= bmSource.bmWidth)
        iX = 0
    next iY
    
    ' Free bitmap buffer
    free(pBmp)
    
    ' Initalize region data and create region
    with *cptr(RGNDATAHEADER ptr, pAlloc)
        .dwSize = sizeof(RGNDATAHEADER)
        .iType = RDH_RECTANGLES
        .nCount = (iCurBytes-.dwSize) \ sizeof(RECT)
        .nRgnSize = 0
        .rcBound = type(0, 0, bmSource.bmWidth, bmSource.bmHeight)
    end with
    dim as HRGN hRgn = ExtCreateRegion(NULL, iCurBytes, pAlloc)
    
    ' Now free struct/RECT buffer
    free(pAlloc)
    
    return hRgn
End Function

' Calculate the regions for the loaded bitmaps
Sub createRegions(hDC as HDC)
    dim as HDC hdcMem = CreateCompatibleDC(hDC)
    
    var hOld = SelectObject(hdcMem, hbmCatBitmaps(CBM_WAITING))
    if hRgnMain then DeleteObject(hRgnMain)
    hRgnMain = createWindowRegion(hdcMem, bmCatBitmap)
    
    SelectObject(hdcMem, hbmCatBitmaps(CBM_LEFT))
    if hRgnLeft then DeleteObject(hRgnLeft)
    hRgnLeft = createWindowRegion(hdcMem, bmCatBitmap)
    
    SelectObject(hdcMem, hbmCatBitmaps(CBM_RIGHT))
    if hRgnRight then DeleteObject(hRgnRight)
    hRgnRight = createWindowRegion(hdcMem, bmCatBitmap)
    
    SelectObject(hdcMem, hbmCatBitmaps(CBM_BOTH))
    if hRgnBoth then DeleteObject(hRgnBoth)
    hRgnBoth = createWindowRegion(hdcMem, bmCatBitmap)
    
    SelectObject(hdcMem, hOld)
    DeleteDC(hdcMem)
End Sub

' Split 2 frame bitmap in half to create 4 frames of animation
Sub split2FrameBitmap(hDC as HDC, hCatBitmaps() as HBITMAP)
    ' Store bitmap info from first bitmap
    GetObject(hCatBitmaps(CBM_BOTH), sizeOf(bmCatBitmap), @bmCatBitmap)
    
    ' Create left/right frames by splitting combined frame
    dim as HDC hdcMem = CreateCompatibleDC(hDC)
    dim as HDC hdcMem2 = CreateCompatibleDC(hDC)
    var hOld2 = SelectObject(hdcMem2, hbmCatBitmaps(CBM_BOTH))
    
    ' Do the split
    with bmCatBitmap
        var hOld = SelectObject(hdcMem, hbmCatBitmaps(CBM_LEFT))
        BitBlt(hdcMem, 0, 0, .bmWidth\2, .bmHeight, _
               hdcMem2, 0, 0, SRCCOPY)
               
        SelectObject(hdcMem, hbmCatBitmaps(CBM_RIGHT))               
        BitBlt(hdcMem, .bmWidth\2, 0, .bmWidth\2, .bmHeight, _
               hdcMem2, .bmWidth\2, 0, SRCCOPY)
               
        SelectObject(hdcMem, hOld)
    end with
    
    SelectObject(hdcMem2, hOld2)
    DeleteDC(hdcMem2)
    DeleteDC(hdcMem)
End Sub

Sub loadDefaultSkin(hDC as HDC)
    iSelectedSkin = 0
    
    ' Load bitmap resources
    hbmCatBitmaps(CBM_WAITING) = LoadBitmap(GetModuleHandle(NULL), @"BM_CAT1")
    hbmCatBitmaps(CBM_LEFT)    = LoadBitmap(GetModuleHandle(NULL), @"BM_CAT1")
    hbmCatBitmaps(CBM_RIGHT)   = LoadBitmap(GetModuleHandle(NULL), @"BM_CAT1")
    hbmCatBitmaps(CBM_BOTH)    = LoadBitmap(GetModuleHandle(NULL), @"BM_CAT2")

    split2FrameBitmap(hDC, hbmCatBitmaps())
End Sub

' Read the typoskin.ini and load resources from file
Sub loadSkinResources(hDC as HDC, sSkinPath as string)
    dim as string sName
    dim as string sSkinCfg = sSkinPath+SKIN_CFG
    
    ' Get skin's name
    dim as zstring*256 szTmp
    var iLen = GetPrivateProfileString("skin", "name", "", szTmp, 255, sSkinCfg)
    printf(!"Loading %s...\r\n", szTmp)
    sName = szTmp
    
    ' Load cat with hands down frame
    iLen = GetPrivateProfileString("skin", "frame2", "cat2.bmp", szTmp, 255, sSkinCfg)
    hbmCatBitmaps(CBM_BOTH) = LoadImage(NULL, sSkinPath+"\"+szTmp, IMAGE_BITMAP, 0, 0, LR_LOADFROMFILE)
    
    if hbmCatBitmaps(CBM_BOTH) = NULL then
        dim as string sErr = "Error loading skin '"+sName+!"'!\r\n'"+szTmp+"' not found!"
        ShowWindow(hWndMain, SW_HIDE)
        Messagebox(hWndMain, sErr, "Error!", MB_ICONERROR)
        ShowWindow(hWndMain, SW_SHOW)
        LoadDefaultSkin(hDC)
        return
    end if
    
    ' Load cat with hands up frame
    iLen = GetPrivateProfileString("skin", "frame1", "cat1.bmp", szTmp, 255, sSkinCfg)
    hbmCatBitmaps(CBM_WAITING) = LoadImage(NULL, sSkinPath+"\"+szTmp, IMAGE_BITMAP, 0, 0, LR_LOADFROMFILE)
    
    if hbmCatBitmaps(CBM_WAITING) = NULL then
        DeleteObject(hbmCatBitmaps(CBM_BOTH)) ' Prevent handle leaks
        dim as string sErr = "Error loading skin '"+sName+!"'!\r\n'"+szTmp+"' not found!"
        ShowWindow(hWndMain, SW_HIDE)
        Messagebox(hWndMain, sErr, "Error!", MB_ICONERROR)
        ShowWindow(hWndMain, SW_SHOW)
        LoadDefaultSkin(hDC)
        return
    end if
    
    hbmCatBitmaps(CBM_LEFT) = LoadImage(NULL, sSkinPath+"\"+szTmp, IMAGE_BITMAP, 0, 0, LR_LOADFROMFILE)
    hbmCatBitmaps(CBM_RIGHT) = LoadImage(NULL, sSkinPath+"\"+szTmp, IMAGE_BITMAP, 0, 0, LR_LOADFROMFILE)
            
    split2FrameBitmap(hDC, hbmCatBitmaps())
End Sub

Sub loadSkin(hDC as HDC, sSkinPath as string)
    ' Close any open DC handles
    for i as integer = 0 to TOTAL_CATS
        if hbmCatBitmaps(i) <> NULL then
            DeleteObject(hbmCatBitmaps(i))
        end if
    next i

    ' if no path specified load default skin
    if sSkinPath = "" then
        LoadDefaultSkin(hDC)
    else
        dim as string sSkinCfg = sSkinPath+SKIN_CFG
        if dir(sSkinCfg) = "" then ' No skin config file???
            ' Silently error our since it's probably a config.ini issue
            LoadDefaultSkin(hDC)
        else
            loadSkinResources(hDC, sSkinPath)
        end if
    end if
    
    ' Create the window regions based on bitmap
    createRegions(hDC)
    
    ' Set window's initial region to the idle cat region
    Dim as HRGN hRgn = CreateRectRgn(0, 0, 0, 0)
    CombineRgn(hRgn, hRgnMain, NULL, RGN_COPY)
    SetWindowRgn(hWndMain, hRgn, TRUE)
End Sub

' Load the app settings from the config file
Sub loadSettings()
    dim as string sCfgPath = exePath+"\config.ini"
    if dir(sCfgPath) = "" then ' Create config if it doesn't exist
        if open(sCfgPath for output as #1) then
            print "Error creating config file!"
        else
            ' Write default config
            print #1, !"[default]\r\nskin=default\r\ncustomLR=true"
            close #1
        end if
    end if
    
    ' Start in CustomLR mode?
    Dim as zstring*6 szCustomLR
    var iLen = GetPrivateProfileString("default", "customLR", "true", szCustomLR, 255, sCfgPath)
    if lcase(szCustomLR) = "true" then
        iCustomLeftRight = TRUE
    else
        iCustomLeftRight = FALSE
    end if
    
    ' Load last used skin
    Dim as zstring*256 szSkinPath
    iLen = GetPrivateProfileString("default", "skin", "", szSkinPath, 255, sCfgPath)
    
    ' Check if last loaded skin is in skin picker UI
    for i as integer = 1 to ubound(skins)
        if szSkinPath = skins(i).sDir then
            iSelectedSkin = i
            exit for
        end if
    next i
    
    ' Set path
    sCurSkin = exepath+"\skins\"+szSkinPath
end sub

