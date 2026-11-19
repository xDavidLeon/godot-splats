#!/usr/bin/env python3
"""Assembles a throwaway Godot project for developing and checking the splat addon.

This repository's root is the addon itself: a game mounts it at addons/splats. So it cannot hold a
project.godot (Godot skips any folder that has one, which would hide the addon from the game), and
this dev/ folder is hidden from Godot by its .gdignore. To run the demo, the tests or the tools,
copy what they need into a project of its own, outside the repository:

    python dev/make_project.py <new folder> [--overlay] [--renderer gl_compatibility|forward_plus|mobile]
                               [--samples <file or folder> ...]

What lands where in the new project:

    addons/splats/      the addon (this repository's root, without dev/ and tools/)
    splats/demo/        dev/demo
    splats/samples/     dev/samples, and anything given with --samples
    splats/reference/   dev/reference
    splats/tools/       dev/tools
    splats/comparisons/ empty: the capture tools write here
    tests/              dev/tests

Then, with a Godot 4.7 binary (the standard build is enough; exporting needs its export templates):

    godot --path <folder> --headless --import                       once; it may end with an error after importing
    godot --path <folder> --headless -s res://tests/test_runner.gd  every dev/tests/test_*.gd
    godot --path <folder>                                           the demo, or the overlay with --overlay
    godot --path <folder> -s res://splats/tools/splat_report.gd     captures beside ink-studio's renders; needs a window
    godot --path <folder> -s res://splats/tools/splat_light_report.gd   lamps, dusk and floor shadows in a room; needs a
                                                                    window, and a room's assets given with --samples

--overlay makes the project for the transparent click-through window: its main scene is the overlay
and it has the two project settings that window needs, which are read at start-up. Run it with
"-- --selftest=<folder for captures>" to have it check itself, "--click=outline" or "--click=pixel"
to choose how the mouse is caught, and "--real-input" for real mouse input (Windows only). It comes
with export presets for Windows and macOS:

    godot --path <folder> --headless --export-release "Windows Desktop" build/splat-overlay.exe

An exported macOS app ignores --rendering-method and --rendering-driver: it always runs the
project's own. Make one project per renderer with --renderer, and for another driver add a line
under [rendering] in its project.godot, such as rendering_device/driver.macos="vulkan" or
gl_compatibility/driver.macos="opengl3_angle". On Windows the exported build does take both options.

The copy is one way. A change made in the assembled project has to be carried back by hand, and so
do captures worth keeping (into dev/comparisons).
"""
import argparse
import pathlib
import shutil

DEMO_PROJECT = """config_version=5

[application]

config/name="Splat Demo"
run/main_scene="res://splats/demo/splat_demo.tscn"
config/features=PackedStringArray("4.7")

[display]

window/size/viewport_width=1920
window/size/viewport_height=1080
window/stretch/mode="viewport"
window/stretch/scale_mode="integer"

[rendering]

renderer/rendering_method="{renderer}"
textures/vram_compression/import_etc2_astc=true
"""

OVERLAY_PROJECT = """config_version=5

[application]

config/name="Splat Overlay"
run/main_scene="res://splats/demo/splat_overlay.tscn"
config/features=PackedStringArray("4.7")

[display]

window/size/viewport_width=480
window/size/viewport_height=480
window/size/borderless=true
window/size/always_on_top=true
window/size/transparent=true
window/per_pixel_transparency/allowed=true

[rendering]

renderer/rendering_method="{renderer}"
textures/vram_compression/import_etc2_astc=true
"""

# Without import_etc2_astc above, a macOS export for arm64 or universal is refused.
# Vulkan adds grey to a transparent window's clear pixels on Windows (seen on NVIDIA): the overlay uses Direct3D 12 there.
WINDOWS_DRIVER = 'rendering_device/driver.windows="d3d12"\n'

