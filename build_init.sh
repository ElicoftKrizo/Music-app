#!/usr/bin/env bash
# =============================================================================
# build_init.sh — CustomPlayer Cloud Build Initialiser v4
# Fix: All structured file generation (pbxproj, plist, scheme) is done
# entirely in Python — zero bash heredoc variable expansion issues.
# Compatible: bash 3.2+ (macOS system default)
# =============================================================================
set -euo pipefail

REPO_ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
PROJECT_NAME="CustomPlayer"
BUNDLE_ID="com.custom.player"
SCHEME_NAME="CustomPlayer"
SOURCES_DIR="$REPO_ROOT/Sources"
RESOURCES_DIR="$REPO_ROOT/Resources"
XCODEPROJ_DIR="$REPO_ROOT/$PROJECT_NAME.xcodeproj"

echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"
echo "  build_init.sh v4 — CustomPlayer project bootstrap"
echo "  Repo root : $REPO_ROOT"
echo "  Xcode proj: $XCODEPROJ_DIR"
echo "━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━━"

# ── 1. Directory structure ────────────────────────────────────────────────────
mkdir -p "$SOURCES_DIR"
mkdir -p "$RESOURCES_DIR"
mkdir -p "$XCODEPROJ_DIR/xcshareddata/xcschemes"

# ── 2. App.swift entry point ──────────────────────────────────────────────────
if [ ! -f "$SOURCES_DIR/App.swift" ]; then
  echo "[init] Creating App.swift"
  python3 -c "
content = '''import SwiftUI
@main
struct CustomPlayerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
'''
open('$SOURCES_DIR/App.swift', 'w').write(content)
print('[init] App.swift created')
"
fi

# ── 3. Stub assets ────────────────────────────────────────────────────────────
python3 << 'PYEOF'
import os, struct, zlib

res = os.environ.get('RESOURCES_DIR', '')
if not res:
    import sys
    # fallback: read from arg written by shell
    res = open('/tmp/cp_resdir.txt').read().strip()

def stub_mp3(path):
    if os.path.exists(path): return
    id3   = b'ID3\x03\x00\x00\x00\x00\x00\x00'
    frame = b'\xff\xfb\x90\x00' + b'\x00' * 413
    open(path, 'wb').write(id3 + frame)
    print(f'  stub mp3  -> {path}')

def stub_ahap(path):
    if os.path.exists(path): return
    content = '''{
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
}'''
    open(path, 'w').write(content)
    print(f'  stub ahap -> {path}')

def stub_png(path):
    if os.path.exists(path): return
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    sig  = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(bytes([0, 80, 10, 30])))
    iend = chunk(b'IEND', b'')
    open(path, 'wb').write(sig + ihdr + idat + iend)
    print(f'  stub png  -> {path}')

stub_mp3 (os.path.join(res, 'music.mp3'))
stub_ahap(os.path.join(res, 'haptic.ahap'))
stub_png (os.path.join(res, 'cover.png'))
PYEOF

echo "[init] Resources:"
ls -lh "$RESOURCES_DIR/"

# ── 4. Generate Xcode project via Python (no heredoc variable expansion) ──────
python3 << PYEOF
import os, uuid, glob

repo_root    = "$REPO_ROOT"
project_name = "$PROJECT_NAME"
bundle_id    = "$BUNDLE_ID"
scheme_name  = "$SCHEME_NAME"
sources_dir  = "$SOURCES_DIR"
resources_dir= "$RESOURCES_DIR"
xcodeproj    = "$XCODEPROJ_DIR"

def new_id():
    return uuid.uuid4().hex[:24].upper()

# ── Collect files ──────────────────────────────────────────────────────────────
swift_files = sorted(glob.glob(os.path.join(sources_dir, '**', '*.swift'), recursive=True))
res_exts    = {'.mp3', '.ahap', '.mp4', '.png', '.jpg', '.jpeg'}
res_files   = sorted([
    f for f in glob.glob(os.path.join(resources_dir, '*'))
    if os.path.isfile(f) and os.path.splitext(f)[1].lower() in res_exts
])

print(f'[init-py] Swift files  : {len(swift_files)}')
for f in swift_files: print(f'  {f}')
print(f'[init-py] Resource files: {len(res_files)}')
for f in res_files: print(f'  {f}')

