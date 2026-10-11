// SPDX-License-Identifier: GPL-3.0-or-later
#import "SettingsViewController.h"
#import "BennuTheme.h"
#import "CatalogClient.h"
#import "PlayerModel.h"
#import "ImageCache.h"
#import "../../PlayerBridge.h"
static NSString* const kBitrateKey = @"BennuBitrate";
static NSString* const kRepoURL = @"https://github.com/micheldpcarlos/bennu-music";
enum { SectionQuality = 0, SectionNetwork, SectionStorage, SectionUpdates, SectionDiagnostics, SectionAbout, SectionCount };
@interface SettingsViewController () <UITableViewDataSource, UITableViewDelegate>
@property(nonatomic, strong) UITableView* table;
@property(nonatomic, strong) UIButton* closeButton;
@property(nonatomic, strong) UILabel* titleLabel;
@property(nonatomic, strong) CatalogRequest* updateRequest;
@property(nonatomic, strong) CatalogRequest* downloadRequest;
@property(nonatomic, strong) CatalogRequest* clearRequest;
@property(nonatomic, copy) NSString* updateStatus;      // text under "Check for updates"
@property(nonatomic, strong) NSDictionary* available;   // latest release when newer: version, debUrl, debName
@property(nonatomic, copy) NSString* downloadedPath;
@property(nonatomic, copy) NSString* storageStatus;
@end
@implementation SettingsViewController
+ (NSString*)appVersion { return [NSBundle.mainBundle.infoDictionary[@"CFBundleShortVersionString"] description] ?: @"?"; }
+ (int)bitrate { int value = (int)[NSUserDefaults.standardUserDefaults integerForKey:kBitrateKey]; return value == 96 || value == 320 ? value : 160; }
- (void)viewDidLoad {
  [super viewDidLoad];
  self.view.backgroundColor = [BennuTheme background];
  self.closeButton = [UIButton buttonWithType:UIButtonTypeCustom];
  [self.closeButton setImage:[BennuTheme icon:@"close" size:22 color:[BennuTheme text]] forState:UIControlStateNormal];
  [self.closeButton addTarget:self action:@selector(close) forControlEvents:UIControlEventTouchUpInside];
  self.titleLabel = [[UILabel alloc] init]; self.titleLabel.text = @"Settings"; self.titleLabel.font = [BennuTheme bold:30]; self.titleLabel.textColor = [BennuTheme text];
  self.table = [[UITableView alloc] initWithFrame:CGRectZero style:UITableViewStyleGrouped];
  self.table.backgroundColor = [BennuTheme background]; self.table.separatorColor = [BennuTheme cardHighlight];
  self.table.dataSource = self; self.table.delegate = self;
  [self.table registerClass:UITableViewCell.class forCellReuseIdentifier:@"row"];
  [self.view addSubview:self.table]; [self.view addSubview:self.titleLabel]; [self.view addSubview:self.closeButton];
  self.updateStatus = @"Tap to check GitHub for a newer release.";
  [self measureStorage];
}
- (void)viewDidLayoutSubviews {
  [super viewDidLayoutSubviews];
  CGFloat width = self.view.bounds.size.width, height = self.view.bounds.size.height;
  self.closeButton.frame = CGRectMake(width - 60, 24, 44, 44);
  self.titleLabel.frame = CGRectMake(32, 40, width - 110, 40);
  self.table.frame = CGRectMake(0, 90, width, height - 90);
}
- (void)close { [self dismissViewControllerAnimated:YES completion:nil]; }
- (BOOL)prefersStatusBarHidden { return YES; }

