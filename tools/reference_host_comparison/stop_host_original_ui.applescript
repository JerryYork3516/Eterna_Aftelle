on run argv
 if count of argv is not 1 then error "Expected exact PID"
 set targetPID to (item 1 of argv) as integer
 if targetPID <= 0 then error "Invalid process identity"
 with timeout of 5 seconds
  tell application "System Events"
   tell (first application process whose unix id is targetPID)
    if name is not "Aftelle" then error "Unexpected exact PID"
    set valuesList to value of every static text of scroll area 1 of group 1 of window 1
    repeat with stateLine in valuesList
     if stateLine contains "phase=sealed" then return "ALREADY_SEALED"
    end repeat
    if not enabled of button 4 of scroll area 1 of group 1 of window 1 then error "Original Stop disabled"
    click button 4 of scroll area 1 of group 1 of window 1
    return "ORIGINAL_STOP_SELECTED"
   end tell
  end tell
 end timeout
end run
