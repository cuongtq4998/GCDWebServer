/*
 Copyright (c) 2012-2019, Pierre-Olivier Latour
 All rights reserved.
 
 Redistribution and use in source and binary forms, with or without
 modification, are permitted provided that the following conditions are met:
 * Redistributions of source code must retain the above copyright
 notice, this list of conditions and the following disclaimer.
 * Redistributions in binary form must reproduce the above copyright
 notice, this list of conditions and the following disclaimer in the
 documentation and/or other materials provided with the distribution.
 * The name of Pierre-Olivier Latour may not be used to endorse
 or promote products derived from this software without specific
 prior written permission.
 
 THIS SOFTWARE IS PROVIDED BY THE COPYRIGHT HOLDERS AND CONTRIBUTORS "AS IS" AND
 ANY EXPRESS OR IMPLIED WARRANTIES, INCLUDING, BUT NOT LIMITED TO, THE IMPLIED
 WARRANTIES OF MERCHANTABILITY AND FITNESS FOR A PARTICULAR PURPOSE ARE
 DISCLAIMED. IN NO EVENT SHALL PIERRE-OLIVIER LATOUR BE LIABLE FOR ANY
 DIRECT, INDIRECT, INCIDENTAL, SPECIAL, EXEMPLARY, OR CONSEQUENTIAL DAMAGES
 (INCLUDING, BUT NOT LIMITED TO, PROCUREMENT OF SUBSTITUTE GOODS OR SERVICES;
 LOSS OF USE, DATA, OR PROFITS; OR BUSINESS INTERRUPTION) HOWEVER CAUSED AND
 ON ANY THEORY OF LIABILITY, WHETHER IN CONTRACT, STRICT LIABILITY, OR TORT
 (INCLUDING NEGLIGENCE OR OTHERWISE) ARISING IN ANY WAY OUT OF THE USE OF THIS
 SOFTWARE, EVEN IF ADVISED OF THE POSSIBILITY OF SUCH DAMAGE.
 */

#if !__has_feature(objc_arc)
#error GCDWebUploader requires ARC
#endif

#import <TargetConditionals.h>
#if TARGET_OS_IPHONE
#import <UIKit/UIKit.h>
#else
#import <SystemConfiguration/SystemConfiguration.h>
#endif

#import "GCDWebUploader.h"
#import "MyGCDWebServerFunctions.h"

#import "MyGCDWebServerDataRequest.h"
#import "MyGCDWebServerMultiPartFormRequest.h"
#import "MyGCDWebServerURLEncodedFormRequest.h"

#import "MyGCDWebServerDataResponse.h"
#import "MyGCDWebServerErrorResponse.h"
#import "MyGCDWebServerFileResponse.h"

NS_ASSUME_NONNULL_BEGIN

@interface GCDWebUploader (Methods)
- (nullable MyGCDWebServerResponse*)listDirectory:(MyGCDWebServerRequest*)request;
- (nullable MyGCDWebServerResponse*)downloadFile:(MyGCDWebServerRequest*)request;
- (nullable MyGCDWebServerResponse*)uploadFile:(MyGCDWebServerMultiPartFormRequest*)request;
- (nullable MyGCDWebServerResponse*)moveItem:(MyGCDWebServerURLEncodedFormRequest*)request;
- (nullable MyGCDWebServerResponse*)deleteItem:(MyGCDWebServerURLEncodedFormRequest*)request;
- (nullable MyGCDWebServerResponse*)createDirectory:(MyGCDWebServerURLEncodedFormRequest*)request;
@end

NS_ASSUME_NONNULL_END

@implementation GCDWebUploader

@dynamic delegate;

