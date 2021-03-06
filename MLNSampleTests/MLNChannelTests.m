//
//  MLNChannelTests.m
//  Marlin
//
//  Created by iain on 17/04/2013.
//  Copyright (c) 2013 iain. All rights reserved.
//

#import "MLNChannelTests.h"
#import "MLNSampleChannel.h"
#import "MLNSampleBlockFile.h"
#import "MLNSampleChannelIterator.h"

@implementation MLNChannelTests {
    MLNSampleChannel *_channel;
}

static const NSUInteger BUFFER_FRAME_SIZE = 44100;

- (MLNSampleChannel *)createChannel
{
    MLNSampleChannel *channel = [[MLNSampleChannel alloc] init];
    [channel setChannelName:@"Test channel"];
    
    float *buffer = malloc(BUFFER_FRAME_SIZE * sizeof(float));
    
    // Fill all the frames with dummy data
    for (int i = 0; i < BUFFER_FRAME_SIZE; i++) {
        buffer[i] = (float)i;
    }
    
    [channel addData:buffer withByteLength:BUFFER_FRAME_SIZE * sizeof(float)];
    
    return channel;
}

- (MLNSampleChannel *)createZeroCrossingChannel:(NSUInteger *)numberCreated
{
    MLNSampleChannel *channel = [[MLNSampleChannel alloc] init];
    [channel setChannelName:@"Test channel"];
    
    float *buffer = malloc(BUFFER_FRAME_SIZE * sizeof(float));

    float value = 1.0;
    
    *numberCreated = 0;
    // Fill all the frames with dummy data
    for (int i = 0; i < BUFFER_FRAME_SIZE; i++) {
        if ((i > 0) && ((i % 100) == 0)) {
            value *= -1.0;
            
            *numberCreated = *numberCreated + 1;
        }
        
        buffer[i] = value;
    }
    
    [channel addData:buffer withByteLength:BUFFER_FRAME_SIZE * sizeof(float)];
    
    return channel;
}

- (void)setUp
{
    _channel = [[MLNSampleChannel alloc] init];
    [_channel setChannelName:@"Test channel"];
}

- (void)tearDown
{
    _channel = nil;
}

- (void)testIterator
{
    _channel = [self createChannel];
    MLNSampleChannelIterator *iter = [[MLNSampleChannelIterator alloc] initWithChannel:_channel atFrame:0];
    
    float d = 0;
    NSUInteger i = 0;
    BOOL moreData = YES;
    
    while (moreData) {
        moreData = [iter frameDataAndAdvance:&d];
        XCTAssertEqual(d, (float)i, @"");

        i++;
    }
    
    XCTAssertEqual(i, [_channel numberOfFrames], @"");
}

- (void)testIteratorRange
{
    _channel = [self createChannel];
    MLNSampleChannelIterator *iter = [[MLNSampleChannelIterator alloc] initWithChannel:_channel withRange:NSMakeRange(10, 10)];
    
    float d = 0;
    NSUInteger i = 0;
    BOOL moreData = YES;
    
    while (moreData) {
        moreData = [iter frameDataAndAdvance:&d];
        XCTAssertEqual(d, (float)(i + 10), @"");
        
        i++;
    }
    
    XCTAssertEqual(i, (NSUInteger)10, @"");
}

- (void)testPeek
{
    _channel = [self createChannel];
    
    NSUInteger frame = (rand() % [_channel numberOfFrames] - 3) + 1;
    NSRange range = NSMakeRange(frame, [_channel numberOfFrames] - frame);
    MLNSampleChannelCIterator *iter = MLNSampleChannelIteratorNew(_channel, range, NO);
    
    float value;
    MLNSampleChannelIteratorPeekFrame(iter, &value);
    XCTAssertEqual((float)frame, value, @"");
    
    MLNSampleChannelIteratorPeekNextFrame(iter, &value);
    XCTAssertEqual((float)frame + 1, value, @"");
    
    MLNSampleChannelIteratorPeekPreviousFrame(iter, &value);
    XCTAssertEqual((float)frame - 1, value, @"");
    
    MLNSampleChannelIteratorFree(iter);
    
    MLNSampleBlock *block1, *block2;
    [_channel splitAtFrame:frame firstBlock:&block1 secondBlock:&block2];
    
    range = NSMakeRange(frame - 1, [_channel numberOfFrames] - (frame - 1));
    iter = MLNSampleChannelIteratorNew(_channel, range, NO);
    
    MLNSampleChannelIteratorPeekNextFrame(iter, &value);
    XCTAssertEqual((float)frame, value, @"");
    
    MLNSampleChannelIteratorFree(iter);
    
    range = NSMakeRange(frame, [_channel numberOfFrames] - frame);
    iter = MLNSampleChannelIteratorNew(_channel, range, NO);
    MLNSampleChannelIteratorPeekPreviousFrame(iter, &value);
    XCTAssertEqual((float)frame - 1, value, @"");
}

