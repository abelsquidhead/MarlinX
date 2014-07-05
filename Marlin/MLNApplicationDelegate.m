//
//  MLNApplicationDelegate.m
//  Marlin
//
//  Created by iain on 11/02/2013.
//  Copyright (c) 2013 iain. All rights reserved.
//

#import "DDLog.h"
#import "DDASLLogger.h"
#import "DDTTYLogger.h"
#import "MLNApplicationDelegate.h"
#import "MLNCacheFile.h"
#import "MLNDocumentController.h"

@implementation MLNApplicationDelegate {
    MLNDocumentController *_documentController;
    NSMutableArray *_cacheFiles;
}

@synthesize clipboardContent = _clipboardContent;

#pragma mark - Delegate methods

- (id)init
{
    self = [super init];
    if (!self) {
        return nil;
    }
    
    _documentController = [[MLNDocumentController alloc] init];
    return self;
}

- (BOOL)applicationShouldOpenUntitledFile:(NSApplication *)sender
{
    // If we're running tests then we don't want any open file dialogs
    BOOL runningTests = NSClassFromString(@"XCTestCase") != nil;
    if(runningTests) {
        return NO;
    }
    
    NSDocumentController *dc = [NSDocumentController sharedDocumentController];
    NSArray *urls = [dc URLsFromRunningOpenPanel];
    
    if (urls == nil) {
        return NO;
    }
    
    NSUInteger urlCount = [urls count];
    for (NSUInteger i = 0; i < urlCount; i++) {
        [dc openDocumentWithContentsOfURL:urls[i] display:YES completionHandler:NULL];
    }
    
    return NO;
}

- (void)applicationDidFinishLaunching:(NSNotification *)notification
{
    // Schedule "Checking whether document exists." into next UI Loop.
    // Because document is not restored yet.
    // So we don't know what do we have to create new one.
    // Opened document can be identified here. (double click document file)
    NSInvocationOperation* op = [[NSInvocationOperation alloc] initWithTarget:self
                                                                     selector:@selector(openNewDocumentIfNeeded)
                                                                       object:nil];
    [[NSOperationQueue mainQueue] addOperation:op];
}

- (void)openNewDocumentIfNeeded
{
}

- (void)applicationWillFinishLaunching:(NSNotification *)notification
{
    // Configure DDLog to ASL and TTY
    [DDLog addLogger:[DDASLLogger sharedInstance]];
    [DDLog addLogger:[DDTTYLogger sharedInstance]];
    
    // Create the temporary cache directory we need
    NSString *bundleID = [[NSBundle mainBundle] bundleIdentifier];
    
    NSFileManager *fm = [NSFileManager defaultManager];
    
    NSArray *filePaths = [fm URLsForDirectory:NSCachesDirectory inDomains:NSUserDomainMask];
    if ([filePaths count] > 0) {
        _cacheURL = [[filePaths objectAtIndex:0] URLByAppendingPathComponent:bundleID];
        
        NSError *error = nil;
        
        if (![fm createDirectoryAtURL:_cacheURL
          withIntermediateDirectories:YES
                           attributes:nil
                                error:&error]) {
            DDLogError(@"Error: %@ - %@", [error localizedFailureReason], [error localizedDescription]);
        }
    }
    
    // We store all the cache files that we created so that on termination we can delete them all
    _cacheFiles = [NSMutableArray array];
}

- (NSApplicationTerminateReply)applicationShouldTerminate:(NSApplication *)sender
{
    DDLogInfo(@"Terminating --- Cleaning up files");
    NSFileManager *fm = [NSFileManager defaultManager];

    for (MLNCacheFile *tfile in _cacheFiles) {
        NSError *error = nil;
        
        close([tfile fd]);
        [fm removeItemAtPath:[tfile filePath] error:&error];
        
        if (error != nil) {
            DDLogError(@"Error removing %@: %@ - %@", [tfile filePath], [error localizedDescription], [error localizedFailureReason]);
        } else {
            DDLogInfo(@"Deleted %@", [tfile filePath]);
        }
    }
    
    return NSTerminateNow;
}

#pragma mark - Cache file tracking
- (MLNCacheFile *)createNewCacheFileWithExtension:(NSString *)extension
{
    int fd;
    
    // Create a unique unpredictable filename
    NSString *guid = [[NSProcessInfo processInfo] globallyUniqueString] ;
    NSString *uniqueFileName = [NSString stringWithFormat:@"Marlin_%@.%@", guid, extension];
    NSURL *cacheFileURL = [_cacheURL URLByAppendingPathComponent:uniqueFileName isDirectory:NO];
    
    const char *filePath = [[cacheFileURL path] UTF8String];
    fd = open (filePath, O_RDWR | O_CREAT, 0660);
    if (fd == -1) {
        // FIXME: Should return &error
        DDLogError(@"Error opening %s: %d", filePath, errno);
        return nil;
    } else {
        DDLogInfo(@"Opened %s for data cache", filePath);
    }

    // Track the path and the fd
    MLNCacheFile *tfile = [[MLNCacheFile alloc] init];
    [tfile setFd:fd];
    [tfile setFilePath:[cacheFileURL path]];
    
    [_cacheFiles addObject:tfile];
    
    return tfile;
}

- (void)removeCacheFile:(MLNCacheFile *)cacheFile
{
    [_cacheFiles removeObject:cacheFile];
}

#pragma mark - Accessors
- (void)setClipboardContent:(MLNPasteboardSampleData *)clipboardContent
{
    if (clipboardContent == _clipboardContent) {
        return;
    }
    
    _clipboardContent = clipboardContent;
    NSPasteboard *pboard = [NSPasteboard generalPasteboard];

    [pboard clearContents];
    
    NSString *customPBoard = @"com.sleep5.marlin.pboarddata";
    [pboard setData:[customPBoard dataUsingEncoding:NSUTF8StringEncoding] forType:@"com.sleep5.marlin.pboardData"];
}

- (MLNPasteboardSampleData *)clipboardContent
{
    return _clipboardContent;
}
@end
