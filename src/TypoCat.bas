''''''''''''''''''''''''''''''''''''
'           Typo The Cat           '
'                                  '
'           Version 1.2            '
'                                  '
'       (C) Copyright 2020         '
'     Written by Graham Downey     '
'                                  '
''''''''''''''''''''''''''''''''''''
#define fbc -s gui typocat.rc

#include "windows.bi"
#include "win\winuser.bi"
#include "win\shellapi.bi"
#include "dir.bi"
#include "crt.bi"

#undef ExtCreateRegion
'#define DebugObjects

'#define DbgPrint(_S) OutputDebugString(_S & !"\r\n"):puts(_S)
#define DbgPrint(_S) scope:end scope

#include "DoubleBuffer.bas"

Declare Function LoadImageAndMask(hInst as HINSTANCE, pzName as zstring ptr, byref hImage as HBITMAP, byref hMask as HBITMAP, uTransparency as COLORREF = &hFF00FF) as integer
Declare Sub WinMain(hInstance as HINSTANCE, hPrevInstance as HINSTANCE, szCmdLine as PSTR, iCmdShow as Integer)
Declare Sub loadSettings()
Declare Sub loadSkin(hDC as HDC, sSkinPath as string)
Declare Sub ReleaseResources()  
Declare Sub ReShowWindow(hwnd as HWND, iNoTrans as long = 1)
Declare Sub SetWndRegion(hWnd as HWND, hRgn as HRGN, iRedraw as integer)
Declare Function CheckKeyStates() as integer

' Function pointer to AnnoyProc
Dim Shared AnnoyProc as Sub()

Const WINDOW_WIDTH = 320, WINDOW_HEIGHT = 240
Dim shared as HWND hwndMain, hWndSkinSelect
static shared as HRGN hRgnMain, hRgnLeft, hRgnRight, hRgnBoth, hRgnCur
Dim Shared as HINSTANCE hInstance
Dim Shared as String szAppName
Dim Shared as String szCaption
Dim shared tOsVer as OSVERSIONINFO
Dim shared as long IsWin32s, IsWin2K

enum ContextMenuCommands
    CMC_SKINS
    CMC_ANNOYING
    CMC_CUSTOMLR
    CMC_ABOUT
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

Const as integer TOTAL_CATS = CBM_LAST-1
const KD_LEFT  = 1, _
      KD_RIGHT = 2, _
      KD_BOTH  = 3, _
      KD_NONE  = 0

Dim shared as integer iCatPic = CBM_WAITING
Dim shared as integer iSelectedSkin = -1
Dim shared as string sCurSkin
dim shared as HPALETTE hPalDither
Dim shared as BITMAP bmCatBitmap                   ' Bitmap info struct
Static shared as HBITMAP hbmCatBmps(TOTAL_CATS)    ' Bitmap handle for each frame
Static shared as HBITMAP hbmCatMasks(TOTAL_CATS)   ' Masks for each frame

Dim shared as integer iCustomLeftRight = TRUE ' Distinguish left/right shift/ctrl
Dim shared as integer iAnnoyingMode = FALSE   ' Enable annoyingness
Dim shared as integer iAnnoyWait = 600000     ' How many ms to wait before annoying
Dim shared as integer iWaitKeyPress = FALSE   ' Do keypresses reset the timer?

' Check if we're running on Win32s
tOsVer.dwOSVersionInfoSize = sizeof(tOsVer)
GetVersionEx(@tOsVer)
IsWin32s = (tOsVer.dwPlatformId = VER_PLATFORM_WIN32s)
IsWin2K = (tOsVer.dwMajorVersion >= 5)

DbgPrint("Load Settings...")
hInstance = GetModuleHandle(NULL)
szAppName = "Typo Cat"
szCaption = "Typo Cat"

'Launch into WinMain()
WinMain(hInstance, NULL, GetCommandLine, SW_NORMAL)

' Mini message loop to simulate Yield() while loading bitmaps
Sub ProcessMessages() 
    static as MSG msg = any
    while (PeekMessage(@msg, NULL, 0, 0, PM_REMOVE))
        TranslateMessage(@msg)
        DispatchMessage(@msg)
    wend
