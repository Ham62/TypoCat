namespace ProgDialog

enum WindowControls_
  wcMain
  
  wcProgBar
  wcInfo
  
  wcLast
end enum
dim shared as HWND CTL(wcLast)       'controls

Function ProgDialogProc(hWnd as HWND, iMsg as uLong, wParam as WPARAM, lParam as LPARAM) as LRESULT   
    static as hFont fntDefault, fntSmall
    
    Select Case iMsg
    Case WM_CREATE        
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
        
        InitCommonControls()
        
        ' Create window controls
        #define CreateControl(mID, mExStyle, mClass, mCaption, mStyle, mX, mY, mWid, mHei) CTL(mID) = CreateWindowEx(mExStyle,mClass,mCaption,mStyle,mX,mY,mWid,mHei,hwnd,cast(hmenu,mID),hInstance,null)
        const cBase = WS_CHILD OR WS_VISIBLE
        const cProgBar = cBase OR PBS_MARQUEE OR WS_BORDER
        
        CreateControl(wcInfo, NULL, WC_STATIC, "Loading ...", cBase, 10, 10, 300, 20)
                
        CreateControl(wcProgBar, NULL, PROGRESS_CLASS, "", cProgBar, 10, 40, 300, 20)
        SendMessage(CTL(wcProgBar), PBM_SETMARQUEE, TRUE, 0)

        ' Create fonts
        var hDC = GetDC(hWnd)
        var nHeight = -MulDiv(9, GetDeviceCaps(hDC, LOGPIXELSY), 72) 'calculate size matching DPI
        fntDefault = CreateFont(nHeight,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,0,0,0,0,"Verdana")
        
        nHeight = -MulDiv(7, GetDeviceCaps(hDC, LOGPIXELSY), 72)
        fntSmall = CreateFont(nHeight,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,0,0,0,0,"Verdana")

        for iCTL as integer = wcMain to wcLast-1
            SendMessage(CTL(iCTL), WM_SETFONT, cast(.WPARAM, fntDefault), TRUE)
        next iCTL
                
        ReleaseDC(hWnd, hDC)
        return 0
        
    Case WM_CTLCOLORSTATIC
        var hdcStatic = cast(HDC, wParam)
        SetBkMode(hdcStatic, TRANSPARENT)
        return cast(integer, GetSysColorBrush(COLOR_BTNFACE))
        
    Case WM_CLOSE
        return 0
        
    End Select
    
    return DefWindowProc(hWnd, iMsg, wParam, lParam)
End Function

Function initProgressDialog(hInstance as HINSTANCE, iMin as integer, iMax as integer, _
                            iStep as integer) as HWND
    static as zstring ptr szClass = @"ProgressDialog"
    Dim as HWND       hWnd
    Dim as WNDCLASSEX wcls
    
    if hInstance = NULL then hInstance = GetModuleHandle(NULL)
    
    wcls.cbSize        = sizeof(WNDCLASSEX)
    wcls.style         = CS_HREDRAW OR CS_VREDRAW
    wcls.lpfnWndProc   = cast(WNDPROC, @ProgDialogProc)
    wcls.cbClsExtra    = 0
    wcls.cbWndExtra    = 0
    wcls.hInstance     = hInstance
    wcls.hIcon         = LoadIcon(hInstance, "FB_PROGRAM_ICON") 
    wcls.hCursor       = LoadCursor(NULL, IDC_ARROW)
    wcls.hbrBackground = cast(HBRUSH, COLOR_BTNFACE + 1)
    wcls.lpszMenuName  = NULL
    wcls.lpszClassName = szClass
    wcls.hIconSm       = LoadImage(hInstance, "FB_PROGRAM_ICON", _
                                   IMAGE_ICON, 16, 16, LR_DEFAULTSIZE)
    
    if (RegisterClassEx(@wcls) = FALSE) then
        DbgPrint("Error! Failed to register window class " & Hex(GetLastError()))
        sleep: system
    end if
    
    const WINDOW_STYLE = WS_OVERLAPPEDWINDOW XOR WS_THICKFRAME XOR WS_MAXIMIZEBOX
    
    hWnd = CreateWindow(szClass, _              ' window class name
                        "Loading Skins...", _   ' Window caption
                        WINDOW_STYLE, _         ' Window style
                        CW_USEDEFAULT, _        ' Initial X position
                        CW_USEDEFAULT, _        ' Initial Y Posotion
                        WINDOW_WIDTH, _         ' Window width
                        WINDOW_HEIGHT/2, _      ' Window height
                        NULL, _                 ' Parent window handle
                        NULL, _                 ' Window menu handle
                        hInstance, _            ' Program instance handle
                        NULL)                   ' Creation parameters

    SendMessage(CTL(wcProgBar), PBM_SETRANGE, 0, MAKELPARAM(iMin, iMax))
    SendMessage(CTL(wcProgBar), PBM_SETSTEP, iStep, 0)

    return hWnd

End Function

end namespace

