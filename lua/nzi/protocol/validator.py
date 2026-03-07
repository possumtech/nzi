#!/usr/bin/env python3
import sys
import os
import json
from lxml import etree

def validate_and_heal(xml_str, xsd_path):
    """
    Validates XML against XSD and attempts to heal minor syntax issues.
    Returns: { "success": bool, "healed_xml": str, "errors": list }
    """
    errors = []
    healed_xml = xml_str
    
    # 1. Parsing with recovery (Healing)
    # This handles unclosed tags, entity errors, etc.
    parser = etree.XMLParser(recover=True, remove_blank_text=True)
    try:
        # Wrap in root if multiple top-level elements exist
        # We use the 'nzi' namespace as the default for the dummy root
        wrapped = f'<root xmlns="nzi" xmlns:agent="nzi" xmlns:model="nzi" xmlns:user="nzi">{xml_str}</root>'
        root = etree.fromstring(wrapped, parser=parser)
        
        # Strip the dummy root for the 'healed' output
        healed_xml = "".join([etree.tostring(child, encoding='unicode') for child in root])
    except Exception as e:
        return {"success": False, "healed_xml": xml_str, "errors": [str(e)]}

    # 2. Schema Validation
    if os.path.exists(xsd_path):
        try:
            with open(xsd_path, 'rb') as f:
                schema_root = etree.XML(f.read())
                schema = etree.XMLSchema(schema_root)
                
                # Validate the entire wrapped root
                if not schema.validate(root):
                    for error in schema.error_log:
                        # Clean up error messages: remove the namespace prefix from tags
                        msg = error.message.replace("{nzi}", "")
                        errors.append(f"Line {error.line}: {msg}")
        except Exception as e:
            errors.append(f"Schema Error: {str(e)}")
            
    return {
        "success": len(errors) == 0,
        "healed_xml": healed_xml,
        "errors": errors
    }

if __name__ == "__main__":
    if len(sys.argv) < 2:
        print(json.dumps({"success": False, "errors": ["Missing schema path"]}))
        sys.exit(1)
        
    xml_input = sys.stdin.read()
    schema_path = sys.argv[1]
    
    result = validate_and_heal(xml_input, schema_path)
    print(json.dumps(result))
