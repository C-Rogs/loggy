#!/usr/bin/env python3
"""Inject LoggyWatch target into project.pbxproj (single-run helper)."""
from pathlib import Path

p = Path("/Users/cameronro/Development/loggy/Loggy.xcodeproj/project.pbxproj")
text = p.read_text()

INSERT_BF = """		AAAA111122223333444455505 /* WatchActiveWorkoutSnapshot.swift in Sources */ = {isa = PBXBuildFile; fileRef = AAAA111122223333444455502 /* WatchActiveWorkoutSnapshot.swift */; };
		AAAA111122223333444455507 /* LiveActivityElapsedLogic.swift in Sources */ = {isa = PBXBuildFile; fileRef = AABBCCDD1122334455667701 /* LiveActivityElapsedLogic.swift */; };
		AAAA111122223333444455509 /* ISO8601.swift in Sources */ = {isa = PBXBuildFile; fileRef = 471D0D097F260C8F438FC7F2 /* ISO8601.swift */; };
		WWWW111122223333444455511 /* LoggyWatchApp.swift in Sources */ = {isa = PBXBuildFile; fileRef = WWWW111122223333444455501 /* LoggyWatchApp.swift */; };
		WWWW111122223333444455512 /* ContentView.swift in Sources */ = {isa = PBXBuildFile; fileRef = WWWW111122223333444455502 /* ContentView.swift */; };
		WWWW111122223333444455513 /* WatchSessionCoordinator.swift in Sources */ = {isa = PBXBuildFile; fileRef = WWWW111122223333444455503 /* WatchSessionCoordinator.swift */; };
		WWWW111122223333444455514 /* WatchHealthWorkoutSessionController.swift in Sources */ = {isa = PBXBuildFile; fileRef = WWWW111122223333444455504 /* WatchHealthWorkoutSessionController.swift */; };
		F10000000000000000000020 /* LoggyWatch.app in Embed Watch Content */ = {isa = PBXBuildFile; fileRef = F10000000000000000000002 /* LoggyWatch.app */; settings = {ATTRIBUTES = (RemoveHeadersOnCopy, ); }; };
"""

if "WWWW111122223333444455511" not in text:
    text = text.replace(
        "/* End PBXBuildFile section */",
        INSERT_BF + "\n/* End PBXBuildFile section */",
        1,
    )

INSERT_FR = """		WWWW111122223333444455501 /* LoggyWatchApp.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = LoggyWatchApp.swift; sourceTree = "<group>"; };
		WWWW111122223333444455502 /* ContentView.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = ContentView.swift; sourceTree = "<group>"; };
		WWWW111122223333444455503 /* WatchSessionCoordinator.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchSessionCoordinator.swift; sourceTree = "<group>"; };
		WWWW111122223333444455504 /* WatchHealthWorkoutSessionController.swift */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = WatchHealthWorkoutSessionController.swift; sourceTree = "<group>"; };
		WWWW111122223333444455505 /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };
		WWWW111122223333444455506 /* LoggyWatch.entitlements */ = {isa = PBXFileReference; lastKnownFileType = text.plist.entitlements; path = LoggyWatch.entitlements; sourceTree = "<group>"; };
		F10000000000000000000002 /* LoggyWatch.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = LoggyWatch.app; sourceTree = BUILT_PRODUCTS_DIR; };
"""

if "WWWW111122223333444455501" not in text:
    text = text.replace(
        "/* End PBXFileReference section */",
        INSERT_FR + "\n/* End PBXFileReference section */",
        1,
    )

GROUP_WATCH = """		F10000000000000000000010 /* LoggyWatch */ = {
			isa = PBXGroup;
			children = (
				WWWW111122223333444455501 /* LoggyWatchApp.swift */,
				WWWW111122223333444455502 /* ContentView.swift */,
				WWWW111122223333444455503 /* WatchSessionCoordinator.swift */,
				WWWW111122223333444455504 /* WatchHealthWorkoutSessionController.swift */,
				WWWW111122223333444455505 /* Info.plist */,
				WWWW111122223333444455506 /* LoggyWatch.entitlements */,
			);
			path = LoggyWatch;
			sourceTree = "<group>";
		};
"""

if "F10000000000000000000010" not in text:
    text = text.replace(
        "\t\tD0C1B2A39485726152433445 /* Docs */,\n",
        "\t\tF10000000000000000000010 /* LoggyWatch */,\n\t\tD0C1B2A39485726152433445 /* Docs */,\n",
        1,
    )
    text = text.replace(
        "/* Begin PBXGroup section */",
        "/* Begin PBXGroup section */\n" + GROUP_WATCH,
        1,
    )

