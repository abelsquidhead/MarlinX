//
//  MLNSampleView.m
//  Marlin
//
//  Created by iain on 31/01/2013.
//  Copyright (c) 2013 iain. All rights reserved.
//

#import "MLNApplicationDelegate.h"
#import "MLNSampleView.h"
#import "MLNSample.h"
#import "MLNSample+Drawing.h"
#import "MLNSampleBlock.h"
#import "MLNSampleChannel.h"
#import "MLNSelectionAction.h"
#import "MLNSelectionButton.h"
#import "MLNSelectionToolbar.h"
#import "Constants.h"

typedef enum {
    DragHandleNone,
    DragHandleStart,
    DragHandleEnd
} DragHandle;

@implementation MLNSampleView {
    CGFloat _intrinsicWidth;
    CGFloat _summedMagnificationLevel;
    
    int _selectionDirection;
    NSTrackingArea *_startTrackingArea;
    NSUInteger _selectionStartFrame;
    NSUInteger _selectionEndFrame;
    NSEvent *_dragEvent;
    DragHandle _dragHandle;
    
    CGGradientRef _shadowGradient;
    
    NSTimer *_cursorTimer;
    BOOL _cursorOpacityDirection;
    float _cursorOpacity;
    BOOL _drawCursor;
    
    MLNSelectionToolbar *_selectionToolbar;
    NSMutableArray *_toolbarConstraints;
    NSLayoutConstraint *_toolbarXConstraint;
    NSLayoutConstraint *_leftXConstraint;
    BOOL _toolbarIsOnRight;
}

@synthesize framesPerPixel = _framesPerPixel;

#define CURSOR_FADE_TIME 0.1
#define CURSOR_PAUSE_TIME 0.3
#define CURSOR_MIN_OPACITY 0.60
#define CURSOR_MAX_OPACITY 0.85

#define DEFAULT_FRAMES_PER_PIXEL 128

- (id)initWithFrame:(NSRect)frame
{
    self = [super initWithFrame:frame];
    if (!self) {
        return nil;
    }
    
    _framesPerPixel = DEFAULT_FRAMES_PER_PIXEL;
    _summedMagnificationLevel = 0;
    _drawCursor = YES;
    _cursorFramePosition = 0;
    _cursorOpacityDirection = NO;
    
    [self resetCursorTimer:CURSOR_FADE_TIME withSelector:@selector(increaseCursorOpacity:)];
    
    [self setContentCompressionResistancePriority:NSLayoutPriorityRequired
                                   forOrientation:NSLayoutConstraintOrientationVertical];
    [self setContentHuggingPriority:NSLayoutPriorityDefaultLow
                     forOrientation:NSLayoutConstraintOrientationVertical];
    
    return self;
}

- (void)removeObserversFromSample:(MLNSample *)sample
{
    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    
    if (_sample) {
        [nc removeObserver:self name:kMLNSampleDataDidChangeInRange object:_sample];
    }
}

- (void)dealloc
{
    [self removeObserversFromSample:_sample];
    CGGradientRelease(_shadowGradient);
}

- (BOOL)isFlipped
{
    return NO;
}

- (NSSize)intrinsicContentSize
{
    CGFloat minimumHeight = 100 * [_sample numberOfChannels];
    
    if (minimumHeight == 0) {
        minimumHeight = NSViewNoInstrinsicMetric;
    }
    
    NSSize intrinsicSize = NSMakeSize(_intrinsicWidth, minimumHeight);
    return intrinsicSize;
}

#pragma mark - Sample view drawing

- (CGContextRef)newMaskContextForRect:(NSRect)scaledRect
{
    CGContextRef maskContext;
    CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceGray();
    
    //NSRect scaledRect = [self convertRectToBacking:bounds];
    maskContext = CGBitmapContextCreate(NULL,
                                         scaledRect.size.width,
                                         scaledRect.size.height,
                                         8,
                                         scaledRect.size.width,
                                         colorspace,
                                         0);
    CGColorSpaceRelease(colorspace);
    
    return maskContext;
}

static const int GUTTER_SIZE = 24;

