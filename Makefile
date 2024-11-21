
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

# Values with defaults
IOS_DEVICE_NAME ?= iPhone 15
# If OS version is not specified, uses the first device name match in the list of available simulators
IOS_VERSION ?= 
ifeq ($(strip $(IOS_VERSION)),)
    IOS_DESTINATION = "platform=iOS Simulator,name=$(IOS_DEVICE_NAME)"
else
    IOS_DESTINATION = "platform=iOS Simulator,name=$(IOS_DEVICE_NAME),OS=$(IOS_VERSION)"
endif

TVOS_DEVICE_NAME ?= Apple TV
# If OS version is not specified, uses the first device name match in the list of available simulators
TVOS_VERSION ?=
ifeq ($(strip $(TVOS_VERSION)),)
	TVOS_DESTINATION = "platform=tvOS Simulator,name=$(TVOS_DEVICE_NAME)"
else
	TVOS_DESTINATION = "platform=tvOS Simulator,name=$(TVOS_DEVICE_NAME),OS=$(TVOS_VERSION)"
endif

clean-derived-data:
	@if [ -z "$(SCHEME)" ]; then \
		echo "Error: SCHEME variable is not set."; \
		exit 1; \
	fi; \
	if [ -z "$(DESTINATION)" ]; then \
		echo "Error: DESTINATION variable is not set."; \
		exit 1; \
	fi; \
	echo "Cleaning derived data for scheme: $(SCHEME) with destination: $(DESTINATION)"; \
	DERIVED_DATA_PATH=`xcodebuild -workspace $(PROJECT_NAME).xcworkspace -scheme "$(SCHEME)" -destination "$(DESTINATION)" -showBuildSettings | grep -m1 'BUILD_DIR' | awk '{print $$3}' | sed 's|/Build/Products||'`; \
	echo "DerivedData Path: $$DERIVED_DATA_PATH"; \
	\
	LOGS_TEST_DIR=$$DERIVED_DATA_PATH/Logs/Test; \
	echo "Logs Test Path: $$LOGS_TEST_DIR"; \
	\
	if [ -d "$$LOGS_TEST_DIR" ]; then \
		echo "Removing existing .xcresult files in $$LOGS_TEST_DIR"; \
		rm -rf "$$LOGS_TEST_DIR"/*.xcresult; \
	else \
		echo "Logs/Test directory does not exist. Skipping cleanup."; \
	fi;

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

ci-archive: ci-pod-install _archive

archive: pod-install _archive

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

test: unit-test-ios functional-test-ios unit-test-tvos functional-test-tvos

unit-test-ios:
	@echo "######################################################################"
	@echo "### Unit Testing iOS"
	@echo "######################################################################"
	@$(MAKE) clean-derived-data SCHEME=UnitTests DESTINATION=$(IOS_DESTINATION)
	xcodebuild test -workspace $(PROJECT_NAME).xcworkspace -scheme "UnitTests" -destination $(IOS_DESTINATION) -enableCodeCoverage YES ADB_SKIP_LINT=YES

functional-test-ios:
	@echo "######################################################################"
	@echo "### Functional Testing iOS"
	@echo "######################################################################"
	@$(MAKE) clean-derived-data SCHEME=FunctionalTests DESTINATION=$(IOS_DESTINATION)
	xcodebuild test -workspace $(PROJECT_NAME).xcworkspace -scheme "FunctionalTests" -destination $(IOS_DESTINATION) -enableCodeCoverage YES ADB_SKIP_LINT=YES

unit-test-tvos:
	@echo "######################################################################"
	@echo "### Unit Testing tvOS"
	@echo "######################################################################"
	@$(MAKE) clean-derived-data SCHEME=UnitTests DESTINATION=$(TVOS_DESTINATION)
	xcodebuild test -workspace $(PROJECT_NAME).xcworkspace -scheme "UnitTests" -destination $(TVOS_DESTINATION) -enableCodeCoverage YES ADB_SKIP_LINT=YES

functional-test-tvos:
	@echo "######################################################################"
	@echo "### Functional Testing tvOS"
	@echo "######################################################################"
	@$(MAKE) clean-derived-data SCHEME=FunctionalTests DESTINATION=$(TVOS_DESTINATION)
	xcodebuild test -workspace $(PROJECT_NAME).xcworkspace -scheme "FunctionalTests" -destination $(TVOS_DESTINATION) -enableCodeCoverage YES ADB_SKIP_LINT=YES

install-githook:
	git config core.hooksPath .githooks

lint-autocorrect:
	./Pods/SwiftLint/swiftlint --fix

lint:
	./Pods/SwiftLint/swiftlint lint Sources SampleApps/$(APP_NAME)

test-SPM-integration:
	sh ./Script/test-SPM.sh

test-podspec:
	sh ./Script/test-podspec.sh
 