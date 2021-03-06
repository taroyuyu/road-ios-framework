//
//  RFDownloader+ConnectionDelegate.m
//  ROADWebService
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


#import "RFDownloader+ConnectionDelegate.h"
#import <ROAD/ROADCore.h>

#import "RFWebServiceLog.h"
#import "NSError+RFWebService.h"
#import "RFAuthenticating.h"
#import "RFWebServiceCall.h"
#import "RFWebServiceClient.h"
#import "RFWebServiceErrorHandler.h"
#import "RFWebServiceErrorHandling.h"
#import "RFServiceProvider+WebServiceCachingManager.h"
#import "RFWebServiceCache.h"
#import "RFWebResponse+HTTPResponse.h"


@interface RFDownloader ()

@property (strong, nonatomic) NSError *downloadError;
@property (strong, nonatomic) NSMutableData *data;
@property (strong, nonatomic) NSHTTPURLResponse *response;
@property (assign, nonatomic) long long expectedContentLenght;

- (void)stop;

@end


@implementation RFDownloader (ConnectionDelegate)

#pragma mark - NSURLConnection delegates

- (void)connection:(NSURLConnection *)connection didFailWithError:(NSError *)error {
    self.downloadError = error;
    [self stop];
    RFWSLogError(@"URL connection(%p) has failed. URL: %@", connection, [connection.currentRequest.URL absoluteString]);
}

- (void)connection:(NSURLConnection *)connection willSendRequestForAuthenticationChallenge:(NSURLAuthenticationChallenge *)challenge {
    
    RFWSLogDebug(@"URL connection(%p) has received authentication method:%@. URL: %@", connection, challenge.protectionSpace.authenticationMethod, [connection.currentRequest.URL absoluteString]);

    if (self.authenticationProvider) {
        RFWSLogDebug(@"URL connection(%p) has passed authentication challenge to authentication provider %@", connection, self.authenticationProvider);
        if ([self.authenticationProvider respondsToSelector:@selector(processAuthenticationChallenge:forConnection:)]) {
            [self.authenticationProvider processAuthenticationChallenge:challenge forConnection:connection];
        }
    } else {
        [challenge.sender continueWithoutCredentialForAuthenticationChallenge:challenge];
    }
}

#pragma mark - NSURLConnection data delegates

- (void)connectionDidFinishLoading:(NSURLConnection *)aConnection {
    RFWSLogInfo(@"URL connection(%p) has finished. URL: %@. Data was received: %@", aConnection, [aConnection.currentRequest.URL absoluteString], [[NSString alloc] initWithData:self.data encoding:((RFWebServiceCall*)[self.attributes RF_firstObjectWithClass:[RFWebServiceCall class]]).bodyEncoding]);
    
    // Checking response with error handler
    RFWebServiceErrorHandler *errorHandlerAttribute = [[self.webServiceClient class] RF_attributeForClassWithAttributeType:[RFWebServiceErrorHandler class]];
    if (!errorHandlerAttribute) {
        errorHandlerAttribute = [self.attributes RF_firstObjectWithClass:[RFWebServiceErrorHandler class]];
    }
    
    if (errorHandlerAttribute.handlerClass) {
      
        if ([errorHandlerAttribute.handlerClass conformsToProtocol:@protocol(RFWebServiceErrorHandling)]) {
            self.downloadError = [errorHandlerAttribute.handlerClass validateResponse:self.response withData:self.data];
        }
    }
    else {
        if ([self.response isKindOfClass:[NSHTTPURLResponse class]]) {
            NSHTTPURLResponse *response = (NSHTTPURLResponse *)self.response;
            if (![self isOkStatusCode:[response statusCode]]) {
                self.downloadError = [[NSError alloc] initWithDomain:NSURLErrorDomain code:[response statusCode] userInfo:nil];
            }
        }
    }

    [self stop];
}

- (void)connection:(NSURLConnection *)connection didReceiveData:(NSData *)data {
    [self.data appendData:data];
    RFWSLogVerbose(@"URL connection(%p) to URL: %@ received data: %@", connection, [connection.currentRequest.URL absoluteString], [[NSString alloc] initWithData:self.data encoding:((RFWebServiceCall*)[self.attributes RF_firstObjectWithClass:[RFWebServiceCall class]]).bodyEncoding]);
    [self updateDownloadProgress:(float)[data length] / (float)self.expectedContentLenght];
}

- (void)connection:(NSURLConnection *)connection didReceiveResponse:(NSURLResponse *)aResponse {
    if ([self.authenticationProvider respondsToSelector:@selector(checkResponse:forConnection:)]) {
        [self.authenticationProvider checkResponse:aResponse forConnection:connection];
    }

    self.response = (NSHTTPURLResponse *)aResponse;
    self.expectedContentLenght = [self.response expectedContentLength];
    
    if ([aResponse isKindOfClass:[NSHTTPURLResponse class]]) {
        RFWSLogDebug(@"URL connection(%p) to URL: %@ received response(%p) with status code: %d\nResponse headers: %@", connection, [connection.currentRequest.URL absoluteString], aResponse, [self.response statusCode], [self.response allHeaderFields]);
    }
    else {
        RFWSLogDebug(@"URL connection(%p) to URL: %@ received response(%p)", connection, [connection.currentRequest.URL absoluteString], aResponse);
    }
    
    [self.data setLength:0]; // discarding previous downloads in case a redirect or mulitpart has sent a new response
}


- (BOOL)isOkStatusCode:(NSInteger)statusCode {
    __block BOOL result = NO;
    [self.successCodes enumerateObjectsUsingBlock:^(id obj, NSUInteger idx, BOOL *stop) {
        if ([obj isKindOfClass:[NSNumber class]]) {
            result = statusCode == [obj integerValue];
        } else if ([obj isKindOfClass:[NSValue class]]) {
            NSRange range = [obj rangeValue];
            result = ((long)range.location <= statusCode) && (long)(range.location + range.length) > statusCode;
        } else {
            RFWSLogWarn(@"RFDownloader: Incorrect statusCode type: %@", NSStringFromClass([obj class]));
        }
        *stop = result;
    }];
    return result;
}

@end
