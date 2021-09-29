;gamepad.au3

Const $iStickLow = 10000, $iStickHigh = 50000  ; 0 to 65535

Func _JoyInit()
	; Create a new joystick/gamepad pointer as the $lpJoy below.
    Local $joy
    Global $JOYINFOEX_struct = "dword[13]"
    $joy = DllStructCreate($JOYINFOEX_struct)
    If @error Then Return 0
    DllStructSetData($joy, 1, DllStructGetSize($joy), 1);dwSize = sizeof(struct)
    DllStructSetData($joy, 1, 255, 2) ;dwFlags = GetAll
    Return $joy
EndFunc   ;==>_JoyInit


;======================================
;   _GetJoy($lpJoy,$iJoy)
;   $lpJoy  Return from _JoyInit()
;   $iJoy   Joystick # 0-15
;   Return  Array containing X-Pos, Y-Pos, Z-Pos, R-Pos, U-Pos, V-Pos,POV
;           Buttons down
;
;           *POV This is a digital game pad, not analog joystick
;           65535   = Not pressed
;           0       = U
;           4500    = UR
;           9000    = R
;           Goes around clockwise increasing 4500 for each position
;======================================
Func _GetJoy($lpJoy, $iJoy)
    Local $coor[8]
    DllCall("Winmm.dll", "int", "joyGetPosEx", _
            "int", $iJoy, _
            "ptr", DllStructGetPtr($lpJoy))
    If @error Then
		Return 0
	Else 
        $coor[0] = DllStructGetData($lpJoy, 1, 3) ; Stick 1 axis, 0 to 65535; left to right
        $coor[1] = DllStructGetData($lpJoy, 1, 4) ; Stick 2 axis, 0 to 65535; up to down
        $coor[2] = DllStructGetData($lpJoy, 1, 5) ; Stick 3 axis, 0 to 65535
        $coor[3] = DllStructGetData($lpJoy, 1, 6) ; Stick 4 axis, 0 to 65535
        $coor[4] = DllStructGetData($lpJoy, 1, 7)
        $coor[5] = DllStructGetData($lpJoy, 1, 8)
        $coor[6] = DllStructGetData($lpJoy, 1, 11)
        $coor[7] = DllStructGetData($lpJoy, 1, 9) ; Button press info. The $Val below.
    EndIf
    Return $coor
EndFunc   ;==>_GetJoy

Func UpPressed(ByRef $coor) ; The $coor returned by _GetJoy()
	If UBound($coor) <> 8 Then return False ; Not the right data
	return $coor[1] < $iStickLow
EndFunc

Func DownPressed(ByRef $coor) ; The $coor returned by _GetJoy()
	If UBound($coor) <> 8 Then return False ; Not the right data
	return $coor[1] > $iStickHigh
EndFunc

Func LeftPressed(ByRef $coor)
	If UBound($coor) <> 8 Then return False ; Not the right data
	return $coor[0] < $iStickLow
EndFunc

Func RightPressed(ByRef $coor)
	If UBound($coor) <> 8 Then return False ; Not the right data
	return $coor[0] > $iStickHigh
EndFunc

Func GetPressed($Val) ; The $coor[7] from _GetJoy()
    $SButtons = ''
    If BitAND($Val, 1) Then $SButtons &= '(A)'
    If BitAND($Val, 2) Then $SButtons &= '(B)'
    If BitAND($Val, 4) Then $SButtons &= '(X)'
    If BitAND($Val, 8) Then $SButtons &= '(Y)'
    If BitAND($Val, 16) Then $SButtons &= '(LB)'
    If BitAND($Val, 32) Then $SButtons &= '(RB)'
    If BitAND($Val, 64) Then $SButtons &= '(Back)'
    If BitAND($Val, 128) Then $SButtons &= '(Start)'
    If BitAND($Val, 256) Then $SButtons &= '(LS)'
    If BitAND($Val, 512) Then $SButtons &= '(RS)'
    Return $SButtons
EndFunc   ;==>GetPressed
