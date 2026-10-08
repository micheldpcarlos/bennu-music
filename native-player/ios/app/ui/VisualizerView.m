// SPDX-License-Identifier: GPL-3.0-or-later
// Windows Media Player 9 visualizations, recreated from the WMP Visualizations Wiki's preset
// lists and its description of Battery's engine: a video-feedback buffer transformed every frame
// by a displacement effect (swirl, kaleidoscope, starburst, tunnel, blocks, zoom, shimmer, shifts)
// plus drawn elements (radar, dot plane, circle waveform, borders, scribble, galaxy), each preset
// pairing effects with a palette. Rendered at half resolution into a feedback bitmap.
#import "VisualizerView.h"
#import "../../AudioTap.h"
#include <math.h>
#define BANDS 48
#define WAVE 128
typedef NS_ENUM(int, Shift) { ShiftNone, ShiftZoom, ShiftZoomOut, ShiftSwirl, ShiftKaleido, ShiftStarburst, ShiftTunnel, ShiftTile, ShiftTwirl, ShiftLeft, ShiftRight, ShiftUp, ShiftDown, ShiftShimmer, ShiftThingus, ShiftRotate, ShiftStretchX };
typedef NS_ENUM(int, Element) { ElNone, ElWave, ElRadar, ElDotPlane, ElCircleWave, ElEdgeGradient, ElScribble, ElEdgeTrace, ElSpectrumEdge, ElGalaxy, ElCircles, ElBars, ElLines, ElAmoeba, ElSpikes, ElFountain, ElSmokeCircles, ElSmokeLines, ElXLines, ElTwoLines, ElMirrorWave };
typedef struct { Shift shift; Element a, b; float hue; float hueRange; float sat; float fade; float speed; BOOL whiteFlash; BOOL cycleHue; } PresetSpec;

