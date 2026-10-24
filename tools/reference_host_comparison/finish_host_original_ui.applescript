on exactIndex(availableNames, allowedNames)
 set foundIndex to 0
 considering case
  repeat with itemIndex from 1 to count of availableNames
   if allowedNames contains (item itemIndex of availableNames) then
    if foundIndex is not 0 then error "Ambiguous exact menu selection"
    set foundIndex to itemIndex
   end if
  end repeat
 end considering
 if foundIndex is 0 then error "Exact menu selection unavailable"
 return foundIndex
end exactIndex

on exportOriginal(targetPID, asWAV, cacheRoot)
 tell application "System Events"
  tell (first application process whose unix id is targetPID)
   set slot to 5
   if asWAV then set slot to 6
   if not enabled of button slot of scroll area 1 of group 1 of window 1 then return "NOT_AVAILABLE"
   click button slot of scroll area 1 of group 1 of window 1
   delay 0.1
   set promptContainer to window 1
   if exists sheet 1 of window 1 then set promptContainer to sheet 1 of window 1
   set promptText to value of every static text of promptContainer
   set oldDelimiters to AppleScript's text item delimiters
   set AppleScript's text item delimiters to linefeed
   set promptString to promptText as text
   set AppleScript's text item delimiters to oldDelimiters
   if promptString does not contain "Export local evidence?" then error "Original export confirmation mismatch"
   if promptString does not contain cacheRoot then error "Unexpected export destination"
   if not (exists button "Export" of promptContainer) then error "Original Export button unavailable"
   click button "Export" of promptContainer
   delay 0.1
   return promptString
  end tell
 end tell
end exportOriginal

on run argv
 if count of argv is not 2 then error "Expected exact PID and approved cache root"
 set targetPID to (item 1 of argv) as integer
 if targetPID <= 0 then error "Invalid process identity"
 set cacheRoot to item 2 of argv
 if cacheRoot does not end with "/com.eterna.aftelle.debug-apple-vp-evidence" then error "Unexpected cache root"
 with timeout of 12 seconds
  tell application "System Events"
   tell (first application process whose unix id is targetPID)
    set frontmost to true
    set stateText to ""
    repeat 160 times
     set valuesList to value of every static text of scroll area 1 of group 1 of window 1
     set oldDelimiters to AppleScript's text item delimiters
     set AppleScript's text item delimiters to linefeed
     set stateText to valuesList as text
     set AppleScript's text item delimiters to oldDelimiters
     if stateText contains "phase=sealed" then exit repeat
     delay 0.025
    end repeat
    if stateText does not contain "phase=sealed" then error "Original App has not sealed; preserve stop and reap"
   end tell
  end tell
  set jsonResult to my exportOriginal(targetPID, false, cacheRoot)
  if jsonResult is "NOT_AVAILABLE" then error "Failure JSON unavailable"
  set wavResult to my exportOriginal(targetPID, true, cacheRoot)
  tell application "System Events"
   tell (first application process whose unix id is targetPID)
    if name is not "Aftelle" then error "Unexpected process name for exact PID"
    set appMenuIndex to my exactIndex(name of every menu bar item of menu bar 1, {"Aftelle"})
    set appMenu to menu 1 of menu bar item appMenuIndex of menu bar 1
    set quitIndex to my exactIndex(name of every menu item of appMenu, {"Quit Aftelle", "退出Aftelle", "退出 Aftelle"})
    set selectedTitle to name of menu item quitIndex of appMenu
    if not enabled of menu item quitIndex of appMenu then error "Exact App Quit is disabled"
    click menu item quitIndex of appMenu
   end tell
  end tell
  return "APP_QUIT_MENU_SELECTED=" & selectedTitle & linefeed & stateText & linefeed & "JSON_EXPORT_CONFIRMED" & linefeed & jsonResult & linefeed & "WAV_EXPORT_RESULT" & linefeed & wavResult
 end timeout
end run
