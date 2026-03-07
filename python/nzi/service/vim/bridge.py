import sys
import json
import logging
import os

# Add the project root to sys.path to allow absolute imports of the nzi package
script_dir = os.path.dirname(os.path.abspath(__file__))
project_root = os.path.abspath(os.path.join(script_dir, "../../../.."))
if project_root not in sys.path:
    # Also add the /python directory to path for the nzi package itself
    sys.path.insert(0, os.path.join(project_root, "python"))

from nzi.core.dom import SessionDOM, ContractViolationError
from nzi.core.parser import ActionParser
from nzi.service.llm.client import LLMClient
from nzi.service.prompt.projector import project_dom_to_messages
from nzi.service.vim.effector import VimEffector
from nzi.service.vim.context import ContextService

def load_env(project_root):
    env_path = os.path.join(project_root, ".env")
    if os.path.exists(env_path):
        with open(env_path, 'r') as f:
            for line in f:
                line = line.strip()
                if line and not line.startswith('#'):
                    if '=' in line:
                        key, value = line.split('=', 1)
                        value = value.strip().strip("'").strip('"')
                        os.environ[key.strip()] = value
    else:
        logging.warning(".env file not found!")

class VimBridge:
    """
    Hardware Sync: Translates between JSON-RPC from Vim and the Python core.
    """
    def __init__(self):
        self.dom = None
        self.llm = LLMClient()
        self.parser = ActionParser()
        self.effector = VimEffector(self)
        self.context = None
        self.running = True
        self.project_root = None

    def setup(self, xsd_path, sch_path, project_root, debug=False):
        self.project_root = project_root
        load_env(project_root)
        self.dom = SessionDOM(xsd_path, sch_path, debug_mode=debug)
        self.context = ContextService(project_root)
        
        # Load the Constitution (System Prompt)
        prompt_path = os.path.join(project_root, "nzi.prompt")
        if os.path.exists(prompt_path):
            with open(prompt_path, 'r') as f:
                self.dom.set_system_prompt(f.read())
        else:
            self.dom.set_system_prompt("You are an agent.")

    def log(self, msg, level=logging.DEBUG):
        logging.log(level, f"[BRIDGE] {msg}")

    def send_to_vim(self, payload):
        print(json.dumps(payload), flush=True)

    def handle_request(self, req):
        method = req.get("method")
        params = req.get("params", {})
        rid = req.get("id")

        if isinstance(params, list):
            params = {}

        try:
            if method == "clear":
                self.dom.clear()
                self.send_to_vim({"success": True, "id": rid})
            
            elif method == "update_context":
                self.context.sync_to_dom(self.dom, params.get("ctx_list", []))
                self.send_to_vim({"success": True, "id": rid})

            elif method == "build_messages":
                msgs = project_dom_to_messages(self.dom, params.get("system_prompt"))
                self.send_to_vim({"success": True, "messages": msgs, "id": rid})

            elif method == "xpath":
                res = self.dom.xpath(params.get("query"))
                self.send_to_vim({"success": True, "results": res, "id": rid})

            elif method == "format":
                self.send_to_vim({"success": True, "xml": self.dom.dump_xml(), "id": rid})

            elif method == "set_system_prompt":
                self.dom.set_system_prompt(params.get("content"))
                self.send_to_vim({"success": True, "id": rid})

            elif method == "add_turn":
                self.dom.add_turn(params["id"], params["user_data"], params.get("assistant"), params.get("metadata"))
                self.send_to_vim({"success": True, "id": rid})

            elif method == "run_loop":
                self.execute_loop(params, rid)

            else:
                self.send_to_vim({"success": False, "error": f"Unknown method: {method}", "id": rid})

        except ContractViolationError as e:
            self.send_to_vim({"success": False, "error": str(e), "xml_dump": e.xml_dump, "id": rid})
        except Exception as e:
            self.log(f"Internal Error: {str(e)}", logging.ERROR)
            self.send_to_vim({"success": False, "error": f"Python Error: {str(e)}", "id": rid})

    def execute_loop(self, params, rid):
        """
        Cognitive Loop: LLM Call -> Streaming -> Action Extraction -> Effector -> DOM Update
        """
        instruction = params.get("instruction")
        user_data = params.get("user_data")
        config = params.get("config", {})

        # 1. Determine Next ID
        try:
            turns = self.dom.xpath("count(//turn)")
            next_id = int(float(turns[0])) + 1
        except:
            next_id = 1

        # 2. Create Turn in DOM immediately
        self.dom.start_turn(next_id, user_data or instruction)

        # 3. Project DOM to Messages
        messages = project_dom_to_messages(self.dom)

        # 4. Stream from LLM
        def on_chunk(text, chunk_type):
            # Update DOM SSOT
            self.dom.append_to_turn(text)
            # Notify Vim to refresh UI
            self.send_to_vim({
                "method": "refresh_ui",
                "params": {"turn_id": next_id}
            })

        success, full_result = self.llm.stream_complete(messages, config, on_chunk)

        if not success:
            # Finalize turn with error if possible
            self.dom.finalize_turn(f"<status level='error'>{full_result}</status>")
            self.send_to_vim({"success": False, "error": full_result, "id": rid})
            return

        # 5. Parse and Finalize DOM
        self.dom.finalize_turn(full_result)
        
        # 6. Parse Actions from the final content
        actions = self.parser.extract_actions(full_result)
        
        # 7. Execute Actions via Effector
        action_results = []
        for action in actions:
            res = self.effector.dispatch(action)
            action_results.append(res)

        self.send_to_vim({"success": True, "id": rid, "actions_executed": len(actions)})

    def listen(self):
        for line in sys.stdin:
            if not line.strip(): continue
            try:
                req = json.loads(line)
                self.handle_request(req)
            except Exception as e:
                self.log(f"Parse Error: {str(e)}")

if __name__ == "__main__":
    # Suppress output to terminal, use file logging ONLY
    logging.basicConfig(filename='/tmp/nzi_bridge.log', level=logging.DEBUG)
    
    bridge = VimBridge()
    xsd = os.path.join(project_root, "nzi.xsd")
    sch = os.path.join(project_root, "nzi.sch")
    
    bridge.setup(xsd, sch, project_root, debug=(os.environ.get("NZI_DEBUG") == "1"))
    bridge.listen()
