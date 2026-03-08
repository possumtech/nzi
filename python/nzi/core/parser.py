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
