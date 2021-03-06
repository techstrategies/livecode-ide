﻿script "revIDEDeveloperExtensionLibrary"
local sExtensionDetailsA

private on __revIDEDeveloperExtensionSendWarning pWarning
   revIDEMessageSend "ideExtensionLog", "Warning:" && pWarning
end __revIDEDeveloperExtensionSendWarning

private on __revIDEDeveloperExtensionSendError pError
   revIDEMessageSend "ideExtensionLog", "Error:" && pError
end __revIDEDeveloperExtensionSendError

private on __revIDEDeveloperExtensionLog pLog
   revIDEMessageSend "ideExtensionLog", pLog
end __revIDEDeveloperExtensionLog

private on __revIDEDeveloperCompilationError pError, pFile
   local tLineNo, tChar, tEndChar, tLine
   # Parse out the error details to provide more meaningful feedback
   repeat for each line tErrLine in pError
      if matchText(tErrLine, ":([0-9]*):([0-9]*):", tLineNo, tChar) then
         put line tLineNo of url ("file:" & pFile) into tLine
         put tChar into tEndChar
         repeat while tChar is not 0 and char tChar - 1 of tLine is not " "
            subtract 1 from tChar
         end repeat
         revIDEMessageSend "ideExtensionLog", "Error: on line" && tLineNo && "(" & tLine & ")" & ":" && char tChar + 1 to tEndChar - 1 of tLine
      end if
   end repeat
   
   revIDEMessageSend "ideExtensionLog", "Error:" && pError
end __revIDEDeveloperCompilationError

private function __revIDEDeveloperExtensionShouldRecompile pFolder, pFile
   # To avoid excessive recompilation, test to see if the compiled module exists and is up to date.
   
   # Recompile because manifest file is missing.
   if there is not a file (pFolder & slash & "manifest.xml") then 
      return true
   end if
   
   # Check timestamps to see if compiled module is out of date.
   local tLastCompiled, tLastModified
   put revIDELastModifiedTimeOfFile(pFolder, "module.lcm") into tLastCompiled
   put revIDELastModifiedTimeOfFile(pFolder, pFile) into tLastModified
   
   return (tLastCompiled is empty or tLastModified > tLastCompiled)
end __revIDEDeveloperExtensionShouldRecompile

private on __revIDEDeveloperExtensionRemoveFolder pFolder
   local tDeveloperExtensionsFolders
   put revIDEGetPreference("cDeveloperExtensionsFolders") into tDeveloperExtensionsFolders
   
   set the itemdelimiter to slash
   local tRootFolder
   put item 1 to -2 of pFolder into tRootFolder
   
   local tLine
   put lineOffset(tRootFolder, tDeveloperExtensionsFolders) into tLine
   if tLine is not 0 then
      delete line tLine of tDeveloperExtensionsFolders
      revIDESetPreference "cDeveloperExtensionsFolders", tDeveloperExtensionsFolders
   end if
end __revIDEDeveloperExtensionRemoveFolder

private on __revIDEDeveloperExtensionAddFolder pFolder
   local tDeveloperExtensionsFolders
   put revIDEGetPreference("cDeveloperExtensionsFolders") into tDeveloperExtensionsFolders
   
   set the itemdelimiter to slash
   local tRootFolder
   put item 1 to -2 of pFolder into tRootFolder
   if tDeveloperExtensionsFolders is empty then
      put tRootFolder into tDeveloperExtensionsFolders
   else
      if tRootFolder is not among the lines of tDeveloperExtensionsFolders then
         put return & tRootFolder after tDeveloperExtensionsFolders
      end if
   end if
   
   revIDESetPreference "cDeveloperExtensionsFolders", tDeveloperExtensionsFolders
end __revIDEDeveloperExtensionAddFolder

