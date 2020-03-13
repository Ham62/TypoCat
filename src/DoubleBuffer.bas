function FlickerFreeSubClass(hwnd as hwnd,msg as integer,wparam as wparam,lparam as lparam) as lresult    
  var pProc = GetProp(hwnd,"OrgProc")
  
  #macro CheckFlick()    
    if cint(GetProp(hwnd,"Redraw"))=false then
      return CallWindowProc(pProc,hwnd,msg,wparam,lparam)
    end if
    var hFlickDC = GetProp(hwnd,"FlickDC")
    var hFlickBMP = GetProp(hwnd,"FlickBMP")
    dim as Rect FlickRect = any
    GetClientRect(hwnd,@FlickRect)  
    if hFlickDC = 0 then    
      var TempDC = GetDC(hwnd)
      hFlickDC = CreateCompatibleDC(TempDC)
      hFlickBMP = CreateCompatibleBitmap(TempDC,FlickRect.Right,FlickRect.Bottom)    
      ReleaseDC(hwnd,TempDC)    
    else
      dim as size FlickSize = any
      GetBitmapDimensionEx(hFlickBMP,@FlickSize)
      if FlickSize.cx <> FlickRect.right or FlickSize.cy <> FlickRect.Bottom then      
        var TempDC = GetDC(hwnd)
        DeleteObject(hFlickBMP) : DeleteObject(hFlickDC)
        hFlickDC = CreateCompatibleDC(TempDC)
        var hTempBMP = CreateCompatibleBitmap(TempDC,FlickRect.Right,FlickRect.Bottom)
        ReleaseDC(hwnd,TempDC) : hFlickBMP = hTempBMP      
      end if    
    end if
    SelectObject(hFlickDC,hFlickBMP)
    SetBitmapDimensionEx(hFlickBMP,FlickRect.Right,FlickRect.Bottom,null)    
    SetProp(hwnd,"FlickDC",hFlickDC)
    SetProp(hwnd,"FlickBMP",hFlickBMP)    
  #endmacro
  
  select case msg  
  case WM_ERASEBKGND
    return true
    'if lparam <> -1 then return true
    'CheckFlick() 
    'return CallWindowProc(pProc,hwnd,msg,cuint(hFlickDC),lparam)
  case WM_PAINT     
    CheckFlick()    
    'SendMessage(hwnd,WM_ERASEBKGND,cuint(hFlickDC),-1)
    dim as PAINTSTRUCT tPaint        
    'BeginPaint( hwnd , @tPaint )    
    if GetUpdateRect( hwnd , @tPaint.rcPaint , false )=0 orelse IsRectEmpty(@tPaint.rcPaint) then
      tPaint.rcPaint.Left = 0 : tPaint.rcPaint.Right = FlickRect.Right
      tPaint.rcPaint.Top = 0 : tPaint.rcPaint.Left = FlickRect.Bottom
    end if
    CallWindowProc(pProc,hwnd,WM_ERASEBKGND,cast(wparam,hFlickDC),lparam)    
    var iResu = CallWindowProc(pProc,hwnd,msg,cast(wparam,hFlickDC),lparam)    
    tPaint.hDC = GetDC(hwnd)    
    with tPaint.RcPaint      
      var hDC = cast(HDC,iif(wparam,cast(HDC,wparam),cast(HDC,tPaint.hDC)))
      'FillRect( hDC , @type<rect>(0,0,640,480), GetStockOBject(BLACK_BRUSH) )
      'BitBlt(hDC,0,0,FlickRect.Right,FlickRect.Bottom,hFlickDC,0,0,SRCCOPY)
      BitBlt(hDC,.Left,.top,.Right,.Bottom,hFlickDC,.Left,.Top,SRCCOPY)
    end with    
    ReleaseDC(hwnd,tPaint.hDC)
    'EndPaint( hwnd , @tPaint )
    ValidateRect(hwnd,null)
    return iResu
  case WM_NCDESTROY
    var hFlickDC = GetProp(hwnd,"FlickDC")
    var hFlickBMP = GetProp(hwnd,"FlickBMP")
    SetWindowLong(hwnd,GWL_WNDPROC,cuint(pProc))    
    RemoveProp(hwnd,"FlickDC")
    RemoveProp(hwnd,"FlickBMP")
    RemoveProp(hwnd,"OrgProc")
    RemoveProp(hwnd,"Redraw")
    if hFlickDC then
      DeleteObject(hFlickBMP)
      DeleteObject(hFlickDC)
    end if  
  case WM_SETREDRAW
    SetProp(hwnd,"Redraw",cast(any ptr,wparam))
  end select
  return CallWindowProc(pProc,hwnd,msg,wparam,lparam)
end function
sub SetDoubleBuffer(hwnd as hwnd)
  var OldProc = GetWindowLong(hwnd,GWL_WNDPROC)
  var NewProc = cuint(@FlickerFreeSubClass)
  if OldProc = 0 then exit sub
  if OldProc = NewProc then exit sub
  SetProp(hwnd,"OrgProc",cast(any ptr,OldProc))
  SetProp(hwnd,"Redraw",cast(any ptr,1))
  'SendMessage(hwnd,WM_SETREDRAW,true,0)
  SetWindowLong(hwnd,GWL_WNDPROC,NewProc)
end sub