End Sub

#include "BitmapsAndRegions.bas"
#include "SkinPicker.bas"

Function WndProc (hWnd as HWND, iMsg as uLong, wParam as WPARAM, lParam as LPARAM) as LRESULT
    Static as HMENU hContextMenu ' Right click context menu
    Static as DWORD dwAnnoyTicks ' Ticks since last AnnoyProc()
    
    ' Manage pseudo transparency on Win32s
    if IsWin32s then
        static as integer iIgnore
        select case iMsg
        case WM_ERASEBKGND
            return 1
            
        case WM_RBUTTONDOWN ' Open popup menu if right mouse clicked
            dim as point MyPT = type(cshort(LOWORD(lParam)), cshort(HIWORD(lParam)))
            ClientToScreen(hWnd, @MyPT)
            SendMessage(hwnd, WM_CONTEXTMENU, wParam, MAKELPARAM(MyPT.x, MyPT.y))
            
        case WM_NCHITTEST ' Enable dragging when client clicked
            var iResu = DefWindowProc(hWnd, iMsg, wParam, lParam)
            if iResu = HTCLIENT	then               
                if (GetAsyncKeyState(VK_LBUTTON) AND &H8000) then
                    return HTCAPTION
                end if
            end if
            return iResu
            
        case WM_SIZE, WM_MOVE ' Redraw window on move/resize
            if (GetAsyncKeyState(VK_LBUTTON) AND &H8000)=0 then        
                ReShowWindow(hwnd, 0)
            end if
            
        case WM_TIMER ' Redraw the window every timer tick
            static dwTicks as DWORD
            var dwNewTicks = GetTickCount()
            if abs(dwNewTicks-dwTicks) > 500 then
                dwTicks = dwNewTicks   
                InvalidateRect(hwnd, null, true)    
            end if      
        end select
    end if
    
    Select Case iMsg
    Case WM_CREATE
        hwndMain = hWnd        
        DbgPrint("WM_CREATE")
      
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

        DbgPrint("Creating popup menu")
        hContextMenu = CreatePopupMenu()
        if hContextMenu = 0 then 
            DbgPrint("Failed to create popup menu")
        end if

        AppendMenu(hContextMenu, MF_STRING, CMC_SKINS, @"Skin...")
        AppendMenu(hContextMenu, MF_SEPARATOR, NULL, NULL)
        
        var iChecked = iif(iAnnoyingMode, MF_CHECKED, MF_UNCHECKED)
        if IsWin2K AndAlso AnnoyProc <> 0 then
            AppendMenu(hContextMenu, MF_STRING OR iChecked, CMC_ANNOYING, @"Annoying Mode")
        end if

        iChecked = iif(iCustomLeftRight, MF_CHECKED, MF_UNCHECKED)
        AppendMenu(hContextMenu, MF_STRING OR iChecked, CMC_CUSTOMLR, @"Distinguish left/right")
                
        AppendMenu(hContextMenu, MF_SEPARATOR, NULL, NULL)
        AppendMenu(hContextMenu, MF_STRING, CMC_ABOUT, @"About") 
        AppendMenu(hContextMenu, MF_SEPARATOR, NULL, NULL)
        AppendMenu(hContextMenu, MF_STRING, CMC_QUIT, @"Quit") 
      
        var hDC = GetDC(hWnd)
      
        ' Create dither palette if on paletted display mode
        if GetDeviceCaps(hDC, BITSPIXEL_) <= 8 then
            hPalDither = CreateHalftonePalette(hDC)
            SelectPalette(hDC, hPalDither, TRUE)
            RealizePalette(hDC)
        end if
      
        DbgPrint("Load default skin")
        loadSkin(hDC, sCurSkin)      
        ReleaseDC(hWnd, hDC)
      
        if IsWin32s = FALSE then 
            setDoubleBuffer(hWnd)
            DbgPrint("Double buffer set..")
        end if
      
        dwAnnoyTicks = GetTickCount()
        DbgPrint("WM_CREATE done")
        return 0

    Case WM_PAINT
        Dim as PAINTSTRUCT ps
        var hDC = BeginPaint(hWnd, @ps)
        hDC = iif(wParam, cast(HDC, wParam), ps.hDC) ' Required for double buffer hook
        
        dim as HDC hdcMem = CreateCompatibleDC(hDC)
        if IsWin32s then  ' Win32s draws to a transparent window on the desktop
            var hdcMem2 = CreateCompatibleDC(hDC)
            var hOld2 = SelectObject(hdcMem2, hbmCatMasks(iCatPic))
            var hOld = SelectObject(hdcMem, hbmCatBmps(iCatPic))
            
            with bmCatBitmap
                for iY as integer = 0 to .bmHeight-1 step 16
                    BitBlt(hDC, 0, iY, .bmWidth, 16, hdcMem2, 0, iY, SRCAND)              
                    BitBlt(hDC, 0, iY, .bmWidth, 16, hdcMem, 0, iY, SRCPAINT)
                next iY
            end with
            SelectObject(hdcMem, hOld):DeleteDC(hdcMem)
            SelectObject(hdcMem2, hOld2):DeleteDC(hdcMem2)
            
        else
            var hOld = SelectObject(hdcMem, hbmCatBmps(iCatPic))
            with bmCatBitmap
                BitBlt(hDC, 0, 0, .bmWidth, .bmHeight, hdcMem, 0, 0, SRCCOPY)
            end with
            SelectObject(hdcMem, hOld):DeleteDC(hdcMem)
        end if
        
        EndPaint(hWnd, @ps)
        return 0
        
    Case WM_TIMER
        ' Don't check key presses if window not visible
        if IsWindowVisible(hWnd) = FALSE then return 0
        
        ' Check the annoying timer
        if iAnnoyingMode AndAlso AnnoyProc <> 0 then
            var dwNewTicks = GetTickCount()
            if abs(dwNewTicks-dwAnnoyTicks) > iAnnoyWait then
                dwAnnoyTicks = dwNewTicks   
                AnnoyProc()
            end if      
        end if
        
        'Process global key presses
        var iResult = CheckKeyStates()
  
        ' Set state of cat if it's changed
        Static as integer iLastState = -1 ' Initalize to -1 to redraw on load
        if iLastState <> iResult then
            if iWaitKeyPress then
                dwAnnoyTicks = GetTickCount() ' reset annoying timer on key hit?
            end if
            
            Dim as HRGN hCopy = 0
            select case iResult
            case KD_BOTH : iCatPic = CBM_BOTH   : hCopy = hRgnBoth
            case KD_LEFT : iCatPic = CBM_LEFT   : hCopy = hRgnLeft
            case KD_RIGHT: iCatPic = CBM_RIGHT  : hCopy = hRgnRight
            case else    : iCatPic = CBM_WAITING: hCopy = hRgnMain
            end select
          
            ' Win32s redraws the trans window on the desktop, Win32 uses regions
            if IsWin32s then
                if iLastState = KD_NONE OrElse iResult = KD_BOTH then
                    InvalidateRect(hWnd, NULL, TRUE)
                else
                    ReShowWindow(hwnd)              
                end if
            else
                ' Set window region
                var hRgn = CreateRectRgn(0, 0, 0, 0)
                CombineRgn(hRgn, hCopy, NULL, RGN_COPY)
                SetWndRegion(hWnd, hRgn, TRUE)            
                InvalidateRect(hWnd, NULL, TRUE)
            end if          
            iLastState = iResult        
        end if

    Case WM_WINDOWPOSCHANGED ' Stay ontop of taskbar Win95-XP
        if IsWindowVisible(hWnd) then
            SetWindowPos(hWnd, HWND_TOPMOST, NULL, NULL, NULL, NULL, _
                         SWP_SHOWWINDOW OR SWP_NOSIZE OR SWP_NOMOVE OR SWP_NOACTIVATE)
        end if

    Case WM_CONTEXTMENU
        dim as integer iX = cshort(LOWORD(lParam))
        dim as integer iY = cshort(HIWORD(lParam))
        TrackPopupMenu(hContextMenu, TPM_LEFTBUTTON, iX, iY, 0, hWnd, NULL)    
        
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
        sCurSkin = szName
        
        if IsWin32s = FALSE then ' Win32s doesn't use regions
          Dim as HRGN hRgn = CreateRectRgn(0, 0, 0, 0)
          CombineRgn(hRgn, hRgnMain, NULL, RGN_COPY)
          SetWndRegion(hWnd, hRgn, TRUE)
        end if
        
        DragFinish(hDrop) ' Free handle
        
    Case WM_COMMAND
        Select Case HIWORD(wParam) ' wNotifyCode
        Case 0 ' Context menu clicked
            Select Case LOWORD(wParam) ' wID of menu item
            Case CMC_SKINS
                dim as RECT r, r2, rcDesk
                GetWindowRect(hWnd, @r) ' Position window over cat window
                SystemParametersInfo(SPI_GETWORKAREA, 0, @rcDesk, NULL)
                
                ' Keep skins window within bounds of desktop
                if r.left+WINDOW_WIDTH > rcDesk.right then
                    r.left = rcDesk.right-WINDOW_WIDTH-GetSystemMetrics(SM_CXEDGE)*2
                elseif r.left < rcDesk.left then
                    r.left = rcDesk.left
                end if
                
                if r.top+WINDOW_HEIGHT > rcDesk.bottom then
                    r.top = rcDesk.bottom-WINDOW_HEIGHT-(GetSystemMetrics(SM_CYSIZEFRAME) _
                            + GetSystemMetrics(SM_CYEDGE)*2 + GetSystemMetrics(SM_CYCAPTION))
                elseif r.top < rcDesk.top then ' Windows 3.1 lets you drag above top of screen
                    r.top = rcDesk.top
                end if

                ShowWindow(hWnd, SW_HIDE)
                ShowWindow(hWndSkinSelect, SW_SHOW)
                SetWindowPos(hWndSkinSelect, 0, r.left, r.top, 0, 0, SWP_NOSIZE OR SWP_NOZORDER)
                                
            Case CMC_ANNOYING                
                if iAnnoyingMode then
                    CheckMenuItem(hContextMenu, CMC_ANNOYING, MF_UNCHECKED)
                    iAnnoyingMode = FALSE
                else
                    dwAnnoyTicks = GetTickCount() ' Reset counter when mode enabled
                    CheckMenuItem(hContextMenu, CMC_ANNOYING, MF_CHECKED)
                    iAnnoyingMode = TRUE
                end if

            Case CMC_CUSTOMLR
                if iCustomLeftRight then
                    CheckMenuItem(hContextMenu, CMC_CUSTOMLR, MF_UNCHECKED)
                    iCustomLeftRight = FALSE
                else
                    CheckMenuItem(hContextMenu, CMC_CUSTOMLR, MF_CHECKED)
                    iCustomLeftRight = TRUE
                end if

            Case CMC_ABOUT
                MessageBox(hWnd, _
                           !"TypoCat Version 1.2\r\n\r\n" + _
                           !"For more information check out the README file\r\n" + _
                           !"in the TypoCat directory.\r\n\r\n" + _
                           !"More great software available at:\r\n" + _ 
                           !"http://grahamdowney.com/\r\n\r\n" + _
                           !"Written by Graham Downey (C) 2020", _
                           "TypoCat", _
                           MB_OK OR MB_ICONINFORMATION)
                
            Case CMC_QUIT
                DestroyWindow(hWnd) ' Quit when quit clicked
                
            End Select
        End Select
        
    Case WM_DESTROY
        ' Clean up
        if hPalDither then DeleteObject( hPalDither )
        if hContextMenu then DestroyMenu(hContextMenu)
      
        PostQuitMessage(0)
        return 0
        
    End Select
    
    return DefWindowProc(hWnd, iMsg, wParam, lParam)
