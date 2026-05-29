#!/usr/bin/env bash
# =============================================================================
# build_init.sh — CustomPlayer Cloud Build Initialiser
# Compatible: bash 3.2+ (macOS default) AND bash 5.x
# Fixes: removed declare -A (bash 3.2 incompatible), fixed heredoc quoting
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

# ── 1. Directory structure ────────────────────────────────────────────────────
mkdir -p "$SOURCES_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$XCODEPROJ_DIR/xcshareddata/xcschemes"

# ── 2. Guarantee App.swift entry point ───────────────────────────────────────
if [ ! -f "$SOURCES_DIR/App.swift" ]; then
  echo "[init] Creating App.swift"
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

# ── 3. Stub placeholder assets if real ones are absent ───────────────────────

create_stub_mp3() {
  python3 - "$1" << 'PYEOF'
import sys, struct
path = sys.argv[1]
id3   = b'ID3\x03\x00\x00\x00\x00\x00\x00'
frame = b'\xff\xfb\x90\x00' + b'\x00' * 413
open(path, 'wb').write(id3 + frame)
print("  stub mp3 -> " + path)
PYEOF
}

create_stub_ahap() {
  # NOTE: no backticks or special chars inside heredoc to avoid sh parse errors
  cat > "$1" << 'AHAP'
{
  "Version": 1.0,
  "Metadata": { "Project": "CustomPlayer" },
  "Pattern": [
    {
      "Event": {
        "Time": 0.0,
        "EventType": "HapticTransient",
        "EventParameters": [
          { "ParameterID": "HapticIntensity", "ParameterValue": 0.5 },
          { "ParameterID": "HapticSharpness", "ParameterValue": 0.5 }
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
path = sys.argv[1]
sig  = b'\x89PNG\r\n\x1a\n'
ihdr = chunk(b'IHDR', struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
idat = chunk(b'IDAT', zlib.compress(bytes([0, 80, 10, 30])))
iend = chunk(b'IEND', b'')
open(path, 'wb').write(sig + ihdr + idat + iend)
print("  stub png  -> " + path)
PYEOF
}

[ ! -f "$RESOURCES_DIR/music.mp3"   ] && create_stub_mp3  "$RESOURCES_DIR/music.mp3"
[ ! -f "$RESOURCES_DIR/haptic.ahap" ] && create_stub_ahap "$RESOURCES_DIR/haptic.ahap"
[ ! -f "$RESOURCES_DIR/cover.png"   ] && create_stub_png  "$RESOURCES_DIR/cover.png"

echo "[init] Resources:"
ls -lh "$RESOURCES_DIR/"

# ── 4. Collect Swift source files into indexed arrays ────────────────────────
# Uses plain indexed arrays only — compatible with bash 3.2
SWIFT_FILES=()
while IFS= read -r -d $'\0' f; do
  SWIFT_FILES+=("$f")
done < <(find "$SOURCES_DIR" -name "*.swift" -print0 | sort -z)

echo "[init] Swift sources (${#SWIFT_FILES[@]} files):"
for f in "${SWIFT_FILES[@]}"; do echo "  $f"; done

RESOURCE_FILES=()
while IFS= read -r -d $'\0' f; do
  RESOURCE_FILES+=("$f")
done < <(find "$RESOURCES_DIR" -type f \( \
    -name "*.mp3" -o -name "*.ahap" -o \
    -name "*.mp4" -o -name "*.png"  -o -name "*.jpg" \
  \) -print0 | sort -z)

echo "[init] Resources (${#RESOURCE_FILES[@]} files):"
for f in "${RESOURCE_FILES[@]}"; do echo "  $f"; done

# ── 5. UUID generator (pure Python — no uuidgen flags needed) ─────────────────
gen_uuid() {
  python3 -c "import uuid; print(uuid.uuid4().hex[:24].upper())"
}

# ── 6. Generate all UUIDs up front using parallel indexed arrays ──────────────
# Instead of declare -A (bash 4+), we use parallel indexed arrays and a
# Python lookup helper written to a temp file.

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

# Parallel arrays for Swift files
SWIFT_FR_UUIDS=()
SWIFT_BF_UUIDS=()
for f in "${SWIFT_FILES[@]}"; do
  SWIFT_FR_UUIDS+=("$(gen_uuid)")
  SWIFT_BF_UUIDS+=("$(gen_uuid)")
done

# Parallel arrays for resource files
RES_FR_UUIDS=()
RES_BF_UUIDS=()
for f in "${RESOURCE_FILES[@]}"; do
  RES_FR_UUIDS+=("$(gen_uuid)")
  RES_BF_UUIDS+=("$(gen_uuid)")
done

# ── 7. Build pbxproj section strings ─────────────────────────────────────────

SWIFT_BUILD_FILE_ENTRIES=""
for i in "${!SWIFT_FILES[@]}"; do
  f="${SWIFT_FILES[$i]}"
  BF="${SWIFT_BF_UUIDS[$i]}"
  FR="${SWIFT_FR_UUIDS[$i]}"
  NAME="$(basename "$f")"
  SWIFT_BUILD_FILE_ENTRIES+="    $BF /* $NAME in Sources */ = {isa = PBXBuildFile; fileRef = $FR /* $NAME */; };
"
done

RES_BUILD_FILE_ENTRIES=""
for i in "${!RESOURCE_FILES[@]}"; do
  f="${RESOURCE_FILES[$i]}"
  BF="${RES_BF_UUIDS[$i]}"
  FR="${RES_FR_UUIDS[$i]}"
  NAME="$(basename "$f")"
  RES_BUILD_FILE_ENTRIES+="    $BF /* $NAME in Resources */ = {isa = PBXBuildFile; fileRef = $FR /* $NAME */; };
"
done

SWIFT_FILE_REF_ENTRIES=""
for i in "${!SWIFT_FILES[@]}"; do
  f="${SWIFT_FILES[$i]}"
  FR="${SWIFT_FR_UUIDS[$i]}"
  NAME="$(basename "$f")"
  SWIFT_FILE_REF_ENTRIES+="    $FR /* $NAME */ = {isa = PBXFileReference; lastKnownFileType = sourcecode.swift; path = $NAME; sourceTree = \"<group>\"; };
"
done

RES_FILE_REF_ENTRIES=""
for i in "${!RESOURCE_FILES[@]}"; do
  f="${RESOURCE_FILES[$i]}"
  FR="${RES_FR_UUIDS[$i]}"
  NAME="$(basename "$f")"
  EXT="${f##*.}"
  case "$EXT" in
    mp3)  FT="audio.mpeg" ;;
    ahap) FT="file" ;;
    mp4)  FT="com.apple.m4v-video" ;;
    png)  FT="image.png" ;;
    jpg)  FT="image.jpeg" ;;
    *)    FT="file" ;;
  esac
  RES_FILE_REF_ENTRIES+="    $FR /* $NAME */ = {isa = PBXFileReference; lastKnownFileType = $FT; path = $NAME; sourceTree = \"<group>\"; };
