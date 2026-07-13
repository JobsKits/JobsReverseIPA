# -*- mode: python ; coding: utf-8 -*-
import sys
from pathlib import Path


project_root = Path(SPECPATH).resolve()
app_name = "IPA Reverse Analysis Tool"
datas = [
    (str(project_root / "icon.png"), "."),
    (str(project_root / "rules"), "rules"),
    (str(project_root / "templates"), "templates"),
    (str(project_root / "tools"), "tools"),
]
if sys.platform == "darwin":
    datas.append((str(project_root / "doctor" / "macos"), "doctor/macos"))

analysis = Analysis(
    [str(project_root / "ipa_reverse_tool" / "gui_main.py")],
    pathex=[str(project_root)],
    binaries=[],
    datas=datas,
    hiddenimports=["PySide6.QtCore", "PySide6.QtGui", "PySide6.QtWidgets"],
    hookspath=[],
    hooksconfig={},
    runtime_hooks=[],
    excludes=[],
    noarchive=False,
    optimize=0,
)
pyz = PYZ(analysis.pure)
exe = EXE(
    pyz,
    analysis.scripts,
    [],
    exclude_binaries=True,
    name=app_name,
    debug=False,
    bootloader_ignore_signals=False,
    strip=False,
    upx=False,
    console=False,
    disable_windowed_traceback=False,
    argv_emulation=False,
    target_arch=None,
    codesign_identity=None,
    entitlements_file=None,
)
collection = COLLECT(
    exe,
    analysis.binaries,
    analysis.datas,
    strip=False,
    upx=False,
    upx_exclude=[],
    name=app_name,
)
if sys.platform == "darwin":
    app = BUNDLE(
        collection,
        name=f"{app_name}.app",
        icon=None,
        bundle_identifier="com.jobs.ipareversetool",
        info_plist={
            "CFBundleDisplayName": app_name,
            "CFBundleName": app_name,
            "CFBundleShortVersionString": "0.2.0",
            "CFBundleVersion": "2",
            "LSMinimumSystemVersion": "12.0",
            "NSHighResolutionCapable": True,
            "CFBundleDocumentTypes": [
                {
                    "CFBundleTypeName": "iOS IPA Archive",
                    "CFBundleTypeRole": "Viewer",
                    "LSHandlerRank": "Owner",
                    "CFBundleTypeExtensions": ["ipa"],
                }
            ],
        },
    )
