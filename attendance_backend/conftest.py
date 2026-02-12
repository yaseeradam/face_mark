import sys
from pathlib import Path


# When running via the `pytest` entrypoint on Windows, the working directory is
# not always added to `sys.path`, which breaks imports like `from app...`.
PROJECT_ROOT = Path(__file__).resolve().parent
if str(PROJECT_ROOT) not in sys.path:
    sys.path.insert(0, str(PROJECT_ROOT))

