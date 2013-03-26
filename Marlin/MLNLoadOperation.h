//
//  MLNLoadOperation.h
//  Marlin
//
//  Created by iain on 29/01/2013.
//  Copyright (c) 2013 iain. All rights reserved.
//

#import <Foundation/Foundation.h>
#import "MLNLoadOperationDelegate.h"

@class MLNSample;

@interface MLNLoadOperation : NSOperation

@property (readwrite, weak) id<MLNLoadOperationDelegate> delegate;

- (id)initForSample:(MLNSample *)sample;

@end
