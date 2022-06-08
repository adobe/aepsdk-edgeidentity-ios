//
// Copyright 2021 Adobe. All rights reserved.
// This file is licensed to you under the Apache License, Version 2.0 (the "License");
// you may not use this file except in compliance with the License. You may obtain a copy
// of the License at http://www.apache.org/licenses/LICENSE-2.0
//
// Unless required by applicable law or agreed to in writing, software distributed under
// the License is distributed on an "AS IS" BASIS, WITHOUT WARRANTIES OR REPRESENTATIONS
// OF ANY KIND, either express or implied. See the License for the specific language
// governing permissions and limitations under the License.
//

#import "Foundation/Foundation.h"
#import "ViewController.h"
#import <AdSupport/ASIdentifierManager.h>
#if __has_include(<AppTrackingTransparency/AppTrackingTransparency.h>)
#import <AppTrackingTransparency/ATTrackingManager.h>
#endif

@import AEPEdgeIdentity;
@import AEPCore;
@import AEPServices;

@implementation ViewController

- (void)viewDidLoad {
    [super viewDidLoad];
    [_lblextensionVersion setText:[NSString stringWithFormat:@"AEPEdgeIdentity version : %@", [AEPMobileEdgeIdentity extensionVersion]]];
    
}

- (IBAction)btnGetECIDClicked:(id)sender {
    [AEPMobileEdgeIdentity getExperienceCloudId:^(NSString *ecid, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.lblECID setText:ecid];
        });
    }];
}

- (IBAction)btnGetUrlVariablesClicked:(id)sender {
    [AEPMobileEdgeIdentity getUrlVariables:^(NSString *urlVariables, NSError *error){
        dispatch_async(dispatch_get_main_queue(), ^{
            [self.lblUrlVariables setText:urlVariables];

        });
    }];
}

- (IBAction)btnUpdateIdentitiesClicked:(id)sender {
    // Create UserID IdentityItem
    AEPIdentityItem *userId = [[AEPIdentityItem alloc] initWithId:@"Mr.Soandso" authenticatedState:AEPAuthenticatedStateAuthenticated primary:false];
    // Create Email IdentityItem's
    AEPIdentityItem *primaryEmail = [[AEPIdentityItem alloc] initWithId:@"example@email.com" authenticatedState:AEPAuthenticatedStateAuthenticated primary:false];
    AEPIdentityItem *secondaryEmail = [[AEPIdentityItem alloc] initWithId:@"anotherOne@email.com" authenticatedState:AEPAuthenticatedStateLoggedOut primary:false];
    
    // Add these elements to a IdentityMap
    AEPIdentityMap *map = [[AEPIdentityMap alloc] init];
    [map addItem:primaryEmail withNamespace:@"Email"];
    [map addItem:secondaryEmail withNamespace:@"Email"];
    [map addItem:userId withNamespace:@"UserID"];
    [AEPMobileEdgeIdentity updateIdentities:map];
    
    [self btnGetIdentitesClicked:nil];
}

- (IBAction)btnRemoveIdentity:(id)sender {
    // Identity Item to be removed
    AEPIdentityItem *secondaryEmail = [[AEPIdentityItem alloc] initWithId:@"anotherOne@email.com" authenticatedState:AEPAuthenticatedStateLoggedOut primary:false];
    [AEPMobileEdgeIdentity removeIdentityItem:secondaryEmail withNamespace:@"Email"];
    [self btnGetIdentitesClicked:nil];
}

- (IBAction)btnGetIdentitesClicked:(id)sender {
    __block NSString *resultString = @"";
    [AEPMobileEdgeIdentity getIdentities:^(AEPIdentityMap *map, NSError *error){
        for (NSString *eachNamespace in map.namespaces) {
            NSArray* items = [map getItemsWithNamespace:eachNamespace];
            [items enumerateObjectsUsingBlock:^(AEPIdentityItem *eachItem, NSUInteger index, BOOL *stop) {
                resultString = [resultString stringByAppendingFormat:@"\n%@[%lu]",eachNamespace,(unsigned long)index];
                resultString = [resultString stringByAppendingFormat:@"\n \t id : %@",eachItem.id];
                resultString = [resultString stringByAppendingFormat:@"\n \t Authenticated State : %ld",(long)eachItem.authenticatedState];
                resultString = [resultString stringByAppendingFormat:@"\n \t isPrimary : %@",eachItem.primary ? @"true" : @"false"];
            }];
        }

        dispatch_async(dispatch_get_main_queue(), ^{
            [self.txtAllIdentities setText:resultString];
        });
    }];
}

- (IBAction)resetIdentitiesClicked:(id)sender {
    [AEPMobileCore resetIdentities];
    [self btnGetIdentitesClicked:nil];
}

- (IBAction)setAdvertisingIdentifier:(id)sender {
    NSString* advertisingId = [_advertisingIdValue text];
    if ([advertisingId isEqualToString:@"device_adid"]) {
        // setup the advertising identifier
       if (@available(iOS 14, *)) {
           [self requestTrackingAuthorization];
       } else {
           [self setAdvertisingIdentifier];
       }
    } else if ([advertisingId length] > 0) {
        [AEPMobileCore setAdvertisingIdentifier: advertisingId];
    } else {
        [AEPMobileCore setAdvertisingIdentifier: nil];
    }
}

// Test function to check if ad tracking is enabled and get device advertising identifier using ASIdentifierManager, deprecated in iOS 14.
// Ad tracking may be disabled in device Settings -> Privacy -> Advertising -> "Limit Ad Tracking"
- (void) setAdvertisingIdentifier {
    // setup the advertising identifier
    NSString *idfa = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];
    BOOL trackingEnabled = [[ASIdentifierManager sharedManager] isAdvertisingTrackingEnabled];

    [AEPLog traceWithLabel:@"AdvertisingIdentifier" message:[NSString stringWithFormat:@"Advertising Tracking is %@ by the user, and IDFA is %@", trackingEnabled ? @"true" : @"false", idfa]];
    [AEPMobileCore setAdvertisingIdentifier: idfa];
    
}

// Test function to request tracking authorization and get device identifier using ATTrackingManager, first available in iOS 14+.
// On first launch, UI is displayed to user to allow or deny tracking. On simulators, advertising identifier is all zeros.
- (void) requestTrackingAuthorization {
    if (@available(iOS 14, *)) {
        [ATTrackingManager requestTrackingAuthorizationWithCompletionHandler:
        ^(ATTrackingManagerAuthorizationStatus status){
            NSString *statusMsg = @"";

            switch(status) {
                case ATTrackingManagerAuthorizationStatusRestricted:
                    statusMsg = @"Restricted";
                    break;
                case ATTrackingManagerAuthorizationStatusDenied:
                    statusMsg = @"Denied";
                    break;
                case ATTrackingManagerAuthorizationStatusAuthorized:
                    statusMsg = @"Authorized";
                    break;
                case ATTrackingManagerAuthorizationStatusNotDetermined:
                    statusMsg = @"Not Determined";
                    break;
            }

            NSString *idfa = [[[ASIdentifierManager sharedManager] advertisingIdentifier] UUIDString];

            [AEPLog traceWithLabel:@"AdvertisingIdentifier" message:[NSString stringWithFormat:@"Advertising Tracking is %@, IDFA is %@", statusMsg, idfa]];
            [AEPMobileCore setAdvertisingIdentifier:idfa];
        }];
    }
}

@end