End Function

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
            ' For generic shift/ctl/alt we can't determine left or right
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

Sub WinMain(hInstance as HINSTANCE, hPrevInstance as HINSTANCE, szCmdLine as PSTR, iCmdShow as Integer)
            
    Dim as HWND       hWnd
    Dim as MSG        msg
    Dim as WNDCLASSEX wcls
    
    #ifdef DebugObjects
    print "Objects before window: ";GetGuiResources( GetCurrentProcess() , GR_GDIOBJECTS ),GetGuiResources( GetCurrentProcess() , GR_USEROBJECTS )
    #endif
    
    LoadSettings()
    
    ' If we're on Win2k+ load the annoying lib
    dim as any ptr hAnnoyLib
    if IsWin2k then
        hAnnoyLib = DyLibLoad("Annoying.dll")
        AnnoyProc = DyLibSymbol(hAnnoyLib, "AnnoyProc")
        
        ' Normally used to set the randomizer first run
        Dim as Sub() InitAnnoying = DyLibSymbol(hAnnoyLib, "InitAnnoying")
        if InitAnnoying <> 0 then InitAnnoying()
    end if
    
    wcls.cbSize        = sizeof(WNDCLASSEX)
    wcls.style         = iif(IsWin32s, 0, CS_HREDRAW OR CS_VREDRAW) OR CS_OWNDC
    wcls.lpfnWndProc   = cast(WNDPROC, @WndProc)
    wcls.cbClsExtra    = 0
    wcls.cbWndExtra    = 0
    wcls.hInstance     = hInstance
    wcls.hIcon         = LoadIcon(hInstance, "FB_PROGRAM_ICON") 
    wcls.hCursor       = LoadCursor(NULL, IDC_ARROW)
    wcls.hbrBackground = 0 'cast(HBRUSH, COLOR_BTNFACE + 1)
    wcls.lpszMenuName  = NULL
    wcls.lpszClassName = strptr(szAppName)
    wcls.hIconSm       = LoadIcon(hInstance, "FB_PROGRAM_ICON")
    
    if (RegisterClassEx(@wcls) = FALSE) then
        DbgPrint("Error! Failed to register window class " & Hex(GetLastError()))
        sleep: system
    end if
    
    const WINDOW_STYLE = WS_POPUP OR WS_SYSMENU
    var WINDOW_STYLE_EX = WS_EX_TOPMOST OR WS_EX_ACCEPTFILES OR _
                          iif(IsWin32s, WS_EX_TRANSPARENT, WS_EX_TOOLWINDOW)
    
    DbgPrint("CreateWindowEx..")
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

    hWndSkinSelect = initPickerWindow(hInstance)

    SetTimer(hWnd, 1, 10, 0) ' Create timer to check keyboard
    
    #ifdef DebugObjects
    print "Objects window created: ";GetGuiResources( GetCurrentProcess() , GR_GDIOBJECTS ),GetGuiResources( GetCurrentProcess() , GR_USEROBJECTS )
    #endif
    
    while (GetMessage(@msg, NULL, 0, 0))
        TranslateMessage(@msg)
        DispatchMessage(@msg)
        
        ' So if our window closes while in ProcessMessage we don't hang idle
        if IsWindow(hWnd) = FALSE then exit while
    wend
        
    ' Clean up resources for Win32s after program exits
    if wcls.hIcon then DestroyIcon(wcls.hIcon)
    if wCls.hIconSm then DestroyIcon(wcls.hIconSm)
    if wCls.hCursor then DestroyCursor(wCls.hCursor)
    if hAnnoyLib then DyLibFree(hAnnoyLib)
    
    DestroyWindow(hWnd)
    UnregisterClass(szAppName, hInstance)
    
    ReleaseResources()    
    
    #ifdef DebugObjects
      print "Objects after window: ";GetGuiResources( GetCurrentProcess() , GR_GDIOBJECTS ),GetGuiResources( GetCurrentProcess() , GR_USEROBJECTS )
      sleep
    #endif

    ' Save settings to config.ini
    dim as string sCfgPath = exePath+"\config.ini"
    
    ' [default]
    if iSelectedSkin > 0 then
        dim as string sSkin = skins(iSelectedSkin).sDir
        WritePrivateProfileString("default", "skin", sSkin, sCfgPath)
    end if
     
    dim as string sTF = iif(iCustomLeftRight, "true", "false") 
    WritePrivateProfileString("default", "customLR", sTF, sCfgPath)
    
    ' [annoyMode]
    sTF = iif(iAnnoyingMode, "true", "false") 
    WritePrivateProfileString("annoyMode", "enabled", sTF, sCfgPath)
    WritePrivateProfileString("annoyMode", "waitTime", str(iAnnoyWait), sCfgPath)
    
    sTF = iif(iWaitKeyPress, "true", "false") 
    WritePrivateProfileString("annoyMode", "waitKeyPress", sTF, sCfgPath)
    
    system msg.wParam
