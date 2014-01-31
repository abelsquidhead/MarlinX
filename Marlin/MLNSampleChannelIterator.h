//
//  MLNSampleChannelIterator.h
//  Marlin
//
//  Created by iain on 26/12/2013.
//  Copyright (c) 2013 iain. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLNSampleBlock.h"

@class MLNSampleChannel;

typedef struct MLNSampleChannelCIterator MLNSampleChannelCIterator;

@interface MLNSampleChannelIterator : NSObject
- (id)initWithChannel:(MLNSampleChannel *)channel atFrame:(NSUInteger)frame;
- (id)initRawIteratorWithChannel:(MLNSampleChannel *)channel
                         atFrame:(NSUInteger)frame;
- (void)resetToFrame:(NSUInteger)frame
           inChannel:(MLNSampleChannel *)channel;
- (BOOL)nextFrameData:(float *)value;
- (BOOL)previousFrameData:(float *)value;
- (BOOL)nextCachePointData:(MLNSampleCachePoint *)cachePoint;
- (NSUInteger)fillBufferWithData:(float *)buffer ofFrameLength:(NSUInteger)frameLength;
- (float)peekFrame;
- (BOOL)peekNextFrame:(float *)frame;
- (BOOL)peekPreviousFrame:(float *)frame;
- (BOOL)findNextZeroCrossing:(NSUInteger *)nextZeroCrossing;
- (BOOL)findPreviousZeroCrossing:(NSUInteger *)previousZeroCrossing;

// C API
MLNSampleChannelCIterator *MLNSampleChannelIteratorNew(MLNSampleChannel *channel,
                                                       NSUInteger frame,
                                                       BOOL isRaw);
void MLNSampleChannelIteratorFree(MLNSampleChannelCIterator *cIter);
void MLNSampleChannelIteratorResetToFrame(MLNSampleChannelCIterator *cIter,
                                          MLNSampleChannel *channel,
                                          NSUInteger frame);
BOOL MLNSampleChannelIteratorHasMoreData(MLNSampleChannelCIterator *iter);
BOOL MLNSampleChannelIteratorNextCachePointData(MLNSampleChannelCIterator *iter,
                                                MLNSampleCachePoint *cachePoint);
BOOL MLNSampleChannelIteratorNextFrameData(MLNSampleChannelCIterator *iter,
                                           float *value);
BOOL MLNSampleChannelIteratorPreviousFrameData(MLNSampleChannelCIterator *iter,
                                               float *value);
NSUInteger MLNSampleChannelIteratorGetPosition(MLNSampleChannelCIterator *cIter);

void MLNSampleChannelIteratorPeekFrame(MLNSampleChannelCIterator *cIter, float *frame);
BOOL MLNSampleChannelIteratorPeekNextFrame(MLNSampleChannelCIterator *cIter, float *frame);
BOOL MLNSampleChannelIteratorPeekPreviousFrame(MLNSampleChannelCIterator *cIter, float *frame);

BOOL MLNSampleChannelIteratorFindNextZeroCrossing(MLNSampleChannelCIterator *cIter,
                                                  NSUInteger *nextZeroCrossing);
BOOL MLNSampleChannelIteratorFindPreviousZeroCrossing(MLNSampleChannelCIterator *cIter,
                                                      NSUInteger *previousZeroCrossing);

@end
