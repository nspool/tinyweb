//
//  HttpServer.swift
//  TinyWeb
//
//  Created by nspool on 30/07/2015.
//  Copyright © 2015 nspool. All rights reserved.
//

/*                                          
          ┌───────────────────────┐         
          │         Start         │         
          └───────────┬───────────┘         
                      │                     
                      ▼                     
 ┌─────────────────────────────────────────┐
 │  receiveIncomingConnectionNotification  │
 └────────────────────┬────────────────────┘
                      │                     
                      ▼                     
 ┌─────────────────────────────────────────┐
 │     receiveIncomingDataNotification     │
 └────────────────────┬────────────────────┘
                      │                     
                      ▼                     
  ┌────────────────────────────────────────┐
  │          HTTPResponseHandler           │
  └────────────────────────────────────────┘
*/

import UIKit

class HttpServer {
  
  enum HTTPServerState: Int {
    case server_STATE_IDLE, server_STATE_STARTING, server_STATE_RUNNING, server_STATE_STOPPING
  }
  
  var lastError: NSError!
  var listeningHandle: FileHandle!
  var socket: CFSocket!
  var state: HTTPServerState!
  var incomingRequests: CFMutableDictionary!
  var responseHandlers: NSMutableSet!
  
  init() {
    state = .server_STATE_IDLE
    responseHandlers = NSMutableSet()
    var keyCallbacks = kCFTypeDictionaryKeyCallBacks
    var valueCallbacks = kCFTypeDictionaryValueCallBacks
    incomingRequests = CFDictionaryCreateMutable(kCFAllocatorDefault, 0,&keyCallbacks,&valueCallbacks)
    start()
  }
  
  func port_htons(_ port: in_port_t) -> in_port_t {
    let isLittleEndian = Int(OSHostByteOrder()) == OSLittleEndian
    return isLittleEndian ? _OSSwapInt16(port) : port
  }
  
  func start() {
    lastError = nil
    state = .server_STATE_STARTING
    socket = CFSocketCreate(kCFAllocatorDefault, PF_INET, SOCK_STREAM,IPPROTO_TCP, 0, nil, nil)
    guard socket != nil else {
      print("failed to create socket")
      return
    }
    var reuse :Int = 1
    let fileDescriptor = CFSocketGetNative(socket);
    guard setsockopt(fileDescriptor, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout<Int>.size)) == 0 else {
      print("failed to set socket options")
      return
    }
    var addr = sockaddr_in(sin_len: __uint8_t(MemoryLayout<sockaddr_in>.size), sin_family: sa_family_t(AF_INET),
      sin_port: port_htons(8080), sin_addr: in_addr(s_addr: inet_addr("0.0.0.0")), sin_zero: (0, 0, 0, 0, 0, 0, 0, 0))
    withUnsafePointer(to: &addr) { (pointer: UnsafePointer<sockaddr_in>) in
        let addressData = NSData(bytes: pointer, length: MemoryLayout<sockaddr_in>.size) as CFData
      guard CFSocketSetAddress(socket, addressData) == .success else {
        print("failed to bind socket")
        return
      }
    }
    listeningHandle = FileHandle(fileDescriptor: fileDescriptor, closeOnDealloc: true)
    NotificationCenter.default.addObserver(
      self,
      selector: #selector(HttpServer.receiveIncomingConnectionNotification(_:)),
      name: NSNotification.Name.NSFileHandleConnectionAccepted,
      object: nil)
    listeningHandle.acceptConnectionInBackgroundAndNotify()
    state = .server_STATE_RUNNING
  }
  
  @objc func receiveIncomingConnectionNotification(_ notification:Notification) {
    guard let userInfo = notification.userInfo as? Dictionary<String,FileHandle> else {
      print("can't get userInfo")
      return
    }
    if let incomingFileHandle = userInfo[NSFileHandleNotificationFileHandleItem] {
      CFDictionaryAddValue(
        incomingRequests,
        Unmanaged.passUnretained(incomingFileHandle).toOpaque(),
        Unmanaged.passUnretained(CFHTTPMessageCreateEmpty(kCFAllocatorDefault, true).takeUnretainedValue()).toOpaque())
      NotificationCenter.default.addObserver(
        self,
        selector: #selector(HttpServer.receiveIncomingDataNotification(_:)),
        name: NSNotification.Name.NSFileHandleDataAvailable,
        object: incomingFileHandle)
      incomingFileHandle.waitForDataInBackgroundAndNotify()
    }
    listeningHandle.acceptConnectionInBackgroundAndNotify()
  }
  
  func closeHandler(_ handle : FileHandle) {
    responseHandlers.remove(handle)
  }
  
  func stopReceiving(_ handle:FileHandle, close:Bool) {
    if close == true {
      handle.closeFile()
    }
    NotificationCenter.default.removeObserver(
      self,
      name: NSNotification.Name.NSFileHandleDataAvailable,
      object: handle)
    CFDictionaryRemoveValue(incomingRequests, Unmanaged.passUnretained(handle).toOpaque());
  }
  
  @objc func receiveIncomingDataNotification(_ notification:Notification) {
    guard let incomingFileHandle = notification.object as? FileHandle else {
      print("failed to get incoming file handle")
      return
    }
    let d = incomingFileHandle.availableData
    guard d.count > 0 else {
      stopReceiving(incomingFileHandle, close:false)
      return
    }
    let incomingRequest = CFDictionaryGetValue(incomingRequests, Unmanaged.passUnretained(incomingFileHandle).toOpaque())
    guard incomingRequest != nil else {
      stopReceiving(incomingFileHandle, close:true)
      return;
    }
    let ir = unsafeBitCast(incomingRequest, to: CFHTTPMessage.self)
    let res = CFHTTPMessageAppendBytes(ir, (d as NSData).bytes.bindMemory(to: UInt8.self, capacity: d.count), CFIndex(d.count))
    guard res != false else {
      stopReceiving(incomingFileHandle, close: true)
      return
    }
    if CFHTTPMessageIsHeaderComplete(ir) != false {
      let handler = HTTPResponseHandler()
      responseHandlers.add(handler)
      stopReceiving(incomingFileHandle, close: false)
      // handler.startImageResponse(incomingFileHandle)
        handler.startDefaultResponse(incomingFileHandle)
    }
    closeHandler(incomingFileHandle)
  }
}