End Sub

sub SetWndRegion(hWnd as HWND, hRgn as HRGN, iRedraw as integer)
    if IsWin32s then
        hRgnCur = hRgn
        if iRedraw then ReShowWindow( hwnd )
    else
        SetWindowRgn( hWnd , hRgn , iRedraw )
    end if
end sub

sub ReShowWindow(hWnd as HWND, iNoTrans as long = 1)
    'disabling transparency, hide/show window, reenable transparency
    var dwStyle = GetWindowLong(hWnd, GWL_EXSTYLE)
    if iNoTrans then SetWindowLong(hWnd, GWL_EXSTYLE, dwStyle AND (NOT WS_EX_TRANSPARENT))
    ShowWindow(hwnd, SW_HIDE)
    ShowWindow(hwnd, SW_SHOWNA)
    InvalidateRect(hWnd, NULL, TRUE)
    if iNoTrans then SetWindowLong(hWnd, GWL_EXSTYLE, dwStyle)
end sub

' Calculate the regions for the loaded bitmaps
Sub createRegions(hDC as HDC)
    if IsWin32s then exit sub ' Win32s doesn't support window regions
    
    if hRgnMain then DeleteObject(hRgnMain)
    hRgnMain = createWindowRegion(hDC, hbmCatMasks(CBM_WAITING), bmCatBitmap)
    
    if hRgnLeft then DeleteObject(hRgnLeft)
    hRgnLeft = createWindowRegion(hDC, hbmCatMasks(CBM_LEFT), bmCatBitmap)
        
    if hRgnRight then DeleteObject(hRgnRight)
    hRgnRight = createWindowRegion(hDC, hbmCatMasks(CBM_RIGHT), bmCatBitmap)
    
    if hRgnBoth then DeleteObject(hRgnBoth)
    hRgnBoth = createWindowRegion(hDC, hbmCatMasks(CBM_BOTH), bmCatBitmap)