/*
Summary: Returns an array of details of the extensions found in user folders
Returns (array):
{ key: The path to the folder containing the extensions
value (array): The array of details pertaining to the extension
{ key: "id"
value: The extension ID
key: "name"
value: The title of the extension
key: "author"
value: The author of the extension
key: "api"
value: An array describing the documented elements of this extension
key: "guide"
value: The user guide
key: "icon"
value: The path to the icon of this extension
key: "retina_icon"
value: The path to the retina icon of this extension } } 
*/
function revIDEDeveloperExtensions
   local tExtensionDetailsA
   
   local tFolders
   if not revEnvironmentIsInstalled() then
      # Look for extension examples in git repo.
      put revEnvironmentRepositoryPath() & slash & "extensions" & slash & "widgets" into tFolders 
      put return & revEnvironmentRepositoryPath() & slash & "extensions" & slash & "libraries" after tFolders
   end if
   
   # Look for extension examples in previously selected user folders.
   local tUserFolders
   put revIDEGetPreference("cDeveloperExtensionsFolders") into tUserFolders
   repeat for each line tLine in tUserFolders
      if tLine is among the lines of tFolders then next repeat
      
      if tFolders is empty then
         put tLine into tFolders
      else
         put return & tLine after tFolders
      end if
   end repeat
   
   local tFolder, tExtensionFolders, tExtensionFolder, tFiles, tExtension
   
   local tFolderHasModule
   repeat for each line tFolder in tFolders
      put false into tFolderHasModule
      if tFolder is empty then
         next repeat
      end if
      set the defaultfolder to tFolder
      put the folders into tExtensionFolders
      repeat for each line tExtensionFolder in tExtensionFolders
         if tExtensionFolder is ".." then 
            next repeat
         end if
         local tExtensionA
         # On first run, don't compile.
         put  revIDEDeveloperExtensionNoCompile(tFolder & slash & tExtensionFolder)  into tExtensionA
         if tExtensionA is not empty then
            put tExtensionA into tExtensionDetailsA[tFolder & slash & tExtensionFolder]
            put true into tFolderHasModule
         end if
      end repeat
      if tFolderHasModule is false then
         __revIDEDeveloperExtensionRemoveFolder tFolder
      end if
   end repeat
   
   return tExtensionDetailsA
end revIDEDeveloperExtensions

private function __revIDEDeveloperExtensionFetchModuleInFolder pFolder
   set the defaultfolder to pFolder
   
   local tFiles
   put the files into tFiles
   filter tFiles with "*.lcb"
   
   local tFile
   # For now, if there are multiple lcb files in one folder, just use the first one.
   if the number of lines of tFiles > 1 then
      put replaceText(tFiles, return, ",") into tFiles
      __revIDEDeveloperExtensionSendError "multiple lcb files in folder" && pFolder & ":" && tFiles
      return empty
   else
      put tFiles into tFile
   end if
   return tFile
end __revIDEDeveloperExtensionFetchModuleInFolder

function revIDEDeveloperExtensionNoCompile pFolder
   local tFile
   put __revIDEDeveloperExtensionFetchModuleInFolder(pFolder) into tFile
   
   if tFile is empty then
      return empty
   end if
   
   local tDataA
   __revIDEDeveloperExtensionFetchMetadata (pFolder & slash & "manifest.xml"), tDataA
   
   if the result is not empty then
      put tFile into tDataA["file"]
   end if
   return tDataA
end revIDEDeveloperExtensionNoCompile

function revIDEDeveloperExtension pFolder
   local tFile
   put __revIDEDeveloperExtensionFetchModuleInFolder(pFolder) into tFile
   
   if tFile is empty then
      return empty
   end if
   
   return __revIDEDeveloperExtensionDetailsFromFile(pFolder, tFile)
end revIDEDeveloperExtension

private function __revIDEDeveloperExtensionFetchFolderDetails pFolder, pFile
   local tDetailsA
   
   # Check timestamps to see if API  is out of date.
   local tLastGenerated, tLastModified, tAPIFolder
   if there is a folder (pFolder & slash & "docs" & slash & "api") then
      put pFolder & slash & "docs" & slash & "api" into tAPIFolder
   else
      put pFolder into tAPIFolder
   end if
   revIDEExtensionUpdateAPI tAPIFolder, pFile
   
   local tAPI
   if the result is empty then
      # Check to see if we've already parsed to a docs library array
      put sExtensionDetailsA[pFolder]["api"] into tAPI
   end if	
   
   if tAPI is empty then
      local tData
      put url ("binfile:" & pFolder & slash & "api.lcdoc") into tData
      put textDecode(tData, "utf-8") into tData
      
      # If either we had to generate the new docs data or get it from the file, parse to a docs library array
      local tLibraryA
      dispatch function "revDocsParseDocTextToLibraryArray" to stack "revDocsParser" with tData, tDetailsA["name"], tDetailsA["author"]
      put the result into tLibraryA
      put tLibraryA["doc"] into tDetailsA["api"]
      put tAPIFolder & slash & "api.lcdoc" into tDetailsA["api_file"]
   end if
   
   if there is a file (pFolder & slash & "support" & slash & "icon.png") then
      put (pFolder & slash & "support" & slash & "icon.png") into tDetailsA["icon"]
   else if there is a file  (pFolder & slash & "icon.png") then
      put (pFolder & slash & "icon.png") into tDetailsA["icon"]
   else
      put empty into tDetailsA["icon"]
   end if
   
   if there is a file (pFolder & slash & "support" & slash & "icon@extra-high.png") then
      put (pFolder & slash & "support" & slash & "icon@extra-high.png") into tDetailsA["retina_icon"]
   else if there is a file (pFolder & slash & "icon@extra-high.png") then
      put (pFolder & slash & "icon@extra-high.png") into tDetailsA["retina_icon"]
   else
      put empty into tDetailsA["retina_icon"]
   end if
   
   local tGuide, tGuideFile
   if there is a file (pFolder & slash & "docs" & slash & "guide" & slash & "guide.md") then
      put pFolder & slash & "docs" & slash & "guide" & slash & "guide.md" into tGuideFile
   else if there is a file (pFolder & slash & "guide.md") then
      put pFolder & slash & "guide.md" into tGuideFile
   end if
   
   if tGuideFile is not empty then
      put tGuideFile into tDetailsA["guide_file"]
      put url ("binfile:" & tGuideFile) into tGuide
      put textDecode(tGuide, "utf-8") into tGuide
   end if 
   
   put tGuide into tDetailsA["guide"]
   
   // AL-2015-02-23: [[ Bug 14552 ]] Find resource folder and return details
   local tResourceFolder, tResources
   put pFolder & slash & "resources" into tResourceFolder
   if there is a folder tResourceFolder then
      put __revIDEDeveloperExtensionListResourcesRecursive(tResourceFolder, "") into tResources
      put tResources into tDetailsA["resources"]
   end if
   
   return tDetailsA 
