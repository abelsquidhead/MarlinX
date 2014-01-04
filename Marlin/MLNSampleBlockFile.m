//
//  MLNSampleBlockFile.m
//  Marlin
//
//  Created by iain on 03/01/2014.
//  Copyright (c) 2014 iain. All rights reserved.
//

#import "MLNSampleBlockFile.h"
#import "MLNSampleChannel.h"

static void MLNSampleBlockFileFree (MLNSampleBlock *block);
static MLNSampleBlock *MLNSampleBlockFileCopy (MLNSampleBlock *block,
                                               NSUInteger startFrame,
                                               NSUInteger endFrame);
static MLNSampleBlock *MLNSampleBlockFileSplitBlockAtFrame (MLNSampleBlock *block,
                                                            NSUInteger splitFrame);
static float MLNSampleBlockFileDataAtFrame(MLNSampleBlock *block,
                                           NSUInteger frame);
static void MLNSampleBlockFileCachePointAtFrame(MLNSampleBlock *block,
                                                MLNSampleCachePoint *cachePoint,
                                                NSUInteger frame);

static MLNSampleBlockMethods methods = {
    MLNSampleBlockFileFree,
    MLNSampleBlockFileCopy,
    MLNSampleBlockFileSplitBlockAtFrame,
    MLNSampleBlockFileDataAtFrame,
    MLNSampleBlockFileCachePointAtFrame,
};

MLNSampleBlock *
MLNSampleBlockFileCreateBlock(MLNMapRegion *region,
                              size_t byteLength,
                              off_t offset,
                              MLNMapRegion *cacheRegion,
                              size_t cacheByteLength,
                              off_t cacheByteOffset)
{
    MLNSampleBlockFile *block = malloc(sizeof(MLNSampleBlockFile));
    
    block->parentBlock.methods = &methods;
    
    block->region = region;
    MLNMapRegionRetain(region);
    
    block->sampleByteLength = byteLength;
    block->byteOffset = offset;
    
    block->cacheRegion = cacheRegion;
    MLNMapRegionRetain(cacheRegion);
    
    block->cacheByteLength = cacheByteLength;
    block->cacheByteOffset = cacheByteOffset;
    
    block->parentBlock.numberOfFrames = byteLength / sizeof (float);
    block->parentBlock.startFrame = 0;
    
    block->parentBlock.nextBlock = NULL;
    block->parentBlock.previousBlock = NULL;
    
    block->parentBlock.reversed = NO;
    
    return (MLNSampleBlock *)block;
}

static void
MLNSampleBlockFileFree (MLNSampleBlock *block)
{
    MLNSampleBlockFile *fileBlock = (MLNSampleBlockFile *)block;
    
    if (block == NULL) {
        return;
    }
    
    MLNMapRegionRelease(fileBlock->region);
    MLNMapRegionRelease(fileBlock->cacheRegion);
    
    free(block);
}

static MLNSampleBlock *
MLNSampleBlockFileCopy (MLNSampleBlock *block,
                        NSUInteger startFrame,
                        NSUInteger endFrame)
{
    MLNSampleBlockFile *copyBlock, *fileBlock;
    size_t copyByteLength;
    off_t copyOffset;
    off_t copyCacheOffset;
    NSUInteger framesToCopy;
    NSUInteger frameOffset;
    NSUInteger copyNumberOfCachePoints;
    
    if (block == NULL) {
        return NULL;
    }
    
    if (!FRAME_IN_BLOCK(block, startFrame) || !FRAME_IN_BLOCK(block, endFrame)) {
        return NULL;
    }
    
    fileBlock = (MLNSampleBlockFile *)block;
    
    if (startFrame == block->startFrame && endFrame == MLNSampleBlockLastFrame(block)) {
        copyBlock = (MLNSampleBlockFile *)MLNSampleBlockFileCreateBlock(fileBlock->region, fileBlock->sampleByteLength, fileBlock->byteOffset,
                                                                        fileBlock->cacheRegion, fileBlock->cacheByteLength, fileBlock->cacheByteOffset);
        
        copyBlock->parentBlock.startFrame = startFrame;
        return (MLNSampleBlock *)copyBlock;
    }
    
    framesToCopy = (endFrame - startFrame) + 1;
    
    frameOffset = (startFrame - block->startFrame);
    copyOffset = fileBlock->byteOffset + (frameOffset * sizeof(float));
    //copyNumberOfFrames = (block->numberOfFrames - frameOffset);
    
    copyByteLength = framesToCopy * sizeof(float);
    
    copyNumberOfCachePoints = framesToCopy / 256;
    if (framesToCopy % 256 != 0) {
        copyNumberOfCachePoints++;
    }
    
    copyCacheOffset = (fileBlock->cacheByteLength - (copyNumberOfCachePoints * sizeof(MLNSampleCachePoint)));
    
    copyBlock = (MLNSampleBlockFile *)MLNSampleBlockFileCreateBlock(fileBlock->region, copyByteLength, copyOffset,
                                                                    fileBlock->cacheRegion,
                                                                    copyNumberOfCachePoints * sizeof(MLNSampleCachePoint),
                                                                    fileBlock->cacheByteOffset + copyCacheOffset);
    copyBlock->parentBlock.startFrame = startFrame;
    
    return (MLNSampleBlock *)copyBlock;
}

