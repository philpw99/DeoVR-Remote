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
#include <GuiToolTip.au3>

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
RestoreWinSize()

Local $iSecond =  @SEC
Local $iCount =  0, $bHaveData = False

Global $sFilePlaying, $iLength, $iPosition, $iPlayerState = -1, $iPlayingSpeed ; Current playback info
Global $gaDropFiles[1]
Global $iListIndex = -1, $bPlayFromStart = False, $bLoopEnable = False 

Global $hSliderToolTip = _GUICtrlSlider_GetToolTips($playSlider)

Global $bCommandRunning = False , $sFulFillCriteria
Global $iC
Global $iPosA = 0, $iPosB = 0

$Dummy = GUICtrlCreateDummy() ; For slider update
$Dummy2 = GUICtrlCreateDummy() ; For double click list view item event.

GUIRegisterMsg($WM_NOTIFY, "_WM_NOTIFY") ; For list view's double click event.
GUIRegisterMsg ($WM_DROPFILES, "_WM_DROPFILES") ; For dropping files on the list.
GUIRegisterMsg($WM_HSCROLL, "WM_HVSCROLL") ; For slider to display current time.

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
		Case $loopEnable
			If _GUICtrlButton_GetCheck($loopEnable) = $BST_CHECKED Then 
				$bLoopEnable = True
			Else 
				$bLoopEnable = False 
			EndIf
		Case $Dummy		; For slider bar drag event
			SetToolTip()
		Case $Dummy2 ; For double click list item event
			PlayItem(GUICtrlRead($Dummy2))
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
			CheckAndSetData()
			$hTimer = TimerInit()
		EndIf ; ==> End of checking data
		
		If $iSecond <> @SEC Then  ; Do this every second.
			$iSecond =  @SEC
;~ 			; Below is to set the control button if playState change.
;~ 			Local $sPlayerState =  GUICtrlRead($playerState), $sPause = GUICtrlRead($btnPause)
;~ 			If $sPlayerState = "Playing" and $sPause = "Play" Then 
;~ 				GUICtrlSetData($btnPause, "Pause")
;~ 			Elseif $sPlayerState = "Paused" And $sPause = "Pause" Then 
;~ 				GUICtrlSetData($btnPause, "Play")
;~ 			EndIf
			
			; Check to see if the sent command is fulfilled.
			FulFillCheck()

			; Check the loop and playing list
			PlayingCheck()
		
			$sent =  TCPSend($iSocket, 0 ) ; Keep alive.
			If @error Then
				ConsoleWrite("Send data error: " & @error & @CRLF)
				; No longer connected
				Disconnect()
			Else 
				; ConsoleWrite("Send success: " & $sent & @CRLF)
			EndIf

			; ConsoleWrite(" have data:" & $bHaveData & " iCount:" & $iCount & @CRLF)
			If $bHaveData Then   ; $bHaveData is set in function CheckAndSetData()
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
		; Do things every 3 seconds while disconnetec.
		If Mod(@SEC, 3) =0 And $iSecond <> @SEC Then
			$iSecond = @SEC
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
	GamePadControl()
WEnd

Func RestoreWinSize()
	Local $iWinX = RegRead("HKEY_CURRENT_USER\Software\DeoVR_Remote", "WinX")
	If Not @error Then 
		Local $iWinY = RegRead("HKEY_CURRENT_USER\Software\DeoVR_Remote", "WinY")
		Local $iWinW = RegRead("HKEY_CURRENT_USER\Software\DeoVR_Remote", "WinW")
		Local $iWinH = RegRead("HKEY_CURRENT_USER\Software\DeoVR_Remote", "WinH")
		WinMove($MainForm, "", $iWinX, $iWinY, $iWinW, $iWinH)
		Local $iListWidth = RegRead("HKEY_CURRENT_USER\Software\DeoVR_Remote", "ColW")
		_GUICtrlListView_SetColumnWidth($iList, Column("Title"), $iListWidth)
	EndIf
EndFunc


Func SetToolTip()
	; Change slider's tooltip title to the Time
	Local $iPos = Int(GUICtrlRead($Dummy))
	_GUIToolTip_SetTitle($hSliderToolTip, "Time: " & TimeConvert($iPos) )
	_GUIToolTip_Update($hSliderToolTip)
EndFunc

Func GamePadControl()
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
EndFunc