end __revIDEDeveloperExtensionFetchFolderDetails

private function __revIDEDeveloperExtensionListResourcesRecursive pFolder, pPrefix
   local tOldDefaultFolder
   put the defaultfolder into tOldDefaultFolder
   set the defaultfolder to pFolder
   local tResources, tResource, tPrefix
   if pPrefix is not empty then
      put pPrefix & slash into tPrefix
   end if
   
   # Add files to the list of resources
   repeat for each line tResource in the files
      if tResource begins with "." then next repeat
      if tResources is empty then
         put tPrefix & tResource into tResources
      else
         put return & tPrefix & tResource after tResources
      end if
   end repeat
   
   # Add folders to the list of resources
   repeat for each line tResourceFolder in the folders
      if tResourceFolder begins with "." then next repeat
      local tRecursive
      put __revIDEDeveloperExtensionListResourcesRecursive(pFolder & slash & tResourceFolder, tPrefix & tResourceFolder) into tRecursive
      if tRecursive is not empty then
         if tResources is empty then
            put tRecursive into tResources
         else
            put return & tRecursive after tResources
         end if
      end if
   end repeat
   set the defaultfolder to tOldDefaultFolder
   return tResources
end __revIDEDeveloperExtensionListResourcesRecursive

private function __revIDEDeveloperExtensionDetailsFromFile pFolder, pFile
   local tDetailsA
   put __revIDEDeveloperExtensionFetchFolderDetails(pFolder, pFile) into tDetailsA
   
   put pFile into tDetailsA["file"]
   if not __revIDEDeveloperExtensionShouldRecompile(pFolder, pFile) then
      __revIDEDeveloperExtensionLog "Skipping recompilation of" && pFolder & slash & "module.lcm - module is up to date"
      # The stored info is up to date.
      if sExtensionDetailsA[pFolder] is not empty then
         union tDetailsA with sExtensionDetailsA[pFolder]
         put tDetailsA into sExtensionDetailsA[pFolder]
         return sExtensionDetailsA[pFolder]
      end if
      # The compiled module and manifest are up to date, but we haven't fetched the information yet.
   else
      # The compiled module or manifest is not up to date, so compile.
      __revIDEDeveloperExtensionLog "Compiling module" && pFolder & slash & pFile
      __revIDEDeveloperCompileModule pFolder & slash & pFile, pFolder
      
      if the result is not empty then
         # This may be better as a warning, and try to parse info direct from the file.
         __revIDEDeveloperExtensionSendError the result
         return tDetailsA
      end if
   end if
   
   __revIDEDeveloperExtensionLog "Fetching metadata from" && pFolder & slash & "manifest.xml"
   local tMetadataA
   __revIDEDeveloperExtensionFetchMetadata (pFolder & slash & "manifest.xml"), tMetadataA
   union tDetailsA with tMetadataA
   
   if the result is not empty then
      __revIDEDeveloperExtensionSendError the result
      return tDetailsA
   end if
   
   put tDetailsA into sExtensionDetailsA[pFolder]
   return sExtensionDetailsA[pFolder]
   
end __revIDEDeveloperExtensionDetailsFromFile

