;*****************************************
;DeoVR_Remote.au3 by Philip
;Created with ISN AutoIt Studio v. 1.13
;*****************************************
#AutoIt3Wrapper_Res_HiDpi=Y

; #include <ColorConstants.au3>
#include <json.au3>
#include "Forms\MainForm.isf"
#include <WinAPIFiles.au3>

; Global initialization
; Opt("GUIOnEventMode", 1) ; cannot use event mode because of the loop

TCPStartup() ; Start the tcp service

OnAutoItExitRegister("OnAutoItExit") ; This doesn't work in event mode.
; GUISetOnEvent($GUI_EVENT_CLOSE, "OnAutoItExit")

Global $bConnected = False , $iSocket = 0

GUISetState(@SW_SHOW,$MainForm)

Local $iSecond =  @SEC, $hTimer = TimerInit(), $hLastPlayTimer = TimerInit()
Local $iCount =  0, $bHaveData = False

Global $iLength, $iPosition, $bPlayFromStart = False ; Current video length and position
Global $iListIndex = -1
GUIRegisterMsg($WM_NOTIFY, "_WM_NOTIFY") ; For list view's double click event.
$cDummy = GUICtrlCreateDummy() 			; Dummy to accept double click event.

While True
	
	$nMsg = GUIGetMsg()
	Switch $nMsg
		Case $GUI_EVENT_CLOSE
			Exit
		Case $btnConnect
			Connect()
		Case $playFile
			PlayLocalFile()
		Case $playLink
			PlayLink()
		Case $GUI_EVENT_DROPPED
			; ConsoleWrite("DropID:" & @GUI_DropId & " fileLink:" & $fileLinkInput & " Drop file:" & @GUI_DragFile & @CRLF)
		Case $jumpBack
			JumpBack()
		Case $jumpForward
			JumpForward()
		Case $addFileToQueue
			AddFile2Queue()
		Case $addLinkToQueue
			AddLink2Queue()
		Case $btnDelete
			DeleteItem()
		Case $chkPlayFromBeginning
			SetPlayFromStart()
		Case $cDummy	; Double click event
			PlayCurrentItem()
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
		; Get message from DeoVR
		Local $iTimePass = TimerDiff($hTimer), $iSize
		
		If $iTimePass > 100 Then ; Check it every 100 ms.
			Local $iSize = TCPRecv($iSocket, 4, 1) , $sData = ""
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
						GUICtrlSetData($filePlaying, $oResult.Item("path" ) ); Display file path and name
						If $oResult.Item("playerState") = "0" Then
							GUICtrlSetData($playerState, "Playing" )
						ElseIf $oResult.Item("playerState") = "1" Then 
							GUICtrlSetData($playerState, "Paused" )
						EndIf
						; Done, now reset the variable
						$sData = ""
						; Below updates statis.
						$iLength = Floor(Int($oResult.Item("duration")))
						$iPosition = Floor(Int($oResult.Item("currentTime")))
						GUICtrlSetData($videoLength, TimeConvert($iLength) ) ; Display the video length
						GUICtrlSetData($videoPosition, TimeConvert($iPosition) )
						GUICtrlSetData($playingSpeed, $oResult.Item("playbackSpeed") )
						GUICtrlSetData($playProgress, Floor($iPosition / $iLength * 100) )
					EndIf 
				EndIf
			EndIf
			; Timer reset.
			$hTimer = TimerInit()
		EndIf
		
		If $iSecond <> @SEC Then
			; Do this every second.
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
		EndIf 
	Else
		; Disconnected. Reset all data.
		If GUICtrlRead($filePlaying) <> "" Then 
			ResetData()
		EndIf
	EndIf
WEnd

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

Func TimeConvert($i)
	Local $iHour =  Floor($i / 3600) 
	Local $iMin = Floor( ($i - 3600 * $iHour) / 60)
	Local $iSec = Mod($i, 60)
	Return StringFormat('%02d:%02d:%02d', $iHour, $iMin, $iSec)
