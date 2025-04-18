# nimlink

A simple and efficient tool for linking Nim packages for local development.

## Problem

Working with local Nim packages should be simple, but often involves tedious manual steps:

- `nimble develop` doesn't respect `srcDir` in `.nimble` files
- Creating symlinks manually is error-prone and boring
- Editing `nim.cfg` files by hand is unnecessary work

## Solution

`nimlink` automates these tedious tasks:

1. Tracks your local packages in a simple registry
2. Creates symlinks automatically with a single command
3. Updates `nim.cfg` files for you to ensure imports work
4. Makes everything "just work" so you can focus on coding

No more manually creating symlinks. No more editing config files. Just register once, install anywhere, and get back to writing Nim.

## Installation

```bash
# Clone the repository
git clone https://github.com/yourusername/nimlink
cd nimlink

# Build it
nim c -d:release nimlink.nim

# Move it to your PATH
cp nimlink ~/.local/bin/ # or another directory in your PATH
```

## Basic Usage

```bash
# Register the current package
cd /path/to/your/package
nimlink

# List registered packages
nimlink list  # or: nimlink l

# Install a package in your project
cd /path/to/your/project
nimlink install package_name  # or: nimlink i package_name

# Install without symlinks (direct mode)
nimlink install package_name -d  # or: nimlink i package_name --direct

# Uninstall a package
nimlink uninstall package_name  # or: nimlink u package_name

# Remove a package from the registry
nimlink remove package_name  # or: nimlink rm package_name
```

## Commands

| Command | Shorthand | Description |
|---------|-----------|-------------|
| `nimlink` | | Register the current directory as a package |
| `nimlink list` | `nimlink l` | List all registered packages |
| `nimlink install NAME` | `nimlink i NAME` | Install a package in your project |
| `nimlink install NAME -d` | `nimlink i NAME --direct` | Add package path directly to nim.cfg (no symlinks) |
| `nimlink uninstall NAME` | `nimlink u NAME` | Remove an installed package from your project |
| `nimlink uninstall NAME -d` | `nimlink u NAME --direct` | Remove a direct path from nim.cfg |
| `nimlink remove NAME` | `nimlink rm NAME` | Remove a package from the registry database |
| `nimlink help` | `nimlink h` | Show help information |

## How It Works

1. **Registration**: When you run `nimlink` in a package directory:
   - Detects the package name from the `.nimble` file
   - Extracts `srcDir` if present
   - Stores the information in `~/.nimlink`

2. **Installation**: When you run `nimlink i package_name`:
   - Creates a `nimlinks/` directory in your project
   - Creates a symlink from the package source to `nimlinks/package_name/`
   - Adds `--path="nimlinks/package_name"` to your project's `nim.cfg`

3. **Direct Mode**: When you run `nimlink i package_name -d`:
   - Skips creating symlinks entirely
   - Adds the absolute path directly to nim.cfg: `--path="/path/to/package/src"`
   - Great for situations where symlinks are problematic

4. **Importing**: In your code:
   - Use `import package_name` from anywhere in your project
   - All changes to the source package are immediately available

## Configuration

You can customize the links directory name with an environment variable:

```bash
export NIMLINK_DIR="vendor"  # Use "vendor" instead of "nimlinks"
```

## Examples

### Developing a library and an application together

```bash
# Register your library
cd ~/projects/mylibrary
nimlink

# Link it in your application (using shorthand)
cd ~/projects/myapp
nimlink i mylibrary

# Now in your application code
# You can use: import mylibrary
# Even from subdirectories like tests/
```

### Working with multiple libraries (with direct paths)

```bash
# Register all your libraries
cd ~/projects/lib1
nimlink
cd ~/projects/lib2
nimlink

# Link them in your project without symlinks (using shorthand)
cd ~/projects/myproject
nimlink i lib1 -d
nimlink i lib2 -d

# Use them in your code
# import lib1
# import lib2
```

## Requirements

- pkg/colors (install with `nimble install colors`)

## License

MIT