Func PlayingCheck()
	; This function checks various things and do the thing.
	
	; if A B loop is enabled and play files in loops and lists.
	If $bLoopEnable Then
		If $iPosB > $iPosA Then  
			; Valid A and B pos
			If $iPosition >= $iPosB or $iPosition < $iPosA Then 
				If Not $bCommandRunning Then
					GoPosition($iPosA)
				EndIf
			EndIf
		EndIf 
	EndIf
	
	; Below is handling automatically playing next video.
	If PlayingFileInList() Then 
		; Set the video length if it's empty
		If _GUICtrlListView_GetItemText($iList, $iListIndex, Column("Length")) = "" Then
			_GUICtrlListView_SetItemText($iList, $iListIndex, TimeConvert($iLength), Column("Length"))
		EndIf
		$iCount =  _GUICtrlListView_GetItemCount($iList)
		If $iListIndex < $iCount -1 Then
			; Available at least one more to play.
			If $iLength = $iPosition And $iPlayerState = 0 Then  ; $iPlayerState = 0 means Playing, not pause.
				; At the end of the file. Time to play next file
				If Not $bCommandRunning Then 
					PlayNextItem()
				EndIf 
			EndIf
		ElseIf $iListIndex = $iCount And $iLength = $iPosition And $iPlayerState = 0 Then
			; Reach the end of the list. Pause it.
			PauseToggle()
		EndIf
	EndIf
EndFunc

Func CheckAndSetData()
	; This function reads tcp input from DeoVR then set the GUI status data
	Local $iSize = TCPRecv($iSocket, 4, 1) , $sData = "", $sText = ""
	If $iSize <> 0 Then ; Got some data to receive.
		$bHaveData = True
		Local $sData =  TCPRecv($iSocket, $iSize)
		; ConsoleWrite($sData & @CRLF)
		If $sData Then
			Local $oResult = Json_Decode($sData) ; Turn the json data into object
			If @error =  -2 Then 
				; No longer connected.
				Disconnect()
				Return
			EndIf
			
			If Json_IsObject($oResult) And Floor($oResult.Item("duration")) <> 0 Then
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
						GUICtrlSetData($btnPause, "Pause")
					Else 
						GUICtrlSetData($playerState, "Paused" )
						GUICtrlSetData($btnPause, "Play")
					EndIf
					If PlayingFileInList() Then
						If $iPlayerState = 0 Then 
							_GUICtrlListView_SetItemText($iList, $iListIndex, "Playing", Column("Status"))
						Else
							_GUICtrlListView_SetItemText($iList, $iListIndex, "Paused", Column("Status"))
						EndIf
					EndIf
				EndIf
				; Below updates statis if not the same.
				if $iLength <> Floor($oResult.Item("duration")) Then
					cw("length:" & $iLength)
					$iLength = Floor($oResult.Item("duration"))
					GUICtrlSetData($videoLength, TimeConvert($iLength) ) ; Display the video length
					SetSliderLength($iLength)	; Set the slider length and ticks
					If PlayingFileInList() Then
						; Just played a new file. Now handle A B Loop after the file loaded.
						Local $aData = _GUICtrlListView_GetItemTextArray($iList, $iListIndex)
						If TimeConvertBack($aData[4]) <> $iLength Then 
							_GUICtrlListView_SetItemText( $iList, $iListIndex, TimeConvert($iLength), Column("Length") )
						EndIf
						If $aData[5] <> "" And $aData[5] <> $aData[6] Then
							; This item has loop data
							$iPosA = TimeConvertBack($aData[5])
							$iPosB = TimeConvertBack($aData[6])
							_GUICtrlSlider_SetSel( $playSlider, $iPosA, $iPosB)
						EndIf
					EndIf
				EndIf
				
				If $iPosition <> Floor($oResult.Item("currentTime")) Then
					$iPosition = Floor($oResult.Item("currentTime"))
					GUICtrlSetData($videoPosition, TimeConvert($iPosition) )
					; Update the slide bar
					_GUICtrlSlider_SetPos($playSlider, $iPosition)
				EndIf
				
				If $iPlayingSpeed <> $oResult.Item("playbackSpeed") Then 
					$iPlayingSpeed = $oResult.Item("playbackSpeed")
					GUICtrlSetData($playingSpeed, $oResult.Item("playbackSpeed") )						
				EndIf
			EndIf ; ==> End of result is a json objet
		EndIf ; ==> End of $sData is valid
	EndIf ; ==> End of $iSize<>0
EndFunc