End Sub

Sub split2FrameBitmap(hDC as HDC, hbmBitmaps() as HBITMAP)
    ' Get bitmap info from first bitmap
    GetObject(hbmBitmaps(CBM_BOTH), sizeOf(bmCatBitmap), @bmCatBitmap)
    
    ' Create left/right frames by splitting combined frame
    dim as HDC hdcMem = CreateCompatibleDC(hDC)
    dim as HDC hdcMem2 = CreateCompatibleDC(hDC)
    var hOld2 = SelectObject(hdcMem2, hbmBitmaps(CBM_BOTH))
    
    with bmCatBitmap
        ' Create left frame
        var hOld = SelectObject(hdcMem, hbmBitmaps(CBM_LEFT))        
        BitBlt(hdcMem, 0, 0, .bmWidth\2, .bmHeight, hdcMem2, 0, 0, SRCCOPY)
        ' Create right frame
        SelectObject(hdcMem, hbmBitmaps(CBM_RIGHT))               
        BitBlt(hdcMem, .bmWidth\2, 0, .bmWidth\2, .bmHeight, hdcMem2, .bmWidth\2, 0, SRCCOPY)
    end with
    
    ' Clean up
    SelectObject(hdcMem , hOld ) : DeleteDC(hdcMem )
    SelectObject(hdcMem2, hOld2) : DeleteDC(hdcMem2)
