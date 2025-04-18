import os
import strutils
import sequtils
import pkg/colors  # For terminal coloring similar to npm colors

proc extractSrcDir(nimbleFile: string): string =
  # This is a simplified approach to extract srcDir from a nimble file
  result = ""
  for line in lines(nimbleFile):
    let trimmedLine = line.strip()
    # Look for srcDir = "something" pattern
    if trimmedLine.startsWith("srcDir") and '=' in trimmedLine:
      # Extract the value from something like: srcDir = "src"
      let parts = trimmedLine.split('=', 1)
      if parts.len == 2:
        result = parts[1].strip().strip(chars={'"', '\''})
        break

proc showUsage() =
  echo "nimdevel - A better alternative to nimble develop".bold
  echo "Usage: nimdevel [OPTIONS]".yellow
  echo ""
  echo "Options:"
  echo "  -h, --help     Show this help"
  echo "  -v, --version  Show version information"
  echo ""
  echo "Run in a directory containing a .nimble file to create"
  echo "a development link that respects the srcDir setting."

proc nimDevelop() =
  # Check for help/version flags
  let args = commandLineParams()
  for arg in args:
    if arg in ["-h", "--help"]:
      showUsage()
      return
    elif arg in ["-v", "--version"]:
      echo "nimdevel v0.1.0"
      return
  
  # Get the current directory (assuming this is the package directory)
  let packageDir = getCurrentDir()
  
  # Find the nimble file
  let nimbleFiles = toSeq(walkFiles(packageDir / "*.nimble"))
  if nimbleFiles.len == 0:
    echo "Error: ".red & "No nimble file found in the current directory"
    return
  
  let nimbleFile = nimbleFiles[0]
  let nimbleFileName = extractFilename(nimbleFile)
  let nimbleBaseName = nimbleFileName.split(".")[0]
  
  # Extract srcDir from the nimble file
  var srcDir = extractSrcDir(nimbleFile)
  
  # If srcDir is found and is relative, make it absolute
  if srcDir != "":
    if not srcDir.isAbsolute():
      srcDir = packageDir / srcDir
  else:
    # Default to package directory if srcDir is empty
    srcDir = packageDir
  
  # Get the nimble dir (with env var support)
  var nimbleDir = getEnv("NIMBLE_DIR")
  if nimbleDir == "":
    # Default location if not set
    nimbleDir = getHomeDir() / ".nimble"
  
  # Create the link directory path
  let linkDir = nimbleDir / "links" / nimbleBaseName & "-#head"
  
  # Create the directory structure if it doesn't exist
  if not dirExists(linkDir):
    try:
      createDir(linkDir)
    except:
      echo "Error: ".red & "Failed to create directory: " & linkDir
      return
  
  # Remove existing link file if it exists
  let linkFile = linkDir / nimbleBaseName & ".nimble-link"
  if fileExists(linkFile):
    try:
      removeFile(linkFile)
    except:
      echo "Error: ".red & "Failed to remove existing link file: " & linkFile
      return
  
  # Create the nimble link file
  try:
    writeFile(linkFile, srcDir)
    echo "Success: ".green & "Created development link for " & nimbleBaseName.bold.yellow
    echo "Link points to: ".blue & srcDir
  except:
    echo "Error: ".red & "Failed to create link file: " & linkFile
    return

when isMainModule:
  nimDevelop()