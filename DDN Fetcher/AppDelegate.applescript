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
  global progressApp
  global latestFirefoxVersion
  global firefoxVersionFields
  
	property parent : class "NSObject"
	
	-- IBOutlets
	property theWindow : missing value
  
  property firefoxMinVersionField : missing value
  property firefoxMaxVersionField : missing value
  property groupPopup : missing value
  property stylePopup : missing value
  property outputView : missing value

	on applicationWillFinishLaunching_(aNotification)
    set progressApp to quoted form of POSIX path of (path to resource "SKProgressBar.app" as text)
    
    -- Insert code here to initialize your application before any files are opened
    loadFamilyList()
    
    -- Load the channel version information from the Mozilla site
    set latestFirefoxVersion to fetchLatestFirefoxVersion()
    set firefoxVersionFields to fetchFirefoxVersionFields()
--    log "VERSION FIELDS"
--    log firefoxVersionFields
	end applicationWillFinishLaunching_
	
	on applicationShouldTerminate_(sender)
		-- Insert code here to do any housekeeping before your application quits
    tell application "SKProgressBar" --progressApp
      quit
    end tell
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
    set fxMinVersion to stringValue() of firefoxMinVersionField as text
    set fxMaxVersion to stringValue() of firefoxMaxVersionField as text

    -- Empty out the results box
    outputView's setString:""
    
    set output to fetchFormattedList(fxMinVersion, fxMaxVersion, selectedFamily, listType) as text
    return output
  end okButtonPressed
  
  -- Handle changes to the version number field, to ensure it's valid
  on controlTextDidChange_(notificationObj)
    set editField to object of notificationObj
    set curValue to (stringValue() of editField as text)
    set gNSAlert to current application's NSAlert
    set fixedValue to ""
    set alertedAlready to false
    
    -- Go through the string and make sure it has no invalid characters.
    -- Remove any invalid characters and alert if any bad ones added.
    
    repeat with ch in the characters of curValue
      if ch ≠ "." and (ch < "0" or ch > "9") then
        if alertedAlready = false then
          set theAlert to gNSAlert's makeAlert_buttons_text_("Please enter a valid Firefox version number", {"OK"}, "Only the digits 0-9 and the decimal point are allowed in Firefox version numbers.")
          theAlert's showOver:theWindow calling:{"errorDismissed:", me}
          alertedAlready = true
        end if
      else
        set fixedValue to fixedValue & ch
      end if
    end repeat
    editField's setStringValue:fixedValue
  end controlTextDidChange_

  -- Called when the error is dismissed; theResult is the button name that was clicked
  on errorDismissed:theResult
  end errorDismmissed:
  
  -- Build the output
  on fetchFormattedList(fxMinVersion, fxMaxVersion, familyName, listType)
    set outputHTML to ""
    set format to ""
    set bugList to fetchResolvedDDNs(fxMinVersion, fxMaxVersion, familyName)
    
    -- If the bugs field is missing, an error occurred
    
    try
      set bugsOnly to bugs of bugList
      set bugCount to length of bugsOnly
    on error
      try
        set code to code of bugList
        
        -- Handle specific codes of interest
        
        if code = 105 or code = 106 then
          display alert "An invalid component (or product) was specified in the topic area's configuration file." as critical buttons {"Stop"}
        else if code = 108 then
          display alert ("The chosen version of Firefox doesn't support the standard fixed-status tracking fields (cf_status_firefox" & fxMinVersion & " in this case).") as critical buttons {"Stop"}
        else
          display alert ("Bugzilla reported an error handling the query [Error code: " & code & "].") as critical buttons ("Stop")
        end if
        return "" -- no results
      on error
        display alert "The response from Bugzilla was not recognized." as critical buttons {"Stop"}
        log bugList
        return "" -- no results
      end try
      display alert "No bugs returned by Bugzilla." as informational
    end try
    
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

    showResultsText(outputHTML, bugCount, listType, fxMinVersion)
    --showCompleteNotification(bugCount, fxMinVersion, listType)
    return outputHTML
  end fetchFormattedList
  
  -- Get the set of resolved DDN bugs for the given family and
  -- Firefox version
  on fetchResolvedDDNs(fxMinVersion, fxMaxVersion, familyName)
    set componentString to makeComponentString(selectedComponents)
    set fxVersionFilter to makeFirefoxVersionFilter(fxMinVersion, fxMaxVersion)

    tell application "JSON Helper"
      set bugURL to "https://bugzilla.mozilla.org/rest/bug?j_top=OR&query_format=advanced&keywords=dev-doc-needed" & fxVersionFilter & componentString & "&bug_status=RESOLVED&bug_status=VERIFIED&bug_status=CLOSED&include_fields=id,component,summary"
      set bugList to fetch JSON from bugURL
    end tell
    return bugList
  end fetchResolvedDDNs
  
  -- Create the Firefox version filter from the version(s) specified
  on makeFirefoxVersionFilter(fxMinVersion, fxMaxVersion)
    set versionFilter to ""
    set minVersionLength to length of (fxMinVersion as text)
    set maxVersionLength to length of (fxMaxVersion as text)
    
    -- If both lengths are 0, we do all bugs
    if minVersionLength + maxVersionLength = 0 then
      return versionFilter
    end if
    
    -- If no minimum version specified, use 5, since that's the earliest we can do
    
    if minVersionLength = 0 then
      fxMinVersion = 5
      firefoxMinVersionField's setStringValue:(fxMinVersion as text)
    end if
    
    -- If no maximum version specified, use the current version, which should be
    -- the latest, since it's nightly
    
    if maxVersionLength = 0 then
      set fxMaxVersion to latestFirefoxVersion
      firefoxMaxVersionField's setStringValue:(fxMaxVersion as text)
    end if
    
    -- Now build the filter string. To do this, find the entry in the saved
    -- field list whose fxVersion field matches fxMinVersion. Then add that
    -- to the filter, along with each entry following up to and including
    -- the one matching fxMaxVersion (or end of the list, whiechever comes
    -- first.
    
    set itemIndex to findVersionInVersionFieldList(fxMinVersion)
    set entry to item itemIndex of firefoxVersionFields
    set filterIndex to 1
    repeat while fxVersion of entry ≤ fxMaxVersion
      set aVersion to fxVersion of entry
      set versionFilter to versionFilter & "&f" & filterIndex & "=cf_status_firefox" & aVersion & "&o" & filterIndex & "=changedto&v" & filterIndex & "=fixed"
      set itemIndex to itemIndex+1
      set filterIndex to filterIndex+1
      set entry to item itemIndex of firefoxVersionFields
    end repeat

    return versionFilter
  end makeFirefoxVersionFilter
  
  -- Get list of valid Firefox version status fields
  on fetchFirefoxVersionFields()
    set currentStep to 0
    set iconPath to (path to resource "DDN Hunter Icons.icns" as text) as alias
    
    try
      set cache to loadVersionListCache()
      if fxVersion of last item in cache > latestFirefoxVersion then
        set cache to cache & {{fieldName: "cf_status_firefox" & latestFirefoxVersion, displayName: "status-firefox" & latestFirefoxVersion, fxVersion: latestFirefoxVersion}}
        saveVersionListCache(cache)
      end if
      return cache
    on error errorMessage number errorNumber
      log errorMessage
    end try
    
    tell application "SKProgressBar" --progressApp
      activate
      set title to "Firefox DDN Fetcher Progress"
      set floating to false
      set show window to true

      tell main bar
        set header to "Fetching all Bugzilla field names..."
        set header alignment to left
        set header size to regular
        set image path to iconPath
        set indeterminate to true
        start animation
        set minimum value to 0
        set maximum value to 1
        set current value to 0
      end tell
    
      tell application "JSON Helper"
        set allFields to fetch JSON from ("https://bugzilla.mozilla.org/rest/field/bug")
      end tell

      set fieldsObj to fields of allFields
      set fieldCount to length of fieldsObj
      set firefoxStatusFields to {}
      
      tell main bar
        set header to "Scanning for Firefox versions known to Bugzilla..."
        
        set minimum value to 0
        set maximum value to fieldCount
        set current value to 0
        set indeterminate to false
        start animation
      end tell
      
      repeat with field in fieldsObj
        if |name| of field starts with "cf_status_firefox" then
          set localFieldName to |name| of field
          set localDisplayName to display_name of field
          set versionNum to text 18 through end of localFieldName
          set newField to {fieldName: localFieldName, displayName: localDisplayName, fxVersion: versionNum}
          copy newField to the end of the firefoxStatusFields
        end if
        tell main bar to increment by 1
      end repeat
      tell main bar to stop animation
      quit -- Quits the progress bar help
    end -- tell progressApp
    set versionList to its sortByVersion:firefoxStatusFields
    saveVersionListCache(versionList)
    return versionList
  end fetchFirefoxVersionFields

  -- Save the version field list to a cache file
  on saveVersionListCache(versionList)
    set cachePath to path to preferences
    set cachePath to (the POSIX path of cachePath) & "Firefox DDN Fetcher.plist"

    set dict to {|versionCache|:versionList}

    tell application "System Events"
      tell (make new property list file with properties {name:cachePath})
        set value to dict
      end tell
    end tell
  end saveVersionListCache
  
  -- Load the version field list from the cache
  on loadVersionListCache()
    set cachePath to path to preferences
    set cachePath to (the POSIX path of cachePath) & "Firefox DDN Fetcher.plist"

    tell application "System Events"
      tell property list file cachePath
        set cacheData to value of property list item "versionCache"
      end tell
    end tell
    return cacheData
  end loadVersionListCache
  
  -- Obtain a single property from a plist file
  to getOneItem from plistItems -- get specified property list element by name or index
    try
      tell application "System Events"
        set thePlist to first item of plistItems -- start at the root element
        repeat with anItem in rest of plistItems -- add on the sub items
          set anItem to the contents of anItem
          try
            set anItem to anItem as integer -- index number?   (indexes start at 1)
          end try
          set thePlist to (get property list item anItem of thePlist)
        end repeat
        return value of thePlist
      end tell
      on error errorMessage number errorNumber
      log errorMessage
      error "getOneItem handler:  element not found (" & errorNumber & ")"
    end try
  end getPlistElement

  -- Sort the specified list of records
  on sortByVersion:versionList
    set sortDescriptor to current application's NSSortDescriptor's sortDescriptorWithKey:"fxVersion" ascending:true selector:"localizedCaseInsensitiveCompare:"
--    set sortDescriptor to current application's NSSortDescriptor's sortDescriptorWithKey:"fxVersion" ascending:true comparator:"localizedCaseInsensitiveCompare:"
    set theArray to current application's NSArray's arrayWithArray:versionList
    return (theArray's sortedArrayUsingDescriptors:{sortDescriptor}) as list
--    return (theArray's sortedArrayUsingFunction:compareVersions context:null) as list
  end sortByVersion:

  on compareVersions(num1, num2, context)
    set v1 to floatValue of num1
    set v2 to floatValue of num2
    
    if v1 < v2 then
      return current application's NSOrderedAscending
    else if v1 > v2 then
      return current application's NSOrderedDescending
    end if
    return current application's NSOrderedSame
  end compareVersions
  
  -- Return the index into the version record list of the entry matching the
  -- specified version number
  on findVersionInVersionFieldList(whichVersion)
    set indexNum to 1
    repeat with entry in firefoxVersionFields
      if fxVersion of entry is equal to (whichVersion as text) then
        return indexNum
      end if
      set indexNum to indexNum+1
    end repeat
    return 0 -- not found
  end findVersionInVersionFieldList

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
  on showCompleteNotification(length, fxMinVersion, format)
    if (length > 0) then
      set msg to "Found " & (length as string) & " " & selectedFamily & " DDN bugs for Firefox " & (fxMinVersion as string) & ". which are marked dev-doc-needed" & ¬
        " Returned in " & format & " format."
    else
      set msg to "No " & selectedFamily & " bugs found for Firefox " & (fxMinVersion as string) & " which are marked dev-doc-needed."
    end if
    display notification msg with title (selectedFamily & " DDN Bugs Retrieved")
  end showCompleteNotification

  -- Show the output to the user
  on showResultsText(output, length, format, fxMinVersion)
    outputView's setString:output
  end showResultsText
  
  -- Fetch the latest Firefox version (Nightly channel) from the JSON file
  -- maintained on product-details.mozilla.org.
  on fetchLatestFirefoxVersion()
    tell application "JSON Helper"
      set versionInfo to fetch JSON from ("https://product-details.mozilla.org/1.0/firefox_versions.json")
      
      set the text item delimiters of AppleScript to {"a", "b", "E"}
      set bits to text items of (FIREFOX_NIGHTLY of versionInfo)
      set the text item delimiters of AppleScript to ", "
      set num to first item of bits as text
      if num ends with ".0" then
        set num to text 1 through -3 of num
      end if
      return num
    end tell
    return 0
  end fetchLatestFirefoxVersion
  
--  on awakeFromNib_(theObject)
--    log "AWAKENED!"
--  end awake from nib
end script
