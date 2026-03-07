import os
import sys
import json
from lxml import etree

# Add project root to sys.path
project_root = os.getcwd()
sys.path.insert(0, os.path.join(project_root, "python"))

from nzi.core.dom import SessionDOM
from nzi.service.prompt.projector import project_dom_to_messages
from nzi.service.vim.context import ContextService

def dump():
    xsd = os.path.join(project_root, "nzi.xsd")
    sch = os.path.join(project_root, "nzi.sch")
    
    # 1. Initialize DOM
    dom = SessionDOM(xsd, sch)
    
    # 2. Load nzi.prompt
    prompt_path = os.path.join(project_root, "nzi.prompt")
    if os.path.exists(prompt_path):
        with open(prompt_path, 'r') as f:
            dom.set_system_prompt(f.read())
            
    # 3. Sync Context (Mocking a simple buffer)
    context = ContextService(project_root)
    mock_vim_items = [
        {"name": "drill_test.txt", "state": "active", "content": "Original Content\n"}
    ]
    context.sync_to_dom(dom, mock_vim_items)
    
    # 4. Add a Turn
    dom.start_turn(1, "Replace 'Original' with 'DRILL'")
    
    # 5. Project to Messages
    messages = project_dom_to_messages(dom)
    
    print(json.dumps(messages, indent=2))

if __name__ == "__main__":
    dump()
