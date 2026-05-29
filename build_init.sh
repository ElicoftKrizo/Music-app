#!/usr/bin/env bash
# =============================================================================
# build_init.sh — CustomPlayer Cloud Build Initialiser v5
# Fix: Pass all bash variables into Python blocks via direct string injection
#      at heredoc call site — no os.environ, no temp files needed.
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
echo "  build_init.sh v5 — CustomPlayer project bootstrap"
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
  # Write using Python with path injected directly — no heredoc expansion issues
  python3 -c "
import os
path = '$SOURCES_DIR/App.swift'
open(path, 'w').write('''import SwiftUI
@main
struct CustomPlayerApp: App {
    var body: some Scene {
        WindowGroup { ContentView() }
    }
}
''')
print('[init] App.swift created:', path)
"
fi

# ── 3. Stub assets — paths injected directly as Python string literals ─────────
python3 - "$SOURCES_DIR" "$RESOURCES_DIR" << 'PYEOF'
import sys, os, struct, zlib

sources_dir   = sys.argv[1]
resources_dir = sys.argv[2]

def stub_mp3(path):
    if os.path.exists(path):
        print(f'  mp3 exists: {path}')
        return
    id3   = b'ID3\x03\x00\x00\x00\x00\x00\x00'
    frame = b'\xff\xfb\x90\x00' + b'\x00' * 413
    open(path, 'wb').write(id3 + frame)
    print(f'  stub mp3  -> {path}')

def stub_ahap(path):
    if os.path.exists(path):
        print(f'  ahap exists: {path}')
        return
    content = """{
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
}"""
    open(path, 'w').write(content)
    print(f'  stub ahap -> {path}')

def stub_png(path):
    if os.path.exists(path):
        print(f'  png exists: {path}')
        return
    def chunk(tag, data):
        c = struct.pack(">I", len(data)) + tag + data
        return c + struct.pack(">I", zlib.crc32(tag + data) & 0xFFFFFFFF)
    sig  = b'\x89PNG\r\n\x1a\n'
    ihdr = chunk(b'IHDR', struct.pack(">IIBBBBB", 1, 1, 8, 2, 0, 0, 0))
    idat = chunk(b'IDAT', zlib.compress(bytes([0, 80, 10, 30])))
    iend = chunk(b'IEND', b'')
    open(path, 'wb').write(sig + ihdr + idat + iend)
    print(f'  stub png  -> {path}')

stub_mp3 (os.path.join(resources_dir, 'music.mp3'))
stub_ahap(os.path.join(resources_dir, 'haptic.ahap'))
stub_png (os.path.join(resources_dir, 'cover.png'))
print('[init-py] Stub assets done')
PYEOF

echo "[init] Resources:"
ls -lh "$RESOURCES_DIR/"

# ── 4. Generate Xcode project entirely in Python ──────────────────────────────
# All bash variables passed as argv — zero heredoc expansion risk
python3 - "$REPO_ROOT" "$PROJECT_NAME" "$BUNDLE_ID" "$SCHEME_NAME" "$SOURCES_DIR" "$RESOURCES_DIR" "$XCODEPROJ_DIR" << 'PYEOF'
import sys, os, uuid, glob

repo_root     = sys.argv[1]
project_name  = sys.argv[2]
bundle_id     = sys.argv[3]
scheme_name   = sys.argv[4]
sources_dir   = sys.argv[5]
resources_dir = sys.argv[6]
xcodeproj     = sys.argv[7]

def new_id():
    return uuid.uuid4().hex[:24].upper()

# ── Collect files ──────────────────────────────────────────────────────────────
swift_files = sorted(glob.glob(os.path.join(sources_dir, '**', '*.swift'), recursive=True))
res_exts    = {'.mp3', '.ahap', '.mp4', '.png', '.jpg', '.jpeg'}
res_files   = sorted([
    f for f in glob.glob(os.path.join(resources_dir, '*'))
    if os.path.isfile(f) and os.path.splitext(f)[1].lower() in res_exts
])

print(f'[init-py] Swift files   : {len(swift_files)}')
for f in swift_files: print(f'  {f}')
print(f'[init-py] Resource files: {len(res_files)}')
for f in res_files: print(f'  {f}')

if not swift_files:
    print('ERROR: No Swift files found in Sources/')
    sys.exit(1)

