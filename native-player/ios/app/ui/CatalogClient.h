// SPDX-License-Identifier: GPL-3.0-or-later
#import <Foundation/Foundation.h>
// Objective-C face of the catalog bridge: a request returns a token; updates arrive on the main
// thread as the engine publishes partial and final JSON. Cancel by releasing the token.
@interface CatalogRequest : NSObject
@property(nonatomic, readonly) uint64_t identifier;
- (void)cancel;
@end
@interface CatalogClient : NSObject
+ (instancetype)shared;
// kind/argument as documented in PlayerBridge.h. update(json, done): json has "error" on failure.
- (CatalogRequest*)request:(NSString*)kind argument:(NSString*)argument update:(void (^)(NSDictionary* json, BOOL done))update;
@end
