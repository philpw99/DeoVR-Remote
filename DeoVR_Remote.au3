;*****************************************
;DeoVR_Remote.au3 by Philip
;Created with ISN AutoIt Studio v. 1.13
;*****************************************
#AutoIt3Wrapper_Res_HiDpi=Y
Opt("WinTitleMatchMode", 3) ; Exact title match mode.

; #include <ColorConstants.au3>
#include <json.au3>
#include <Array.au3>
#include <GuiSlider.au3>
#include "Forms\MainForm.isf"
#include <WinAPIFiles.au3>
#include "gamepad.au3"

; Global initialization
; Opt("GUIOnEventMode", 1) ; cannot use event mode because of the loop

TCPStartup() ; Start the tcp service

OnAutoItExitRegister("OnAutoItExit") ; This doesn't work in event mode.
; GUISetOnEvent($GUI_EVENT_CLOSE, "OnAutoItExit")

Global $bConnected = False , $iSocket = 0
Global $hTimer = TimerInit(), $iCheckDataInterval = 300  ;  Check the data every 300 ms

; Initialzing the joystick/gamepad
Global $lpJoy = _JoyInit(), $bHasGamepad
Global $hTimerLastPressed = TimerInit(), $iInterval = 500 ; Minimum 500ms between presses.
$bHaveGamepad = ( $lpJoy <> 0)

GUISetState(@SW_SHOW,$MainForm)

Local $iSecond =  @SEC, $hTimer = TimerInit(), $hLastPlayTimer = TimerInit()
Local $iCount =  0, $bHaveData = False

Global $sFilePlaying, $iLength, $iPosition, $iPlayerState = -1, $iPlayingSpeed ; Current playback info
Global $gaDropFiles[1]
Global $iListIndex = -1, $bPlayFromStart = False

Global $iPosA = 0, $iPosB = 0, $iGoPosition = 0
GUIRegisterMsg($WM_NOTIFY, "_WM_NOTIFY") ; For list view's double click event.
GUIRegisterMsg ($WM_DROPFILES, "_WM_DROPFILES") ; For dropping files on the list.

