
export EXTENSION_NAME = AEPEdgeIdentity
export APP_NAME = TestApp
PROJECT_NAME = $(EXTENSION_NAME)
TARGET_NAME_XCFRAMEWORK = $(EXTENSION_NAME).xcframework
SCHEME_NAME_XCFRAMEWORK = $(EXTENSION_NAME)XCF

CURR_DIR := ${CURDIR}
IOS_SIMULATOR_ARCHIVE_PATH = $(CURR_DIR)/build/ios_simulator.xcarchive/Products/Library/Frameworks/
IOS_SIMULATOR_ARCHIVE_DSYM_PATH = $(CURR_DIR)/build/ios_simulator.xcarchive/dSYMs/
IOS_ARCHIVE_PATH = $(CURR_DIR)/build/ios.xcarchive/Products/Library/Frameworks/
IOS_ARCHIVE_DSYM_PATH = $(CURR_DIR)/build/ios.xcarchive/dSYMs/
TVOS_SIMULATOR_ARCHIVE_PATH = $(CURR_DIR)/build/tvos_simulator.xcarchive/Products/Library/Frameworks/
TVOS_SIMULATOR_ARCHIVE_DSYM_PATH = $(CURR_DIR)/build/tvos_simulator.xcarchive/dSYMs/
TVOS_ARCHIVE_PATH = $(CURR_DIR)/build/tvos.xcarchive/Products/Library/Frameworks/
TVOS_ARCHIVE_DSYM_PATH = $(CURR_DIR)/build/tvos.xcarchive/dSYMs/

TEST_APP_IOS_SCHEME = TestApp
TEST_APP_IOS_OBJC_SCHEME = TestAppObjC
TEST_APP_TVOS_SCHEME = TestApptvOS

setup:
	pod install
	cd SampleApps/$(APP_NAME) && pod install

setup-tools: install-githook

clean:
	rm -rf build

clean-ios-test-files:
	rm -rf iosresults.xcresult

clean-tvos-test-files:
	rm -rf tvosresults.xcresult
pod-install:
	pod install --repo-update
	cd SampleApps/$(APP_NAME) && pod install --repo-update

open:
	open $(PROJECT_NAME).xcworkspace

pod-repo-update:
	pod repo update
	cd SampleApps/$(APP_NAME) && pod repo update

pod-update: pod-repo-update
	pod update
	cd SampleApps/$(APP_NAME) && pod update

ci-pod-install:
	bundle exec pod install --repo-update
	cd SampleApps/$(APP_NAME) && bundle exec pod install --repo-update

ci-archive: ci-pod-update _archive

archive: pod-update _archive

zip:
	cd build && zip -r -X $(PROJECT_NAME).xcframework.zip $(PROJECT_NAME).xcframework/
	swift package compute-checksum build/$(PROJECT_NAME).xcframework.zip

build-ios:
	@echo "######################################################################"
	@echo "### Building iOS archive"
	@echo "######################################################################"
	xcodebuild archive -workspace $(PROJECT_NAME).xcworkspace -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/ios.xcarchive" -sdk iphoneos -destination="iOS" SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES ADB_SKIP_LINT=YES
	xcodebuild archive -workspace $(PROJECT_NAME).xcworkspace -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/ios_simulator.xcarchive" -sdk iphonesimulator -destination="iOS Simulator" SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES ADB_SKIP_LINT=YES

build-tvos:
	@echo "######################################################################"
	@echo "### Building tvOS archive"
	@echo "######################################################################"
	xcodebuild archive -workspace $(PROJECT_NAME).xcworkspace -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/tvos.xcarchive" -sdk appletvos -destination="tvOS" SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES ADB_SKIP_LINT=YES
	xcodebuild archive -workspace $(PROJECT_NAME).xcworkspace -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/tvos_simulator.xcarchive" -sdk appletvsimulator -destination="tvOS Simulator" SKIP_INSTALL=NO BUILD_LIBRARIES_FOR_DISTRIBUTION=YES ADB_SKIP_LINT=YES