// ---- storage
- (void)measureStorage {
  NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString* cache = [documents stringByAppendingPathComponent:@"bennu-cache"];
  dispatch_async(dispatch_get_global_queue(DISPATCH_QUEUE_PRIORITY_LOW, 0), ^{
    unsigned long long bytes = 0; NSUInteger files = 0;
    for (NSString* name in [NSFileManager.defaultManager enumeratorAtPath:cache]) {
      NSDictionary* attributes = [NSFileManager.defaultManager attributesOfItemAtPath:[cache stringByAppendingPathComponent:name] error:nil];
      if ([attributes[NSFileType] isEqualToString:NSFileTypeRegular]) { bytes += [attributes fileSize]; ++files; }
    }
    dispatch_async(dispatch_get_main_queue(), ^{
      self.storageStatus = files ? [NSString stringWithFormat:@"%.1f MB in %lu files: track metadata, covers and artwork", bytes / 1048576.0, (unsigned long)files] : @"Nothing cached yet";
      [self.table reloadSections:[NSIndexSet indexSetWithIndex:SectionStorage] withRowAnimation:UITableViewRowAnimationNone];
    });
  });
}
- (void)clearCache {
  __weak SettingsViewController* weakSelf = self;
  self.storageStatus = @"Clearing…"; [self.table reloadSections:[NSIndexSet indexSetWithIndex:SectionStorage] withRowAnimation:UITableViewRowAnimationNone];
  [[ImageCache shared] clearDisk];
  self.clearRequest = [[CatalogClient shared] request:@"clearcache" argument:@"" update:^(NSDictionary* json, BOOL done) {
    SettingsViewController* owner = weakSelf; if (!owner || !done) return;
    [owner measureStorage];
  }];
}

// ---- updates
- (void)checkForUpdates {
  __weak SettingsViewController* weakSelf = self;
  self.updateStatus = @"Checking…"; self.available = nil; [self.table reloadSections:[NSIndexSet indexSetWithIndex:SectionUpdates] withRowAnimation:UITableViewRowAnimationNone];
  self.updateRequest = [[CatalogClient shared] request:@"update" argument:[SettingsViewController appVersion] update:^(NSDictionary* json, BOOL done) {
    SettingsViewController* owner = weakSelf; if (!owner || !done) return;
    if (json[@"error"]) { owner.updateStatus = [NSString stringWithFormat:@"Could not check: %@", json[@"error"]]; }
    else if ([json[@"newer"] boolValue]) { owner.available = json; owner.updateStatus = [NSString stringWithFormat:@"Bennu Music %@ is available.", json[@"latest"]]; }
    else owner.updateStatus = [NSString stringWithFormat:@"You have the latest version (%@).", json[@"latest"] ?: [SettingsViewController appVersion]];
    [owner.table reloadSections:[NSIndexSet indexSetWithIndex:SectionUpdates] withRowAnimation:UITableViewRowAnimationNone];
  }];
}
- (void)downloadUpdate {
  if (!self.available) return;
  __weak SettingsViewController* weakSelf = self;
  self.updateStatus = [NSString stringWithFormat:@"Downloading %@…", self.available[@"debName"]]; [self.table reloadSections:[NSIndexSet indexSetWithIndex:SectionUpdates] withRowAnimation:UITableViewRowAnimationNone];
  self.downloadRequest = [[CatalogClient shared] request:@"download" argument:self.available[@"debUrl"] update:^(NSDictionary* json, BOOL done) {
    SettingsViewController* owner = weakSelf; if (!owner || !done) return;
    if (json[@"error"]) { owner.updateStatus = [NSString stringWithFormat:@"Download failed: %@", json[@"error"]]; }
    else { owner.downloadedPath = json[@"path"]; owner.updateStatus = [NSString stringWithFormat:@"Saved to %@. Open it with Filza and tap Install.", json[@"path"]]; }
    [owner.table reloadSections:[NSIndexSet indexSetWithIndex:SectionUpdates] withRowAnimation:UITableViewRowAnimationNone];
  }];
}
- (void)openDownloaded {
  if (!self.downloadedPath) return;
  NSURL* filza = [NSURL URLWithString:[@"filza://view" stringByAppendingString:self.downloadedPath]];
  if ([UIApplication.sharedApplication canOpenURL:filza]) { [UIApplication.sharedApplication openURL:filza]; return; }
  UIAlertController* alert = [UIAlertController alertControllerWithTitle:@"Install the update" message:[NSString stringWithFormat:@"Filza is not installed. Install the file with any package manager, or over SSH:\n\ndpkg -i %@", self.downloadedPath] preferredStyle:UIAlertControllerStyleAlert];
  [alert addAction:[UIAlertAction actionWithTitle:@"OK" style:UIAlertActionStyleDefault handler:nil]];
  [self presentViewController:alert animated:YES completion:nil];
}