# ── UUID pool ──────────────────────────────────────────────────────────────────
PROJECT_UUID          = new_id()
MAIN_GROUP_UUID       = new_id()
PRODUCTS_GROUP_UUID   = new_id()
SOURCES_GROUP_UUID    = new_id()
RESOURCES_GROUP_UUID  = new_id()
TARGET_UUID           = new_id()
APP_PRODUCT_UUID      = new_id()
SOURCES_PHASE_UUID    = new_id()
RESOURCES_PHASE_UUID  = new_id()
FRAMEWORKS_PHASE_UUID = new_id()
DEBUG_CFG_UUID        = new_id()
RELEASE_CFG_UUID      = new_id()
PROJ_DEBUG_CFG_UUID   = new_id()
PROJ_RELEASE_CFG_UUID = new_id()
CFG_LIST_UUID         = new_id()
PROJ_CFG_LIST_UUID    = new_id()
INFOPLIST_UUID        = new_id()

swift_fr = [new_id() for _ in swift_files]
swift_bf = [new_id() for _ in swift_files]
res_fr   = [new_id() for _ in res_files]
res_bf   = [new_id() for _ in res_files]

def file_type(path):
    ext = os.path.splitext(path)[1].lower()
    return {'.swift':'sourcecode.swift','.mp3':'audio.mpeg','.ahap':'file',
            '.mp4':'com.apple.m4v-video','.png':'image.png',
            '.jpg':'image.jpeg','.jpeg':'image.jpeg'}.get(ext,'file')

# ── pbxproj sections ───────────────────────────────────────────────────────────
bf_section = ''
for i,f in enumerate(swift_files):
    n = os.path.basename(f)
    bf_section += f'    {swift_bf[i]} /* {n} in Sources */ = {{isa = PBXBuildFile; fileRef = {swift_fr[i]} /* {n} */; }};\n'
for i,f in enumerate(res_files):
    n = os.path.basename(f)
    bf_section += f'    {res_bf[i]} /* {n} in Resources */ = {{isa = PBXBuildFile; fileRef = {res_fr[i]} /* {n} */; }};\n'

fr_section = ''
for i,f in enumerate(swift_files):
    n = os.path.basename(f); ft = file_type(f)
    fr_section += f'    {swift_fr[i]} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {n}; sourceTree = "<group>"; }};\n'
for i,f in enumerate(res_files):
    n = os.path.basename(f); ft = file_type(f)
    fr_section += f'    {res_fr[i]} /* {n} */ = {{isa = PBXFileReference; lastKnownFileType = {ft}; path = {n}; sourceTree = "<group>"; }};\n'
fr_section += f'    {APP_PRODUCT_UUID} /* {project_name}.app */ = {{isa = PBXFileReference; explicitFileType = wrapper.application; includeInIndex = 0; path = {project_name}.app; sourceTree = BUILT_PRODUCTS_DIR; }};\n'
fr_section += f'    {INFOPLIST_UUID} /* Info.plist */ = {{isa = PBXFileReference; lastKnownFileType = text.plist.xml; path = Info.plist; sourceTree = "<group>"; }};\n'

src_children = ''.join(f'        {swift_fr[i]} /* {os.path.basename(f)} */,\n' for i,f in enumerate(swift_files))
src_children += f'        {INFOPLIST_UUID} /* Info.plist */,\n'
res_children = ''.join(f'        {res_fr[i]} /* {os.path.basename(f)} */,\n' for i,f in enumerate(res_files))

src_phase = ''.join(f'        {swift_bf[i]} /* {os.path.basename(f)} in Sources */,\n' for i,f in enumerate(swift_files))
res_phase = ''.join(f'        {res_bf[i]} /* {os.path.basename(f)} in Resources */,\n' for i,f in enumerate(res_files))

