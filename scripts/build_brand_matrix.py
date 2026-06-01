#!/usr/bin/env python3
"""Build every branded app scheme sequentially."""

from __future__ import annotations

import argparse
import subprocess
import sys
from typing import List

from brand_support import PACKAGE_DIR, PROJECT_PATH, ROOT, load_brand_configs, run


def build_parser() -> argparse.ArgumentParser:
    parser = argparse.ArgumentParser(description="Validate and build the branded app matrix.")
    parser.add_argument(
        "--configuration",
        default="Debug",
        choices=["Debug", "Release"],
        help="Xcode configuration to build.",
    )
    parser.add_argument(
        "--destination",
        default="generic/platform=iOS Simulator",
        help="xcodebuild destination.",
    )
    parser.add_argument(
        "--scheme",
        action="append",
        dest="schemes",
        help="Build only this scheme. Can be passed more than once.",
    )
    parser.add_argument(
        "--skip-swift-build",
        action="store_true",
        help="Skip the standalone JueceoCore package build.",
    )
    parser.add_argument(
        "--skip-validation",
        action="store_true",
        help="Skip scripts/validate_brands.py.",
    )
    parser.add_argument(
        "--verbose",
        action="store_true",
        help="Show full xcodebuild output instead of -quiet.",
    )
    return parser


def main() -> int:
    args = build_parser().parse_args()
    schemes: List[str] = args.schemes or [config.scheme for config in load_brand_configs()]

    try:
        if not args.skip_validation:
            run([sys.executable, "scripts/validate_brands.py"])

        if not args.skip_swift_build:
            run(["swift", "build"], cwd=PACKAGE_DIR)

        run(["xcodebuild", "-list", "-project", str(PROJECT_PATH)])

        for scheme in schemes:
            command = [
                "xcodebuild",
                "-project",
                str(PROJECT_PATH),
                "-scheme",
                scheme,
                "-destination",
                args.destination,
                "-configuration",
                args.configuration,
                "CODE_SIGNING_ALLOWED=NO",
                "build",
            ]
            if not args.verbose:
                command.insert(1, "-quiet")
            run(command)
    except subprocess.CalledProcessError as exc:
        return exc.returncode

    print("Brand build matrix OK.")
    return 0


if __name__ == "__main__":
    sys.exit(main())
