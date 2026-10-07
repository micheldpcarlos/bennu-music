// SPDX-License-Identifier: GPL-3.0-or-later
#import "SetupViewController.h"
#import "PhoenixTheme.h"
#import "PlayerModel.h"
#import "../../auth/DeviceAuth.h"
@interface SetupViewController ()
@property(nonatomic, strong) UIButton* closeButton;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) UILabel* accountLabel;
@property(nonatomic, strong) UIView* qrCard;
@property(nonatomic, strong) UILabel* qrTitle;
@property(nonatomic, strong) UIImageView* qrImage;
@property(nonatomic, strong) UILabel* codeLabel;
@property(nonatomic, strong) UILabel* qrHint;
@property(nonatomic, strong) UILabel* qrStatus;
@property(nonatomic, strong) UIButton* codeButton;
@property(nonatomic, strong) UIView* connectCard;
@property(nonatomic, strong) UILabel* connectTitle;
@property(nonatomic, strong) UILabel* connectHint;
@property(nonatomic, strong) UIButton* connectButton;
@property(nonatomic, strong) NSTimer* timer;
@property(nonatomic) uint32_t revision;
@property(nonatomic, copy) NSString* shownURL;
@end
@implementation SetupViewController
- (UILabel*)label:(UIFont*)font color:(UIColor*)color in:(UIView*)parent {
  UILabel* label = [[UILabel alloc] init]; label.font = font; label.textColor = color; label.numberOfLines = 0;
  [parent addSubview:label]; return label;
}
- (UIView*)card {
  UIView* card = [[UIView alloc] init]; card.backgroundColor = [PhoenixTheme surface]; card.layer.cornerRadius = 10;
  [self.view addSubview:card]; return card;
}
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [PhoenixTheme background];
  self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.closeButton setImage:[PhoenixTheme icon:@"close" size:28 color:[PhoenixTheme text]] forState:UIControlStateNormal];
  [self.closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
  [self.view addSubview:self.closeButton];
  self.titleLabel = [self label:[PhoenixTheme bold:30] color:[PhoenixTheme text] in:self.view];
  self.titleLabel.text = @"Connect Spotify";
  self.accountLabel = [self label:[PhoenixTheme regular:15] color:[PhoenixTheme subtext] in:self.view];
  self.qrCard = [self card];
  self.qrTitle = [self label:[PhoenixTheme bold:20] color:[PhoenixTheme text] in:self.qrCard];
  self.qrTitle.text = @"Sign in with your phone";
  self.qrImage = [[UIImageView alloc] init]; self.qrImage.backgroundColor = [UIColor whiteColor]; self.qrImage.layer.cornerRadius = 8; self.qrImage.clipsToBounds = YES;
  self.qrImage.layer.magnificationFilter = kCAFilterNearest; self.qrImage.contentMode = UIViewContentModeScaleAspectFit;
  [self.qrCard addSubview:self.qrImage];
  self.codeLabel = [self label:[UIFont fontWithName:@"Menlo-Bold" size:34] ?: [PhoenixTheme bold:34] color:[PhoenixTheme green] in:self.qrCard];
  self.codeLabel.textAlignment = NSTextAlignmentCenter;
  self.qrHint = [self label:[PhoenixTheme regular:15] color:[PhoenixTheme subtext] in:self.qrCard];
  self.qrHint.text = @"1. Scan the code with your phone's camera, or open spotify.com/pair on any device.\n2. Sign in to Spotify and enter the code.\n3. Come back here. The iPad finishes on its own.";
  self.qrStatus = [self label:[PhoenixTheme regular:14] color:[PhoenixTheme text] in:self.qrCard];
  self.codeButton = [PhoenixTheme pillButton:@"Get a new code"];
  [self.codeButton addTarget:self action:@selector(newCode) forControlEvents:UIControlEventTouchUpInside];
  [self.qrCard addSubview:self.codeButton];
  self.connectCard = [self card];
  self.connectTitle = [self label:[PhoenixTheme bold:20] color:[PhoenixTheme text] in:self.connectCard];
  self.connectTitle.text = @"Or pair with Spotify Connect";
  self.connectHint = [self label:[PhoenixTheme regular:15] color:[PhoenixTheme subtext] in:self.connectCard];
  self.connectHint.text = @"Play something in Spotify on your phone, tap the devices icon and choose “Phoenix Player”. If the iPad is not listed, tap the button, then close and reopen this app.";
  self.connectButton = [PhoenixTheme pillButton:@"Enable pairing on next launch"];
  [self.connectButton addTarget:self action:@selector(enablePairing) forControlEvents:UIControlEventTouchUpInside];
  [self.connectCard addSubview:self.connectButton];
  [self render:@{@"state": @"idle"}];
  [self newCode];
}
- (void)viewWillAppear:(BOOL)animated {
  [super viewWillAppear:animated];
  self.timer = [NSTimer scheduledTimerWithTimeInterval:0.5 target:self selector:@selector(poll) userInfo:nil repeats:YES];
}
- (void)viewWillDisappear:(BOOL)animated { [self.timer invalidate]; self.timer = nil; [super viewWillDisappear:animated]; }
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width;
  BOOL wide = width > 700;
  self.closeButton.frame = CGRectMake(width - 60, 24, 44, 44);
  self.titleLabel.frame = CGRectMake(32, 40, width - 120, 40);
  self.accountLabel.frame = CGRectMake(32, 84, width - 120, 22);
  CGFloat top = 124, gap = 24;
  CGFloat cardWidth = wide ? (width - 32 * 2 - gap) / 2 : width - 64;
  CGFloat inner = cardWidth - 48, qr = MIN(220, inner);
  CGFloat qrCardHeight = 60 + qr + 300;
  self.qrCard.frame = CGRectMake(32, top, cardWidth, qrCardHeight);
  self.connectCard.frame = wide ? CGRectMake(32 + cardWidth + gap, top, cardWidth, 240) : CGRectMake(32, top + qrCardHeight + gap, cardWidth, 240);
  self.qrTitle.frame = CGRectMake(24, 20, inner, 26);
  self.qrImage.frame = CGRectMake((cardWidth - qr) / 2, 60, qr, qr);
  self.codeLabel.frame = CGRectMake(24, 60 + qr + 12, inner, 40);
  self.qrHint.frame = CGRectMake(24, 60 + qr + 58, inner, 120);
  self.qrStatus.frame = CGRectMake(24, 60 + qr + 186, inner, 40);
  self.codeButton.frame = CGRectMake(24, 60 + qr + 236, 170, 32);
  self.connectTitle.frame = CGRectMake(24, 20, inner, 26);
  self.connectHint.frame = CGRectMake(24, 56, inner, 110);
  self.connectButton.frame = CGRectMake(24, 180, 250, 32);
}
- (UIImage*)qrFor:(NSString*)text {
  CIFilter* filter = [CIFilter filterWithName:@"CIQRCodeGenerator"];
  [filter setValue:[text dataUsingEncoding:NSUTF8StringEncoding] forKey:@"inputMessage"];
  [filter setValue:@"M" forKey:@"inputCorrectionLevel"];
  CIImage* output = filter.outputImage;
  if (!output) return nil;
  CGFloat scale = 220 / output.extent.size.width;
  CIImage* scaled = [output imageByApplyingTransform:CGAffineTransformMakeScale(scale, scale)];
  return [UIImage imageWithCGImage:[[CIContext contextWithOptions:nil] createCGImage:scaled fromRect:scaled.extent]];
}
- (void)newCode {
  ipad_device_auth_cancel();
  self.shownURL = nil;
  dispatch_after(dispatch_time(DISPATCH_TIME_NOW, (int64_t)(0.6 * NSEC_PER_SEC)), dispatch_get_main_queue(), ^{ ipad_device_auth_start(); });
  self.qrStatus.text = @"Requesting a code…";
  self.codeLabel.text = @""; self.qrImage.image = nil;
}
- (void)poll {
  char buffer[2048];
  uint32_t revision = ipad_device_auth_status(buffer, sizeof(buffer));
  PlayerModel* model = [PlayerModel shared];
  self.accountLabel.text = model.ready ? @"Connected. Signing in again switches the account on the next launch." : @"No account connected yet.";
  if (!revision || revision == self.revision) return;
  self.revision = revision;
  NSDictionary* state = [NSJSONSerialization JSONObjectWithData:[NSData dataWithBytes:buffer length:strlen(buffer)] options:0 error:nil];
  if ([state isKindOfClass:NSDictionary.class]) [self render:state];
}
- (void)render:(NSDictionary*)state {
  NSString* phase = state[@"state"] ?: @"idle";
  NSString* code = state[@"code"] ?: @"";
  NSString* url = state[@"url"] ?: @"";
  if ([phase isEqualToString:@"waiting"]) {
    self.codeLabel.text = code;
    if (![url isEqualToString:self.shownURL]) { self.shownURL = url; self.qrImage.image = [self qrFor:url]; }
    self.qrStatus.text = @"Waiting for approval on your phone…";
  } else if ([phase isEqualToString:@"requesting"]) {
    self.qrStatus.text = @"Requesting a code…";
  } else if ([phase isEqualToString:@"verifying"]) {
    self.qrStatus.text = @"Approved. Signing the player in…";
  } else if ([phase isEqualToString:@"done"]) {
    self.qrStatus.text = @"Signed in. The player is connecting.";
    self.qrStatus.textColor = [PhoenixTheme green];
    [NSNotificationCenter.defaultCenter postNotificationName:@"IPadAccountPaired" object:nil];
  } else if ([phase isEqualToString:@"failed"]) {
    self.qrStatus.text = state[@"message"] ?: @"Sign-in failed.";
  } else {
    self.qrStatus.text = @"";
  }
  if (![phase isEqualToString:@"done"]) self.qrStatus.textColor = [PhoenixTheme text];
}
- (void)enablePairing {
  NSString* marker = @"/var/mobile/Documents/cspot-use-connect-pairing";
  BOOL ok = [@"" writeToFile:marker atomically:YES encoding:NSUTF8StringEncoding error:nil];
  self.connectHint.text = ok ? @"Pairing is enabled for the next launch. Close Phoenix Player from the app switcher, open it again, then pick “Phoenix Player” in Spotify's device list on your phone."
                            : @"Could not enable pairing (Documents folder not writable).";
}
- (void)close { ipad_device_auth_cancel(); [self dismissViewControllerAnimated:YES completion:nil]; }
@end
