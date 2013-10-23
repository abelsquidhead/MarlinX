//
//  MLNSample+Operations.h
//  Marlin
//
//  Created by iain on 13/03/2013.
//  Copyright (c) 2013 iain. All rights reserved.
//

#import "MLNSample.h"

@interface MLNSample (Operations)

- (BOOL)deleteRange:(NSRange)range
        undoManager:(NSUndoManager *)undoManager;

- (NSArray *)copyRange:(NSRange)range withError:(NSError **)error;

- (BOOL)canInsertChannels:(NSArray *)channels
               sampleRate:(NSUInteger)sampleRate;
- (BOOL)insertChannels:(NSArray *)channels
               atFrame:(NSUInteger)frame
       withUndoManager:(NSUndoManager *)undoManager;
- (void)insertBlocks:(NSArray *)blockList
             atFrame:(NSUInteger)frame
     withUndoManager:(NSUndoManager *)undoManager;

- (BOOL)cropRange:(NSRange)range withUndoManager:(NSUndoManager *)undoManager;

- (void)insertSilenceAtFrame:(NSUInteger)frame
              numberOfFrames:(NSUInteger)numberOfFrames
                 undoManager:(NSUndoManager *)undoManager;
- (void)clearRange:(NSRange)clearRange
   withUndoManager:(NSUndoManager *)undoManager;

- (void)dumpDataInRange:(NSRange)range;

@end