- (void)testIteratorBackwards
{
    MLNSampleChannel *channel = [self createChannel];
    NSUInteger frame = (rand() % [channel numberOfFrames] - 10) + 5;
    NSRange range = NSMakeRange(frame, [channel numberOfFrames]);
    MLNSampleChannelCIterator *iter = MLNSampleChannelIteratorNew(channel, range, NO);
    BOOL moreData = YES;
    NSUInteger i = frame;
    
    while (moreData) {
        float value;
        
        moreData = MLNSampleChannelIteratorFrameDataAndRewind(iter, &value);
        
        XCTAssertEqual(value, (float)i, @"");
        i--;
    }
    
    XCTAssertEqual(i, (NSUInteger)0, @"");
}

- (void)testSplitChannel
{
    MLNSampleChannel *channel = [self createChannel];
    MLNSampleBlock *block1, *block2;
    NSUInteger splitFrame = rand() % [channel numberOfFrames];

    [channel splitAtFrame:splitFrame firstBlock:&block1 secondBlock:&block2];
    XCTAssertFalse(block1 == NULL, @"");
    XCTAssertFalse(block2 == NULL, @"");
    
    XCTAssertEqual(block1->startFrame, (NSUInteger)0, @"");
    XCTAssertEqual(block1->numberOfFrames, (NSUInteger)splitFrame, @"");
    XCTAssertEqual(block1->nextBlock, block2, @"");
    
    for (int i = 0; i < splitFrame; i++) {
        float value = MLNSampleBlockDataAtFrame(block1, i);
        XCTAssertEqual(value, (float)i, @"");
    }
    
    XCTAssertEqual(block2->startFrame, (NSUInteger)splitFrame, @"");
    XCTAssertEqual(block2->numberOfFrames, (NSUInteger)[channel numberOfFrames] - splitFrame, @"");
    XCTAssertEqual(block2->previousBlock, block1, @"");
    
    for (NSUInteger i = splitFrame; i < splitFrame + block2->numberOfFrames; i++) {
        float value = MLNSampleBlockDataAtFrame(block2, i - splitFrame);
        XCTAssertEqual(value, (float)i, @"");
    }
}

- (void)testAddBlocks
{
    MLNSampleBlock *block1, *block2;
    
    block1 = MLNSampleBlockFileCreateBlock(NULL, BUFFER_FRAME_SIZE * sizeof(float), 0, NULL, 0, 0);
    block2 = MLNSampleBlockFileCreateBlock(NULL, BUFFER_FRAME_SIZE * sizeof(float), 0, NULL, 0, 0);
    
    XCTAssertTrue([_channel firstBlock] == NULL, @"[_channel firstBlock] != NULL");
    
    [_channel addBlock:block1];
    
    XCTAssertTrue([_channel firstBlock] == block1, @"[_channel firstBlock] != block1");
    XCTAssertTrue([_channel lastBlock] == block1, @"[_channel lastBlock] != block1");
    XCTAssertEqual([_channel numberOfFrames], BUFFER_FRAME_SIZE, @"[_channel numberOfFrames != %lu: %lu", BUFFER_FRAME_SIZE, [_channel numberOfFrames]);
    
    [_channel addBlock:block2];
    
    XCTAssertTrue([_channel lastBlock] == block2, @"[_channel lastBlock != block2");
    XCTAssertEqual([_channel numberOfFrames], BUFFER_FRAME_SIZE * 2, @"[_channel numberOfFrames != %lu: %lu", BUFFER_FRAME_SIZE * 2, [_channel numberOfFrames]);
    
    XCTAssertEqual(block2->startFrame, BUFFER_FRAME_SIZE, @"block2->startFrame != %lu: %lu", BUFFER_FRAME_SIZE, block2->startFrame);
}

