import os
import logging

class VimEffector:
    """
    Cognitive Output: Decides how to execute model actions.
    Some actions are handled internally (data), others delegated to Vim (UI).
    """
    def __init__(self, bridge):
        self.bridge = bridge

    def dispatch(self, action):
        """
        Routes an action to the correct handler.
        """
        method_name = f"handle_{action.name}"
        handler = getattr(self, method_name, self.handle_unknown)
        return handler(action)

    def handle_read(self, action):
        filename = action.attributes.get("file")
        if not filename: return "Error: Missing file attribute"
        
        # We can handle 'read' internally in Python to update the DOM
        try:
            with open(os.path.join(self.bridge.project_root, filename), 'r') as f:
                content = f.read()
                self.bridge.dom.update_context([{"name": filename, "state": "read", "content": content}], None)
                return f"File {filename} read into context."
        except Exception as e:
            return f"Error reading file {filename}: {str(e)}"

    def handle_edit(self, action):
        from nzi.core.parser import ActionParser
        parser = ActionParser()
        blocks = parser.parse_edit_blocks(action.content)
        
        if not blocks:
            return "Error: Could not parse SEARCH/REPLACE blocks. Ensure you use the unified diff format."

        # Edits are delegated to Vim
        self.bridge.send_to_vim({
            "method": "propose_edit",
            "params": {
                "file": action.attributes.get("file"),
                "blocks": blocks # Send pre-parsed (and potentially healed) blocks
            }
        })
        
        healed = any(b['healed'] for b in blocks)
        if healed:
            return (
                "Edit applied via heuristic healing. Warning: SEARCH/REPLACE markers were malformed.\n"
                "Please use strictly:\n"
                "<<<<<<< SEARCH\n"
                "[exact code to find]\n"
                "=======\n"
                "[new code to replace it with]\n"
                ">>>>>>> REPLACE"
            )
        
        return "Edit proposed in Vim."

    def handle_shell(self, action):
        # Shell commands are delegated to Vim's terminal/job system
        self.bridge.send_to_vim({
            "method": "execute_shell",
            "params": {
                "command": action.content
            }
        })
        return "Shell command dispatched."

    def handle_create(self, action):
        filename = action.attributes.get("file")
        if not filename: return "Error: Missing file attribute"
        
        self.bridge.send_to_vim({
            "method": "propose_create",
            "params": {
                "file": filename,
                "content": action.content
            }
        })
        return f"Creation of {filename} proposed in Vim."

    def handle_grep(self, action):
        pattern = action.content
        self.bridge.send_to_vim({
            "method": "execute_grep",
            "params": {
                "pattern": pattern
            }
        })
        return f"Grep for '{pattern}' dispatched."

    def handle_unknown(self, action):
        logging.warning(f"Unknown action: {action.name}")
        return f"Warning: Action {action.name} is not implemented."
