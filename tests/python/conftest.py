import sys
from pathlib import Path

# Make "import loader" work when pytest is run from the repository root.
sys.path.insert(0, str(Path(__file__).resolve().parents[2]))