While True
	Sleep(10)
	$nMsg = GUIGetMsg()
	Switch $nMsg
		Case $GUI_EVENT_CLOSE
			Exit
		Case $btnConnect
			Connect()
		Case $playLink
			PlayLink()
		Case $GUI_EVENT_DROPPED
			; cw("DropID:" & @GUI_DropId & " Drop file:" & @GUI_DragFile)
			; _ArrayDisplay($gaDropFiles)
			If $gaDropFiles[0] <> "" Then 
				For $i = 0 To UBound($gaDropFiles) - 1
					AddFile2Queue($gaDropFiles[$i])
				Next
				ReDim $gaDropFiles[1]
				$gaDropFiles[0] = "" ; Done, clear the list
			EndIf 
		Case $jumpBack
			JumpBack()
		Case $jumpForward
			JumpForward()
		Case $addLinkToQueue
			AddLink2Queue( StringStripWS( _GUICtrlRichEdit_GetText($linkInput), 1 + 2) )
		Case $btnDelete
			DeleteItem()
		Case $chkPlayFromBeginning
			SetPlayFromStart()
		Case $playNext
			PlayNextItem()
		Case $playPrevious
			PlayPreviousItem()
		Case $btnPause
			PauseToggle()
		Case $btnSaveList
			SaveList()
		Case $btnLoadList
			LoadList()
		Case $playSlider
			SliderSetTime()
		Case $LoopA
			SetLoopA()
		Case $LoopB
			SetLoopB()
		Case $LoopClear
			LoopClear()
	EndSwitch

	; Make rich edit only accepts text and link.
	If _GUICtrlRichEdit_IsModified($linkInput) Then 
		Local $content = _GUICtrlRichEdit_GetText($linkInput)
		; Special case for file:///
		If StringMid($content, 2, 1) = ":" Then
			$content = StringReplace($content, ":", ":\", 1)
		EndIf
		StringStripWS( _GUICtrlRichEdit_SetText($linkInput, $content), 1 + 2)
		_GUICtrlRichEdit_SetModified($linkInput, False )
	EndIf
	
	If $bConnected Then 
		If TimerDiff($hTimer) > $iCheckDataInterval Then  ; Check DeoVR message every 300 ms.
			Local $iSize = TCPRecv($iSocket, 4, 1) , $sData = "", $sText = ""
			If $iSize <> 0 Then ; Got some data to receive.
				$bHaveData = True
				$sData =  TCPRecv($iSocket, $iSize)
				; ConsoleWrite($sData & @CRLF)
				If $sData Then
					Local $oResult = Json_Decode($sData) ; Turn the json data into object
					If @error =  -2 Then 
						; No longer connected.
						Disconnect()
					EndIf
					If Json_IsObject($oResult) Then
						If $sFilePlaying <> $oResult.Item("path") Then 
							; Playing file is different.
							$sFilePlaying = $oResult.Item("path")
							GUICtrlSetData($filePlaying, $sFilePlaying ); Display file path and name
						EndIf
						if $iPlayerState <> $oResult.Item("playerState") _ 
								Or GUICtrlRead($playerState) = "" Then
							$iPlayerState =  $oResult.Item("playerState")
							If $iPlayerState = 0 Then
								GUICtrlSetData($playerState, "Playing" )
							Else 
								GUICtrlSetData($playerState, "Paused" )
							EndIf
						EndIf
						; Done, now reset the variable
						$sData = ""
						; Below updates statis if not the same.
						if $iLength <> Floor(Int($oResult.Item("duration"))) Then 
							$iLength = Floor(Int($oResult.Item("duration")))
							GUICtrlSetData($videoLength, TimeConvert($iLength) ) ; Display the video length
							; Update the slide bar
							_GUICtrlSlider_SetRange($playSlider, 0, $iLength)
							If $iLength > 3600 Then  ; Longer than 1 hour, 5 minutes
								_GUICtrlSlider_SetTicFreq($playSlider, 300)
								_GUICtrlSlider_SetPageSize($playSlider, 300)
							ElseIf $iLength > 600 Then 	; Longer than 10 minutes, 1 minutes
								_GUICtrlSlider_SetTicFreq($playSlider, 60)
								_GUICtrlSlider_SetPageSize($playSlider, 60)
								; cw("page size:" & _GUICtrlSlider_GetPageSize($playSlider))
							Else 
								_GUICtrlSlider_SetTicFreq($playSlider, 15)  ; 15 seconds
								_GUICtrlSlider_SetPageSize($playSlider, 15)
							EndIf 
						EndIf
						If $iPosition <> Floor(Int($oResult.Item("currentTime"))) Then
							$iPosition = Floor(Int($oResult.Item("currentTime")))
							GUICtrlSetData($videoPosition, TimeConvert($iPosition) )
							; Update the slide bar
							_GUICtrlSlider_SetPos($playSlider, $iPosition)
							If $iGoPosition = 0 Then
								If $iPosB <> 0 Then ; Has looping selection
									If $iPosition >= $iPosB Then
										; Do the looping.
										GoPosition($iPosA)
									EndIf
								EndIf 
							Else 
								;Jumping to a new position. Not updating.
								If Abs($iGoPosition - $iPosition) < 3 Then ; within 3 seconds of margin.
									$iGoPosition = 0
								EndIf
							EndIf 
						EndIf
						If $iPlayingSpeed <> $oResult.Item("playbackSpeed") Then 
							$iPlayingSpeed = $oResult.Item("playbackSpeed")
							GUICtrlSetData($playingSpeed, $oResult.Item("playbackSpeed") )						
						EndIf
					EndIf 
				EndIf
			EndIf
		EndIf ; ==> End of checking data
		If $iSecond <> @SEC Then  ; Do this every second.
			$sent =  TCPSend($iSocket, 0 ) ; Keep alive.
			
			; Below is to set the control button if playState change.
			Local $sPlayerState =  GUICtrlRead($playerState), $sPause = GUICtrlRead($btnPause)
			If $sPlayerState = "Playing" and $sPause = "Play" Then 
				GUICtrlSetData($btnPause, "Pause")
			Elseif $sPlayerState = "Paused" And $sPause = "Pause" Then 
				GUICtrlSetData($btnPause, "Play")
			EndIf
			
			; Below is handling automatically playing next video.
			If $iListIndex <> -1 And $iLength <> 0 Then ; Have an index, the current item.
				$iCount =  _GUICtrlListView_GetItemCount($iList)
				If $iListIndex < $iCount -1 Then
					; Available at least one more to play.
					If $iLength = $iPosition and GUICtrlRead($playerState) = "Playing" Then
						; At the end of the file. Time to play next file
						If TimerDiff($hLastPlayTimer) > 5000 Then ; Need to be at least 5 seconds apart.
							$hLastPlayTimer = TimerInit()
							PlayNextItem()
						EndIf
					EndIf
				EndIf
			EndIf
			
			If @error Then
				ConsoleWrite("Send data error: " & @error & @CRLF)
				; No longer connected
				Disconnect()
			Else 
				; ConsoleWrite("Send success: " & $sent & @CRLF)
			EndIf
			$iSecond =  @SEC
			; ConsoleWrite(" have data:" & $bHaveData & " iCount:" & $iCount & @CRLF)
			If $bHaveData Then 
				$iCount = 0
				$bHaveData = False
			Else 
				$iCount += 1
			EndIf
			
			If $iCount > 3 Then 
				; Not playing a file any more.
				ResetData()
			EndIf
		EndIf ; ==> Do things every second
		; Check to see if Deo VR still running.
		$hDeoVR = WinGetHandle("Deo VR", "")
		If @error Then
			Disconnect()
		EndIf
	Else ; ==> If not connected.
		; Do things every second while disconnetec.
		If $iSecond <> @SEC Then
			$iSecond =  @SEC
			; Disconnected. Reset all data.
			If GUICtrlRead($filePlaying) <> "" Then 
				ResetData()
			EndIf
			Local $ip =  GUICtrlRead($hostInput),  $port =  GUICtrlRead($portInput)
			$iSocket = TCPConnect($ip, $port)
			If @error Then
				GUICtrlSetData($connectStatus, "DeoVR is not ready.")
			Else 
				TCPCloseSocket($iSocket)
				GUICtrlSetData($connectStatus, "DeoVR is ready to connect.")
			EndIf
		EndIf 
	EndIf
	
	; Gamepad and joystick 0
	If $bHaveGamepad Then
		$aJoyData = _GetJoy($lpJoy, 0)
		If $aJoyData <> 0 Then 
			; All good.
			Select 
				Case UpPressed($aJoyData)
					If TimerDiff($hTimerLastPressed)> $iInterval Then 
						PlayPreviousItem()
						$hTimerLastPressed = TimerInit()
						cw("up")
					EndIf
				Case DownPressed($aJoyData)
					If TimerDiff($hTimerLastPressed)> $iInterval Then 
						PlayNextItem()
						$hTimerLastPressed = TimerInit()
						cw("down")
					EndIf
				;;; Below is quoted out because DeoVR handles left and right button as well.
				; Case LeftPressed($aJoyData)
				;	If TimerDiff($hTimerLastPressed)> $iInterval Then 
				;		JumpBack()
				;		$hTimerLastPressed = TimerInit()
				;		cw("left")
				;	EndIf
				; Case RightPressed($aJoyData)
				;	If TimerDiff($hTimerLastPressed)> $iInterval Then 
				;		JumpForward()
				;		$hTimerLastPressed = TimerInit()
				;		cw("right")
				;	EndIf
				Case BPressed($aJoyData)
					If TimerDiff($hTimerLastPressed)> $iInterval Then 
						PauseToggle()
						$hTimerLastPressed = TimerInit()
						cw("(B)")
					EndIf
			EndSelect 
		EndIf
	EndIf 
	
WEnd

Func LoopClear()
	_GUICtrlSlider_ClearSel($playSlider)
	$iPosA = 0
	$iPosB = 0
EndFunc

Func SetLoopA()
	$iPosA = _GUICtrlSlider_GetPos($playSlider)
	If $iPosB = 0 Or $iPosB < $iPosA Then $iPosB = $iLength
	_GUICtrlSlider_SetSel($playSlider, $iPosA, $iPosB)
EndFunc

Func SetLoopB()
	$iPosB = _GUICtrlSlider_GetPos($playSlider)
	If $iPosA > $iPosB Then $iPosA = 0
	_GUICtrlSlider_SetSel($playSlider, $iPosA, $iPosB)
EndFunc


Func SliderSetTime()
	If $iLength = 0 Then 
		_GUICtrlSlider_SetPos($playSlider, 0)
		Return 
	EndIf
	If Not $bConnected Then Return
	Local $iNewPos = _GUICtrlSlider_GetPos($playSlider)

	If $iNewPos <> $iPosition Then GoPosition($iNewPos)
	; $iPosition = $iNewPos ; Prevent it from being called again.
EndFunc

; Handling encoded URL like %20...etc
Func _URLDecode($toDecode)
 local $strChar = "", $iOne, $iTwo
 Local $aryHex = StringSplit($toDecode, "")
 For $i = 1 to $aryHex[0]
  If $aryHex[$i] = "%" Then
   $i = $i + 1
   $iOne = $aryHex[$i]
   $i = $i + 1
   $iTwo = $aryHex[$i]
   $strChar = $strChar & Chr(Dec($iOne & $iTwo))
  Else
   $strChar = $strChar & $aryHex[$i]
  EndIf
 Next
 Return StringReplace($strChar, "+", " ")
EndFunc

; Converts seconds to HH:MM:SS
Func TimeConvert($i)
	Local $iHour =  Floor($i / 3600) 
	Local $iMin = Floor( ($i - 3600 * $iHour) / 60)
	Local $iSec = Mod($i, 60)
	Return StringFormat('%02d:%02d:%02d', $iHour, $iMin, $iSec)
EndFunc

; Load the saved m3u to the play list.
Func LoadList()
	Local $sFileOpenDialog = FileOpenDialog("Open the m3u list file:", @DocumentsCommonDir, _ 
		"M3U Play List File (*.m3u)", 3 )
	If @error Then
        ; Display the error message.
        MsgBox($MB_SYSTEMMODAL, "", "No file was opened.")
		Return 
    EndIf
	
	If StringInStr($sFileOpenDialog, "|") <> 0 Then 
        MsgBox($MB_SYSTEMMODAL, "", "Only one file is allowed.")
		Return 
	EndIf
	
	Local $hFile = FileOpen($sFileOpenDialog, $FO_READ)
	If $hFile = -1 Then 
		MsgBox($MB_SYSTEMMODAL, "", "An error occurred when opening the file.")
        Return
	EndIf
	
	; Clean up the list view first
	_GUICtrlListView_DeleteAllItems($iList)
	
	Local $EOF = False 
	While Not $EOF
		$sLine = FileReadLine($hFile)
		If @error Then
			$EOF = True
			ExitLoop 
		EndIf
		; Ignore the extra info line
		If StringLeft($sLine, 8) = "#EXTINF:" then ContinueLoop
		; Add the item.
		_GUICtrlListView_AddItem($iList, $sLine)
	WEnd 
	FileClose($hFile)
	$iListIndex = -1
EndFunc

; Save the list as m3u file
Func SaveList()
	; Save the play list to a m3u file.
	Local $sFileSaveDialog = FileSaveDialog("Save the m3u list file as:", @DocumentsCommonDir, _ 
		"M3U Play List File (*.m3u)", 16, "MyPlaylist.m3u" )
	If @error Then
        ; Display the error message.
        MsgBox($MB_SYSTEMMODAL, "", "No file was saved.")
		Return 
    EndIf
	
	; Retrieve the filename from the filepath e.g. Example.au3.
	Local $sFileName = StringTrimLeft($sFileSaveDialog, StringInStr($sFileSaveDialog, "\", 2, -1))

	; Check if the extension .au3 is appended to the end of the filename.
	Local $iExtension = StringInStr($sFileName, ".", 2, -1)

	; If a period (dot) is found then check whether or not the extension is equal to .au3.
	If $iExtension Then
		; If the extension isn't equal to .au3 then append to the end of the filepath.
		If StringTrimLeft($sFileName, $iExtension - 1) <> ".m3u" Then $sFileSaveDialog &= ".m3u"
	Else
		; If no period (dot) was found then append to the end of the file.
		$sFileSaveDialog &= ".m3u"
	EndIf
	; set the file name again after modification
	$sFileName = StringTrimLeft($sFileSaveDialog, StringInStr($sFileSaveDialog, "\", 2, -1))
	
	; Display the saved file.
	; MsgBox($MB_SYSTEMMODAL, "", "You saved the following file:" & @CRLF & $sFileSaveDialog)
	
	Local $hFile = FileOpen($sFileSaveDialog, $FO_OVERWRITE)
	If $hFile = -1 Then 
		MsgBox($MB_SYSTEMMODAL, "", "An error occurred when creating the file.")
		Return
	EndIf
	
	Local $iCount = _GUICtrlListView_GetItemCount ($iList)
	For $i = 0 to $iCount-1
		Local $aData = _GUICtrlListView_GetItemTextArray ($iList, $i)
		FileWriteLine($hFile, "#EXTINF:-1, ")
		FileWriteLine($hFile, $aData[1])
	Next
	FileClose($hFile)
	MsgBox($MB_ICONINFORMATION, "File Saved.", "This file:" & $sFileName & " was saved.")
EndFunc

Func PauseToggle()
	If Not $bConnected Then return 1
	
	Local $sState = GUICtrlRead($playerState)
	If $iPlayerState = 0 Then
		; Pause it
		SendCommand('{"playerState":1}')
		$iPlayerState = 1
		GUICtrlSetData($playerState, "Paused")
	Else
		; Play it
		SendCommand('{"playerState":0}')
		$iPlayerState = 0
		GUICtrlSetData($playerState, "Playing")
		If $iListIndex <> -1 Then 
			_GUICtrlListView_SetItemText ($iList, $iListIndex, "Playing", 1)
		EndIf
	EndIf
	; Handle the play list
	If $iListIndex <> -1 And _ 
		$sFilePlaying = _GUICtrlListView_GetItemText($iList, $iListIndex) Then 
		; Only set text if the file playing is the play list's current item.
		If $iPlayerState Then 
			; Paused
			_GUICtrlListView_SetItemText ($iList, $iListIndex, "Paused", 1)			
		Else 
			; Playing
			_GUICtrlListView_SetItemText ($iList, $iListIndex, "Playing", 1)			
		EndIf
	EndIf

EndFunc

; Send a text command to DeoVR player
Func SendCommand($sCommand)
	If $iSocket = 0 or not $bConnected Then Return 1
	
	Local $iLength = Int(BinaryLen($sCommand), 1) ; Making sure it's 4 bytes int.
	Local $sSend = BinaryToString(Binary($iLength) & Binary($sCommand))
	TCPSend($iSocket, $sSend)
	If @error Then
		ConsoleWrite("Error sending:" & $iLength & $sCommand & @CRLF)
	Else
		ConsoleWrite("Command Sent: " & $sCommand &  @CRLF)
	EndIf
EndFunc

; Play an item in the list
Func PlayItem($iIndex)
	
	If $iListIndex <> -1 Then 
		; Set previous playing to nothing
		_GUICtrlListView_SetItemText($iList, $iListIndex, "", 1)
	EndIf
	; Set the current index number
	$iListIndex = $iIndex

	If $bConnected Then
		Local $sText = _GUICtrlListView_GetItemText($iList, $iListIndex) ; Get current item's text
		Play($sText)
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "Playing", 1)
	Else 
		; Not connected, but can be selected as the active item.
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "Active", 1)
	EndIf 
EndFunc

; Play the previous item in the list
Func PlayPreviousItem()
	Local $iCount = _GUICtrlListView_GetItemCount($iList), $iItemToPlay
	If $iCount = 0 Then Return False ; Nothing in the list.
	If $iListIndex = -1 Then
		$iItemToPlay = 0 ; Play first item.
	ElseIf $iListIndex = 0  Then 
		; Reach the beginning. Don't play, just return.
		Return
	Else
		; Play the next one.
		$iItemToPlay = $iListIndex - 1
		; First set the "Playing" to nothing
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "", 1)
	EndIf
	; Set the playing item to "Playing"
	Local $sNewText = _GUICtrlListView_GetItemText($iList, $iItemToPlay)
	_GUICtrlListView_SetItemText ($iList, $iItemToPlay, "Playing", 1)
	_GUICtrlListView_SetItemSelected ($iList, $iItemToPlay)
	$iListIndex = $iItemToPlay
	Play($sNewText)
EndFunc

; Play the next item in the list
Func PlayNextItem()
	Local $iCount = _GUICtrlListView_GetItemCount($iList), $iItemToPlay
	If $iCount = 0 Then Return False ; Nothing in the list.
	If $iListIndex = -1 Then
		$iItemToPlay = 0 ; Play first item.
	ElseIf $iListIndex + 1 >= $iCount Then 
		; Reach the end. Don't play, just return.
		Return
	Else
		; Play the next one.
		$iItemToPlay = $iListIndex + 1
		; First set the "Playing" to nothing
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "", 1 )
	EndIf
	; Set the playing item to "Playing"
	Local $sNewText = _GUICtrlListView_GetItemText($iList, $iItemToPlay)
	_GUICtrlListView_SetItemText ($iList, $iItemToPlay, "Playing", 1)
	_GUICtrlListView_SetItemSelected ($iList, $iItemToPlay)
	$iListIndex = $iItemToPlay
	Play($sNewText)
EndFunc

Func _WM_DROPFILES($hWnd, $msgID, $wParam, $lParam) ; Special handling of dropping files
	#forceref $hWnd, $lParam
	Switch $msgID
		Case $WM_DROPFILES
			Local $nSize, $pFileName
			Local $nAmt = DllCall("shell32.dll", "int", "DragQueryFileW", "hwnd", $wParam, "int", 0xFFFFFFFF, "ptr", 0, "int", 255)
			For $i = 0 To $nAmt[0] - 1
				$nSize = DllCall("shell32.dll", "int", "DragQueryFileW", "hwnd", $wParam, "int", $i, "ptr", 0, "int", 0) 
				$nSize = $nSize[0] + 1
				$pFileName = DllStructCreate("wchar[" & $nSize & "]")
				DllCall("shell32.dll", "int", "DragQueryFileW", "hwnd", $wParam, "int", $i, "ptr", DllStructGetPtr($pFileName), "int", $nSize)
				ReDim $gaDropFiles[$i+1]
				$gaDropFiles[$i] = DllStructGetData($pFileName, 1)
				$pFileName = 0
			Next
	EndSwitch
	Return $GUI_RUNDEFMSG ; Let AutoIt handle it from here.
EndFunc

Func _WM_NOTIFY($hWnd, $iMsg, $wParam, $lParam) ; Special handling of double click
	#forceref $hWnd, $iMsg, $wParam
	; This one handles list view's double click event.
	Local $hWndFrom, $iIDFrom, $iCode, $tNMHDR, $hWndListView, $tInfo, $iIndex
    $hWndListView = $iList
    If Not IsHWnd($iList) Then $hWndListView = GUICtrlGetHandle($iList)

    $tNMHDR = DllStructCreate($tagNMHDR, $lParam)
    $hWndFrom = HWnd(DllStructGetData($tNMHDR, "hWndFrom"))
    $iCode = DllStructGetData($tNMHDR, "Code")

    Switch $hWndFrom
		Case $hWndListView
			Switch $iCode
				Case $NM_DBLCLK
					$tInfo = DllStructCreate($tagNMITEMACTIVATE, $lParam)
					$iIndex = DllStructGetData($tInfo, "Index")
					cw("Double clicked on index:" & $iIndex)
					PlayItem($iIndex)
			EndSwitch
    EndSwitch
    Return $GUI_RUNDEFMSG	; Let Autoit handle it from here.
EndFunc

Func SetPlayFromStart()
	$bPlayFromStart = (GUICtrlRead($chkPlayFromBeginning) = $GUI_CHECKED )
EndFunc

Func DeleteItem()
	; Delete the highlighted item in the play list.
	_GUICtrlListView_DeleteItemsSelected($iList)
EndFunc

Func ResetData()
	If GUICtrlRead($filePlaying) <> "" Then 
		GUICtrlSetData($filePlaying, "" )
		$sFilePlaying = ""
		GUICtrlSetData($playerState, "" )
		$iPlayerState = -1
		GUICtrlSetData($videoLength, "" )
		$iLength = 0
		GUICtrlSetData($videoPosition, "" )
		$iPosition = 0
		GUICtrlSetData($playingSpeed, "" )
		$iPlayingSpeed = 0
		_GUICtrlSlider_SetPos($playSlider, 0)
		; GUICtrlSetData($playProgress, 0 )
		If $iPosA Or $iPosB Then 
			$iPosA = 0
			$iPosB = 0
			_GUICtrlSlider_ClearSel($playSlider)
		EndIf 
	EndIf
	If $iListIndex <> -1 Then 
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "Active", 1)
	EndIf
