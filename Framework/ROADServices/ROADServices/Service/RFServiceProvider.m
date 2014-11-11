//
//  RFServiceProvider.m
//  ROADServices
//
//  Copyright (c) 2014 EPAM Systems, Inc. All rights reserved.
//
//  Redistribution and use in source and binary forms, with or without
//  modification, are permitted provided that the following conditions are met:
//
//  Redistributions of source code must retain the above copyright notice, this
//  list of conditions and the following disclaimer.
//  Redistributions in binary form must reproduce the above copyright notice, this
//  list of conditions and the following disclaimer in the documentation and/or
//  other materials provided with the distribution.
//  Neither the name of the EPAM Systems, Inc.  nor the names of its contributors
//  may be used to endorse or promote products derived from this software without
//  specific prior written permission.
//
//  THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
//  ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
//  WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
//  DISCLAIMED. IN NO EVENT SHALL THE COPYRIGHT HOLDER OR CONTRIBUTORS BE LIABLE
//  FOR ANY DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL
//  DAMAGES (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR
//  SERVICES; LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER
//  CAUSED AND ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY,
//  OR TORT (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE
//  OF THIS SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
//
//  See the NOTICE file and the LICENSE file distributed with this work
//  for additional information regarding copyright ownership and licensing


#import <objc/runtime.h>
#import <ROAD/ROADReflection.h>

#import "RFServiceProvider.h"

const char *RFServiceMethodEncoding = "@@:";

@implementation RFServiceProvider

static NSMutableDictionary *services;


#pragma mark - Method resolution

+ (BOOL)resolveClassMethod:(SEL)sel {
    BOOL result = [super resolveClassMethod:sel];

    if (!result) {
        NSString *selectorName = NSStringFromSelector(sel);
        // Framework's calls must not be checked on service attriutes
        if (![selectorName hasPrefix:@"RF_"]) {
            RFService *serviceAttribute = [RFServiceProvider RF_attributeForMethod:selectorName withAttributeType:[RFService class]];
            
            if (serviceAttribute != nil) {
                result = YES;
                IMP const implementation = [self methodForSelector:@selector(fetchService)];
                Class metaClass = object_getClass(self);
                class_addMethod(metaClass, sel, implementation, RFServiceMethodEncoding);
            }
        }
    }
    
    return result;
}

+ (id)fetchService {
    NSString * const serviceName = NSStringFromSelector(_cmd);
    __block id theService;
    dispatch_sync([self RF_sharedQueue], ^{
        theService = services[serviceName];

        if (theService == nil) {
            RFService * const serviceAttribute = [[self class] RF_attributeForMethod:serviceName withAttributeType:[RFService class]];
            Class const serviceClass = serviceAttribute.serviceClass;
            theService = [[(id)serviceClass alloc] init];
            [self registerService:theService forServiceName:serviceName];
        }
    });
    return theService;
}


#pragma mark - Service registration

+ (void)registerService:(const id)aServiceInstance forServiceName:(NSString * const)serviceName {
    
    if (aServiceInstance != nil) {
        if (!services) {
            services = [[NSMutableDictionary alloc] init];
        }
        
        services[serviceName] = aServiceInstance;
    }
}

+ (dispatch_queue_t)RF_sharedQueue {
    static dispatch_once_t onceToken;
    static dispatch_queue_t sharedQueue = nil;
    dispatch_once(&onceToken, ^{
        sharedQueue = dispatch_queue_create(NULL, DISPATCH_QUEUE_SERIAL);
    });
    
    return sharedQueue;
}

@end