''''''''''''''''''''''''''''''''''''
'           Typo The Cat           '
'                                  '
' (C) Copyright Graham Downey 2020 '
''''''''''''''''''''''''''''''''''''
#define fbc -s gui typocat.rc
#include "windows.bi"
#include "crt.bi"

#include "DoubleBuffer.bas"

#define ShowDebug 0
Declare Function createWindowRegion(hdcSource as HDC, bmSource as BITMAP, clrTrans as COLORREF = BGR(255, 0, 255)) as HRGN
Declare Sub WinMain(hInstance as HINSTANCE, hPrevInstance as HINSTANCE, szCmdLine as PSTR, iCmdShow as Integer)
Declare Sub loadDefaultSkin(hDC as HDC)

Const WINDOW_WIDTH = 320, WINDOW_HEIGHT = 240
Dim shared as HWND hwndMain      ' Handle of main cat window
static shared as HRGN hRgnMain, hRgnLeft, hRgnRight, hRgnBoth
Dim Shared as HINSTANCE hInstance
Dim Shared as String szAppName
Dim Shared as String szCaption

enum ContextMenuCommands
    CMC_QUIT
end enum

enum CatBitmaps
    CBM_WAITING = 0
    CBM_LEFT
    CBM_RIGHT
    CBM_BOTH
    CBM_LAST
end enum
Const as integer TOTAL_CATS = CBM_LAST-1
Dim shared as integer iCatPic = CBM_WAITING
Dim shared as BITMAP bmCatBitmap              ' Bitmap info struct
Dim shared as HDC hdcCatBitmaps(TOTAL_CATS)   ' hdc of each cat frame

Dim shared as integer iCustomLeftRight = 1 ' Distinguish left/right shift/ctrl

hInstance = GetModuleHandle(NULL)
szAppName = "Typo Cat"
szCaption = "Typo Cat"

'Launch into WinMain()
WinMain(hInstance, NULL, Command, SW_NORMAL)

Function WndProc (hWnd as HWND, iMsg as uInteger, wParam as WPARAM, lParam as LPARAM) as LRESULT
    Static as HMENU hContextMenu
    
    Select Case iMsg
    Case WM_CREATE
        setDoubleBuffer(hWnd)
        
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

        hContextMenu = CreatePopupMenu()
        AppendMenu(hContextMenu, MF_STRING, CMC_QUIT, @"Quit")

        var hDC = GetDC(hWnd)
        
        loadDefaultSkin(hDC)
        
        hRgnMain = createWindowRegion(hdcCatBitmaps(CBM_WAITING), bmCatBitmap)
        hRgnLeft = createWindowRegion(hdcCatBitmaps(CBM_LEFT), bmCatBitmap)
        hRgnRight = createWindowRegion(hdcCatBitmaps(CBM_RIGHT), bmCatBitmap)
        
        hRgnBoth = CreateRectRgn(0, 0, 0, 0)
        CombineRgn(hRgnBoth, hRgnLeft, hRgnRight, RGN_OR)
        
        Dim as HRGN hRgn = CreateRectRgn(0, 0, 0, 0)
        CombineRgn(hRgn, hRgnMain, NULL, RGN_COPY)
        SetWindowRgn(hWnd, hRgn, TRUE)

        ReleaseDC(hWnd, hDC)
        return 0
        
    Case WM_PAINT
        Dim as PAINTSTRUCT ps
        var hDC = BeginPaint(hWnd, @ps)
        hDC = iif( wparam , cast(HDC,wparam) , ps.hDC) ' Required for double buffer hook
        
        with bmCatBitmap
            BitBlt(hDC, 0, 0, .bmWidth, .bmHeight, hdcCatBitmaps(iCatPic), 0, 0, SRCCOPY)
        end with
        
        EndPaint(hWnd, @ps)
        return 0
       
    Case WM_WINDOWPOSCHANGED
        SetWindowPos(hWnd, HWND_TOPMOST, NULL, NULL, NULL, NULL, _
                     SWP_SHOWWINDOW OR SWP_NOSIZE OR SWP_NOMOVE)
       
    Case WM_CONTEXTMENU
        dim as integer iX = LOWORD(lParam)
        dim as integer iY = HIWORD(lParam)
        TrackPopupMenuEx(hContextMenu, NULL, iX, iY, hWnd, NULL)
        
    Case WM_NCHITTEST
        if (GetAsyncKeyState(VK_LBUTTON) AND &H8000) then
            return HTCAPTION ' Enable dragging whenever client left clicked
        end if
        return HTCLIENT ' Right click client area sends us WM_CONTEXTMENU
    
    Case WM_COMMAND
        Select Case HIWORD(wParam) ' wNotifyCode
        Case 0 ' Context menu clicked
            Select Case LOWORD(wParam) ' wID of menu item
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
             &HA4 to &HB9, &HC1 to &HDA
            Continue For
            
        Case VK_SHIFT, VK_CONTROL ' Skip if we're checking specific left/right
            if iCustomLeftRight then continue for
            
        End Select
        
        if (GetAsyncKeyState(iK) AND &H8000) then
            if (iK AND 1) then ' Odd keys
                iKeyStates OR= KD_RIGHT
            else               ' Even keys
                iKeyStates OR= KD_LEFT
            end if
        end if
    next iK
    return iKeyStates