# Products
if "F10000000000000000000002 /* LoggyWatch.app */" not in text.split("name = Products")[0]:
    pass
text = text.replace(
    "\t\t\t\t67D851DBB71794F994A97AA7 /* Loggy.app */,\n",
    "\t\t\t\t67D851DBB71794F994A97AA7 /* Loggy.app */,\n\t\t\t\tF10000000000000000000002 /* LoggyWatch.app */,\n",
    1,
)

# Copy embed phase
EMBED = """		F10000000000000000000004 /* Embed Watch Content */ = {
			isa = PBXCopyFilesBuildPhase;
			buildActionMask = 2147483647;
			dstPath = "";
			dstSubfolderSpec = 16;
			files = (
				F10000000000000000000020 /* LoggyWatch.app in Embed Watch Content */,
			);
			name = "Embed Watch Content";
			runOnlyForDeploymentPostprocessing = 0;
		};
"""

if "F10000000000000000000004" not in text:
    text = text.replace(
        "/* End PBXCopyFilesBuildPhase section */",
        EMBED + "\n/* End PBXCopyFilesBuildPhase section */",
        1,
    )

# Container proxy + dependency
PROXY = """		F10000000000000000000006 /* PBXContainerItemProxy */ = {
			isa = PBXContainerItemProxy;
			containerPortal = EE3FD26F09A89239977B4153 /* Project object */;
			proxyType = 1;
			remoteGlobalIDString = F10000000000000000000001;
			remoteInfo = LoggyWatch;
		};
"""

DEP = """		F10000000000000000000005 /* PBXTargetDependency */ = {
			isa = PBXTargetDependency;
			target = F10000000000000000000001 /* LoggyWatch */;
			targetProxy = F10000000000000000000006 /* PBXContainerItemProxy */;
		};
"""

if "F10000000000000000000006" not in text:
    text = text.replace(
        "/* End PBXContainerItemProxy section */",
        PROXY + "\n/* End PBXContainerItemProxy section */",
        1,
    )
    text = text.replace(
        "/* End PBXTargetDependency section */",
        DEP + "\n/* End PBXTargetDependency section */",
        1,
    )

# Loggy target: add embed phase + dependency
text = text.replace(
    "\t\t\tdependencies = (\n\t\t\t\tBEA6D7529A9965714635F317 /* PBXTargetDependency */,\n\t\t\t);",
    "\t\t\tdependencies = (\n\t\t\t\tBEA6D7529A9965714635F317 /* PBXTargetDependency */,\n\t\t\t\tF10000000000000000000005 /* PBXTargetDependency */,\n\t\t\t);",
    1,
)
text = text.replace(
    "\t\t\tbuildPhases = (\n\t\t\t\t7E1A2A6CC7B952D926AAA83D /* Sources */,\n\t\t\t\t3AF7A5B58120CF4912FB7185 /* Frameworks */,\n\t\t\t\tB4A392817465534241302918 /* Resources */,\n\t\t\t\t4DD2D6FD20E8033DE91D0DEE /* Embed Foundation Extensions */,\n\t\t\t);",
    "\t\t\tbuildPhases = (\n\t\t\t\t7E1A2A6CC7B952D926AAA83D /* Sources */,\n\t\t\t\t3AF7A5B58120CF4912FB7185 /* Frameworks */,\n\t\t\t\tB4A392817465534241302918 /* Resources */,\n\t\t\t\t4DD2D6FD20E8033DE91D0DEE /* Embed Foundation Extensions */,\n\t\t\t\tF10000000000000000000004 /* Embed Watch Content */,\n\t\t\t);",
    1,
)

SOURCES_WATCH = """		F10000000000000000000007 /* Sources */ = {
			isa = PBXSourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
				WWWW111122223333444455511 /* LoggyWatchApp.swift in Sources */,
				WWWW111122223333444455512 /* ContentView.swift in Sources */,
				WWWW111122223333444455513 /* WatchSessionCoordinator.swift in Sources */,
				WWWW111122223333444455514 /* WatchHealthWorkoutSessionController.swift in Sources */,
				AAAA111122223333444455505 /* WatchActiveWorkoutSnapshot.swift in Sources */,
				AAAA111122223333444455507 /* LiveActivityElapsedLogic.swift in Sources */,
				AAAA111122223333444455509 /* ISO8601.swift in Sources */,
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		F10000000000000000000008 /* Frameworks */ = {
			isa = PBXFrameworksBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
		F10000000000000000000009 /* Resources */ = {
			isa = PBXResourcesBuildPhase;
			buildActionMask = 2147483647;
			files = (
			);
			runOnlyForDeploymentPostprocessing = 0;
		};
"""

