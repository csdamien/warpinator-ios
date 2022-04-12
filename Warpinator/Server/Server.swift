//
//  Server.swift
//  Warpinator
//
//  Created by William Millington on 2021-10-04.
//

import UIKit

import GRPC
import NIO
import NIOSSL

import Network

import Logging


final class Server {
    
    //
    // MARK: ServerError
    enum ServerError: Error {
        case NO_EVENTLOOP
        case CREDENTIALS_INVALID
        case CREDENTIALS_UNAVAILABLE
        case CREDENTIALS_GENERATION_ERROR
        case SERVER_FAILURE
        case UKNOWN_ERROR
        
        var localizedDescription: String {
            switch self {
            case .NO_EVENTLOOP: return "No available eventloop"
            case .CREDENTIALS_INVALID: return "Server certificate and/or private key are invalid"
            case .CREDENTIALS_UNAVAILABLE: return "Server certificate and/or private key could not be found"
            case .CREDENTIALS_GENERATION_ERROR: return "Server credentials could not be created"
            case .SERVER_FAILURE: return "Server failed to start"
            case .UKNOWN_ERROR: return "Server has encountered an unknown error"
            }
        }
    }
    
    
    private let DEBUG_TAG: String = "Server: "
    
    // TODO: turn into static Settings properties
    private let SERVICE_TYPE = "_warpinator._tcp."
    private let SERVICE_DOMAIN = "local"
    
    var eventLoopGroup: EventLoopGroup
    
    let warpinatorProvider: WarpinatorServiceProvider // = WarpinatorServiceProvider()
    
//    var remoteManager: RemoteManager
    
    var errorDelegate: ErrorDelegate?
    
    var server: GRPC.Server?
    var isRunning: Bool = false
    var attempts = 0
    
    let queueLabel = "WarpinatorServerQueue"
    lazy var serverQueue = DispatchQueue(label: queueLabel, qos: .userInitiated)
    
    var logger: Logger = {
        var log = Logger(label: "warpinator.Server", factory: StreamLogHandler.standardOutput)
        log.logLevel = .debug
        return log
    }()
    
    
    init(eventloopGroup group: EventLoopGroup,
         provider: WarpinatorServiceProvider,
         errorDelegate delegate: ErrorDelegate) {
        
        eventLoopGroup = group
        
        warpinatorProvider = provider
        errorDelegate = delegate
        
    }
    
    
    //
    // MARK: start
    func start() -> EventLoopFuture<Void>  {
        
        guard let credentials = try? Authenticator.shared.getServerCredentials() else {
            return eventLoopGroup.next().makeFailedFuture( ServerError.CREDENTIALS_GENERATION_ERROR )
        }
        
        return startupServer(withCredentials: credentials).map { server in
            print(self.DEBUG_TAG+"transfer server started on: \(String(describing: server.channel.localAddress))")
            self.server = server
            self.isRunning = true
        }
        
    }
    
    
    private func startupServer(withCredentials credentials: Authenticator.Credentials) -> EventLoopFuture<GRPC.Server>  {
        
        let serverCertificate =  credentials.certificate
        let serverPrivateKey = credentials.key
        
        return GRPC.Server.usingTLSBackedByNIOSSL(on: eventLoopGroup,
                                                        certificateChain: [ serverCertificate  ],
                                                        privateKey: serverPrivateKey )
            .withTLS(trustRoots: .certificates( [serverCertificate ] ) )
            .withServiceProviders( [ warpinatorProvider ] )
            .bind(host: "\(Utils.getIP_V4_Address())",
                  port: Int( SettingsManager.shared.transferPortNumber ))
        
            // try again on error
            .flatMapError { error in
                
                print( self.DEBUG_TAG + "transfer server failed: \(error))")
                
                return self.eventLoopGroup.next().flatScheduleTask(in: .seconds(2)) {
                    self.startupServer(withCredentials: credentials)
                }.futureResult
            }
        
    }
    
    
    // MARK: stop
    func stop() -> EventLoopFuture<Void> {
        guard let server = server, isRunning else {
            return eventLoopGroup.next().makeSucceededVoidFuture()
        }
        
        isRunning = false
        return server.initiateGracefulShutdown()
    }
    
    
}

