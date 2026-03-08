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
            "choice", "reset", "status", "ack", "match",
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
        Parses SEARCH/REPLACE blocks. 
        Supports standard markers: <<<<<<< SEARCH, =======, >>>>>>> REPLACE
        Heuristically heals blocks with missing brackets or minor drift.
        Returns a list of dicts: {"search": str, "replace": str, "healed": bool}
        """
        blocks = []
        # 1. Try standard regex first
        standard_pattern = re.compile(r'<<<<<<< SEARCH\n(.*?)\n=======\n(.*?)\n>>>>>>> REPLACE', re.DOTALL)
        matches = standard_pattern.findall(text)
        
        if matches:
            for s, r in matches:
                blocks.append({"search": s, "replace": r, "healed": False})
            return blocks

        # 2. Heuristic fallback: Split by '=======' if 'SEARCH' and 'REPLACE' keywords exist
        if "SEARCH" in text and "REPLACE" in text and "=======" in text:
            # Attempt to split the whole block
            parts = re.split(r'\n?=======\n?', text)
            if len(parts) == 2:
                s_part = parts[0]
                r_part = parts[1]
                
                # Clean up leftover keywords/markers
                s_clean = re.sub(r'^(.*?)SEARCH\n?', '', s_part, flags=re.DOTALL).strip()
                r_clean = re.sub(r'\n?>>>>>>> REPLACE.*$', '', r_part, flags=re.DOTALL).strip()
                
                blocks.append({"search": s_clean, "replace": r_clean, "healed": True})
        
        return blocks

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
