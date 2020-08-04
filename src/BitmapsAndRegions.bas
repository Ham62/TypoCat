' Load an image and create a transparency mask for it
function LoadImageAndMask(hInst as HINSTANCE, pzName as zstring ptr, _
                          byref hImage as HBITMAP, byref hMask as HBITMAP, _
                          uTransparency as COLORREF = &hFF00FF) as integer
  static as MSG msg = any
  
  dim as BITMAPINFO ptr ptInf = 0, ptInfCopy = 0
  dim pBits as any ptr = 0, hGlob as HGLOBAL, hResu as HBITMAP
  
  'if reading from resource then lock the resource to get its bits
  if hInst then 'Resource
      DbgPrint("Loading from resource...")
      var hRes = FindResource( hInst , pzName , RT_BITMAP )
      if hRes = 0 then SetLastError( ERROR_RESOURCE_NAME_NOT_FOUND ): return 0
      hGlob = LoadResource( hInst , hRes )
      ptInf = LockResource( hGlob )
      if ptInf = 0 then FreeResource(hGlob):SetLastError( ERROR_NOT_ENOUGH_MEMORY ): return 0
      'get offset to bits...
  else  'if reading from file... then do basic validate of the file and read it into memory
    DbgPrint(!"Loading from file...\n")
    dim pF as FILE ptr = any, tFile as BITMAPFILEHEADER = any
    if IsWin32s then 
      dim as zstring ptr pzLong = pzName
      dim as zstring*MAX_PATH zName = any : pzName = @zName
      if GetShortPathName( pzLong , pzName , MAX_PATH ) = 0 then strcpy(pzName,pzLong)
      var iOff = 0, iOut=0, bName = cptr(ubyte ptr,pzName)
      for N as integer = 0 to strlen(pzName) 'includes \0
        select case bName[N]        
        case asc("/"): bName[N] = asc("\")
        case asc("\"): iOff = -1 
        case asc("."),asc("0"): iOff = 0
        case else
          if iOff >= 8 then
            bName[iOut-2] = asc("~")
            bName[iOut-1] = asc("1")
            continue for
          end if          
        end select
        bName[iOut] = bName[N]
        iOut += 1: iOff += 1
      next N        
      DbgPrint((*pzName))
    end if
    pF = fopen( pzName , "rb" )
    if pF = 0 then       
      DbgPrint(!"File Not Found...\n")
      SetLastError(ERROR_FILE_NOT_FOUND): return 0
    end if
    if fRead( @tFile , sizeof(tFile) , 1 , pF ) = 0 then        
      DbgPrint(!"Error Reading header...\n")
      fClose(pF): SetLastError(ERROR_READ_FAULT): return 0
    end if
    if tFile.bfType <> cvshort("BM") or tFile.bfSize < 32 or tFile.bfSize > 8*1024*1024 then        
      DbgPrint(!"Not valid Bitmap file\n")
      fClose(pF): SetLastError(ERROR_BAD_FILE_TYPE): return 0
    end if
    tFile.bfSize -= sizeof(BITMAPFILEHEADER)
    tFile.bfOffBits -= sizeof(BITMAPFILEHEADER)
    ptInf = allocate(tFile.bfSize)
    if ptInf = 0 then 
      DbgPrint(!"failed to allocate\n")
      fClose(pF): SetLastError(ERROR_NOT_ENOUGH_MEMORY): return 0      
    end if
    if fRead( ptInf , tFile.bfSize , 1 , pF ) = 0 then        
      DbgPrint(!"failed to read\n")
      fClose(pF): deallocate(ptInf)
      SetLastError(ERROR_READ_FAULT): return 0
    end if
    pBits = cptr(any ptr,ptInf)+tFile.bfOffBits
    fClose(pF)
  end if 
  
  ProcessMessages()
  DbgPrint("loaded...")
  with ptInf->bmiHeader   
    
    'how many entries are there on the table?
    dim as integer iEntries = 0
    if .biBitCount > 8 then
      iEntries = iif(ptInf->bmiHeader.biSize > offsetof(BITMAPINFOHEADER, biCompression) andalso .biCompression = BI_BITFIELDS, 3, 0)
    else
      iEntries = (1 shl .biBitCount)
      if ptInf->bmiHeader.biSize > offsetof(BITMAPINFOHEADER,biClrUsed) andalso .biClrUsed andalso .biClrUsed < iEntries then
        iEntries = .biClrUsed
      end if         
    end if
    DbgPrint("entries: " & iEntries)
    
    var iHdSz = ptInf->bmiHeader.biSize+iEntries*sizeof(RGBQUAD)
    if pBits = 0 then pBits = cptr(any ptr,ptInf)+iHdSz
    ptInfCopy = allocate(iHdSz): memcpy( ptInfCopy , ptInf , iHdSz )
    
    ProcessMessages()
    DbgPrint("creating bitmaps...")
    
    'Create compatible bitmaps for the image and temp mask
    var hDC = GetDC(0), iWid = .biWidth, ihei = abs(.biHeight)
    hImage = CreateCompatibleBitmap( hDC , iWid , iHei )
    var hTemp = CreateCompatibleBitmap( hDC , iWid , iHei )
    
    ReleaseDC(0,hDC)
    if hImage = 0 then DbgPrint(!"failed to create bitmap image...\n")
    
    ProcessMessages()
    DbgPrint("creating mask")
    
    'Create Mask
    'hMask = CreateBitmap( iWid , iHei , 1 , 1 , 0 )
    'if hMask = 0 then DbgPrint(!"failed to create bitmap mask...\n")
    hMask = hTemp
    
    'DCs for image/mask
    var hDCImg = CreateCompatibleDC(0), hDCMask = CreateCompatibleDC(0)
    if hDCImg = 0 orelse hDCMask = 0 then
      DbgPrint("Failed to create masks")
    end if
    var hOldBmI = SelectObject( hDCImg  , hImage )          
    var hOldBmM = SelectObject( hDCMask , hTemp  )
    
    ' Support for loading images on palleted display modes
    if GetDeviceCaps( hDCImg, BITSPIXEL_ ) <= 8 then      
      SelectPalette( hDCImg, hPalDither , FALSE ): RealizePalette( hDCImg )
      SelectPalette( hDCMask, hPalDither , FALSE ): RealizePalette( hDCMask )
      if isWin32s=0 then SetStretchBltMode( hDCImg , HALFTONE )
    end if
    
    ProcessMessages()
    DbgPrint("storing image")
    
    'store image on device bitmap from the original DIB
    
    StretchDIBits(hDCImg,0,0,iWid,iHei,0,0,iWid,iHei,pBits,ptInf,DIB_RGB_COLORS,SRCCOPY)
    
    ProcessMessages()
    DbgPrint("changing palette or image")
    
    'change all palette entries that are transparent to black and the rest to white
    if .biBitCount > 8 then
      var iPix = iWid*iHei, pBits2 = allocate( ((iPix*.biBitCount)\8) )
      select case .biBitCount
      case 32 ' 32bpp color mode
        var dwTrans = uTransparency and &hFCFCFC
        var pPixI = cast(DWORD ptr, pBits), pPixO = cast(DWORD ptr,pBits2)
        for N as integer = 0 to iPix-1
          *pPixO = iif((*pPixI and &hFCFCFC)=dwTrans,&h000000,&hFFFFFF)
          pPixO += 1: pPixI += 1
        next N
      case 24 ' 24bpp color mode
        var dwTrans = uTransparency and &hFCFCFC
        var pPixI = cast(DWORD ptr, pBits), pPixO = cast(DWORD ptr,pBits2)
        for N as integer = 0 to iPix-1
          if (*pPixI and &hFCFCFC)=dwTrans then *pPixO and= &hFF000000 else *pPixO or= &h00FFFFFF
          *cptr(any ptr ptr,@pPixI) += 3: *cptr(any ptr ptr,@pPixO) += 3
        next N
      case 15,16 ' 15/16bpp color mode
        var pPixO = cast(WORD ptr,pBits2), pPixI = cast(WORD ptr,pBits)
        var wTrans = pPixI[(iHei-1)*iWid]
        for N as integer = 0 to iPix-1          
          *pPixO = iif(*pPixI=wTrans,&h0000,&hFFFF)
          pPixO += 1: pPixI += 1
        next N
      end select
      DbgPrint("storing mask")
      'generate the BW image (on native format) for the mask
      StretchDIBits(hDCMask,0,0,iWid,iHei,0,0,iWid,iHei,pBits2,ptInfCopy,DIB_RGB_COLORS,SRCCOPY)
      Deallocate(pBits2)
    else
      var pPal = cast(dword ptr,cast(any ptr,ptInfCopy)+.biSize)          
      for N as integer = 0 to iEntries-1 ' Create 1bpp mask for transparency
        pPal[N] = iif((pPal[N] and &hFCFCFC) = (uTransparency and &hFCFCFC), &h000000, &hFFFFFF)
      next N    
      DbgPrint("storing mask")
      'generate the BW image (on native format) for the mask
      StretchDIBits(hDCMask,0,0,iWid,iHei,0,0,iWid,iHei,pBits,ptInfCopy,DIB_RGB_COLORS,SRCCOPY)
    end if
    
    ProcessMessages()
    #if 0
      scope ' Debug by displaying bitmap and mask on desktop
        var hdcscr = GetDC(0)
        BitBlt(hdcscr,0,0,iWid,iHei,hDCImg,0,0,SRCCOPY)
        var iTick = GetTickCount()
        while abs(GetTickCount()-iTick) < 1000: sleep_(1): wend
        
        BitBlt(hdcscr,0,0,iWid,iHei,hDCMask,0,0,SRCCOPY)
        iTick = GetTickCount()
        while abs(GetTickCount()-iTick) < 1000: sleep_(1): wend
        releaseDC(0,hdcscr)
      end scope
    #endif
    
    DbgPrint("masking image")
    'change all transparent parts on the image to black
    BitBlt(hDCImg,0,0,iWid,iHei,hDCMask,0,0,SRCAND)
    
    'DbgPrint("invert mask into BW bitmap")
    'store the inverse mask on the BW bitmap
    'SelectObject( hDCImg , hMask )
    'BitBlt(hDCImg,0,0,iWid,iHei,hDcMask,0,0,NOTSRCCOPY)
    DbgPrint("invert mask")
    InvertRect(hDCMask, @type<RECT>(0,0,iWid,iHei))

    'sync hdcs with their image and delete temp native mask
    'SelectObject( hDCImg, hImage )
    'SelectObject( hDcMask , hMask )
    'DeleteObject( hTemp )    
    
    #if 0
      scope ' Debug by displaying bitmap and mask on desktop
        var hdcscr = GetDC(0)
        BitBlt(hdcscr,0,0,iWid,iHei,hDCImg,0,0,SRCCOPY)
        var iTick = GetTickCount()
        while abs(GetTickCount()-iTick) < 500: sleep_(1): wend
        
        BitBlt(hdcscr,0,0,iWid,iHei,hDCMask,0,0,SRCCOPY)
        iTick = GetTickCount()
        while abs(GetTickCount()-iTick) < 500: sleep_(1): wend
        releaseDC(0,hdcscr)
      end scope    
    #endif
    
    ProcessMessages()
    DbgPrint("Cleanup...")
    if ptInfCopy then deallocate(ptInfCopy)
    
    'debug displaying bitmaps
    #if 0
      'sleep 50,1            
      var hWnd = cast(HWND, 0) 'GetConsoleWindow()
      var hDCScr = GetDC(hWnd)
      BitBlt( hDCScr , 0,0 , iWid,iHei , hDCImg , 0,0 , SRCCOPY )
      var iTick = GetTickCount(): while abs(iTick-GetTickCount()) < 1000: sleep_ 1: wend
      'sleep
      BitBlt( hDCScr , 0,0 , iWid,iHei , hDCMask , 0,0 , SRCCOPY )
      iTick = GetTickCount(): while abs(iTick-GetTickCount()) < 1000: sleep_ 1: wend
      'sleep
      ReleaseDC(hWnd,hDCScr)
      'end
    #endif
    
    'unselect bitmaps and delete DCs
    DbgPrint("Cleanup2...")
    SelectObject( hDCImg  , hOldBmI ): DeleteDC( hDCImg  )
    SelectObject( hDCMask , hOldBmM ): DeleteDC( hDCMask )
    
  end with
  
  ProcessMessages()
  DbgPrint("Free resource or pointer")
  'deallocate pointer or resource
  if hInst then
    'GlobalUnlock(hGlob)
    FreeResource(hGlob)
  else
    deallocate(ptInf)
  end if    
  
  DbgPrint("Done.")
  
  return 1
    
end function

' Create a window region based on a bitmap and mask passed
Function createWindowRegion(hDC as HDC, hBmMask as HBITMAP, bmSource as BITMAP) as HRGN
    
    dim as integer iX = 0
        
    'Get Bitmap bits to look for transparent areas
    var pBits = allocate(bmSource.bmWidthBytes*bmSource.bmHeight)
    if pBits = 0 then
      DbgPrint("Failed to allocate bits")
    end if
    
    type BITMAPINFO256
      bmiHeader as BITMAPINFOHEADER
      bmiColors(255) as RGBQUAD
    end type
    dim as BITMAPINFO256 tBmpInfo256
    with tBmpInfo256.bmiHeader
      .biSize = sizeof(BITMAPINFOHEADER)
      .biWidth = bmSource.bmWidthBytes    : .biPlanes = 1
      .biHeight = bmSource.bmHeight : .biBitCount = 8
      .biCompression = BI_RGB
    end with
    #define ptBmpInfo cptr(BITMAPINFO ptr, @tBmpInfo256)
    
    if GetDIBits( hDC , hBmMask , 0 , bmSource.bmHeight , pBits , ptBmpInfo , DIB_RGB_COLORS ) = 0 then
      var iErr = GetLastError()
      DbgPrint("Failed to get bits "+hex$(iErr))
    end if
    
    'temporary structure to store region rects (start with room for 1022 rects)
    #ifdef ExtCreateRegion
      const HdrSz = sizeof(RGNDATAHEADER)
    #else       
      const HdrSz = 0
    #endif
    
    const InitRcs = 1536-(HdrSz\sizeof(RECT)) 'make bytes a multiple of 4096 bytes
    var iCurBytes =  HdrSz, iMaxBytes = iCurBytes+InitRcs*sizeof(RECT)
    var pAlloc = Allocate(iMaxBytes), iRc = 0, pRc = cast(RECT ptr,pAlloc+iCurBytes)   
    if pAlloc = 0 then
      DbgPrint("Failed to allocate memory for temp array")
    end if
    
    var pPix = cast(ubyte ptr,pBits+bmSource.bmWidthBytes*(bmSource.bmHeight+1))
    
    'locate opaque rects
    for iY as integer = 0 to bmSource.bmHeight-1
        iX = 0 : pPix -= bmSource.bmWidthBytes*2
        do
            ' Skip over transparent pixels
            while (iX < bmSource.bmWidthBytes AndAlso *pPix)                
                iX += 1: pPix += 1
            wend
            
            ' Count how wide this pixel area is
            dim as integer iLeft = iX
            while (iX < bmSource.bmWidthBytes AndAlso *pPix=0)
                iX += 1: pPix += 1
            wend
            
            'increase list if max reached
            if iCurBytes >= iMaxBytes then
              DbgPrint("More rects needed... reallocating")
              iMaxBytes += 512*sizeof(RECT)
              pAlloc = Reallocate(pAlloc,iMaxBytes)
              pRc = cast(RECT ptr,pAlloc+iCurBytes)
            end if
            ' Add to rect list...
            *pRc = type(iLeft,iY,iX,iY)
            pRc += 1: iCurBytes += sizeof(RECT)
            *pRc = type(iX,iY+1,iLeft,iY+1)
            pRc += 1: iCurBytes += sizeof(RECT)
            
        loop until (iX >= bmSource.bmWidthBytes)
        
    next iY
    'var hDC = GetDC(0)
    'SetDibitsToDevice( hDC , 0 , 0 , bmSource.bmWidth,bmSource.bmHeight , 0,0 , 0 , bmSource.bmHeight , pBits , @tBmpInfo , DIB_RGB_COLORS )
    'sleep 1000,1
    'ReleaseDC(0,hDC)
    
    'can now free the image pixels
    Deallocate(pBits)
    
    DbgPrint("Region setting " & ((iCurBytes-HdrSz)\sizeof(RECT)) & " rects")
    
    'initialize the region data header, and create the region
    #ifdef ExtCreateRegion
      with *cptr(RGNDATAHEADER ptr, pAlloc)
        .dwSize = sizeof(RGNDATAHEADER)
        .iType = RDH_RECTANGLES
        .nCount = (iCurBytes-.dwSize)\sizeof(RECT)      
        .nRgnSize = 0
        .rcBound = type(0,0,bmSource.bmWidthBytes,bmSource.bmHeight)
      end with
      var hRgn = ExtCreateRegion( NULL , iCurBytes , pAlloc )    
      if hRgn = 0 then
        var iErr = GetLastError()
        DbgPrint("Failed to create region Error: " & hex(iErr))
      end if
    #else
      var iSz = iCurBytes\(sizeof(RECT)*2)
      var pTemp = cptr(integer ptr,allocate(iSz*sizeof(integer)))
      if pTemp = 0 then
        DbgPrint("Failed to allocate temp buffer for polygon sizes")
      end if
      for N as integer = 0 to iSz-1 : pTemp[N] = 4 : next N
      var hRgn = CreatePolyPolygonRgn( pAlloc , pTemp , iSz , ALTERNATE )
      if hRgn = 0 then
        var iErr = GetLastError()
        DbgPrint("Failed to create region Error: " & hex(iErr))
      end if
      Deallocate(pTemp)
    #endif
    
    'can noew free the initialization struct+rects
    Deallocate(pAlloc)
    
    
    DbgPrint("Region just needs " & GetRegionData(hRgn,0,0)\sizeof(RECT) & " rects")
    return hRgn
End Function

