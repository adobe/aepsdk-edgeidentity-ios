
export EXTENSION_NAME = AEPEdgeIdentity
export APP_NAME = TestApp
PROJECT_NAME = $(EXTENSION_NAME)
TARGET_NAME_XCFRAMEWORK = $(EXTENSION_NAME).xcframework
SCHEME_NAME_XCFRAMEWORK = $(EXTENSION_NAME)XCF
ARCHIVE_BUILD_SETTINGS ?=

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
	xcrun swift package resolve

setup-tools: install-githook

clean:
	rm -rf build

clean-ios-test-files:
	rm -rf iosresults.xcresult

clean-tvos-test-files:
	rm -rf tvosresults.xcresult
	
open:
	open $(PROJECT_NAME).xcworkspace

ci-archive: setup _archive

archive: setup _archive

zip:
	cd build && zip -r -X $(PROJECT_NAME).xcframework.zip $(PROJECT_NAME).xcframework/
	xcrun swift package compute-checksum build/$(PROJECT_NAME).xcframework.zip

build-ios:
	@echo "######################################################################"
	@echo "### Building iOS archive"
	@echo "######################################################################"
	xcodebuild archive -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/ios.xcarchive" -sdk iphoneos -destination 'generic/platform=iOS' SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO ADB_SKIP_LINT=YES $(ARCHIVE_BUILD_SETTINGS)
	xcodebuild archive -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/ios_simulator.xcarchive" -sdk iphonesimulator -destination 'generic/platform=iOS Simulator' SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO ADB_SKIP_LINT=YES $(ARCHIVE_BUILD_SETTINGS)

build-tvos:
	@echo "######################################################################"
	@echo "### Building tvOS archive"
	@echo "######################################################################"
	xcodebuild archive -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/tvos.xcarchive" -sdk appletvos -destination 'generic/platform=tvOS' SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO ADB_SKIP_LINT=YES $(ARCHIVE_BUILD_SETTINGS)
	xcodebuild archive -project $(PROJECT_NAME).xcodeproj -scheme $(SCHEME_NAME_XCFRAMEWORK) -archivePath "./build/tvos_simulator.xcarchive" -sdk appletvsimulator -destination 'generic/platform=tvOS Simulator' SKIP_INSTALL=NO BUILD_LIBRARY_FOR_DISTRIBUTION=YES CODE_SIGNING_ALLOWED=NO ADB_SKIP_LINT=YES $(ARCHIVE_BUILD_SETTINGS)

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

_archive: clean
	$(MAKE) build-ios build-tvos
	@echo "######################################################################"
	@echo "### Generating iOS and tvOS Frameworks for $(PROJECT_NAME)"
	@echo "######################################################################"
	xcodebuild -create-xcframework -framework "$(IOS_SIMULATOR_ARCHIVE_PATH)$(PROJECT_NAME).framework" -debug-symbols "$(IOS_SIMULATOR_ARCHIVE_DSYM_PATH)$(PROJECT_NAME).framework.dSYM" \
	-framework "$(TVOS_SIMULATOR_ARCHIVE_PATH)$(PROJECT_NAME).framework" -debug-symbols "$(TVOS_SIMULATOR_ARCHIVE_DSYM_PATH)$(PROJECT_NAME).framework.dSYM" \
	-framework "$(IOS_ARCHIVE_PATH)$(PROJECT_NAME).framework" -debug-symbols "$(IOS_ARCHIVE_DSYM_PATH)$(PROJECT_NAME).framework.dSYM" \
	-framework "$(TVOS_ARCHIVE_PATH)$(PROJECT_NAME).framework" -debug-symbols "$(TVOS_ARCHIVE_DSYM_PATH)$(PROJECT_NAME).framework.dSYM" -output ./build/$(PROJECT_NAME).xcframework

test: test-SPM-integration

install-githook:
	git config core.hooksPath .githooks

lint-autocorrect:
	swiftlint --fix

lint:
	swiftlint lint Sources SampleApps/$(APP_NAME)

test-SPM-integration:
	sh ./Script/test-SPM.sh
 