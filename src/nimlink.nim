import os
import strutils
import json
import sequtils
import times
import pkg/colors

const 
  DEFAULT_LINKS_DIR = "nimlinks"
  CONFIG_FILENAME = "nim.cfg"

# ---- Database Functions ----

proc getDatabasePath(): string =
  return getHomeDir() / ".nimlink"

proc readDatabase(): JsonNode =
  let dbPath = getDatabasePath()
  if not fileExists(dbPath):
    # Create empty database if it doesn't exist
    let emptyDb = %* {}
    writeFile(dbPath, $emptyDb)
    return emptyDb
  
  try:
    let content = readFile(dbPath)
    return parseJson(content)
  except:
    echo "Error: ".red & "Failed to read database. Creating new one."
    let emptyDb = %* {}
    writeFile(dbPath, $emptyDb)
    return emptyDb

proc writeDatabase(db: JsonNode) =
  let dbPath = getDatabasePath()
  writeFile(dbPath, pretty(db))

# ---- Helper Functions ----

proc extractSrcDir(nimbleFile: string): string =
  # Extract srcDir from a nimble file
  for line in lines(nimbleFile):
    let trimmed = line.strip()
    if trimmed.startsWith("srcDir") and '=' in trimmed:
      let parts = trimmed.split('=', 1)
      if parts.len == 2:
        return parts[1].strip().strip(chars={'"', '\''})
  return ""  # Default is empty, will use repo root

proc findNimbleFile(repoPath: string): string =
  # Find a .nimble file in the repository
  let nimbleFiles = toSeq(walkFiles(repoPath / "*.nimble"))
  if nimbleFiles.len == 0:
    return ""
  return nimbleFiles[0]

proc getLinksDir(): string =
  # Get the links directory (from env var or default)
  let envDir = getEnv("NIMLINK_DIR")
  if envDir != "":
    return envDir
  return DEFAULT_LINKS_DIR

proc ensureLinksDir(projectDir: string = getCurrentDir()): string =
  # Ensure the links directory exists
  let linksPath = projectDir / getLinksDir()
  if not dirExists(linksPath):
    createDir(linksPath)
  return linksPath

proc updateConfig(projectDir: string, packageName: string, sourcePath: string, action: string, isDirect: bool = false) =
  # Update the nim.cfg file to include or remove a package path
  let configPath = projectDir / CONFIG_FILENAME
  
  # Create the appropriate path line
  var pathLine: string
  if isDirect:
    pathLine = "--path=\"" & sourcePath & "\""
  else:
    let linksDir = getLinksDir()
    pathLine = "--path=\"" & linksDir & "/" & packageName & "\""
  
  # Create config file if it doesn't exist
  if not fileExists(configPath):
    if action == "add":
      writeFile(configPath, pathLine)
      echo "Created config file: ".green & configPath
    return
  
  # Read existing config
  var configLines = readFile(configPath).strip().splitLines()
  
  # Look for existing package path line
  var lineIndex = -1
  for i, line in configLines:
    if line.strip() == pathLine:
      lineIndex = i
      break
  
  # Update config file
  if action == "add" and lineIndex == -1:
    # Add the new path entry
    configLines.add(pathLine)
    writeFile(configPath, configLines.join("\n"))
    echo "Updated config file: ".green & configPath
  elif action == "remove" and lineIndex != -1:
    # Remove the path entry
    configLines.delete(lineIndex)
    writeFile(configPath, configLines.join("\n"))
    echo "Updated config file: ".green & configPath

proc isSymlink(path: string): bool =
  # Check if a path is a symlink
  try:
    discard expandSymlink(path)
    return true
  except:
    return false

# ---- Command Functions ----