PRESETS = """[preset.0]

name="Windows Desktop"
platform="Windows Desktop"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.bytes"
exclude_filter=""
export_path="build/{name}.exe"
script_export_mode=2

[preset.0.options]

binary_format/embed_pck=false
binary_format/architecture="x86_64"

[preset.1]

name="macOS"
platform="macOS"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.bytes"
exclude_filter=""
export_path="build/{name}.zip"
script_export_mode=2

[preset.1.options]

binary_format/architecture="universal"
application/bundle_identifier="com.example.{bundle}"
codesign/codesign=1

[preset.2]

name="Web"
platform="Web"
runnable=true
dedicated_server=false
custom_features=""
export_filter="all_resources"
include_filter="*.bytes"
exclude_filter=""
export_path="build/web/index.html"
script_export_mode=2

[preset.2.options]

variant/extensions_support=false
variant/thread_support=false
"""

# From dev/ into the project.
COPIES = {
    "demo": "splats/demo",
    "samples": "splats/samples",
    "reference": "splats/reference",
    "tools": "splats/tools",
    "tests": "tests",
}
# Of the repository's root, what is not the addon as a game sees it.
NOT_THE_ADDON = shutil.ignore_patterns(".git", ".gitignore", ".gitattributes", "dev", "tools", ".splat-diffs")


def main() -> None:
    parser = argparse.ArgumentParser(description="Assemble a throwaway Godot project for the splat addon's demo, tests and tools.")
    parser.add_argument("folder", type=pathlib.Path, help="the folder to create; it must not exist or must be empty")
    parser.add_argument("--overlay", action="store_true", help="the transparent click-through window, with the project settings it needs")
    parser.add_argument("--renderer", default="gl_compatibility", choices=["gl_compatibility", "forward_plus", "mobile"])
    parser.add_argument("--samples", nargs="*", default=[], type=pathlib.Path, metavar="PATH",
                        help="more .bytes files, or folders of them, to put in splats/samples (for a new test)")
    arguments = parser.parse_args()

    dev = pathlib.Path(__file__).resolve().parent
    folder: pathlib.Path = arguments.folder.resolve()
    if dev.parent in folder.parents or folder == dev.parent:
        raise SystemExit(f"{folder} is inside the addon's repository; give a folder outside it.")
    if folder.exists() and any(folder.iterdir()):
        raise SystemExit(f"{folder} is not empty; give a new folder.")
    folder.mkdir(parents=True, exist_ok=True)

    shutil.copytree(dev.parent, folder / "addons" / "splats", ignore=NOT_THE_ADDON)
    for source, target in COPIES.items():
        shutil.copytree(dev / source, folder / target)
    for extra in arguments.samples:
        if extra.is_dir():
            for file in sorted(extra.glob("*.bytes")):
                shutil.copy2(file, folder / "splats" / "samples" / file.name)
        elif extra.is_file():
            shutil.copy2(extra, folder / "splats" / "samples" / extra.name)
        else:
            raise SystemExit(f"--samples: nothing at {extra}")
    (folder / "splats" / "comparisons").mkdir()
    (folder / "build").mkdir()

    text = (OVERLAY_PROJECT if arguments.overlay else DEMO_PROJECT).format(renderer=arguments.renderer)
    if arguments.overlay and arguments.renderer != "gl_compatibility":
        text += WINDOWS_DRIVER
    name = "splat-overlay" if arguments.overlay else "splat-demo"
    presets = PRESETS.format(name=name, bundle=name.replace("-", ""))
    # open(), not Path.write_text(newline=...): that argument needs Python 3.10, and macOS ships 3.9
    for file_name, content in (("project.godot", text), ("export_presets.cfg", presets)):
        with open(folder / file_name, "w", encoding="utf-8", newline="\n") as file:
            file.write(content)
    what = "the overlay" if arguments.overlay else "the demo"
    print(f"Made {folder}: {what}, {arguments.renderer}. Next: godot --path {folder} --headless --import")


if __name__ == "__main__":
    main()