EndFunc

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
	Local $sState = GUICtrlRead($playerState)
	If $sState = "Playing" Then
		; Pause it
		SendCommand('{"playerState":1}')
		; Set play icon.
		; GUICtrlSetImage($btnPause,@scriptdir&"\"&"Images\Forward.ico")
		GUICtrlSetData($btnPause, "Play")
	ElseIf $sState = "Paused" Then
		; Play it
		SendCommand('{"playerState":0}')
		; GUICtrlSetImage($btnPause,@scriptdir&"\"&"Images\pause.ico")
		GUICtrlSetData($btnPause, "Pause")
	EndIf
EndFunc

Func SendCommand($sCommand)
	If $iSocket = 0 or not $bConnected Then Return
	
	Local $iLength = Int(BinaryLen($sCommand), 1) ; Making sure it's 4 bytes int.
	Local $sSend = BinaryToString(Binary($iLength) & Binary($sCommand))
	TCPSend($iSocket, $sSend)
	If @error Then
		ConsoleWrite("Error sending:" & $iLength & $sCommand & @CRLF)
	Else
		ConsoleWrite("Command Sent: " & $sCommand &  @CRLF)
	EndIf
EndFunc

Func PlayCurrentItem()
	; Set the previous playing item to nothing
	
	; If $iListIndex = -1 then no previous item is playing
	
	If $iListIndex <> -1 Then 
		; Set previous playing to nothing
		_GUICtrlListView_SetItemText($iList, $iListIndex, "", 1)
	EndIf
	; Set the current index number
	$iListIndex = _GUICtrlListView_GetHotItem ($iList)

	If $iListIndex = -1 Then Return

	Local $sText = _GUICtrlListView_GetItemText($iList, $iListIndex) ; Get current item's text
	Play($sText)
	_GUICtrlListView_SetItemText ($iList, $iListIndex, "Playing", 1)
EndFunc

Func PlayPreviousItem()
	Local $iCount = _GUICtrlListView_GetItemCount($iList), $iItemToPlay
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

Func PlayNextItem()
	Local $iCount = _GUICtrlListView_GetItemCount($iList), $iItemToPlay
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

Func _WM_NOTIFY($hWnd, $iMsg, $wParam, $lParam)
	#forceref $hWnd, $iMsg, $wParam
	; This one handles list view's double click event.
	Local $hWndFrom, $iIDFrom, $iCode, $tNMHDR, $hWndListView, $tInfo
    $hWndListView = $iList
    If Not IsHWnd($iList) Then $hWndListView = GUICtrlGetHandle($iList)

    $tNMHDR = DllStructCreate($tagNMHDR, $lParam)
    $hWndFrom = HWnd(DllStructGetData($tNMHDR, "hWndFrom"))
    $iCode = DllStructGetData($tNMHDR, "Code")

    Switch $hWndFrom
		Case $hWndListView
			Switch $iCode
				Case $NM_DBLCLK
					GUICtrlSendToDummy($cDummy)
			EndSwitch
    EndSwitch
    Return $GUI_RUNDEFMSG
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
		GUICtrlSetData($playerState, "" )
		GUICtrlSetData($videoLength, "" )
		GUICtrlSetData($videoPosition, "" )
		GUICtrlSetData($playingSpeed, "" )
		GUICtrlSetData($playProgress, 0 )
	EndIf 
EndFunc

Func AddFile2Queue()
	; cw("here")
	Local $sFile =  StringStripWS( GUICtrlRead($fileLinkInput), 1 + 2 )
	If Not FileExists($sFile) Then
		Local $reply = MsgBox($MB_OK + $MB_ICONWARNING, "File not exist.", _
			"This file does not exist, are you sure to add it to the list?")
		If $reply = $IDCANCEL Then Return
	EndIf
	GUICtrlCreateListViewItem($sFile & "|", $iList)
	GUICtrlSetData($fileLinkInput, "")
EndFunc

Func AddLink2Queue()
	Local $sLink = StringStripWS( _GUICtrlRichEdit_GetText($linkInput), 1 + 2) ; strip leading and trailing white spaces.
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

Func PlayLocalFile()
	Local $sFile =  GUICtrlRead($fileLinkInput)
	If Not FileExists($sFile) Then
		Local $reply = MsgBox($MB_OKCANCEL + $MB_ICONWARNING, "File not exist.", _ 
			"This file doesn't exist, still want to play it anyway?")
		If $reply = $IDCANCEL Then Return
	EndIf
	Play(StringReplace($sFile, "\", "/"))
	GUICtrlSetData($fileLinkInput, "")
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
	Local $state =  GUICtrlRead($btnConnect)
	If $state =  "Connect" Then 
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
	Elseif $state =  "Disconnect" Then
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
EndFunc

Func OnAutoItExit()
   ; ConsoleWrite("here")
   If $iSocket <> 0 Then TCPCloseSocket($iSocket)
   TCPShutdown() ; Close the tcp service
   ; Exit 
EndFunc