- (void)drawRect:(NSRect)dirtyRect
{
    CGContextRef context = [[NSGraphicsContext currentContext] graphicsPort];
    NSRect bounds = [self bounds];
    NSRect realDrawRect = dirtyRect;
    
    // We actually want to draw the whole of the vertical
    realDrawRect.origin.y = bounds.origin.y;
    realDrawRect.size.height = bounds.size.height;
    
    if ([_sample isLoaded] == NO) {
        return;
    }
    
    NSUInteger numberOfChannels = [_sample numberOfChannels];
    NSRect channelRect = realDrawRect;
    
    // If there is only 1 channel, we need extra room for the marker gutter
    // We also make the bottom gutter smaller because we don't need the second row of ticks
    int extraGutterHeight = (numberOfChannels == 1) ? GUTTER_SIZE - 7 : 0;
    CGFloat channelHeight = (realDrawRect.size.height - extraGutterHeight) / numberOfChannels;
    
    // 55 56 58
    NSColor *darkBG = [NSColor colorWithCalibratedRed:0.214 green:0.218 blue:0.226 alpha:1.0];
    
    channelRect.size.height = channelHeight;
    
    NSRect maskRect = channelRect;
    maskRect.size.height -= GUTTER_SIZE;
    
    // Scale to take Retina display into consideration
    NSRect scaledRect = [self convertRectToBacking:maskRect];
    NSUInteger channel;
    
    for (channel = 0; channel < numberOfChannels; channel++) {
        channelRect.origin.y = realDrawRect.size.height - (channelHeight * (channel + 1));
        maskRect.origin.y = channelRect.origin.y;
        
        NSRect channelBackgroundRect = maskRect;
        channelBackgroundRect.origin.x = bounds.origin.x;
        channelBackgroundRect.size.width = bounds.size.width;
        
        /*
        if (NSIntersectsRect(dirtyRect, channelBackgroundRect) == NO) {
            continue;
        }
         */
        
        if (_shadowGradient == nil) {
            // Draw the shadow gradients
            CGFloat components[8] = {0.45, 0.45, 0.45, 1.0,  // Start color
                0.6, 0.6, 0.6, 0.1}; // End color
            CGFloat locations[2] = {0.4, 1.0};
            size_t num_locations = 2;
            
            CGColorSpaceRef colorspace = CGColorSpaceCreateDeviceRGB();
            _shadowGradient = CGGradientCreateWithColorComponents(colorspace, components, locations, num_locations);
            CGColorSpaceRelease(colorspace);
        }

        CGPoint startPoint = CGPointMake(channelBackgroundRect.origin.x, NSMaxY(channelBackgroundRect) - 10);
        CGPoint endPoint = CGPointMake(channelBackgroundRect.origin.x, NSMaxY(channelBackgroundRect) + 7);
        CGContextDrawLinearGradient(context, _shadowGradient, startPoint, endPoint, 0);

        startPoint = CGPointMake(channelBackgroundRect.origin.x, channelBackgroundRect.origin.y + 10);
        endPoint = CGPointMake(channelBackgroundRect.origin.x, channelBackgroundRect.origin.y - 7);
        CGContextDrawLinearGradient(context, _shadowGradient, startPoint, endPoint, 0);
        
        NSBezierPath *path = [NSBezierPath bezierPathWithRoundedRect:channelBackgroundRect xRadius:10.0 yRadius:10.0];
        [darkBG setFill];
        [path fill];
        
        [[NSColor blackColor] setStroke];
        [path stroke];
    }
    
    // Draw ruler scale
    // numberOfChannels - 1 because we don't want to draw one for the bottom channel
    int firstChannel = (numberOfChannels == 1) ? 0 : 1;
    for (channel = firstChannel; channel < numberOfChannels; channel++) {
        CGFloat rulerY;
        CGFloat rulerGutterSize;
        
        // If there is only one channel, we draw the ruler below the channel, otherwise it is above
        if (numberOfChannels == 1) {
            rulerY = 0;
            rulerGutterSize = GUTTER_SIZE - 7;
        } else {
            rulerY = realDrawRect.size.height - (channelHeight * channel) - GUTTER_SIZE;
            rulerGutterSize = GUTTER_SIZE;
        }
        NSRect rulerRect = NSMakeRect(bounds.origin.x, rulerY,
                                      bounds.size.width, rulerGutterSize);
        
        NSRect intersectRect = NSIntersectionRect(dirtyRect, rulerRect);
        // We want the horizontal intersect, but to make drawing ticks easier we draw the whole height
        intersectRect.size.height = rulerRect.size.height;
        intersectRect.origin.y = rulerRect.origin.y;
        
        [self drawRulerInContext:context inRect:intersectRect onlyDrawTop:(numberOfChannels == 1)];
    }
    
    NSBezierPath *selectionPath = nil;
    NSRect selectionRect;
    
    // Draw the background of the selection before we draw the waveform so it is behind.
    if (_hasSelection) {
        selectionRect = [self selectionToRect];
        
        if (NSIntersectsRect(selectionRect, dirtyRect)) {
            NSColor *selectionBackgroundColour = [NSColor colorWithCalibratedRed:0.2 green:0.2 blue:0.6 alpha:0.75];
            [selectionBackgroundColour setFill];
            
            selectionRect.origin.x += 0.5;
            selectionRect.origin.y += 0.5;
            selectionRect.size.width -= 1;
            selectionRect.size.height -= 1;
            
            selectionPath = [NSBezierPath bezierPathWithRoundedRect:selectionRect xRadius:4.0 yRadius:4.0];
            
            [selectionPath fill];
        }
    }
    
    for (NSUInteger channel = 0; channel < numberOfChannels; channel++) {
        CGContextRef maskContext;
        CGImageRef sampleMask;
        
        channelRect.origin.y = realDrawRect.size.height - (channelHeight * (channel + 1));
        maskRect.origin.y = channelRect.origin.y;
        
        if (NSIntersectsRect(dirtyRect, channelRect) == NO) {
            continue;
        }

        maskContext = [self newMaskContextForRect:scaledRect];
        [_sample drawWaveformInContext:maskContext
                         channelNumber:channel
                                  rect:scaledRect
                    withFramesPerPixel:_framesPerPixel];
        sampleMask = CGBitmapContextCreateImage(maskContext);
        
        CGContextSaveGState(context);
        
        NSRect smallerMaskRect = NSInsetRect(maskRect, 0, 6);
        CGContextClipToMask(context, smallerMaskRect, sampleMask);

        NSColor *waveformColour = [NSColor colorWithCalibratedRed:0.5 green:0.5 blue:0.2 alpha:1.0];
        [waveformColour setFill];
        
        NSRect intersectRect = NSIntersectionRect(smallerMaskRect, dirtyRect);
        
        NSRectFill(intersectRect);
        CGContextRestoreGState(context);
        
        CGImageRelease(sampleMask);
        CGContextRelease(maskContext);
        
        [self drawNameForChannel:channel InRect:maskRect];
    }

    // Draw the outline of the selection over the waveform
    // Checking selectionPath will let us know if the background of the selection needed to be draw
    if (_hasSelection && NSIntersectsRect(dirtyRect, [self selectionRectToDirtyRect:selectionRect]) == YES) {
        [self drawSelectionFrameInRect:selectionRect];
    }
    
    if (_drawCursor && _hasSelection == NO) {
        NSPoint cursorPoint = [self convertFrameToPoint:_cursorFramePosition];
        NSRect cursorRect = NSMakeRect(cursorPoint.x + 0.5, 0, 1, [self bounds].size.height - GUTTER_SIZE);
        if (NSIntersectsRect(cursorRect, dirtyRect)) {
            NSColor *cursorColour = [NSColor colorWithCalibratedWhite:1.0 alpha:_cursorOpacity];
            [cursorColour set];
            
            NSRectFillUsingOperation(cursorRect, NSCompositeSourceOver);
        }
    }
}

- (void)drawSelectionFrameInRect:(NSRect)rect
{
    NSRect outerRect = NSInsetRect(rect, -5.0, 0.0);
    CGFloat x1, y1, x2, y2, midY, handleTopY, handleBottomY;
    NSBezierPath *outerPath = [[NSBezierPath alloc] init];
    
    NSPoint topRight, rightTop, rightBottom, bottomRight;
    NSPoint topLeft, leftTop, bottomLeft, leftBottom;
    
    NSPoint rightHandleLeftTop, rightHandleTop, rightHandleRightTop;
    NSPoint rightHandleRightBottom, rightHandleBottom, rightHandleLeftBottom;
    NSPoint leftHandleLeftTop, leftHandleTop, leftHandleRightTop;
    NSPoint leftHandleLeftBottom, leftHandleBottom, leftHandleRightBottom;
    
    x1 = outerRect.origin.x;
    y1 = outerRect.origin.y;
    x2 = NSMaxX(outerRect);
    y2 = NSMaxY(outerRect);
    
    midY = NSMidY(outerRect);
    handleBottomY = midY - 20.0;
    handleTopY = midY + 20.0;
    
    topRight = NSMakePoint(x2 - 5, y2);
    rightTop = NSMakePoint(x2, y2 - 5);
    rightBottom = NSMakePoint(x2, y1 + 5);
    bottomRight = NSMakePoint(x2 - 5, y1);
    
    topLeft = NSMakePoint(x1 + 5, y2);
    leftTop = NSMakePoint(x1, y2 - 5);
    leftBottom = NSMakePoint(x1, y1 + 5);
    bottomLeft = NSMakePoint(x1 + 5, y1);
    
    // Handle points
    rightHandleLeftTop = NSMakePoint(x2, handleTopY + 2);
    rightHandleTop = NSMakePoint(x2 + 2, handleTopY);
    rightHandleRightTop = NSMakePoint(x2 + 4, handleTopY - 2);
    
    rightHandleRightBottom = NSMakePoint(x2 + 4, handleBottomY + 2);
    rightHandleBottom = NSMakePoint(x2 + 2, handleBottomY);
    rightHandleLeftBottom = NSMakePoint(x2, handleBottomY - 2);
    
    leftHandleLeftTop = NSMakePoint(x1 - 4, handleTopY - 2);
    leftHandleTop = NSMakePoint(x1 - 2, handleTopY);
    leftHandleRightTop = NSMakePoint(x1, handleTopY + 2);
    
    leftHandleLeftBottom = NSMakePoint(x1 - 4, handleBottomY + 2);
    leftHandleBottom = NSMakePoint(x1 - 2, handleBottomY);
    leftHandleRightBottom = NSMakePoint(x1, handleBottomY - 2);
    
    // Top line
    [outerPath moveToPoint:topLeft];
    [outerPath lineToPoint:topRight];
    
    // Top right corner
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2, y2) toPoint:rightTop radius:5.0];
    
    // Right side
    [outerPath lineToPoint:rightHandleLeftTop];
    
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2, handleTopY) toPoint:rightHandleTop radius:2.0];
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2 + 4, handleTopY) toPoint:rightHandleRightTop radius:2.0];
    [outerPath lineToPoint:rightHandleRightBottom];
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2 + 4, handleBottomY) toPoint:rightHandleBottom radius:2.0];
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2, handleBottomY) toPoint:rightHandleLeftBottom radius:2.0];

    [outerPath lineToPoint:rightBottom];
    
    // Bottom right corner
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2, y1) toPoint:bottomRight radius:5.0];
    
    // Bottom line
    [outerPath lineToPoint:bottomLeft];
    
    // Bottom left corner
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x1, y1) toPoint:leftBottom radius:5.0];
    
    // Left side
    [outerPath lineToPoint:leftHandleRightBottom];
    
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x1, handleBottomY) toPoint:leftHandleBottom radius:2.0];
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x1 - 4, handleBottomY) toPoint:leftHandleLeftBottom radius:2.0];
    [outerPath lineToPoint:leftHandleLeftTop];
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x1 - 4, handleTopY) toPoint:leftHandleTop radius:2.0];
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x1, handleTopY) toPoint:leftHandleRightTop radius:2.0];
    
    [outerPath lineToPoint:leftTop];
    
    // Top left corner
    [outerPath appendBezierPathWithArcFromPoint:NSMakePoint(x1, y2) toPoint:topLeft radius:5.0];
    
    NSBezierPath *innerPath;
    
    [outerPath setWindingRule:NSEvenOddWindingRule];
    NSRect innerSelectionRect = NSInsetRect(rect, 0.0, 5.0);
    /*
    innerPath = [NSBezierPath bezierPathWithRoundedRect:innerSelectionRect
                                                xRadius:4.0 yRadius:4.0];
    */
    NSAttributedString *startString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%lu", _selectionStartFrame]];
    NSAttributedString *endString = [[NSAttributedString alloc] initWithString:[NSString stringWithFormat:@"%lu", _selectionEndFrame]];
    NSSize startSize = [startString size];
    NSSize endSize = [endString size];
    
    innerPath = [self innerSelectionPathInRect:innerSelectionRect
                         startStringSize:startSize
                           endStringSize:endSize];
    
    [outerPath appendBezierPath:[innerPath bezierPathByReversingPath]];
    
    [[NSColor colorWithCalibratedRed:0.566 green:0.666 blue:0.796 alpha:1.000] set];
    [outerPath fill];

    if (startSize.width + endSize.width + 25 < innerSelectionRect.size.width) {
        [startString drawAtPoint:NSMakePoint(innerSelectionRect.origin.x, innerSelectionRect.origin.y + 5)];
        [endString drawAtPoint:NSMakePoint(NSMaxX(innerSelectionRect) - [endString size].width - 5, innerSelectionRect.origin.y + 5)];
    }
    
    [[NSColor blackColor] set];
    [outerPath stroke];
}

