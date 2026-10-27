on run argv
	set targetPID to (item 1 of argv) as integer
	set approvedAssetPath to item 2 of argv
	with timeout of 10 seconds
		tell application "System Events"
			tell (first application process whose unix id is targetPID)
				set frontmost to true
				repeat 120 times
					if exists scroll area 1 of group 1 of window 1 then exit repeat
					delay 0.025
				end repeat
				if (count of buttons of scroll area 1 of group 1 of window 1) is not 6 then error "Unexpected acoustic controls"
				if not enabled of button 1 of scroll area 1 of group 1 of window 1 then error "Prepare not ready"
				click button 1 of scroll area 1 of group 1 of window 1
				click button 2 of scroll area 1 of group 1 of window 1
				repeat 30 times
					if name of window 1 is "打开" then exit repeat
					delay 0.05
				end repeat
				if name of window 1 is not "打开" then error "Original NSOpenPanel missing"
				keystroke "g" using {command down, shift down}
				repeat 30 times
					if exists text field 1 of sheet 1 of window 1 then exit repeat
					delay 0.05
				end repeat
				set value of text field 1 of sheet 1 of window 1 to approvedAssetPath
				key code 36
				repeat 30 times
					if not (exists sheet 1 of window 1) then exit repeat
					delay 0.05
				end repeat
				if name of window 1 is not "打开" then error "OpenPanel unexpectedly closed"
				key code 36
				repeat 30 times
					if (count of windows) is 1 and name of window 1 is "Aftelle" then exit repeat
					delay 0.05
				end repeat
				if (count of buttons of scroll area 1 of group 1 of window 1) is not 6 then error "Unexpected prepared layout"
				if not enabled of button 3 of scroll area 1 of group 1 of window 1 then error "App rejected approved material"
				return "PREPARED_FOR_ORIGINAL_START_CONFIRMATION_NO_CAPTURE"
			end tell
		end tell
	end timeout
end run
