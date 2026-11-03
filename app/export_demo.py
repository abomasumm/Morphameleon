"""export_demo.py: publish one finished run in the real app dashboard, as plain files for static hosting.

    python3 app/export_demo.py <project path> <output dir> [--single-file]

Writes the app page in read-only snapshot mode, the run's state.json and its diffs. No server, no model calls.
The page loads its logo from ../../assets/, which the demo site in docs/ provides. With --single-file, index.html
holds everything itself, so it opens from a downloaded folder (the GitHub Action's dashboard).
"""
import base64
import json
import os
import subprocess
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
project, out = os.path.abspath(sys.argv[1]), os.path.abspath(sys.argv[2])
# The project's own dashboard.py writes state.json and diffs/, with local paths stripped.
subprocess.run([sys.executable, os.path.join(project, ".agents", "dashboard.py"), "--export", out], cwd=project, check=True)
info = {"id": "snapshot", "name": os.path.basename(project), "path": "", "loop": False, "started": True,
        "keyReady": True, "migration": "written", "remote": "", "gh": False}
snapshot = "true"
if "--single-file" in sys.argv:
    diffs = {}
    for name in os.listdir(os.path.join(out, "diffs")):
        with open(os.path.join(out, "diffs", name), errors="replace") as fh:
            diffs[name[:-5]] = fh.read()
    with open(os.path.join(out, "state.json")) as fh:
        state = json.load(fh)
    with open(os.path.join(os.path.dirname(HERE), "docs", "assets", "morphameleon-logo.png"), "rb") as fh:
        logo = "data:image/png;base64," + base64.b64encode(fh.read()).decode()
    # "<" is escaped so nothing in a diff can close the script tag.
    snapshot = json.dumps({"state": state, "project": info, "diffs": diffs, "logo": logo}).replace("<", "\\u003c")
with open(os.path.join(HERE, "index.html")) as fh:
    script = "<head>\n<script>window.MORPHAMELEON_SNAPSHOT = %s; document.documentElement.classList.add(\"snapshot\");</script>" % snapshot
    page = fh.read().replace("<head>", script, 1)
with open(os.path.join(out, "index.html"), "w") as fh:
    fh.write(page)
with open(os.path.join(out, "project.json"), "w") as fh:
    json.dump(info, fh)
print("wrote %s in the app's dashboard design" % out)