on revIDEDeveloperExtensionAddResourceFile pExtensionFolder, pResourcePath, pType
   if there is not a file pResourcePath then
      __revIDEDeveloperExtensionSendError the result
      exit revIDEDeveloperExtensionAddResourceFile
   end if
   
   local tResourceFolder
   put pExtensionFolder & slash & "resources" into tResourceFolder
   if there is not a folder tResourceFolder then
      create folder tResourceFolder
   end if
   
   set the itemdelimiter to slash
   switch pType
      case "icon"
         revCopyFile pResourcePath, pExtensionFolder & slash & "icon.png"
      case "retina_icon"
         revCopyFile pResourcePath, pExtensionFolder & slash & "icon@extra-high.png"
      case "api"
         revCopyFile pResourcePath, pExtensionFolder & slash & "api.lcdoc"
      case "guide"
         revCopyFile pResourcePath, pExtensionFolder & slash & "guide.md"
      default
         revCopyFile pResourcePath, tResourceFolder & slash & item -1 of pResourcePath
   end switch
   
   if the result is not empty then
      __revIDEDeveloperExtensionSendError "Failed to copy file:" && the result
   end if
end revIDEDeveloperExtensionAddResourceFile

on revIDEDeveloperExtensionAddResourceFolder pExtensionFolder, pResourceFolder
   if there is not a folder pResourceFolder then
      __revIDEDeveloperExtensionSendError "No such folder:" && pResourceFolder
      exit revIDEDeveloperExtensionAddResourceFolder
   end if
   
   local tResourceFolder
   put pExtensionFolder & slash & "resources" into tResourceFolder
   if there is not a folder tResourceFolder then
      create folder tResourceFolder
   end if
   
   revCopyFolder pResourceFolder, pExtensionFolder & slash & "resources"
   if the result is not empty then
      __revIDEDeveloperExtensionSendError "Failed to copy folder:" && the result
   end if
end revIDEDeveloperExtensionAddResourceFolder

on revIDEDeveloperExtensionTest pPath
   local tDetailsA
   put revIDEDeveloperExtension(pPath) into tDetailsA
   
   if tDetailsA["file"] is empty then
      __revIDEDeveloperExtensionSendError "No extension to test in" && pPath
      exit revIDEDeveloperExtensionTest
   end if
   
   # AL-2015-07-15: [[ Bug ]] If the details of the extension doesn't include an ID, then the compile failed
   if tDetailsA["id"] is empty then
      __revIDEDeveloperExtensionSendError "Could not compile module" && pPath
      exit revIDEDeveloperExtensionTest
   end if
   
   if there is not a file (pPath & slash & "module.lcm") then
      __revIDEDeveloperExtensionSendError "No compiled module in" && pPath
      exit revIDEDeveloperExtensionTest
   end if
   
   __revIDEDeveloperExtensionLog "Launching in Test Window"
   
   __updateExtensionPropertiesFromManifest pPath & slash & "manifest.xml", tDetailsA["id"]
   
   __revIDEDeveloperExtensionLaunchTestStack pPath, tDetailsA
end revIDEDeveloperExtensionTest

private function __testStackRects
   local tDataA
   if there is a stack "LiveCode Extension Test Window" then
      put the rect of stack "LiveCode Extension Test Window" into tDataA["rect"]
      if there is a widget 1 of stack "LiveCode Extension Test Window" then
         put the rect of widget 1 of stack "LiveCode Extension Test Window" into tDataA["wrect"]
      end if
      return tDataA
   end if
   
   local tScreenRect
   put the working screenrect into tScreenRect
   
   local tX, tY
   if the left of this stack + 200 < (item 3 of tScreenRect) / 2 then
      put the right of this stack + 200 into tX
   else
      put the left of this stack - 200 into tX
   end if
   put item 2 of the loc of this stack into tY
   put tX & comma & tY into tDataA["loc"]
   return tDataA
end __testStackRects

private function __testStackScript
   local tScript
   put "on closeStackRequest;revIDEDeveloperExtensionClearTestStack;exit closeStackRequest;end closeStackRequest;on saveStackRequest;exit saveStackRequest;end saveStackRequest" into tScript
   replace ";" with return in tScript
   return tScript
end __testStackScript

private on __revIDEDeveloperExtensionLaunchTestStack pPath, pDetailsA
   local tRectsA
   put __testStackRects() into tRectsA
   
   if there is a stack "LiveCode Extension Test Window" then
      revIDEDeveloperExtensionClearTestStack
   end if
   
   revIDEDeveloperExtensionCreateTestStack pPath, tRectsA, pDetailsA
end __revIDEDeveloperExtensionLaunchTestStack

on revIDEDeveloperExtensionClearTestStack
   send "__revIDEDeveloperExtensionDoClearTestStack" to me in 0 millisecs
end revIDEDeveloperExtensionClearTestStack

on revIDEDeveloperExtensionCreateTestStack pPath, pRectsA, pDetailsA
      send "__revIDEDeveloperExtensionDoCreateTestStack pPath, pRectsA, pDetailsA" to me in 0 millisecs
end revIDEDeveloperExtensionCreateTestStack