End Function


Sub WinMain(hInstance as HINSTANCE, hPrevInstance as HINSTANCE, _
            szCmdLine as PSTR, iCmdShow as Integer)
            
    Dim as HWND       hWnd
    Dim as MSG        msg
    Dim as WNDCLASSEX wcls

    #if ShowDebug
        AllocConsole() 'Show console
    #endif
    
    wcls.cbSize        = sizeof(WNDCLASSEX)
    wcls.style         = CS_HREDRAW OR CS_VREDRAW
    wcls.lpfnWndProc   = @WndProc
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
    
    'const WINDOW_STYLE = WS_OVERLAPPEDWINDOW ' XOR WS_THICKFRAME XOR WS_MAXIMIZEBOX
    const WINDOW_STYLE = WS_POPUP OR WS_SYSMENU 'OR WS_THICKFRAME
    
    hWnd = CreateWindow(szAppName, _            ' window class name
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
            
    hwndMain = hWnd
    ShowWindow(hWnd, iCmdShow)
    UpdateWindow(hWnd)
    
    
    Dim as integer iLastState ' Last state of cat
    while (msg.message <> WM_QUIT)
        while (PeekMessage(@msg, NULL, 0, 0, PM_REMOVE))
            TranslateMessage(@msg)
            DispatchMessage(@msg)
        wend
        
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
        end if
        
        sleep 10,1
    wend

    for i as integer = 0 to TOTAL_CATS
        DeleteDC(hdcCatBitmaps(i))
    next i
        
    system msg.wParam
End Sub

' http://www.flounder.com/setwindowrgn.htm
'https://www.codeguru.com/cpp/w-d/dislog/non-rectangulardialogs/article.php/c5037/Creating-Shaped-Windows-Using-Regions-with-Win32.htm
Function createWindowRegion(hdcSource as HDC, bmSource as BITMAP, _
                            clrTrans as COLORREF = BGR(255, 0, 255)) as HRGN
    dim as integer iX = 0
    dim as HRGN hRgn = CreateRectRgn(0, 0, 0, 0) ' Start with empty region
    
    for iY as integer = 0 to bmSource.bmHeight-1        
        do
            ' Skip over transparent pixels
            while (iX < bmSource.bmWidth AndAlso _
                   GetPixel(hdcSource, iX, iY) = clrTrans)
                iX += 1
            wend
            
            ' Count how wide this pixel area is
            dim as integer iLeft = iX
            while (iX < bmSource.bmWidth AndAlso _
                   GetPixel(hdcSource, iX, iY) <> clrTrans)
                iX += 1
            wend
    
            ' Combine regions and delete temp object
            dim as HRGN hRgn2 = CreateRectRgn(iLeft, iY, iX, iY+1)
            CombineRgn(hRgn, hRgn, hRgn2, RGN_OR)
            DeleteObject(hRgn2)
            
        loop until (iX >= bmSource.bmWidth)
        iX = 0
    next iY
    
    return hRgn
End Function

Sub loadDefaultSkin(hDC as HDC)
    Dim as HBITMAP hCatBitmaps(TOTAL_CATS)

    ' Load bitmap resources
    hCatBitmaps(CBM_WAITING) = LoadBitmap(GetModuleHandle(NULL), @"BM_CAT1")
    hCatBitmaps(CBM_LEFT)    = LoadBitmap(GetModuleHandle(NULL), @"BM_CAT1")
    hCatBitmaps(CBM_RIGHT)   = LoadBitmap(GetModuleHandle(NULL), @"BM_CAT1")
    hCatBitmaps(CBM_BOTH)    = LoadBitmap(GetModuleHandle(NULL), @"BM_CAT2")

    for i as integer = 0 to TOTAL_CATS
        ' Initalize DC for each bitmap
        hdcCatBitmaps(i) = CreateCompatibleDC(hDC)
        
        ' Copy bitmap data from resource into bitmap structures
        SelectObject(hdcCatBitmaps(i), hCatBitmaps(i))
        GetObject(hCatBitmaps(i), sizeOf(bmCatBitmap), @bmCatBitmap)
        
        ' Delete the old resource handles
        DeleteObject(hCatBitmaps(i))
    next i
        
    ' Create left/right frames by splitting combined frame
    with bmCatBitmap
        BitBlt(hdcCatBitmaps(CBM_LEFT), 0, 0, .bmWidth\2, .bmHeight, _
               hdcCatBitmaps(CBM_BOTH), 0, 0, SRCCOPY)
               
        BitBlt(hdcCatBitmaps(CBM_RIGHT), .bmWidth\2, 0, .bmWidth\2, .bmHeight, _
               hdcCatBitmaps(CBM_BOTH), .bmWidth\2, 0, SRCCOPY)
    end with
End Sub