# ── UUID pool ──────────────────────────────────────────────────────────────────
PROJECT_UUID            = new_id()
MAIN_GROUP_UUID         = new_id()
PRODUCTS_GROUP_UUID     = new_id()
SOURCES_GROUP_UUID      = new_id()
RESOURCES_GROUP_UUID    = new_id()
TARGET_UUID             = new_id()
APP_PRODUCT_UUID        = new_id()
SOURCES_PHASE_UUID      = new_id()
RESOURCES_PHASE_UUID    = new_id()
FRAMEWORKS_PHASE_UUID   = new_id()
DEBUG_CFG_UUID          = new_id()
RELEASE_CFG_UUID        = new_id()
PROJ_DEBUG_CFG_UUID     = new_id()
PROJ_RELEASE_CFG_UUID   = new_id()
CFG_LIST_UUID           = new_id()
PROJ_CFG_LIST_UUID      = new_id()
INFOPLIST_UUID          = new_id()

# Per-file UUIDs
swift_fr  = [new_id() for _ in swift_files]
swift_bf  = [new_id() for _ in swift_files]
res_fr    = [new_id() for _ in res_files]
res_bf    = [new_id() for _ in res_files]

# ── File type helper ───────────────────────────────────────────────────────────
def file_type(path):
    ext = os.path.splitext(path)[1].lower()
    return {
        '.swift': 'sourcecode.swift',
        '.mp3':   'audio.mpeg',
        '.ahap':  'file',
        '.mp4':   'com.apple.m4v-video',
        '.png':   'image.png',
        '.jpg':   'image.jpeg',
        '.jpeg':  'image.jpeg',
    }.get(ext, 'file')

# ── Build pbxproj sections ─────────────────────────────────────────────────────
def indent(lines, n=4):
    pad = ' ' * n
    return ''.join(pad + l + '\n' for l in lines if l is not None)

# PBXBuildFile
bf_lines = []
for i, f in enumerate(swift_files):
    name = os.path.basename(f)
    bf_lines.append(f'{swift_bf[i]} /* {name} in Sources */ = {{isa = PBXBuildFile; fileRef = {swift_fr[i]} /* {name} */; }};')
for i, f in enumerate(res_files):
    name = os.path.basename(f)
    bf_lines.append(f'{res_bf[i]} /* {name} in Resources */ = {{isa = PBXBuildFile; fileRef = {res_fr[i]} /* {name} */; }};')

# PBXFileReference
fr_lines = []
for i, f in enumerate(swift_files):
    name = os.path.basename(f)
    ft   = file_type(f)
    fr_lines.append(f'{swift_fr[i]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {name}; sourceTree = "<group>"; }};')
for i, f in enumerate(res_files):
    name = os.path.basename(f)
    ft   = file_type(f)
    fr_lines.append(f'{res_fr[i]} /* {name} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {name}; sourceTree = "<group>"; }};')
fr_lines.append(f'{APP_PRODUCT_UUID} /* {project_name}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {project_name}.app; sourceTree = BUILT_PRODUCTS_DIR; }};')
fr_lines.append(f'{INFOPLIST_UUID} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};')

# Groups
src_children  = ''.join(f'        {swift_fr[i]} /* {os.path.basename(f)} */,\n' for i, f in enumerate(swift_files))
src_children += f'        {INFOPLIST_UUID} /* Info.plist */,\n'
res_children  = ''.join(f'        {res_fr[i]} /* {os.path.basename(f)} */,\n' for i, f in enumerate(res_files))

# Build phases
src_phase_files = ''.join(f'        {swift_bf[i]} /* {os.path.basename(f)} in Sources */,\n' for i, f in enumerate(swift_files))
res_phase_files = ''.join(f'        {res_bf[i]} /* {os.path.basename(f)} in Resources */,\n' for i, f in enumerate(res_files))

