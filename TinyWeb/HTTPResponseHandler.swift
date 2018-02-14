 
//
//  HTTPResponseHandler.swift
//  TinyWeb
//
//  Created by nspool on 30/07/2015.
//  Copyright © 2015 nspool. All rights reserved.
//

import UIKit

class HTTPResponseHandler {
  
  func startDefaultResponse(_ fileHandle: FileHandle) {
    let response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 501, nil, kCFHTTPVersion1_1).takeRetainedValue()
    CFHTTPMessageSetHeaderFieldValue(response, "Content-Type" as CFString, "text/html" as CFString)
    CFHTTPMessageSetHeaderFieldValue(response, "Connection" as CFString, "close" as CFString)
    let body = "<html><head><title>501 - Not (Yet) Implemented</title></head>".data(using: String.Encoding.utf8)
    CFHTTPMessageSetBody(response,  body! as CFData)
    let headerData = CFHTTPMessageCopySerializedMessage(response)!.takeRetainedValue()
    fileHandle.write(headerData as Data)
  }
  
  func startImageResponse(_ fileHandle: FileHandle) {
    if let image = try? Data(contentsOf: URL(fileURLWithPath: Bundle.main.path(forResource: "test", ofType: "jpg")!)) {
      let response = CFHTTPMessageCreateResponse(kCFAllocatorDefault, 200, nil, kCFHTTPVersion1_0).takeRetainedValue()
      CFHTTPMessageSetHeaderFieldValue(response, "Content-Type" as CFString, "image/jpeg" as CFString)
      CFHTTPMessageSetHeaderFieldValue(response, "Content-Length" as CFString, "\(image.count)" as CFString)
      let headerData = CFHTTPMessageCopySerializedMessage(response)!.takeRetainedValue()
      fileHandle.write(headerData as Data)
      fileHandle.write(image)
    } else  {
      startDefaultResponse(fileHandle)
    }
  }
 }