proc registerCmd() =
  # Register the current directory as a package
  let repoPath = getCurrentDir()
  
  # Find nimble file
  let nimbleFile = findNimbleFile(repoPath)
  if nimbleFile == "":
    echo "Error: ".red & "No .nimble file found in current directory"
    return
  
  # Extract package name from nimble file
  let packageName = splitFile(nimbleFile).name
  
  # Extract srcDir from nimble file
  var srcDir = extractSrcDir(nimbleFile)
  
  # Add to database
  var db = readDatabase()
  
  let repoInfo = %* {
    "name": packageName,
    "path": repoPath,
    "srcDir": srcDir,
    "added": $now()
  }
  
  if db.hasKey(packageName):
    echo "Updating ".yellow & packageName.bold & " registration"
  else:
    echo "Registering ".green & packageName.bold
  
  db[packageName] = repoInfo
  writeDatabase(db)
  
  echo "Success: ".green & "Registered " & packageName.bold.yellow
  echo "Path: ".blue & repoPath
  
  if srcDir != "":
    echo "Source directory: ".blue & srcDir
  else:
    echo "Source directory: ".blue & "repository root"

proc listCmd() =
  let db = readDatabase()
  
  if db.len == 0:
    echo "No packages registered.".yellow
    echo "Run " & "nimlink".bold & " in a Nim package directory to register it."
    return
  
  echo "Registered packages:".bold.cyan
  for name, info in db:
    echo "• " & name.bold.green
    echo "  Path: ".blue & info["path"].getStr()
    
    if info["srcDir"].getStr() != "":
      echo "  Source: ".blue & info["srcDir"].getStr()
    else:
      echo "  Source: ".blue & "repository root"
      
    echo "  Added: ".dim & info["added"].getStr()
    
    if name != db.keys.toSeq[^1]:
      echo ""

proc removeCmd(packageName: string) =
  # Remove a package from the database
  var db = readDatabase()
  
  if not db.hasKey(packageName):
    echo "Error: ".red & "Package " & packageName.bold & " not found in database"
    return
  
  db.delete(packageName)
  writeDatabase(db)
  
  echo "Success: ".green & "Removed " & packageName.bold.yellow & " from database"

proc installCmd(packageName: string, projectDir: string = getCurrentDir(), isDirect: bool = false) =
  # Install a package by creating a symlink in the links directory
  let db = readDatabase()
  
  if not db.hasKey(packageName):
    echo "Error: ".red & "Package " & packageName.bold & " not found"
    echo "Run " & "nimlink list".bold & " to see available packages"
    return
  
  # Get package info
  let info = db[packageName]
  let repoPath = info["path"].getStr()
  let srcDir = info["srcDir"].getStr()
  
  # Determine source path (repo root or srcDir)
  let sourcePath = 
    if srcDir != "":
      if isAbsolute(srcDir): srcDir
      else: repoPath / srcDir
    else:
      repoPath
  
  if isDirect:
    # Direct mode: just add path to config file
    updateConfig(projectDir, packageName, sourcePath, "add", true)
    echo "Success: ".green & "Added " & packageName.bold.yellow & " path directly to nim.cfg"
    echo "Path: ".blue & sourcePath
    echo "You can now use: ".green & "import " & packageName & " from anywhere in your project"
    return
    
  # Regular mode: create symlink and add its path to config
  
  # Ensure links directory exists
  let linksDir = ensureLinksDir(projectDir)
  
  # Check if symlink already exists
  let linkPath = linksDir / packageName
  if dirExists(linkPath) or fileExists(linkPath):
    echo "Error: ".red & "Target already exists: " & linkPath
    echo "Use " & "nimlink uninstall ".bold & packageName.bold & " first"
    return
  
  # Create symlink
  try:
    createSymlink(sourcePath, linkPath)
    echo "Success: ".green & "Created symlink for " & packageName.bold.yellow
    echo "From: ".blue & sourcePath
    echo "To: ".blue & linkPath
    
    # Update nim.cfg to include the links directory
    updateConfig(projectDir, packageName, sourcePath, "add", false)
    
    echo "You can now use: ".green & "import " & packageName & " from anywhere in your project"
  except:
    echo "Error: ".red & "Failed to create symlink"
    echo "You may need administrator privileges on Windows"