- (NSBezierPath *)innerSelectionPathInRect:(NSRect)innerSelectionRect
                           startStringSize:(NSSize)startSize
                             endStringSize:(NSSize)endSize
{
    // If the strings don't fit on the selection then tough
    if (startSize.width + endSize.width + 25 > innerSelectionRect.size.width) {
        return [NSBezierPath bezierPathWithRoundedRect:innerSelectionRect
                                               xRadius:4.0 yRadius:4.0];
    }

    NSBezierPath *innerPath = [[NSBezierPath alloc] init];
    
    CGFloat x1, y1, x2, y2;
    
    NSPoint topRight, rightTop, rightBottom, bottomRight, endCorner, endTopCorner;
    NSPoint topLeft, leftTop, bottomLeft;
    
    x1 = innerSelectionRect.origin.x;
    y1 = innerSelectionRect.origin.y;
    x2 = NSMaxX(innerSelectionRect);
    y2 = NSMaxY(innerSelectionRect);
    
    topRight = NSMakePoint(x2 - 5, y2);
    rightTop = NSMakePoint(x2, y2 - 5);
    rightBottom = NSMakePoint(x2, y1 + endSize.height + 15.0);
    bottomRight = NSMakePoint(x2 - 10 - endSize.width, y1);
    endTopCorner = NSMakePoint(bottomRight.x + 5, rightBottom.y - 5);
    endCorner = NSMakePoint(bottomRight.x, rightBottom.y - 5);
    
    topLeft = NSMakePoint(x1 + 5, y2);
    leftTop = NSMakePoint(x1, y2 - 5);
    bottomLeft = NSMakePoint(x1 + 10 + startSize.width, y1);
    
    // Top line
    [innerPath moveToPoint:topLeft];
    [innerPath lineToPoint:topRight];
    
    // Top right corner
    [innerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2, y2) toPoint:rightTop radius:5.0];
    
    // Right side
    [innerPath lineToPoint:rightBottom];
    [innerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2, y1 + endSize.height + 10) toPoint:endCorner radius:5.0];
    
    [innerPath lineToPoint:endTopCorner];
    [innerPath appendBezierPathWithArcFromPoint:endCorner toPoint:NSMakePoint(x2 - endSize.width - 10, y1) radius:5.0];
    
    [innerPath lineToPoint:NSMakePoint(x2-endSize.width - 10, y1 + 5)];
    [innerPath appendBezierPathWithArcFromPoint:NSMakePoint(x2 - endSize.width - 10, y1)
                                        toPoint:NSMakePoint(x2 - endSize.width - 15, y1) radius:5.0];
    
    // Bottom line
    [innerPath lineToPoint:bottomLeft];
    [innerPath appendBezierPathWithArcFromPoint:NSMakePoint(bottomLeft.x - 5, y1)
                                        toPoint:NSMakePoint(bottomLeft.x - 5, y1 + 5) radius:5.0];
    
    [innerPath lineToPoint:NSMakePoint(bottomLeft.x - 5, y1 + startSize.height + 5)];
    [innerPath appendBezierPathWithArcFromPoint:NSMakePoint(bottomLeft.x - 5, y1 + startSize.height + 10)
                                        toPoint:NSMakePoint(bottomLeft.x - 10, y1 + startSize.height + 10)
                                         radius:5.0];
    
    [innerPath lineToPoint:NSMakePoint(x1 + 5, y1 + startSize.height + 10)];
    [innerPath appendBezierPathWithArcFromPoint:NSMakePoint(x1, y1 + startSize.height + 10)
                                        toPoint:NSMakePoint(x1, y1 + startSize.height + 15) radius:5.0];
    // Left side
    [innerPath lineToPoint:leftTop];
    
    // Top left corner
    [innerPath appendBezierPathWithArcFromPoint:NSMakePoint(x1, y2) toPoint:topLeft radius:5.0];
    
    return innerPath;
}

- (void)drawNameForChannel:(NSUInteger)channel
                    InRect:(NSRect)maskRect
{
    static const char *mono[1] = {"Mono"};
    static const char *stereo[2] = {"Left", "Right"};
    static const char *surround51[6] = {"Front Left", "Front Right", "Centre", "Sub", "Surround Left", "Surround Right"};
    static const char *surround71[8] = {"Front Left", "Front Right", "Centre", "Sub", "Surround Left", "Surround Right", "Surround Back Left", "Surround Back Right"};
    
    static const char **channelCountToNamesMap[8] = {mono, stereo, surround51, surround51, surround51, surround51, surround71, surround71};
    
    const char **nameMap = channelCountToNamesMap[[_sample numberOfChannels] - 1];
    NSString *name = [NSString stringWithUTF8String:nameMap[channel]];
    NSDictionary *attrs = @{NSForegroundColorAttributeName: [NSColor lightGrayColor]};
    NSAttributedString *attrString = [[NSAttributedString alloc] initWithString:name attributes:attrs];
    
    NSRect nameRect;
    
    nameRect.size = [attrString size];
    
    CGFloat y = NSMaxY(maskRect) - (nameRect.size.height + 3);
    nameRect.origin = CGPointMake(8, y);
    
    [attrString drawInRect:nameRect];
}

