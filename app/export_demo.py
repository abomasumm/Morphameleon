"""export_demo.py: publish one finished run in the real app dashboard, as plain files for static hosting.

    python3 app/export_demo.py <project path> <output dir>

Writes the app page in read-only snapshot mode, the run's state.json and its diffs. No server, no model calls.
The page loads its logo from ../../assets/, which the demo site in docs/ provides.
"""
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
project, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
# The project's own dashboard.py writes state.json and diffs/, with local paths stripped.
subprocess.run([sys.executable, os.path.join(project, ".agents", "dashboard.py"), "--export", out], cwd=project, check=True)
with open(os.path.join(HERE, "index.html")) as fh:
    page = fh.read().replace("<head>", "<head>\n<script>window.MORPHAMELEON_SNAPSHOT = true; document.documentElement.classList.add(\"snapshot\");</script>", 1)
with open(os.path.join(out, "index.html"), "w") as fh:
    fh.write(page)
with open(os.path.join(out, "project.json"), "w") as fh:
    json.dump({"id": "snapshot", "name": os.path.basename(project), "path": "", "loop": False, "started": True,
               "keyReady": True, "migration": "written", "remote": "", "gh": False}, fh)
print("wrote %s in the app's dashboard design" % out)
