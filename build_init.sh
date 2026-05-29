#!/usr/bin/env bash
# =============================================================================
# build_init.sh — CustomPlayer Cloud Build Initialiser
# Runs on GitHub Actions macos-14 runner BEFORE xcodebuild.
# Creates a fully self-contained Xcode project from scratch using
# xcodebuild + PlistBuddy + direct .pbxproj manipulation so no Tuist
# version mismatch can ever break the build.
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="CustomPlayer"
BUNDLE_ID="com.custom.player"
SCHEME_NAME="CustomPlayer"
SOURCES_DIR="$REPO_ROOT/Sources"
RESOURCES_DIR="$REPO_ROOT/Resources"
XCODEPROJ_DIR="$REPO_ROOT/$PROJECT_NAME.xcodeproj"
PBXPROJ="$XCODEPROJ_DIR/project.pbxproj"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  build_init.sh — CustomPlayer project bootstrap"
echo "  Repo root : $REPO_ROOT"
echo "  Xcode proj: $XCODEPROJ_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Ensure directory structure ─────────────────────────────────────────────
mkdir -p "$SOURCES_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$XCODEPROJ_DIR/xcshareddata/xcschemes"

# ── 2. Guarantee App.swift entry point ───────────────────────────────────────
if [ ! -f "$SOURCES_DIR/App.swift" ]; then
  echo "[init] Creating App.swift entry point"
  cat > "$SOURCES_DIR/App.swift" << 'SWIFT'
import SwiftUI
@main
struct CustomPlayerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
SWIFT
fi

# ── 3. Create stub placeholder assets if real assets are absent ───────────────
# Real production assets (music.mp3 etc.) should be committed to Resources/.
# These stubs prevent compile-time errors if a file is missing.

create_stub_mp3() {
  python3 - "$1" << 'PYEOF'
import sys, struct, zlib
path = sys.argv[1]
# Minimal valid ID3v2.3 header (10 bytes) + one silent MPEG1 Layer3 frame
id3  = b'ID3\x03\x00\x00\x00\x00\x00\x00'
# MPEG1, Layer 3, 128kbps, 44100Hz, stereo — silent frame (417 bytes payload)
frame = b'\xff\xfb\x90\x00' + b'\x00' * 413
with open(path, 'wb') as f:
    f.write(id3 + frame)
print(f"  stub mp3 → {path}")
PYEOF
}

create_stub_ahap() {
  cat > "$1" << 'AHAP'
{
  "Version": 1.0,
  "Metadata": {
    "Project": "CustomPlayer",
    "Description": "Stub AHAP — replace with production pattern"
  },
  "Pattern": [
    {
      "Event": {
        "Time": 0.0,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity",  "ParameterValue": 0.5 },
          { "ParameterID": "HapticSharpness",  "ParameterValue": 0.5 }
        ]
      }
    },
    {
      "Event": {
        "Time": 0.5,
        "EventType": "HapticContinuous",
        "EventDuration": 0.3,
        "EventParameters": [
          { "ParameterID": "HapticIntensity",  "ParameterValue": 0.3 },
          { "ParameterID": "HapticSharpness",  "ParameterValue": 0.4 }
        ]
      }
    }
  ]
}
AHAP
}

create_stub_png() {
  python3 - "$1" << 'PYEOF'
import sys, struct, zlib
def chunk(tag, data):
    c = struct.pack(">I", len(data)) + tag + data
    return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
def png_1x1(r, g, b):
    sig  = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(bytes([0, r, g, b])))
    iend = chunk(b'IEND', b'')
    return sig + ihdr + idat + iend
path = sys.argv[1]
with open(path, 'wb') as f:
    f.write(png_1x1(80, 10, 30))
print(f"  stub png  → {path}")
PYEOF
}

[ ! -f "$RESOURCES_DIR/music.mp3"  ] && create_stub_mp3  "$RESOURCES_DIR/music.mp3"
[ ! -f "$RESOURCES_DIR/haptic.ahap"] && create_stub_ahap "$RESOURCES_DIR/haptic.ahap"
[ ! -f "$RESOURCES_DIR/cover.png"  ] && create_stub_png  "$RESOURCES_DIR/cover.png"