# ── Write project.pbxproj ──────────────────────────────────────────────────────
pbxproj = f"""// !$*UTF8*$!
{{
  archiveVersion = 1;
  classes = {{}};
  objectVersion = 56;
  objects = {{

/* Begin PBXBuildFile section */
{indent(bf_lines)}
/* End PBXBuildFile section */

/* Begin PBXFileReference section */
{indent(fr_lines)}
/* End PBXFileReference section */

/* Begin PBXFrameworksBuildPhase section */
    {FRAMEWORKS_PHASE_UUID} = {{
      isa = PBXFrameworksBuildPhase;
      buildActionMask = 2147483647;
      files = ();
      runOnlyForDeploymentPostprocessing = 0;
    }};
/* End PBXFrameworksBuildPhase section */

/* Begin PBXGroup section */
    {MAIN_GROUP_UUID} = {{
      isa = PBXGroup;
      children = (
        {SOURCES_GROUP_UUID} /* Sources */,
        {RESOURCES_GROUP_UUID} /* Resources */,
        {PRODUCTS_GROUP_UUID} /* Products */,
      );
      sourceTree = "<group>";
    }};
    {PRODUCTS_GROUP_UUID} /* Products */ = {{
      isa = PBXGroup;
      children = ({APP_PRODUCT_UUID} /* {project_name}.app */);
      name = Products;
      sourceTree = "<group>";
    }};
    {SOURCES_GROUP_UUID} /* Sources */ = {{
      isa = PBXGroup;
      children = (
{src_children}
      );
      name = Sources;
      path = Sources;
      sourceTree = "<group>";
    }};
    {RESOURCES_GROUP_UUID} /* Resources */ = {{
      isa = PBXGroup;
      children = (
{res_children}
      );
      name = Resources;
      path = Resources;
      sourceTree = "<group>";
    }};
/* End PBXGroup section */

/* Begin PBXNativeTarget section */
    {TARGET_UUID} /* {project_name} */ = {{
      isa = PBXNativeTarget;
      buildConfigurationList = {CFG_LIST_UUID};
      buildPhases = (
        {SOURCES_PHASE_UUID} /* Sources */,
        {FRAMEWORKS_PHASE_UUID} /* Frameworks */,
        {RESOURCES_PHASE_UUID} /* Resources */,
      );
      buildRules = ();
      dependencies = ();
      name = {project_name};
      productName = {project_name};
      productReference = {APP_PRODUCT_UUID} /* {project_name}.app */;
      productType = "com.apple.product-type.application";
    }};
/* End PBXNativeTarget section */

/* Begin PBXProject section */
    {PROJECT_UUID} /* Project object */ = {{
      isa = PBXProject;
      attributes = {{
        BuildIndependentTargetsInParallel = 1;
        LastSwiftUpdateCheck = 1500;
        LastUpgradeCheck = 1500;
        TargetAttributes = {{ {TARGET_UUID} = {{ CreatedOnToolsVersion = 15.0; }}; }};
      }};
      buildConfigurationList = {PROJ_CFG_LIST_UUID};
      compatibilityVersion = "Xcode 14.0";
      developmentRegion = en;
      hasScannedForEncodings = 0;
      knownRegions = (en, Base);
      mainGroup = {MAIN_GROUP_UUID};
      productRefGroup = {PRODUCTS_GROUP_UUID} /* Products */;
      projectDirPath = "";
      projectRoot = "";
      targets = ({TARGET_UUID} /* {project_name} */);
    }};
/* End PBXProject section */

/* Begin PBXResourcesBuildPhase section */
    {RESOURCES_PHASE_UUID} = {{
      isa = PBXResourcesBuildPhase;
      buildActionMask = 2147483647;
      files = (
{res_phase_files}
      );
      runOnlyForDeploymentPostprocessing = 0;
    }};
/* End PBXResourcesBuildPhase section */

/* Begin PBXSourcesBuildPhase section */
    {SOURCES_PHASE_UUID} = {{
      isa = PBXSourcesBuildPhase;
      buildActionMask = 2147483647;
      files = (
{src_phase_files}
      );
      runOnlyForDeploymentPostprocessing = 0;
    }};
/* End PBXSourcesBuildPhase section */

/* Begin XCBuildConfiguration section */
    {DEBUG_CFG_UUID} /* Debug */ = {{
      isa = XCBuildConfiguration;
      buildSettings = {{
        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;
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
        PRODUCT_BUNDLE_IDENTIFIER             = {bundle_id};
        PRODUCT_NAME                          = {project_name};
        PROVISIONING_PROFILE_SPECIFIER        = "";
        SWIFT_ACTIVE_COMPILATION_CONDITIONS   = DEBUG;
        SWIFT_OPTIMIZATION_LEVEL              = "-Onone";
        SWIFT_VERSION                         = 5.9;
        TARGETED_DEVICE_FAMILY                = "1,2";
        SKIP_INSTALL                          = NO;
      }};
      name = Debug;
    }};
    {RELEASE_CFG_UUID} /* Release */ = {{
      isa = XCBuildConfiguration;
      buildSettings = {{
        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;
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
        PRODUCT_BUNDLE_IDENTIFIER             = {bundle_id};
        PRODUCT_NAME                          = {project_name};
        PROVISIONING_PROFILE_SPECIFIER        = "";
        SWIFT_ACTIVE_COMPILATION_CONDITIONS   = "";
        SWIFT_OPTIMIZATION_LEVEL              = "-Owholemodule";
        SWIFT_VERSION                         = 5.9;
        TARGETED_DEVICE_FAMILY                = "1,2";
        SKIP_INSTALL                          = NO;
      }};
      name = Release;
    }};
    {PROJ_DEBUG_CFG_UUID} /* Debug */ = {{
      isa = XCBuildConfiguration;
      buildSettings = {{
        ALWAYS_SEARCH_USER_PATHS = NO;
        CLANG_ENABLE_MODULES     = YES;
        ENABLE_TESTABILITY       = YES;
        GCC_OPTIMIZATION_LEVEL  = 0;
        ONLY_ACTIVE_ARCH         = NO;
        SDKROOT                  = iphoneos;
      }};
      name = Debug;
    }};
    {PROJ_RELEASE_CFG_UUID} /* Release */ = {{
      isa = XCBuildConfiguration;
      buildSettings = {{
        ALWAYS_SEARCH_USER_PATHS = NO;
        CLANG_ENABLE_MODULES     = YES;
        SDKROOT                  = iphoneos;
        VALIDATE_PRODUCT         = YES;
      }};
      name = Release;
    }};
/* End XCBuildConfiguration section */

/* Begin XCConfigurationList section */
    {CFG_LIST_UUID} = {{
      isa = XCConfigurationList;
      buildConfigurations = ({DEBUG_CFG_UUID} /* Debug */, {RELEASE_CFG_UUID} /* Release */);
      defaultConfigurationIsVisible = 0;
      defaultConfigurationName = Release;
    }};
    {PROJ_CFG_LIST_UUID} = {{
      isa = XCConfigurationList;
      buildConfigurations = ({PROJ_DEBUG_CFG_UUID} /* Debug */, {PROJ_RELEASE_CFG_UUID} /* Release */);
      defaultConfigurationIsVisible = 0;
      defaultConfigurationName = Release;
    }};
/* End XCConfigurationList section */

  }};
  rootObject = {PROJECT_UUID} /* Project object */;
}}
"""

