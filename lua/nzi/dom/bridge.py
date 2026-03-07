#!/usr/bin/env python3
import sys
import os
import json
from lxml import etree

def xpath_query(xml_str, query, namespaces=None):
    if namespaces is None:
        namespaces = {"nzi": "nzi", "agent": "nzi", "model": "nzi"}
    
    parser = etree.XMLParser(recover=True, remove_blank_text=True)
    try:
        # Wrap in session if not present
        xml_trimmed = xml_str.strip()
        if not xml_trimmed.startswith("<session"):
            wrapped = f'<session xmlns="nzi" xmlns:agent="nzi" xmlns:model="nzi">{xml_str}</session>'
        else:
            if 'xmlns="nzi"' not in xml_trimmed:
                xml_trimmed = xml_trimmed.replace("<session", '<session xmlns="nzi" xmlns:agent="nzi" xmlns:model="nzi"', 1)
            wrapped = xml_trimmed
            
        root = etree.fromstring(wrapped, parser=parser)
        results = root.xpath(query, namespaces=namespaces)
        
        final_results = []
        for r in results:
            if isinstance(r, etree._Element):
                final_results.append(etree.tostring(r, encoding='unicode').strip())
            else:
                final_results.append(str(r).strip())
        return {"success": True, "results": final_results}
    except Exception as e:
        return {"success": False, "error": str(e)}

def parse_output(text):
    """
    Parses LLM output for <model:*> tags and markdown code blocks.
    Uses regex for extraction because LLM output often contains unescaped characters (like <)
    that break standard XML parsers.
    """
    actions = []
    import re
    
    # 1. Extract Tags using Regex
    # Matches <model:tag attr="val">content</model:tag>
    tag_pattern = re.compile(r'<model:([\w_]+)([^>]*?)>(.*?)</model:\1>', re.DOTALL)
    for match in tag_pattern.finditer(text):
        tag_name = match.group(1)
        attr_str = match.group(2).strip()
        content = match.group(3).strip()
        
        # Parse attributes from attr_str
        attr_dict = {}
        for attr_match in re.finditer(r'([\w_-]+)=["\']([^"\']+)["\']', attr_str):
            attr_dict[attr_match.group(1)] = attr_match.group(2)
            
        action = {
            "name": tag_name,
            "attr": attr_dict,
            "content": content
        }
        
        # If it's an edit block, parse structured search/replace internally
        if tag_name == "edit":
            blocks = []
            lines = content.split("\n")
            current_block = None
            state = "none"
            for line in lines:
                if line.startswith("<<<<<<<"):
                    current_block = {"search": [], "replace": []}
                    state = "search"
                elif line.startswith("======="):
                    state = "replace"
                elif line.startswith(">>>>>>>"):
                    if current_block:
                        blocks.append({
                            "search": current_block["search"],
                            "replace": current_block["replace"]
                        })
                        current_block = None
                    state = "none"
                elif state == "search":
                    current_block["search"].append(line)
                elif state == "replace":
                    current_block["replace"].append(line)
            action["blocks"] = blocks
            
        actions.append(action)
        
    # Matches self-closing tags <model:tag attr="val" />
    self_closing_pattern = re.compile(r'<model:([\w_]+)([^>]*?)/\s*>', re.DOTALL)
    for match in self_closing_pattern.finditer(text):
        tag_name = match.group(1)
        attr_str = match.group(2).strip()
        
        attr_dict = {}
        for attr_match in re.finditer(r'([\w_-]+)=["\']([^"\']+)["\']', attr_str):
            attr_dict[attr_match.group(1)] = attr_match.group(2)
            
        actions.append({
            "name": tag_name,
            "attr": attr_dict,
            "content": ""
        })

    # 2. Extract Markdown Blocks (Standard regex)
    # Shell blocks
    for match in re.finditer(r"```(?:sh|bash)\s*\n(.*?)\n```", text, re.DOTALL):
        actions.append({
            "name": "shell",
            "attr": {},
            "content": match.group(1).strip()
        })
        
    # Full-file replacement "Secret" fallback
    for match in re.finditer(r"```(\w+)\s*\n(.*?)\n```", text, re.DOTALL):
        lang = match.group(1)
        content = match.group(2)
        if lang not in ["sh", "bash"]:
            # Check for path in first lines
            first_lines = content.split("\n")[:2]
            path_match = None
            for line in first_lines:
                m = re.search(r"[#\-]{2,}\s*([\w\d_\-\./]+)", line)
                if m and "." in m.group(1):
                    path_match = m.group(1)
                    break
            if path_match:
                actions.append({
                    "name": "replace_all",
                    "attr": {"file": path_match},
                    "content": content
                })

    return {"success": True, "actions": actions}

def main():
    try:
        raw_input = sys.stdin.read()
        if not raw_input.strip():
            sys.exit(0)
        request = json.loads(raw_input)
    except Exception as e:
        print(json.dumps({"success": False, "error": f"Failed to parse input: {str(e)}"}))
        sys.exit(1)

    action = request.get("action")
    if action == "xpath":
        res = xpath_query(request.get("xml", ""), request.get("query", ""), request.get("namespaces"))
        print(json.dumps(res))
    elif action == "parse":
        res = parse_output(request.get("text", ""))
        print(json.dumps(res))
    else:
        print(json.dumps({"success": False, "error": f"Unknown action: {action}"}))
        sys.exit(1)

if __name__ == "__main__":
    main()