// ---- diagnostics
- (void)exportLog:(UIView*)anchor {
  NSString* documents = NSSearchPathForDirectoriesInDomains(NSDocumentDirectory, NSUserDomainMask, YES).firstObject;
  NSString* log = [NSString stringWithContentsOfFile:[documents stringByAppendingPathComponent:@"cspot-app.log"] encoding:NSUTF8StringEncoding error:nil] ?: @"";
  if (log.length > 300000) log = [log substringFromIndex:log.length - 300000];
  // Scrub anything that could be a credential, then strip the engine's colour codes.
  NSMutableString* clean = [NSMutableString string];
  for (NSString* line in [log componentsSeparatedByString:@"\n"]) {
    NSString* lower = line.lowercaseString;
    if ([lower containsString:@"bearer "] || [lower containsString:@"authdata"] || [lower containsString:@"blob"] || [lower containsString:@"credential"] || [lower containsString:@"token\":"]) continue;
    NSString* stripped = [[NSRegularExpression regularExpressionWithPattern:@"\x1b\\[[0-9;]*m" options:0 error:nil] stringByReplacingMatchesInString:line options:0 range:NSMakeRange(0, line.length) withTemplate:@""];
    stripped = [[NSRegularExpression regularExpressionWithPattern:@"BQ[A-Za-z0-9_-]{20,}" options:0 error:nil] stringByReplacingMatchesInString:stripped options:0 range:NSMakeRange(0, stripped.length) withTemplate:@"<token>"];
    [clean appendString:stripped]; [clean appendString:@"\n"];
  }
  NSString* crashes = [NSString stringWithContentsOfFile:[documents stringByAppendingPathComponent:@"bennu-crash.log"] encoding:NSUTF8StringEncoding error:nil] ?: @"";
  if (crashes.length > 20000) crashes = [crashes substringFromIndex:crashes.length - 20000];
  NSString* header = [NSString stringWithFormat:@"Bennu Music %@ on %@ %@\n%@\n\n--- crashes ---\n%@\n--- log ---\n", [SettingsViewController appVersion], UIDevice.currentDevice.model, UIDevice.currentDevice.systemVersion, [NSDate date], crashes.length ? crashes : @"(none)\n"];
  NSString* path = [documents stringByAppendingPathComponent:@"bennu-diagnostics.txt"];
  [[header stringByAppendingString:clean] writeToFile:path atomically:YES encoding:NSUTF8StringEncoding error:nil];
  UIActivityViewController* share = [[UIActivityViewController alloc] initWithActivityItems:@[[NSURL fileURLWithPath:path]] applicationActivities:nil];
  share.popoverPresentationController.sourceView = anchor; share.popoverPresentationController.sourceRect = anchor.bounds;
  [self presentViewController:share animated:YES completion:nil];
}