static NSDictionary* catalog(void) {
  static NSDictionary* table;
  if (!table) table = @{
    @"Alchemy": @[@"Random"],
    @"Ambience": @[@"Random", @"Swirl", @"Warp", @"Anon", @"Falloff", @"Water", @"Bubble", @"Dizzy", @"Windmill", @"Niagara", @"Blender", @"X Marks the Spot", @"Down the Drain", @"Thingus"],
    @"Bars and Waves": @[@"Bars", @"Ocean Mist", @"Fire Storm", @"Scope"],
    @"Battery": @[@"Randomization", @"brightsphere", @"dance of the freaky circles", @"cominatcha", @"cottonstar", @"dandelionaid", @"drinkdeep", @"eletriarnation", @"event horizon", @"hizodge", @"gemstonematrix", @"sepiaswirl", @"illuminator", @"i see the truth", @"kaleidovision", @"chemicalnova", @"lotus", @"green is not your enemy", @"relatively calm", @"sleepyspray", @"smoke or water?", @"spider's last moment...", @"strawberryaid", @"the world", @"my tornado is resting", @"back to the groove"],
    @"Particle": @[@"Particle", @"Rotating Particle"],
    @"Plenoptic": @[@"Random", @"Smokey Circles", @"Smokey Lines", @"Vox", @"Flame", @"Fountain", @"Spyro"],
    @"Spikes": @[@"Spikes", @"Amoeba"]};
  return table;
}
// Preset recipes. hue: base hue 0..1 (-1 = cycling rainbow); fade: feedback retention per frame.
static PresetSpec spec(NSString* family, NSString* preset) {
  PresetSpec s = {ShiftZoom, ElWave, ElNone, -1, 0.1, 0.9, 0.92, 1, NO, YES};
  NSDictionary* battery = @{
    @"brightsphere": @[@(ShiftZoom), @(ElCircleWave), @(ElEdgeGradient), @0.55, @0.3, @0.94],
    @"dance of the freaky circles": @[@(ShiftSwirl), @(ElCircles), @(ElNone), @0.85, @0.9, @0.93],
    @"cominatcha": @[@(ShiftStarburst), @(ElSpectrumEdge), @(ElRadar), @0.08, @0.8, @0.9],
    @"cottonstar": @[@(ShiftShimmer), @(ElGalaxy), @(ElNone), @0.6, @0.2, @0.95],
    @"dandelionaid": @[@(ShiftStarburst), @(ElDotPlane), @(ElNone), @0.15, @0.6, @0.9],
    @"drinkdeep": @[@(ShiftTunnel), @(ElCircleWave), @(ElNone), @0.6, @0.3, @0.94],
    @"eletriarnation": @[@(ShiftTwirl), @(ElRadar), @(ElLines), @0.5, @0.8, @0.91],
    @"event horizon": @[@(ShiftZoomOut), @(ElEdgeGradient), @(ElCircleWave), @0.65, @0.5, @0.95],
    @"hizodge": @[@(ShiftTile), @(ElEdgeTrace), @(ElBars), @0.3, @0.6, @0.9],
    @"gemstonematrix": @[@(ShiftKaleido), @(ElDotPlane), @(ElNone), @0.75, @0.8, @0.9],
    @"sepiaswirl": @[@(ShiftSwirl), @(ElWave), @(ElNone), @0.08, @0.6, @0.95],
    @"illuminator": @[@(ShiftZoom), @(ElRadar), @(ElEdgeGradient), @0.12, @0.9, @0.9],
    @"i see the truth": @[@(ShiftKaleido), @(ElCircleWave), @(ElNone), @0.0, @0.9, @0.93],
    @"kaleidovision": @[@(ShiftKaleido), @(ElScribble), @(ElNone), @-1, @0.9, @0.92],
    @"chemicalnova": @[@(ShiftStarburst), @(ElScribble), @(ElCircles), @0.3, @1.0, @0.88],
    @"lotus": @[@(ShiftSwirl), @(ElCircles), @(ElCircleWave), @0.9, @0.7, @0.94],
    @"green is not your enemy": @[@(ShiftTwirl), @(ElWave), @(ElEdgeTrace), @0.33, @1.0, @0.92],
    @"relatively calm": @[@(ShiftZoom), @(ElWave), @(ElNone), @0.58, @0.4, @0.96],
    @"sleepyspray": @[@(ShiftDown), @(ElFountain), @(ElNone), @0.7, @0.5, @0.93],
    @"smoke or water?": @[@(ShiftShimmer), @(ElSmokeLines), @(ElNone), @0.55, @0.3, @0.96],
    @"spider's last moment...": @[@(ShiftStretchX), @(ElLines), @(ElXLines), @0.0, @0.0, @0.9],
    @"strawberryaid": @[@(ShiftZoom), @(ElCircles), @(ElSpectrumEdge), @0.98, @0.9, @0.9],
    @"the world": @[@(ShiftRotate), @(ElGalaxy), @(ElCircleWave), @0.6, @0.7, @0.93],
    @"my tornado is resting": @[@(ShiftTwirl), @(ElRadar), @(ElNone), @0.5, @0.5, @0.94],
    @"back to the groove": @[@(ShiftTile), @(ElBars), @(ElNone), @0.1, @0.9, @0.88]};
  NSDictionary* ambience = @{
    @"Swirl": @[@(ShiftSwirl), @(ElWave)], @"Warp": @[@(ShiftZoom), @(ElWave)], @"Anon": @[@(ShiftLeft), @(ElWave)],
    @"Falloff": @[@(ShiftDown), @(ElWave)], @"Water": @[@(ShiftShimmer), @(ElWave)], @"Bubble": @[@(ShiftZoomOut), @(ElCircles)],
    @"Dizzy": @[@(ShiftRotate), @(ElWave)], @"Windmill": @[@(ShiftRotate), @(ElLines)], @"Niagara": @[@(ShiftDown), @(ElLines)],
    @"Blender": @[@(ShiftTwirl), @(ElWave)], @"X Marks the Spot": @[@(ShiftStretchX), @(ElXLines)], @"Down the Drain": @[@(ShiftSwirl), @(ElTwoLines)],
    @"Thingus": @[@(ShiftThingus), @(ElWave)]};
  NSDictionary* plenoptic = @{
    @"Smokey Circles": @[@(ShiftZoom), @(ElSmokeCircles), @0.55], @"Smokey Lines": @[@(ShiftZoom), @(ElSmokeLines), @0.3],
    @"Vox": @[@(ShiftUp), @(ElBars), @0.8], @"Flame": @[@(ShiftUp), @(ElSpectrumEdge), @0.06], @"Fountain": @[@(ShiftDown), @(ElFountain), @0.5],
    @"Spyro": @[@(ShiftSwirl), @(ElGalaxy), @0.7]};
  if ([family isEqualToString:@"Battery"] && battery[preset]) {
    NSArray* r = battery[preset]; s.shift = [r[0] intValue]; s.a = [r[1] intValue]; s.b = [r[2] intValue]; s.hue = [r[3] floatValue]; s.sat = [r[4] floatValue]; s.fade = [r[5] floatValue]; s.hueRange = 0.12; s.cycleHue = NO;
  } else if ([family isEqualToString:@"Ambience"] && ambience[preset]) {
    NSArray* r = ambience[preset]; s.shift = [r[0] intValue]; s.a = [r[1] intValue]; s.hue = -1; s.sat = 0.85; s.fade = 0.93; s.whiteFlash = YES;
  } else if ([family isEqualToString:@"Plenoptic"] && plenoptic[preset]) {
    NSArray* r = plenoptic[preset]; s.shift = [r[0] intValue]; s.a = [r[1] intValue]; s.hue = [r[2] floatValue]; s.sat = 0.7; s.fade = 0.97; s.hueRange = 0.3; s.cycleHue = YES;
  } else if ([family isEqualToString:@"Spikes"]) {
    s.shift = ShiftNone; s.a = [preset isEqualToString:@"Amoeba"] ? ElAmoeba : ElSpikes; s.hue = 0.15; s.sat = 0.95; s.fade = 0; s.cycleHue = NO;
  } else if ([family isEqualToString:@"Particle"]) {
    s.shift = [preset isEqualToString:@"Rotating Particle"] ? ShiftRotate : ShiftNone; s.a = ElDotPlane; s.hue = 0.7; s.sat = 0.9; s.fade = 0.6; s.cycleHue = NO;
  } else if ([family isEqualToString:@"Bars and Waves"]) {
    // Research: Bars/Scope are yellow-green on black; Ocean Mist is a soft mirrored blue-white waveform with short
    // fading trails; Fire Storm is the spectrum rendered as flame with a rising smear.
    s.shift = ShiftNone; s.fade = 0; s.cycleHue = NO; s.hue = 0.2; s.sat = 0.85;
    if ([preset isEqualToString:@"Scope"]) s.a = ElWave;
    else if ([preset isEqualToString:@"Ocean Mist"]) { s.a = ElMirrorWave; s.shift = ShiftUp; s.fade = 0.78; s.hue = 0.58; s.sat = 0.45; }
    else if ([preset isEqualToString:@"Fire Storm"]) { s.a = ElBars; s.shift = ShiftUp; s.fade = 0.85; s.hue = 0.04; s.hueRange = 0.12; s.sat = 0.95; }
    else s.a = ElBars;
  } else {
    // Alchemy Random, Battery Randomization, Ambience/Plenoptic Random: a fresh random recipe.
    Shift shifts[] = {ShiftZoom, ShiftSwirl, ShiftKaleido, ShiftStarburst, ShiftTunnel, ShiftTile, ShiftTwirl, ShiftShimmer, ShiftRotate, ShiftZoomOut};
    Element elements[] = {ElWave, ElRadar, ElDotPlane, ElCircleWave, ElScribble, ElGalaxy, ElCircles, ElLines, ElFountain, ElSmokeCircles};
    s.shift = shifts[arc4random_uniform(10)]; s.a = elements[arc4random_uniform(10)]; s.b = arc4random_uniform(2) ? elements[arc4random_uniform(10)] : ElNone;
    s.hue = arc4random_uniform(100) / 100.0; s.sat = 0.7 + arc4random_uniform(30) / 100.0; s.fade = 0.9 + arc4random_uniform(6) / 100.0; s.hueRange = 0.2; s.cycleHue = arc4random_uniform(2);
    if ([family isEqualToString:@"Alchemy"]) s.fade = 0.95;
  }
  return s;
}