- (void)testRemoveBlocks
{
    MLNSampleBlock *block1, *block2;
    
    block1 = MLNSampleBlockFileCreateBlock(NULL, BUFFER_FRAME_SIZE * sizeof(float), 0, NULL, 0, 0);
    block2 = MLNSampleBlockFileCreateBlock(NULL, BUFFER_FRAME_SIZE * sizeof(float), 0, NULL, 0, 0);
    
    // We know addBlocks works if the previous test passed
    [_channel addBlock:block1];
    [_channel addBlock:block2];

    [_channel removeBlock:block1];
    
    XCTAssertTrue([_channel firstBlock] == block2, @"[_channel firstBlock] != block2");
    XCTAssertEqual([_channel numberOfFrames], BUFFER_FRAME_SIZE, @"[_channel numberOfFrames] != %lu: %lu", BUFFER_FRAME_SIZE, [_channel numberOfFrames]);
    XCTAssertEqual(block2->startFrame, (NSUInteger)0, @"block2->startFrame != 0: %lu", block2->startFrame);
    
    // Check the removed blocks have been unlinked
    XCTAssertTrue(block1->nextBlock == NULL, @"block1->nextBlock != NULL");
    XCTAssertTrue(block2->previousBlock == NULL, @"block2->previousBlock != NULL");
    
    [_channel removeBlock:block2];
    
    XCTAssertTrue([_channel firstBlock] == NULL, @"[_channel firstBlock] != NULL");
    XCTAssertTrue([_channel lastBlock] == NULL, @"[_channel lastBlock] != NULL");
    XCTAssertEqual([_channel numberOfFrames], (NSUInteger)0, @"[_channel numberOfFrames] != 0: %lu", [_channel numberOfFrames]);
    
    MLNSampleBlockFree(block1);
    MLNSampleBlockFree(block2);
}

- (void)testDeleteMiddleRegion
{
    MLNSampleBlock *block;
    
    _channel = [self createChannel];
    
    [_channel deleteRange:NSMakeRange(100, 100)];
    
    // We should now have 2 blocks [0 -> 99] & [100 -> 43999]
    XCTAssertEqual([_channel count], (NSUInteger)2, @"[_channel count] != 2: %lu", [_channel count]);
    
    block = [_channel firstBlock];
    XCTAssertEqual(block->startFrame, (NSUInteger)0, @"block->startFrame != 0: %lu", block->startFrame);
    XCTAssertEqual(block->numberOfFrames, (NSUInteger)100, @"block->numberOfFrames != 100: %lu", block->numberOfFrames);
    
    block = block->nextBlock;
    XCTAssertFalse(block == NULL, @"block == NULL");
    XCTAssertEqual(block->startFrame, (NSUInteger)100, @"block->startFrame != 100: %lu", block->startFrame);
    XCTAssertEqual(block->numberOfFrames, (NSUInteger)43900, @"block->numberOfFrames != 43900: %lu", block->numberOfFrames);
}

- (void)testDeleteStart
{
    MLNSampleBlock *block;

    _channel = [self createChannel];
    
    [_channel deleteRange:NSMakeRange(0, 100)];
    
    XCTAssertEqual([_channel count], (NSUInteger)1, @"[_channel count] != 1: %lu", [_channel count]);
    block = [_channel firstBlock];
    
    XCTAssertFalse(block == NULL, @"block == NULL");
    XCTAssertEqual(block->startFrame, (NSUInteger)0, @"block->startFrame != 0: %lu", block->startFrame);
    XCTAssertEqual(block->numberOfFrames, (NSUInteger)BUFFER_FRAME_SIZE - 100, @"block->numberOfFrames != 44000: %lu", block->numberOfFrames);
    
    XCTAssertEqual([_channel lastBlock], [_channel firstBlock], @"");
}

- (void)testDeleteEnd
{
    MLNSampleBlock *block;
    
    _channel = [self createChannel];
    
    [_channel deleteRange:NSMakeRange(44000, 100)];
    
    XCTAssertEqual([_channel count], (NSUInteger)1, @"[_channel count] != 1: %lu", [_channel count]);
    block = [_channel firstBlock];
    
    XCTAssertFalse(block == NULL, @"block == NULL");
    XCTAssertEqual(block->startFrame, (NSUInteger)0, @"block->startFrame != 0: %lu", block->startFrame);
    XCTAssertEqual(block->numberOfFrames, (NSUInteger)BUFFER_FRAME_SIZE - 100, @"block->numberOfFrames != 44000: %lu", block->numberOfFrames);
    
    XCTAssertEqual([_channel lastBlock], [_channel firstBlock], @"");
}