- (instancetype)initWithUploadDirectory:(NSString*)path {
  if ((self = [super init])) {
    NSString* bundlePath = [[NSBundle bundleForClass:[GCDWebUploader class]] pathForResource:@"GCDWebUploader" ofType:@"bundle"];
    if (bundlePath == nil) {
      return nil;
    }
    NSBundle* siteBundle = [NSBundle bundleWithPath:bundlePath];
    if (siteBundle == nil) {
      return nil;
    }
    _uploadDirectory = [path copy];
    GCDWebUploader* __unsafe_unretained server = self;

    // Resource files
    [self addGETHandlerForBasePath:@"/" directoryPath:(NSString*)[siteBundle resourcePath] indexFilename:nil cacheAge:3600 allowRangeRequests:NO];

    // Web page
    [self addHandlerForMethod:@"GET"
                         path:@"/"
                 requestClass:[MyGCDWebServerRequest class]
                 processBlock:^MyGCDWebServerResponse*(MyGCDWebServerRequest* request) {

#if TARGET_OS_IPHONE
                   NSString* device = [[UIDevice currentDevice] name];
#else
          NSString* device = CFBridgingRelease(SCDynamicStoreCopyComputerName(NULL, NULL));
#endif
                   NSString* title = server.title;
                   if (title == nil) {
                     title = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
                     if (title == nil) {
                       title = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
                     }
#if !TARGET_OS_IPHONE
                     if (title == nil) {
                       title = [[NSProcessInfo processInfo] processName];
                     }
#endif
                   }
                   NSString* header = server.header;
                   if (header == nil) {
                     header = title;
                   }
                   NSString* prologue = server.prologue;
                   if (prologue == nil) {
                     prologue = [siteBundle localizedStringForKey:@"PROLOGUE" value:@"" table:nil];
                   }
                   NSString* epilogue = server.epilogue;
                   if (epilogue == nil) {
                     epilogue = [siteBundle localizedStringForKey:@"EPILOGUE" value:@"" table:nil];
                   }
                   NSString* footer = server.footer;
                   if (footer == nil) {
                     NSString* name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleDisplayName"];
                     if (name == nil) {
                       name = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleName"];
                     }
                     NSString* version = [[NSBundle mainBundle] objectForInfoDictionaryKey:@"CFBundleShortVersionString"];
#if !TARGET_OS_IPHONE
                     if (!name && !version) {
                       name = @"OS X";
                       version = [[NSProcessInfo processInfo] operatingSystemVersionString];
                     }
#endif
                     footer = [NSString stringWithFormat:[siteBundle localizedStringForKey:@"FOOTER_FORMAT" value:@"" table:nil], name, version];
                   }
                   return [MyGCDWebServerDataResponse responseWithHTMLTemplate:(NSString*)[siteBundle pathForResource:@"index" ofType:@"html"]
                                                                   variables:@{
                                                                     @"device" : device,
                                                                     @"title" : title,
                                                                     @"header" : header,
                                                                     @"prologue" : prologue,
                                                                     @"epilogue" : epilogue,
                                                                     @"footer" : footer
                                                                   }];
                 }];

    // File listing
    [self addHandlerForMethod:@"GET"
                         path:@"/list"
                 requestClass:[MyGCDWebServerRequest class]
                 processBlock:^MyGCDWebServerResponse*(MyGCDWebServerRequest* request) {
                   return [server listDirectory:request];
                 }];

    // File download
    [self addHandlerForMethod:@"GET"
                         path:@"/download"
                 requestClass:[MyGCDWebServerRequest class]
                 processBlock:^MyGCDWebServerResponse*(MyGCDWebServerRequest* request) {
                   return [server downloadFile:request];
                 }];

    // File upload
    [self addHandlerForMethod:@"POST"
                         path:@"/upload"
                 requestClass:[MyGCDWebServerMultiPartFormRequest class]
                 processBlock:^MyGCDWebServerResponse*(MyGCDWebServerRequest* request) {
                   return [server uploadFile:(MyGCDWebServerMultiPartFormRequest*)request];
                 }];

    // File and folder moving
    [self addHandlerForMethod:@"POST"
                         path:@"/move"
                 requestClass:[MyGCDWebServerURLEncodedFormRequest class]
                 processBlock:^MyGCDWebServerResponse*(MyGCDWebServerRequest* request) {
                   return [server moveItem:(MyGCDWebServerURLEncodedFormRequest*)request];
                 }];

    // File and folder deletion
    [self addHandlerForMethod:@"POST"
                         path:@"/delete"
                 requestClass:[MyGCDWebServerURLEncodedFormRequest class]
                 processBlock:^MyGCDWebServerResponse*(MyGCDWebServerRequest* request) {
                   return [server deleteItem:(MyGCDWebServerURLEncodedFormRequest*)request];
                 }];

    // Directory creation
    [self addHandlerForMethod:@"POST"
                         path:@"/create"
                 requestClass:[MyGCDWebServerURLEncodedFormRequest class]
                 processBlock:^MyGCDWebServerResponse*(MyGCDWebServerRequest* request) {
                   return [server createDirectory:(MyGCDWebServerURLEncodedFormRequest*)request];
                 }];
  }
  return self;
}