# ── Write project.pbxproj ──────────────────────────────────────────────────────
pbxproj = (
    '// !$*UTF8*$!\n'
    '{\n'
    '  archiveVersion = 1;\n'
    '  classes = {};\n'
    '  objectVersion = 56;\n'
    '  objects = {\n\n'
    '/* Begin PBXBuildFile section */\n'
    + bf_section +
    '/* End PBXBuildFile section */\n\n'
    '/* Begin PBXFileReference section */\n'
    + fr_section +
    '/* End PBXFileReference section */\n\n'
    '/* Begin PBXFrameworksBuildPhase section */\n'
    f'    {FRAMEWORKS_PHASE_UUID} = {{\n'
    '      isa = PBXFrameworksBuildPhase;\n'
    '      buildActionMask = 2147483647;\n'
    '      files = ();\n'
    '      runOnlyForDeploymentPostprocessing = 0;\n'
    '    };\n'
    '/* End PBXFrameworksBuildPhase section */\n\n'
    '/* Begin PBXGroup section */\n'
    f'    {MAIN_GROUP_UUID} = {{\n'
    '      isa = PBXGroup;\n'
    '      children = (\n'
    f'        {SOURCES_GROUP_UUID} /* Sources */,\n'
    f'        {RESOURCES_GROUP_UUID} /* Resources */,\n'
    f'        {PRODUCTS_GROUP_UUID} /* Products */,\n'
    '      );\n'
    '      sourceTree = "<group>";\n'
    '    };\n'
    f'    {PRODUCTS_GROUP_UUID} /* Products */ = {{\n'
    '      isa = PBXGroup;\n'
    f'      children = ({APP_PRODUCT_UUID} /* {project_name}.app */);\n'
    '      name = Products;\n'
    '      sourceTree = "<group>";\n'
    '    };\n'
    f'    {SOURCES_GROUP_UUID} /* Sources */ = {{\n'
    '      isa = PBXGroup;\n'
    '      children = (\n'
    + src_children +
    '      );\n'
    '      name = Sources;\n'
    '      path = Sources;\n'
    '      sourceTree = "<group>";\n'
    '    };\n'
    f'    {RESOURCES_GROUP_UUID} /* Resources */ = {{\n'
    '      isa = PBXGroup;\n'
    '      children = (\n'
    + res_children +
    '      );\n'
    '      name = Resources;\n'
    '      path = Resources;\n'
    '      sourceTree = "<group>";\n'
    '    };\n'
    '/* End PBXGroup section */\n\n'
    '/* Begin PBXNativeTarget section */\n'
    f'    {TARGET_UUID} /* {project_name} */ = {{\n'
    '      isa = PBXNativeTarget;\n'
    f'      buildConfigurationList = {CFG_LIST_UUID};\n'
    '      buildPhases = (\n'
    f'        {SOURCES_PHASE_UUID} /* Sources */,\n'
    f'        {FRAMEWORKS_PHASE_UUID} /* Frameworks */,\n'
    f'        {RESOURCES_PHASE_UUID} /* Resources */,\n'
    '      );\n'
    '      buildRules = ();\n'
    '      dependencies = ();\n'
    f'      name = {project_name};\n'
    f'      productName = {project_name};\n'
    f'      productReference = {APP_PRODUCT_UUID} /* {project_name}.app */;\n'
    '      productType = "com.apple.product-type.application";\n'
    '    };\n'
    '/* End PBXNativeTarget section */\n\n'
    '/* Begin PBXProject section */\n'
    f'    {PROJECT_UUID} /* Project object */ = {{\n'
    '      isa = PBXProject;\n'
    '      attributes = {\n'
    '        BuildIndependentTargetsInParallel = 1;\n'
    '        LastSwiftUpdateCheck = 1500;\n'
    '        LastUpgradeCheck = 1500;\n'
    f'        TargetAttributes = {{ {TARGET_UUID} = {{ CreatedOnToolsVersion = 15.0; }}; }};\n'
    '      };\n'
    f'      buildConfigurationList = {PROJ_CFG_LIST_UUID};\n'
    '      compatibilityVersion = "Xcode 14.0";\n'
    '      developmentRegion = en;\n'
    '      hasScannedForEncodings = 0;\n'
    '      knownRegions = (en, Base);\n'
    f'      mainGroup = {MAIN_GROUP_UUID};\n'
    f'      productRefGroup = {PRODUCTS_GROUP_UUID} /* Products */;\n'
    '      projectDirPath = "";\n'
    '      projectRoot = "";\n'
    f'      targets = ({TARGET_UUID} /* {project_name} */);\n'
    '    };\n'
    '/* End PBXProject section */\n\n'
    '/* Begin PBXResourcesBuildPhase section */\n'
    f'    {RESOURCES_PHASE_UUID} = {{\n'
    '      isa = PBXResourcesBuildPhase;\n'
    '      buildActionMask = 2147483647;\n'
    '      files = (\n'
    + res_phase +
    '      );\n'
    '      runOnlyForDeploymentPostprocessing = 0;\n'
    '    };\n'
    '/* End PBXResourcesBuildPhase section */\n\n'
    '/* Begin PBXSourcesBuildPhase section */\n'
    f'    {SOURCES_PHASE_UUID} = {{\n'
    '      isa = PBXSourcesBuildPhase;\n'
    '      buildActionMask = 2147483647;\n'
    '      files = (\n'
    + src_phase +
    '      );\n'
    '      runOnlyForDeploymentPostprocessing = 0;\n'
    '    };\n'
    '/* End PBXSourcesBuildPhase section */\n\n'
    '/* Begin XCBuildConfiguration section */\n'
    f'    {DEBUG_CFG_UUID} /* Debug */ = {{\n'
    '      isa = XCBuildConfiguration;\n'
    '      buildSettings = {\n'
    '        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;\n'
    '        CODE_SIGN_IDENTITY                    = "";\n'
    '        CODE_SIGNING_ALLOWED                  = NO;\n'
    '        CODE_SIGNING_REQUIRED                 = NO;\n'
    '        CURRENT_PROJECT_VERSION               = 1;\n'
    '        DEBUG_INFORMATION_FORMAT              = dwarf;\n'
    '        DEVELOPMENT_TEAM                      = "";\n'
    '        ENABLE_BITCODE                        = NO;\n'
    '        INFOPLIST_FILE                        = Sources/Info.plist;\n'
    '        IPHONEOS_DEPLOYMENT_TARGET            = 16.0;\n'
    '        MARKETING_VERSION                     = 1.0.0;\n'
    '        ONLY_ACTIVE_ARCH                      = NO;\n'
    f'        PRODUCT_BUNDLE_IDENTIFIER             = {bundle_id};\n'
    f'        PRODUCT_NAME                          = {project_name};\n'
    '        PROVISIONING_PROFILE_SPECIFIER        = "";\n'
    '        SWIFT_ACTIVE_COMPILATION_CONDITIONS   = DEBUG;\n'
    '        SWIFT_OPTIMIZATION_LEVEL              = "-Onone";\n'
    '        SWIFT_VERSION                         = 5.9;\n'
    '        TARGETED_DEVICE_FAMILY                = "1,2";\n'
    '        SKIP_INSTALL                          = NO;\n'
    '      };\n'
    '      name = Debug;\n'
    '    };\n'
    f'    {RELEASE_CFG_UUID} /* Release */ = {{\n'
    '      isa = XCBuildConfiguration;\n'
    '      buildSettings = {\n'
    '        ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES = YES;\n'
    '        CODE_SIGN_IDENTITY                    = "";\n'
    '        CODE_SIGNING_ALLOWED                  = NO;\n'
    '        CODE_SIGNING_REQUIRED                 = NO;\n'
    '        CURRENT_PROJECT_VERSION               = 1;\n'
    '        DEBUG_INFORMATION_FORMAT              = "dwarf-with-dsym";\n'
    '        DEVELOPMENT_TEAM                      = "";\n'
    '        ENABLE_BITCODE                        = NO;\n'
    '        INFOPLIST_FILE                        = Sources/Info.plist;\n'
    '        IPHONEOS_DEPLOYMENT_TARGET            = 16.0;\n'
    '        MARKETING_VERSION                     = 1.0.0;\n'
    '        ONLY_ACTIVE_ARCH                      = NO;\n'
    f'        PRODUCT_BUNDLE_IDENTIFIER             = {bundle_id};\n'
    f'        PRODUCT_NAME                          = {project_name};\n'
    '        PROVISIONING_PROFILE_SPECIFIER        = "";\n'
    '        SWIFT_ACTIVE_COMPILATION_CONDITIONS   = "";\n'
    '        SWIFT_OPTIMIZATION_LEVEL              = "-Owholemodule";\n'
    '        SWIFT_VERSION                         = 5.9;\n'
    '        TARGETED_DEVICE_FAMILY                = "1,2";\n'
    '        SKIP_INSTALL                          = NO;\n'
    '      };\n'
    '      name = Release;\n'
    '    };\n'
    f'    {PROJ_DEBUG_CFG_UUID} /* Debug */ = {{\n'
    '      isa = XCBuildConfiguration;\n'
    '      buildSettings = {\n'
    '        ALWAYS_SEARCH_USER_PATHS = NO;\n'
    '        CLANG_ENABLE_MODULES     = YES;\n'
    '        ENABLE_TESTABILITY       = YES;\n'
    '        GCC_OPTIMIZATION_LEVEL  = 0;\n'
    '        ONLY_ACTIVE_ARCH         = NO;\n'
    '        SDKROOT                  = iphoneos;\n'
    '      };\n'
    '      name = Debug;\n'
    '    };\n'
    f'    {PROJ_RELEASE_CFG_UUID} /* Release */ = {{\n'
    '      isa = XCBuildConfiguration;\n'
    '      buildSettings = {\n'
    '        ALWAYS_SEARCH_USER_PATHS = NO;\n'
    '        CLANG_ENABLE_MODULES     = YES;\n'
    '        SDKROOT                  = iphoneos;\n'
    '        VALIDATE_PRODUCT         = YES;\n'
    '      };\n'
    '      name = Release;\n'
    '    };\n'
    '/* End XCBuildConfiguration section */\n\n'
    '/* Begin XCConfigurationList section */\n'
    f'    {CFG_LIST_UUID} = {{\n'
    '      isa = XCConfigurationList;\n'
    f'      buildConfigurations = ({DEBUG_CFG_UUID} /* Debug */, {RELEASE_CFG_UUID} /* Release */);\n'
    '      defaultConfigurationIsVisible = 0;\n'
    '      defaultConfigurationName = Release;\n'
    '    };\n'
    f'    {PROJ_CFG_LIST_UUID} = {{\n'
    '      isa = XCConfigurationList;\n'
    f'      buildConfigurations = ({PROJ_DEBUG_CFG_UUID} /* Debug */, {PROJ_RELEASE_CFG_UUID} /* Release */);\n'
    '      defaultConfigurationIsVisible = 0;\n'
    '      defaultConfigurationName = Release;\n'
    '    };\n'
    '/* End XCConfigurationList section */\n\n'
    '  };\n'
    f'  rootObject = {PROJECT_UUID} /* Project object */;\n'
    '}\n'
)

