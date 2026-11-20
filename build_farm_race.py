from pathlib import Path
from zipfile import ZIP_DEFLATED, ZipFile

from build_panorama import build_panorama


root = Path(__file__).resolve().parent
source = root / "game" / "dota_addons" / "am_farm_race"
build_panorama()
with ZipFile(root / "Anti-Mage Farm Race.zip", "w", ZIP_DEFLATED) as bundle:
    for name in ("Launch Farm Race.cmd", "Host Farm Race.cmd", "Join Farm Race.cmd", "README.md"):
        bundle.write(root / name, name)
    for path in sorted(source.rglob("*")):
        if path.is_file():
            bundle.write(path, path.relative_to(root))