pbxproj_path = os.path.join(xcodeproj, 'project.pbxproj')
open(pbxproj_path, 'w').write(pbxproj)
size = os.path.getsize(pbxproj_path)
print(f'[init-py] project.pbxproj written ({size:,} bytes)')

# ── Write Info.plist ───────────────────────────────────────────────────────────
plist = f"""<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
  <key>CFBundleDisplayName</key>         <string>Custom Player</string>
  <key>CFBundleIdentifier</key>          <string>{bundle_id}</string>
  <key>CFBundleName</key>                <string>{project_name}</string>
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
</plist>"""

plist_path = os.path.join(sources_dir, 'Info.plist')
open(plist_path, 'w').write(plist)
print(f'[init-py] Info.plist written')

# ── Write .xcscheme ────────────────────────────────────────────────────────────
scheme_xml = f"""<?xml version="1.0" encoding="UTF-8"?>
<Scheme LastUpgradeVersion="1500" version="1.7">
  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">
    <BuildActionEntries>
      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">
        <BuildableReference
           BuildableIdentifier = "primary"
           BlueprintIdentifier = "{TARGET_UUID}"
           BuildableName       = "{project_name}.app"
           BlueprintName       = "{project_name}"
           ReferencedContainer = "container:{project_name}.xcodeproj">
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
         BlueprintIdentifier = "{TARGET_UUID}"
         BuildableName       = "{project_name}.app"
         BlueprintName       = "{project_name}"
         ReferencedContainer = "container:{project_name}.xcodeproj">
      </BuildableReference>
    </BuildableProductRunnable>
  </LaunchAction>
  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">
    <BuildableProductRunnable runnableDebuggingMode="0">
      <BuildableReference
         BuildableIdentifier = "primary"
         BlueprintIdentifier = "{TARGET_UUID}"
         BuildableName       = "{project_name}.app"
         BlueprintName       = "{project_name}"
         ReferencedContainer = "container:{project_name}.xcodeproj">
      </BuildableReference>
    </BuildableProductRunnable>
  </ProfileAction>
  <AnalyzeAction buildConfiguration="Debug"/>
  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES" customArchiveName="{project_name}"/>
</Scheme>"""

scheme_path = os.path.join(xcodeproj, 'xcshareddata', 'xcschemes', f'{scheme_name}.xcscheme')
open(scheme_path, 'w').write(scheme_xml)
print(f'[init-py] Scheme written: {scheme_path}')

print('[init-py] All files generated successfully')
PYEOF

# ── 5. Final validation ───────────────────────────────────────────────────────
echo ""
echo "[init] Project structure:"
find "$XCODEPROJ_DIR" -type f | sort
echo ""
echo "[init] Validating with xcodebuild -list..."
xcodebuild -project "$XCODEPROJ_DIR" -list
echo ""
echo "[init] build_init.sh complete"