End Sub

' Load the default skin embedded in executable
Sub loadDefaultSkin(hDC as HDC)
    iSelectedSkin = 0
    
    ' Load bitmap resources
    LoadImageAndMask(hInstance, "BM_CAT1", hbmCatBmps(CBM_WAITING) , hbmCatMasks(CBM_WAITING))
    LoadImageAndMask(hInstance, "BM_CAT1", hbmCatBmps(CBM_LEFT)    , hbmCatMasks(CBM_LEFT)   )
    LoadImageAndMask(hInstance, "BM_CAT1", hbmCatBmps(CBM_RIGHT)   , hbmCatMasks(CBM_RIGHT)  )
    LoadImageAndMask(hInstance, "BM_CAT2", hbmCatBmps(CBM_BOTH)    , hbmCatMasks(CBM_BOTH)   )    
    
    split2FrameBitmap(hDC, hbmCatBmps())
    split2FrameBitmap(hDC, hbmCatMasks())
End Sub

' Read the typoskin.ini and load resources from file
Sub loadSkinResources(hDC as HDC, sSkinPath as string)
    
    dim as string sName    
    dim as string sSkinCfg = sSkinPath+SKIN_CFG    
    dim as zstring*256 szTmp
    dim as integer iResu = any
    var iLen = GetPrivateProfileString("skin", "name", "", szTmp, 255, sSkinCfg)
    DbgPrint( !"Loading " & szTmp & "..." )    
    sName = szTmp
    
    ' Load cat with hands down frame
    iLen = GetPrivateProfileString("skin", "frame2", "cat2.bmp", szTmp, 255, sSkinCfg)
    iResu = LoadImageAndMask(NULL, sSkinPath+"\"+szTmp, hbmCatBmps(CBM_BOTH), hbmCatMasks(CBM_BOTH))
    
    if iResu = NULL then
        dim as string sErr = "Error loading skin '"+sName+!"'!\r\n'"+szTmp+"' not found!"
        ShowWindow(hWndMain, SW_HIDE)
        Messagebox(hWndMain, sErr, "Error!", MB_ICONERROR)
        ShowWindow(hWndMain, SW_SHOW)
        LoadDefaultSkin(hDC) ' If we error out loading skin revert to default
        return
    end if
    
    ' Load cat with hands up frame
    iLen = GetPrivateProfileString("skin", "frame1", "cat1.bmp", szTmp, 255, sSkinCfg)    
    iResu = LoadImageAndMask(NULL, sSkinPath+"\"+szTmp, hbmCatBmps(CBM_WAITING), hbmCatMasks(CBM_WAITING))
    
    if iResu = NULL then
        DeleteObject(hbmCatBmps(CBM_BOTH)) ' Prevent handle leaks
        DeleteObject(hbmCatMasks(CBM_BOTH))
        
        dim as string sErr = "Error loading skin '"+sName+!"'!\r\n'"+szTmp+"' not found!"
        ShowWindow(hWndMain, SW_HIDE)
        Messagebox(hWndMain, sErr, "Error!", MB_ICONERROR)
        ShowWindow(hWndMain, SW_SHOW)
        LoadDefaultSkin(hDC)
        return
    end if
    
    ' Load image for left/right skins
    LoadImageAndMask(NULL, sSkinPath+"\"+szTmp, hbmCatBmps(CBM_LEFT), hbmCatMasks(CBM_LEFT))
    LoadImageAndMask(NULL, sSkinPath+"\"+szTmp, hbmCatBmps(CBM_RIGHT), hbmCatMasks(CBM_RIGHT))            
    split2FrameBitmap(hDC, hbmCatBmps())
    split2FrameBitmap(hDC, hbmCatMasks())
End Sub

Sub loadSkin(hDC as HDC, sSkinPath as string)
    
    ' Close any open DC handles
    DbgPrint("Delete Previous Region")
    for i as integer = 0 to TOTAL_CATS
        if hbmCatBmps(i)  then DeleteObject(hbmCatBmps(i) ): hbmCatBmps(i)=0
        if hbmCatMasks(i) then DeleteObject(hbmCatMasks(i)): hbmCatMasks(i)=0
    next i

    if sSkinPath = "" then
        DbgPrint("No name so load default skin")
        LoadDefaultSkin(hDC)
    else
        dim as string sSkinCfg = sSkinPath+SKIN_CFG
        if dir(sSkinCfg) = "" then ' No skin config file???
            ' Silently error our since it's probably a config.ini issue
            DbgPrint("No skin config file so load default skin")
            LoadDefaultSkin(hDC)
        else
            DbgPrint("Loading Skin resources")
            loadSkinResources(hDC, sSkinPath)
        end if
    end if
    
    ' Create the window regions based on bitmap
    dim as double TMR = timer
    DbgPrint("Creating regions for this resource")
    createRegions(hDC)
    DbgPrint("Regions Created in " & cint((timer-TMR)*1000) & "ms")
    
    ' Set window's initial region to the idle cat region
    if IsWin32s = FALSE then ' (Regions don't work on Win32s)
      DbgPrint("Create initial region")
      Dim as HRGN hRgn = CreateRectRgn(0, 0, 0, 0)
      CombineRgn(hRgn, hRgnMain, NULL, RGN_COPY)
      DbgPrint("Set window region")
      SetWndRegion(hWndMain, hRgn, TRUE)
    end if
    
    ' Resize window to bitmap size
    SetWindowPos(hWndMain, 0, 0, 0, bmCatBitmap.bmWidth, bmCatBitmap.bmHeight, _
                 SWP_NOMOVE or SWP_NOZORDER or SWP_NOACTIVATE)
End Sub

Sub ReleaseResources()  
  for i as integer = 0 to TOTAL_CATS
    if hbmCatBmps(i) then DeleteObject(hbmCatBmps(i)): hbmCatBmps(i) = 0
    if hbmCatMasks(i) then DeleteObject(hbmCatMasks(i)): hbmCatMasks(i) = 0
  next 
  if hRgnMain then DeleteObject(hRgnMain): hRgnMain = 0
  if hRgnLeft then DeleteObject(hRgnLeft): hRgnLeft = 0
  if hRgnRight then DeleteObject(hRgnRight): hRgnRight = 0
  if hRgnBoth then DeleteObject(hRgnBoth): : hRgnBoth = 0
end sub

' Load the app settings from the config file
Sub loadSettings()
    dim as string sCfgPath = exePath+"\config.ini"
    if dir(sCfgPath) = "" then ' Create config if it doesn't exist
        if open(sCfgPath for output as #1) then
            print "Error creating config file!"
        else
            ' Write default config
            print #1, !"[default]\r\nskin=default\r\ncustomLR=true\r\n"
            print #1, !"[annoyMode]\r\nenabled=false\r\nwaitTime=300000\r\nwaitKeyPress=false"
            close #1
        end if
    end if
    
    ' Start in CustomLR mode?
    Dim as zstring*6 szTF
    var iLen = GetPrivateProfileString("default", "customLR", "true", szTF, 5, sCfgPath)
    iCustomLeftRight = (lcase(szTF) = "true")
    
    ' Load last used skin
    Dim as zstring*256 szSkinPath
    iLen = GetPrivateProfileString("default", "skin", "", szSkinPath, 255, sCfgPath)
        
    ' Set path
    sCurSkin = exepath+"\skins\"+szSkinPath
    
    ' Start with annoyMode enabled?
    iLen = GetPrivateProfileString("annoyMode", "enabled", "false", szTF, 5, sCfgPath)
    iAnnoyingMode = (lcase(szTF) = "true")
    
    ' Wait time before annoying stuff
    iAnnoyWait = GetPrivateProfileInt("annoyMode", "waitTime", 300000, sCfgPath)
    
    ' Do key presses interrupt wait time?
    iLen = GetPrivateProfileString("annoyMode", "waitKeyPress", "false", szTF, 5, sCfgPath)
    iWaitKeyPress = (lcase(szTF) = "true")
end sub


