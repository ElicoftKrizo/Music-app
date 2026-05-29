import ProjectDescription

// MARK: - Custom Player — Tuist Project Manifest
// Compatible with Tuist 4.x
// Run `tuist generate` to produce CustomPlayer.xcodeproj

let deploymentTargets = DeploymentTargets.iOS("16.0")

let infoPlistEntries: [String: Plist.Value] = [
    "CFBundleDisplayName": "Custom Player",
    "CFBundleShortVersionString": "1.0.0",
    "CFBundleVersion": "1",
    "UILaunchStoryboardName": "",
    "UISupportedInterfaceOrientations": [
        "UIInterfaceOrientationPortrait"
    ],
    "UISupportedInterfaceOrientations~ipad": [
        "UIInterfaceOrientationPortrait",
        "UIInterfaceOrientationPortraitUpsideDown",
        "UIInterfaceOrientationLandscapeLeft",
        "UIInterfaceOrientationLandscapeRight"
    ],
    "NSMicrophoneUsageDescription": "This app does not use the microphone.",
    "UIRequiresFullScreen": true,
    "UIStatusBarStyle": "UIStatusBarStyleLightContent",
    "UIViewControllerBasedStatusBarAppearance": false,
    "AVAudioSessionCategory": "AVAudioSessionCategoryPlayback",
    "UIBackgroundModes": ["audio"],
    "NSAppTransportSecurity": [
        "NSAllowsArbitraryLoads": false
    ]
]

let settings = Settings.settings(
    base: [
        "SWIFT_VERSION": "5.9",
        "IPHONEOS_DEPLOYMENT_TARGET": "16.0",
        "PRODUCT_BUNDLE_IDENTIFIER": "com.custom.player",
        "PRODUCT_NAME": "CustomPlayer",
        "TARGETED_DEVICE_FAMILY": "1,2",
        "ENABLE_BITCODE": false,
        "CODE_SIGNING_ALLOWED": false,
        "CODE_SIGNING_REQUIRED": false,
        "CODE_SIGN_IDENTITY": "",
        "PROVISIONING_PROFILE_SPECIFIER": "",
        "ALWAYS_EMBED_SWIFT_STANDARD_LIBRARIES": true,
        "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
        "ASSETCATALOG_COMPILER_APPICON_NAME": "AppIcon",
        "DEVELOPMENT_LANGUAGE": "en",
        "MTL_ENABLE_DEBUG_INFO": "INCLUDE_SOURCE",
    ],
    configurations: [
        .debug(
            name: "Debug",
            settings: [
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "DEBUG",
                "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                "ONLY_ACTIVE_ARCH": true,
            ],
            xcconfig: nil
        ),
        .release(
            name: "Release",
            settings: [
                "SWIFT_ACTIVE_COMPILATION_CONDITIONS": "",
                "DEBUG_INFORMATION_FORMAT": "dwarf-with-dsym",
                "ONLY_ACTIVE_ARCH": false,
                "SWIFT_OPTIMIZATION_LEVEL": "-Owholemodule",
            ],
            xcconfig: nil
        ),
    ],
    defaultSettings: .recommended
)

let appTarget = Target.target(
    name: "CustomPlayer",
    destinations: [.iPhone, .iPad],
    product: .app,
    bundleId: "com.custom.player",
    deploymentTargets: deploymentTargets,
    infoPlist: .extendingDefault(with: infoPlistEntries),
    sources: [
        SourceFileGlob(
            glob: "Sources/**/*.swift",
            excluding: [],
            compilerFlags: nil,
            codeGen: nil
        )
    ],
    resources: [
        ResourceFileElement.glob(
            pattern: "Resources/**",
            tags: [],
            inclusionCondition: nil
        )
    ],
    entitlements: nil,
    scripts: [],
    dependencies: [],
    settings: settings,
    coreDataModels: [],
    environment: [:],
    launchArguments: [],
    additionalFiles: []
)

let project = Project(
    name: "CustomPlayer",
    organizationName: "com.custom",
    options: Project.Options.options(
        automaticSchemesOptions: .enabled(
            targetSchemesGrouping: .byNameSuffix(build: [], test: ["Tests"], run: []),
            codeCoverageEnabled: false,
            testingOptions: [],
            testLanguage: nil,
            testRegion: nil,
            testScreenCaptureFormat: .screenshots,
            runLanguage: nil,
            runRegion: nil
        ),
        disableBundleAccessors: false,
        disableShowEnvironmentVarsInScriptPhases: false,
        disableSynthesizedResourceAccessors: false,
        textSettings: .textSettings(
            usesTabs: nil,
            indentWidth: nil,
            tabWidth: nil,
            wrapsLines: nil
        )
    ),
    packages: [],
    settings: settings,
    targets: [appTarget],
    schemes: [
        Scheme.scheme(
            name: "CustomPlayer",
            shared: true,
            hidden: false,
            buildAction: BuildAction.buildAction(
                targets: [TargetReference(stringLiteral: "CustomPlayer")],
                preActions: [],
                postActions: [],
                runPostActionsOnFailure: false,
                findImplicitDependencies: true
            ),
            testAction: TestAction.targets(
                [],
                arguments: nil,
                configuration: .debug,
                attachDebugger: false,
                expandVariableFromTarget: nil,
                preActions: [],
                postActions: [],
                options: TestActionOptions.options(),
                diagnosticsOptions: .options(
                    addressSanitizerEnabled: false,
                    detectStackUseAfterReturnEnabled: false,
                    threadSanitizerEnabled: false,
                    mainThreadCheckerEnabled: false,
                    performanceAntipatternCheckerEnabled: false
                )
            ),
            runAction: RunAction.runAction(
                configuration: .debug,
                attachDebugger: true,
                customLLDBInitFile: nil,
                preActions: [],
                postActions: [],
                executable: TargetReference(stringLiteral: "CustomPlayer"),
                arguments: nil,
                options: RunActionOptions.options(),
                diagnosticsOptions: .options(
                    addressSanitizerEnabled: false,
                    detectStackUseAfterReturnEnabled: false,
                    threadSanitizerEnabled: false,
                    mainThreadCheckerEnabled: false,
                    performanceAntipatternCheckerEnabled: false
                ),
                expandVariableFromTarget: nil
            ),
            archiveAction: ArchiveAction.archiveAction(
                configuration: .release,
                revealArchiveInOrganizer: true,
                customArchiveName: "CustomPlayer",
                preActions: [],
                postActions: []
            ),
            profileAction: ProfileAction.profileAction(
                configuration: .release,
                executable: TargetReference(stringLiteral: "CustomPlayer"),
                arguments: nil,
                preActions: [],
                postActions: [],
                options: ProfileActionOptions.options(
                    storeKitConfigurationPath: nil,
                    simulatedLocation: nil
                )
            ),
            analyzeAction: AnalyzeAction.analyzeAction(
                configuration: .debug
            )
        )
    ],
    additionalFiles: [],
    resourceSynthesizers: .default
)