EndFunc

Func AddFile2Queue($sFile)
	; cw("here")
	If Not FileExists($sFile) Then
		Local $reply = MsgBox($MB_OK + $MB_ICONWARNING, "File not exist.", _
			"This file does not exist, are you sure to add it to the list?")
		If $reply = $IDCANCEL Then Return
	ElseIf StringInStr(FileGetAttrib($sFile), "D") Then 
		; It's a directory, ignore.
		Return
	EndIf
	GUICtrlCreateListViewItem($sFile & "|", $iList)
EndFunc

Func AddLink2Queue($sLink)
	If $sLink <> "" Then
		GUICtrlCreateListViewItem($sLink & "|", $iList)
	EndIf
	_GUICtrlRichEdit_SetText($linkInput, "")
EndFunc

Func Disconnect()
	TCPCloseSocket($iSocket)
	$iSocket =  0
	$bConnected = False
	GUICtrlSetData($btnConnect, "Disconnect")
	GUICtrlSetData($connectStatus, "Connection lost.")
	GUICtrlSetData($btnConnect, "Connect")
	ResetData()
EndFunc

Func Play($str)
	; cw("playing:" & $str)
	; Return
	; Send the str to DeoVR to play
	If $iSocket = 0 or not $bConnected Then
		MsgBox(16, "No connection", "There is no connection to DeoVR yet.")		
	Else
		$str = StringStripWS($str, 1 + 2)
		$str = StringReplace($str, "\", "/")
		Local $sCommand
		If $bPlayFromStart Then
			$sCommand = '{"path":"' & $str & '","currentTime":0}'
		Else 
			$sCommand = '{"path":"' & $str & '"}'
		EndIf 
		SendCommand($sCommand)
	EndIf 
EndFunc

Func PlayLink()
	Local $sLink = _GUICtrlRichEdit_GetText($linkInput)
	Play($sLink)
	_GUICtrlRichEdit_SetText($linkInput, "")
EndFunc

Func Connect()
	; this one connects to the host
	; ConsoleWrite("here" & @CRLF)
	; Currently connect or disconnect?

	If Not $bConnected Then 
		; Connect
		Local $ip =  GUICtrlRead($hostInput),  $port =  GUICtrlRead($portInput)
		$iSocket = TCPConnect($ip, $port)
		If @error Then
			GUICtrlSetData($connectStatus, "Error connecting to the host.")
			; MsgBox(16, "Error Connecting", "There is an error connecting to the host. Error code: " & @error)
			Sleep(2000)
			GUICtrlSetData($connectStatus, " ")
			Return
		EndIf
		; It's connected without error.
		GUICtrlSetData($connectStatus, "Connected.")
		$bConnected =  True
		GUICtrlSetData($btnConnect, "Disconnect")
	Else
		; Disconnect
		TCPCloseSocket($iSocket)
		$bConnected =  False 
		$iSocket = 0
		GUICtrlSetData($connectStatus, "Disconnected.")
		GUICtrlSetData($btnConnect, "Connect")
	EndIf
	$hTimer = TimerInit()
EndFunc

Func JumpBack()
	If Not $bConnected then Return 1 ; Cannot work without connected.
	
	Switch GUICtrlRead($playerState)
		Case "Playing", "Paused"
			Local $iJump = Int(GUICtrlRead($jumpSec)), $iNewPosition
			If $iJump = 0 Then $iJump = 30
			If $iPosition - $iJump < 0 Then
				$iNewPosition = 0
			Else 
				$iNewPosition = $iPosition - $iJump
			EndIf
			GoPosition($iNewPosition)
		Case Else
			Return 

	EndSwitch
EndFunc

Func JumpForward()
	If Not $bConnected then Return 1 ; Cannot work without connected.
	
	Switch GUICtrlRead($playerState)
		Case "Playing", "Paused"
			Local $iJump = Int(GUICtrlRead($jumpSec)), $iNewPosition
			If $iJump = 0 Then $iJump = 30
			If $iPosition + $iJump > $iLength Then
				$iNewPosition = $iLength - 5
			Else 
				$iNewPosition = $iPosition + $iJump
			EndIf
			GoPosition($iNewPosition)
		Case Else
			Return 
	EndSwitch
EndFunc

Func cw($str)
	ConsoleWrite($str & @CRLF)
EndFunc

Func GoPosition($iPos)
	Local $sCommand = '{"currentTime":' & $iPos & '}'
	SendCommand($sCommand)
	$iGoPosition = $iPos
EndFunc

Func OnAutoItExit()
   ; ConsoleWrite("here")
   If $iSocket <> 0 Then TCPCloseSocket($iSocket)
   TCPShutdown() ; Close the tcp service
   ; Exit 
EndFunc