// Calculate the gap between the main ruler ticks.
// Code from original Marlin: https://git.gnome.org/browse/marlin/tree/marlin/marlin-marker-view.c
static int
getIncrementForFramesPerPixel (NSUInteger framesPerPixel)
{
    int increment, i, f, factor;
    
	i = 1;
	f = 100;
	increment = i * f;
    
	/* Go up as 100, 200, 500, 1000, 2000, 5000 and so on... */
	for (factor = 1; ; factor *= 2) {
		if (framesPerPixel <= factor) {
			break;
		}
        
		i++;
		if (i == 3) {
			i = 5;
		} else if (i == 6) {
			i = 1;
			f *= 10;
		}
        
		increment = i * f;
	}
    
	return increment;
}

- (void)drawRulerInContext:(CGContextRef)context
                    inRect:(NSRect)dirtyRect
               onlyDrawTop:(BOOL)onlyDrawTop
{
    NSRect scaledRect = [self convertRectToBacking:dirtyRect];
    NSUInteger firstFrame = scaledRect.origin.x * _framesPerPixel;
    int increment = getIncrementForFramesPerPixel(_framesPerPixel);
    
    NSUInteger modIncrement = firstFrame % increment;
    NSUInteger firstMarkFrame = firstFrame - modIncrement;
    
    CGFloat maxY = NSMaxY(dirtyRect);
    NSUInteger maxX = NSMaxX(scaledRect) * _framesPerPixel;
    
    // Need to draw to the next major marker
    // to make sure that the label is drawn
    int modLast = maxX % increment;
    maxX += (increment - modLast);
    
    for (NSUInteger i = firstMarkFrame; i <= maxX; i += increment) {
        CGPoint markPoint = [self convertFrameToPoint:i];
        if (onlyDrawTop == NO) {
            CGContextMoveToPoint(context, markPoint.x + 0.5, dirtyRect.origin.y);
            CGContextAddLineToPoint(context, markPoint.x + 0.5, dirtyRect.origin.y + 5);
        }
        
        CGContextMoveToPoint(context, markPoint.x + 0.5, maxY);
        CGContextAddLineToPoint(context, markPoint.x + 0.5, maxY - 5);

        NSUInteger minorGap = increment / 10;
        NSUInteger j;
        int iter;
        
        for (j = i + minorGap, iter = 0; j < i + increment; j += minorGap, iter++) {
            CGPoint minorPoint = [self convertFrameToPoint:j];
            CGFloat length = (iter == 4) ? 3.5 : 2;
            
            if (onlyDrawTop == NO) {
                CGContextMoveToPoint(context, minorPoint.x + 0.5, dirtyRect.origin.y);
                CGContextAddLineToPoint(context, minorPoint.x + 0.5, dirtyRect.origin.y + length);
            }
            CGContextMoveToPoint(context, minorPoint.x + 0.5, maxY);
            CGContextAddLineToPoint(context, minorPoint.x + 0.5, maxY - length);
        }

        CGContextSetRGBStrokeColor(context, 0, 0, 0, 1.0);
        CGContextStrokePath(context);
        
        NSString *label = [NSString stringWithFormat:@"%lu", i];
        NSAttributedString *attrLabel = [[NSAttributedString alloc] initWithString:label];
        NSSize labelSize = [attrLabel size];
        
        CGFloat x = markPoint.x - (labelSize.width / 2) + 0.5;

        // Make sure the label is all on screen at both 0
        if (x < 0) {
            x = 0;
        }
        
        // and at the end of the view
        NSRect bounds = [self bounds];
        if (x + labelSize.width > bounds.size.width) {
            x = bounds.size.width - labelSize.width;
        }
        // 4 is kind of a magic number deduced by trial and error
        // labelSize seems to add padding I guess.
        [label drawAtPoint:NSMakePoint(x, maxY - (4 + labelSize.height)) withAttributes:nil];
    }
    
}

#pragma mark - accessors

static void *sampleContext = &sampleContext;

- (void)sampledLoadedHandler
{
    CGFloat iw = [_sample numberOfFrames] / (_framesPerPixel);
    NSSize size = NSMakeSize(iw, 10);
    NSSize scaledSize = [self convertSizeFromBacking:size];
    
    _intrinsicWidth = scaledSize.width;
    
    DDLogVerbose(@"Sample loaded handler: numberOfFrames: %lu", [_sample numberOfFrames]);
    DDLogVerbose(@"%lu %@ -> %@", _framesPerPixel, NSStringFromSize(size), NSStringFromSize(scaledSize));
    [self setNeedsDisplay:YES];
    
    [self invalidateIntrinsicContentSize];
}

- (void)observeValueForKeyPath:(NSString *)keyPath
                      ofObject:(id)object
                        change:(NSDictionary *)change
                       context:(void *)context
{
    if (context != sampleContext) {
        [super observeValueForKeyPath:keyPath ofObject:object change:change context:context];
        return;
    }
    
    if ([keyPath isEqualToString:@"loaded"]) {
        [self sampledLoadedHandler];
        return;
    }
    
    if ([keyPath isEqualToString:@"numberOfFrames"]) {
        [self sampledLoadedHandler];
        return;
    }
}

- (void)setSample:(MLNSample *)sample
{
    if (sample == _sample) {
        return;
    }

    [self removeObserversFromSample:_sample];
    
    _sample = sample;

    NSNotificationCenter *nc = [NSNotificationCenter defaultCenter];
    [nc addObserver:self
           selector:@selector(sampleDataDidChangeInRange:)
               name:kMLNSampleDataDidChangeInRange
             object:sample];
    
    if ([_sample isLoaded]) {
        [self sampledLoadedHandler];
    } else {
        [_sample addObserver:self
                  forKeyPath:@"loaded"
                     options:0
                     context:sampleContext];
        [_sample addObserver:self
                  forKeyPath:@"numberOfFrames"
                     options:0
                     context:sampleContext];
    }
}

- (void)setFramesPerPixel:(NSUInteger)framesPerPixel
{
    if (_framesPerPixel == framesPerPixel) {
        return;
    }
    
    if (framesPerPixel < 1) {
        framesPerPixel = 1;
    }
    
    _framesPerPixel = framesPerPixel;
    
    NSSize intrinsicSize = NSMakeSize([_sample numberOfFrames] / (_framesPerPixel), 0.0);
    NSSize scaledSize = [self convertSizeFromBacking:intrinsicSize];
    
    _intrinsicWidth = scaledSize.width;
    
    [self setNeedsDisplay:YES];
    [self invalidateIntrinsicContentSize];
    
    if (_hasSelection) {
        NSRect selectionRect = [self selectionToRect];
        [self repositionSelectionResizeTrackingAreas:selectionRect];
        [self updateSelectionToolbarInSelectionRect:selectionRect];
        [self setDragHandleForPoint:[self convertPoint:[NSEvent mouseLocation] fromView:nil]];
    }
}

- (NSUInteger)framesPerPixel
{
    return _framesPerPixel;
}

- (void)setFrameSize:(NSSize)newSize
{
    [super setFrameSize:newSize];
    
    // If we have a toolbar, then we may need to reposition it
    if (_hasSelection) {
        NSRect selectionRect = [self selectionToRect];
        [self repositionSelectionResizeTrackingAreas:selectionRect];
        [self updateSelectionToolbarInSelectionRect:selectionRect];
    }
}

- (void)setVisibleRange:(NSRange)newVisibleRange
{
    NSRect visibleRect = [self visibleRect];
    NSRect scaledRect = [self convertRectToBacking:visibleRect];
    
    NSUInteger newFramesPerPixel = (NSUInteger)((CGFloat)newVisibleRange.length / scaledRect.size.width);
    
    [self updateScrollPositionForNewZoom:newFramesPerPixel offset:newVisibleRange.location];
}