pbxproj_path = os.path.join(xcodeproj, 'project.pbxproj')
open(pbxproj_path, 'w').write(pbxproj)
print(f'[init-py] project.pbxproj written ({os.path.getsize(pbxproj_path):,} bytes)')

# ── Write Info.plist ───────────────────────────────────────────────────────────
plist = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" '
    '"http://www.apple.com/DTDs/PropertyList-1.0.dtd">\n'
    '<plist version="1.0">\n'
    '<dict>\n'
    '  <key>CFBundleDisplayName</key>         <string>Custom Player</string>\n'
    f'  <key>CFBundleIdentifier</key>          <string>{bundle_id}</string>\n'
    f'  <key>CFBundleName</key>                <string>{project_name}</string>\n'
    '  <key>CFBundlePackageType</key>         <string>APPL</string>\n'
    '  <key>CFBundleShortVersionString</key>  <string>1.0.0</string>\n'
    '  <key>CFBundleVersion</key>             <string>1</string>\n'
    '  <key>LSRequiresIPhoneOS</key>          <true/>\n'
    '  <key>UILaunchStoryboardName</key>      <string></string>\n'
    '  <key>UIRequiresFullScreen</key>        <true/>\n'
    '  <key>UIStatusBarStyle</key>            <string>UIStatusBarStyleLightContent</string>\n'
    '  <key>UIViewControllerBasedStatusBarAppearance</key> <false/>\n'
    '  <key>NSMicrophoneUsageDescription</key><string>This app does not use the microphone.</string>\n'
    '  <key>UIBackgroundModes</key>\n'
    '  <array><string>audio</string></array>\n'
    '  <key>UISupportedInterfaceOrientations</key>\n'
    '  <array><string>UIInterfaceOrientationPortrait</string></array>\n'
    '  <key>UISupportedInterfaceOrientations~ipad</key>\n'
    '  <array>\n'
    '    <string>UIInterfaceOrientationPortrait</string>\n'
    '    <string>UIInterfaceOrientationPortraitUpsideDown</string>\n'
    '    <string>UIInterfaceOrientationLandscapeLeft</string>\n'
    '    <string>UIInterfaceOrientationLandscapeRight</string>\n'
    '  </array>\n'
    '  <key>NSAppTransportSecurity</key>\n'
    '  <dict><key>NSAllowsArbitraryLoads</key><false/></dict>\n'
    '</dict>\n'
    '</plist>\n'
)
plist_path = os.path.join(sources_dir, 'Info.plist')
open(plist_path, 'w').write(plist)
print(f'[init-py] Info.plist written')

