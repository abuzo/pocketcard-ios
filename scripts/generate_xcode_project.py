#!/usr/bin/env python3
"""Deterministically regenerate the checked-in Xcode project. Python standard library only."""
from __future__ import annotations

import argparse
import hashlib
import json
from pathlib import Path
import xml.etree.ElementTree as ET


def identifier(label: str) -> str:
    return hashlib.sha1(label.encode()).hexdigest()[:24].upper()


def serialize(value: object, level: int = 0) -> str:
    tab = '\t' * level
    if isinstance(value, dict):
        body = ''.join(f'{tab}\t{json.dumps(str(k))} = {serialize(v, level+1)};\n' for k, v in value.items())
        return '{\n' + body + tab + '}'
    if isinstance(value, list):
        return '(\n' + ''.join(f'{tab}\t{serialize(v, level+1)},\n' for v in value) + tab + ')'
    return json.dumps(str(value), ensure_ascii=False)


def build_project(root: Path) -> tuple[str, dict]:
    objects: dict[str, dict] = {}
    def obj(key: str, isa: str, **fields) -> str:
        uid = identifier(key)
        if uid in objects:
            raise ValueError(f'Duplicate object: {key}')
        objects[uid] = dict(isa=isa, **fields)
        return uid
    def file(path: str, type_: str) -> str:
        return obj('file:' + path, 'PBXFileReference', lastKnownFileType=type_, path=path, sourceTree='<group>')
    def phase(key: str, isa: str, files: list[str]) -> str:
        return obj(key, isa, buildActionMask=2147483647, files=files, runOnlyForDeploymentPostprocessing=0)
    def build(key: str, file_id: str) -> str:
        return obj('build:' + key, 'PBXBuildFile', fileRef=file_id)
    app_sources = []; test_sources = []; group_files = []
    for path in sorted((root / 'ios').glob('PocketCard*/*.swift')):
        rel = path.relative_to(root / 'ios').as_posix()
        ref = file(rel, 'sourcecode.swift'); group_files.append(ref)
        (test_sources if path.parent.name == 'PocketCardTests' else app_sources).append(build(rel, ref))
    resource_builds = []
    for path, kind in [('PocketCard/Assets.xcassets', 'folder.assetcatalog'),
                       ('PocketCard/PrivacyInfo.xcprivacy', 'text.xml')]:
        ref = file(path, kind); group_files.append(ref); resource_builds.append(build(path,ref))
    for path, kind in [('PocketCard/Info.plist', 'text.plist.xml'),
                       ('PocketCard/PocketCard.entitlements', 'text.plist.entitlements'),
                       ('Local.xcconfig.example', 'text.xcconfig')]:
        group_files.append(file(path,kind))
    base = file('Configurations/Base.xcconfig', 'text.xcconfig'); group_files.append(base)
    product_app = obj('product:app','PBXFileReference',explicitFileType='wrapper.application',includeInIndex=0,
                      path='PocketCard.app',sourceTree='BUILT_PRODUCTS_DIR')
    product_tests = obj('product:tests','PBXFileReference',explicitFileType='wrapper.cfbundle',includeInIndex=0,
                        path='PocketCardTests.xctest',sourceTree='BUILT_PRODUCTS_DIR')
    products = obj('group:products','PBXGroup',children=[product_app,product_tests],name='Products',sourceTree='<group>')
    main_group = obj('group:main','PBXGroup',children=group_files+[products],sourceTree='<group>')
    package = obj('package:core','XCLocalSwiftPackageReference',relativePath='..')
    app_dep = obj('product-dependency:app','XCSwiftPackageProductDependency',package=package,productName='PocketCardCore')
    test_dep = obj('product-dependency:tests','XCSwiftPackageProductDependency',package=package,productName='PocketCardCore')
    app_link = obj('build:app-package','PBXBuildFile',productRef=app_dep)
    test_link = obj('build:tests-package','PBXBuildFile',productRef=test_dep)
    app_phases = [phase('phase:app-sources','PBXSourcesBuildPhase',app_sources),
                  phase('phase:app-frameworks','PBXFrameworksBuildPhase',[app_link]),
                  phase('phase:app-resources','PBXResourcesBuildPhase',resource_builds)]
    test_phases = [phase('phase:tests-sources','PBXSourcesBuildPhase',test_sources),
                   phase('phase:tests-frameworks','PBXFrameworksBuildPhase',[test_link]),
                   phase('phase:tests-resources','PBXResourcesBuildPhase',[])]
    def configs(key: str, shared: dict, debug: dict | None = None, release: dict | None = None, config_file=None) -> str:
        refs = []
        for name, extra in [('Debug',debug or {}),('Release',release or {})]:
            fields = dict(buildSettings={**shared,**extra},name=name)
            if config_file: fields['baseConfigurationReference'] = config_file
            refs.append(obj(f'config:{key}:{name}','XCBuildConfiguration',**fields))
        return obj('config-list:' + key,'XCConfigurationList',buildConfigurations=refs,
                   defaultConfigurationIsVisible=0,defaultConfigurationName='Release')
    project_configs = configs('project', dict(
        ALWAYS_SEARCH_USER_PATHS='NO', CLANG_ENABLE_MODULES='YES', CLANG_ENABLE_OBJC_ARC='YES',
        CLANG_WARN_DOCUMENTATION_COMMENTS='YES', CLANG_WARN_UNREACHABLE_CODE='YES',
        GCC_C_LANGUAGE_STANDARD='gnu17', GCC_WARN_UNUSED_VARIABLE='YES',
        IPHONEOS_DEPLOYMENT_TARGET='17.0', SDKROOT='iphoneos', SWIFT_VERSION='5.0',
        SWIFT_STRICT_CONCURRENCY='targeted', CODE_SIGN_STYLE='Automatic',
        ENABLE_USER_SCRIPT_SANDBOXING='YES'),
        dict(DEBUG_INFORMATION_FORMAT='dwarf', ENABLE_TESTABILITY='YES', GCC_OPTIMIZATION_LEVEL=0,
             ONLY_ACTIVE_ARCH='YES', SWIFT_ACTIVE_COMPILATION_CONDITIONS='DEBUG $(inherited)', SWIFT_OPTIMIZATION_LEVEL='-Onone'),
        dict(DEBUG_INFORMATION_FORMAT='dwarf-with-dsym', SWIFT_COMPILATION_MODE='wholemodule',
             SWIFT_OPTIMIZATION_LEVEL='-O', VALIDATE_PRODUCT='YES'), config_file=base)
    app_configs = configs('app',dict(
        PRODUCT_NAME='$(TARGET_NAME)', PRODUCT_MODULE_NAME='PocketCard',
        PRODUCT_BUNDLE_IDENTIFIER='$(POCKETCARD_BUNDLE_ID)', CODE_SIGN_ENTITLEMENTS='$(PC_APP_ENTITLEMENTS)',
        GENERATE_INFOPLIST_FILE='NO', INFOPLIST_FILE='PocketCard/Info.plist',
        ASSETCATALOG_COMPILER_APPICON_NAME='AppIcon', TARGETED_DEVICE_FAMILY='1',
        SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO',
        SUPPORTS_MAC_DESIGNED_FOR_IPHONE_IPAD='NO',
        LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks'],
        MARKETING_VERSION='0.1.0', CURRENT_PROJECT_VERSION='1'))
    tests_configs = configs('tests',dict(
        PRODUCT_NAME='$(TARGET_NAME)',PRODUCT_BUNDLE_IDENTIFIER='$(POCKETCARD_BUNDLE_ID).tests',
        GENERATE_INFOPLIST_FILE='YES',TARGETED_DEVICE_FAMILY='1',
        SUPPORTED_PLATFORMS='iphoneos iphonesimulator', SUPPORTS_MACCATALYST='NO',
        BUNDLE_LOADER='$(TEST_HOST)', TEST_HOST='$(BUILT_PRODUCTS_DIR)/PocketCard.app/PocketCard',
        TEST_TARGET_NAME='PocketCard', LD_RUNPATH_SEARCH_PATHS=['$(inherited)','@executable_path/Frameworks','@loader_path/Frameworks']))
    app_target = obj('target:app','PBXNativeTarget',buildConfigurationList=app_configs,buildPhases=app_phases,
                     buildRules=[],dependencies=[],name='PocketCard',packageProductDependencies=[app_dep],
                     productName='PocketCard',productReference=product_app,productType='com.apple.product-type.application')
    proxy = obj('proxy:app','PBXContainerItemProxy',containerPortal=identifier('project'),proxyType=1,
                remoteGlobalIDString=app_target,remoteInfo='PocketCard')
    dependency = obj('dependency:app','PBXTargetDependency',target=app_target,targetProxy=proxy)
    tests_target = obj('target:tests','PBXNativeTarget',buildConfigurationList=tests_configs,buildPhases=test_phases,
                       buildRules=[],dependencies=[dependency],name='PocketCardTests',packageProductDependencies=[test_dep],
                       productName='PocketCardTests',productReference=product_tests,productType='com.apple.product-type.bundle.unit-test')
    project = obj('project','PBXProject',attributes=dict(BuildIndependentTargetsInParallel='YES',LastUpgradeCheck='1600',
                    TargetAttributes={app_target:{'CreatedOnToolsVersion':'16.0'},
                                      tests_target:{'CreatedOnToolsVersion':'16.0','TestTargetID':app_target}}),
                  buildConfigurationList=project_configs,compatibilityVersion='Xcode 14.0',
                  developmentRegion='ru',hasScannedForEncodings=0,knownRegions=['ru','en','Base'],mainGroup=main_group,
                  packageReferences=[package],productRefGroup=products,projectDirPath='',projectRoot='',targets=[app_target,tests_target])
    graph = dict(archiveVersion=1,classes={},objectVersion=56,objects=dict(sorted(objects.items())),rootObject=project)
    return '// !$*UTF8*$!\n' + serialize(graph) + '\n', graph