#pragma mark - Notifications
- (void)sampleDataDidChangeInRange:(NSNotification *)note
{
    NSDictionary *userInfo = [note userInfo];
    NSValue *value = userInfo[@"range"];
    NSRange range = [value rangeValue];
    
    NSRect changedRect = NSMakeRect(range.location / _framesPerPixel, 0,
                                    range.length / _framesPerPixel, [self bounds].size.height);
    
    DDLogVerbose(@"Sample changed: %@ %@", NSStringFromRange(range), NSStringFromRect(changedRect));
    [self setNeedsDisplayInRect:changedRect];
}

#pragma mark - Events

- (NSUInteger)convertPointToFrame:(NSPoint)point
{
    NSPoint scaledPoint = [self convertPointToBacking:point];
    CGFloat x = (scaledPoint.x < 0) ? 0: scaledPoint.x;
    
    return (x * _framesPerPixel);
}

- (NSPoint)convertFrameToPoint:(NSUInteger)frame
{
    NSPoint scaledPoint = NSMakePoint(frame / _framesPerPixel, 0.0);
    return [self convertPointFromBacking:scaledPoint];
}

- (void)mouseDown:(NSEvent *)event
{
    NSUInteger possibleStartFrame = 0;
    
    if ([event type] != NSLeftMouseDown) {
        return;
    }
    
    // Store the current selection in case we need to remove it on mouseUp
    NSRect selectionRect = [self selectionToRect];
    
    // Possible selection start
    NSPoint mouseLoc = [self convertPoint:[event locationInWindow] fromView:nil];
    NSPoint startPoint = mouseLoc;
    NSPoint lastPoint = mouseLoc;
    BOOL insideSelection = NO;
    
    if (_dragHandle == DragHandleNone) {
        possibleStartFrame = [self convertPointToFrame:startPoint];
        insideSelection = _hasSelection ? (possibleStartFrame >= _selectionStartFrame && possibleStartFrame <= _selectionEndFrame) : NO;
    }
    
    // Grab the mouse and handle everything in a modal event loop
    NSUInteger eventMask = NSLeftMouseDraggedMask | NSLeftMouseUpMask | NSPeriodicMask;
    NSEvent *nextEvent;
    BOOL dragged = NO;
    BOOL timerOn = NO;
    
    while ((nextEvent = [[self window] nextEventMatchingMask:eventMask])) {
        NSRect visibleRect = [self visibleRect];
        
        switch ([nextEvent type]) {
            case NSPeriodic:
                if (insideSelection == NO) {
                    [self resizeSelection:_dragEvent];
                } else {
                    NSPoint newMouseLoc = [self convertPoint:[_dragEvent locationInWindow] fromView:nil];
                    CGFloat dx = newMouseLoc.x - lastPoint.x;
                    NSPoint scaledDX;
                    
                    scaledDX = [self convertPointToBacking:NSMakePoint(dx, 0)];
                    [self moveSelectionByOffset:scaledDX.x];
                    
                    lastPoint = newMouseLoc;
                }
                [self autoscroll:_dragEvent];
                break;
                
            case NSLeftMouseDragged:
                if (dragged == NO && _dragHandle == DragHandleNone && !insideSelection) {
                    if (_hasSelection) {
                        [self clearSelection];
                    }
                    _selectionStartFrame = possibleStartFrame;
                    _selectionEndFrame = possibleStartFrame;
                    _selectionDirection = 1;
                }

                mouseLoc = [self convertPoint:[nextEvent locationInWindow] fromView:nil];
                if (![self mouse:mouseLoc inRect:visibleRect]) {
                    if (timerOn == NO) {
                        [NSEvent startPeriodicEventsAfterDelay:0.1 withPeriod:0.1];
                        timerOn = YES;
                    }
                    _dragEvent = nextEvent;
                    break;
                } else if (timerOn) {
                    [NSEvent stopPeriodicEvents];
                    timerOn = NO;
                    _dragEvent = nil;
                }
            
                if (mouseLoc.x != startPoint.x) {
                    dragged = YES;
                    if (insideSelection == NO) {
                        [self resizeSelection:nextEvent];
                    } else {
                        CGFloat dx = mouseLoc.x - lastPoint.x;
                        NSPoint scaledDX;
                        
                        scaledDX = [self convertPointToBacking:NSMakePoint(dx, 0)];
                        [self moveSelectionByOffset:scaledDX.x];
                        
                        lastPoint = mouseLoc;
                    }
                }
                
                /* I'm not happy with how this works out, but I still think it's a good idea.
                 * Idea is that as you select, vertical movement changes zoom so you can refine the
                 * selection easier, or to quickly select a larger area than the working zoom would allow */
                /*
                zoomLoc = [nextEvent locationInWindow];
                if (zoomLoc.y != zoomPoint.y) {
                    CGFloat dZoom = (zoomLoc.y - zoomPoint.y) / 1000.0;
                    CGFloat offset = zoomLoc.x - [self visibleRect].origin.x;

                    DDLogVerbose(@"dZoom: %f", dZoom);
                    //[self setFramesPerPixel:[self calculateFramesPerPixelForMagnification:dZoom]];
                    [self magnify:dZoom atFrame:mouseLoc.x * _framesPerPixel offset:offset];
                    
                    zoomPoint = zoomLoc;
                }
                 */
                break;
                
            case NSLeftMouseUp:
                [NSEvent stopPeriodicEvents];
                _dragEvent = nil;
                
                mouseLoc = [self convertPoint:[nextEvent locationInWindow] fromView:nil];
                if (!insideSelection) {
                    // If we weren't inside a selection, then we were in one of the tracking areas.
                    // Work out which one.
                    if (mouseLoc.x < startPoint.x) {
                        _dragHandle = DragHandleStart;
                    } else if (mouseLoc.x > startPoint.x) {
                        _dragHandle = DragHandleEnd;
                    }
                }
                
                if (dragged == NO) {
                    _selectionStartFrame = 0;
                    _selectionEndFrame = 0;
                    _hasSelection = NO;
                    [self selectionChanged];

                    // Move the cursor
                    [self moveCursorTo:possibleStartFrame];

                    [self removeTrackingArea:_startTrackingArea];
                    //[self removeTrackingArea:_endTrackingArea];
                    _startTrackingArea = nil;
                    //_endTrackingArea = nil;
                    
                    [self removeSelectionToolbar];
                    
                    selectionRect.size.width += 0.5;
                    
                    [self setNeedsDisplayInRect:[self selectionRectToDirtyRect:selectionRect]];
                }

                return;
                
            default:
                break;
        }
    }
    
    _dragEvent = nil;
}

- (void)setDragHandleForPoint:(NSPoint)mouseLoc
{
    NSRect trackingRect = [_startTrackingArea rect];
    
    if (mouseLoc.x >= trackingRect.origin.x && mouseLoc.x <= trackingRect.origin.x + 15) {
        _dragHandle = DragHandleStart;
    } else if (mouseLoc.x >= NSMaxX(trackingRect) - 15 && mouseLoc.x <= NSMaxX(trackingRect)) {
        _dragHandle= DragHandleEnd;
    } else {
        _dragHandle = DragHandleNone;
    }
}

- (void)setDragHandleForEvent:(NSEvent *)event
{
    NSPoint mouseLoc = [self convertPoint:[event locationInWindow] fromView:nil];
    [self setDragHandleForPoint:mouseLoc];
}

- (void)mouseMoved:(NSEvent *)theEvent
{
    [self setDragHandleForEvent:theEvent];
    [self cursorUpdate:theEvent];
}

- (void)mouseEntered:(NSEvent *)event
{
    [self setDragHandleForEvent:event];
}

- (void)mouseExited:(NSEvent *)event
{
    _dragHandle = DragHandleNone;
}

