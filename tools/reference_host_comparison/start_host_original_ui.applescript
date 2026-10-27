on run argv
 set targetPID to (item 1 of argv) as integer
 with timeout of 8 seconds
 tell application "System Events"
  tell (first application process whose unix id is targetPID)
   set frontmost to true
   if not enabled of button 3 of scroll area 1 of group 1 of window 1 then error "Original Start disabled"
   click button 3 of scroll area 1 of group 1 of window 1
   delay 0.1
   if value of static text 1 of sheet 1 of window 1 is not "Allow local test?" then error "Original start consent mismatch"
   if description of button 1 of sheet 1 of window 1 is not "Use microphone, local capture and test playback" then error "Original consent scope mismatch"
   click button 1 of sheet 1 of window 1
   return "ORIGINAL_START_CONFIRMATION_CLICKED_ONCE"
  end tell
 end tell
 end timeout
end run
