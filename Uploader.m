#import "Uploader.h"

@implementation RNFSUploadParams

@end

@interface RNFSUploader()

@property (copy) RNFSUploadParams* params;

@property (retain) NSURLSessionDataTask* task;

@end

@implementation RNFSUploader

- (void)uploadFiles:(RNFSUploadParams*)params
{
  _params = params;

  NSString *method = _params.method;
  NSURL *url = [NSURL URLWithString:_params.toUrl];
  NSMutableURLRequest *req = [NSMutableURLRequest requestWithURL:url];
  [req setHTTPMethod:method];

  // set headers
  NSString *formBoundaryString = [self generateBoundaryString];
  NSString *contentType = [NSString stringWithFormat:@"multipart/form-data; boundary=%@", formBoundaryString];
  [req setValue:contentType forHTTPHeaderField:@"Content-Type"];
  for (NSString *key in _params.headers) {
    id val = [_params.headers objectForKey:key];
    if ([val respondsToSelector:@selector(stringValue)]) {
      val = [val stringValue];
    }
    if (![val isKindOfClass:[NSString class]]) {
      continue;
    }
    [req setValue:val forHTTPHeaderField:key];
  }

  NSData *formBoundaryData = [[NSString stringWithFormat:@"--%@\r\n", formBoundaryString] dataUsingEncoding:NSUTF8StringEncoding];
  NSMutableData* reqBody = [NSMutableData data];

  // add fields
  for (NSString *key in _params.fields) {
    id val = [_params.fields objectForKey:key];
    if ([val respondsToSelector:@selector(stringValue)]) {
      val = [val stringValue];
    }
    if (![val isKindOfClass:[NSString class]]) {
      continue;
    }

    [reqBody appendData:formBoundaryData];
    [reqBody appendData:[[NSString stringWithFormat:@"Content-Disposition: form-data; name=\"%@\"\r\n\r\n", key] dataUsingEncoding:NSUTF8StringEncoding]];
    [reqBody appendData:[val dataUsingEncoding:NSUTF8StringEncoding]];
    [reqBody appendData:[@"\r\n" dataUsingEncoding:NSUTF8StringEncoding]];
  }

  // add files
  for (NSDictionary *file in _params.files) {
    NSString *name = file[@"name"];
    NSString *filename = file[@"filename"];
    NSString *filepath = file[@"filepath"];
    NSString *filetype = file[@"filetype"];

    // Check if file exists
    NSFileManager *fileManager = [NSFileManager defaultManager];
    if (![fileManager fileExistsAtPath:filepath]){
      // NSError* error = [NSError errorWithDomain:@"Uploader" code:NSURLErrorFileDoesNotExist userInfo:@{NSLocalizedDescriptionKey: [NSString stringWithFormat: @"Failed to open target file at path: %@", filepath]}];
      // return _params.errorCallback(error);
      NSLog(@"Failed to open target file at path: %@", filepath);
      continue;
    }

    NSData *fileData = [NSData dataWithContentsOfFile:filepath];

    [reqBody appendData:fileData];
  }

  // add end boundary
  NSData* end = [[NSString stringWithFormat:@"--%@--\r\n", formBoundaryString] dataUsingEncoding:NSUTF8StringEncoding];
  [reqBody appendData:end];

  // send request
  [req setHTTPBody:reqBody];

  NSURLSessionConfiguration *sessionConfiguration = [NSURLSessionConfiguration defaultSessionConfiguration];
  NSURLSession *session = [NSURLSession sessionWithConfiguration:sessionConfiguration delegate:(id)self delegateQueue:[NSOperationQueue mainQueue]];
  _task = [session dataTaskWithRequest:req completionHandler:^(NSData *data, NSURLResponse *response, NSError *error) {
      NSString * str = [[NSString alloc] initWithData:data encoding:NSUTF8StringEncoding];
      return _params.completeCallback(str, response);
  }];
  [_task resume];
  _params.beginCallback();
}

- (NSString *)generateBoundaryString
{
  NSString *uuid = [[NSUUID UUID] UUIDString];
  return [NSString stringWithFormat:@"----%@", uuid];
}

- (NSString *)mimeTypeForPath:(NSString *)filepath
{
  NSString *fileExtension = [filepath pathExtension];
  NSString *UTI = (__bridge_transfer NSString *)UTTypeCreatePreferredIdentifierForTag(kUTTagClassFilenameExtension, (__bridge CFStringRef)fileExtension, NULL);
  NSString *contentType = (__bridge_transfer NSString *)UTTypeCopyPreferredTagWithClass((__bridge CFStringRef)UTI, kUTTagClassMIMEType);

  if (contentType) {
    return contentType;
  }
  return @"application/octet-stream";
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didCompleteWithError:(NSError *)error
{
  if(error != nil) {
    return _params.errorCallback(error);
  }
}

- (void)URLSession:(NSURLSession *)session task:(NSURLSessionTask *)task didSendBodyData:(int64_t)bytesSent totalBytesSent:(int64_t)totalBytesSent totalBytesExpectedToSend:(NSInteger)totalBytesExpectedToSend
{
  return _params.progressCallback([NSNumber numberWithLongLong:totalBytesExpectedToSend], [NSNumber numberWithLongLong:totalBytesSent]);
}

- (void)stopUpload
{
  [_task cancel];
}

@end
