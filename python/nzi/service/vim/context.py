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
            # Fallback for non-git repos: walk the directory (capped)
            return []

    def sync_to_dom(self, dom, raw_vim_items):
        """
        Processes raw data from Vim and updates the DOM session.
        """
        final_context = []
        
        # 1. Start with the project universe (the map)
        universe = self.get_universe()
        for path in universe:
            final_context.append({
                "name": path,
                "state": "map"
            })

        # 2. Promote/Update with real buffer content from Vim
        for item in raw_vim_items:
            name = item['name']
            existing = next((x for x in final_context if x["name"] == name), None)
            if existing:
                existing["state"] = "active"
                if item.get("content"):
                    existing["content"] = item["content"]
            else:
                final_context.append({
                    "name": name,
                    "state": "active",
                    "content": item.get("content")
                })

        # 3. Read roadmap from AGENTS.md
        roadmap_content = None
        roadmap_path = os.path.join(self.project_root, "AGENTS.md")
        if os.path.exists(roadmap_path):
            with open(roadmap_path, 'r') as f:
                roadmap_content = f.read()

        dom.update_context(final_context, roadmap_content)