echo "[init] Resources:"
ls -lh "$RESOURCES_DIR/"

# ── 4. Collect Swift source files ────────────────────────────────────────────
SWIFT_FILES=()
while IFS= read -r -d $'\0' f; do
  SWIFT_FILES+=("$f")
done < <(find "$SOURCES_DIR" -name "*.swift" -print0 | sort -z)

echo "[init] Swift sources (${#SWIFT_FILES[@]} files):"
for f in "${SWIFT_FILES[@]}"; do echo "  $f"; done

# ── 5. Collect Resource files ─────────────────────────────────────────────────
RESOURCE_FILES=()
while IFS= read -r -d $'\0' f; do
  RESOURCE_FILES+=("$f")
done < <(find "$RESOURCES_DIR" -type f \( -name "*.mp3" -o -name "*.ahap" -o -name "*.mp4" -o -name "*.png" -o -name "*.jpg" \) -print0 | sort -z)

echo "[init] Resources (${#RESOURCE_FILES[@]} files):"
for f in "${RESOURCE_FILES[@]}"; do echo "  $f"; done

# ── 6. Generate UUIDs ─────────────────────────────────────────────────────────
# We need stable, unique UUIDs for every pbxproj object.
gen_uuid() {
  python3 -c "import uuid; print(uuid.uuid4().hex[:24].upper())"
}

PROJECT_UUID=$(gen_uuid)
MAIN_GROUP_UUID=$(gen_uuid)
PRODUCTS_GROUP_UUID=$(gen_uuid)
SOURCES_GROUP_UUID=$(gen_uuid)
RESOURCES_GROUP_UUID=$(gen_uuid)
TARGET_UUID=$(gen_uuid)
APP_PRODUCT_UUID=$(gen_uuid)
SOURCES_PHASE_UUID=$(gen_uuid)
RESOURCES_PHASE_UUID=$(gen_uuid)
FRAMEWORKS_PHASE_UUID=$(gen_uuid)
DEBUG_CONFIG_UUID=$(gen_uuid)
RELEASE_CONFIG_UUID=$(gen_uuid)
PROJECT_DEBUG_CONFIG_UUID=$(gen_uuid)
PROJECT_RELEASE_CONFIG_UUID=$(gen_uuid)
CONFIG_LIST_UUID=$(gen_uuid)
PROJECT_CONFIG_LIST_UUID=$(gen_uuid)
INFOPLIST_UUID=$(gen_uuid)

# Generate UUID pairs (file ref + build file) for each Swift source
declare -A SWIFT_FILE_REF_UUIDS
declare -A SWIFT_BUILD_FILE_UUIDS
for f in "${SWIFT_FILES[@]}"; do
  SWIFT_FILE_REF_UUIDS["$f"]=$(gen_uuid)
  SWIFT_BUILD_FILE_UUIDS["$f"]=$(gen_uuid)
done

# Generate UUID pairs for each resource
declare -A RES_FILE_REF_UUIDS
declare -A RES_BUILD_FILE_UUIDS
for f in "${RESOURCE_FILES[@]}"; do
  RES_FILE_REF_UUIDS["$f"]=$(gen_uuid)
  RES_BUILD_FILE_UUIDS["$f"]=$(gen_uuid)
done

# ── 7. Build the pbxproj sections ────────────────────────────────────────────

# Helper: relative path from project root
rel_path() { python3 -c "import os; print(os.path.relpath('$1', '$REPO_ROOT'))"; }

# 7a. PBXBuildFile section entries
SWIFT_BUILD_FILE_ENTRIES=""
for f in "${SWIFT_FILES[@]}"; do
  BF_UUID="${SWIFT_BUILD_FILE_UUIDS[$f]}"
  FR_UUID="${SWIFT_FILE_REF_UUIDS[$f]}"
  SWIFT_BUILD_FILE_ENTRIES+="    $BF_UUID /* $(basename $f) in Sources */ = {isa = PBXBuildFile; fileRef = $FR_UUID /* $(basename $f) */; };
"
done

