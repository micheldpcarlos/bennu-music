// SPDX-License-Identifier: GPL-3.0-or-later
#import "QRSetup.h"
#import "AuthStore.h"
#import "OAuthLogin.h"
#import <CoreImage/CoreImage.h>
#import <QuartzCore/QuartzCore.h>
#import <Security/Security.h>
#import <CommonCrypto/CommonDigest.h>
#import <dispatch/dispatch.h>
#include <sys/stat.h>
#include <fcntl.h>
#include <unistd.h>
#include <errno.h>
#include <stdio.h>
#include <string.h>

static NSString* const QRClient=@"8686d6b87e484c50a6f9ab93bcc099e7";
static NSString* const QRRedirect=@"http://127.0.0.1:8765/callback";
static const char* CallbackFile="/var/mobile/Documents/phoenix-qr-inbox/callback.txt";
static NSString* qrBase64(NSData* data) {
 NSString* value=[data base64EncodedStringWithOptions:0];
 value=[value stringByReplacingOccurrencesOfString:@"+" withString:@"-"];
 value=[value stringByReplacingOccurrencesOfString:@"/" withString:@"_"];
 return [value stringByReplacingOccurrencesOfString:@"=" withString:@""];
}
static NSString* qrRandom(NSUInteger count) {
 NSMutableData* data=[NSMutableData dataWithLength:count];
 if(SecRandomCopyBytes(kSecRandomDefault,count,data.mutableBytes)!=errSecSuccess)return nil;
 return qrBase64(data);
}
static NSData* qrForm(NSDictionary* fields) {
 NSCharacterSet* allowed=[NSCharacterSet characterSetWithCharactersInString:@"ABCDEFGHIJKLMNOPQRSTUVWXYZabcdefghijklmnopqrstuvwxyz0123456789-._~"];
 NSMutableArray* parts=[NSMutableArray array];
 for(NSString* key in fields) [parts addObject:[NSString stringWithFormat:@"%@=%@",key,[fields[key] stringByAddingPercentEncodingWithAllowedCharacters:allowed]]];
 return [[parts componentsJoinedByString:@"&"] dataUsingEncoding:NSUTF8StringEncoding];
}
static NSString* qrTakeCallback(void) {
 int fd=open(CallbackFile,O_RDONLY|O_NOFOLLOW);
 if(fd<0)return nil;
 struct stat info;
 if(fstat(fd,&info)!=0 || !S_ISREG(info.st_mode) || info.st_uid!=getuid() || (info.st_mode&077)!=0 || info.st_size<1 || info.st_size>16384){close(fd);fprintf(stderr,"QR AUTH: callback file rejected (permissions or size)\n");return nil;}
 char buffer[16385];size_t used=0;
 while(used<sizeof(buffer)-1){ssize_t n=read(fd,buffer+used,sizeof(buffer)-1-used);if(n<0){if(errno==EINTR)continue;close(fd);return nil;}if(!n)break;used+=(size_t)n;}
 close(fd);
 NSString* value=[[NSString alloc] initWithBytes:buffer length:used encoding:NSUTF8StringEncoding];
 memset(buffer,0,sizeof(buffer));
 if(unlink(CallbackFile)!=0){fprintf(stderr,"QR AUTH: callback cleanup failed\n");return nil;}
 return value ?: @"";
}
static UIImage* qrImage(NSString* url) {
 CIFilter* filter=[CIFilter filterWithName:@"CIQRCodeGenerator"];
 [filter setValue:[url dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
 [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
 CIImage* output=filter.outputImage;if(!output)return nil;
 output=[output imageByApplyingTransform:CGAffineTransformMakeScale(6,6)];
 CIContext* context=[CIContext contextWithOptions:@{kCIContextUseSoftwareRenderer:@YES}];
 CGImageRef raw=[context createCGImage:output fromRect:output.extent];if(!raw)return nil;
 // Four-module white quiet zone around the QR; render without interpolation.
 CGFloat width=CGImageGetWidth(raw),height=CGImageGetHeight(raw);
 UIGraphicsBeginImageContextWithOptions(CGSizeMake(width+48,height+48),YES,1);
 CGContextRef drawing=UIGraphicsGetCurrentContext();
 if(!drawing){CGImageRelease(raw);UIGraphicsEndImageContext();return nil;}
 [[UIColor whiteColor] setFill];UIRectFill(CGRectMake(0,0,width+48,height+48));
 CGContextSetInterpolationQuality(drawing,kCGInterpolationNone);
 [[UIImage imageWithCGImage:raw] drawInRect:CGRectMake(24,24,width,height)];
 UIImage* image=UIGraphicsGetImageFromCurrentImageContext();UIGraphicsEndImageContext();CGImageRelease(raw);return image;
}

@interface IPadQRController:UIViewController
@property(nonatomic,strong) UILabel* heading;
@property(nonatomic,strong) UILabel* status;
@property(nonatomic,strong) UIImageView* image;
@property(nonatomic,strong) UIButton* closeButton;
@property(nonatomic,strong) UIButton* renewButton;
@property(nonatomic,strong) NSTimer* timer;
@property(nonatomic,strong) NSURLSessionDataTask* task;
@property(nonatomic,copy) NSString* verifier;
@property(nonatomic,copy) NSString* state;
@property(nonatomic,strong) NSDate* expires;
@property(nonatomic) BOOL busy;
@property(nonatomic) BOOL done;
@property(nonatomic) BOOL cancelled;
@property(nonatomic) BOOL previousIdleSetting;
- (void)exchangeCode:(NSString*)code;
- (void)fail:(NSString*)message;
@end
@implementation IPadQRController
- (void)viewDidLoad {
 [super viewDidLoad];self.view.backgroundColor=[UIColor colorWithWhite:0.07 alpha:1];
 self.heading=[[UILabel alloc] init];self.heading.text=@"Connect Spotify";self.heading.textColor=UIColor.whiteColor;self.heading.font=[UIFont boldSystemFontOfSize:26];self.heading.textAlignment=NSTextAlignmentCenter;
 self.status=[[UILabel alloc] init];self.status.textColor=UIColor.whiteColor;self.status.font=[UIFont systemFontOfSize:19];self.status.numberOfLines=0;self.status.textAlignment=NSTextAlignmentCenter;
 self.image=[[UIImageView alloc] init];self.image.contentMode=UIViewContentModeScaleAspectFit;self.image.layer.magnificationFilter=kCAFilterNearest;self.image.layer.minificationFilter=kCAFilterNearest;
 self.closeButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.closeButton setTitle:@"Back to player" forState:UIControlStateNormal];[self.closeButton addTarget:self action:@selector(closeSetup) forControlEvents:UIControlEventTouchUpInside];self.closeButton.titleLabel.font=[UIFont systemFontOfSize:22];
 self.renewButton=[UIButton buttonWithType:UIButtonTypeSystem];[self.renewButton setTitle:@"New QR" forState:UIControlStateNormal];[self.renewButton addTarget:self action:@selector(beginSetup) forControlEvents:UIControlEventTouchUpInside];self.renewButton.titleLabel.font=[UIFont systemFontOfSize:22];
 for(UIView* view in @[self.heading,self.status,self.image,self.closeButton,self.renewButton])[self.view addSubview:view];
 self.previousIdleSetting=UIApplication.sharedApplication.idleTimerDisabled;
 UIApplication.sharedApplication.idleTimerDisabled=YES; // Only while the setup sheet is visible.
 [self beginSetup];
 self.timer=[NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(checkCallback) userInfo:nil repeats:YES];
}
- (void)viewDidLayoutSubviews {
 [super viewDidLayoutSubviews];CGFloat w=self.view.bounds.size.width,h=self.view.bounds.size.height;
 CGFloat side=MIN(450,MIN(w-80,h-310));
 self.heading.frame=CGRectMake(30,35,w-60,45);
 self.image.frame=CGRectMake((w-side)/2,95,side,side);
 self.status.frame=CGRectMake(35,side+112,w-70,h-side-202);
 self.renewButton.frame=CGRectMake(w/2-200,h-75,150,50);
 self.closeButton.frame=CGRectMake(w/2+10,h-75,200,50);
}
- (void)viewDidDisappear:(BOOL)animated {
 [super viewDidDisappear:animated];self.cancelled=YES;[self.timer invalidate];self.timer=nil;[self.task cancel];self.task=nil;self.verifier=nil;self.state=nil;
 UIApplication.sharedApplication.idleTimerDisabled=self.previousIdleSetting;
}
- (void)closeSetup {self.cancelled=YES;[self dismissViewControllerAnimated:YES completion:nil];}
- (void)beginSetup {
 if(self.busy)return;
 qrTakeCallback(); // Discard a stale callback before creating a new session.
 self.done=NO;self.cancelled=NO;self.verifier=qrRandom(32);self.state=qrRandom(24);
 self.expires=[NSDate dateWithTimeIntervalSinceNow:600];
 if(!self.verifier || !self.state){[self fail:@"Secure random generation failed. Try New QR."];return;}
 NSData* input=[self.verifier dataUsingEncoding:NSASCIIStringEncoding];unsigned char digest[CC_SHA256_DIGEST_LENGTH];CC_SHA256(input.bytes,(CC_LONG)input.length,digest);
 NSURLComponents* authorization=[NSURLComponents componentsWithString:@"https://accounts.spotify.com/authorize"];
 authorization.queryItems=@[
  [NSURLQueryItem queryItemWithName:@"client_id" value:QRClient],
  [NSURLQueryItem queryItemWithName:@"response_type" value:@"code"],
  [NSURLQueryItem queryItemWithName:@"redirect_uri" value:QRRedirect],
  [NSURLQueryItem queryItemWithName:@"scope" value:@"streaming user-read-private playlist-read-private user-library-read"],
  [NSURLQueryItem queryItemWithName:@"state" value:self.state],
  [NSURLQueryItem queryItemWithName:@"code_challenge_method" value:@"S256"],
  [NSURLQueryItem queryItemWithName:@"code_challenge" value:qrBase64([NSData dataWithBytes:digest length:sizeof(digest)])]];
 self.image.image=qrImage(authorization.URL.absoluteString);
 if(!self.image.image){[self fail:@"QR rendering failed. Check the app log."];return;}
 self.status.text=@"Scan with your phone and approve Spotify.\nCopy the final callback address into the Mac console.\nKeep this screen open. QR expires in 10 minutes.";
 self.renewButton.enabled=YES;
 fprintf(stderr,"QR AUTH: new session ready; verifier stays on iPad\n");
}
- (void)fail:(NSString*)message {
 self.status.text=message;self.busy=NO;self.done=YES;self.verifier=nil;self.state=nil;self.image.image=nil;self.renewButton.enabled=YES;
}
- (void)checkCallback {
 if(self.busy || self.done || self.cancelled)return;
 if(self.expires.timeIntervalSinceNow<=0){[self fail:@"QR expired. Tap New QR and authorize again."];return;}
 NSString* value=qrTakeCallback();if(!value)return;
 value=[value stringByTrimmingCharactersInSet:NSCharacterSet.whitespaceAndNewlineCharacterSet];
 if([value hasPrefix:@"127.0.0.1:8765/"])value=[@"http://" stringByAppendingString:value];
 NSURLComponents* callback=[NSURLComponents componentsWithString:value];
 NSMutableDictionary* items=[NSMutableDictionary dictionary];BOOL duplicate=NO;
 for(NSURLQueryItem* item in callback.queryItems){if(items[item.name])duplicate=YES;items[item.name]=item.value ?: @"";}
 BOOL valid=!duplicate && [callback.scheme isEqualToString:@"http"] && [callback.host isEqualToString:@"127.0.0.1"] && [callback.port isEqual:@8765] && [callback.path isEqualToString:@"/callback"] && !callback.user.length && !callback.password.length && !callback.fragment.length && [items[@"state"] isEqualToString:self.state] && (([items[@"code"] length]>0)!=([items[@"error"] length]>0));
 if(!valid){fprintf(stderr,"QR AUTH: callback rejected (path, state, or parameters)\n");self.status.text=@"Callback rejected. Use this QR's full callback address, or tap New QR and authorize again.";return;}
 if(items[@"error"]){[self fail:@"Spotify authorization was denied. Tap New QR to retry."];return;}
 if([items[@"code"] length]>8192){[self fail:@"Callback code is too large. Tap New QR."];return;}
 fprintf(stderr,"QR AUTH: callback state verified\n");self.busy=YES;self.renewButton.enabled=NO;self.image.image=nil;
 [self exchangeCode:items[@"code"]];
}
- (void)exchangeCode:(NSString*)code {
 self.status.text=@"Callback verified.\nExchanging the code on this iPad…";
 NSMutableURLRequest* request=[NSMutableURLRequest requestWithURL:[NSURL URLWithString:@"https://accounts.spotify.com/api/token"]];
 request.HTTPMethod=@"POST";request.timeoutInterval=20;
 [request setValue:@"application/x-www-form-urlencoded" forHTTPHeaderField:@"Content-Type"];
 request.HTTPBody=qrForm(@{@"client_id":QRClient,@"grant_type":@"authorization_code",@"code":code,@"redirect_uri":QRRedirect,@"code_verifier":self.verifier});
 __weak IPadQRController* weakSelf=self;
 self.task=[NSURLSession.sharedSession dataTaskWithRequest:request completionHandler:^(NSData* data,NSURLResponse* response,NSError* error){
  NSInteger status=[response isKindOfClass:NSHTTPURLResponse.class]?((NSHTTPURLResponse*)response).statusCode:0;
  id json=data && data.length<=65536?[NSJSONSerialization JSONObjectWithData:data options:0 error:NULL]:nil;
  NSString* token=[json isKindOfClass:NSDictionary.class] && [json[@"access_token"] isKindOfClass:NSString.class]?json[@"access_token"]:nil;
  dispatch_async(dispatch_get_main_queue(),^{
   IPadQRController* owner=weakSelf;if(!owner || owner.cancelled)return;
   owner.verifier=nil;owner.state=nil;owner.task=nil;
   fprintf(stderr,"QR AUTH: token response HTTP=%ld network_code=%ld\n",(long)status,(long)error.code);
   if(error || status!=200 || !token.length || [token lengthOfBytesUsingEncoding:NSUTF8StringEncoding]>16384){[owner fail:[NSString stringWithFormat:@"Token exchange failed (HTTP %ld, network %ld).\nTap New QR to retry.",(long)status,(long)error.code]];return;}
   owner.status.text=@"Spotify authorization succeeded.\nChecking player login and reusable credentials…";
   dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_DEFAULT,0),^{
    @autoreleasepool {
     char credentials[4096]={};int passed=ipad_oauth_reusable_credentials(token.UTF8String,credentials,sizeof(credentials));
     NSString* record=passed?[NSString stringWithUTF8String:credentials]:nil;memset(credentials,0,sizeof(credentials));
     dispatch_async(dispatch_get_main_queue(),^{
      IPadQRController* current=weakSelf;if(!current || current.cancelled)return;
      if(!passed || !record){[current fail:@"Player account login failed. Check QR AUTH logs and try New QR."];return;}
      if(!ipad_auth_save(record.UTF8String)){[current fail:@"Keychain save failed. Check the AUTH status in the app log."];return;}
      fprintf(stderr,"QR AUTH: account saved in Keychain\n");current.done=YES;current.busy=NO;current.renewButton.enabled=YES;
      current.status.text=@"Account saved in Keychain.\nReturn to the player. A waiting player will connect automatically.\nIf another account is already playing, close and reopen the app to switch.";
      [NSNotificationCenter.defaultCenter postNotificationName:@"IPadAccountPaired" object:nil];
     });
    }
   });
  });
 }];[self.task resume];
}
@end
UIViewController* ipad_qr_setup_controller(void) {return [[IPadQRController alloc] init];}
