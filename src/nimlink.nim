import os
import times
import json
import strutils
import sequtils
import pkg/colors  # For terminal coloring

type
  RepoInfo = object
    name: string  # Name of the repository
    path: string  # Full path to the repository
    srcDir: string  # Source directory (relative to path)
    date: string  # Date when added

proc extractSrcDir(nimbleFile: string): string =
  # Extract srcDir from a nimble file
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

proc getRepoName(repoPath: string): string =
  # Extract repo name from path
  result = extractFilename(repoPath)

proc findNimbleFile(repoPath: string): string =
  # Find a .nimble file in the repository
  let nimbleFiles = toSeq(walkFiles(repoPath / "*.nimble"))
  if nimbleFiles.len == 0:
    return ""
  return nimbleFiles[0]

proc registerRepo(repoPath: string) =
  # Get absolute path
  let absPath = 
    if isAbsolute(repoPath): repoPath
    else: getCurrentDir() / repoPath
  
  # Check if directory exists
  if not dirExists(absPath):
    echo "Error: ".red & "Directory does not exist: " & absPath
    return
  
  # Find nimble file
  let nimbleFile = findNimbleFile(absPath)
  if nimbleFile == "":
    echo "Error: ".red & "No .nimble file found in " & absPath
    return
  
  # Extract repository name from nimble file
  let repoName = splitFile(nimbleFile).name
  
  # Extract srcDir from nimble file
  var srcDir = extractSrcDir(nimbleFile)
  if srcDir == "":
    srcDir = "."  # Default to repo root
  
  # Add to database
  var db = readDatabase()
  
  let repoInfo = %* {
    "name": repoName,
    "path": absPath,
    "srcDir": srcDir,
    "date": $now()
  }
  
  db[repoName] = repoInfo
  writeDatabase(db)
  
  echo "Success: ".green & "Registered repository " & repoName.bold.yellow
  echo "Path: ".blue & absPath
  echo "Source directory: ".blue & srcDir

proc listRepos() =
  let db = readDatabase()
  
  if db.len == 0:
    echo "No repositories registered. Use 'nimlink' in a repository to register it.".yellow
    return
  
  echo "Registered repositories:".bold
  for repoName, repoInfo in db:
    echo repoName.bold.green & ":"
    echo "  Path: " & repoInfo["path"].getStr()
    echo "  Source: " & repoInfo["srcDir"].getStr()
    echo "  Added: " & repoInfo["date"].getStr()

proc installRepo(repoName: string, targetDir: string = "") =
  let db = readDatabase()
  
  # Check if repo exists in database
  if not db.hasKey(repoName):
    echo "Error: ".red & "Repository not found: " & repoName
    echo "Use 'nimlink --list' to see available repositories."
    return
  
  # Get repo info
  let repoInfo = db[repoName]
  let repoPath = repoInfo["path"].getStr()
  let srcDir = repoInfo["srcDir"].getStr()
  
  # Determine source path
  let sourcePath = repoPath / srcDir
  
  # Determine target path
  var targetPath = 
    if targetDir == "": getCurrentDir() / repoName
    else: getCurrentDir() / targetDir / repoName
  
  # Check if source exists
  if not dirExists(sourcePath):
    echo "Error: ".red & "Source directory not found: " & sourcePath
    return
  
  # Create target directory if it doesn't exist
  let targetParent = parentDir(targetPath)
  if not dirExists(targetParent) and targetParent != "":
    createDir(targetParent)
  
  # Check if target already exists
  if dirExists(targetPath) or fileExists(targetPath):
    echo "Error: ".red & "Target already exists: " & targetPath
    return
  
  # Create symlink
  try:
    createSymlink(sourcePath, targetPath)
    echo "Success: ".green & "Created symlink for " & repoName.bold.yellow
    echo "Source: ".blue & sourcePath
    echo "Target: ".blue & targetPath
  except:
    echo "Error: ".red & "Failed to create symlink"
    echo "Source: ".red & sourcePath
    echo "Target: ".red & targetPath
    echo "You may need administrator privileges."

proc showUsage() =
  echo "nimlink - Simple repository linking tool for Nim".bold
  echo "Usage: nimlink [OPTIONS] [REPO_NAME]".yellow
  echo ""
  echo "Options:"
  echo "  -h, --help     Show this help"
  echo "  -l, --list     List registered repositories"
  echo "  -i, --install  Install repository (requires REPO_NAME)"
  echo "  -t, --target   Target directory for installation (used with --install)"
  echo ""
  echo "Examples:".bold
  echo "  nimlink                 # Register current repository"
  echo "  nimlink --list          # List all registered repositories"
  echo "  nimlink --install repo  # Install 'repo' in current directory"

proc main() =
  let args = commandLineParams()
  
  if args.len == 0:
    # Register current repository
    registerRepo(getCurrentDir())
    return
  
  var i = 0
  while i < args.len:
    case args[i]
    of "-h", "--help":
      showUsage()
      return
      
    of "-l", "--list":
      listRepos()
      return
      
    of "-i", "--install":
      if i + 1 >= args.len:
        echo "Error: ".red & "No repository name provided for installation"
        return
      
      var targetDir = ""
      # Check for target option
      if i + 2 < args.len and args[i + 2] in ["-t", "--target"]:
        if i + 3 < args.len:
          targetDir = args[i + 3]
          installRepo(args[i + 1], targetDir)
          return
        else:
          echo "Error: ".red & "No target directory provided"
          return
      # Check if the target is already provided
      elif i + 2 < args.len and args[i + 2] notin ["-t", "--target"]:
        targetDir = args[i + 2]
        installRepo(args[i + 1], targetDir)
        return
      else:
        installRepo(args[i + 1])
        return
        
    of "-t", "--target":
      echo "Error: ".red & "--target must be used with --install"
      return
      
    else:
      echo "Unknown option: ".red & args[i]
      showUsage()
      return
      
    inc i

when isMainModule:
  main()