RES_BUILD_FILE_ENTRIES=""
for f in "${RESOURCE_FILES[@]}"; do
  BF_UUID="${RES_BUILD_FILE_UUIDS[$f]}"
  FR_UUID="${RES_FILE_REF_UUIDS[$f]}"
  RES_BUILD_FILE_ENTRIES+="    $BF_UUID /* $(basename $f) in Resources */ = {isa = PBXBuildFile; fileRef = $FR_UUID /* $(basename $f) */; };
"
done

# 7b. PBXFileReference entries for Swift sources
SWIFT_FILE_REF_ENTRIES=""
for f in "${SWIFT_FILES[@]}"; do
  FR_UUID="${SWIFT_FILE_REF_UUIDS[$f]}"
  REL="$(rel_path $f)"
  SWIFT_FILE_REF_ENTRIES+="    $FR_UUID /* $(basename $f) */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = $(basename $f); sourceTree = \"<group>\"; };
"
done

# 7c. PBXFileReference entries for resources
RES_FILE_REF_ENTRIES=""
for f in "${RESOURCE_FILES[@]}"; do
  FR_UUID="${RES_FILE_REF_UUIDS[$f]}"
  EXT="${f##*.}"
  case "$EXT" in
    mp3)  FT="audio.mpeg";;
    ahap) FT="file";;
    mp4)  FT="com.apple.m4v-video";;
    png)  FT="image.png";;
    jpg)  FT="image.jpeg";;
    *)    FT="file";;
  esac
  RES_FILE_REF_ENTRIES+="    $FR_UUID /* $(basename $f) */ = {isa = PBXFileReference; lastKnownFileType = $FT; path = $(basename $f); sourceTree = \"<group>\"; };
"
done

# 7d. Sources group children (Swift files only)
SOURCES_GROUP_CHILDREN=""
for f in "${SWIFT_FILES[@]}"; do
  FR_UUID="${SWIFT_FILE_REF_UUIDS[$f]}"
  SOURCES_GROUP_CHILDREN+="      $FR_UUID /* $(basename $f) */,
"
done

# 7e. Resources group children
RES_GROUP_CHILDREN=""
for f in "${RESOURCE_FILES[@]}"; do
  FR_UUID="${RES_FILE_REF_UUIDS[$f]}"
  RES_GROUP_CHILDREN+="      $FR_UUID /* $(basename $f) */,
"
done

# 7f. PBXSourcesBuildPhase file list
SOURCES_PHASE_FILES=""
for f in "${SWIFT_FILES[@]}"; do
  BF_UUID="${SWIFT_BUILD_FILE_UUIDS[$f]}"
  SOURCES_PHASE_FILES+="      $BF_UUID /* $(basename $f) in Sources */,
"
done

# 7g. PBXResourcesBuildPhase file list
RESOURCES_PHASE_FILES=""
for f in "${RESOURCE_FILES[@]}"; do
  BF_UUID="${RES_BUILD_FILE_UUIDS[$f]}"
  RESOURCES_PHASE_FILES+="      $BF_UUID /* $(basename $f) in Resources */,
"
done

# ── 8. Write the Info.plist ───────────────────────────────────────────────────
INFOPLIST_PATH="$SOURCES_DIR/Info.plist"
/usr/libexec/PlistBuddy -c "Add :CFBundleIdentifier          string $BUNDLE_ID"             "$INFOPLIST_PATH" 2>/dev/null || true
cat > "$INFOPLIST_PATH" << PLIST
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>         <string>Custom Player</string>
  <key>CFBundleIdentifier</key>          <string>$BUNDLE_ID</string>
  <key>CFBundleName</key>                <string>$PROJECT_NAME</string>
  <key>CFBundlePackageType</key>         <string>APPL</string>
  <key>CFBundleShortVersionString</key>  <string>1.0.0</string>
  <key>CFBundleVersion</key>             <string>1</string>
  <key>LSRequiresIPhoneOS</key>          <true/>
  <key>UILaunchStoryboardName</key>      <string></string>
  <key>UIRequiresFullScreen</key>        <true/>
  <key>UIStatusBarStyle</key>            <string>UIStatusBarStyleLightContent</string>
  <key>UIViewControllerBasedStatusBarAppearance</key> <false/>
  <key>NSMicrophoneUsageDescription</key><string>This app does not use the microphone.</string>
  <key>UIBackgroundModes</key>
  <array><string>audio</string></array>
  <key>UISupportedInterfaceOrientations</key>
  <array><string>UIInterfaceOrientationPortrait</string></array>
  <key>UISupportedInterfaceOrientations~ipad</key>
  <array>
    <string>UIInterfaceOrientationPortrait</string>
    <string>UIInterfaceOrientationPortraitUpsideDown</string>
    <string>UIInterfaceOrientationLandscapeLeft</string>
    <string>UIInterfaceOrientationLandscapeRight</string>
  </array>
  <key>NSAppTransportSecurity</key>
  <dict><key>NSAllowsArbitraryLoads</key><false/></dict>
