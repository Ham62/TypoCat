#include once "win\commctrl.bi"
#include "ProgressDialog.bas"

type CatSkin
    sDir as string
    sName as string
    sInfo as string
    
    bmIcon as BITMAP
    hbmIcon as HBITMAP
end type

const ICON_SIZE = 64
dim shared as integer iSkins = 0 ' Number of skins in skins folder
redim shared as CatSkin skins()  ' Skins from skins folder

' Convert a passed bitmap to a 64x64 icon
Function toIcon(hDC as HDC, hbmSource as HBITMAP, hbmMask as HBITMAP = 0) as HBITMAP
    dim as HDC hdcMem, hdcMem2
    dim as BITMAP bm
   
    ' Create DCs to draw masks to
    hdcMem = CreateCompatibleDC(hDC)
    hdcMem2 = CreateCompatibleDC(hDC)
    
    ' Set pallet for palleted displays
    if GetDeviceCaps(hDC , BITSPIXEL_) <= 8 then
      SelectPalette(hDC, hPalDither, FALSE): RealizePalette(hDC)
      SelectPalette(hDCMem, hPalDither, FALSE): RealizePalette(hDCMem)
      SelectPalette(hDCMem2, hPalDither, FALSE): RealizePalette(hDCMem2)
    end if
   
    GetObject(hbmSource, sizeOf(bm), @bm)
       
    ' Create transparency mask
    dim as HBITMAP hbmMask2 = hbmMask
    if hbmMask = 0 then hbmMask2 = CreateBitmap(bm.bmWidth, bm.bmHeight, 1, 1, NULL)
   
    ' Load source image
    var hTmp1 = SelectObject(hdcMem, hbmSource)
    var hTmp2 = SelectObject(hdcMem2, hbmMask2)
   
    ' Create masks
    if hbmMask = 0 then
      SetBkColor(hdcMem, BGR(255, 0, 255)) ' Specify magenta as color to base mask off
      BitBlt(hdcMem2, 0, 0, bm.bmWidth, bm.bmHeight, hdcMem, 0, 0, SRCCOPY)   ' create mask
      SetBkColor(hdcMem, BGR(0, 0, 0)):SetTextColor(hDCMem, BGR(255,255,255))
      BitBlt(hdcMem, 0, 0, bm.bmwidth, bm.bmHeight, hdcMem2, 0, 0, SRCAND)    ' set bg to black
      SetBkColor(hdcMem, BGR(255, 255, 255)):SetTextColor(hDCMem, BGR(0,0,0))
    end if
   
    ' Create destination icon in memory
    dim as HBITMAP hbmIcon = CreateCompatibleBitmap(hDC, ICON_SIZE, ICON_SIZE)
    SelectObject(hdcMem, hbmIcon)
   
    ' Copy image to icon
    with bm
        ' Set icon bg color
        FillRect(hdcMem, @type<RECT>(0, 0, .bmWidth, .bmHeight), GetSysColorBrush(COLOR_BTNFACE))
               
        ' Draw mask
        dim as integer iHeight = (.bmHeight/.bmWidth)*ICON_SIZE
        StretchBlt(hdcMem, 0, (ICON_SIZE\2)-(iHeight\2), ICON_SIZE, iHeight, _
                   hdcMem2, 0, 0, .bmWidth, .bmHeight, SRCAND)
       
        ' Draw bitmap
        SelectObject(hdcMem2, hbmSource)
        StretchBlt(hdcMem, 0, (ICON_SIZE\2)-(iHeight\2), ICON_SIZE, iHeight, _
                   hdcMem2, 0, 0, .bmWidth, .bmHeight, SRCPAINT)
    end with
   
    ' Free bitmaps from selected DCs
    SelectObject(hdcMem, hTmp1)
    SelectObject(hdcMem2, hTmp2)
   
    ' Delete DCs
    DeleteDC(hdcMem)
    DeleteDC(hdcMem2)
 
    ' Delete unneeded bitmaps
    DeleteObject(hbmMask2)
    DeleteObject(hbmSource)
 
    return hbmIcon
End Function

