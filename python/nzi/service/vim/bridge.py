import sys
import json
import logging
import os

# Add the project root to sys.path to allow absolute imports of the nzi package
script_dir = os.path.dirname(os.path.abspath(__file__))
# python/nzi/service/vim/ -> 4 levels up to reach root
project_root = os.path.abspath(os.path.join(script_dir, "..", "..", "..", ".."))
python_dir = os.path.join(project_root, "python")
if python_dir not in sys.path:
    sys.path.insert(0, python_dir)

from nzi.core.dom import SessionDOM
from nzi.service.vim.context import ContextService
from nzi.service.vim.effector import VimEffector
from nzi.service.llm.client import LLMClient
from nzi.service.prompt.projector import project_dom_to_messages

class VimBridge:
    """
    Control Bridge: Orchestrates state sync and model execution between Vim and DOM.
    This is the STDIN/STDOUT JSON-RPC server.
    """
    def __init__(self):
        self.dom = None
        self.context = None
        self.effector = None
        self.llm = LLMClient()
        self.project_root = None

    def setup(self, xsd_path, sch_path, project_root, debug=False):
        self.project_root = project_root
        self.dom = SessionDOM(xsd_path, sch_path)
        self.context = ContextService(project_root)
        self.effector = VimEffector(self)
        
        # Initial context sync
        self.context.sync_to_dom(self.dom, [])
        self.send_to_vim({"method": "refresh_ui"})

    def log(self, msg, level=logging.DEBUG):
        logging.log(level, f"[BRIDGE] {msg}")
        if os.getenv("NZI_DEBUG") == "1":
            try:
                log_path = os.path.join(self.project_root or ".", "nzi_debug.log")
                with open(log_path, "a") as f:
                    import datetime
                    f.write(f"[{datetime.datetime.now().strftime('%H:%M:%S')}] [PYTHON] {msg}\n")
            except: pass

    def send_to_vim(self, payload):
        # Auto-inject the latest XML state into every response to Lua
        if self.dom and "xml" not in payload:
            payload["xml"] = self.dom.dump_xml()

        sys.stdout.write(json.dumps(payload) + "\n")
        sys.stdout.flush()

    def handle_request(self, req):
        import time
        start_time = time.time()
        method = req.get("method")
        params = req.get("params", {})
        rid = req.get("id")
        
        self.log(f"Handling {method} (id={rid})")

        try:
            if method == "clear":
                self.dom.clear()
                self.send_to_vim({"success": True, "id": rid})
                self.send_to_vim({"method": "refresh_ui"})
            
            elif method == "update_context":
                self.context.sync_to_dom(self.dom, params.get("ctx_list", []))
                self.send_to_vim({"success": True, "id": rid})
                self.send_to_vim({"method": "refresh_ui"})

            elif method == "build_messages":
                msgs = project_dom_to_messages(self.dom, params.get("system_prompt"))
                self.send_to_vim({"success": True, "messages": msgs, "id": rid})

            elif method == "xpath":
                res = self.dom.xpath(params.get("query"))
                self.send_to_vim({"success": True, "results": res, "id": rid})

            elif method == "run_loop":
                self.execute_loop(params, rid)

            elif method == "add_turn":
                self.dom.add_turn(params["user_data"], params.get("assistant"), params.get("metadata"), params.get("id"))
                self.send_to_vim({"success": True, "id": rid})
                self.send_to_vim({"method": "refresh_ui"})

            elif method == "hydrate":
                # Create a new DOM from the provided XML string
                self.dom.hydrate(params.get("xml"))
                self.send_to_vim({"success": True, "id": rid})
                self.send_to_vim({"method": "refresh_ui"})

            elif method == "delete_after":
                self.dom.delete_after(params.get("turn_id"))
                self.send_to_vim({"success": True, "id": rid})
                self.send_to_vim({"method": "refresh_ui"})

            elif method == "set_system_prompt":
                self.dom.set_system_prompt(params.get("content"))
                self.send_to_vim({"success": True, "id": rid})
                self.send_to_vim({"method": "refresh_ui"})

            else:
                self.send_to_vim({"success": False, "error": f"Unknown method: {method}", "id": rid})

        except Exception as e:
            self.log(f"Internal Error: {str(e)}", logging.ERROR)
            self.send_to_vim({"success": False, "error": str(e), "id": rid})
        
        self.log(f"Finished {method} in {time.time() - start_time:.4f}s")

    def execute_loop(self, params, rid):
        instruction = params.get("instruction")
        mode = params.get("mode", "act")
        user_data = params.get("user_data", instruction)
        config = params.get("config", {})

        # 1. Start the Turn in DOM
        # Turn ID is handled by DOM auto-increment or passed via params
        turn = self.dom.start_turn(user_data, turn_id=params.get("turn_id"))
        self.send_to_vim({"method": "refresh_ui"})

        # 2. Build Messages
        messages = project_dom_to_messages(self.dom)

        # 3. Stream from LLM
        def on_chunk(chunk, chunk_type="content"):
            if chunk_type == "content":
                self.dom.append_to_turn(chunk)
            
            # Send incremental update to Vim
            self.send_to_vim({
                "method": "stream_chunk",
                "params": {
                    "content": chunk,
                    "type": chunk_type
                }
            })

        success, full_result = self.llm.stream_complete(messages, config, on_chunk)

        if not success:
            error_msg = f"<status level='error'>{full_result}</status>"
            self.dom.finalize_turn({"content": error_msg})
            self.send_to_vim({"success": False, "error": full_result, "id": rid})
            self.send_to_vim({"method": "refresh_ui"})
            return

        # 4. Finalize DOM Turn
        self.dom.finalize_turn(full_result)
        
        # 5. Extract Actions
        from nzi.core.parser import ActionParser
        parser = ActionParser()
        content_str = full_result.get("content", "")
        actions = parser.parse(content_str)

        # 6. Execute Actions (Automated Discovery Loop)
        for action in actions:
            if action.name == "read":
                # Automated Discovery Loop
                filename = action.attributes.get("file")
                content = self.effector.handle_read(filename)
                self.execute_loop({
                    "type": "env",
                    "status": "pass",
                    "file": filename,
                    "content": content,
                    "instruction": f"Read file {filename}. Proceed.",
                    "config": config
                }, rid)
            elif action.name == "lookup":
                # Automated Discovery Loop
                pattern = action.content
                results = self.effector.handle_lookup(pattern)
                self.execute_loop({
                    "type": "env",
                    "status": "pass",
                    "content": results,
                    "instruction": f"Lookup results for '{pattern}'. Proceed.",
                    "config": config
                }, rid)
            elif action.name == "run":
                self.effector.run(action.content)
            elif action.name == "env":
                self.effector.run(action.content, signal_type="env")
            elif action.name == "create":
                self.effector.propose_create({
                    "file": action.attributes.get("file"),
                    "content": action.content
                })
            elif action.name == "edit":
                # Parser provides searched/replaced blocks
                self.effector.propose_edit({
                    "file": action.attributes.get("file"),
                    "blocks": action.blocks
                })
            elif action.name == "delete":
                self.effector.propose_delete({
                    "file": action.attributes.get("file")
                })
            elif action.name == "prompt_user":
                self.effector.propose_choice({
                    "content": action.content
                })
            elif action.name == "ask":
                self.effector.propose_choice({
                    "content": f"{action.content}\n- [ ] Response"
                })

        self.send_to_vim({"success": True, "id": rid, "actions_executed": len(actions)})

    def listen(self):
        for line in sys.stdin:
            try:
                req = json.loads(line)
                self.handle_request(req)
            except Exception as e:
                self.log(f"Listener Error: {str(e)}", logging.ERROR)

if __name__ == "__main__":
    # Setup basic logging to file
    logging.basicConfig(filename='/tmp/nzi_bridge.log', level=logging.DEBUG)
    bridge = VimBridge()
    xsd = os.path.join(project_root, "nzi.xsd")
    sch = os.path.join(project_root, "nzi.sch")
    bridge.setup(xsd, sch, project_root, debug=True)
    bridge.listen()
