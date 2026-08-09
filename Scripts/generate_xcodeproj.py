#!/usr/bin/env python3
"""Generate ScreenTidy.xcodeproj/project.pbxproj for the Sprint 0 foundation.

WARNING: Regenerating wipes SPM package refs (GRDB), test targets, and custom
INFOPLIST keys. Prefer editing project.pbxproj in place. If you must regenerate,
re-add GRDB (`https://github.com/groue/GRDB.swift.git`, upToNextMajor 7.0.0),
ScreenTidyTests, NSPhotoLibraryUsageDescription, UIUserInterfaceStyle=Light,
and DEVELOPMENT_TEAM afterward.
"""

from __future__ import annotations

import os
import uuid
from pathlib import Path

ROOT = Path(__file__).resolve().parents[1]
SOURCE_ROOT = ROOT / "ScreenTidy"
PROJECT_DIR = ROOT / "ScreenTidy.xcodeproj"

# Stable-looking 24-char hex IDs
def uid(name: str) -> str:
    return uuid.uuid5(uuid.NAMESPACE_URL, f"screentidy:{name}").hex[:24].upper()


def collect_swift_files() -> list[Path]:
    files = sorted(SOURCE_ROOT.rglob("*.swift"))
    return files


def main() -> None:
    swift_files = collect_swift_files()
    asset_path = SOURCE_ROOT / "Assets.xcassets"

    project_id = uid("project")
    target_id = uid("target")
    sources_phase = uid("sources")
    resources_phase = uid("resources")
    frameworks_phase = uid("frameworks")
    product_ref = uid("product")
    app_group = uid("group-app")
    products_group = uid("group-products")
    main_group = uid("group-main")
    sources_config_debug = uid("config-debug")
    sources_config_release = uid("config-release")
    project_config_debug = uid("proj-debug")
    project_config_release = uid("proj-release")
    project_config_list = uid("proj-configs")
    target_config_list = uid("target-configs")

    file_refs: dict[Path, str] = {}
    build_files: dict[Path, str] = {}

    for path in swift_files:
        rel = path.relative_to(ROOT)
        file_refs[path] = uid(f"ref:{rel}")
        build_files[path] = uid(f"build:{rel}")

    asset_ref = uid("ref:assets")
    asset_build = uid("build:assets")

    # Build nested groups by directory
    # Flat group listing all files is simpler and valid.
    file_ref_entries = []
    for path in swift_files:
        rel = path.relative_to(SOURCE_ROOT)
        file_ref_entries.append(
            f'\t\t{file_refs[path]} /* {path.name} */ = {{isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = "{rel.as_posix()}"; sourceTree = "<group>"; }};'
        )
    file_ref_entries.append(
        f'\t\t{asset_ref} /* Assets.xcassets */ = {{isa = PBXFileReference; lastKnownFileType = folder.assetcatalog; path = Assets.xcassets; sourceTree = "<group>"; }};'
    )
    file_ref_entries.append(
        f'\t\t{product_ref} /* ScreenTidy.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = ScreenTidy.app; sourceTree = BUILT_PRODUCTS_DIR; }};'
    )

    build_file_entries = []
    for path in swift_files:
        build_file_entries.append(
            f'\t\t{build_files[path]} /* {path.name} in Sources */ = {{isa = PBXBuildFile; fileRef = {file_refs[path]} /* {path.name} */; }};'
        )
    build_file_entries.append(
        f'\t\t{asset_build} /* Assets.xcassets in Resources */ = {{isa = PBXBuildFile; fileRef = {asset_ref} /* Assets.xcassets */; }};'
    )

    # Group children: use folder-relative paths from ScreenTidy/
    # Put all swift files in ScreenTidy group with path = ScreenTidy and children using relative paths
    # For nested paths, Xcode needs subgroup OR path includes subdirs in file ref.

    # File refs already use path relative to SOURCE_ROOT with sourceTree group.
    # Parent group path = ScreenTidy.

    children_ids = [file_refs[p] for p in swift_files] + [asset_ref]
    children_list = "\n".join(
        f'\t\t\t\t{file_refs[p]} /* {p.name} */,' for p in swift_files
    )
    children_list += f"\n\t\t\t\t{asset_ref} /* Assets.xcassets */,"

    sources_list = "\n".join(
        f'\t\t\t\t{build_files[p]} /* {p.name} in Sources */,' for p in swift_files
    )

    pbx = f"""// !$*UTF8*$!
{{
	archiveVersion = 1;
	classes = {{
	}};
	objectVersion = 56;
	objects = {{

/* Begin PBXBuildFile section */
{chr(10).join(build_file_entries)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{chr(10).join(file_ref_entries)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
		{frameworks_phase} /* Frameworks */ = {{
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
		{main_group} = {{
			isa = PBXGroup;
			children = (
				{app_group} /* ScreenTidy */,
				{products_group} /* Products */,
			);
			sourceTree = "<group>";
		}};
		{app_group} /* ScreenTidy */ = {{
			isa = PBXGroup;
			children = (
{children_list}
			);
			path = ScreenTidy;
			sourceTree = "<group>";
		}};
		{products_group} /* Products */ = {{
			isa = PBXGroup;
			children = (
				{product_ref} /* ScreenTidy.app */,
			);
			name = Products;
			sourceTree = "<group>";
		}};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
		{target_id} /* ScreenTidy */ = {{
			isa = PBXNativeTarget;
			buildConfigurationList = {target_config_list} /* Build configuration list for PBXNativeTarget "ScreenTidy" */;
			buildPhases = (
				{sources_phase} /* Sources */,
				{frameworks_phase} /* Frameworks */,
				{resources_phase} /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = ScreenTidy;
			productName = ScreenTidy;
			productReference = {product_ref} /* ScreenTidy.app */;
			productType = "com.apple.product-type.application";
		}};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
		{project_id} /* Project object */ = {{
			isa = PBXProject;
			attributes = {{
				BuildIndependentTargetsInParallel = 1;
				LastSwiftUpdateCheck = 1600;
				LastUpgradeCheck = 1600;
				TargetAttributes = {{
					{target_id} = {{
						CreatedOnToolsVersion = 16.0;
					}};
				}};
			}};
			buildConfigurationList = {project_config_list} /* Build configuration list for PBXProject "ScreenTidy" */;
			compatibilityVersion = "Xcode 14.0";
			developmentRegion = en;
			hasScannedForEncodings = 0;
			knownRegions = (
				en,
				Base,
			);
			mainGroup = {main_group};
			productRefGroup = {products_group} /* Products */;
			projectDirPath = "";
			projectRoot = "";
			targets = (
				{target_id} /* ScreenTidy */,
			);
		}};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
		{resources_phase} /* Resources */ = {{
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				{asset_build} /* Assets.xcassets in Resources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
		{sources_phase} /* Sources */ = {{
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
{sources_list}
			);
			runOnlyForDeploymentPostprocessing = 0;
		}};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
		{project_config_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = dwarf;
				ENABLE_TESTABILITY = YES;
				GCC_DYNAMIC_NO_PIC = NO;
				GCC_OPTIMIZATION_LEVEL = 0;
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				ONLY_ACTIVE_ARCH = YES;
				SDKROOT = iphoneos;
				SWIFT_ACTIVE_COMPILATION_CONDITIONS = "DEBUG $(inherited)";
				SWIFT_OPTIMIZATION_LEVEL = "-Onone";
				SWIFT_VERSION = 5.0;
			}};
			name = Debug;
		}};
		{project_config_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ALWAYS_SEARCH_USER_PATHS = NO;
				CLANG_ENABLE_MODULES = YES;
				CLANG_ENABLE_OBJC_ARC = YES;
				COPY_PHASE_STRIP = NO;
				DEBUG_INFORMATION_FORMAT = "dwarf-with-dsym";
				IPHONEOS_DEPLOYMENT_TARGET = 17.0;
				SDKROOT = iphoneos;
				SWIFT_COMPILATION_MODE = wholemodule;
				SWIFT_VERSION = 5.0;
				VALIDATE_PRODUCT = YES;
			}};
			name = Release;
		}};
		{sources_config_debug} /* Debug */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = ScreenTidy;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.screentidy.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
			}};
			name = Debug;
		}};
		{sources_config_release} /* Release */ = {{
			isa = XCBuildConfiguration;
			buildSettings = {{
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				ASSETCATALOG_COMPILER_GLOBAL_ACCENT_COLOR_NAME = AccentColor;
				CODE_SIGN_STYLE = Automatic;
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = "";
				ENABLE_PREVIEWS = YES;
				GENERATE_INFOPLIST_FILE = YES;
				INFOPLIST_KEY_CFBundleDisplayName = ScreenTidy;
				INFOPLIST_KEY_LSApplicationCategoryType = "public.app-category.productivity";
				INFOPLIST_KEY_UIApplicationSceneManifest_Generation = YES;
				INFOPLIST_KEY_UILaunchScreen_Generation = YES;
				INFOPLIST_KEY_UISupportedInterfaceOrientations = UIInterfaceOrientationPortrait;
				INFOPLIST_KEY_UISupportedInterfaceOrientations_iPad = "UIInterfaceOrientationLandscapeLeft UIInterfaceOrientationLandscapeRight UIInterfaceOrientationPortrait UIInterfaceOrientationPortraitUpsideDown";
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 0.1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.screentidy.app;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SUPPORTED_PLATFORMS = "iphoneos iphonesimulator";
				SUPPORTS_MACCATALYST = NO;
				SWIFT_EMIT_LOC_STRINGS = YES;
				SWIFT_VERSION = 5.0;
				TARGETED_DEVICE_FAMILY = 1;
			}};
			name = Release;
		}};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
		{project_config_list} /* Build configuration list for PBXProject "ScreenTidy" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{project_config_debug} /* Debug */,
				{project_config_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
		{target_config_list} /* Build configuration list for PBXNativeTarget "ScreenTidy" */ = {{
			isa = XCConfigurationList;
			buildConfigurations = (
				{sources_config_debug} /* Debug */,
				{sources_config_release} /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Release;
		}};
/* End XCConfigurationList section */
	}};
	rootObject = {project_id} /* Project object */;
}}
"""

    PROJECT_DIR.mkdir(parents=True, exist_ok=True)
    (PROJECT_DIR / "project.pbxproj").write_text(pbx)
    workspace = PROJECT_DIR / "project.xcworkspace"
    workspace.mkdir(exist_ok=True)
    (workspace / "contents.xcworkspacedata").write_text(
        """<?xml version="1.0" encoding="UTF-8"?>
<Workspace
   version = "1.0">
   <FileRef
      location = "self:">
   </FileRef>
</Workspace>
"""
    )
    print(f"Generated project with {len(swift_files)} Swift files")
    for p in swift_files:
        print(f"  - {p.relative_to(ROOT)}")


if __name__ == "__main__":
    main()