Func SetSliderLength($iSliderLength)
	; Update the slide bar
	_GUICtrlSlider_SetRange($playSlider, 0, $iSliderLength)
	If $iSliderLength > 1800 Then  ; Longer than 30 minutes, 5 minutes
		_GUICtrlSlider_SetTicFreq($playSlider, 300)
		_GUICtrlSlider_SetPageSize($playSlider, 300)
	ElseIf $iSliderLength > 600 Then 	; Longer than 10 minutes, 1 minutes
		_GUICtrlSlider_SetTicFreq($playSlider, 60)
		_GUICtrlSlider_SetPageSize($playSlider, 60)
		; cw("page size:" & _GUICtrlSlider_GetPageSize($playSlider))
	Else 
		_GUICtrlSlider_SetTicFreq($playSlider, 15)  ; 15 seconds
		_GUICtrlSlider_SetPageSize($playSlider, 15)
	EndIf
EndFunc

Func LoopClear()
	_GUICtrlSlider_ClearSel($playSlider)
	$iPosA = 0
	$iPosB = 0
	If PlayingFileInList() Or (Not $bConnected And $iListIndex <> -1 ) Then 
		; The file playing is the one in the list
		_GUICtrlListView_SetItemText($iList, $iListIndex, "", Column("A"))
		_GUICtrlListView_SetItemText($iList, $iListIndex, "", Column("B"))
	EndIf
EndFunc

Func SetLoopA()
	$iPosA = _GUICtrlSlider_GetPos($playSlider)
	If $iPosB = 0 Or $iPosB <= $iPosA Then
		If $bConnected Then 
			$iPosB = $iLength
		Else
			$iPosB = _GUICtrlSlider_GetRangeMax($playSlider)
		EndIf 
	EndIf
	_GUICtrlSlider_SetSel($playSlider, $iPosA, $iPosB)
	If PlayingFileInList() Or (Not $bConnected And $iListIndex <> -1 ) Then 
		; The file playing is the one in the list
		If _GUICtrlListView_GetItemText($iList, $iListIndex, Column("Length")) <> "" Then ; Should have length info
			_GUICtrlListView_SetItemText($iList, $iListIndex, TimeConvert($iPosA), Column("A"))
			_GUICtrlListView_SetItemText($iList, $iListIndex, TimeConvert($iPosB), Column("B"))
		EndIf 
	EndIf
EndFunc