@end

@implementation GCDWebUploader (Methods)

- (BOOL)_checkFileExtension:(NSString*)fileName {
  if (_allowedFileExtensions && ![_allowedFileExtensions containsObject:[[fileName pathExtension] lowercaseString]]) {
    return NO;
  }
  return YES;
}

- (NSString*)_uniquePathForPath:(NSString*)path {
  if ([[NSFileManager defaultManager] fileExistsAtPath:path]) {
    NSString* directory = [path stringByDeletingLastPathComponent];
    NSString* file = [path lastPathComponent];
    NSString* base = [file stringByDeletingPathExtension];
    NSString* extension = [file pathExtension];
    int retries = 0;
    do {
      if (extension.length) {
        path = [directory stringByAppendingPathComponent:(NSString*)[[base stringByAppendingFormat:@" (%i)", ++retries] stringByAppendingPathExtension:extension]];
      } else {
        path = [directory stringByAppendingPathComponent:[base stringByAppendingFormat:@" (%i)", ++retries]];
      }
    } while ([[NSFileManager defaultManager] fileExistsAtPath:path]);
  }
  return path;
}

- (MyGCDWebServerResponse*)listDirectory:(MyGCDWebServerRequest*)request {
  NSString* relativePath = [[request query] objectForKey:@"path"];
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
  BOOL isDirectory = NO;
  if (!absolutePath || ![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }
  if (!isDirectory) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is not a directory", relativePath];
  }

  NSString* directoryName = [absolutePath lastPathComponent];
  if (!_allowHiddenItems && [directoryName hasPrefix:@"."]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Listing directory name \"%@\" is not allowed", directoryName];
  }

  NSError* error = nil;
  NSArray* contents = [[[NSFileManager defaultManager] contentsOfDirectoryAtPath:absolutePath error:&error] sortedArrayUsingSelector:@selector(localizedStandardCompare:)];
  if (contents == nil) {
    return [MyGCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed listing directory \"%@\"", relativePath];
  }

  NSMutableArray* array = [NSMutableArray array];
  for (NSString* item in [contents sortedArrayUsingSelector:@selector(localizedStandardCompare:)]) {
    if (_allowHiddenItems || ![item hasPrefix:@"."]) {
      NSDictionary* attributes = [[NSFileManager defaultManager] attributesOfItemAtPath:[absolutePath stringByAppendingPathComponent:item] error:NULL];
      NSString* type = [attributes objectForKey:NSFileType];
      if ([type isEqualToString:NSFileTypeRegular] && [self _checkFileExtension:item]) {
        [array addObject:@{
          @"path" : [relativePath stringByAppendingPathComponent:item],
          @"name" : item,
          @"size" : (NSNumber*)[attributes objectForKey:NSFileSize]
        }];
      } else if ([type isEqualToString:NSFileTypeDirectory]) {
        [array addObject:@{
          @"path" : [[relativePath stringByAppendingPathComponent:item] stringByAppendingString:@"/"],
          @"name" : item
        }];
      }
    }
  }
  return [MyGCDWebServerDataResponse responseWithJSONObject:array];
}