def scheme_xml() -> bytes:
    root = ET.Element('Scheme', LastUpgradeVersion='1600', version='1.3')
    def ref(parent, target, product):
        ET.SubElement(parent,'BuildableReference',BuildableIdentifier='primary',BlueprintIdentifier=identifier('target:'+target),
                      BuildableName=product,BlueprintName='PocketCard' if target=='app' else 'PocketCardTests',
                      ReferencedContainer='container:PocketCard.xcodeproj')
    build = ET.SubElement(root,'BuildAction',parallelizeBuildables='YES',buildImplicitDependencies='YES')
    entries=ET.SubElement(build,'BuildActionEntries')
    for target,product in [('app','PocketCard.app'),('tests','PocketCardTests.xctest')]:
        entry=ET.SubElement(entries,'BuildActionEntry',buildForTesting='YES',buildForRunning='YES' if target=='app' else 'NO',
                            buildForProfiling='YES' if target=='app' else 'NO',buildForArchiving='YES' if target=='app' else 'NO',
                            buildForAnalyzing='YES')
        ref(entry,target,product)
    test=ET.SubElement(root,'TestAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',
                       selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',shouldUseLaunchSchemeArgsEnv='YES')
    testables=ET.SubElement(test,'Testables'); entry=ET.SubElement(testables,'TestableReference',skipped='NO',parallelizable='NO');ref(entry,'tests','PocketCardTests.xctest')
    launch=ET.SubElement(root,'LaunchAction',buildConfiguration='Debug',selectedDebuggerIdentifier='Xcode.DebuggerFoundation.Debugger.LLDB',
                         selectedLauncherIdentifier='Xcode.IDEFoundation.Launcher.LLDB',launchStyle='0',useCustomWorkingDirectory='NO',
                         ignoresPersistentStateOnLaunch='NO',debugDocumentVersioning='YES',debugServiceExtension='internal',allowLocationSimulation='YES')
    ref(ET.SubElement(launch,'BuildableProductRunnable',runnableDebuggingMode='0'),'app','PocketCard.app')
    profile=ET.SubElement(root,'ProfileAction',buildConfiguration='Release',shouldUseLaunchSchemeArgsEnv='YES',savedToolIdentifier='',useCustomWorkingDirectory='NO',debugDocumentVersioning='YES')
    ref(ET.SubElement(profile,'BuildableProductRunnable',runnableDebuggingMode='0'),'app','PocketCard.app')
    ET.SubElement(root,'AnalyzeAction',buildConfiguration='Debug')
    ET.SubElement(root,'ArchiveAction',buildConfiguration='Release',revealArchiveInOrganizer='YES')
    ET.indent(root)
    return ET.tostring(root,encoding='utf-8',xml_declaration=True)+b'\n'


def main():
    parser=argparse.ArgumentParser(description=__doc__);parser.add_argument('--check',action='store_true');args=parser.parse_args()
    root=Path(__file__).resolve().parents[1]; content,_=build_project(root)
    project=root/'ios/PocketCard.xcodeproj'
    outputs={project/'project.pbxproj':content.encode(),project/'xcshareddata/xcschemes/PocketCard.xcscheme':scheme_xml()}
    if args.check:
        bad=[str(p.relative_to(root)) for p,data in outputs.items() if not p.is_file() or p.read_bytes()!=data]
        if bad: raise SystemExit('Project is stale. Run scripts/generate_xcode_project.py: '+', '.join(bad))
        print('Xcode project and shared scheme match the generator (not an iOS build).')
    else:
        for path,data in outputs.items():path.parent.mkdir(parents=True,exist_ok=True);path.write_bytes(data)
        print('Generated ios/PocketCard.xcodeproj')


if __name__=='__main__':main()