proc uninstallCmd(packageName: string, projectDir: string = getCurrentDir(), isDirect: bool = false) =
  # Remove a symlink from the links directory
  if isDirect:
    # Direct mode: find the package to get its source path
    let db = readDatabase()
    if not db.hasKey(packageName):
      echo "Error: ".red & "Package " & packageName.bold & " not found in database"
      return
      
    # Get package info
    let info = db[packageName]
    let repoPath = info["path"].getStr()
    let srcDir = info["srcDir"].getStr()
    
    # Determine source path
    let sourcePath = 
      if srcDir != "":
        if isAbsolute(srcDir): srcDir
        else: repoPath / srcDir
      else:
        repoPath
        
    # Remove from config file
    updateConfig(projectDir, packageName, sourcePath, "remove", true)
    echo "Success: ".green & "Removed " & packageName.bold.yellow & " path from nim.cfg"
    return
  
  # Regular mode: remove symlink and path
  let linksDir = projectDir / getLinksDir()
  let linkPath = linksDir / packageName
  
  # Check if symlink exists
  if not dirExists(linkPath) and not fileExists(linkPath):
    echo "Error: ".red & "No symlink found for " & packageName.bold
    return
  
  # Check if it's a symlink
  if not isSymlink(linkPath):
    echo "Error: ".red & "Not a symlink: " & linkPath
    echo "Only symlinks created by nimlink can be safely removed".yellow
    return
  
  # Remove the symlink
  try:
    try:
      removeDir(linkPath)  # For directory symlinks
    except:
      removeFile(linkPath)  # For file symlinks
      
    echo "Success: ".green & "Removed symlink for " & packageName.bold.yellow
    echo "From: ".blue & linkPath
    
    # Update nim.cfg to remove the package path
    updateConfig(projectDir, packageName, "", "remove", false)
  except:
    echo "Error: ".red & "Failed to remove symlink: " & linkPath

proc showHelp() =
  echo "nimlink - Nim package linking tool".bold.green
  echo ""
  echo "Commands:".cyan
  echo "  nimlink                 Register current package in database"
  echo "  nimlink list, l         List registered packages"
  echo "  nimlink install, i NAME Install package to project links directory"
  echo "  nimlink uninstall, u NAME  Remove installed package from links directory"
  echo "  nimlink remove, rm NAME    Remove package from database"
  echo "  nimlink help            Show this help"
  echo ""
  echo "Options:".cyan
  echo "  --direct, -d            Add direct path in nim.cfg without creating symlinks"
  echo ""
  echo "Environment Variables:".cyan
  echo "  NIMLINK_DIR             Custom links directory name (default: nimlinks)"
  echo ""
  echo "Examples:".bold.blue
  echo "  nimlink                         # Register current directory"
  echo "  nimlink i mylibrary             # Link mylibrary to project (shorthand)"
  echo "  nimlink install mylibrary -d    # Add direct path to nim.cfg" 
  echo "  nimlink u mylibrary             # Remove link from project (shorthand)"
  echo "  nimlink rm mylibrary            # Remove from database (shorthand)"

proc main() =
  let args = commandLineParams()
  
  if args.len == 0:
    registerCmd()
    return
  
  let command = args[0].toLowerAscii()
  
  # Check for --direct or -d flag
  var isDirect = false
  for arg in args:
    if arg in ["--direct", "-d"]:
      isDirect = true
      break
  
  case command:
  of "list", "ls", "l":
    listCmd()
    
  of "install", "i":
    if args.len < 2 or (args[1] in ["--direct", "-d"] and args.len < 3):
      echo "Error: ".red & "No package name specified"
      echo "Usage: nimlink install PACKAGE [--direct]".yellow
      return
    
    let packageName = 
      if args[1] in ["--direct", "-d"] and args.len >= 3: args[2]
      else: args[1]
    
    installCmd(packageName, getCurrentDir(), isDirect)
    
  of "uninstall", "un", "u":
    if args.len < 2 or (args[1] in ["--direct", "-d"] and args.len < 3):
      echo "Error: ".red & "No package name specified"
      echo "Usage: nimlink uninstall PACKAGE [--direct]".yellow
      return
    
    let packageName = 
      if args[1] in ["--direct", "-d"] and args.len >= 3: args[2]
      else: args[1]
    
    uninstallCmd(packageName, getCurrentDir(), isDirect)
    
  of "remove", "rm", "r":
    if args.len < 2:
      echo "Error: ".red & "No package name specified"
      echo "Usage: nimlink remove PACKAGE".yellow
      return
    
    let packageName = args[1]
    removeCmd(packageName)
    
  of "help", "-h", "--help", "h":
    showHelp()
    
  else:
    echo "Unknown command: ".red & command
    showHelp()

when isMainModule:
  main()