TARGET_WATCH = """		F10000000000000000000001 /* LoggyWatch */ = {
			isa = PBXNativeTarget;
			buildConfigurationList = F10000000000000000000031 /* Build configuration list for PBXNativeTarget "LoggyWatch" */;
			buildPhases = (
				F10000000000000000000007 /* Sources */,
				F10000000000000000000008 /* Frameworks */,
				F10000000000000000000009 /* Resources */,
			);
			buildRules = (
			);
			dependencies = (
			);
			name = LoggyWatch;
			packageProductDependencies = (
			);
			productName = LoggyWatch;
			productReference = F10000000000000000000002 /* LoggyWatch.app */;
			productType = "com.apple.product-type.application";
		};
"""

if "F10000000000000000000001 /* LoggyWatch */" not in text:
    text = text.replace(
        "/* Begin PBXSourcesBuildPhase section */",
        "/* Begin PBXSourcesBuildPhase section */\n" + SOURCES_WATCH,
        1,
    )
    text = text.replace(
        "/* End PBXNativeTarget section */",
        TARGET_WATCH + "\n/* End PBXNativeTarget section */",
        1,
    )

text = text.replace(
    "\t\t\ttargets = (\n\t\t\t\tB9E8FB43846CD04426F2AC27 /* Loggy */,\n\t\t\t\t8071162F1BA1F2439A83BB40 /* LoggyLiveActivity */,\n\t\t\t\tA1F0E1D2C3B4A59697868690C /* LoggyTests */,\n\t\t\t);",
    "\t\t\ttargets = (\n\t\t\t\tB9E8FB43846CD04426F2AC27 /* Loggy */,\n\t\t\t\t8071162F1BA1F2439A83BB40 /* LoggyLiveActivity */,\n\t\t\t\tA1F0E1D2C3B4A59697868690C /* LoggyTests */,\n\t\t\t\tF10000000000000000000001 /* LoggyWatch */,\n\t\t\t);",
    1,
)

CFG_DBG = """		F10000000000000000000041 /* Debug */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = LoggyWatch/LoggyWatch.entitlements;
				CODE_SIGN_IDENTITY = "iPhone Developer";
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = SXWJBD2V3V;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = LoggyWatch/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.loggy.app.watch;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SWIFT_VERSION = 5.10;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;
			};
			name = Debug;
		};
		F10000000000000000000042 /* Release */ = {
			isa = XCBuildConfiguration;
			buildSettings = {
				ASSETCATALOG_COMPILER_APPICON_NAME = AppIcon;
				CODE_SIGN_ENTITLEMENTS = LoggyWatch/LoggyWatch.entitlements;
				CODE_SIGN_IDENTITY = "iPhone Developer";
				CURRENT_PROJECT_VERSION = 1;
				DEVELOPMENT_TEAM = SXWJBD2V3V;
				GENERATE_INFOPLIST_FILE = NO;
				INFOPLIST_FILE = LoggyWatch/Info.plist;
				LD_RUNPATH_SEARCH_PATHS = (
					"$(inherited)",
					"@executable_path/Frameworks",
				);
				MARKETING_VERSION = 1.0;
				PRODUCT_BUNDLE_IDENTIFIER = com.loggy.app.watch;
				PRODUCT_NAME = "$(TARGET_NAME)";
				SDKROOT = watchos;
				SKIP_INSTALL = YES;
				SWIFT_VERSION = 5.10;
				TARGETED_DEVICE_FAMILY = 4;
				WATCHOS_DEPLOYMENT_TARGET = 10.0;
			};
			name = Release;
		};
"""

CFG_LIST = """		F10000000000000000000031 /* Build configuration list for PBXNativeTarget "LoggyWatch" */ = {
			isa = XCConfigurationList;
			buildConfigurations = (
				F10000000000000000000041 /* Debug */,
				F10000000000000000000042 /* Release */,
			);
			defaultConfigurationIsVisible = 0;
			defaultConfigurationName = Debug;
		};
"""

if "F10000000000000000000041" not in text:
    text = text.replace(
        "/* End XCBuildConfiguration section */",
        CFG_DBG + CFG_LIST + "\n/* End XCBuildConfiguration section */",
        1,
    )

p.write_text(text)
print("patched", p)