on __revIDEDeveloperExtensionDoCreateTestStack pPath, tRectsA, pDetailsA
   if there is a folder (pPath & slash & "resources") then
      load extension from file (pPath & slash & "module.lcm") with resource path (pPath & slash & "resources")
   else
      load extension from file (pPath & slash & "module.lcm") 
   end if
   
   local tResult
   put the result into tResult
   if tResult is not empty then
      __revIDEDeveloperExtensionSendError tResult
      exit __revIDEDeveloperExtensionDoCreateTestStack
   end if
   
   lock screen
   create stack "LiveCode Extension Test Window"
   if tRectsA["rect"] is not empty then
      set the rect of stack "LiveCode Extension Test Window" to tRectsA["rect"]
   else
      set the loc of stack "LiveCode Extension Test Window" to tRectsA["loc"]
   end if
   set the destroyStack of stack "LiveCode Extension Test Window" to true
   set the title of it to pDetailsA["name"]
   set the script of it to __testStackScript()
   go stack "LiveCode Extension Test Window"
   create widget as pDetailsA["id"]
   
   if there is not a widget 1 of stack "LiveCode Extension Test Window" then
      __revIDEDeveloperExtensionSendError "failed to create widget" && pDetailsA["id"]
      __revIDEDeveloperExtensionDoClearTestStack
      exit __revIDEDeveloperExtensionDoCreateTestStack
   end if
   
   if tRectsA["wrect"] is not empty then
      set the rect of widget 1 of stack "LiveCode Extension Test Window" to tRectsA["wrect"]
   end if
   
   set the cCurExtension of stack "LiveCode Extension Test Window" to pDetailsA["id"]
   unlock screen
end __revIDEDeveloperExtensionDoCreateTestStack

on __revIDEDeveloperExtensionDoClearTestStack
   repeat while there is a widget 1 of stack "LiveCode Extension Test Window" 
      delete widget 1 of stack "LiveCode Extension Test Window"
   end repeat
   local tExtension
   put the cCurExtension of stack "LiveCode Extension Test Window" into tExtension
   delete stack "LiveCode Extension Test Window"
   if tExtension is not empty then
      __revIDEDeveloperExtensionUnload tExtension
      __revIDEDeveloperExtensionLog "Unloading..."
   end if
end __revIDEDeveloperExtensionDoClearTestStack

local sInstalledExtension
on __revIDEDeveloperExtensionUnload pExtension
   # Don't unload if we have installed
   if pExtension is not sInstalledExtension then
      unload extension pExtension
   end if
end __revIDEDeveloperExtensionUnload

on revIDEDeveloperExtensionInstall pFolder
   local tPackage
   __revIDEDeveloperExtensionBuildPackage pFolder, "", tPackage
   revIDEInstallExtension tPackage
   put pFolder & slash & "module.lcm" into sInstalledExtension
end revIDEDeveloperExtensionInstall

on revIDEDeveloperExtensionUninstall pPath
   local tDetailsA
   put revIDEDeveloperExtension(pPath) into tDetailsA
   
   if tDetailsA["id"] is empty then
      __revIDEDeveloperExtensionSendError "Extension id lost from" && pPath & ": cannot uninstall"
      exit revIDEDeveloperExtensionUninstall
   end if
   
   revIDEUninstallExtension tDetailsA["id"]
   
end revIDEDeveloperExtensionUninstall

on revIDEDeveloperExtensionEditScript pFolder
   local tFile
   put __revIDEDeveloperExtensionFetchModuleInFolder(pFolder) into tFile
   
   # AL-2015-04-01: [[ Bug 15130 ]] First check to see if there is an existing association
   launch document tFile
   if the result is not empty then
      # AL-2015-04-01: [[ Bug 15130 ]] Check to see if the text editor preference is set
      local tEditor
      put revIDEGetPreference("LCB_textEditor") into tEditor
      if tEditor is not empty then
         launch tFile with tEditor
      end if
   end if
   
   if the result is "no association" or the result is "request failed" then
      answer file "Select text editor..."
      if it is not empty then
         launch tFile with it
      end if
   end if
   
   if the result is not empty then
      __revIDEDeveloperExtensionSendError "Could not open" && tFile & ":" && the result
   else if it is not empty then
      # AL-2015-04-01: [[ Bug 15130 ]] If the new text editor launch was successful, set the preference
      revIDESetPreference "LCB_textEditor", it
   end if
end revIDEDeveloperExtensionEditScript

on revIDEDeveloperExtensionOpen pFolder
   if __revIDEDeveloperExtensionFetchModuleInFolder(pFolder) is empty then
      exit revIDEDeveloperExtensionOpen
   end if
   
   __revIDEDeveloperExtensionAddFolder pFolder
   return revIDEDeveloperExtension(pFolder)
end revIDEDeveloperExtensionOpen

function __revIDEDeveloperExtensionFetchWidgetTemplateFile
   return url ("file:" & revIDESpecialFolderPath("Toolset") & slash & "widget_template.txt")
end __revIDEDeveloperExtensionFetchWidgetTemplateFile