- (void)testDeleteAll
{
    _channel = [self createChannel];
    
    [_channel deleteRange:NSMakeRange(0, BUFFER_FRAME_SIZE)];
    
    XCTAssertEqual([_channel count], (NSUInteger)0, @"[_channel count] != 0: %lu", [_channel count]);
    XCTAssertEqual([_channel numberOfFrames], (NSUInteger)0, @"[_channel numberOfFrames] != 0: %lu", [_channel numberOfFrames]);
    XCTAssertTrue([_channel firstBlock] == NULL, @"[_channel firstBlock] != NULL");
    XCTAssertTrue([_channel lastBlock] == NULL, @"[_channel lastBlock] != NULL");
}

- (void)testDeleteInvalidLocation
{
    _channel = [self createChannel];
    XCTAssertThrows([_channel deleteRange:NSMakeRange(276824, 100)]);
}

- (void)testDeleteInvalidLength
{
    _channel = [self createChannel];
    XCTAssertThrows([_channel deleteRange:NSMakeRange(100, 124124123)]);
}

- (void)testCopyChannel
{
    NSUInteger startFrame, endFrame, numberOfFrames;
    MLNSampleChannel *channelCopy;
    
    _channel = [self createChannel];
    startFrame = rand() % [_channel numberOfFrames];
    endFrame = startFrame + (rand() % ([_channel numberOfFrames] - startFrame));
    numberOfFrames = (endFrame - startFrame) + 1;
    
    channelCopy = [_channel copyChannelInRange:NSMakeRange(startFrame, numberOfFrames)];
    
    XCTAssertNotNil(channelCopy, @"channelCopy is nil");
    XCTAssertEqual([channelCopy numberOfFrames], numberOfFrames, @"[channelCopy numberOfFrames] != %lu: %lu", numberOfFrames, [channelCopy numberOfFrames]);
}

- (void)insertChannelAt:(NSUInteger)insertFrame
     expectedBlockCount:(NSUInteger)count
{
    MLNSampleChannel *channel2;
    
    _channel = [self createChannel];
    channel2 = [self createChannel];
    
    BOOL result = [_channel insertChannel:channel2 atFrame:insertFrame];
    if (result == NO) {
        return;
    }
    
    NSUInteger blockCount = 0;
    MLNSampleBlock *block = [_channel firstBlock];
    while (block) {
        blockCount++;
        block = block->nextBlock;
    }
    
    XCTAssertEqual(blockCount, count, @"blockCount != %lu: %lu", count, blockCount);
    block = [_channel firstBlock];
    
    XCTAssertEqual(block->startFrame, (NSUInteger)0, @"block->startFrame != 0: %lu", block->startFrame);
    for (NSUInteger i = 0; i < insertFrame; i++) {
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)i, @"data[%lu] != %f: %f", i, i, value);
    }
    
    if (count == 3) {
        block = block->nextBlock;
        
        XCTAssertEqual(block->startFrame, insertFrame, @"block->startFrame != %lu: %lu", insertFrame, block->startFrame);
        for (NSUInteger i = 0; i < block->numberOfFrames; i++) {
            float value = MLNSampleBlockDataAtFrame(block, i);
            XCTAssertEqual(value, (float)i, @"data[%lu] != %f: %f", i, i, value);
        }
    }
    
    block = block->nextBlock;
    
    XCTAssertEqual(block->startFrame, insertFrame + [channel2 numberOfFrames], @"block->startFrame != %lu: %lu", insertFrame + [channel2 numberOfFrames], block->startFrame);
    for (NSUInteger i = 0; i < block->numberOfFrames; i++) {
        float result = insertFrame + i;
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)result, @"data[%lu] != %f: %f", i, result, value);
    }
}

- (void)testInsertChannel
{
    MLNSampleChannel *channel2;
    NSUInteger insertFrame = rand() % BUFFER_FRAME_SIZE;
    
    _channel = [self createChannel];
    channel2 = [self createChannel];
    
    BOOL result = [_channel insertChannel:channel2 atFrame:insertFrame];
    if (result == NO) {
        return;
    }
    
    NSUInteger blockCount = 0;
    MLNSampleBlock *block = [_channel firstBlock];
    while (block) {
        blockCount++;
        block = block->nextBlock;
    }
    
    XCTAssertEqual(blockCount, (NSUInteger)3, @"blockCount != 3: %lu", blockCount);
    block = [_channel firstBlock];
    
    XCTAssertEqual(block->startFrame, (NSUInteger)0, @"block->startFrame != 0: %lu", block->startFrame);
    for (NSUInteger i = 0; i < insertFrame; i++) {
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)i, @"data[%lu] != %f: %f", i, i, value);
    }
    
    block = block->nextBlock;
    XCTAssertEqual(block->startFrame, insertFrame, @"block->startFrame != %lu: %lu", insertFrame, block->startFrame);
    for (NSUInteger i = 0; i < block->numberOfFrames; i++) {
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)i, @"data[%lu] != %f: %f", i, i, value);
    }
    
    block = block->nextBlock;
    XCTAssertEqual(block->startFrame, insertFrame + [channel2 numberOfFrames], @"block->startFrame != %lu: %lu", insertFrame + [channel2 numberOfFrames], block->startFrame);
    for (NSUInteger i = 0; i < block->numberOfFrames; i++) {
        float result = insertFrame + i;
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)result, @"data[%lu] != %f: %f", i, result, value);
    }
}