- (void)cursorUpdate:(NSEvent *)event
{
    if (_dragHandle != DragHandleNone) {
        [[NSCursor resizeLeftRightCursor] set];
    } else {
        [super cursorUpdate:event];
    }
}

- (NSUInteger)calculateFramesPerPixelForMagnification:(CGFloat)magnification
{
    NSUInteger fpp;
    CGFloat dfpp = (_framesPerPixel * magnification);
    if (ABS(dfpp) < 1) {
        if (magnification < 0) {
            dfpp = -1;
        } else {
            dfpp = 1;
        }
    }
    fpp = _framesPerPixel - dfpp;
    
    if (fpp < 1) {
        fpp = 1;
    }
    
    if (fpp > 65536) {
        fpp = 65536;
    }
    
    return fpp;
}

- (void)magnify:(CGFloat)magnification
        atFrame:(NSInteger)atFrame
         offset:(CGFloat)offset
{
    NSUInteger fpp;
    
    fpp = [self calculateFramesPerPixelForMagnification:magnification];
    
    [self setFramesPerPixel:fpp];
    
    NSInteger newPosition = (atFrame / fpp) - offset;
    [self scrollPoint:CGPointMake(newPosition, 0)];
}

- (void)magnifyWithEvent:(NSEvent *)event
{
    NSPoint locationInView = [self convertPoint:[event locationInWindow] fromView:nil];
    NSInteger zoomFrame = locationInView.x * _framesPerPixel;
    CGFloat dx = locationInView.x - [self visibleRect].origin.x;
    
    [self magnify:[event magnification] atFrame:zoomFrame offset:dx];
}

#pragma mark - Zoom handling

- (void)updateScrollPositionForNewZoom:(NSUInteger)newFramesPerPixel
                                offset:(NSUInteger)offsetFrame
{
    NSScrollView *scrollView = [self enclosingScrollView];
    NSClipView *clipView = [scrollView contentView];
    
    NSUInteger zoomFrame = [clipView bounds].origin.x * _framesPerPixel;
    
    if (newFramesPerPixel < 1) {
        newFramesPerPixel = 1;
    } else if (newFramesPerPixel > 65536) {
        newFramesPerPixel = 65536;
    }
    
    [self setFramesPerPixel:newFramesPerPixel];
    
    if (offsetFrame == (NSUInteger)-1) {
        NSUInteger newPosition = (zoomFrame / newFramesPerPixel);
        [self scrollPoint:NSMakePoint(newPosition, 0)];
    } else {
        NSPoint scrollPoint = [self convertFrameToPoint:offsetFrame];
        [self scrollPoint:scrollPoint];
    }
}

- (void)zoomIn
{
    NSUInteger newFramesPerPixel = _framesPerPixel / 2;
    
    [self updateScrollPositionForNewZoom:newFramesPerPixel offset:-1];
}

- (void)zoomOut
{
    NSUInteger newFramesPerPixel = _framesPerPixel * 2;
    
    [self updateScrollPositionForNewZoom:newFramesPerPixel offset:-1];
}

- (void)zoomToFit
{
    NSScrollView *scrollView = [self enclosingScrollView];
    NSClipView *clipView = [scrollView contentView];
    
    NSRect scaledWidth = [self convertRectToBacking:[clipView bounds]];
    
    NSUInteger newFramesPerPixel = [_sample numberOfFrames] / scaledWidth.size.width;
    [self updateScrollPositionForNewZoom:newFramesPerPixel offset:-1];
}

- (void)zoomToNormal
{
    [self updateScrollPositionForNewZoom:DEFAULT_FRAMES_PER_PIXEL offset:-1];
}
#pragma mark - Selection handling

- (NSRange)selection
{
    return NSMakeRange(_selectionStartFrame, _selectionEndFrame - _selectionStartFrame);
}

- (void)setSelection:(NSRange)selection
{
    if (selection.length == 0) {
        [self clearSelection];
        return;
    }
    
    NSRect oldSelectionRect = [self selectionToRect];
    
    _selectionStartFrame = selection.location;
    _selectionEndFrame = NSMaxRange(selection);
    _hasSelection = YES;
    
    NSRect newSelectionRect = [self selectionToRect];
    
    //DDLogWarn(@"Selection: %lu, %lu (%@)", _selectionStartFrame, _selectionEndFrame, NSStringFromRect(newSelectionRect));
    [self updateSelection:newSelectionRect oldSelectionRect:oldSelectionRect];
}

static NSRect
subtractSelectionRects (NSRect a, NSRect b)
{
    if (a.origin.x == b.origin.x) {
        if (a.size.width < b.size.width) {
            return NSMakeRect(NSMaxX(a), 0, b.size.width - a.size.width, a.size.height);
        } else {
            return NSMakeRect(NSMaxX(b), 0, a.size.width - b.size.width, a.size.height);
        }
    } else {
        if (a.size.width < b.size.width) {
            return NSMakeRect(NSMinX(b), 0, b.size.width - a.size.width, a.size.height);
        } else {
            return NSMakeRect(NSMinX(a), 0, a.size.width - b.size.width, a.size.height);
        }
    }
}

- (void)selectionChanged
{
    NSRange selectionRange = NSMakeRange(_selectionStartFrame, _selectionEndFrame - _selectionStartFrame);
    
    if ([_delegate respondsToSelector:@selector(sampleView:selectionDidChange:)]) {
        [_delegate sampleView:self
           selectionDidChange:selectionRange];
    }
}

- (NSRect)selectionToRect
{
    if (!_hasSelection) {
        return NSZeroRect;
    }
    
    NSPoint startPoint = [self convertFrameToPoint:_selectionStartFrame];
    NSUInteger selectionFrameWidth = _selectionEndFrame - _selectionStartFrame;
    
    // Overload NSPoint here to convert a frame to the backing store pixel format
    NSPoint selectionWidth = [self convertFrameToPoint:selectionFrameWidth];
    NSRect selectionRect = NSMakeRect(startPoint.x, 0, selectionWidth.x, [self bounds].size.height - GUTTER_SIZE);
    
    return selectionRect;
}

// Take into consideration the handles of the visible selection
- (NSRect)selectionRectToDirtyRect:(NSRect)selectionRect
{
    return NSInsetRect(selectionRect, -10.0, 0.0);
}

- (void)repositionSelectionResizeTrackingAreas:(NSRect)newSelectionRect
{
    NSRect trackingRect = NSInsetRect(newSelectionRect, -10, 0);
    if (_startTrackingArea) {
        [self removeTrackingArea:_startTrackingArea];
        _startTrackingArea = nil;
    }
    
    _startTrackingArea = [[NSTrackingArea alloc] initWithRect:trackingRect
                                                      options:NSTrackingCursorUpdate | NSTrackingMouseEnteredAndExited |
                                                        NSTrackingMouseMoved | NSTrackingActiveInActiveApp
                                                        owner:self
                                                     userInfo:nil];
    [self addTrackingArea:_startTrackingArea];
}

- (void)updateSelection:(NSRect)newSelectionRect
       oldSelectionRect:(NSRect)oldSelectionRect
{
    [self repositionSelectionResizeTrackingAreas:newSelectionRect];
    
    [self updateSelectionToolbarInSelectionRect:newSelectionRect];
    [self selectionChanged];
    
    // Only redraw the changed selection
    if (!NSEqualRects(oldSelectionRect, NSZeroRect)) {
        oldSelectionRect.size.width += 0.5;
        [self setNeedsDisplayInRect:[self selectionRectToDirtyRect:oldSelectionRect]];
    }
    
    newSelectionRect.size.width += 0.5;
    [self setNeedsDisplayInRect:[self selectionRectToDirtyRect:newSelectionRect]];
}