- (MyGCDWebServerResponse*)downloadFile:(MyGCDWebServerRequest*)request {
  NSString* relativePath = [[request query] objectForKey:@"path"];
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
  BOOL isDirectory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }
  if (isDirectory) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_BadRequest message:@"\"%@\" is a directory", relativePath];
  }

  NSString* fileName = [absolutePath lastPathComponent];
  if (([fileName hasPrefix:@"."] && !_allowHiddenItems) || ![self _checkFileExtension:fileName]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Downlading file name \"%@\" is not allowed", fileName];
  }

  if ([self.delegate respondsToSelector:@selector(webUploader:didDownloadFileAtPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.delegate webUploader:self didDownloadFileAtPath:absolutePath];
    });
  }
  return [MyGCDWebServerFileResponse responseWithFile:absolutePath isAttachment:YES];
}

- (MyGCDWebServerResponse*)uploadFile:(MyGCDWebServerMultiPartFormRequest*)request {
  NSRange range = [[request.headers objectForKey:@"Accept"] rangeOfString:@"application/json" options:NSCaseInsensitiveSearch];
  NSString* contentType = (range.location != NSNotFound ? @"application/json" : @"text/plain; charset=utf-8");  // Required when using iFrame transport (see https://github.com/blueimp/jQuery-File-Upload/wiki/Setup)

  MyGCDWebServerMultiPartFile* file = [request firstFileForControlName:@"files[]"];
  if ((!_allowHiddenItems && [file.fileName hasPrefix:@"."]) || ![self _checkFileExtension:file.fileName]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploaded file name \"%@\" is not allowed", file.fileName];
  }
  NSString* relativePath = [[request firstArgumentForControlName:@"path"] string];
  NSString* absolutePath = [self _uniquePathForPath:[[_uploadDirectory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)] stringByAppendingPathComponent:file.fileName]];

  if (![self shouldUploadFileAtPath:absolutePath withTemporaryFile:file.temporaryPath]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Uploading file \"%@\" to \"%@\" is not permitted", file.fileName, relativePath];
  }

  NSError* error = nil;
  if (![[NSFileManager defaultManager] moveItemAtPath:file.temporaryPath toPath:absolutePath error:&error]) {
    return [MyGCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving uploaded file to \"%@\"", relativePath];
  }

  if ([self.delegate respondsToSelector:@selector(webUploader:didUploadFileAtPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.delegate webUploader:self didUploadFileAtPath:absolutePath];
    });
  }
  return [MyGCDWebServerDataResponse responseWithJSONObject:@{} contentType:contentType];
}

- (MyGCDWebServerResponse*)moveItem:(MyGCDWebServerURLEncodedFormRequest*)request {
  NSString* oldRelativePath = [request.arguments objectForKey:@"oldPath"];
  NSString* oldAbsolutePath = [_uploadDirectory stringByAppendingPathComponent:GCDWebServerNormalizePath(oldRelativePath)];
  BOOL isDirectory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:oldAbsolutePath isDirectory:&isDirectory]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", oldRelativePath];
  }

  NSString* oldItemName = [oldAbsolutePath lastPathComponent];
  if ((!_allowHiddenItems && [oldItemName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:oldItemName])) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving from item name \"%@\" is not allowed", oldItemName];
  }

  NSString* newRelativePath = [request.arguments objectForKey:@"newPath"];
  NSString* newAbsolutePath = [self _uniquePathForPath:[_uploadDirectory stringByAppendingPathComponent:GCDWebServerNormalizePath(newRelativePath)]];

  NSString* newItemName = [newAbsolutePath lastPathComponent];
  if ((!_allowHiddenItems && [newItemName hasPrefix:@"."]) || (!isDirectory && ![self _checkFileExtension:newItemName])) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving to item name \"%@\" is not allowed", newItemName];
  }

  if (![self shouldMoveItemFromPath:oldAbsolutePath toPath:newAbsolutePath]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Moving \"%@\" to \"%@\" is not permitted", oldRelativePath, newRelativePath];
  }

  NSError* error = nil;
  if (![[NSFileManager defaultManager] moveItemAtPath:oldAbsolutePath toPath:newAbsolutePath error:&error]) {
    return [MyGCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed moving \"%@\" to \"%@\"", oldRelativePath, newRelativePath];
  }

  if ([self.delegate respondsToSelector:@selector(webUploader:didMoveItemFromPath:toPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.delegate webUploader:self didMoveItemFromPath:oldAbsolutePath toPath:newAbsolutePath];
    });
  }
  return [MyGCDWebServerDataResponse responseWithJSONObject:@{}];
}