- (void)testInsertStart
{
    MLNSampleChannel *channel2;
    NSUInteger insertFrame = 0;
    
    _channel = [self createChannel];
    channel2 = [self createChannel];
    
    BOOL result = [_channel insertChannel:channel2 atFrame:insertFrame];
    if (result == NO) {
        return;
    }
    
    NSUInteger blockCount = 0;
    MLNSampleBlock *block = [_channel firstBlock];
    while (block) {
        blockCount++;
        block = block->nextBlock;
    }
    
    XCTAssertEqual(blockCount, (NSUInteger)2, @"blockCount != 2: %lu", blockCount);
    block = [_channel firstBlock];
    
    XCTAssertEqual(block->startFrame, (NSUInteger)0, @"block->startFrame != 0: %lu", block->startFrame);
    for (NSUInteger i = 0; i < insertFrame; i++) {
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)i, @"data[%lu] != %f: %f", i, i, value);
    }
    
    block = block->nextBlock;
    XCTAssertEqual(block->startFrame, insertFrame + [channel2 numberOfFrames], @"block->startFrame != %lu: %lu", insertFrame + [channel2 numberOfFrames], block->startFrame);
    for (NSUInteger i = 0; i < block->numberOfFrames; i++) {
        float result = insertFrame + i;
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)result, @"data[%lu] != %f: %f", i, result, value);
    }
}

- (void)testInsertEnd
{
    MLNSampleChannel *channel2;
    NSUInteger insertFrame = BUFFER_FRAME_SIZE;
    
    _channel = [self createChannel];
    channel2 = [self createChannel];
    
    BOOL result = [_channel insertChannel:channel2 atFrame:insertFrame];
    if (result == NO) {
        return;
    }
    
    NSUInteger blockCount = 0;
    MLNSampleBlock *block = [_channel firstBlock];
    while (block) {
        blockCount++;
        block = block->nextBlock;
    }
    
    XCTAssertEqual(blockCount, (NSUInteger)2, @"blockCount != 2: %lu", blockCount);
    block = [_channel firstBlock];
    
    XCTAssertEqual(block->startFrame, (NSUInteger)0, @"block->startFrame != 0: %lu", block->startFrame);
    for (NSUInteger i = 0; i < insertFrame; i++) {
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)i, @"data[%lu] != %f: %f", i, i, value);
    }
    
    block = block->nextBlock;
    XCTAssertEqual(block->startFrame, insertFrame, @"block->startFrame != %lu: %lu", insertFrame, block->startFrame);
    for (NSUInteger i = 0; i < block->numberOfFrames; i++) {
        float value = MLNSampleBlockDataAtFrame(block, i);
        XCTAssertEqual(value, (float)i, @"data[%lu] != %f: %f", i, i, value);
    }
}

- (void)testInsertInvalid
{
    MLNSampleChannel *channel2;
    
    _channel = [self createChannel];
    channel2 = [self createChannel];
    
    XCTAssertThrows([_channel insertChannel:channel2 atFrame:BUFFER_FRAME_SIZE + rand()]);
}

#define TEST_BUFFER_SIZE 1024

- (void)testFillBuffer
{
    /*
    float *buffer;
    size_t byteSize;
    
    _channel = [self createChannel];
    
    buffer = malloc(TEST_BUFFER_SIZE * sizeof(float));
    
    byteSize = [_channel fillBuffer:buffer withLength:TEST_BUFFER_SIZE * sizeof(float) fromFrame:0];
    STAssertEquals(byteSize, TEST_BUFFER_SIZE * sizeof(float), @"");

    for (int i = 0; i < (byteSize / sizeof(float)); i++) {
        STAssertEquals(buffer[i], (float)i, @"");
    }

    NSUInteger startFrame = [_channel numberOfFrames] - 10;

    byteSize = [_channel fillBuffer:buffer withLength:TEST_BUFFER_SIZE fromFrame:[_channel numberOfFrames] - 10];
    STAssertEquals(byteSize / sizeof(float), (size_t)10, @"");

    for (int i = 0; i < byteSize / sizeof(float); i++) {
        STAssertEquals(buffer[i], (float)startFrame + i, @"");
    }
     */
}

