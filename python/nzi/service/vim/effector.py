import os
import logging
import subprocess

class VimEffector:
    """
    Hardware Bridge: Executes model actions by communicating with Neovim.
    """
    def __init__(self, bridge):
        self.bridge = bridge

    def propose_edit(self, params):
        self.bridge.send_to_vim({
            "method": "propose_edit",
            "params": params
        })

    def propose_create(self, params):
        self.bridge.send_to_vim({
            "method": "propose_create",
            "params": params
        })

    def propose_delete(self, params):
        self.bridge.send_to_vim({
            "method": "propose_delete",
            "params": params
        })

    def propose_choice(self, params):
        self.bridge.send_to_vim({
            "method": "propose_choice",
            "params": params
        })

    def handle_read(self, filename):
        """Reads a file and returns its content for the discovery loop."""
        try:
            full_path = os.path.join(self.bridge.project_root, filename)
            if not os.path.exists(full_path):
                return f"Error: File {filename} does not exist."
            with open(full_path, 'r') as f:
                return f.read()
        except Exception as e:
            return f"Error reading file {filename}: {str(e)}"

    def handle_lookup(self, pattern):
        """Performs a technical search and returns results."""
        try:
            # We use git grep -n for line numbers and technical precision
            res = subprocess.check_output(
                ["git", "grep", "-n", "--", pattern],
                cwd=self.bridge.project_root,
                stderr=subprocess.STDOUT
            )
            return res.decode('utf-8')
        except subprocess.CalledProcessError as e:
            if e.returncode == 1:
                return f"No matches found for '{pattern}'."
            return f"Error during lookup: {e.output.decode('utf-8')}"
        except Exception as e:
            return f"Internal lookup error: {str(e)}"

    def run(self, cmd, signal_type="run"):
        """Executes a state-changing command in Vim."""
        self.bridge.send_to_vim({
            "method": "execute_shell",
            "params": {
                "command": cmd,
                "signal_type": signal_type
            }
        })
        return "Command dispatched."