function __revIDEDeveloperExtensionFetchTemplate pDataA
   local tTemplate
   if pDataA["type"] is "widget" then
      put __revIDEDeveloperExtensionFetchWidgetTemplateFile() into tTemplate
   else
      put __revIDEDeveloperExtensionFetchLibraryTemplateFile() into tTemplate
   end if
end __revIDEDeveloperExtensionFetchTemplate

on revIDEDeveloperExtensionNew pDataA
   local tTemplate
   put __revIDEDeveloperExtensionFetchTemplate(pDataA) into tTemplate
   if tTemplate is empty then
      return empty
   end if
   put merge(tTemplate) into url("file:" & pDataA["path"] & slash & pDataA["name"] & ".lcb")
end revIDEDeveloperExtensionNew

private on __revIDEDeveloperExtensionFetchMetadata pManifestPath, @rDataA
   local tDataA
   
   local tManifestContents, tId
   put url ("file:" & pManifestPath) into tManifestContents
   put revXMLCreateTree(tManifestContents,true,true,false) into tId
   
   if tId begins with "xmlerr" then
      return "Error: invalid xml in manifest"
   end if
   
   local tTargetType
   put textDecode(revXMLNodeContents(tId, "/package/type"), "utf-8") into tTargetType
   
   if tTargetType begins with "xmlerr" then
      __revIDEDeveloperExtensionSendError "couldn't retrieve extension type from manifest" && pManifestPath
      exit __revIDEDeveloperExtensionFetchMetadata
   end if
   put tTargetType into tDataA["type"]
   
   local tTargetName
   put textDecode(revXMLNodeContents(tId, "/package/name"), "utf-8") into tTargetName
   
   if tTargetName begins with "xmlerr" then
      __revIDEDeveloperExtensionSendError "couldn't retrieve extension name from manifest" && pManifestPath
      exit __revIDEDeveloperExtensionFetchMetadata
   end if
   
   set the itemdelimiter to "."
   if not tTargetName begins with "community.livecode" or the number of items of tTargetName < 4 then
      __revIDEDeveloperExtensionSendWarning "extension name has invalid identifier (" & tTargetName & ") - must be community.livecode.<yourId>.<extensionTitle>"
   end if
   put tTargetName into tDataA["id"]
   
   # If we have a library, we don't require various packaged elements
   if tTargetType is "widget" then
      local tTargetTitle
      put textDecode(revXMLNodeContents(tId, "/package/title"), "utf-8") into tTargetTitle
      
      if tTargetTitle is empty or tTargetTitle begins with "xmlerr" then
         __revIDEDeveloperExtensionSendWarning "couldn't retrieve title from" && tTargetName && "manifest - ensure .lcb file has 'metadata title is " & quote & "<title>" & quote & "'"
         put empty into tTargetTitle
      end if
      put tTargetTitle into tDataA["name"]
   end if
   
   local tTargetVersion
   put textDecode(revXMLNodeContents(tId, "/package/version"), "utf-8") into tTargetVersion
   
   if tTargetVersion is empty or tTargetVersion begins with "xmlerr" then
      __revIDEDeveloperExtensionSendWarning "couldn't retrieve version from" && tTargetName && "manifest - ensure .lcb file has 'metadata version is " & quote & "<version>" & quote & "'"
      put empty into tTargetVersion
   end if
   
   if the number of items of tTargetVersion is not 3 then
      __revIDEDeveloperExtensionSendWarning "extension name has invalid identifier (" & tTargetVersion & ") - must be <major>.<minor>.<revision>"
   end if
   put tTargetVersion into tDataA["version"]
   
   local tTargetAuthor
   put textDecode(revXMLNodeContents(tId, "/package/author"), "utf-8") into tTargetAuthor
   
   if tTargetAuthor is empty or tTargetAuthor begins with "xmlerr" then
      __revIDEDeveloperExtensionSendWarning "couldn't retrieve author from" && tTargetName && "manifest - ensure .lcb file has 'metadata author is " & quote & "<author_name>" & quote & "'"
      put empty into tTargetAuthor
   end if
   put tTargetAuthor into tDataA["author"]
   
   put tDataA into rDataA
   return empty
end __revIDEDeveloperExtensionFetchMetadata

private function shellFormat pArg, pSwitch
   local tOutput
   
   if pSwitch is not empty then
      put "--" & pSwitch & " " into tOutput
   end if
   
   return tOutput & quote & pArg & quote & " "
end shellFormat