static MLNSampleBlock *
MLNSampleBlockFileSplitBlockAtFrame (MLNSampleBlock *block,
                                     NSUInteger splitFrame)
{
    MLNSampleBlockFile *newBlock, *fileBlock;
    NSUInteger realSplitFrame;
    NSUInteger numberFramesInSelf;
    NSUInteger numberFramesInOther;
    NSUInteger otherStart;
    NSUInteger numberOfCachePoints;
    NSUInteger numberOfCachePointsInSelf;
    NSUInteger numberOfCachePointsInOther;
  
    if (block == NULL) {
        return NULL;
    }
  
    if (!FRAME_IN_BLOCK(block, splitFrame)) {
        return NULL;
    }
  
    fileBlock = (MLNSampleBlockFile *)block;
    
    DDLogCVerbose(@"Splitting block at %lu", splitFrame);
    if (block->reversed) {
        realSplitFrame = ((MLNSampleBlockLastFrame(block) + 1) - splitFrame) + block->startFrame;
    } else {
        realSplitFrame = splitFrame;
    }
    DDLogCVerbose(@"Real split frame: %lu", realSplitFrame);
    MLNSampleBlockDumpBlock(block);
  
    numberFramesInSelf = realSplitFrame - block->startFrame;
    numberFramesInOther = block->numberOfFrames - numberFramesInSelf;
    otherStart = block->startFrame + numberFramesInSelf;
  
    DDLogCVerbose(@"Number frames in self: %lu", numberFramesInSelf);
    DDLogCVerbose(@"Number frames in new block: %lu", numberFramesInOther);
    DDLogCVerbose(@"Other start: %lu", otherStart);
  
    numberOfCachePoints = fileBlock->cacheByteLength / sizeof(MLNSampleCachePoint);
  
    DDLogCVerbose(@"Total cache points: %lu", numberOfCachePoints);
  
    numberOfCachePointsInSelf = numberFramesInSelf / MLNSampleChannelFramesPerCachePoint();
    if (numberFramesInSelf % MLNSampleChannelFramesPerCachePoint() != 0) {
        numberOfCachePointsInSelf++;
    }
  
    numberOfCachePointsInOther = numberOfCachePoints - numberOfCachePointsInSelf;
  
    DDLogCVerbose(@"number cache points in self: %lu", numberOfCachePointsInSelf);
    DDLogCVerbose(@"number cache points in other: %lu", numberOfCachePointsInOther);
    if (realSplitFrame == block->startFrame) {
        DDLogCVerbose(@"Split frame == _startFrame, returning self");
  
        // FIXME: Do blocks need to be ref-counted?
        return block;
    }
  
    newBlock = (MLNSampleBlockFile *)MLNSampleBlockFileCreateBlock(fileBlock->region,
                                                                   numberFramesInOther * sizeof(float),
                                                                   fileBlock->byteOffset + numberFramesInSelf * sizeof(float),
                                                                   fileBlock->cacheRegion,
                                                                   numberOfCachePointsInOther * sizeof(MLNSampleCachePoint),
                                                                   fileBlock->cacheByteOffset + (numberOfCachePointsInSelf * sizeof(MLNSampleCachePoint)));
    newBlock->parentBlock.startFrame = otherStart;
    newBlock->parentBlock.reversed = block->reversed;
  
    block->numberOfFrames = numberFramesInSelf;
    fileBlock->sampleByteLength = block->numberOfFrames * sizeof(float);
    fileBlock->cacheByteLength = numberOfCachePointsInSelf * sizeof(MLNSampleCachePoint);
  
    if (block->reversed) {
        MLNSampleBlockPrependBlock(block, (MLNSampleBlock *)newBlock);
    } else {
        MLNSampleBlockAppendBlock(block, (MLNSampleBlock *)newBlock);
    }
  
    MLNSampleBlockDumpBlock((MLNSampleBlock *)newBlock);
  
    return (MLNSampleBlock *)newBlock;
}

static float
MLNSampleBlockFileDataAtFrame(MLNSampleBlock *block,
                              NSUInteger frame)
{
    MLNSampleBlockFile *fileBlock;
    float *data;
    
    if (block == NULL) {
        return 0.0;
    }
    
    fileBlock = (MLNSampleBlockFile *)block;
    
    data = (float *)(fileBlock->region->dataRegion + fileBlock->byteOffset);
    return data[frame];
}

static void
MLNSampleBlockFileCachePointAtFrame(MLNSampleBlock *block,
                                    MLNSampleCachePoint *cachePoint,
                                    NSUInteger frame)
{
    MLNSampleBlockFile *fileBlock;
    MLNSampleCachePoint *cachePointData, *cp;
    if (block == NULL) {
        return;
    }
    
    fileBlock = (MLNSampleBlockFile *)block;
    cachePointData = (MLNSampleCachePoint *)(fileBlock->cacheRegion->dataRegion + fileBlock->cacheByteOffset);
    cp = cachePointData + frame;
    cachePoint->avgMaxValue = cp->avgMaxValue;
    cachePoint->avgMinValue = cp->avgMinValue;
    cachePoint->maxValue = cp->maxValue;
    cachePoint->minValue = cp->minValue;
}