//
//  SLFDocument.m
//  Marlin
//
//  Created by iain on 29/01/2013.
//  Copyright (c) 2013 iain. All rights reserved.
//

#import "MLNDocument.h"
#import "MLNSample.h"
#import "MLNSample+Operations.h"
#import "MLNSampleView.h"

@implementation MLNDocument {
    MLNSample *_testSample;
}

- (id)init
{
    self = [super init];
    if (self) {
        // Add your subclass-specific initialization here.
    }
    return self;
}

- (NSString *)windowNibName
{
    // Override returning the nib file name of the document
    // If you need to use a subclass of NSWindowController or if your document supports multiple NSWindowControllers, you should remove this method and override -makeWindowControllers instead.
    return @"MLNDocument";
}

- (void)windowControllerDidLoadNib:(NSWindowController *)aController
{
    [super windowControllerDidLoadNib:aController];
    // Add any code here that needs to be executed once the windowController has loaded the document's window.
    
    NSURL *url = [NSURL fileURLWithPath:@"/Users/iain/Desktop/Change of Scenery rado edit.wav" isDirectory:NO];
    //NSURL *url = [NSURL fileURLWithPath:@"/Users/iain/sine.wav" isDirectory:NO];
    _testSample = [[MLNSample alloc] initWithURL:url];
    
    [_sampleView setSample:_testSample];
    [_sampleView setTranslatesAutoresizingMaskIntoConstraints:NO];
    
    // We only want to allow scrolling on the horizontal axis.
    //[_scrollView setVerticalScrollElasticity:NSScrollElasticityNone];
    
    // FIXME: Only on 10.8
    [_scrollView setBackgroundColor:[NSColor underPageBackgroundColor]];
    
    //[_scrollView setHasHorizontalRuler:YES];
    //[_scrollView setRulersVisible:YES];
    
    NSClipView *clipView = [_scrollView contentView];
    //[clipView setCopiesOnScroll:NO];
    NSDictionary *viewsDict = @{@"sampleView":_sampleView};
    
    [clipView addConstraints:[NSLayoutConstraint constraintsWithVisualFormat:@"V:|[sampleView]|" options:0 metrics:nil views:viewsDict]];
}

+ (BOOL)autosavesInPlace
{
    return YES;
}

- (NSData *)dataOfType:(NSString *)typeName error:(NSError **)outError
{
    // Insert code here to write your document to data of the specified type. If outError != NULL, ensure that you create and set an appropriate error when returning nil.
    // You can also choose to override -fileWrapperOfType:error:, -writeToURL:ofType:error:, or -writeToURL:ofType:forSaveOperation:originalContentsURL:error: instead.
    NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
    @throw exception;
    return nil;
}

- (BOOL)readFromData:(NSData *)data ofType:(NSString *)typeName error:(NSError **)outError
{
    // Insert code here to read your document from the given data of the specified type. If outError != NULL, ensure that you create and set an appropriate error when returning NO.
    // You can also choose to override -readFromFileWrapper:ofType:error: or -readFromURL:ofType:error: instead.
    // If you override either of these, you should also override -isEntireFileLoaded to return NO if the contents are lazily loaded.
    NSException *exception = [NSException exceptionWithName:@"UnimplementedMethod" reason:[NSString stringWithFormat:@"%@ is unimplemented", NSStringFromSelector(_cmd)] userInfo:nil];
    @throw exception;
    return YES;
}

#pragma Menu actions

- (void)playSample:(id)sender
{
    [_testSample play];
}

- (void)stopSample:(id)sender
{
    [_testSample stop];
}

- (void)delete:(id)sender
{
    NSRange selection = [_sampleView selection];
    DDLogVerbose(@"Delete selected range: %@", NSStringFromRange(selection));
    
    [_testSample deleteRange:selection];
    [_sampleView clearSelection];
}

- (BOOL)validateMenuItem:(NSMenuItem *)menuItem
{
    BOOL valid = FALSE;
    
    DDLogVerbose(@"Validate");
    if ([menuItem action] == @selector(delete:)) {
        valid = [_sampleView hasSelection];
    }
    
    return valid;
}
@end
