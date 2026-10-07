// SPDX-License-Identifier: GPL-3.0-or-later
#import <UIKit/UIKit.h>
#import <SafariServices/SafariServices.h>
#import <QuartzCore/QuartzCore.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#include <arpa/inet.h>
#include <sys/socket.h>
#include <sys/select.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>
#import <dispatch/dispatch.h>

static NSString* const ClientID = @"8686d6b87e484c50a6f9ab93bcc099e7";
static NSString* const RedirectURI = @"http://127.0.0.1:8765/callback";
static NSString* const Scopes = @"streaming user-read-private playlist-read-private user-library-read";
static NSString* base64url(NSData* data) {
  NSString* encoded = [data base64EncodedStringWithOptions:0];
  encoded = [encoded stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
  encoded = [encoded stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
  return [encoded stringByReplacingOccurrencesOfString:@"=" withString:@""];
}
static NSString* randomString(NSUInteger length) {
  NSMutableData* bytes = [NSMutableData dataWithLength:length];
  if (SecRandomCopyBytes(kSecRandomDefault, length, bytes.mutableBytes) != errSecSuccess) return nil;
  return base64url(bytes);
}
static NSData* formBody(NSDictionary* fields) {
  NSCharacterSet* allowed = [NSCharacterSet characterSetWithCharactersInString:
      @"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
  NSMutableArray* parts = [NSMutableArray array];
  for (NSString* key in fields) {
    NSString* value = [fields[key] stringByAddingPercentEncodingWithAllowedCharacters:allowed];
    [parts addObject:[NSString stringWithFormat:@"%@=%@", key, value]];
  }
  return [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
}
static void answerSocket(int fd, BOOL accepted) {
  const char* response = accepted
    ? "HTTP/1.1 200 OK\r\nContent-Type: text/html; charset=utf-8\r\nCache-Control: no-store\r\nReferrer-Policy: no-referrer\r\nConnection: close\r\n\r\n<!doctype html><meta name=viewport content='width=device-width'><title>OAuth Probe</title><p>Authorization received. Return to OAuth Probe.</p>"
    : "HTTP/1.1 400 Bad Request\r\nConnection: close\r\nCache-Control: no-store\r\n\r\nInvalid callback.";
  size_t left = strlen(response);
  while (left) {
    ssize_t sent = send(fd, response, left, 0);
    if (sent <= 0) break;
    response += sent; left -= (size_t)sent;
  }
}

@interface ProbeController : UIViewController <SFSafariViewControllerDelegate>
@property(nonatomic, strong) UILabel* statusLabel;
@property(nonatomic, strong) UIButton* loginButton;
@property(nonatomic, strong) SFSafariViewController* browser;
@property(nonatomic, strong) NSURLSessionDataTask* requestTask;
@property(nonatomic, copy) NSString* verifier;
@property(nonatomic, copy) NSString* oauthState;
@property(atomic) BOOL cancelled;
@property(nonatomic) BOOL busy;
- (void)exchangeCode:(NSString*)code verifier:(NSString*)verifier;
- (void)checkProfile:(NSString*)token;
- (void)finish:(NSString*)message;
@end

@implementation ProbeController
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [UIColor colorWithWhite:0.08 alpha:1];
  self.statusLabel = [[UILabel alloc] initWithFrame:CGRectZero];
  self.statusLabel.textColor = UIColor.whiteColor;
  self.statusLabel.font = [UIFont systemFontOfSize:22];
  self.statusLabel.numberOfLines = 0;
  self.statusLabel.textAlignment = NSTextAlignmentCenter;
  self.statusLabel.text = @"Spotify OAuth Probe\n\nThis checks login on this iPad.\nIt does not change the working player.\n\nTokens stay in memory and are never logged.\nTap Sign in to test the authorization page.";
  [self.view addSubview:self.statusLabel];
  self.loginButton = [UIButton buttonWithType:UIButtonTypeSystem];
  [self.loginButton setTitle:@"Sign in to Spotify" forState:UIControlStateNormal];
  self.loginButton.titleLabel.font = [UIFont boldSystemFontOfSize:24];
  self.loginButton.tintColor = UIColor.whiteColor;
  self.loginButton.backgroundColor = [UIColor colorWithRed:0.1 green:0.65 blue:0.3 alpha:1];
  self.loginButton.layer.cornerRadius = 12;
  [self.loginButton addTarget:self action:@selector(beginLogin) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.loginButton];
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGRect bounds = self.view.bounds;
  self.statusLabel.frame = CGRectMake(50, 90, bounds.size.width - 100, bounds.size.height - 290);
  self.loginButton.frame = CGRectMake((bounds.size.width - 320) / 2, bounds.size.height - 160, 320, 70);
}
- (void)setStatus:(NSString*)text {
  NSAssert(NSThread.isMainThread, @"UI updates require the main thread");
  self.statusLabel.text = text;
}
- (void)finish:(NSString*)message {
  self.busy = NO;
  self.loginButton.enabled = YES;
  self.loginButton.alpha = 1;
  self.requestTask = nil;
  self.verifier = nil;
  self.oauthState = nil;
  if (self.browser) {
    self.browser.delegate = nil;
    [self dismissViewControllerAnimated:YES completion:nil];
    self.browser = nil;
  }
  [self setStatus:message];
}
- (void)beginLogin {
  if (self.busy) return;
  NSString* verifier = randomString(32); // 43 URL-safe characters (RFC 7636).
  NSString* state = randomString(24);
  if (!verifier || !state) { [self finish:@"Could not generate secure random values."]; return; }
  int server = socket(AF_INET, SOCK_STREAM, 0);
  if (server < 0) { [self finish:@"Could not create the callback listener."]; return; }
  int yes = 1;
  setsockopt(server, SOL_SOCKET, SO_REUSEADDR, &yes, sizeof(yes));
  struct sockaddr_in address = {0};
  address.sin_len = sizeof(address);
  address.sin_family = AF_INET;
  address.sin_port = htons(8765);
  address.sin_addr.s_addr = htonl(INADDR_LOOPBACK);
  if (bind(server, (struct sockaddr*)&address, sizeof(address)) || listen(server, 4)) {
    close(server);
    [self finish:@"Cannot listen on 127.0.0.1:8765. Close any older OAuth probe and retry."];
    return;
  }
  self.verifier = verifier;
  self.oauthState = state;
  self.cancelled = NO;
  self.busy = YES;
  self.loginButton.enabled = NO;
  self.loginButton.alpha = 0.4;
  [self setStatus:@"Authorization page opened.\n\nIf it is blank or broken, tap Done.\nThe probe will wait up to three minutes."];
  NSData* verifierBytes = [verifier dataUsingEncoding:NSASCIIStringEncoding];
  unsigned char digest[CC_SHA256_DIGEST_LENGTH];
  CC_SHA256(verifierBytes.bytes, (CC_LONG)verifierBytes.length, digest);
  NSString* challenge = base64url([NSData dataWithBytes:digest length:sizeof(digest)]);
  NSURLComponents* authorization = [NSURLComponents componentsWithString:@"https://accounts.spotify.com/authorize"];
  authorization.queryItems = @[
    [NSURLQueryItem queryItemWithName:@"client_id" value:ClientID],
    [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
    [NSURLQueryItem queryItemWithName:@"redirect_uri" value:RedirectURI],
    [NSURLQueryItem queryItemWithName:@"scope" value:Scopes],
    [NSURLQueryItem queryItemWithName:@"state" value:state],
    [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
    [NSURLQueryItem queryItemWithName:@"code_challenge" value:challenge]
  ];
  fprintf(stderr, "OAUTH: listener ready; opening authorization page\n");
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT, 0), ^{
    @autoreleasepool {
      NSDate* deadline = [NSDate dateWithTimeIntervalSinceNow:180];
      NSDictionary* accepted = nil;
      while (!self.cancelled && deadline.timeIntervalSinceNow > 0 && !accepted) {
        fd_set descriptors; FD_ZERO(&descriptors); FD_SET(server, &descriptors);
        struct timeval timeout = {0, 250000};
        int available = select(server + 1, &descriptors, NULL, NULL, &timeout);
        if (available < 0) { if (errno == EINTR) continue; break; }
        if (available == 0) continue;
        int client = accept(server, NULL, NULL);
        if (client < 0) continue;
        // Prevent a disconnected local browser from delivering SIGPIPE.
        setsockopt(client, SOL_SOCKET, SO_NOSIGPIPE, &yes, sizeof(yes));
        struct timeval receiveTimeout = {2, 0};
        setsockopt(client, SOL_SOCKET, SO_RCVTIMEO, &receiveTimeout, sizeof(receiveTimeout));
        char bytes[16385]; size_t used = 0;
        while (used < sizeof(bytes) - 1 && !self.cancelled && deadline.timeIntervalSinceNow > 0) {
          ssize_t count = recv(client, bytes + used, sizeof(bytes) - 1 - used, 0);
          if (count <= 0) break;
          used += (size_t)count; bytes[used] = '\0';
          if (strstr(bytes, "\r\n\r\n")) break;
        }
        bytes[used] = '\0';
        NSString* header = [[NSString alloc] initWithBytes:bytes length:used encoding:NSUTF8StringEncoding];
        NSArray* line = [[header componentsSeparatedByString:@"\r\n"].firstObject componentsSeparatedByString:@" "];
        BOOL valid = NO;
        if (line.count == 3 && [line[0] isEqualToString:@"GET"] && [line[1] hasPrefix:@"/callback?"]) {
          NSURLComponents* callback = [NSURLComponents componentsWithString:[@"http://127.0.0.1:8765" stringByAppendingString:line[1]]];
          NSMutableDictionary* values = [NSMutableDictionary dictionary];
          BOOL duplicate = NO;
          for (NSURLQueryItem* item in callback.queryItems) {
            if (values[item.name]) duplicate = YES;
            values[item.name] = item.value ?: @"";
          }
          valid = !duplicate && [callback.path isEqualToString:@"/callback"] &&
              [values[@"state"] isEqualToString:state] &&
              (([values[@"code"] length] > 0) != ([values[@"error"] length] > 0));
          if (valid) accepted = values;
        }
        answerSocket(client, valid);
        close(client);
      }
      close(server);
      dispatch_async(dispatch_get_main_queue(), ^{
        if (self.cancelled) {
          fprintf(stderr, "OAUTH: cancelled by user\n");
          [self finish:@"Authorization cancelled.\n\nIf the page was broken, report what appeared.\nPlayback in the separate player is unchanged."];
        } else if (!accepted) {
          fprintf(stderr, "OAUTH: callback timed out or listener stopped\n");
          [self finish:@"No valid callback received.\n\nCheck the login page and the registered redirect URI:\nhttp://127.0.0.1:8765/callback"];
        } else if (accepted[@"error"]) {
          fprintf(stderr, "OAUTH: authorization denied\n");
          [self finish:@"Spotify authorization was denied.\nNo tokens were saved."];
        } else {
          fprintf(stderr, "OAUTH: callback state verified\n");
          if (self.browser) {
            self.browser.delegate = nil;
            [self dismissViewControllerAnimated:YES completion:nil];
            self.browser = nil;
          }
          [self exchangeCode:accepted[@"code"] verifier:verifier];
        }
      });
    }
  });
  self.browser = [[SFSafariViewController alloc] initWithURL:authorization.URL];
  self.browser.delegate = self;
  [self presentViewController:self.browser animated:YES completion:nil];
}
- (void)safariViewControllerDidFinish:(SFSafariViewController*)controller {
  (void)controller;
  self.cancelled = YES;
  [self dismissViewControllerAnimated:YES completion:nil];
  self.browser = nil;
}
- (void)exchangeCode:(NSString*)code verifier:(NSString*)verifier {
  [self setStatus:@"Callback verified.\nExchanging the authorization code…"];
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://accounts.spotify.com/api/token"]];
  request.HTTPMethod = @"POST";
  request.timeoutInterval = 20;
  [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
  request.HTTPBody = formBody(@{@"client_id":ClientID, @"grant_type":@"authorization_code",
      @"code":code, @"redirect_uri":RedirectURI, @"code_verifier":verifier});
  self.requestTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse*)response).statusCode : 0;
    NSDictionary* json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSString* token = [json isKindOfClass:NSDictionary.class] && [json[@"access_token"] isKindOfClass:NSString.class] ? json[@"access_token"] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      self.verifier = nil; self.oauthState = nil;
      if (error || status != 200 || !token.length) {
        fprintf(stderr, "OAUTH: token exchange failed; HTTP=%ld network_code=%ld\n", (long)status, (long)error.code);
        [self finish:[NSString stringWithFormat:@"Token exchange failed (HTTP %ld, network error %ld).\nReport these numbers; no tokens were logged.", (long)status, (long)error.code]];
      } else {
        fprintf(stderr, "OAUTH: token exchange successful\n");
        [self checkProfile:token];
      }
    });
  }];
  [self.requestTask resume];
}
- (void)checkProfile:(NSString*)token {
  [self setStatus:@"Token received.\nChecking the account profile…"];
  NSMutableURLRequest* request = [NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://api.spotify.com/v1/me"]];
  request.timeoutInterval = 20;
  [request setValue:[@"Bearer " stringByAppendingString:token] forHTTPHeaderField:@"Authorization"];
  self.requestTask = [NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data, NSURLResponse* response, NSError* error) {
    NSInteger status = [response isKindOfClass:NSHTTPURLResponse.class] ? ((NSHTTPURLResponse*)response).statusCode : 0;
    NSDictionary* json = data ? [NSJSONSerialization JSONObjectWithData:data options:0 error:NULL] : nil;
    NSString* name = [json isKindOfClass:NSDictionary.class] && [json[@"display_name"] isKindOfClass:NSString.class] ? json[@"display_name"] : nil;
    dispatch_async(dispatch_get_main_queue(), ^{
      fprintf(stderr, "OAUTH: profile response; HTTP=%ld network_code=%ld\n", (long)status, (long)error.code);
      self.requestTask = nil;
      if (error || status != 200) {
        [self finish:[NSString stringWithFormat:@"OAuth token exchange succeeded.\nProfile request failed (HTTP %ld, network error %ld).\n\nFor HTTP 403, check your developer app's user allowlist.\nThis has not authenticated CSpot yet.", (long)status, (long)error.code]];
      } else {
        [self finish:[NSString stringWithFormat:@"On-iPad OAuth succeeded.\nAccount: %@\n\nCallback, PKCE token exchange and profile access passed.\n\nTokens were not saved.\nCSpot token login and credential persistence are the next test.", name.length ? name : @"Profile received"]];
      }
    });
  }];
  [self.requestTask resume];
}
@end

@interface ProbeDelegate : UIResponder <UIApplicationDelegate>
@property(nonatomic, strong) UIWindow* window;
@end
@implementation ProbeDelegate
- (BOOL)application:(UIApplication*)application didFinishLaunchingWithOptions:(NSDictionary*)options {
  (void)application; (void)options;
  NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString* path = [documents stringByAppendingPathComponent:@"ipad-oauth-probe.log"];
  freopen(path.fileSystemRepresentation, "a", stderr);
  setvbuf(stderr, NULL, _IOLBF, 0);
  fprintf(stderr, "OAUTH: probe launched; client configured; no tokens logged\n");
  self.window = [[UIWindow alloc] initWithFrame:UIScreen.mainScreen.bounds];
  self.window.rootViewController = [[ProbeController alloc] init];
  [self.window makeKeyAndVisible];
  return YES;
}
@end
int main(int argc, char** argv) {
  @autoreleasepool {
    return UIApplicationMain(argc, argv, nil, NSStringFromClass([ProbeDelegate class]));
  }
}