</dict>
</plist>
PLIST

# Add Info.plist as a file reference
INFOPLIST_PATH_REL="$(rel_path $INFOPLIST_PATH)"
SOURCES_GROUP_CHILDREN+="      $INFOPLIST_UUID /* Info.plist */,
"

# ── 9. Write the .pbxproj ─────────────────────────────────────────────────────
cat > "$PBXPROJ" << PBXPROJ
// !$*UTF8*$!
{
  archiveVersion = 1;
  classes = {};
  objectVersion = 56;
  objects = {

/* ── PBXBuildFile ── */
$SWIFT_BUILD_FILE_ENTRIES
$RES_BUILD_FILE_ENTRIES

/* ── PBXFileReference ── */
$SWIFT_FILE_REF_ENTRIES
$RES_FILE_REF_ENTRIES
    $APP_PRODUCT_UUID /* $PROJECT_NAME.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = $PROJECT_NAME.app; sourceTree = BUILT_PRODUCTS_DIR; };
    $INFOPLIST_UUID /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };

/* ── PBXFrameworksBuildPhase ── */
    $FRAMEWORKS_PHASE_UUID = {
      isa = PBXFrameworksBuildPhase;
      buildActionMask = 2147483647;
      files = ();
      runOnlyForDeploymentPostprocessing = 0;
    };

/* ── PBXGroup ── */
    $MAIN_GROUP_UUID = {
      isa = PBXGroup;
      children = (
        $SOURCES_GROUP_UUID /* Sources */,
        $RESOURCES_GROUP_UUID /* Resources */,
        $PRODUCTS_GROUP_UUID /* Products */,
      );
      sourceTree = "<group>";
    };
    $PRODUCTS_GROUP_UUID /* Products */ = {
      isa = PBXGroup;
      children = (
        $APP_PRODUCT_UUID /* $PROJECT_NAME.app */,
      );
      name = Products;
      sourceTree = "<group>";
    };
    $SOURCES_GROUP_UUID /* Sources */ = {
      isa = PBXGroup;
      children = (
$SOURCES_GROUP_CHILDREN
      );
      name = Sources;
      path = Sources;
      sourceTree = "<group>";
    };
    $RESOURCES_GROUP_UUID /* Resources */ = {
      isa = PBXGroup;
      children = (
$RES_GROUP_CHILDREN
      );
      name = Resources;
      path = Resources;
      sourceTree = "<group>";
    };

/* ── PBXNativeTarget ── */
    $TARGET_UUID /* $PROJECT_NAME */ = {
      isa = PBXNativeTarget;
      buildConfigurationList = $CONFIG_LIST_UUID;
      buildPhases = (
        $SOURCES_PHASE_UUID /* Sources */,
        $FRAMEWORKS_PHASE_UUID /* Frameworks */,
        $RESOURCES_PHASE_UUID /* Resources */,
      );
      buildRules = ();
      dependencies = ();
      name = $PROJECT_NAME;
      productName = $PROJECT_NAME;
      productReference = $APP_PRODUCT_UUID /* $PROJECT_NAME.app */;
      productType = "com.apple.product-type.application";
    };

/* ── PBXProject ── */
    $PROJECT_UUID /* Project object */ = {
      isa = PBXProject;
      attributes = {
        BuildIndependentTargetsInParallel = 1;
        LastSwiftUpdateCheck = 1500;
        LastUpgradeCheck = 1500;
        TargetAttributes = {
          $TARGET_UUID = {
            CreatedOnToolsVersion = 15.0;
          };
        };
      };
      buildConfigurationList = $PROJECT_CONFIG_LIST_UUID;
      compatibilityVersion = "Xcode 14.0";
      developmentRegion = en;
      hasScannedForEncodings = 0;
      knownRegions = (en, Base);
      mainGroup = $MAIN_GROUP_UUID;
      productRefGroup = $PRODUCTS_GROUP_UUID /* Products */;
      projectDirPath = "";
      projectRoot = "";
      targets = ($TARGET_UUID /* $PROJECT_NAME */);
    };

/* ── PBXResourcesBuildPhase ── */
    $RESOURCES_PHASE_UUID = {
      isa = PBXResourcesBuildPhase;
      buildActionMask = 2147483647;
      files = (
$RESOURCES_PHASE_FILES
      );
      runOnlyForDeploymentPostprocessing = 0;
    };

/* ── PBXSourcesBuildPhase ── */
    $SOURCES_PHASE_UUID = {
      isa = PBXSourcesBuildPhase;
      buildActionMask = 2147483647;
      files = (
$SOURCES_PHASE_FILES
      );
      runOnlyForDeploymentPostprocessing = 0;
    };

/* ── XCBuildConfiguration ── */
    $DEBUG_CONFIG_UUID /* Debug */ = {
      isa = XCBuildConfiguration;
      buildSettings = {
        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;
        ASSETCATALOG_COMPILER_APPICON_NAME    = AppIcon;
        CODE_SIGN_IDENTITY                    = "";
        CODE_SIGNING_ALLOWED                  = NO;
        CODE_SIGNING_REQUIRED                 = NO;
        CURRENT_PROJECT_VERSION               = 1;
        DEBUG_INFORMATION_FORMAT              = dwarf;
        DEVELOPMENT_TEAM                      = "";
        ENABLE_BITCODE                        = NO;
        INFOPLIST_FILE                        = Sources/Info.plist;
        IPHONEOS_DEPLOYMENT_TARGET            = 16.0;
        MARKETING_VERSION                     = 1.0.0;
        ONLY_ACTIVE_ARCH                      = NO;
        PRODUCT_BUNDLE_IDENTIFIER             = $BUNDLE_ID;
        PRODUCT_NAME                          = $PROJECT_NAME;
        PROVISIONING_PROFILE_SPECIFIER        = "";
        SWIFT_ACTIVE_COMPILATION_CONDITIONS   = DEBUG;
        SWIFT_OPTIMIZATION_LEVEL             = "-Onone";
        SWIFT_VERSION                         = 5.9;
        TARGETED_DEVICE_FAMILY                = "1,2";
        SKIP_INSTALL                          = NO;
      };
      name = Debug;
    };
    $RELEASE_CONFIG_UUID /* Release */ = {
      isa = XCBuildConfiguration;
      buildSettings = {
        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;
        ASSETCATALOG_COMPILER_APPICON_NAME    = AppIcon;
        CODE_SIGN_IDENTITY                    = "";
        CODE_SIGNING_ALLOWED                  = NO;
        CODE_SIGNING_REQUIRED                 = NO;
        CURRENT_PROJECT_VERSION               = 1;
        DEBUG_INFORMATION_FORMAT              = "dwarf-with-dsym";
        DEVELOPMENT_TEAM                      = "";
        ENABLE_BITCODE                        = NO;
        INFOPLIST_FILE                        = Sources/Info.plist;
        IPHONEOS_DEPLOYMENT_TARGET            = 16.0;
        MARKETING_VERSION                     = 1.0.0;
        ONLY_ACTIVE_ARCH                      = NO;
        PRODUCT_BUNDLE_IDENTIFIER             = $BUNDLE_ID;
        PRODUCT_NAME                          = $PROJECT_NAME;
        PROVISIONING_PROFILE_SPECIFIER        = "";
        SWIFT_ACTIVE_COMPILATION_CONDITIONS   = "";
        SWIFT_OPTIMIZATION_LEVEL             = "-Owholemodule";
        SWIFT_VERSION                         = 5.9;
        TARGETED_DEVICE_FAMILY                = "1,2";
        SKIP_INSTALL                          = NO;
      };
      name = Release;
    };
    $PROJECT_DEBUG_CONFIG_UUID /* Debug */ = {
      isa = XCBuildConfiguration;
      buildSettings = {
        ALWAYS_SEARCH_USER_PATHS = NO;
        CLANG_ENABLE_MODULES     = YES;
        ENABLE_STRICT_OBJC_MSGSEND = YES;
        ENABLE_TESTABILITY       = YES;
        GCC_DYNAMIC_NO_PIC       = NO;
        GCC_OPTIMIZATION_LEVEL   = 0;
        MTL_ENABLE_DEBUG_INFO    = INCLUDE_SOURCE;
        ONLY_ACTIVE_ARCH         = NO;
        SDKROOT                  = iphoneos;
      };
      name = Debug;
    };
    $PROJECT_RELEASE_CONFIG_UUID /* Release */ = {
      isa = XCBuildConfiguration;
      buildSettings = {
        ALWAYS_SEARCH_USER_PATHS = NO;
        CLANG_ENABLE_MODULES     = YES;
        ENABLE_STRICT_OBJC_MSGSEND = YES;
        SDKROOT                  = iphoneos;
        VALIDATE_PRODUCT         = YES;
      };
      name = Release;
    };

/* ── XCConfigurationList ── */
    $CONFIG_LIST_UUID /* Build configuration list for PBXNativeTarget "$PROJECT_NAME" */ = {
      isa = XCConfigurationList;
      buildConfigurations = ($DEBUG_CONFIG_UUID /* Debug */, $RELEASE_CONFIG_UUID /* Release */);
      defaultConfigurationIsVisible = 0;
      defaultConfigurationName = Release;
    };
    $PROJECT_CONFIG_LIST_UUID /* Build configuration list for PBXProject "$PROJECT_NAME" */ = {
      isa = XCConfigurationList;
      buildConfigurations = ($PROJECT_DEBUG_CONFIG_UUID /* Debug */, $PROJECT_RELEASE_CONFIG_UUID /* Release */);
      defaultConfigurationIsVisible = 0;
      defaultConfigurationName = Release;
    };

  };
  rootObject = $PROJECT_UUID /* Project object */;
}
PBXPROJ

