# Godot MCP Server Setup Guide

This guide will help you set up the **Coding-Solo/godot-mcp** server for enhanced Godot development with Claude Code.

## Prerequisites

- Godot Engine installed (Godot 4.x)
- Node.js (v18+) and npm installed
- Claude Code CLI

## Installation Steps

### 1. Install the Godot MCP Server

```bash
# Navigate to a suitable location for MCP servers (e.g., ~/mcp-servers/)
cd ~/mcp-servers  # or C:\mcp-servers on Windows

# Clone the repository
git clone https://github.com/Coding-Solo/godot-mcp.git
cd godot-mcp

# Install dependencies
npm install

# Build the server
npm run build
```

### 2. Locate Your Claude Code MCP Configuration

Claude Code uses a global MCP configuration file. Common locations:

**Windows:**
- `%APPDATA%\Claude\claude_desktop_config.json`
- `%USERPROFILE%\.config\claude\claude_desktop_config.json`

**macOS:**
- `~/Library/Application Support/Claude/claude_desktop_config.json`

**Linux:**
- `~/.config/claude/claude_desktop_config.json`

### 3. Configure Claude Code

Edit your `claude_desktop_config.json` and add the Godot MCP server:

```json
{
  "mcpServers": {
    "godot": {
      "command": "node",
      "args": [
        "C:\\mcp-servers\\godot-mcp\\build\\index.js"
      ],
      "env": {
        "GODOT_PATH": "C:\\Path\\To\\Godot_v4.x_stable.exe",
        "DEBUG": "false"
      }
    }
  }
}
```

**Important:**
- Replace the path in `args` with your actual path to the built MCP server
- Replace `GODOT_PATH` with your Godot executable path
- Use forward slashes or double backslashes on Windows

### 4. Restart Claude Code

After saving the configuration:
1. Close Claude Code completely
2. Reopen Claude Code
3. Navigate to your project directory

### 5. Verify the MCP Server

Try these test prompts to verify the connection:

```
"List available MCP tools"
"Launch the Godot editor for this project"
"Get Godot project information"
```

## Available MCP Tools

Once configured, you'll have access to:

- **launch_editor** - Launch the Godot editor for your project
- **run_project** - Run the project and capture debug output
- **get_project_info** - Get information about the current project
- **list_scenes** - List all scenes in the project
- **create_scene** - Create a new scene with nodes
- **get_debug_output** - Capture console output and errors

## Environment Variables

| Variable | Description | Example |
|----------|-------------|---------|
| `GODOT_PATH` | Path to Godot executable | `C:\Godot\Godot_v4.3.exe` |
| `DEBUG` | Enable detailed logging | `true` or `false` |

## Troubleshooting

### MCP Server Not Found
- Verify the path in `claude_desktop_config.json` points to `build/index.js`
- Ensure you ran `npm run build` successfully

### Godot Not Launching
- Check `GODOT_PATH` is correct
- Verify Godot executable has proper permissions
- Try setting `DEBUG: "true"` to see detailed logs

### Permission Errors
- On Linux/macOS, ensure the Godot executable is executable: `chmod +x /path/to/godot`
- Check that Claude Code has permission to execute Node.js commands

## Project-Specific Configuration

For this project (Alcohol Empire Tycoon), the MCP server will:
- Help navigate between world map and factory interior scenes
- Inspect scene hierarchies and node structures
- Provide Godot 4.x API documentation
- Assist with autoload singleton setup
- Help manage the dual-layer scene architecture

## Next Steps

Once the MCP server is configured:
1. Test with "Get Godot project information"
2. Use "Launch editor" to open the project
3. Ask for scene inspection and navigation help
4. Request Godot API documentation when needed

---

**Current Project:** Alcohol Empire Tycoon
**Project Path:** `C:\GitLab\gamedev\Repo\butykos`
**Godot Version:** 4.x
