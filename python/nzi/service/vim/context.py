import os
import subprocess
import logging

class ContextService:
    """
    Intelligence Service: Manages project mapping and buffer prioritization.
    Decides what actually makes it into the XML DOM based on workspace state.
    """
    def __init__(self, project_root):
        self.project_root = project_root

    def get_universe(self):
        """
        Lists all tracked files in the repository to provide a 'map' context.
        """
        try:
            res = subprocess.check_output(
                ["git", "ls-files"], 
                cwd=self.project_root, 
                stderr=subprocess.DEVNULL
            )
            return res.decode('utf-8').splitlines()
        except:
            return []

    def sync_to_dom(self, dom, raw_vim_items):
        """
        Processes raw data from Vim and updates the DOM session.
        Calculates metadata (like size) in Python.
        """
        final_context = []
        
        # 1. Start with the project universe (the map)
        universe = self.get_universe()
        for path in universe:
            full_path = os.path.join(self.project_root, path)
            size = -1
            if os.path.exists(full_path):
                size = os.path.getsize(full_path)
                
            final_context.append({
                "path": path,
                "state": "map",
                "size": str(size)
            })

        # 2. Promote/Update with real buffer content from Vim
        for item in raw_vim_items:
            name = item['name']
            existing = next((x for x in final_context if x["path"] == name), None)
            
            full_path = os.path.join(self.project_root, name)
            size = -1
            if os.path.exists(full_path):
                size = os.path.getsize(full_path)

            if existing:
                existing["state"] = item.get("state", "active")
                existing["size"] = str(size)
                if item.get("content"):
                    existing["content"] = item["content"]
            else:
                final_context.append({
                    "path": name,
                    "state": item.get("state", "active"),
                    "size": str(size),
                    "content": item.get("content")
                })

        # 3. Read roadmap from AGENTS.md
        roadmap_content = "Roadmap file not found."
        roadmap_path = os.path.join(self.project_root, "AGENTS.md")
        if os.path.exists(roadmap_path):
            with open(roadmap_path, 'r') as f:
                roadmap_content = f.read()

        dom.update_context(final_context, roadmap_content)