"
done

SOURCES_GROUP_CHILDREN=""
for i in "${!SWIFT_FILES[@]}"; do
  NAME="$(basename "${SWIFT_FILES[$i]}")"
  FR="${SWIFT_FR_UUIDS[$i]}"
  SOURCES_GROUP_CHILDREN+="        $FR /* $NAME */,
"
done
SOURCES_GROUP_CHILDREN+="        $INFOPLIST_UUID /* Info.plist */,
"

RES_GROUP_CHILDREN=""
for i in "${!RESOURCE_FILES[@]}"; do
  NAME="$(basename "${RESOURCE_FILES[$i]}")"
  FR="${RES_FR_UUIDS[$i]}"
  RES_GROUP_CHILDREN+="        $FR /* $NAME */,
"
done

SOURCES_PHASE_FILES=""
for i in "${!SWIFT_FILES[@]}"; do
  NAME="$(basename "${SWIFT_FILES[$i]}")"
  BF="${SWIFT_BF_UUIDS[$i]}"
  SOURCES_PHASE_FILES+="        $BF /* $NAME in Sources */,
"
done

RESOURCES_PHASE_FILES=""
for i in "${!RESOURCE_FILES[@]}"; do
  NAME="$(basename "${RESOURCE_FILES[$i]}")"
  BF="${RES_BF_UUIDS[$i]}"
  RESOURCES_PHASE_FILES+="        $BF /* $NAME in Resources */,
"
done

# ── 8. Write Info.plist ───────────────────────────────────────────────────────
INFOPLIST_PATH="$SOURCES_DIR/Info.plist"
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

echo "[init] Info.plist written"