private command __revIDEDeveloperCompileModule pFile, pTargetFolder
   # The manifest is currently always generated from the source
   if there is a file (pTargetFolder & slash & "manifest.xml") then
      delete file (pTargetFolder & slash & "manifest.xml")
   end if
   
   local tResourcePath
   if revEnvironmentIsInstalled() is false then
      put revEnvironmentBinariesPath() into tResourcePath
   else
      put revIDESpecialFolderPath("Toolchain") into tResourcePath
   end if
   
   # Build the shell command
   local tShellCommand
   
   # The actual compile command
   if the platform is "win32" then
      put shellFormat(tResourcePath & slash & "lc-compile.exe") into tShellCommand
   else
      put shellFormat(tResourcePath & slash & "lc-compile") into tShellCommand
   end if
   # The folder to put the .lci file
   put shellFormat(pTargetFolder, "modulepath") after tShellCommand
   
   # The built-in module path
   put shellFormat(tResourcePath & slash & "modules/lci", "modulepath") after tShellCommand
   
   # Installed module path
   put shellFormat(revIDESpecialFolderPath("user extensions") & slash & "interface", "modulepath") after tShellCommand
   
   # The manifest target
   put shellFormat(pTargetFolder & slash & "manifest.xml", "manifest") after tShellCommand
   
   # The output
   put shellFormat(pTargetFolder & slash & "module.lcm", "output") after tShellCommand
   
   # The target .lcb file
   put shellFormat(pFile) after tShellCommand
   
   # AL-2015-06-15: [[ Bug 15001 ]] Don't show console window when executing shell command
   local tHideConsoleWindows
   put the hideConsoleWindows into tHideConsoleWindows
   set the hideConsoleWindows to true
   
   local tShellOutput, tShellResult
   put shell(tShellCommand) into tShellOutput
   put the result into tShellResult
   
   set the hideConsoleWindows to tHideConsoleWindows
   
   if tShellResult is not 0 then
      __revIDEDeveloperCompilationError tShellOutput
      return "failed to compile module"
   end if
   
   __revIDEDeveloperExtensionLog tShellOutput
   
   if there is not a file (pTargetFolder & slash & "module.lcm") then
      return "failed to compile module"
   end if
   
   if there is not a file (pTargetFolder & slash & "manifest.xml") then
      return "failed to generate manifest"
   end if
   
   return empty
end __revIDEDeveloperCompileModule

on revIDEDeveloperExtensionBuildPackage pFolder
   local tBuiltLocation
   __revIDEDeveloperExtensionBuildPackage pFolder, "", tBuiltLocation
   # AL-2015-05-22: [[ Bug 14919 ]] Don't display success dialog when package building fails
   if the result is empty then
      answer "Package" && tBuiltLocation && "built successfully"
   end if
end revIDEDeveloperExtensionBuildPackage

private on __revIDEDeveloperExtensionBuildPackage pFolder, pTargetFolder, @rBuiltLocation
   local tDetailsA
   put revIDEDeveloperExtension(pFolder) into tDetailsA
   
   local tFullPath
   put pFolder & slash & tDetailsA["file"] into tFullPath
   
   if there is not a file tFullPath then
      return "Error: missing file" && tFullPath
   end if
   
   local tTargetFolder
   if pTargetFolder is empty then
      put pFolder into tTargetFolder
   else
      put pTargetFolder into tTargetFolder
   end if
   
   local tTargetName
   if tDetailsA["id"] is empty then
      __revIDEDeveloperExtensionSendError "no id found in " && tFullpath
      return "no id found"
   end if
   put tDetailsA["id"] into tTargetName
   
   local tTargetVersion
   if tDetailsA["version"] is empty then
      __revIDEDeveloperExtensionSendError "no version found in " && tFullpath
      return "no version found"
   end if
   put tDetailsA["version"] into tTargetVersion
   
   local tArchive
   put tTargetFolder & slash & tTargetName & "." & tTargetVersion & ".lce" into tArchive
   
   if there is a file tArchive then
      delete file tArchive
   end if
   revZipOpenArchive tArchive, "write"
   
   if the result begins with "ziperr" then
      __revIDEDeveloperExtensionSendError "couldn't open zip archive" &&  tArchive
      return "couldn't open zip archive" && tArchive
   end if
   
   local tError
   
   # AL-2015-05-22: [[ Bug 14919 ]] Use default widget and library icons if none are provided
   local tIcon
   if tError is empty then
      put tDetailsA["icon"] into tIcon
      if tIcon is empty or there is not a file tIcon then
         answer file "Select icon file" with type "|png|"
         if it is empty then
            __revIDEDeveloperExtensionLog "Using default icon"
            get revIDEDefaultExtensionIcon(tDetailsA["type"], false)
         end if
         put it into tIcon
      end if
   end if
   
   local tRetinaIcon
   if tError is empty then
      put tDetailsA["retina_icon"] into tRetinaIcon
      if tRetinaIcon is empty or there is not a file tRetinaIcon then
         answer file "Select retina icon file" with type "|png|"
         if it is empty then
            __revIDEDeveloperExtensionLog "Using default retina icon"
            get revIDEDefaultExtensionIcon(tDetailsA["type"], true)
         end if
         put it into tRetinaIcon
      end if
   end if
   
   local tGuide
   put tDetailsA["guide_file"] into tGuide
   if there is not a file tGuide then
      put empty into tGuide
   end if
   
   local tDocs
   put tDetailsA["api_file"] into tDocs
   if there is not a file tDocs then
      put empty into tDocs
   end if
   
   local tResources
   put (pFolder & slash & "resources") into tResources
   if there is not a folder tResources then
      put empty into tResources
   end if
   
   # AL-2015-03-18: [[ Bug 15007 ]] Include interface file if present
   local tInterfaceFile
   if there is a file (pFolder & slash & tTargetName & ".lci") then
      put pFolder & slash & tTargetName & ".lci" into tInterfaceFile
   end if
   
   if tError is empty then
      put __revIDEDeveloperExtensionAddSpecifiedFilesToPackage(tFullPath, pFolder, tArchive, pFolder & slash & "module.lcm", tIcon, tRetinaIcon, tGuide, tDocs, tResources, tInterfaceFile) into tError
   end if
   
   revZipCloseArchive tArchive
   
   if tError is empty then
      if the result begins with "ziperr" then
         put "Error: couldn't close zip archive" into tError
      end if
   end if
   
   if tError is not empty then
      __revIDEDeveloperExtensionSendError tError
      return tError
   end if
   
   put tArchive into rBuiltLocation
   return empty
