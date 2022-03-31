//
//  RemoteManager.swift
//  Warpinator
//
//  Created by William Millington on 2021-10-17.
//

import Foundation
import Network

import GRPC
import NIO


final class RemoteManager {
    
    private let DEBUG_TAG: String = "RemoteManager: "
    
    var remotes: [String: Remote] = [:] // [hostname:remote]
    
    weak var remotesViewController: ViewController?
    
    var remoteEventloopGroup: EventLoopGroup?
    
    let queueLabel = "RemoteManagerCleanupQueue"
    lazy var cleanupQueue = DispatchQueue(label: queueLabel, qos: .userInteractive)
    
    
//    // TODO remove this feature.
//    // - Warp registration returns wrong address (I think is a bug in OG Warpinator?)
//    // - IP is now secured during authentication
//    /* if WarpRegistration receives a request BEFORE we detect a remote
//     with that hostname, then store that IP address here so we can update that
//     remote once it is detected   [hostname:ipaddress] */
//    var ipPlaceHolders : [String:String] = [:]
//
    
    //
    // MARK: add Remote
    func addRemote(_ remote: Remote){
        print(DEBUG_TAG+"adding remote with UUID: \(remote.details.uuid)")
        
        remote.eventloopGroup = remoteEventloopGroup 
        remotes[remote.details.uuid] = remote
        
//        // if we've stored the ip address of a remote with that hostname
//        // This is probably not great, for the same reason listed down in
//        // storeIPAddress()
//        if let address = ipPlaceHolders[remote.details.hostname] {
//            remote.details.ipAddress = address
//        }
        
        DispatchQueue.main.async {
            self.remotesViewController?.remoteAdded(remote)
        }
        
        remote.startConnection()
    }
    
    
    // tells the remote with this uuid to start a connection,
    // if it exists
    func startConnection(forRemoteWithUUID uuid: String) {
        
        guard let remote = remotes[uuid] else {
            print(DEBUG_TAG+"\t remote not found")
            return
        }
        remote.startConnection()
    }
    
    
    
    // MARK: remove Remote
    func removeRemote(withUUID uuid: String){
            print(DEBUG_TAG+"removing remote...")
        
        guard let remote = remotes[uuid] else {
            print(DEBUG_TAG+"\t remote not found")
            return
        }
        
        
        let future = remote.disconnect()
        
        future?.whenComplete { result in
            
            self.remotes.removeValue(forKey: remote.details.uuid)
            
            DispatchQueue.main.async {
                self.remotesViewController?.remoteRemoved(with: uuid)
            }
            
            print(self.DEBUG_TAG+"\t remote removed")
        }
//
//        remotes.removeValue(forKey: remote.details.uuid)
//
//        DispatchQueue.main.async {
//            self.remotesViewController?.remoteRemoved(with: uuid)
//        }
//
//        print(DEBUG_TAG+"\t remote removed")
//
    }
    
    
    //
    // MARK storeIPAddress
//    func storeIPAddress(_ address: String, forHostname hostname: String){
//
//        print(DEBUG_TAG+"storing address (\(address)) for \(hostname)")
//
//        // TODO this fails if two remotes share a hostname. Not good. No bueno.
//        // Can't use uuid because it's not provided in the Registration request
//        remotes.forEach { (key,remote) in
//            if remote.details.hostname == hostname {
//                print(self.DEBUG_TAG+"\tfound remote for hostname\(hostname)")
//                remote.details.ipAddress = address
//                remote.startConnection()
//                return
//            }
//        }
//
//        ipPlaceHolders[hostname] = address
//    }
    
    
    //
    // MARK: find remote
    @discardableResult
    func containsRemote(for uuid: String) -> Remote? {
        
        if let remote = remotes.first(where: { (key, entry) in
            return entry.details.uuid == uuid })?.value {
            return remote
        }
        
        return nil
    }
    
    
    
    
    