typedef struct { CGFloat x, y, vx, vy, life, hue; } Particle;
@interface VisualizerView () {
  float _bands[BANDS], _wave[WAVE], _peak[BANDS];
  Particle _particles[120];
  CGContextRef _canvas;
  CGFloat _cw, _ch;
  float _bassHistory[16]; int _bassIndex;
}
@property(nonatomic, copy) NSString* family;
@property(nonatomic, copy) NSString* preset;
@property(nonatomic) PresetSpec spec;
@property(nonatomic, strong) CADisplayLink* link;
@property(nonatomic) CFTimeInterval lastRandom;
@property(nonatomic) float level, beat, phase, hueShift;
@property(nonatomic) int frameCount;   // NOT `frame`: that would shadow UIView's frame setter and the view would never resize
@property(nonatomic, strong) UILabel* nameLabel;
@end
@implementation VisualizerView
+ (NSArray*)families { return @[@"Alchemy", @"Ambience", @"Bars and Waves", @"Battery", @"Particle", @"Plenoptic", @"Spikes"]; }
+ (NSArray*)presetsForFamily:(NSString*)family { return catalog()[family] ?: @[]; }
- (instancetype)initWithFrame:(CGRect)frame {
  if ((self = [super initWithFrame:frame])) {
    self.backgroundColor = [UIColor blackColor]; self.opaque = YES;
    self.layer.contentsGravity = kCAGravityResize;   // the half-res bitmap is scaled up by the GPU
    self.layer.magnificationFilter = kCAFilterLinear;
    self.nameLabel = [[UILabel alloc] init];
    self.nameLabel.font = [UIFont systemFontOfSize:13]; self.nameLabel.textColor = [UIColor colorWithWhite:1 alpha:0.6];
    [self addSubview:self.nameLabel];
    for (int i = 0; i < 120; i++) [self resetParticle:i];
  }
  return self;
}
- (void)layoutSubviews {
  [super layoutSubviews];
  self.nameLabel.frame = CGRectMake(20, self.bounds.size.height - 34, self.bounds.size.width - 40, 20);
  CGFloat cw = floor(self.bounds.size.width / 2), ch = floor(self.bounds.size.height / 2);
  if (!_canvas || cw != _cw || ch != _ch) {
    if (_canvas) CGContextRelease(_canvas);
    _cw = cw; _ch = ch;
    CGColorSpaceRef space = CGColorSpaceCreateDeviceRGB();
    _canvas = CGBitmapContextCreate(NULL, (size_t)cw, (size_t)ch, 8, (size_t)cw * 4, space, kCGImageAlphaNoneSkipFirst | kCGBitmapByteOrder32Little);
    CGColorSpaceRelease(space);
    CGContextSetRGBFillColor(_canvas, 0, 0, 0, 1); CGContextFillRect(_canvas, CGRectMake(0, 0, cw, ch));
    CGContextSetInterpolationQuality(_canvas, kCGInterpolationLow);
  }
}
- (void)dealloc { [self.link invalidate]; if (_canvas) CGContextRelease(_canvas); }
- (void)startWithFamily:(NSString*)family preset:(NSString*)preset {
  self.family = family; self.preset = preset; self.spec = spec(family, preset);
  self.lastRandom = CACurrentMediaTime();
  self.nameLabel.text = [NSString stringWithFormat:@"%@ — %@", family, preset];
  [self.link invalidate];
  self.link = [CADisplayLink displayLinkWithTarget:self selector:@selector(tick)];
  self.link.frameInterval = self.spec.shift == ShiftNone ? 2 : 3;   // 30 fps analyzers, 20 fps feedback effects on the iPad 2
  [self.link addToRunLoop:NSRunLoop.mainRunLoop forMode:NSRunLoopCommonModes];
}
- (void)stop { [self.link invalidate]; self.link = nil; }
- (void)touchesBegan:(NSSet*)touches withEvent:(UIEvent*)event { if (self.onTouch) self.onTouch(); }
- (void)resetParticle:(int)i {
  _particles[i].x = arc4random_uniform(1000) / 1000.0; _particles[i].y = arc4random_uniform(1000) / 1000.0;
  _particles[i].vx = (arc4random_uniform(100) - 50) / 4000.0; _particles[i].vy = (arc4random_uniform(100) - 50) / 4000.0;
  _particles[i].life = 1; _particles[i].hue = arc4random_uniform(100) / 100.0;
}
- (void)tick {
  float level = 0;
  BOOL audio = ipad_audio_tap_read(_bands, BANDS, _wave, WAVE, &level) != 0;
  if (!audio) {
    for (int i = 0; i < BANDS; i++) _bands[i] = 0.08f + 0.06f * sinf(self.phase * 1.3f + i * 0.4f);
    for (int i = 0; i < WAVE; i++) _wave[i] = 0.05f * sinf(self.phase * 2 + i * 0.2f);
    level = 0.1f;
  }
  for (int i = 0; i < BANDS; i++) _peak[i] = MAX(_bands[i], _peak[i] * 0.9f);
  self.level = self.level * 0.7f + level * 0.3f;
  // Beat: bass energy against its recent average.
  float bass = (_bands[0] + _bands[1] + _bands[2] + _bands[3]) / 4;
  float avg = 0; for (int i = 0; i < 16; i++) avg += _bassHistory[i]; avg /= 16;
  _bassHistory[_bassIndex] = bass; _bassIndex = (_bassIndex + 1) % 16;
  float hit = (bass > avg * 1.25f && bass > 0.3f) ? 1 : 0;
  self.beat = MAX(hit, self.beat * 0.85f);
  self.phase += (0.02f + self.level * 0.05f) * self.spec.speed;
  if (self.spec.cycleHue) self.hueShift += 0.0015f;
  self.frameCount += 1;
  if (([self.preset isEqualToString:@"Random"] || [self.preset isEqualToString:@"Randomization"]) && CACurrentMediaTime() - self.lastRandom > 25) {
    self.lastRandom = CACurrentMediaTime(); self.spec = spec(self.family, self.preset);
  }
  if (_canvas) { [self renderFrame]; CGImageRef image = CGBitmapContextCreateImage(_canvas); self.layer.contents = (__bridge id)image; CGImageRelease(image); }
}
static UIColor* hsv(CGFloat h, CGFloat s, CGFloat v, CGFloat a) { return [UIColor colorWithHue:fmod(fmod(h, 1) + 1, 1) saturation:s brightness:v alpha:a]; }
- (CGFloat)hue:(CGFloat)offset {
  PresetSpec s = self.spec;
  CGFloat base = s.hue < 0 ? self.phase * 0.08 : s.hue;
  return base + self.hueShift + offset * s.hueRange;
}
// ---- the feedback step: redraw the previous frame transformed, then dim it
- (void)applyShift {
  PresetSpec s = self.spec;
  CGFloat w = _cw, h = _ch, L = self.level, B = self.beat;
  if (s.shift == ShiftNone || s.fade == 0) { CGContextSetRGBFillColor(_canvas, 0, 0, 0, 1); CGContextFillRect(_canvas, CGRectMake(0, 0, w, h)); return; }
  CGImageRef previous = CGBitmapContextCreateImage(_canvas);
  CGContextSetRGBFillColor(_canvas, 0, 0, 0, 1); CGContextFillRect(_canvas, CGRectMake(0, 0, w, h));
  CGContextSaveGState(_canvas);
  CGContextSetAlpha(_canvas, s.fade);
  CGRect full = CGRectMake(0, 0, w, h);
  switch (s.shift) {
    case ShiftZoom: case ShiftStarburst: {
      CGFloat z = 1 + 0.015 + L * 0.03 + B * 0.04;
      CGContextTranslateCTM(_canvas, w / 2, h / 2); CGContextScaleCTM(_canvas, z, z);
      if (s.shift == ShiftStarburst) CGContextRotateCTM(_canvas, 0.01 + B * 0.02);
      CGContextDrawImage(_canvas, CGRectMake(-w / 2, -h / 2, w, h), previous); break; }
    case ShiftZoomOut: { CGFloat z = 0.985 - L * 0.02; CGContextTranslateCTM(_canvas, w / 2, h / 2); CGContextScaleCTM(_canvas, z, z); CGContextDrawImage(_canvas, CGRectMake(-w / 2, -h / 2, w, h), previous); break; }
    case ShiftRotate: { CGContextTranslateCTM(_canvas, w / 2, h / 2); CGContextRotateCTM(_canvas, 0.03 + L * 0.03); CGContextScaleCTM(_canvas, 1.005, 1.005); CGContextDrawImage(_canvas, CGRectMake(-w / 2, -h / 2, w, h), previous); break; }
    case ShiftTunnel: { CGContextTranslateCTM(_canvas, w / 2, h / 2); CGContextScaleCTM(_canvas, 1.04 + L * 0.03, 1.0); CGContextDrawImage(_canvas, CGRectMake(-w / 2, -h / 2, w, h), previous); break; }
    case ShiftStretchX: { CGContextTranslateCTM(_canvas, w / 2, h / 2); CGContextScaleCTM(_canvas, 1.0 + sin(self.phase) * 0.03, 1.02); CGContextDrawImage(_canvas, CGRectMake(-w / 2, -h / 2, w, h), previous); break; }
    case ShiftShimmer: case ShiftThingus: {
      CGFloat wob = sin(self.phase * 3) * 0.02, z = 1.01 + L * 0.02;
      CGContextTranslateCTM(_canvas, w / 2 + sin(self.phase * 2) * 4, h / 2 + cos(self.phase * 1.7) * 4);
      CGContextScaleCTM(_canvas, z + wob, z - wob * (s.shift == ShiftThingus ? 3 : 1));
      CGContextDrawImage(_canvas, CGRectMake(-w / 2, -h / 2, w, h), previous); break; }
    case ShiftLeft: CGContextDrawImage(_canvas, CGRectOffset(full, -(3 + L * 6), 0), previous); break;
    case ShiftRight: CGContextDrawImage(_canvas, CGRectOffset(full, 3 + L * 6, 0), previous); break;
    case ShiftUp: CGContextDrawImage(_canvas, CGRectOffset(full, 0, 3 + L * 8), previous); break;   // bitmap y grows upward
    case ShiftDown: CGContextDrawImage(_canvas, CGRectOffset(full, 0, -(3 + L * 8)), previous); break;
    case ShiftTile: {
      CGFloat tw = w / 2, th = h / 2;
      for (int i = 0; i < 2; i++) for (int j = 0; j < 2; j++) CGContextDrawImage(_canvas, CGRectMake(i * tw, j * th, tw, th), previous);
      break; }
    case ShiftKaleido: {
      // Mirror the top-left quadrant into the other three.
      CGContextSaveGState(_canvas); CGContextClipToRect(_canvas, CGRectMake(0, h / 2, w / 2, h / 2)); CGContextDrawImage(_canvas, CGRectMake(-2, h / 2 + 2, w + 4, h / 2), previous); CGContextRestoreGState(_canvas);
      CGContextSaveGState(_canvas); CGContextClipToRect(_canvas, CGRectMake(w / 2, h / 2, w / 2, h / 2)); CGContextTranslateCTM(_canvas, w, 0); CGContextScaleCTM(_canvas, -1, 1); CGContextDrawImage(_canvas, CGRectMake(-2, h / 2 + 2, w + 4, h / 2), previous); CGContextRestoreGState(_canvas);
      CGContextSaveGState(_canvas); CGContextClipToRect(_canvas, CGRectMake(0, 0, w, h / 2)); CGContextTranslateCTM(_canvas, 0, h); CGContextScaleCTM(_canvas, 1, -1); CGContextDrawImage(_canvas, CGRectMake(0, h / 2, w, h / 2), previous); CGContextRestoreGState(_canvas);
      CGContextSaveGState(_canvas); CGContextTranslateCTM(_canvas, w / 2, h / 2); CGContextRotateCTM(_canvas, 0.01 + L * 0.02); CGContextScaleCTM(_canvas, 1.01, 1.01); CGContextSetAlpha(_canvas, 0.5); CGContextDrawImage(_canvas, CGRectMake(-w / 2, -h / 2, w, h), previous); CGContextRestoreGState(_canvas);
      break; }
    case ShiftSwirl: case ShiftTwirl: {
      // Concentric rings rotated by increasing angles approximate a swirl displacement.
      int rings = 6; CGFloat maxR = hypot(w, h) / 2;
      for (int r = rings; r >= 1; r--) {
        CGFloat outer = maxR * r / rings, inner = maxR * (r - 1) / rings;
        CGContextSaveGState(_canvas);
        CGMutablePathRef ring = CGPathCreateMutable();
        CGPathAddEllipseInRect(ring, NULL, CGRectMake(w / 2 - outer, h / 2 - outer, outer * 2, outer * 2));
        CGPathAddEllipseInRect(ring, NULL, CGRectMake(w / 2 - inner, h / 2 - inner, inner * 2, inner * 2));
        CGContextAddPath(_canvas, ring); CGContextEOClip(_canvas); CGPathRelease(ring);
        CGFloat angle = (s.shift == ShiftSwirl ? (rings - r + 1) : r) * (0.012 + L * 0.03);
        CGContextTranslateCTM(_canvas, w / 2, h / 2); CGContextRotateCTM(_canvas, angle); CGContextScaleCTM(_canvas, 1.012, 1.012);
        CGContextDrawImage(_canvas, CGRectMake(-w / 2, -h / 2, w, h), previous);
        CGContextRestoreGState(_canvas);
      }
      break; }
    default: CGContextDrawImage(_canvas, full, previous); break;
  }
  CGContextRestoreGState(_canvas);
  CGImageRelease(previous);
}
// ---- drawn elements (bitmap coordinates: origin bottom-left)
- (void)drawElement:(Element)element {
  CGContextRef c = _canvas; CGFloat w = _cw, h = _ch, cx = w / 2, cy = h / 2, L = self.level, B = self.beat;
  PresetSpec s = self.spec;
  CGFloat bright = s.whiteFlash && L > 0.75 ? 1 : 1;
  CGFloat satur = s.whiteFlash && L > 0.75 ? 0.1 : s.sat;
  switch (element) {
    case ElWave: {
      CGContextSetLineWidth(c, 2 + L * 2); CGContextSetStrokeColorWithColor(c, hsv([self hue:0], satur, bright, 1).CGColor);
      CGContextBeginPath(c);
      for (int i = 0; i < WAVE; i++) { CGFloat x = i * w / (WAVE - 1), y = cy + _wave[i] * h * 0.4; i ? CGContextAddLineToPoint(c, x, y) : CGContextMoveToPoint(c, x, y); }
      CGContextStrokePath(c); break; }
    case ElMirrorWave: {
      CGContextSetLineCap(c, kCGLineCapRound); CGContextSetLineWidth(c, 3 + L * 3);
      for (int k = 0; k < 2; k++) {
        CGContextSetStrokeColorWithColor(c, hsv([self hue:0], satur, 1, 0.9).CGColor);
        CGContextBeginPath(c);
        for (int i = 0; i < WAVE; i++) { CGFloat x = i * w / (WAVE - 1), y = cy + (k ? -1 : 1) * (h * 0.04 + fabs(_wave[i]) * h * 0.45); i ? CGContextAddLineToPoint(c, x, y) : CGContextMoveToPoint(c, x, y); }
        CGContextStrokePath(c);
      }
      break; }
    case ElTwoLines: case ElXLines: {
      CGContextSetLineWidth(c, 2); 
      for (int k = 0; k < 2; k++) {
        CGContextSetStrokeColorWithColor(c, hsv([self hue:k * 0.5], satur, bright, 1).CGColor);
        CGContextBeginPath(c);
        for (int i = 0; i < WAVE; i++) {
          CGFloat t = i / (CGFloat)(WAVE - 1), x = element == ElXLines ? t * w : t * w, y;
          if (element == ElXLines) y = (k ? 1 - t : t) * h + _wave[i] * h * 0.2;
          else y = cy + (k ? -1 : 1) * (h * 0.15 * (L > 0.7 ? -1 : 1)) + _wave[i] * h * 0.3;
          i ? CGContextAddLineToPoint(c, x, y) : CGContextMoveToPoint(c, x, y);
        }
        CGContextStrokePath(c);
      }
      break; }
    case ElLines: {
      CGContextSetLineWidth(c, 1.5);
      for (int k = 0; k < 8; k++) {
        CGFloat a = self.phase * 0.5 + k * M_PI / 4, len = MIN(w, h) * (0.2 + _bands[k * 6] * 0.6);
        CGContextSetStrokeColorWithColor(c, hsv([self hue:k / 8.0], satur, bright, 0.9).CGColor);
        CGContextMoveToPoint(c, cx, cy); CGContextAddLineToPoint(c, cx + cos(a) * len, cy + sin(a) * len); CGContextStrokePath(c);
      }
      break; }
    case ElRadar: {
      CGFloat a = self.phase * 1.2, len = MIN(w, h) * (0.3 + L * 0.3);
      CGContextSetLineWidth(c, 3 + B * 4); CGContextSetStrokeColorWithColor(c, hsv([self hue:0], satur, bright, 1).CGColor);
      CGContextMoveToPoint(c, cx, cy); CGContextAddLineToPoint(c, cx + cos(a) * len, cy + sin(a) * len); CGContextStrokePath(c);
      for (int i = 0; i < 12; i++) { CGFloat r = len * (0.3 + _bands[i * 4] * 0.7); CGContextSetFillColorWithColor(c, hsv([self hue:i / 12.0], satur, bright, 0.9).CGColor); CGContextFillEllipseInRect(c, CGRectMake(cx + cos(a - i * 0.08) * r - 3, cy + sin(a - i * 0.08) * r - 3, 6, 6)); }
      break; }
    case ElDotPlane: {
      // Perspective grid of dots whose height follows the spectrum (the Particle visualization).
      int cols = 16, rows = 12;
      for (int r = 0; r < rows; r++) for (int col = 0; col < cols; col++) {
        CGFloat depth = (r + 1) / (CGFloat)rows, persp = 0.3 + depth * 0.7;
        CGFloat x = cx + (col - cols / 2 + 0.5) * (w / cols) * persp;
        CGFloat lift = _bands[(col + r) % BANDS] * h * 0.25 * persp;
        CGFloat y = h * 0.15 + depth * h * 0.45 + lift + sin(self.phase * 2 + col * 0.5 + r) * 3;
        CGFloat size = 2 + persp * 3 + L * 2;
        CGContextSetFillColorWithColor(c, hsv([self hue:0.15 + (col % 4) * 0.08], satur, 0.6 + depth * 0.4, 1).CGColor);
        CGContextFillEllipseInRect(c, CGRectMake(x - size / 2, y - size / 2, size, size));
      }
      break; }
    case ElCircleWave: {
      CGFloat base = MIN(w, h) * (0.18 + L * 0.1);
      CGContextSetLineWidth(c, 2 + B * 3); CGContextSetStrokeColorWithColor(c, hsv([self hue:0.2], satur, bright, 1).CGColor);
      CGContextBeginPath(c);
      for (int i = 0; i <= WAVE; i++) { CGFloat a = i * 2 * M_PI / WAVE + self.phase * 0.3, r = base + _wave[i % WAVE] * base * 0.8; CGFloat x = cx + cos(a) * r, y = cy + sin(a) * r; i ? CGContextAddLineToPoint(c, x, y) : CGContextMoveToPoint(c, x, y); }
      CGContextStrokePath(c); break; }
    case ElCircles: {
      for (int i = 0; i < 10; i++) {
        CGFloat a = self.phase * (0.3 + i * 0.05) + i, r = MIN(w, h) * (0.1 + 0.3 * ((i * 37) % 10) / 10.0);
        CGFloat x = cx + cos(a) * r, y = cy + sin(a * 1.3) * r * 0.7, size = 6 + _bands[i * 4] * 40 + B * 10;
        CGContextSetLineWidth(c, 2); CGContextSetStrokeColorWithColor(c, hsv([self hue:i / 10.0], satur, bright, 1).CGColor);
        CGContextStrokeEllipseInRect(c, CGRectMake(x - size / 2, y - size / 2, size, size));
      }
      break; }
    case ElEdgeGradient: {
      CGFloat thick = 12 + L * 40 + B * 20;
      for (int i = 0; i < 6; i++) {
        CGContextSetStrokeColorWithColor(c, hsv([self hue:i * 0.05], satur, bright, 0.5 - i * 0.07).CGColor); CGContextSetLineWidth(c, thick / 6);
        CGContextStrokeRect(c, CGRectInset(CGRectMake(0, 0, w, h), i * thick / 6, i * thick / 6));
      }
      break; }
    case ElEdgeTrace: {
      CGContextSetLineWidth(c, 2 + L * 3); CGContextSetStrokeColorWithColor(c, hsv([self hue:0], satur, bright, 1).CGColor);
      CGContextStrokeRect(c, CGRectInset(CGRectMake(0, 0, w, h), 6 + sin(self.phase) * 4, 6 + sin(self.phase) * 4)); break; }
    case ElSpectrumEdge: {
      int n = 32; CGFloat bw = w / n;
      for (int i = 0; i < n; i++) { CGFloat v = _bands[i * BANDS / n], bh = v * h * 0.35; CGContextSetFillColorWithColor(c, hsv([self hue:v * 0.3], satur, bright, 1).CGColor); CGContextFillRect(c, CGRectMake(i * bw, 0, bw - 1, bh)); CGContextFillRect(c, CGRectMake(i * bw, h - bh, bw - 1, bh)); }
      break; }
    case ElBars: {
      int n = 32; CGFloat bw = w / n;
      for (int i = 0; i < n; i++) {
        CGFloat v = _bands[i * BANDS / n], bh = v * h * 0.8;
        CGContextSetFillColorWithColor(c, hsv([self hue:(1 - v) * 0.3], satur, bright, 1).CGColor);
        CGContextFillRect(c, CGRectMake(i * bw + 1, 8, bw - 2, bh));
        CGContextSetFillColorWithColor(c, [UIColor whiteColor].CGColor); CGContextFillRect(c, CGRectMake(i * bw + 1, 8 + _peak[i * BANDS / n] * h * 0.8, bw - 2, 2));
      }
      break; }
    case ElScribble: {
      CGContextSetLineWidth(c, 1.5 + B * 2); CGContextSetStrokeColorWithColor(c, hsv([self hue:0.3], satur, bright, 0.9).CGColor);
      CGFloat x = cx + cos(self.phase * 4) * w * 0.2, y = cy + sin(self.phase * 3) * h * 0.2;
      CGContextMoveToPoint(c, x, y);
      for (int i = 0; i < 24; i++) { x += (arc4random_uniform(100) - 50) * (0.3 + L); y += (arc4random_uniform(100) - 50) * (0.3 + L); CGContextAddLineToPoint(c, x, y); }
      CGContextStrokePath(c); break; }
    case ElGalaxy: {
      for (int i = 0; i < 90; i++) {
        CGFloat t = i / 90.0, a = t * 6 * M_PI + self.phase * 0.5, r = t * MIN(w, h) * 0.45 * (0.8 + _bands[i % BANDS] * 0.5);
        CGFloat size = 1.5 + (1 - t) * 3 + _bands[i % BANDS] * 4;
        CGContextSetFillColorWithColor(c, hsv([self hue:t * 0.3], satur, bright, 0.9).CGColor);
        CGContextFillEllipseInRect(c, CGRectMake(cx + cos(a) * r - size / 2, cy + sin(a) * r * 0.6 - size / 2, size, size));
      }
      break; }
    case ElSpikes: case ElAmoeba: {
      // Spikes: round dots pushed outward by the spectrum; Amoeba: the same as a closed outline.
      int n = BANDS; CGFloat base = MIN(w, h) * 0.18;
      CGContextSetFillColorWithColor(c, hsv(element == ElAmoeba ? 0.25 : 0.14, 0.95, 1, 1).CGColor);
      CGContextSetStrokeColorWithColor(c, hsv(element == ElAmoeba ? 0.25 : 0.14, 0.95, 1, 1).CGColor); CGContextSetLineWidth(c, 3);
      if (element == ElAmoeba) CGContextBeginPath(c);
      for (int i = 0; i <= n; i++) {
        CGFloat a = i * 2 * M_PI / n - M_PI_2, r = base + _peak[i % n] * MIN(w, h) * 0.3;
        CGFloat x = cx + cos(a) * r, y = cy + sin(a) * r;
        if (element == ElAmoeba) { i ? CGContextAddLineToPoint(c, x, y) : CGContextMoveToPoint(c, x, y); }
        else if (i < n) { CGFloat size = 5 + _bands[i] * 8; CGContextFillEllipseInRect(c, CGRectMake(x - size / 2, y - size / 2, size, size)); CGContextMoveToPoint(c, cx + cos(a) * base * 0.6, cy + sin(a) * base * 0.6); CGContextAddLineToPoint(c, x, y); CGContextStrokePath(c); }
      }
      if (element == ElAmoeba) { CGContextClosePath(c); CGContextStrokePath(c); }
      break; }
    case ElFountain: {
      for (int i = 0; i < 120; i++) {
        Particle* q = &_particles[i];
        q->vy -= 0.0006; q->x += q->vx; q->y += q->vy; q->life -= 0.01;
        if (q->life <= 0 || q->y < 0) { [self resetParticle:i]; q->x = 0.5 + (arc4random_uniform(100) - 50) / 1000.0; q->y = 0.1; q->vx = (arc4random_uniform(100) - 50) / 2500.0; q->vy = 0.012 + L * 0.02 + arc4random_uniform(100) / 10000.0; }
        CGFloat size = 2 + _bands[i % BANDS] * 5;
        CGContextSetFillColorWithColor(c, hsv([self hue:q->hue * 0.3], satur, bright, q->life).CGColor);
        CGContextFillEllipseInRect(c, CGRectMake(q->x * w - size / 2, q->y * h - size / 2, size, size));
      }
      break; }
    case ElSmokeCircles: case ElSmokeLines: {
      for (int i = 0; i < 6; i++) {
        CGFloat a = self.phase * (0.4 + i * 0.1) + i * 1.1, r = MIN(w, h) * (0.15 + 0.2 * (i % 3) / 3.0);
        CGFloat x = cx + cos(a) * r, y = cy + sin(a * 1.4) * r * 0.8, size = 10 + _bands[i * 7] * 60;
        CGContextSetStrokeColorWithColor(c, hsv([self hue:i / 6.0], satur, bright, 0.5).CGColor); CGContextSetLineWidth(c, 4 + L * 6);
        if (element == ElSmokeCircles) CGContextStrokeEllipseInRect(c, CGRectMake(x - size / 2, y - size / 2, size, size));
        else { CGContextMoveToPoint(c, x - size, y); CGContextAddCurveToPoint(c, x - size / 2, y + _wave[i * 10] * 100, x + size / 2, y - _wave[i * 10 + 5] * 100, x + size, y); CGContextStrokePath(c); }
      }
      break; }
    default: break;
  }
}
- (void)renderFrame {
  [self applyShift];
  PresetSpec s = self.spec;
  if (s.whiteFlash && self.level > 0.78) { CGContextSetRGBFillColor(_canvas, 1, 1, 1, 0.5); CGContextFillRect(_canvas, CGRectMake(0, 0, _cw, _ch)); }
  [self drawElement:s.a];
  if (s.b != ElNone) [self drawElement:s.b];
}
@end
