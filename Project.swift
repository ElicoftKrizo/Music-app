import ProjectDescription

// MARK: - CustomPlayer — Tuist Project Manifest
// Compatible with Tuist 4.x (any minor version)
// Fixes: SourceFileGlob initializer, removed environment:, removed
//        findImplicitDependencies:, removed ProfileActionOptions

let infoPlist: [String: Plist.Value] = [
    "CFBundleDisplayName":            "Custom Player",
    "CFBundleShortVersionString":     "1.0.0",
    "CFBundleVersion":                "1",
    "UILaunchStoryboardName":         "",
    "UISupportedInterfaceOrientations": [
        "UIInterfaceOrientationPortrait"
    ],
    "UISupportedInterfaceOrientations~ipad": [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight"
    ],
    "UIRequiresFullScreen":                     true,
    "UIStatusBarStyle":                         "UIStatusBarStyleLightContent",
    "UIViewControllerBasedStatusBarAppearance": false,
    "NSMicrophoneUsageDescription":             "This app does not use the microphone.",
    "UIBackgroundModes":                        ["audio"],
    "AVAudioSessionCategory":                   "AVAudioSessionCategoryPlayback",
    "NSAppTransportSecurity": [
        "NSAllowsArbitraryLoads": false
    ]
]

let baseSettings: SettingsDictionary = [
    "SWIFT_VERSION":                        "5.9",
    "IPHONEOS_DEPLOYMENT_TARGET":           "16.0",
    "PRODUCT_BUNDLE_IDENTIFIER":            "com.custom.player",
    "PRODUCT_NAME":                         "CustomPlayer",
    "TARGETED_DEVICE_FAMILY":               "1,2",
    "ENABLE_BITCODE":                       false,
    "CODE_SIGNING_ALLOWED":                 false,
    "CODE_SIGNING_REQUIRED":                false,
    "CODE_SIGN_IDENTITY":                   "",
    "PROVISIONING_PROFILE_SPECIFIER":       "",
    "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": true,
    "ASSETCATALOG_COMPILER_APPICON_NAME":   "AppIcon",
    "DEVELOPMENT_LANGUAGE":                 "en",
]

let settings = Settings.settings(
    base: baseSettings,
    configurations: [
        .debug(name: "Debug", settings: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
            "DEBUG_INFORMATION_FORMAT":            "dwarf-with-dsym",
            "ONLY_ACTIVE_ARCH":                    true,
        ]),
        .release(name: "Release", settings: [
            "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "",
            "DEBUG_INFORMATION_FORMAT":            "dwarf-with-dsym",
            "ONLY_ACTIVE_ARCH":                    false,
            "SWIFT_OPTIMIZATION_LEVEL":            "-Owholemodule",
        ]),
    ],
    defaultSettings: .recommended
)

let appTarget = Target.target(
    name: "CustomPlayer",
    destinations: [.iPhone, .iPad],
    product: .app,
    bundleId: "com.custom.player",
    deploymentTargets: .iOS("16.0"),
    infoPlist: .extendingDefault(with: infoPlist),
    sources: ["Sources/**/*.swift"],
    resources: ["Resources/**"],
    entitlements: nil,
    scripts: [],
    dependencies: [],
    settings: settings,
    coreDataModels: [],
    launchArguments: [],
    additionalFiles: []
)

let project = Project(
    name: "CustomPlayer",
    organizationName: "com.custom",
    options: .options(
        automaticSchemesOptions: .disabled,
        disableBundleAccessors: false,
        disableSynthesizedResourceAccessors: false
    ),
    packages: [],
    settings: settings,
    targets: [appTarget],
    schemes: [
        .scheme(
            name: "CustomPlayer",
            shared: true,
            buildAction: .buildAction(targets: ["CustomPlayer"]),
            testAction: nil,
            runAction: .runAction(
                configuration: .debug,
                executable: "CustomPlayer"
            ),
            archiveAction: .archiveAction(
                configuration: .release,
                revealArchiveInOrganizer: true,
                customArchiveName: "CustomPlayer"
            ),
            profileAction: .profileAction(
                configuration: .release,
                executable: "CustomPlayer"
            ),
            analyzeAction: .analyzeAction(configuration: .debug)
        )
    ],
    additionalFiles: [],
    resourceSynthesizers: .default
)