echo "[init] project.pbxproj written ($(wc -c < "$PBXPROJ") bytes)"

# ── 10. Write the shared scheme ──────────────────────────────────────────────
SCHEME_PATH="$XCODEPROJ_DIR/xcshareddata/xcschemes/$SCHEME_NAME.xcscheme"
cat > "$SCHEME_PATH" << SCHEME
<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference
           BuildableIdentifier = "primary"
           BlueprintIdentifier = "$TARGET_UUID"
           BuildableName       = "$PROJECT_NAME.app"
           BlueprintName       = "$PROJECT_NAME"
           ReferencedContainer = "container:$PROJECT_NAME.xcodeproj">
        </BuildableReference>
      </BuildActionEntry>
    </BuildActionEntries>
  </BuildAction>
  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn" shouldUseLaunchSchemeArgsEnv="YES" codeCoverageEnabled="NO">
    <Testables/>
  </TestAction>
  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference
         BuildableIdentifier = "primary"
         BlueprintIdentifier = "$TARGET_UUID"
         BuildableName       = "$PROJECT_NAME.app"
         BlueprintName       = "$PROJECT_NAME"
         ReferencedContainer = "container:$PROJECT_NAME.xcodeproj">
      </BuildableReference>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference
         BuildableIdentifier = "primary"
         BlueprintIdentifier = "$TARGET_UUID"
         BuildableName       = "$PROJECT_NAME.app"
         BlueprintName       = "$PROJECT_NAME"
         ReferencedContainer = "container:$PROJECT_NAME.xcodeproj">
      </BuildableReference>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES" customArchiveName="$PROJECT_NAME"/>
</Scheme>
SCHEME

echo "[init] Scheme written: $SCHEME_PATH"

# ── 11. Sanity check ─────────────────────────────────────────────────────────
echo ""
echo "[init] Final project structure:"
find "$XCODEPROJ_DIR" -type f | sort
echo ""
echo "[init] Validating project with xcodebuild -list..."
xcodebuild -project "$XCODEPROJ_DIR" -list
echo ""
echo "[init] ✓ build_init.sh complete"