' Scan skins directory for loadable skins
Sub findSkins(hDC as HDC)    
    ' The first skin is always the default cat
    redim preserve skins(10)
    with Skins(0)
        dim as HBITMAP hBm, hBmMask
        LoadImageAndMask(hInstance, "BM_CAT1", hBm, hBmMask)
        .sDir = ""
        .sName = "Default"
        .sInfo = "The classic Typo we all know and love!"
        .hbmIcon = toIcon(hDC, hBm, hBmMask)
        iSkins += 1
    end with

    ' Count how many skins in in folder
    Dim as integer iDirs = 0
    Dim as string sDir
    sDir = Dir("skins\*", fbdirectory)
    while len(sDir) > 0
        if sDir[0] = asc(".") then
            sDir = Dir()
            continue while
        end if
        iDirs += 1
        sDir = Dir()
    wend
    
    ' Initalize progress bar
    var hWndProg = ProgDialog.initProgressDialog(NULL, 0, iDirs*2, 1)
    dim as HWND hWndProgText = GetDlgItem(hWndProg, ProgDialog.wcInfo)
    dim as HWND hWndProgBar = GetDlgItem(hWndProg, ProgDialog.wcProgBar)
    SendMessage(hWndProgBar, PBM_SETPOS, 0, 0)
    ShowWindow(hWndProg, SW_SHOW)

    ' Scan skins directory for other skins
    DbgPrint("finding Skins...")
    sDir = Dir("skins\*", fbdirectory)
    while len(sDir) > 0
        static as MSG msg = any
        ProcessMessages()
        
        ' Ignore folders starting with '.'
        if sDir[0] = asc(".") then
            sDir = Dir()
            continue while
        end if
        
        ' Check if this directory contains a skin config file
        dim as string sCfg = "skins\"+sDir+"\typoskin.ini"
        if open(sCfg for binary access read as #1) = 0 then
            close #1

            dim as zstring*256 szName
            var iLen = GetPrivateProfileString("skin", "name", sDir, szName, 255, sCfg)
            SetWindowText(hWndProgText, "Loading "+szName+"...")
            DbgPrint("found Skin:")
            DbgPrint("  " & sDir & " :: " & szName)
            
            dim as zstring*256 szFileName
            iLen = GetPrivateProfileString("skin", "icon", "", szFileName, 255, sCfg)
            if iLen = 0 then
                iLen = GetPrivateProfileString("skin", "frame1", "", szFileName, 255, sCfg)
            end if

            dim as HBITMAP hBm, hBmMask
            LoadImageAndMask(NULL, "skins\"+sDir+"\"+szFileName, hBm, hBmMask)
            ProcessMessages() ' Loading image can be slow
            SendMessage(hWndProgBar, PBM_STEPIT, 0, 0)
            
            iLen = GetPrivateProfileString("skin", "info", "", szFileName, 255, sCfg)
            
            ' Store skin
            if iSkins > ubound(skins) then redim preserve skins(iSkins+10)
            with skins(iSkins)
                .sDir = sDir
                .sName = szName
                .sInfo = szFileName
                .hbmIcon = toIcon(hDC, hBm, hBmMask)
            end with
            
            iSkins += 1
            SendMessage(hWndProgBar, PBM_STEPIT, 0, 0)
        end if
        sDir = Dir()
    wend
    
    DestroyWindow(hWndProg) ' Clean up progress dialog
    
    ' Resize to exact number of entries we have
    redim preserve skins(iSkins-1)
    
    DbgPrint(!"\r\n"+String(40, "-"))
    DbgPrint("  " & iSkins & " skins loaded total")
End Sub

enum WindowControls
  wcMain
  wcOKBtn
  wcCancelBtn
  
  wcSkinList
  
  wcLast
end enum
dim shared as HWND CTL(wcLast)       'controls

Function SkinPickerProc(hWnd as HWND, iMsg as uLong, wParam as WPARAM, lParam as LPARAM) as LRESULT   
    static as hFont fntDefault, fntSmall
    
    Select Case iMsg
    Case WM_CREATE        
        Scope   'Calculate Client Area Size
            Dim as rect RcWnd = any, RcCli = Any
            GetClientRect(hWnd, @RcCli)
            GetWindowRect(hWnd, @RcWnd)
            'Window Rect is in SCREEN coordinate.... make right/bottom become WID/HEI
            with RcWnd
                .right -= .left: .bottom -= .top
                .right += (.right-RcCli.right)  'Add difference cli/wnd
                .bottom += (.bottom-RcCli.bottom)   'add difference cli/wnd
                SetWindowPos(hWnd, NULL, 0, 0, .right, .bottom, SWP_NOZORDER OR SWP_NOREPOSITION)
            end with
        end Scope        
        
        InitCommonControls()
        
        ' Create window controls
        #define CreateControl(mID, mExStyle, mClass, mCaption, mStyle, mX, mY, mWid, mHei) CTL(mID) = CreateWindowEx(mExStyle,mClass,mCaption,mStyle,mX,mY,mWid,mHei,hwnd,cast(hmenu,mID),hInstance,null)
        const cBase = WS_CHILD OR WS_VISIBLE
        const cButton = cBase
        const cListBox = cBase OR WS_VSCROLL OR LBS_DISABLENOSCROLL OR LBS_OWNERDRAWFIXED
        
        ' OK/Cancel buttons
        Dim as integer iWid = 60, iPadding = 80
        CreateControl(wcOKBtn, NULL, WC_BUTTON, "OK", cBase, iPadding, 210, iWid, 24) 
        CreateControl(wcCancelBtn, NULL, WC_BUTTON, "Cancel", cButton, _
                      WINDOW_WIDTH-iPadding-iWid, 210, iWid, 24)
        
        ' Listbox containing skins
        CreateControl(wcSkinList, WS_EX_CLIENTEDGE, WC_LISTBOX, "", cListBox, _
                      0, 0, WINDOW_WIDTH, WINDOW_HEIGHT-20)

        ' Create fonts
        var hDC = GetDC(hWnd)
        var nHeight = -MulDiv(9, GetDeviceCaps(hDC, LOGPIXELSY), 72) 'calculate size matching DPI
        fntDefault = CreateFont(nHeight,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,0,0,0,0,"Verdana")
        
        nHeight = -MulDiv(7, GetDeviceCaps(hDC, LOGPIXELSY), 72)
        fntSmall = CreateFont(nHeight,0,0,0,FW_NORMAL,0,0,0,DEFAULT_CHARSET,0,0,0,0,"Verdana")

        for iCTL as integer = wcMain to wcLast-1
            SendMessage(CTL(iCTL), WM_SETFONT, cast(wParam, fntDefault), TRUE)
        next iCTL
                
        ReleaseDC(hWnd, hDC)
        return 0
        
    Case WM_MEASUREITEM
        if wParam = wcSkinList then
            dim as LPMEASUREITEMSTRUCT mis = cast(LPMEASUREITEMSTRUCT, lParam)
            mis->itemHeight = ICON_SIZE
            return TRUE
        end if
       
    Case WM_DRAWITEM
        Dim as DRAWITEMSTRUCT ptr pDIS = Cast(DRAWITEMSTRUCT ptr, lParam)
        var hDC = pDIS->hDC
                
        ' If there are no items to draw skip message
        if pDIS->itemID = -1 then exit select
        
        Select Case pDIS->itemAction
        Case ODA_DRAWENTIRE, ODA_SELECT
            dim as RECT r = pDIS->rcItem
            dim as hDC hdcMem = CreateCompatibleDC(hDC)
            
            const TEXT_PADDING = 10
            dim as integer iTxtLeft = r.left+ICON_SIZE+TEXT_PADDING\2

            ' Draw background of item to window color
            FillRect(hDC, @type<RECT>(r.left, r.top, r.right, r.bottom), _
                     GetSysColorBrush(COLOR_BTNFACE))

            ' If item is selected draw highlighted color and set text color
            if pDIS->itemState = ODS_SELECTED then
                SetTextColor(hDC, GetSysColor(COLOR_HIGHLIGHTTEXT))
                FillRect(hDC, @type<RECT>(iTxtLeft, r.top, r.right, r.bottom), _
                         GetSysColorBrush(COLOR_HIGHLIGHT))
            else
                SetTextColor(hDC, GetSysColor(COLOR_BTNTEXT))
            end if
            
            ' Draw skin icon
            dim as integer iItem = pDIS->itemID
            var hOld = SelectObject(hdcMem, skins(iItem).hbmIcon)
            BitBlt(hDC, r.left, r.top, r.right-r.left, r.bottom-r.top, _
                   hdcMem, 0, 0, SRCCOPY)
            
            SetBkMode(hDC, TRANSPARENT)
            Dim as integer iMiddle = (r.bottom-r.top)\2+r.top'-TEXT_PADDING\2
            
            ' Display skin name
            var fntOld = SelectObject(hDC, fntDefault)
            DrawText(hDC, skins(iItem).sName, len(skins(iItem).sName), _
                     @type<RECT>(r.left+ICON_SIZE+TEXT_PADDING, _
                     r.top+TEXT_PADDING, r.right, iMiddle), _
                     DT_LEFT OR DT_VCENTER OR DT_WORDBREAK OR DT_EDITCONTROL)

            ' Display skin info (show dir if no info available)
            SelectObject(hDC, fntSmall)
            dim as string sInfo = skins(iItem).sInfo
            if sInfo = "" then sInfo = "[\Skins\"+skins(iItem).sDir+"]"
            DrawText(hDC, sInfo, len(sInfo), _
                    @type<RECT>(r.left+ICON_SIZE+TEXT_PADDING, _
                    iMiddle, r.right, r.bottom), _
                    DT_LEFT OR DT_VCENTER OR DT_WORDBREAK OR DT_EDITCONTROL)


            ' If item is selected draw a box around it
            if pDIS->itemState = ODS_SELECTED then
                var hOldBrush = SelectObject(hDC, GetStockObject(NULL_BRUSH))
                Rectangle(hDC, r.left, r.top, r.right, r.bottom)
                SelectObject(hDC, hOldBrush)
            end if

            ' Line between icon and text
            var hPen = CreatePen(PS_SOLID, 1, GetSysColor(COLOR_GRAYTEXT))
            SelectObject(hDC, hPen)
            MoveToEx(hDC, iTxtLeft, r.top, NULL)
            LineTo(hDC, iTxtLeft, r.bottom)

            ' Line separating each row
            dim as HPEN hPen2 = CreatePen(PS_SOLID, 1, GetSysColor(COLOR_WINDOWFRAME))
            var hOldPen = SelectObject(hDC, hPen2)
            MoveToEx(hDC, r.left, r.bottom-1, NULL)
            LineTo(hDC, r.right, r.bottom-1)
            
            SelectObject(hDC, hOldPen)
            DeleteObject(hPen)
            DeleteObject(hPen2)
            
            SelectObject(hdcMem, hOld)
            SelectObject(hDC, fntOld)
            DeleteDC(hdcMem)
        End Select
        
        return TRUE
    
    Case WM_SHOWWINDOW
        if iSkins = 0 then
            ' Load skin info/icons first time we open the window
            var hDC = GetDC(hWnd)
            findSkins(hDC)
            ReleaseDC(hWnd, hDC)
            for i as integer = 0 to ubound(skins)
                ' Populate listbox with skins
                SendMessage(CTL(wcSkinList), LB_ADDSTRING, 0, cast(lParam, skins(i).sName))
            next i
        end if
        
        ' Highlight currently selected skin
        if iSelectedSkin = -1 then ' -1 means loaded from drag/drop
            dim as integer iPos = len(sCurSkin) ' Get directory name from path
            while iPos > 0 AndAlso sCurSkin[iPos] <> asc("\")
                iPos -= 1
            wend
            
            iSelectedSkin = 0
            if iPos > 0 then ' Check if last loaded skin is in skin picker UI
                dim as string sSkinPath = mid(sCurSkin, iPos+2)
                print sCurSkin, sSkinPath
                for i as integer = 1 to ubound(skins)
                    if sSkinPath = skins(i).sDir then
                        iSelectedSkin = i
                        exit for
                    end if
                next
            end if
        end if
        
        ' Select current skins
        SendMessage(CTL(wcSkinList), LB_SETCURSEL, iSelectedSkin, 0)
    
    Case WM_COMMAND
        Select Case HIWORD(wParam)     ' wNotifyCode
        Case BN_CLICKED
            Select Case LOWORD(wParam) ' wID
            Case wcOKBtn
                dim as integer iSkin = SendMessage(CTL(wcSkinList), LB_GETCURSEL, 0, 0)
                iSelectedSkin = iSkin
                
                var hDC = GetDC(hWnd) ' Load selected skin
                LoadSkin(hDC, "skins\"+skins(iSkin).sDir)
                ReleaseDC(hWnd, hDC)
                
                SendMessage(hWnd, WM_CLOSE, 0, 0)
                
            Case wcCancelBtn
                SendMessage(hWnd, WM_CLOSE, 0, 0)

            End Select
        End Select
        
    Case WM_MOUSEWHEEL
        dim as integer iTopIndex = SendMessage(CTL(wcSkinList), LB_GETTOPINDEX, 0, 0)
        dim as short zDelta = HIWORD(wParam) ' Wheel rotation
        
        ' Scroll skin list when we recieve the wheel event
        if zDelta > 0 AndAlso iTopIndex > 0 then
            SendMessage(CTL(wcSkinList), LB_SETTOPINDEX, iTopIndex-1, 0)
        elseif zDelta < 0 AndAlso iTopIndex < (ubound(skins)-2) then
            SendMessage(CTL(wcSkinList), LB_SETTOPINDEX, iTopIndex+1, 0)
        end if

    Case WM_CLOSE
        ShowWindow(hWnd, SW_HIDE)
        ShowWindow(hWndMain, SW_SHOW)
        return 0
        
    End Select
    
    return DefWindowProc(hWnd, iMsg, wParam, lParam)
End Function

Function initPickerWindow(hInstance as HINSTANCE) as HWND
    static as zstring ptr szClass = @"SkinPicker"
    Dim as HWND       hWnd
    Dim as WNDCLASSEX wcls
    
    wcls.cbSize        = sizeof(WNDCLASSEX)
    wcls.style         = CS_HREDRAW OR CS_VREDRAW
    wcls.lpfnWndProc   = cast(WNDPROC, @SkinPickerProc)
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
                        "TypoSkin Picker", _    ' Window caption
                        WINDOW_STYLE, _         ' Window style
                        CW_USEDEFAULT, _        ' Initial X position
                        CW_USEDEFAULT, _        ' Initial Y Posotion
                        WINDOW_WIDTH, _         ' Window width
                        WINDOW_HEIGHT, _        ' Window height
                        NULL, _                 ' Parent window handle
                        NULL, _                 ' Window menu handle
                        hInstance, _            ' Program instance handle
                        NULL)                   ' Creation parameters
                        
    return hWnd

End Function


