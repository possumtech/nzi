import os
from lxml import etree

def get_effective_xml(xml_path, prompt_path="nzi.prompt"):
    """
    Reads an XML session file and injects the nzi.prompt into Turn 0's 
    <system> tag if it is missing.
    """
    with open(xml_path, 'rb') as f:
        xml_doc = etree.XML(f.read())
    
    turn0 = xml_doc.xpath("//turn[@id='0']")
    if turn0 and turn0[0].find("system") is None:
        if os.path.exists(prompt_path):
            with open(prompt_path, 'r') as f:
                prompt_content = f.read()
                sys_el = etree.Element("system")
                # Use CDATA to keep the XML dump clean (raw < and >)
                # and ensure the model gets character-perfect tokens.
                sys_el.text = etree.CDATA(prompt_content)
                # Insert at the beginning of Turn 0
                turn0[0].insert(0, sys_el)
    
    return xml_doc