build-app: setup
	@echo "######################################################################"
	@echo "### Building $(TEST_APP_IOS_SCHEME)"
	@echo "######################################################################"
	xcodebuild clean build -workspace $(PROJECT_NAME).xcworkspace -scheme $(TEST_APP_IOS_SCHEME) -destination 'generic/platform=iOS Simulator'
	
	@echo "######################################################################"
	@echo "### Building $(TEST_APP_IOS_OBJC_SCHEME)"
	@echo "######################################################################"
	xcodebuild clean build -workspace $(PROJECT_NAME).xcworkspace -scheme $(TEST_APP_IOS_OBJC_SCHEME) -destination 'generic/platform=iOS Simulator'

	@echo "######################################################################"
	@echo "### Building $(TEST_APP_TVOS_SCHEME)"
	@echo "######################################################################"
	xcodebuild clean build -workspace $(PROJECT_NAME).xcworkspace -scheme $(TEST_APP_TVOS_SCHEME) -destination 'generic/platform=tvOS Simulator'

_archive: clean build-ios build-tvos
	@echo "######################################################################"
	@echo "### Generating iOS and tvOS Frameworks for $(PROJECT_NAME)"
	@echo "######################################################################"
	xcodebuild -create-xcframework -framework $(IOS_SIMULATOR_ARCHIVE_PATH)$(PROJECT_NAME).framework -debug-symbols $(IOS_SIMULATOR_ARCHIVE_DSYM_PATH)$(PROJECT_NAME).framework.dSYM \
	-framework $(TVOS_SIMULATOR_ARCHIVE_PATH)$(PROJECT_NAME).framework -debug-symbols $(TVOS_SIMULATOR_ARCHIVE_DSYM_PATH)$(PROJECT_NAME).framework.dSYM \
	-framework $(IOS_ARCHIVE_PATH)$(PROJECT_NAME).framework -debug-symbols $(IOS_ARCHIVE_DSYM_PATH)$(PROJECT_NAME).framework.dSYM \
	-framework $(TVOS_ARCHIVE_PATH)$(PROJECT_NAME).framework -debug-symbols $(TVOS_ARCHIVE_DSYM_PATH)$(PROJECT_NAME).framework.dSYM -output ./build/$(PROJECT_NAME).xcframework

test: test-ios test-tvos

test-ios: clean-ios-test-files
	@echo "######################################################################"
	@echo "### Testing iOS"
	@echo "######################################################################"
	@echo "List of available shared Schemes in xcworkspace"
	xcodebuild -workspace $(PROJECT_NAME).xcworkspace -list
	final_scheme=""; \
	if xcodebuild -workspace $(PROJECT_NAME).xcworkspace -list | grep -q "($(PROJECT_NAME) project)"; \
	then \
	   final_scheme="$(EXTENSION_NAME) ($(PROJECT_NAME) project)" ; \
	   echo $$final_scheme ; \
	else \
	   final_scheme="$(EXTENSION_NAME)" ; \
	   echo $$final_scheme ; \
	fi; \
	xcodebuild test -workspace $(PROJECT_NAME).xcworkspace -scheme "$$final_scheme" -destination 'platform=iOS Simulator,name=iPhone 14' -derivedDataPath build/out -resultBundlePath iosresults.xcresult -enableCodeCoverage YES

test-tvos: clean-tvos-test-files
	@echo "######################################################################"
	@echo "### Testing tvOS"
	@echo "######################################################################"
	@echo "List of available shared Schemes in xcworkspace"
	xcodebuild -workspace $(PROJECT_NAME).xcworkspace -list
	final_scheme=""; \
	if xcodebuild -workspace $(PROJECT_NAME).xcworkspace -list | grep -q "($(PROJECT_NAME) project)"; \
	then \
	   final_scheme="$(EXTENSION_NAME) ($(PROJECT_NAME) project)" ; \
	   echo $$final_scheme ; \
	else \
	   final_scheme="$(EXTENSION_NAME)" ; \
	   echo $$final_scheme ; \
	fi; \
	xcodebuild test -workspace $(PROJECT_NAME).xcworkspace -scheme "$$final_scheme" -destination 'platform=tvOS Simulator,name=Apple TV' -derivedDataPath build/out -resultBundlePath tvosresults.xcresult -enableCodeCoverage YES

install-githook:
	git config core.hooksPath .githooks

lint-autocorrect:
	./Pods/SwiftLint/swiftlint --fix

lint:
	./Pods/SwiftLint/swiftlint lint Sources SampleApps/$(APP_NAME)

# make check-version VERSION=4.0.0
check-version:
	sh ./Script/version.sh $(VERSION)

test-SPM-integration:
	sh ./Script/test-SPM.sh

test-podspec:
	sh ./Script/test-podspec.sh
 