- (void)testInsertSilence
{
    _channel = [self createChannel];
    
    [_channel insertSilenceAtFrame:100 frameDuration:100];
    
    XCTAssertEqual([_channel numberOfFrames], (NSUInteger)44200, @"");

    // FIXME: Should probably just use an iterator for this.
    
    // First block should be 0 -> 99
    MLNSampleBlock *block1 = [_channel firstBlock];
    XCTAssertFalse(block1 == NULL, @"");
    
    XCTAssertEqual(block1->startFrame, (NSUInteger)0, @"");
    XCTAssertEqual(block1->numberOfFrames, (NSUInteger)100, @"");
    XCTAssertEqual(MLNSampleBlockLastFrame(block1), (NSUInteger)99, @"");
    
    for (int i = 0; i < 100; i++) {
        float value = MLNSampleBlockDataAtFrame(block1, i);
        XCTAssertEqual(value, (float)i, @"");
    }
    
    // Second block should be 100 -> 199
    MLNSampleBlock *block2 = block1->nextBlock;
    
    XCTAssertFalse(block2 == NULL, @"");
    XCTAssertEqual(block2->startFrame, (NSUInteger)100, @"");
    XCTAssertEqual(block2->numberOfFrames, (NSUInteger)100, @"");
    XCTAssertEqual(MLNSampleBlockLastFrame(block2), (NSUInteger)199, @"");
    
    for (int i = 0; i < 100; i++) {
        float value = MLNSampleBlockDataAtFrame(block2, i);
        XCTAssertEqual(value, (float)0.0, @"");
    }
    
    // Third block should be 200 -> 44199, containing 100 -> 44099
    MLNSampleBlock *block3 = block2->nextBlock;
    
    XCTAssertFalse(block3 == NULL, @"");
    XCTAssertEqual(block3->startFrame, (NSUInteger)200, @"");
    XCTAssertEqual(block3->numberOfFrames, (NSUInteger)44000, @"");
    XCTAssertEqual(MLNSampleBlockLastFrame(block3), (NSUInteger)44199, @"");
    
    for (int i = 0; i < 44000; i++) {
        float value = MLNSampleBlockDataAtFrame(block3, i);
        XCTAssertEqual(value, (float)i + 100, @"");
    }
}

- (void)testFindAllZeroCrossingForward
{
    NSUInteger numberCreated;
    MLNSampleChannel *channel = [self createZeroCrossingChannel:&numberCreated];
    MLNSampleChannelIterator *iter = [[MLNSampleChannelIterator alloc] initWithChannel:channel atFrame:0];
    
    NSUInteger zx;
    NSUInteger foundZX = 0;
    
    while ([iter findNextZeroCrossing:&zx upTo:[channel numberOfFrames]]) {
        XCTAssertEqual((zx % 100), (NSUInteger)0, @"");
        foundZX++;
    }
    
    XCTAssertEqual(foundZX, numberCreated, @"");
}

- (void)testFindAllZeroCrossingBackwards
{
    NSUInteger numberCreated;
    MLNSampleChannel *channel = [self createZeroCrossingChannel:&numberCreated];
    MLNSampleChannelIterator *iter = [[MLNSampleChannelIterator alloc] initWithChannel:channel atFrame:[channel numberOfFrames] - 1];
    
    XCTAssertNotNil(iter, @"");
    NSUInteger zx;
    NSUInteger foundZX = 0;
    
    while ([iter findPreviousZeroCrossing:&zx upTo:-1]) {
        XCTAssertEqual((zx % 100), (NSUInteger)0, @"");
        foundZX++;
    }
    
    XCTAssertEqual(foundZX, numberCreated, @"");
}

- (void)testMaxValueInRange
{
    _channel = [self createChannel];
    
    float maxSampleValue = [_channel maxSampleValueInRange:NSMakeRange(0, [_channel numberOfFrames])];
    
    XCTAssertEqual(maxSampleValue, (float)44099, @"");
}
@end
