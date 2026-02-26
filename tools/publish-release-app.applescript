-- publish-release-app.applescript
-- Prompts for a tag and title, optionally zips themes, then runs publish-release.sh in Terminal
-- The Terminal window remains open so you can inspect output and press RETURN to close.

property repoPath : "/Users/sexybitch/Sites/zed-themes"
property scriptName : "publish-release.sh"
property scriptPath : repoPath & "/" & scriptName

-- Ensure the repo/script exists
on fileExists(thePath)
	try
		do shell script "test -e " & quoted form of thePath & " && printf OK || printf NO"
		return true
	on error
		return false
	end try
end fileExists

if not fileExists(repoPath) then
	display alert "Repository not found" message "The repository path does not exist: " & repoPath as string
	return
end if

if not fileExists(scriptPath) then
	display alert "Script not found" message "publish-release.sh not found in: " & repoPath as string
	return
end if

-- Make sure script is executable
try
	do shell script "chmod +x " & quoted form of scriptPath with administrator privileges
on error
	-- If the user cancels sudo prompt or it fails, continue without escalating; publish script may still be executable
end try

-- Ask for tag
set defaultTag to "v1.0.0"
set tagResult to display dialog "Enter release tag (e.g. v1.0.0):" default answer defaultTag buttons {"Cancel", "Continue"} default button "Continue"
set theTag to text returned of tagResult
if theTag is "" then
	display alert "Invalid tag" message "Tag cannot be empty."
	return
end if

-- Ask for title (optional)
set titleResult to display dialog "Enter release title (optional, press Continue to use tag as title):" default answer theTag buttons {"Cancel", "Continue"} default button "Continue"
set theTitle to text returned of titleResult
if theTitle is "" then set theTitle to theTag

-- Ask whether to zip themes
set zipPrompt to display dialog "Include a zip of the themes/ directory as an asset?" buttons {"No", "Yes"} default button "Yes"
set zipChoice to button returned of zipPrompt
set doZip to (zipChoice is "Yes")

-- Confirm draft behavior (create as draft)
set draftPrompt to display dialog "Create release as a draft for one-click approval in browser?" buttons {"No (publish immediately)", "Yes (draft)"} default button "Yes"
set draftChoice to button returned of draftPrompt
set asDraft to (draftChoice is "Yes")

-- Confirm proceed
set confirmMsg to "About to run publish script with:\n\n• tag: " & theTag & "\n• title: " & theTitle & "\n• zip themes: " & (doZip as string) & "\n• as draft: " & (asDraft as string) & "\n\nProceed?"
set conf to display dialog confirmMsg buttons {"Cancel", "Run"} default button "Run"
if button returned of conf is "Cancel" then return

-- Build command to run in bash
set quotedRepo to quoted form of repoPath
set quotedTag to quoted form of theTag
set quotedTitle to quoted form of theTitle

set optionsList to ""
if doZip then set optionsList to optionsList & " --zip-themes"
if asDraft is false then set optionsList to optionsList & " --no-draft"
-- We run with --yes to avoid interactive prompts inside publish-release.sh; Terminal will still show output.
set optionsList to optionsList & " --yes"

set innerCmd to "cd " & quotedRepo & " && ./" & scriptName & " --tag " & quotedTag & " --title " & quotedTitle & optionsList

-- Wrap for bash -lc so environment and PATH are predictable. Keep terminal open after completion for inspection.
set bashCmd to "/bin/bash -lc " & quoted form of (innerCmd & " ; echo \"\" ; echo \"--- publish script finished ---\" ; echo \"Press RETURN to close this window...\" ; read -r line")

-- Open Terminal and run the command in a new window
tell application "Terminal"
	activate
	try
		-- Create a new window and run command
		do script bashCmd
	on error errMsg
		-- On some macOS versions, creating a new window may fail; fall back to do script anyway
		do script bashCmd in front window
	end try
end tell

return