// ---- table
- (NSInteger)numberOfSectionsInTableView:(UITableView*)table { return SectionCount; }
- (NSInteger)tableView:(UITableView*)table numberOfRowsInSection:(NSInteger)section {
  switch (section) {
    case SectionQuality: return 3;
    case SectionNetwork: return 1;
    case SectionStorage: return 1;
    case SectionUpdates: return 2 + (self.available ? 1 : 0) + (self.downloadedPath ? 1 : 0);
    case SectionDiagnostics: return 1;
    default: return 2;
  }
}
- (NSString*)tableView:(UITableView*)table titleForHeaderInSection:(NSInteger)section {
  return @[@"Audio quality", @"Network", @"Storage", @"Updates", @"Diagnostics", @"About"][section];
}
- (NSString*)tableView:(UITableView*)table titleForFooterInSection:(NSInteger)section {
  switch (section) {
    case SectionQuality: return @"Higher quality uses more data and more of the iPad's CPU. A change restarts the player.";
    case SectionNetwork: return @"When visible, phones on this Wi-Fi can pick Bennu Music in Spotify's device list.";
    case SectionStorage: return self.storageStatus ?: @"";
    case SectionUpdates: return self.updateStatus ?: @"";
    case SectionDiagnostics: return @"Creates a text file from the player's log with credentials removed, to attach to a bug report.";
    default: return @"GPL-3.0. Not affiliated with Spotify.";
  }
}
- (void)tableView:(UITableView*)table willDisplayHeaderView:(UIView*)view forSection:(NSInteger)section {
  if ([view isKindOfClass:UITableViewHeaderFooterView.class]) { ((UITableViewHeaderFooterView*)view).textLabel.textColor = [BennuTheme subtext]; }
}
- (void)tableView:(UITableView*)table willDisplayFooterView:(UIView*)view forSection:(NSInteger)section {
  if ([view isKindOfClass:UITableViewHeaderFooterView.class]) { ((UITableViewHeaderFooterView*)view).textLabel.textColor = [BennuTheme subtext]; }
}
- (UITableViewCell*)tableView:(UITableView*)table cellForRowAtIndexPath:(NSIndexPath*)path {
  UITableViewCell* cell = [table dequeueReusableCellWithIdentifier:@"row" forIndexPath:path];
  cell.backgroundColor = [BennuTheme card]; cell.textLabel.textColor = [BennuTheme text]; cell.textLabel.font = [BennuTheme regular:16];
  cell.accessoryType = UITableViewCellAccessoryNone; cell.accessoryView = nil; cell.selectionStyle = UITableViewCellSelectionStyleDefault;
  UIView* highlight = [[UIView alloc] init]; highlight.backgroundColor = [BennuTheme cardHighlight]; cell.selectedBackgroundView = highlight;
  cell.textLabel.text = @""; cell.detailTextLabel.text = @"";
  switch (path.section) {
    case SectionQuality: {
      int rates[] = {96, 160, 320};
      cell.textLabel.text = @[@"Normal (96 kbps)", @"High (160 kbps)", @"Very high (320 kbps)"][path.row];
      cell.accessoryType = [SettingsViewController bitrate] == rates[path.row] ? UITableViewCellAccessoryCheckmark : UITableViewCellAccessoryNone;
      cell.tintColor = [BennuTheme green];
      break; }
    case SectionNetwork: {
      cell.textLabel.text = @"Visible on this network";
      UISwitch* toggle = [[UISwitch alloc] init]; toggle.on = ipad_engine_discoverable() != 0; toggle.onTintColor = [BennuTheme green];
      [toggle addTarget:self action:@selector(visibilityChanged:) forControlEvents:UIControlEventValueChanged];
      cell.accessoryView = toggle; cell.selectionStyle = UITableViewCellSelectionStyleNone;
      break; }
    case SectionStorage: cell.textLabel.text = @"Clear cached data"; break;
    case SectionUpdates:
      if (path.row == 0) { cell.textLabel.text = [NSString stringWithFormat:@"Version %@", [SettingsViewController appVersion]]; cell.selectionStyle = UITableViewCellSelectionStyleNone; }
      else if (path.row == 1) cell.textLabel.text = @"Check for updates";
      else if (path.row == 2 && self.available) { cell.textLabel.text = [NSString stringWithFormat:@"Download Bennu Music %@", self.available[@"latest"]]; cell.textLabel.textColor = [BennuTheme green]; }
      else { cell.textLabel.text = @"Open the downloaded update in Filza"; cell.textLabel.textColor = [BennuTheme green]; }
      break;
    case SectionDiagnostics: cell.textLabel.text = @"Export diagnostics log…"; break;
    default:
      cell.textLabel.text = path.row == 0 ? @"Bennu Music on GitHub" : @"Report a problem";
      cell.accessoryType = UITableViewCellAccessoryDisclosureIndicator;
  }
  return cell;
}
- (void)visibilityChanged:(UISwitch*)toggle { ipad_engine_set_discoverable(toggle.on ? 1 : 0); }
- (void)tableView:(UITableView*)table didSelectRowAtIndexPath:(NSIndexPath*)path {
  [table deselectRowAtIndexPath:path animated:YES];
  switch (path.section) {
    case SectionQuality: {
      int rates[] = {96, 160, 320};
      if ([SettingsViewController bitrate] == rates[path.row]) return;
      [NSUserDefaults.standardUserDefaults setInteger:rates[path.row] forKey:kBitrateKey];
      [table reloadSections:[NSIndexSet indexSetWithIndex:SectionQuality] withRowAnimation:UITableViewRowAnimationNone];
      ipad_engine_stop();   // the launcher restarts the engine with the new bitrate
      break; }
    case SectionStorage: [self clearCache]; break;
    case SectionUpdates:
      if (path.row == 1) [self checkForUpdates];
      else if (path.row == 2 && self.available) [self downloadUpdate];
      else if (path.row >= 2) [self openDownloaded];
      break;
    case SectionDiagnostics: [self exportLog:[table cellForRowAtIndexPath:path]]; break;
    case SectionAbout:
      [UIApplication.sharedApplication openURL:[NSURL URLWithString:path.row == 0 ? kRepoURL : [kRepoURL stringByAppendingString:@"/issues/new/choose"]]];
      break;
    default: break;
  }
}
@end
