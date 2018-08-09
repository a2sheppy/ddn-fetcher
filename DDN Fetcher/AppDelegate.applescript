--
--  AppDelegate.applescript
--  DDN Fetcher
--
--  Created by Eric Shepherd on 8/3/18.
--  Copyright © 2018 Mozilla. All rights reserved.
--

use framework "Foundation"
use framework "AppKit"
use scripting additions

script AppDelegate
  global apiFamilyDict
  global apiFamilyList
  global apiFamilyObjCDict
  global selectedFamily
  global selectedComponents
  
	property parent : class "NSObject"
	
	-- IBOutlets
	property theWindow : missing value
  
  property firefoxVersionField : missing value
  property groupPopup : missing value
  property stylePopup : missing value
  property outputView : missing value

	on applicationWillFinishLaunching_(aNotification)
		-- Insert code here to initialize your application before any files are opened
    loadFamilyList()
	end applicationWillFinishLaunching_
	
	on applicationShouldTerminate_(sender)
		-- Insert code here to do any housekeeping before your application quits 
		return current application's NSTerminateNow
	end applicationShouldTerminate_
	
  on loadFamilyList()
    set plistPath to ((path to resource "APIFamilies.plist") as string)
    
    tell application "System Events"
      set plistFile to property list file plistPath
      set apiFamilyDict to contents of plistFile
      set apiFamilyList to value of apiFamilyDict
      set apiFamilyObjCDict to current application's NSDictionary's dictionaryWithDictionary:apiFamilyList
      set familyNames to apiFamilyObjCDict's allKeys()
      
      -- Go over the items in the family list and add the family names
      -- to the popup
      
      groupPopup's removeAllItems()
      repeat with family in familyNames
        groupPopup's addItemWithTitle:family
      end repeat
    end tell
  end loadFamilyList
  
  on okButtonPressed:sender
    set selectedFamily to groupPopup's titleOfSelectedItem() as string
    set selectedComponents to apiFamilyObjCDict's valueForKey:selectedFamily
    set listType to stylePopup's titleOfSelectedItem() as string

    set editable of outputView to false
    outputView's setFont_(current application's NSFont's fontWithName_size_("Menlo", 12))
    
    set output to fetchFormattedList(stringValue() of firefoxVersionField, selectedFamily, listType) as text
    return output
  end okButtonPressed
  
  -- Build the output
  on fetchFormattedList(fxVersion, familyName, listType)
    set bugList to fetchResolvedDDNs(fxVersion, familyName)
    set bugCount to length of bugs in bugList
    set outputHTML to ""
    set format to ""
    
    -- Determine the proper formatting string based on the list type
    -- requested by the caller
    
    if listType = "Markdown Bullet List" then
      set format to "* [$name](https://bugzilla.mozilla.org/show_bug.cgi?id=$bugid) ($component)"
    else if listType is equal to "Markdown Checklist" then
      set format to "- [ ] [$name](https://bugzilla.mozilla.org/show_bug.cgi?id=$bugid) ($component)"
    else if listType is equal to "HTML Bullet List" then
      set format to "<li><a href='https://bugzilla.mozilla.org/show_bug.cgi?id=$bugid'>$name</a> ($component)</li>"
    else if listType is equal to "HTML Plain Links" then
      set format to "<a href='https://bugzilla.mozilla.org/show_bug.cgi?id=$bugid'>$name</a> ($component)<br>"
    else
      return ""
    end if
    
    repeat with bug in bugs of bugList
      set bugName to summary of bug
      set bugComponent to component of bug
      set bugID to |id| of bug
      
      set bugHTML to replaceSubstring(format, "$bugid", bugID as string)
      set bugHTML to replaceSubstring(bugHTML, "$name", bugName)
      set bugHTML to replaceSubstring(bugHTML, "$component", bugComponent)
      set outputHTML to outputHTML & bugHTML & return
    end repeat

    showResultsText(outputHTML, bugCount, listType, fxVersion)
    showCompleteNotification(bugCount, fxVersion, listType)
    return outputHTML
  end fetchFormattedList
  
  -- Get the set of resolved DDN bugs for the given family and
  -- Firefox version
  on fetchResolvedDDNs(fxVersion, familyName)
    set componentString to makeComponentString(selectedComponents)

    tell application "JSON Helper"
      set bugURL to "https://bugzilla.mozilla.org/rest/bug?keywords=dev-doc-needed&f1=cf_status_firefox" & fxVersion & "&o1=changedto&v1=fixed" & componentString & "&bug_status=RESOLVED&bug_status=VERIFIED&bug_status=CLOSED&include_fields=id,component,summary"
      
      set bugList to fetch JSON from bugURL
    end tell
    return bugList
  end fetchResolvedDDNs
  
  -- Convert an array of component names into the needed
  -- form for use in the Bugzilla query
  on makeComponentString(components)
    set componentString to ""
    repeat with component in components
      set componentString to componentString & "&component=" & component
    end repeat
    return componentString
  end makeComponentString

  on indexof(theItem, theList) -- credits Emmanuel Levy
    set oTIDs to AppleScript's text item delimiters
    set AppleScript's text item delimiters to return
    set theList to return & theList & return
    set AppleScript's text item delimiters to oTIDs
    try
      -1 + (count (paragraphs of (text 1 thru (offset of (return & theItem & return) in theList) of theList)))
      on error
      0
    end try
  end indexof

  -- Given a string this_text, find within it the given search_string
  -- and replace it with replacement_string
  on replaceSubstring(this_text, search_string, replacement_string)
    set AppleScript's text item delimiters to the search_string
    set the item_list to every text item of this_text
    
    set AppleScript's text item delimiters to the replacement_string
    set this_text to the item_list as string
    set AppleScript's text item delimiters to ", "
    return this_text
  end replaceSubstring
  
  -- Show the "search complete" notification.
  on showCompleteNotification(length, fxVersion, format)
    if (length > 0) then
      set msg to "Found " & (length as string) & " " & selectedFamily & " DDN bugs for Firefox " & (fxVersion as string) & ". which are marked dev-doc-needed" & ¬
        " Returned in " & format & " format."
    else
      set msg to "No " & selectedFamily & " bugs found for Friefox " & (fxVersion as string) & " which are marked dev-doc-needed."
    end if
    display notification msg with title (selectedFamily & " DDN Bugs Retrieved")
  end showCompleteNotification

  -- Show the output to the user
  on showResultsText(output, length, format, fxVersion)
    outputView's setString:output
  end showResultsText

end script