- (MyGCDWebServerResponse*)deleteItem:(MyGCDWebServerURLEncodedFormRequest*)request {
  NSString* relativePath = [request.arguments objectForKey:@"path"];
  NSString* absolutePath = [_uploadDirectory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)];
  BOOL isDirectory = NO;
  if (![[NSFileManager defaultManager] fileExistsAtPath:absolutePath isDirectory:&isDirectory]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_NotFound message:@"\"%@\" does not exist", relativePath];
  }

  NSString* itemName = [absolutePath lastPathComponent];
  if (([itemName hasPrefix:@"."] && !_allowHiddenItems) || (!isDirectory && ![self _checkFileExtension:itemName])) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting item name \"%@\" is not allowed", itemName];
  }

  if (![self shouldDeleteItemAtPath:absolutePath]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Deleting \"%@\" is not permitted", relativePath];
  }

  NSError* error = nil;
  if (![[NSFileManager defaultManager] removeItemAtPath:absolutePath error:&error]) {
    return [MyGCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed deleting \"%@\"", relativePath];
  }

  if ([self.delegate respondsToSelector:@selector(webUploader:didDeleteItemAtPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.delegate webUploader:self didDeleteItemAtPath:absolutePath];
    });
  }
  return [MyGCDWebServerDataResponse responseWithJSONObject:@{}];
}

- (MyGCDWebServerResponse*)createDirectory:(MyGCDWebServerURLEncodedFormRequest*)request {
  NSString* relativePath = [request.arguments objectForKey:@"path"];
  NSString* absolutePath = [self _uniquePathForPath:[_uploadDirectory stringByAppendingPathComponent:GCDWebServerNormalizePath(relativePath)]];

  NSString* directoryName = [absolutePath lastPathComponent];
  if (!_allowHiddenItems && [directoryName hasPrefix:@"."]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory name \"%@\" is not allowed", directoryName];
  }

  if (![self shouldCreateDirectoryAtPath:absolutePath]) {
    return [MyGCDWebServerErrorResponse responseWithClientError:kGCDWebServerHTTPStatusCode_Forbidden message:@"Creating directory \"%@\" is not permitted", relativePath];
  }

  NSError* error = nil;
  if (![[NSFileManager defaultManager] createDirectoryAtPath:absolutePath withIntermediateDirectories:NO attributes:nil error:&error]) {
    return [MyGCDWebServerErrorResponse responseWithServerError:kGCDWebServerHTTPStatusCode_InternalServerError underlyingError:error message:@"Failed creating directory \"%@\"", relativePath];
  }

  if ([self.delegate respondsToSelector:@selector(webUploader:didCreateDirectoryAtPath:)]) {
    dispatch_async(dispatch_get_main_queue(), ^{
      [self.delegate webUploader:self didCreateDirectoryAtPath:absolutePath];
    });
  }
  return [MyGCDWebServerDataResponse responseWithJSONObject:@{}];
}

@end

@implementation GCDWebUploader (Subclassing)

- (BOOL)shouldUploadFileAtPath:(NSString*)path withTemporaryFile:(NSString*)tempPath {
  return YES;
}

- (BOOL)shouldMoveItemFromPath:(NSString*)fromPath toPath:(NSString*)toPath {
  return YES;
}

- (BOOL)shouldDeleteItemAtPath:(NSString*)path {
  return YES;
}

- (BOOL)shouldCreateDirectoryAtPath:(NSString*)path {
  return YES;
}

@end