    // MARK: shutdown all remotes
    func shutdownAllRemotes() -> EventLoopFuture<Void>? {
        
        print(DEBUG_TAG+"shutting down all remotes")
        
        guard let eventloop = remoteEventloopGroup?.next() else {
            return nil
        }
        
//        let promise = eventloop.makePromise(of: Void.self)
        
//        let firstFuture = eventloop.makeSucceededVoidFuture()
//        for remote in remotes.values {
//            let f = remote.disconnect()
//        }
        
        let futures = remotes.values.compactMap { remote in
            return remote.disconnect()
        }
        
//        let lastFuture =  EventLoopFuture.whenAllComplete(futures, on: eventloop)
        
        let future = EventLoopFuture.whenAllComplete(futures, on: eventloop).map { _ -> Void in
            print(self.DEBUG_TAG+"Remotes have finished shutting down")
//            return {}()
//            return eventloop.makeSucceededVoidFuture()
        }
        
        
        
        return future //eventloop.makeSucceededVoidFuture() //EventLoopFuture.whenAllComplete(futures, on: eventloop)
//        let lastFuture = futures.reduce(firstFuture, { (lastFuture, thisFuture) in
//
//            let nextFuture = lastFuture.map {
//
//            }
//
//            return eventloop.makeSucceededVoidFuture()
//        })
        
        
//        let future = eventloop.submit {
//
//            let futures = self.remotes.values.compactMap { $0.disconnect() }
//
//            futures.forEach { future in
//                do {
//                    try future.wait()
//                    print(self.DEBUG_TAG+"disconnection successful")
//                }
//                catch {
//                    print(self.DEBUG_TAG+"disconnection unsuccessful: \(error)")
//                } // if something cancels this 'wait', it doesn't matter
//            }
//
//
//        }
        
        
        // make a promise that we're waiting for all the remotes to shut down
        // if a shutdown fails
//        cleanupQueue.async {
//            let futures = self.remotes.values.compactMap { $0.disconnect() }
//
//            futures.forEach { future in
//                do {
//                    try future.wait()
//                    print(self.DEBUG_TAG+"")
//                }
//                catch { } // if something cancels this 'wait', it doesn't matter
//            }
//
//            // succeed promise
////            promise.su
//        }
        
//        return future
        
//        var futures: [EventLoopFuture<Void>] = []
//
//        remotes.values.forEach { remote in
//            if let future = remote.disconnect() {
//                futures.append( future )
//            }
//        }
        
//        return futures
    }
    
}



extension RemoteManager: MDNSBrowserDelegate {
    
    
    // MARK: mDNS result added
    func mDNSBrowserDidAddResult(_ result: NWBrowser.Result) {
        
        print(DEBUG_TAG+"mDNSBrowser added result: \(result.endpoint)")
        
        // ignore result:
        // - if result has metadata,
        // - AND if the metadata has a record "type",
        // - AND if "type" is 'flush'
        guard case let NWBrowser.Result.Metadata.bonjour(record) = result.metadata,
           let type = record.dictionary["type"],
           type != "flush" else {
            print(DEBUG_TAG+"service \(result.endpoint) is flushing; ignore"); return
        }
        
        
        var serviceName = "unknown_service"
        switch result.endpoint {
        case .service(name: let name, type: _, domain: _, interface: _):
            
            print(DEBUG_TAG+"Found service \(name) (at endpoint: \(result.endpoint))")
            
            serviceName = name
            
            // Check if we found own MDNS record
            if name == SettingsManager.shared.uuid {
                print(DEBUG_TAG+"\t\tFound myself (\(result.endpoint))"); return
            } else {
                print(DEBUG_TAG+"service discovered: \(name)")
            }
            
        default: print(DEBUG_TAG+"unknown service endpoint type: \(result.endpoint)"); return
        }
        
        
        //
        var hostname = serviceName
        var api = "1"
        var authPort = 42000
        
        // parse TXT record for metadata
        if case let NWBrowser.Result.Metadata.bonjour(txtRecord) = result.metadata {
            
            for (key, value) in txtRecord.dictionary {
                switch key {
                case "hostname": hostname = value
                case "api-version": api = value
                case "auth-port": authPort = Int(value) ?? 42000
                case "type": break
                default: print("unknown TXT record type: \"\(key)\":\"\(value)\"")
                }
            }
        }
        
        
        
        // check if we already know this remote
        if let remote = containsRemote(for: serviceName) {
            
            print(DEBUG_TAG+"Service already added")
            
            // Are we connected?
            if [ .Disconnected, .Idle, .Error ].contains( remote.details.status ) {
                print(DEBUG_TAG+"\t\t not connected: reconnecting...")
                remote.startConnection()
            }
            return
        }
        
        
        var details = RemoteDetails(endpoint: result.endpoint)
        details.hostname = hostname
        details.uuid = serviceName
        details.api = api
        details.port = 42000
        details.authPort = authPort //"42000"
        details.status = .Disconnected
        
        
        let newRemote = Remote(details: details)
        
        addRemote(newRemote)
        
    }
    
    
    // MARK: mDNS result removed
    func mDNSBrowserDidRemoveResult(_ result: NWBrowser.Result) {
        
        print(DEBUG_TAG+"mDNSBrowser removed result: \(result.endpoint)")
        
        // check metadata for "type",
        // and if type is 'flush', then ignore
        if case let NWBrowser.Result.Metadata.bonjour(record) = result.metadata,
           let type = record.dictionary["type"],
           type == "flush" {
            print(DEBUG_TAG+"service \(result.endpoint) is flushing; ignore"); return
        }
        
        
        if case let .service(name: name, type: _, domain: _, interface: _) = result.endpoint {
            
            // check if we have a remote registered to the service name
            if let remote = containsRemote(for: name) {
        
                // remove it
                removeRemote(withUUID: remote.details.uuid)
            }
        }
        
    }
    
}