Func PlayingFileInList()
	; This function will determine if the file playing is the current item in the list
	; It needs special handling because local file name change from e:\video to e:/video
	If $iListIndex = -1 Then return False 
	Local $str = _GUICtrlListView_GetItemText($iList, $iListIndex)
	$str = StringReplace($str, "\", "/")
	return $sFilePlaying = $str
EndFunc

Func SetLoopB()
	$iPosB = _GUICtrlSlider_GetPos($playSlider)
	If $iPosA >= $iPosB Then $iPosA = 0
	_GUICtrlSlider_SetSel($playSlider, $iPosA, $iPosB)
	If PlayingFileInList() Or (Not $bConnected And $iListIndex <> -1 ) Then 
		If _GUICtrlListView_GetItemText($iList, $iListIndex, Column("Length")) <> "" Then 
			; The file playing is the one in the list
			_GUICtrlListView_SetItemText($iList, $iListIndex, TimeConvert($iPosA), Column("A"))
			_GUICtrlListView_SetItemText($iList, $iListIndex, TimeConvert($iPosB), Column("B"))
		EndIf 
	EndIf
EndFunc


Func SliderSetTime()
	If $bConnected Then 
		; Connected. Now the slider controls the video position
		If $iLength = 0 Then 
			_GUICtrlSlider_SetPos($playSlider, 0)
			Return 
		EndIf
		Local $iNewPos = _GUICtrlSlider_GetPos($playSlider)

		If Abs($iNewPos - $iPosition)>5 Then GoPosition($iNewPos)
		; $iPosition = $iNewPos ; Prevent it from being called again.
	Else ; Not connected. The list item controls the slider
		
	EndIf 
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
	Return StringFormat('%01d:%02d:%02d', $iHour, $iMin, $iSec)
EndFunc

; Convert the HH:MM:SS back to seconds
Func TimeConvertBack($str)
	If StringInStr($str, ":", 2) = 0 Then Return 0
	Local $aTime = StringSplit($str, ":")
	Return Int($aTime[1]) * 3600 + Int($aTime[2]) * 60 + Int($aTime[3])
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
		If StringLeft($sLine, 8) = "#EXTINF:" then
			Local $aData[1][6]
			$sLine = StringTrimLeft($sLine, 8)
			Local $aResult = StringSplit($sLine, " ,")
			If $aResult[0] = 4 Then 
				; With A B data
				$aData[0][1] = $aResult[4]	; Title of the file
				$aData[0][4] = TimeConvert( Int(StringTrimLeft($aResult[2], 5)) ); Loop A
				$aData[0][5] = TimeConvert( Int(StringTrimLeft($aResult[3], 5)) ); Loop B
			ElseIf $aResult[0] = 2 Then
				; Withou A B data
				$aData[0][1] = $aResult[2] ; Title of the file
			EndIf
			
			If Int($aResult[1]) <> -1 Then
				$aData[0][3] = TimeConvert(Int($aResult[1])) ; Length of video
			EndIf
			$aData[0][0] = FileReadLine($hFile) ; The full file/path
			; Add the item.
			_GUICtrlListView_AddArray($iList, $aData)
			ContinueLoop
		EndIf
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
	
	; Write the required first line.
	FileWriteLine($hFile, "#EXTM3U")
	; Now write the file/path list
	Local $iCount = _GUICtrlListView_GetItemCount ($iList)
	For $i = 0 to $iCount-1
		Local $aData = _GUICtrlListView_GetItemTextArray ($iList, $i)
		Local $iVlength, $iVposA, $iVposB, $line = "#EXTINF:"
		If $aData[0] = 6 Then
			If $aData[4] <> "" Then
				; Has length data
				$iVlength = TimeConvertBack($aData[4])
			Else
				$iVlength = -1
			EndIf
			$line = $line & $iVlength
			If $aData[5] <> "" Then
				; Has Loop data
				
				$iVposA = TimeConvertBack($aData[5])
				$iVposB = TimeConvertBack($aData[6])
				$line = $line & " PosA=" & $iVposA & " PosB=" & $iVposB
			EndIf
			FileWriteLine($hFile, $line & "," & $aData[2]) ; $aData[2] is the name of the file.
		Else 
			FileWriteLine($hFile, "#EXTINF:-1, ")
		EndIf 
		; Write the real file/path on second line.
		FileWriteLine($hFile, $aData[1])
	Next
	FileClose($hFile)
	MsgBox($MB_ICONINFORMATION, "File Saved.", "This file:" & $sFileName & " was saved.")
EndFunc

Func PauseToggle()
	If Not $bConnected or $bCommandRunning Then return 1

	If $iPlayerState = 0 Then
		; Pause it
		SendCommand('{"playerState":1}')
		$bCommandRunning = True 
		$sFulFillCriteria = "$iPlayerState=1"
	Else
		; Play it
		SendCommand('{"playerState":0}')
		$bCommandRunning = True 
		$sFulFillCriteria = "$iPlayerState=0"
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
		_GUICtrlListView_SetItemText($iList, $iListIndex, "", Column("Status"))
	EndIf
	; Set the current index number
	$iListIndex = $iIndex

	If $bConnected Then
		Local $sText = _GUICtrlListView_GetItemText($iList, $iListIndex) ; Get current item's raw path
		Play($sText)
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "Playing", Column("Status"))
	Else 
		; Not connected, but can be selected as the active item.
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "Active", Column("Status"))
		
		; Set Length for slider
		Local $Vlength = _GUICtrlListView_GetItemText($iList, $iListIndex, Column("Length"))
		cw("length:" & $Vlength)
		If $Vlength <> "" Then
			SetSliderLength(TimeConvertBack($Vlength))
			; Set loop A B for slider
			Local $A = _GUICtrlListView_GetItemText($iList, $iListIndex, Column("A") )
			If $A <> "" Then
				Local $B = _GUICtrlListView_GetItemText($iList, $iListIndex, Column("B") )
				_GUICtrlSlider_SetSel($playSlider, TimeConvertBack($A), TimeConvertBack($B) )
			Else
				_GUICtrlSlider_ClearSel($playSlider)
			EndIf
		Else 
			_GUICtrlSlider_ClearSel($playSlider)
		EndIf 
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
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "", Column("Status"))
	EndIf
	
	$iListIndex = $iItemToPlay
	Local $sFile = _GUICtrlListView_GetItemText($iList, $iListIndex)
	; Set the playing item to "Playing"
	_GUICtrlListView_SetItemText ($iList, $iListIndex, "Playing", Column("Status"))
	_GUICtrlListView_SetItemSelected ($iList, $iListIndex)
	
	Play($sFile)
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
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "", Column("Status") )
	EndIf
	; Set the playing item to "Playing"
	Local $sNewText = _GUICtrlListView_GetItemText($iList, $iItemToPlay)
	_GUICtrlListView_SetItemText ($iList, $iItemToPlay, "Playing", Column("Status"))
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
					GUICtrlSendToDummy($Dummy2, $iIndex)
				Case $LVN_HOTTRACK ; When the user moves the mouse over an item
					$tInfo = DllStructCreate($tagNMLISTVIEW, $lParam)
					$gText = _GUICtrlListView_GetItemText($hWndFrom, DllStructGetData($tInfo, "Item"))
					If DllStructGetData($tInfo, "SubItem") = Column("Title") Then 
						ToolTip($gText, Default , Default , Default , Default , $TIP_BALLOON + $TIP_CENTER)
					Else 
						ToolTip("")
					EndIf 
			EndSwitch
    EndSwitch
    Return $GUI_RUNDEFMSG	; Let Autoit handle it from here.