- (void)moveSelectionByOffset:(CGFloat)offset
{
    NSUInteger offsetFrames = offset * _framesPerPixel;
    NSRect oldSelectionRect = [self selectionToRect];
    NSUInteger frameCount = _selectionEndFrame - _selectionStartFrame;
    
    _selectionStartFrame += offsetFrames;
    _selectionEndFrame += offsetFrames;
    
    if (((NSInteger)_selectionStartFrame) < 0) {
        _selectionStartFrame = 0;
        _selectionEndFrame = frameCount;
    } else if (_selectionEndFrame >= [_sample numberOfFrames]) {
        _selectionEndFrame = [_sample numberOfFrames] - 1;
        _selectionStartFrame = _selectionEndFrame - frameCount;
    }
    
    NSRect newSelectionRect = [self selectionToRect];
    
    [self updateSelection:newSelectionRect
         oldSelectionRect:oldSelectionRect];
}

- (void)resizeSelection:(NSEvent *)event
{
    NSPoint endPoint = [self convertPoint:[event locationInWindow] fromView:nil];
    
    NSUInteger tmp = [self convertPointToFrame:endPoint];
    NSUInteger otherEnd;
 
    NSRect oldSelectionRect = [self selectionToRect];
    
    if (tmp >= [_sample numberOfFrames]) {
        tmp = [_sample numberOfFrames] - 1;
    }
    
    if (_dragHandle == DragHandleStart) {
        if (tmp >= _selectionEndFrame) {
            tmp = _selectionEndFrame - _framesPerPixel;
        }
        
        if (tmp <= 0) {
            tmp = 0;
        }
        
        _selectionStartFrame = tmp;
    } else if (_dragHandle == DragHandleEnd) {
        if (tmp <= _selectionStartFrame) {
            tmp = _selectionStartFrame + _framesPerPixel;
        }
        
        if (tmp >= [_sample numberOfFrames]) {
            tmp = [_sample numberOfFrames] - 1;
        }
        
        _selectionEndFrame = tmp;
    } else {
        if (_selectionDirection == -1) {
            otherEnd = _selectionEndFrame;
        } else {
            otherEnd = _selectionStartFrame;
        }

        int newDirection = (tmp < otherEnd) ? -1 : 1;
        BOOL directionChange = (newDirection != _selectionDirection);
        
        if (directionChange) {
            NSUInteger startTmp = _selectionStartFrame;
            _selectionStartFrame = _selectionEndFrame;
            _selectionEndFrame = startTmp;
        }
        
        _selectionDirection = newDirection;
        if (_selectionDirection == -1) {
            _selectionStartFrame = tmp;
        } else {
            _selectionEndFrame = tmp;
        }
    }
    
    _hasSelection = YES;
    
    NSRect newSelectionRect = [self selectionToRect];
    
    [self updateSelection:newSelectionRect
         oldSelectionRect:oldSelectionRect];
}

- (void)clearSelection
{
    NSRect selectionRect = [self selectionToRect];
    
    if (_selectionToolbar) {
        [self removeSelectionToolbar];
    }
    
    _selectionStartFrame = 0;
    _selectionEndFrame = 0;
    _hasSelection = NO;
    [self selectionChanged];
    
    [self removeTrackingArea:_startTrackingArea];
    //[self removeTrackingArea:_endTrackingArea];
    _startTrackingArea = nil;
    _dragHandle = DragHandleNone;
    //_endTrackingArea = nil;
    
    selectionRect.size.width += 0.5;
    [self setNeedsDisplayInRect:[self selectionRectToDirtyRect:selectionRect]];
    DDLogVerbose(@"Mouse up: No drag %@", NSStringFromRect(selectionRect));
}

- (void)removeSelectionToolbar
{
    [_selectionToolbar removeFromSuperview];
    _selectionToolbar = nil;
    _toolbarConstraints = nil;
    _toolbarXConstraint = nil;
}

#define X_DISTANCE_FROM_OUTER_FRAME 10.0
#define X_DISTANCE_FROM_INNER_FRAME 5.0
- (void)updateSelectionToolbarInSelectionRect:(NSRect)newSelectionRect
{
    if (_selectionToolbar == nil) {
        if (![_delegate respondsToSelector:@selector(sampleViewWillShowSelectionToolbar)]) {
            return;
        }
        
        NSArray *toolbarItems = [_delegate sampleViewWillShowSelectionToolbar];
        if ([toolbarItems count] == 0) {
            return;
        }
        
        _selectionToolbar = [[MLNSelectionToolbar alloc] initWithFrame:NSZeroRect];
        for (MLNSelectionAction *action in toolbarItems) {
            MLNSelectionButton *button = [[MLNSelectionButton alloc] initWithAction:action];
            
            [_selectionToolbar addSubview:button];
        }
        
        [_selectionToolbar setTranslatesAutoresizingMaskIntoConstraints:NO];
        [self addSubview:_selectionToolbar];
        
        NSDictionary *viewsDict = @{@"toolbar": _selectionToolbar};
        NSDictionary *verticalMetrics = @{@"offset": @(GUTTER_SIZE + 10.0)};
        
        // Setup the constraint that pins the toolbar to the top of the view
        NSArray *constraints = [NSLayoutConstraint constraintsWithVisualFormat:@"V:|-offset-[toolbar]"
                                                                       options:0
                                                                       metrics:verticalMetrics
                                                                         views:viewsDict];
        _toolbarConstraints = [NSMutableArray arrayWithArray:constraints];
        [self addConstraints:_toolbarConstraints];
 
        // The X constraint is set correctly below.
        _toolbarXConstraint = nil;
    }

    NSSize intrinsicSize = [_selectionToolbar intrinsicContentSize];
    CGFloat widthIfTheToolbarWasHorizontal = [_selectionToolbar isHorizontal] ? intrinsicSize.width : intrinsicSize.height;

    if (widthIfTheToolbarWasHorizontal + 20.0 > newSelectionRect.size.width) {
        // Toolbar is too big to put into the selection. Put it on its side and along the edge
        
        if ([_selectionToolbar isHorizontal]) {
            // Switching to side
            [_selectionToolbar setHorizontal:NO];
            
            // Because the toolbar has been fliped to vertical, we need to get the intrinsic size again
            intrinsicSize = [_selectionToolbar intrinsicContentSize];
            
            [self removeConstraint:_toolbarXConstraint];
            
            // Now we work out which side of the selection it should be on
            if ((NSMaxX(newSelectionRect) + intrinsicSize.width + X_DISTANCE_FROM_OUTER_FRAME) > NSMaxX([self bounds])) {
                _toolbarXConstraint = [NSLayoutConstraint constraintWithItem:_selectionToolbar
                                                                   attribute:NSLayoutAttributeRight
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:self
                                                                   attribute:NSLayoutAttributeLeft
                                                                  multiplier:0
                                                                    constant:newSelectionRect.origin.x - X_DISTANCE_FROM_OUTER_FRAME];
                _toolbarIsOnRight = NO;
            } else {
                _toolbarXConstraint = [NSLayoutConstraint constraintWithItem:_selectionToolbar
                                                                   attribute:NSLayoutAttributeLeft
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:self
                                                                   attribute:NSLayoutAttributeLeft
                                                                  multiplier:0
                                                                    constant:NSMaxX(newSelectionRect) + X_DISTANCE_FROM_OUTER_FRAME];
                _toolbarIsOnRight = YES;
            }
            
            [self addConstraint:_toolbarXConstraint];
        } else {
            // Toolbar is already vertical.
            
            // Check if the toolbar is on the correct side
            BOOL changeSide = NO;
            
            if ((NSMaxX(newSelectionRect) + intrinsicSize.width + X_DISTANCE_FROM_OUTER_FRAME) > NSMaxX([self bounds])) {
                if (_toolbarIsOnRight) {
                    changeSide = YES;
                }
            } else {
                if (!_toolbarIsOnRight) {
                    changeSide = YES;
                }
            }
            
            // Reposition
            if (changeSide) {
                [self removeConstraint:_toolbarXConstraint];
                if (_toolbarIsOnRight) {
                    _toolbarXConstraint = [NSLayoutConstraint constraintWithItem:_selectionToolbar
                                                                       attribute:NSLayoutAttributeRight
                                                                       relatedBy:NSLayoutRelationEqual
                                                                          toItem:self
                                                                       attribute:NSLayoutAttributeLeft
                                                                      multiplier:0
                                                                        constant:newSelectionRect.origin.x - X_DISTANCE_FROM_OUTER_FRAME];
                    _toolbarIsOnRight = NO;
                } else {
                    _toolbarXConstraint = [NSLayoutConstraint constraintWithItem:_selectionToolbar
                                                                       attribute:NSLayoutAttributeLeft
                                                                       relatedBy:NSLayoutRelationEqual
                                                                          toItem:self
                                                                       attribute:NSLayoutAttributeLeft
                                                                      multiplier:0
                                                                        constant:NSMaxX(newSelectionRect) + X_DISTANCE_FROM_OUTER_FRAME];
                    _toolbarIsOnRight = YES;
                }
                [self addConstraint:_toolbarXConstraint];
            } else {
                // Don't need to change the side, just set the constant
                CGFloat newConstant;
                
                if (!_toolbarIsOnRight) {
                    newConstant = newSelectionRect.origin.x - X_DISTANCE_FROM_OUTER_FRAME;
                } else {
                    newConstant = NSMaxX(newSelectionRect) + X_DISTANCE_FROM_OUTER_FRAME;
                }
                
                [_toolbarXConstraint setConstant:newConstant];
            }
        }
    } else {
        if ([_selectionToolbar isHorizontal]) {
            if (_toolbarXConstraint == nil) {
                _toolbarXConstraint = [NSLayoutConstraint constraintWithItem:_selectionToolbar
                                                                   attribute:NSLayoutAttributeRight
                                                                   relatedBy:NSLayoutRelationEqual
                                                                      toItem:self
                                                                   attribute:NSLayoutAttributeLeft
                                                                  multiplier:0
                                                                    constant:NSMaxX(newSelectionRect) - X_DISTANCE_FROM_INNER_FRAME];
                [self addConstraint:_toolbarXConstraint];
            } else {
                [_toolbarXConstraint setConstant:NSMaxX(newSelectionRect) - X_DISTANCE_FROM_INNER_FRAME];
            }
        } else {
            // Switch to horizontal and reposition
            [_selectionToolbar setHorizontal:YES];
            
            [self removeConstraint:_toolbarXConstraint];
            _toolbarXConstraint = [NSLayoutConstraint constraintWithItem:_selectionToolbar
                                                               attribute:NSLayoutAttributeRight
                                                               relatedBy:NSLayoutRelationEqual
                                                                  toItem:self
                                                               attribute:NSLayoutAttributeLeft
                                                              multiplier:0
                                                                constant:NSMaxX(newSelectionRect) - X_DISTANCE_FROM_INNER_FRAME];
            [self addConstraint:_toolbarXConstraint];
        }
    }
}

