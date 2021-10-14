# DeoVR Remote
<img src="https://user-images.githubusercontent.com/22040708/137249192-e2fa0a72-33fd-4db5-bc95-d01490cd6abf.png" width='500' />

 This is a Windows based DeoVR remote control program, written in AutoIt3. AutoIt3 is the best in writing small simple GUI programs.
 GUI is designed by ISN AutoIt Studio. That Germany guy really rocks!
 
 DeoVR player offers simple remote control function at port 23554, and this remote program utilize it to add features like playlist, jumping forward and back...
 
 To use it:
 * First you need to run DeoVR in SteamVR or other platforms, then in DeoVR you need to turn on the "Remote control" in the settings.
 DeoVR only accepts remote connections when in the player mode, which means you need to play some video then pause it.
 * Once DeoVR is ready, you can come back to this program and click on "Connect". Once it's connected, it will show you what file DeoVR is playing, video duration, the position...etc.
 * This program adds a play list for DeoVR. You can drag local files to the list, or drag a URL to the branket, then add it to the list. The URL should be a direct link, like "https://mywebsite.com/myvideo.mp4", not a stream link like "rtsp://example.com/abcstream". After that, just double click on an item in the list to start playing that file/link.
 * Now you can save the list with indepent A B Loop settings. Also the list will only show the file name, not the full path.
 * Now you can use gamepad to control the playback. ~~Left to jump back, right to jump forward,~~ (DeoVR has build-in support for left and right buttons) Up to play previous file/link, down to play next file/link, button B to Play/Pause. ( Actually I am surprised that there is no way to do one button play/pause in DeoVR. That should be a very basic feature.)
