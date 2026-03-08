import re
import logging

class Action:
    def __init__(self, name, content, attributes=None):
        self.name = name
        self.content = content
        self.attributes = attributes or {}

    def __repr__(self):
        return f"Action(name={self.name}, attr={self.attributes})"

class ActionParser:
    """
    Parses action tags from raw assistant text.
    Supported actions: edit, create, read, shell, env, grep, delete, etc.
    """
    def __init__(self):
        # List of tags that we consider "actions" or protocol units
        self.action_tags = [
            "edit", "create", "read", "shell", "env", "lookup", "delete", 
            "choice", "prompt_user", "ask", "reset", "status", "ack", "match",
            "summary", "reasoning", "response"
        ]
        # Regex to match any of the action tags
        tag_list = "|".join(self.action_tags)
        # Matches <tag attr="val">content</tag>
        self.tag_pattern = re.compile(rf'<({tag_list})([^>]*?)>(.*?)</\1>', re.DOTALL)
        # Matches self-closing <tag attr="val" />
        self.self_closing_pattern = re.compile(rf'<({tag_list})([^>]*?)\s*/>')

    def parse_attributes(self, attr_str):
        attrs = {}
        kv_pattern = re.compile(r'(\w+)="([^"]*)"')
        for match in kv_pattern.finditer(attr_str):
            attrs[match.group(1)] = match.group(2)
        return attrs

    def parse_edit_blocks(self, text):
        """
        Robustly parses one or more SEARCH/REPLACE blocks.
        Finds pairs of anchors (SEARCH...=======...REPLACE) and extracts content.
        Preserves all line breaks and indentation.
        """
        blocks = []
        # Pattern looks for: Optional markers + Keyword + Newline -> Content -> ======= -> Content -> Optional markers + Keyword
        # This handles both:
        # <<<<<<< SEARCH          SEARCH
        # code                    code
        # =======         AND     =======
        # code                    code
        # >>>>>>> REPLACE         REPLACE
        pattern = re.compile(
            r'(?:<{3,}\s*)?SEARCH\n(.*?)\n={3,}\n(.*?)\n(?:>{3,}\s*)?REPLACE', 
            re.DOTALL | re.MULTILINE
        )
        
        matches = pattern.finditer(text)
        for match in matches:
            search_content = match.group(1)
            replace_content = match.group(2)
            
            # Determine if this specific block was healed
            # (If it doesn't start with the full <<<<<<< marker)
            is_healed = not match.group(0).startswith('<<<<<<<')
            
            blocks.append({
                "search": search_content,
                "replace": replace_content,
                "healed": is_healed
            })
            
        return blocks

    def parse(self, text):
        """Alias for extract_actions to match bridge usage."""
        return self.extract_actions(text)

    def extract_actions(self, text):
        actions = []
        
        # 1. Extract standard tags
        for match in self.tag_pattern.finditer(text):
            name = match.group(1)
            attr_str = match.group(2)
            content = match.group(3).strip()
            actions.append(Action(name, content, self.parse_attributes(attr_str)))

        # 2. Extract self-closing tags
        for match in self.self_closing_pattern.finditer(text):
            name = match.group(1)
            attr_str = match.group(2)
            actions.append(Action(name, "", self.parse_attributes(attr_str)))

        return actions