end __revIDEDeveloperExtensionBuildPackage

private function __revIDEDeveloperExtensionAddSpecifiedFilesToPackage pSource, pFolder, pArchive, pModule, pIcon, pRetinaIcon, pGuide, pDocs, pResourcesFolder, pInterfaceFile
   local tError
   
   set the itemdelimiter to slash
   # Add source into package
   revZipAddItemWithFile pArchive, item -1 of pSource, pSource
   
   if the result begins with "ziperr" then
      put "couldn't add source" into tError
   end if
   
   # Add module into package
   revZipAddItemWithFile pArchive, "module.lcm", pModule
   
   if the result begins with "ziperr" then
      put "couldn't add module" into tError
   end if
   
   # Add manifest into package
   if tError is empty then
      revZipAddItemWithFile pArchive, "manifest.xml", pFolder & slash & "manifest.xml"
      
      if the result begins with "ziperr" then
         put "couldn't add manifest" into tError
      end if
   end if
   
   # Add user guide
   if tError is empty then
      // AL-2015-03-03: [[ Bug 14781 ]] If there is no guide, warn and don't try to add a file
   	  if pGuide is empty then
   	    __revIDEDeveloperExtensionSendWarning "no user guide found"
   	  else
	    revZipAddItemWithFile pArchive, "docs/guide/guide.md", pGuide
      end if
      if the result begins with "ziperr" then
         put "couldn't add guide" into tError
      end if
   end if
   
   # Add icons
   if tError is empty then
      revZipAddItemWithFile pArchive, "support/icon.png", pIcon
      
      if the result begins with "ziperr" then
         put "couldn't add icon.png" into tError
      end if
   end if
   
   if tError is empty then
      revZipAddItemWithFile pArchive, "support/icon@extra-high.png", pRetinaIcon
      
      if the result begins with "ziperr" then
         put "couldn't add icon@extra-high.png" into tError
      end if
   end if
   
   # Add docs
   if tError is empty then
      if pDocs is empty then
         __revIDEDeveloperExtensionSendWarning "docs formatting error. Docs may be empty"
      else
         revZipAddItemWithFile pArchive, "docs/api/api.lcdoc", pDocs
      end if
      if the result begins with "ziperr" then
         put "couldn't add doc " & pDocs into tError 
      end if
   end if
   
   # Add resources
   if tError is empty and pResourcesFolder is not empty then
      local tResources
      put __revIDEDeveloperExtensionListResourcesRecursive(pResourcesFolder, "") into tResources
      repeat for each line tLine in tResources
         revZipAddItemWithFile pArchive, "resources/" & tLine, pResourcesFolder & slash & tLine
         
         if the result begins with "ziperr" then
            __revIDEDeveloperExtensionSendWarning "couldn't add resource" && pResourcesFolder & slash & tLine
         end if
      end repeat
   end if
   
   # AL-2015-03-18: [[ Bug 15007 ]] Include interface file if present
   if tError is empty and pInterfaceFile is not empty then
      revZipAddItemWithFile pArchive, item -1 of pInterfaceFile, pInterfaceFile
      
      if the result begins with "ziperr" then
         __revIDEDeveloperExtensionSendWarning "couldn't add interface file" && pInterfaceFile
      end if
   end if
   
   return tError
end __revIDEDeveloperExtensionAddSpecifiedFilesToPackage