#pragma mark - Cursor
// FIXME We should pause the cursor when it's off screen
- (void)resetCursorTimer:(NSTimeInterval)interval
            withSelector:(SEL)selector
{
    [_cursorTimer invalidate];
    _cursorTimer = [NSTimer scheduledTimerWithTimeInterval:interval
                                                    target:self
                                                  selector:selector
                                                  userInfo:nil
                                                   repeats:YES];
}

- (void)pauseCursor:(NSTimer *)timer
{
    if (_cursorOpacity >= CURSOR_MAX_OPACITY) {
        [self resetCursorTimer:CURSOR_FADE_TIME withSelector:@selector(decreaseCursorOpacity:)];
    } else {
        _cursorOpacity = CURSOR_MIN_OPACITY;
        [self resetCursorTimer:CURSOR_FADE_TIME withSelector:@selector(increaseCursorOpacity:)];
    }
}

- (void)increaseCursorOpacity:(NSTimer *)timer
{
    _cursorOpacity += 0.05;
    [self invalidateCursor:timer];
}

- (void)decreaseCursorOpacity:(NSTimer *)timer
{
    _cursorOpacity -= 0.05;
    if (_cursorOpacity <= CURSOR_MIN_OPACITY) {
        _cursorOpacity = 0.0;
    }
    [self invalidateCursor:timer];
}

- (void)invalidateCursor:(NSTimer *)timer
{
    NSPoint cursorPoint = [self convertFrameToPoint:_cursorFramePosition];
    
    NSRect cursorRect = NSMakeRect(cursorPoint.x + 0.5, 0.0, 1.0, [self bounds].size.height);
    [self setNeedsDisplayInRect:cursorRect];
    
    if (_cursorOpacity <= 0.0 || _cursorOpacity >= CURSOR_MAX_OPACITY) {
        _cursorOpacityDirection = !_cursorOpacityDirection;
        [self resetCursorTimer:CURSOR_PAUSE_TIME withSelector:@selector(pauseCursor:)];
    }
}

- (void)moveCursorTo:(NSUInteger)cursorFrame
{
    NSPoint cursorPoint = [self convertFrameToPoint:_cursorFramePosition];
    
    DDLogVerbose(@"old cursor at %@", NSStringFromPoint(cursorPoint));
    // Invalidate the old cursor
    NSRect cursorRect = NSMakeRect(cursorPoint.x + 0.5, 0.0, 1.0, [self bounds].size.height);
    [self setNeedsDisplayInRect:cursorRect];
    
    _cursorFramePosition = cursorFrame;

    // Now invalidate the new cursor
    cursorPoint = [self convertFrameToPoint:cursorFrame];

    cursorRect = NSMakeRect(cursorPoint.x + 0.5, 0.0, 1.0, [self bounds].size.height);
    _drawCursor = YES;
    
    _cursorOpacity = CURSOR_MAX_OPACITY;
    [self setNeedsDisplayInRect:cursorRect];
}

- (void)centreOnCursor
{
    NSPoint cursorPoint = [self convertFrameToPoint:_cursorFramePosition];
    NSScrollView *scrollView = [self enclosingScrollView];
    NSClipView *clipView = (NSClipView *)[scrollView contentView];
    
    NSRect cvBounds = [clipView bounds];
    float halfWidth = NSWidth(cvBounds) / 2;
    
    [self scrollPoint:NSMakePoint(MAX(0, cursorPoint.x - halfWidth), 0.0)];
}

#pragma mark - Debugging

// Writes a CGImageRef to a PNG file
void CGImageWriteToFile(CGImageRef image, NSURL *fileURL) {
    CFURLRef url = (__bridge CFURLRef)fileURL;
    CGImageDestinationRef destination = CGImageDestinationCreateWithURL(url, kUTTypePNG, 1, NULL);
    CGImageDestinationAddImage(destination, image, nil);
    
    if (!CGImageDestinationFinalize(destination)) {
        NSLog(@"Failed to write image to %@", [fileURL path]);
    } else {
        NSLog(@"Wrote image to %@", [fileURL path]);
    }
    
    CFRelease(destination);
}

- (void)dumpCacheImage
{
    /*
    static int count = 0;
    NSString *filename = [NSString stringWithFormat:@"cacheDump-%d.png", count];
    MLNApplicationDelegate *appDelegate = [NSApp delegate];
    
    NSURL *url = [[appDelegate cacheURL] URLByAppendingPathComponent:filename];
    
    count++;
    
    CGImageWriteToFile(_sampleMask, url);
     */
}

@end
