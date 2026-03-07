#!/usr/bin/env python3
import sys
import os
import json
from lxml import etree
from lxml.isoschematron import Schematron

def validate_and_heal(xml_str, xsd_path, sch_path=None):
    """
    Validates XML against XSD and Schematron, attempts to heal syntax issues.
    Returns: { "success": bool, "healed_xml": str, "errors": list }
    """
    errors = []
    
    # 1. Parsing with recovery (Healing)
    parser = etree.XMLParser(recover=True, remove_blank_text=True)
    try:
        # Normalize input: Ensure it has a root <session> tag for validation
        xml_trimmed = xml_str.strip()
        if "<session" not in xml_trimmed[:100]:
            # If it's just a fragment, we must provide the minimum required root state
            wrapped = f'<session xmlns="nzi" xmlns:agent="nzi" xmlns:model="nzi" xmlns:nzi="nzi"><system/><project_roadmap/>{xml_str}</session>'
        else:
            # Ensure namespaces are present if it is already a session
            if 'xmlns="nzi"' not in xml_trimmed and 'xmlns:agent="nzi"' not in xml_trimmed:
                xml_trimmed = xml_trimmed.replace("<session", '<session xmlns="nzi" xmlns:agent="nzi" xmlns:model="nzi" xmlns:nzi="nzi"', 1)
                xml_trimmed = xml_trimmed.replace("<agent:session", '<agent:session xmlns:agent="nzi" xmlns:model="nzi" xmlns:nzi="nzi"', 1)
            wrapped = xml_trimmed

        root = etree.fromstring(wrapped, parser=parser)
        healed_xml = etree.tostring(root, encoding='unicode', pretty_print=True)
    except Exception as e:
        return {"success": False, "healed_xml": xml_str, "errors": [f"Parse Error: {str(e)}"]}

    # 2. Layer 1: XSD (Structural integrity)
    if os.path.exists(xsd_path):
        try:
            with open(xsd_path, 'rb') as f:
                schema = etree.XMLSchema(etree.XML(f.read()))
                if not schema.validate(root):
                    for error in schema.error_log:
                        msg = error.message.replace("{nzi}", "")
                        errors.append(f"XSD Line {error.line}: {msg}")
        except Exception as e:
            errors.append(f"XSD Load Error: {str(e)}")

    # 3. Layer 2: Schematron (Contract rules & XPath)
    if sch_path and os.path.exists(sch_path):
        try:
            with open(sch_path, 'rb') as f:
                schematron = Schematron(etree.XML(f.read()))
                if not schematron.validate(root):
                    for error in schematron.error_log:
                        msg = error.message.replace("{nzi}", "")
                        errors.append(f"SCH Line {error.line}: {msg}")
        except Exception as e:
            errors.append(f"SCH Load Error: {str(e)}")
            
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
    sch_path = sys.argv[2] if len(sys.argv) > 2 else None
    
    result = validate_and_heal(xml_input, schema_path, sch_path)
    print(json.dumps(result))