# ── Write .xcscheme ────────────────────────────────────────────────────────────
scheme_xml = (
    '<?xml version="1.0" encoding="UTF-8"?>\n'
    '<Scheme LastUpgradeVersion="1500" version="1.7">\n'
    '  <BuildAction parallelizeBuildables="YES" buildImplicitDependencies="YES">\n'
    '    <BuildActionEntries>\n'
    '      <BuildActionEntry buildForTesting="YES" buildForRunning="YES" buildForProfiling="YES" buildForArchiving="YES" buildForAnalyzing="YES">\n'
    '        <BuildableReference\n'
    '           BuildableIdentifier = "primary"\n'
    f'           BlueprintIdentifier = "{TARGET_UUID}"\n'
    f'           BuildableName       = "{project_name}.app"\n'
    f'           BlueprintName       = "{project_name}"\n'
    f'           ReferencedContainer = "container:{project_name}.xcodeproj">\n'
    '        </BuildableReference>\n'
    '      </BuildActionEntry>\n'
    '    </BuildActionEntries>\n'
    '  </BuildAction>\n'
    '  <TestAction buildConfiguration="Debug" selectedDebuggerIdentifier="" selectedLauncherIdentifier="Xcode.IDEFoundation.Launcher.PosixSpawn" shouldUseLaunchSchemeArgsEnv="YES" codeCoverageEnabled="NO">\n'
    '    <Testables/>\n'
    '  </TestAction>\n'
    '  <LaunchAction buildConfiguration="Debug" selectedDebuggerIdentifier="Xcode.DebuggerFoundation.Debugger.LLDB" selectedLauncherIdentifier="Xcode.DebuggerFoundation.Launcher.LLDB" launchStyle="0" useCustomWorkingDirectory="NO" ignoresPersistentStateOnLaunch="NO" debugDocumentVersioning="YES" debugServiceExtension="internal" allowLocationSimulation="YES">\n'
    '    <BuildableProductRunnable runnableDebuggingMode="0">\n'
    '      <BuildableReference\n'
    '         BuildableIdentifier = "primary"\n'
    f'         BlueprintIdentifier = "{TARGET_UUID}"\n'
    f'         BuildableName       = "{project_name}.app"\n'
    f'         BlueprintName       = "{project_name}"\n'
    f'         ReferencedContainer = "container:{project_name}.xcodeproj">\n'
    '      </BuildableReference>\n'
    '    </BuildableProductRunnable>\n'
    '  </LaunchAction>\n'
    '  <ProfileAction buildConfiguration="Release" shouldUseLaunchSchemeArgsEnv="YES" savedToolIdentifier="" useCustomWorkingDirectory="NO" debugDocumentVersioning="YES">\n'
    '    <BuildableProductRunnable runnableDebuggingMode="0">\n'
    '      <BuildableReference\n'
    '         BuildableIdentifier = "primary"\n'
    f'         BlueprintIdentifier = "{TARGET_UUID}"\n'
    f'         BuildableName       = "{project_name}.app"\n'
    f'         BlueprintName       = "{project_name}"\n'
    f'         ReferencedContainer = "container:{project_name}.xcodeproj">\n'
    '      </BuildableReference>\n'
    '    </BuildableProductRunnable>\n'
    '  </ProfileAction>\n'
    '  <AnalyzeAction buildConfiguration="Debug"/>\n'
    f'  <ArchiveAction buildConfiguration="Release" revealArchiveInOrganizer="YES" customArchiveName="{project_name}"/>\n'
    '</Scheme>\n'
)
scheme_path = os.path.join(xcodeproj, 'xcshareddata', 'xcschemes', f'{scheme_name}.xcscheme')
open(scheme_path, 'w').write(scheme_xml)
print(f'[init-py] Scheme written: {scheme_path}')
print('[init-py] All project files generated successfully')
PYEOF

# ── 5. Validate ───────────────────────────────────────────────────────────────
echo ""
echo "[init] Project structure:"
find "$XCODEPROJ_DIR" -type f | sort
echo ""
echo "[init] Validating with xcodebuild -list..."
xcodebuild -project "$XCODEPROJ_DIR" -list
echo ""
echo "[init] build_init.sh v5 complete"
