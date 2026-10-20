"""Compile the official ICNS artwork into the main bundle's app icon catalog."""

import json
import plistlib
import shutil
import subprocess
import sys
import tempfile
from pathlib import Path


def package_icon(app: Path, source: Path) -> None:
    resources = app / "Contents/Resources"
    info_path = app / "Contents/Info.plist"
    info = plistlib.loads(info_path.read_bytes())
    resources.mkdir(parents=True, exist_ok=True)
    # Preserve the original upstream asset; actool produces a separate fallback.
    shutil.copy2(source, resources / source.name)
    with tempfile.TemporaryDirectory(prefix="tempo-app-icon-") as temporary:
        root = Path(temporary)
        iconset = root / "Amplifier.iconset"
        subprocess.run(
            ["iconutil", "--convert", "iconset", "--output", str(iconset), str(source)],
            check=True,
        )
        catalog = root / "Assets.xcassets"
        appicon = catalog / "AppIcon.appiconset"
        appicon.mkdir(parents=True)
        images = []
        for size in (16, 32, 128, 256, 512):
            for scale in (1, 2):
                filename = f"icon_{size}x{size}{'@2x' if scale == 2 else ''}.png"
                shutil.copy2(iconset / filename, appicon / filename)
                images.append({
                    "idiom": "mac", "size": f"{size}x{size}",
                    "scale": f"{scale}x", "filename": filename,
                })
        (appicon / "Contents.json").write_text(json.dumps({
            "images": images, "info": {"version": 1, "author": "xcode"},
        }))
        partial = root / "asset-info.plist"
        subprocess.run([
            "xcrun", "actool", str(catalog), "--compile", str(resources),
            "--platform", "macosx", "--minimum-deployment-target",
            info["LSMinimumSystemVersion"], "--app-icon", "AppIcon",
            "--output-partial-info-plist", str(partial),
        ], check=True)
        compiled = plistlib.loads(partial.read_bytes())
        if compiled.get("CFBundleIconName") != "AppIcon":
            raise RuntimeError("Asset compiler did not declare the application icon")
        fallback = compiled["CFBundleIconFile"]
        if not fallback.endswith(".icns"):
            fallback += ".icns"
        for resource in ("Assets.car", fallback):
            if not (resources / resource).is_file() or (resources / resource).stat().st_size == 0:
                raise RuntimeError(f"Missing compiled application icon resource: {resource}")
        info.update(compiled)
        info_path.write_bytes(plistlib.dumps(info))


if __name__ == "__main__":
    package_icon(Path(sys.argv[1]).resolve(), Path(sys.argv[2]).resolve())
