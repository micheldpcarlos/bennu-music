// SPDX-License-Identifier: GPL-3.0-or-later
#import "VisualizerView.h"
#import "PlayerModel.h"
#import "../../AudioTap.h"
#include <math.h>
#define BANDS 48
#define WAVE 128
static NSDictionary* catalog(void) {
  static NSDictionary* table;
  if (!table) table = @{
    @"Alchemy": @[@"Random", @"Ambient", @"Dance", @"Dream", @"Fire", @"Floral", @"Garden", @"Glow", @"Halo", @"Hallucination", @"Heat", @"Nebula", @"Orbit", @"Pulse", @"Rainbow", @"Smoke", @"Spring", @"Strobe", @"Surf", @"Twilight"],
    @"Ambience": @[@"Random", @"Swirl", @"Water", @"Splash", @"Fountain", @"Ripple", @"Mist", @"Aurora"],
    @"Bars and Waves": @[@"Bars", @"Ocean Mist", @"Scope", @"Fire Storm", @"Mirror Bars", @"Ribbon"],
    @"Battery": @[@"Random", @"Pulsing Oval", @"Molecular", @"Plasma Lite", @"Spikes", @"Strobe Lights", @"Surge", @"Warp", @"Zebra", @"Firefly", @"Hollywood Lights", @"Metal Sea", @"Dreamscape", @"Bugs", @"Buzz", @"Dizzy Lights", @"Ripples", @"Tiger", @"Scope", @"Fountain", @"Flames", @"Dancer", @"Halo"],
    @"Musical Colors": @[@"Random", @"Soft Hues", @"Crystal", @"Neon", @"Pastel", @"Ember", @"Ice"],
    @"Particle": @[@"Random", @"Crystal Ball", @"Fireworks", @"Cosmic Rain", @"Swarm", @"Comet"],
    @"Plenoptic": @[@"Random", @"Peaks", @"Clouds", @"Lava", @"Canyon", @"Tide"],
    @"Spikes": @[@"Random", @"Spikes", @"Pyramids", @"Stars", @"Crown", @"Thorns"]};
  return table;
}
typedef struct { CGFloat x, y, vx, vy, life, size, hue; } Particle;
@interface VisualizerView () {
  float _peakHold[BANDS];
  float _bands[BANDS];
  float _wave[WAVE];
  Particle _particles[160];
}
@property(nonatomic, copy) NSString* family;
@property(nonatomic, copy) NSString* preset;
@property(nonatomic) NSInteger presetIndex;
@property(nonatomic, strong) CADisplayLink* link;
@property(nonatomic) CFTimeInterval started;
@property(nonatomic) CFTimeInterval lastRandom;
@property(nonatomic) float smoothLevel;
@property(nonatomic) float phase;
@property(nonatomic) BOOL hasAudio;
@property(nonatomic, strong) UILabel* nameLabel;
@end
@implementation VisualizerView
+ (NSArray*)families { return @[@"Alchemy", @"Ambience", @"Bars and Waves", @"Battery", @"Musical Colors", @"Particle", @"Plenoptic", @"Spikes"]; }
+ (NSArray*)presetsForFamily:(NSString*)family { return catalog()[family] ?: @[]; }
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.backgroundColor = [UIColor blackColor];
    self.opaque = YES;
    self.contentMode = UIViewContentModeRedraw;
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont systemFontOfSize:13]; self.nameLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    [self addSubview:self.nameLabel];
    for (int i = 0; i < 160; i++) [self resetParticle:i];
  }
  return self;
}
- (void)layoutSubviews { [super layoutSubviews]; self.nameLabel.frame = CGRectMake(20, self.bounds.size.height - 34, self.bounds.size.width - 40, 20); }
- (void)startWithFamily:(NSString*)family preset:(NSString*)preset {
  self.family = family; self.preset = preset;
  self.presetIndex = [[VisualizerView presetsForFamily:family] indexOfObject:preset];
  if (self.presetIndex == NSNotFound) self.presetIndex = 0;
  self.started = CACurrentMediaTime(); self.lastRandom = self.started;
  self.nameLabel.text = [NSString stringWithFormat:@"%@ — %@", family, preset];
  [self.link invalidate];
  self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
  self.link.frameInterval = 2;   // 30 fps on the iPad 2
  [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)stop { [self.link invalidate]; self.link = nil; }
- (void)dealloc { [self.link invalidate]; }
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event { if (self.onTouch) self.onTouch(); }
- (void)tick {
  float level = 0;
  self.hasAudio = ipad_audio_tap_read(_bands, BANDS, _wave, WAVE, &level) != 0;
  if (!self.hasAudio) {
    // Idle motion so the screen never looks dead when paused.
    for (int i = 0; i < BANDS; i++) _bands[i] = 0.08f + 0.06f * sinf(self.phase * 1.3f + i * 0.4f);
    for (int i = 0; i < WAVE; i++) _wave[i] = 0.04f * sinf(self.phase * 2 + i * 0.2f);
    level = 0.1f;
  }
  self.smoothLevel = self.smoothLevel * 0.8f + level * 0.2f;
  for (int i = 0; i < BANDS; i++) _peakHold[i] = MAX(_bands[i], _peakHold[i] * 0.93f);
  self.phase += 0.03f + self.smoothLevel * 0.08f;
  // "Random" presets rotate through the family every 20 seconds.
  if ([self.preset isEqualToString:@"Random"] && CACurrentMediaTime() - self.lastRandom > 20) {
    self.lastRandom = CACurrentMediaTime();
    NSArray* presets = [VisualizerView presetsForFamily:self.family];
    self.presetIndex = 1 + arc4random_uniform((uint32_t)MAX(1, presets.count - 1));
    self.nameLabel.text = [NSString stringWithFormat:@"%@ — %@", self.family, presets[self.presetIndex]];
  }
  [self setNeedsDisplay];
}
- (NSString*)activePreset { NSArray* presets = [VisualizerView presetsForFamily:self.family]; return self.presetIndex < (NSInteger)presets.count ? presets[self.presetIndex] : @""; }
- (void)resetParticle:(int)i {
  CGFloat w = MAX(1, self.bounds.size.width), h = MAX(1, self.bounds.size.height);
  _particles[i].x = arc4random_uniform((uint32_t)w); _particles[i].y = arc4random_uniform((uint32_t)h);
  _particles[i].vx = (arc4random_uniform(100) - 50) / 60.0; _particles[i].vy = (arc4random_uniform(100) - 50) / 60.0;
  _particles[i].life = 1; _particles[i].size = 2 + arc4random_uniform(6); _particles[i].hue = arc4random_uniform(360) / 360.0;
}
static UIColor* hsv(CGFloat h, CGFloat s, CGFloat v, CGFloat a) { return [UIColor colorWithHue:fmod(h + 1, 1) saturation:s brightness:v alpha:a]; }
- (void)drawRect:(CGRect)rect {
  CGContextRef c = UIGraphicsGetCurrentContext();
  CGFloat w = self.bounds.size.width, h = self.bounds.size.height;
  NSString* f = self.family, *p = [self activePreset];
  CGContextSetFillColorWithColor(c, [UIColor blackColor].CGColor); CGContextFillRect(c, self.bounds);
  if ([f isEqualToString:@"Bars and Waves"]) [self drawBarsAndWaves:c w:w h:h preset:p];
  else if ([f isEqualToString:@"Spikes"]) [self drawSpikes:c w:w h:h preset:p];
  else if ([f isEqualToString:@"Battery"]) [self drawBattery:c w:w h:h preset:p];
  else if ([f isEqualToString:@"Ambience"]) [self drawAmbience:c w:w h:h preset:p];
  else if ([f isEqualToString:@"Musical Colors"]) [self drawMusicalColors:c w:w h:h preset:p];
  else if ([f isEqualToString:@"Particle"]) [self drawParticle:c w:w h:h preset:p];
  else if ([f isEqualToString:@"Plenoptic"]) [self drawPlenoptic:c w:w h:h preset:p];
  else [self drawAlchemy:c w:w h:h preset:p];
}
// ---- Bars and Waves: Bars, Ocean Mist, Scope, Fire Storm, Mirror Bars, Ribbon
- (void)drawBarsAndWaves:(CGContextRef)c w:(CGFloat)w h:(CGFloat)h preset:(NSString*)p {
  if ([p isEqualToString:@"Scope"] || [p isEqualToString:@"Ribbon"]) {
    CGContextSetLineWidth(c, [p isEqualToString:@"Ribbon"] ? 6 : 2);
    int layers = [p isEqualToString:@"Ribbon"] ? 5 : 1;
    for (int l = 0; l < layers; l++) {
      CGContextSetStrokeColorWithColor(c, hsv(0.33 + l * 0.08 + self.phase * 0.02, 0.9, 1, layers > 1 ? 0.5 : 1).CGColor);
      CGContextBeginPath(c);
      for (int i = 0; i < WAVE; i++) {
        CGFloat x = i * w / (WAVE - 1), y = h / 2 + _wave[i] * h * 0.4 * (1 + l * 0.15) + l * 6;
        if (i == 0) CGContextMoveToPoint(c, x, y); else CGContextAddLineToPoint(c, x, y);
      }
      CGContextStrokePath(c);
    }
    return;
  }
  if ([p isEqualToString:@"Ocean Mist"]) {
    for (int i = 0; i < WAVE - 1; i++) {
      CGFloat x = i * w / (WAVE - 1), a = fabs(_wave[i]) * h * 0.45 + 2;
      CGContextSetFillColorWithColor(c, hsv(0.55 + _wave[i] * 0.1, 0.7, 0.9, 0.5).CGColor);
      CGContextFillRect(c, CGRectMake(x, h / 2 - a, w / WAVE + 1, a * 2));
    }
    return;
  }
  int count = 32; CGFloat gap = 4, bw = (w - gap * (count + 1)) / count;
  for (int i = 0; i < count; i++) {
    float v = _bands[i * BANDS / count];
    CGFloat bh = v * h * 0.8;
    CGFloat x = gap + i * (bw + gap);
    if ([p isEqualToString:@"Fire Storm"]) {
      for (int s = 0; s < 12; s++) {
        CGFloat seg = bh / 12;
        CGContextSetFillColorWithColor(c, hsv(0.12 * (1 - s / 12.0), 1, 1, 1).CGColor);
        CGContextFillRect(c, CGRectMake(x, h - 20 - (s + 1) * seg, bw, seg - 1));
      }
    } else if ([p isEqualToString:@"Mirror Bars"]) {
      CGContextSetFillColorWithColor(c, hsv(0.6 - v * 0.4, 0.9, 1, 1).CGColor);
      CGContextFillRect(c, CGRectMake(x, h / 2 - bh / 2, bw, bh));
    } else {
      CGContextSetFillColorWithColor(c, hsv(0.33 - v * 0.33, 0.9, 1, 1).CGColor);
      CGContextFillRect(c, CGRectMake(x, h - 20 - bh, bw, bh));
      CGContextSetFillColorWithColor(c, [UIColor whiteColor].CGColor);
      CGContextFillRect(c, CGRectMake(x, h - 20 - _peakHold[i * BANDS / count] * h * 0.8 - 3, bw, 3));
    }
  }
}
// ---- Spikes: radial spikes from the centre
- (void)drawSpikes:(CGContextRef)c w:(CGFloat)w h:(CGFloat)h preset:(NSString*)p {
  CGFloat cx = w / 2, cy = h / 2, base = MIN(w, h) * 0.12;
  int count = [p isEqualToString:@"Stars"] ? 24 : [p isEqualToString:@"Crown"] ? 12 : BANDS;
  BOOL pyramids = [p isEqualToString:@"Pyramids"], thorns = [p isEqualToString:@"Thorns"];
  for (int i = 0; i < count; i++) {
    float v = _bands[i * BANDS / count];
    CGFloat angle = self.phase * 0.3 + i * 2 * M_PI / count, len = base + v * MIN(w, h) * 0.42;
    CGFloat spread = pyramids ? 0.12 : thorns ? 0.02 : 0.05;
    CGContextSetFillColorWithColor(c, hsv(i / (CGFloat)count + self.phase * 0.05, 0.9, 0.5 + v * 0.5, 0.9).CGColor);
    CGContextBeginPath(c);
    CGContextMoveToPoint(c, cx + cos(angle - spread) * base, cy + sin(angle - spread) * base);
    CGContextAddLineToPoint(c, cx + cos(angle) * len, cy + sin(angle) * len);
    CGContextAddLineToPoint(c, cx + cos(angle + spread) * base, cy + sin(angle + spread) * base);
    CGContextClosePath(c); CGContextFillPath(c);
  }
  CGContextSetFillColorWithColor(c, hsv(self.phase * 0.05, 0.6, 1, 1).CGColor);
  CGContextFillEllipseInRect(c, CGRectMake(cx - base * 0.8, cy - base * 0.8, base * 1.6, base * 1.6));
}
// ---- Battery: the classic geometric collection
- (void)drawBattery:(CGContextRef)c w:(CGFloat)w h:(CGFloat)h preset:(NSString*)p {
  CGFloat cx = w / 2, cy = h / 2, L = self.smoothLevel;
  if ([p isEqualToString:@"Pulsing Oval"] || [p isEqualToString:@"Halo"]) {
    for (int r = 8; r >= 1; r--) {
      CGFloat rx = (0.1 + 0.07 * r + L * 0.25) * w / 2, ry = (0.1 + 0.07 * r + L * 0.25) * h / 2;
      CGContextSetStrokeColorWithColor(c, hsv(self.phase * 0.1 + r * 0.05, 1, 1, 0.9 - r * 0.08).CGColor); CGContextSetLineWidth(c, 3);
      CGContextStrokeEllipseInRect(c, CGRectMake(cx - rx, cy - ry, rx * 2, ry * 2));
    }
  } else if ([p isEqualToString:@"Molecular"] || [p isEqualToString:@"Bugs"] || [p isEqualToString:@"Firefly"] || [p isEqualToString:@"Buzz"]) {
    BOOL lines = [p isEqualToString:@"Molecular"];
    for (int i = 0; i < 40; i++) {
      CGFloat a = self.phase * (0.2 + (i % 5) * 0.07) + i, r = (0.15 + 0.3 * ((i * 37) % 100) / 100.0) * MIN(w, h) * (0.6 + _bands[i % BANDS] * 0.6);
      CGFloat x = cx + cos(a) * r, y = cy + sin(a * 1.3) * r * 0.7;
      CGContextSetFillColorWithColor(c, hsv(i / 40.0, 0.8, 1, 0.9).CGColor);
      CGFloat s = 4 + _bands[i % BANDS] * 18;
      CGContextFillEllipseInRect(c, CGRectMake(x - s / 2, y - s / 2, s, s));
      if (lines && i > 0) { CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.25].CGColor); CGContextSetLineWidth(c, 1); CGContextMoveToPoint(c, cx, cy); CGContextAddLineToPoint(c, x, y); CGContextStrokePath(c); }
    }
  } else if ([p isEqualToString:@"Strobe Lights"] || [p isEqualToString:@"Hollywood Lights"] || [p isEqualToString:@"Dizzy Lights"]) {
    int beams = 16;
    for (int i = 0; i < beams; i++) {
      CGFloat a = self.phase * 0.4 + i * 2 * M_PI / beams, len = MAX(w, h);
      CGContextSetStrokeColorWithColor(c, hsv(i / (CGFloat)beams + self.phase * 0.1, 0.8, 1, 0.1 + _bands[i * 3 % BANDS] * 0.8).CGColor);
      CGContextSetLineWidth(c, 6 + _bands[i * 3 % BANDS] * 30);
      CGContextMoveToPoint(c, cx, [p isEqualToString:@"Hollywood Lights"] ? h : cy); CGContextAddLineToPoint(c, cx + cos(a) * len, cy + sin(a) * len); CGContextStrokePath(c);
    }
  } else if ([p isEqualToString:@"Zebra"] || [p isEqualToString:@"Tiger"]) {
    int stripes = 24;
    for (int i = 0; i < stripes; i++) {
      CGFloat y = i * h / stripes + sin(self.phase + i) * _bands[i % BANDS] * 40;
      CGContextSetFillColorWithColor(c, ([p isEqualToString:@"Tiger"] ? hsv(0.08, 1, i % 2 ? 1 : 0.2, 1) : [UIColor colorWithWhite:i % 2 ? 1 : 0.1 alpha:1]).CGColor);
      CGContextFillRect(c, CGRectMake(0, y, w, h / stripes * (0.5 + _bands[i % BANDS])));
    }
  } else if ([p isEqualToString:@"Warp"] || [p isEqualToString:@"Surge"] || [p isEqualToString:@"Ripples"]) {
    for (int r = 1; r <= 14; r++) {
      CGFloat rad = fmod(r * 40 + self.phase * 60, MAX(w, h) * 0.75) * (0.6 + L);
      CGContextSetStrokeColorWithColor(c, hsv(0.55 + r * 0.03, 0.9, 1, 1 - rad / (MAX(w, h) * 0.75)).CGColor); CGContextSetLineWidth(c, 2 + L * 6);
      if ([p isEqualToString:@"Surge"]) CGContextStrokeRect(c, CGRectMake(cx - rad, cy - rad * 0.75, rad * 2, rad * 1.5));
      else CGContextStrokeEllipseInRect(c, CGRectMake(cx - rad, cy - rad, rad * 2, rad * 2));
    }
  } else if ([p isEqualToString:@"Plasma Lite"] || [p isEqualToString:@"Dreamscape"] || [p isEqualToString:@"Metal Sea"]) {
    int cols = 24, rows = 18;
    for (int y = 0; y < rows; y++) for (int x = 0; x < cols; x++) {
      CGFloat v = 0.5 + 0.5 * sin(x * 0.5 + self.phase) * cos(y * 0.6 - self.phase * 1.3) + _bands[(x + y) % BANDS] * 0.5;
      CGContextSetFillColorWithColor(c, ([p isEqualToString:@"Metal Sea"] ? [UIColor colorWithWhite:v * 0.8 alpha:1] : hsv(v * 0.5 + self.phase * 0.05, 0.9, MIN(1, v), 1)).CGColor);
      CGContextFillRect(c, CGRectMake(x * w / cols, y * h / rows, w / cols + 1, h / rows + 1));
    }
  } else if ([p isEqualToString:@"Spikes"] || [p isEqualToString:@"Flames"]) {
    [self drawSpikes:c w:w h:h preset:[p isEqualToString:@"Flames"] ? @"Thorns" : @"Spikes"];
  } else if ([p isEqualToString:@"Scope"]) {
    [self drawBarsAndWaves:c w:w h:h preset:@"Scope"];
  } else if ([p isEqualToString:@"Fountain"] || [p isEqualToString:@"Dancer"]) {
    [self drawParticle:c w:w h:h preset:@"Fireworks"];
  } else {
    [self drawBattery:c w:w h:h preset:@"Pulsing Oval"];
  }
}
// ---- Ambience: soft drifting blobs
- (void)drawAmbience:(CGContextRef)c w:(CGFloat)w h:(CGFloat)h preset:(NSString*)p {
  CGFloat baseHue = [p isEqualToString:@"Water"] ? 0.58 : [p isEqualToString:@"Aurora"] ? 0.4 : [p isEqualToString:@"Mist"] ? 0.0 : self.phase * 0.03;
  CGFloat sat = [p isEqualToString:@"Mist"] ? 0 : 0.8;
  int blobs = [p isEqualToString:@"Splash"] || [p isEqualToString:@"Fountain"] ? 24 : 10;
  for (int i = 0; i < blobs; i++) {
    CGFloat t = self.phase * (0.15 + 0.03 * (i % 4)), band = _bands[(i * 5) % BANDS];
    CGFloat x = w * (0.5 + 0.42 * sin(t + i * 1.7)), y = h * (0.5 + 0.4 * cos(t * 1.3 + i * 0.9));
    if ([p isEqualToString:@"Fountain"]) { x = w / 2 + sin(t * 3 + i) * w * 0.3 * band; y = h - fmod(t * 400 + i * 60, h); }
    if ([p isEqualToString:@"Ripple"]) { x = w / 2 + cos(i) * (band * w * 0.4); y = h / 2 + sin(i) * (band * h * 0.4); }
    CGFloat r = (MIN(w, h) * 0.12) * (0.6 + band * 1.2);
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    UIColor* color = hsv(baseHue + i * 0.05, sat, 1, 0.55);
    CGFloat comps[8]; [color getRed:&comps[0] green:&comps[1] blue:&comps[2] alpha:&comps[3]]; comps[4] = comps[0]; comps[5] = comps[1]; comps[6] = comps[2]; comps[7] = 0;
    CGGradientRef g = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
    CGContextDrawRadialGradient(c, g, CGPointMake(x, y), 0, CGPointMake(x, y), r, kCGGradientDrawsBeforeStartLocation);
    CGGradientRelease(g); CGColorSpaceRelease(space);
  }
}
// ---- Musical Colors: full-screen colour washes driven by the spectrum
- (void)drawMusicalColors:(CGContextRef)c w:(CGFloat)w h:(CGFloat)h preset:(NSString*)p {
  int cols = 6, rows = 4;
  for (int y = 0; y < rows; y++) for (int x = 0; x < cols; x++) {
    float v = _bands[(y * cols + x) * BANDS / (cols * rows)];
    CGFloat hue = [p isEqualToString:@"Ember"] ? 0.05 + v * 0.1 : [p isEqualToString:@"Ice"] ? 0.55 + v * 0.1 : (x + y) / 10.0 + self.phase * 0.05;
    CGFloat sat = [p isEqualToString:@"Pastel"] || [p isEqualToString:@"Soft Hues"] ? 0.35 : 0.9;
    CGFloat val = [p isEqualToString:@"Neon"] ? MIN(1, 0.2 + v * 1.4) : 0.25 + v * 0.75;
    CGContextSetFillColorWithColor(c, hsv(hue, sat, val, 1).CGColor);
    CGContextFillRect(c, CGRectMake(x * w / cols, y * h / rows, w / cols + 1, h / rows + 1));
    if ([p isEqualToString:@"Crystal"]) { CGContextSetStrokeColorWithColor(c, [UIColor colorWithWhite:1 alpha:0.5].CGColor); CGContextStrokeRect(c, CGRectMake(x * w / cols + 6, y * h / rows + 6, w / cols - 12, h / rows - 12)); }
  }
}
// ---- Particle systems
- (void)drawParticle:(CGContextRef)c w:(CGFloat)w h:(CGFloat)h preset:(NSString*)p {
  CGFloat L = self.smoothLevel;
  for (int i = 0; i < 160; i++) {
    Particle* q = &_particles[i];
    if ([p isEqualToString:@"Cosmic Rain"]) { q->vy = 3 + L * 10; q->vx = 0; }
    else if ([p isEqualToString:@"Fireworks"]) { q->vy += 0.12; }
    else if ([p isEqualToString:@"Crystal Ball"]) { CGFloat dx = w / 2 - q->x, dy = h / 2 - q->y; q->vx += dx * 0.002; q->vy += dy * 0.002; q->vx *= 0.98; q->vy *= 0.98; }
    else if ([p isEqualToString:@"Comet"]) { q->vx = 4 + L * 8; }
    else if ([p isEqualToString:@"Swarm"]) { q->vx += (arc4random_uniform(10) - 5) * 0.1; q->vy += (arc4random_uniform(10) - 5) * 0.1; q->vx *= 0.95; q->vy *= 0.95; }
    q->x += q->vx * (1 + L * 2); q->y += q->vy * (1 + L * 2); q->life -= 0.004 + L * 0.01;
    if (q->life <= 0 || q->x < -20 || q->x > w + 20 || q->y < -20 || q->y > h + 20) {
      [self resetParticle:i];
      if ([p isEqualToString:@"Fireworks"]) { q->x = w / 2 + (arc4random_uniform(200) - 100); q->y = h * 0.7; q->vy = -(4 + arc4random_uniform(8)) * (0.5 + L); }
      if ([p isEqualToString:@"Cosmic Rain"]) q->y = -10;
      if ([p isEqualToString:@"Comet"]) q->x = -10;
    }
    CGFloat s = q->size * (0.6 + L * 2) * (0.5 + _bands[i % BANDS]);
    CGContextSetFillColorWithColor(c, hsv(q->hue + self.phase * 0.02, 0.8, 1, q->life).CGColor);
    CGContextFillEllipseInRect(c, CGRectMake(q->x - s / 2, q->y - s / 2, s, s));
  }
}
// ---- Plenoptic: layered landscapes of waves
- (void)drawPlenoptic:(CGContextRef)c w:(CGFloat)w h:(CGFloat)h preset:(NSString*)p {
  int layers = 7;
  for (int l = 0; l < layers; l++) {   // far ridges first, near ones last
    CGFloat hue = [p isEqualToString:@"Lava"] ? 0.02 + l * 0.02 : [p isEqualToString:@"Clouds"] ? 0.6 : [p isEqualToString:@"Canyon"] ? 0.07 + l * 0.01 : [p isEqualToString:@"Tide"] ? 0.5 + l * 0.03 : 0.3 + l * 0.08;
    CGContextSetFillColorWithColor(c, hsv(hue, [p isEqualToString:@"Clouds"] ? 0.2 : 0.8, 0.9 - l * 0.1, 1).CGColor);
    CGContextBeginPath(c); CGContextMoveToPoint(c, 0, h);
    for (int i = 0; i <= 48; i++) {
      CGFloat x = i * w / 48;
      CGFloat amp = [p isEqualToString:@"Peaks"] ? _bands[i % BANDS] * h * 0.5 : (0.5 + 0.5 * sin(i * 0.4 + self.phase + l)) * h * 0.18 + _bands[(i + l * 3) % BANDS] * h * 0.25;
      CGFloat y = h * (0.35 + l * 0.08) - amp;
      CGContextAddLineToPoint(c, x, y);
    }
    CGContextAddLineToPoint(c, w, h); CGContextClosePath(c); CGContextFillPath(c);
  }
}
// ---- Alchemy: flowing ribbons and glows (WMP 9's showcase collection)
- (void)drawAlchemy:(CGContextRef)c w:(CGFloat)w h:(CGFloat)h preset:(NSString*)p {
  CGFloat cx = w / 2, cy = h / 2, L = self.smoothLevel;
  CGFloat hueBase = [p isEqualToString:@"Fire"] || [p isEqualToString:@"Heat"] ? 0.03 : [p isEqualToString:@"Garden"] || [p isEqualToString:@"Spring"] ? 0.3 : [p isEqualToString:@"Dream"] || [p isEqualToString:@"Twilight"] ? 0.7 : [p isEqualToString:@"Surf"] ? 0.52 : [p isEqualToString:@"Floral"] ? 0.9 : self.phase * 0.04;
  BOOL mono = [p isEqualToString:@"Smoke"], strobe = [p isEqualToString:@"Strobe"];
  int ribbons = [p isEqualToString:@"Ambient"] || [p isEqualToString:@"Dream"] ? 4 : 9;
  for (int r = 0; r < ribbons; r++) {
    CGContextSetLineWidth(c, 3 + L * 14 + r);
    CGContextSetStrokeColorWithColor(c, (mono ? [UIColor colorWithWhite:0.9 alpha:0.35] : hsv(hueBase + r * 0.06, 0.85, strobe && ((int)(self.phase * 10) % 2) ? 0.3 : 1, 0.55)).CGColor);
    CGContextBeginPath(c);
    for (int i = 0; i <= 64; i++) {
      CGFloat t = i / 64.0, a = t * 2 * M_PI * 2 + self.phase * (0.5 + r * 0.05) + r;
      CGFloat rad = (0.12 + 0.05 * r) * MIN(w, h) * (1 + _bands[(i + r * 4) % BANDS] * 1.2);
      CGFloat x = cx + cos(a) * rad * (1 + 0.3 * sin(self.phase + r)), y = cy + sin(a * ([p isEqualToString:@"Orbit"] ? 1 : 1.5)) * rad;
      if (i == 0) CGContextMoveToPoint(c, x, y); else CGContextAddLineToPoint(c, x, y);
    }
    CGContextStrokePath(c);
  }
  if ([p isEqualToString:@"Glow"] || [p isEqualToString:@"Halo"] || [p isEqualToString:@"Nebula"] || [p isEqualToString:@"Pulse"]) {
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    CGFloat comps[8] = {1, 1, 1, 0.6 * L + 0.2, 1, 1, 1, 0};
    UIColor* color = hsv(hueBase, 0.5, 1, 1); [color getRed:&comps[0] green:&comps[1] blue:&comps[2] alpha:NULL]; comps[4] = comps[0]; comps[5] = comps[1]; comps[6] = comps[2];
    CGGradientRef g = CGGradientCreateWithColorComponents(space, comps, NULL, 2);
    CGContextDrawRadialGradient(c, g, CGPointMake(cx, cy), 0, CGPointMake(cx, cy), MIN(w, h) * (0.2 + L * 0.5), 0);
    CGGradientRelease(g); CGColorSpaceRelease(space);
  }
  if ([p isEqualToString:@"Rainbow"] || [p isEqualToString:@"Dance"]) [self drawBarsAndWaves:c w:w h:h preset:@"Mirror Bars"];
}
@end