EndFunc

Func WM_HVSCROLL($hwnd, $iMsg, $wParam, $lParam) ; Slider
    #forceref $hWnd, $iMsg, $wParam, $lParam
	
    $hWndSlider = $playSlider
    If Not IsHWnd($playSlider) Then $hWndSlider = GUICtrlGetHandle($playSlider)
	
    Switch $lParam
        Case $hWndSlider
			GUICtrlSendToDummy($Dummy, GUICtrlRead($playSlider))
    EndSwitch
	Return $GUI_RUNDEFMSG	; Let Autoit handle it from here.
EndFunc   ;==>WM_HVSCROLL

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
	$bCommandRunning =  False 
	If $iListIndex <> -1 Then 
		_GUICtrlListView_SetItemText ($iList, $iListIndex, "Active", Column("Status"))
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
		MsgBox(0, "Error", "Cannot add a directory to the list.")
		Return
	EndIf
	Local $sFileName = StringTrimLeft($sFile, StringInStr($sFile, "\", 2, -1))
	GUICtrlCreateListViewItem($sFile & "|" & $sFileName, $iList)
EndFunc

Func AddLink2Queue($sLink)
	If $sLink <> "" Then
		Local $sFileName = StringTrimLeft($sLink, StringInStr($sLink, "/", 2, -1))
		GUICtrlCreateListViewItem($sLink & "|" & $sFileName, $iList)
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
			$sCommand = '{"path":"' & $str & '","currentTime":0,"playerState":0}'
		Else 
			$sCommand = '{"path":"' & $str & '","playerState":0}'
		EndIf
		If $bCommandRunning Then
			MsgBox(0, "Waiting for command", "Sorry, still waiting for last command to take effect.")
			Return 
		EndIf
		SendCommand($sCommand)
		$bCommandRunning = True 
		$sFulFillCriteria = "$sFilePlaying=" & Q($str)
	EndIf 
EndFunc

Func Q($str)
	; Enclose the string with single quote.
	Return "'" & $str & "'"
EndFunc

Func FulFillCheck()
	; Check to see if the fulfill criteria is met.
	If $bCommandRunning Then
		GUICtrlSetData($connectStatus, "Command sent. Waiting DeoVR.")
	EndIf
	$done = Execute($sFulFillCriteria)
	If @error Then Return
	If $done Then
		$bCommandRunning = False
		GUICtrlSetData($connectStatus, "Command done.")
		$sFulFillCriteria = ""
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
	If $iPos < $iLength And $iPos >= 0 And Not $bCommandRunning Then 
		SendCommand($sCommand)
		$bCommandRunning = True 
		$sFulFillCriteria = "Abs($iPosition-" & $iPos & ")<5"
	EndIf 
EndFunc

Func Column($ColumnName)
	Switch $ColumnName
		Case "Title"
			Return 1
		Case "Status"
			Return 2
		Case "Length"
			Return 3
		Case "A"
			Return 4
		Case "B"
			Return 5
		Case Else
			Return 0
	EndSwitch
EndFunc

Func OnAutoItExit()
	; ConsoleWrite("here")
	If $iSocket <> 0 Then TCPCloseSocket($iSocket)
	TCPShutdown() ; Close the tcp service
	; Save the windows position and size
	Local $aSize = WinGetPos($MainForm)
	If Not @error Then 
		RegWrite("HKEY_CURRENT_USER\Software\DeoVR_Remote", "WinX", "REG_DWORD", $aSize[0])
		RegWrite("HKEY_CURRENT_USER\Software\DeoVR_Remote", "WinY", "REG_DWORD", $aSize[1])
		RegWrite("HKEY_CURRENT_USER\Software\DeoVR_Remote", "WinW", "REG_DWORD", $aSize[2])
		RegWrite("HKEY_CURRENT_USER\Software\DeoVR_Remote", "WinH", "REG_DWORD", $aSize[3])
		; Title Column Width
		Local $iListWidth = _GUICtrlListView_GetColumnWidth($iList, 1)
		RegWrite("HKEY_CURRENT_USER\Software\DeoVR_Remote", "ColW", "REG_DWORD", $iListWidth)
	EndIf
	GUIDelete()
   ; Exit 
EndFunc