# ── 9. Write project.pbxproj ──────────────────────────────────────────────────
cat > "$PBXPROJ" << PBXPROJ
// !\$*UTF8*\$!
{
  archiveVersion = 1;
  classes = {};
  objectVersion = 56;
  objects = {

/* PBXBuildFile */
$SWIFT_BUILD_FILE_ENTRIES
$RES_BUILD_FILE_ENTRIES

/* PBXFileReference */
$SWIFT_FILE_REF_ENTRIES
$RES_FILE_REF_ENTRIES
    $APP_PRODUCT_UUID /* $PROJECT_NAME.app */ = {isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = $PROJECT_NAME.app; sourceTree = BUILT_PRODUCTS_DIR; };
    $INFOPLIST_UUID /* Info.plist */ = {isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; };

/* PBXFrameworksBuildPhase */
    $FRAMEWORKS_PHASE_UUID = {
      isa = PBXFrameworksBuildPhase;
      buildActionMask = 2147483647;
      files = ();
      runOnlyForDeploymentPostprocessing = 0;
    };

/* PBXGroup */
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
      children = ($APP_PRODUCT_UUID /* $PROJECT_NAME.app */);
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

/* PBXNativeTarget */
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

/* PBXProject */
    $PROJECT_UUID /* Project object */ = {
      isa = PBXProject;
      attributes = {
        BuildIndependentTargetsInParallel = 1;
        LastSwiftUpdateCheck = 1500;
        LastUpgradeCheck = 1500;
        TargetAttributes = { $TARGET_UUID = { CreatedOnToolsVersion = 15.0; }; };
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

/* PBXResourcesBuildPhase */
    $RESOURCES_PHASE_UUID = {
      isa = PBXResourcesBuildPhase;
      buildActionMask = 2147483647;
      files = (
$RESOURCES_PHASE_FILES
      );
      runOnlyForDeploymentPostprocessing = 0;
    };

/* PBXSourcesBuildPhase */
    $SOURCES_PHASE_UUID = {
      isa = PBXSourcesBuildPhase;
      buildActionMask = 2147483647;
      files = (
$SOURCES_PHASE_FILES
      );
      runOnlyForDeploymentPostprocessing = 0;
    };

/* XCBuildConfiguration */
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
        SWIFT_OPTIMIZATION_LEVEL              = "-Onone";
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
        SWIFT_OPTIMIZATION_LEVEL              = "-Owholemodule";
        SWIFT_VERSION                         = 5.9;
        TARGETED_DEVICE_FAMILY                = "1,2";
        SKIP_INSTALL                          = NO;
      };
      name = Release;
    };
    $PROJECT_DEBUG_CONFIG_UUID /* Debug */ = {
      isa = XCBuildConfiguration;
      buildSettings = {
        ALWAYS_SEARCH_USER_PATHS  = NO;
        CLANG_ENABLE_MODULES      = YES;
        ENABLE_TESTABILITY        = YES;
        GCC_OPTIMIZATION_LEVEL   = 0;
        ONLY_ACTIVE_ARCH          = NO;
        SDKROOT                   = iphoneos;
      };
      name = Debug;
    };
    $PROJECT_RELEASE_CONFIG_UUID /* Release */ = {
      isa = XCBuildConfiguration;
      buildSettings = {
        ALWAYS_SEARCH_USER_PATHS  = NO;
        CLANG_ENABLE_MODULES      = YES;
        SDKROOT                   = iphoneos;
        VALIDATE_PRODUCT          = YES;
      };
      name = Release;
    };

/* XCConfigurationList */
    $CONFIG_LIST_UUID = {
      isa = XCConfigurationList;
      buildConfigurations = ($DEBUG_CONFIG_UUID /* Debug */, $RELEASE_CONFIG_UUID /* Release */);
      defaultConfigurationIsVisible = 0;
      defaultConfigurationName = Release;
    };
    $PROJECT_CONFIG_LIST_UUID = {
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

# ── 10. Write shared scheme ───────────────────────────────────────────────────
SCHEME_FILE="$XCODEPROJ_DIR/xcshareddata/xcschemes/$SCHEME_NAME.xcscheme"
cat > "$SCHEME_FILE" << SCHEME
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

echo "[init] Scheme written: $SCHEME_FILE"

# ── 11. Final validation ──────────────────────────────────────────────────────
echo ""
echo "[init] Project structure:"
find "$XCODEPROJ_DIR" -type f | sort
echo ""
echo "[init] Validating with xcodebuild -list..."
xcodebuild -project "$XCODEPROJ_DIR" -list
echo ""
echo "[init] build_init.sh complete"
