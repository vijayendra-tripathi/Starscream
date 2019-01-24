//
//  HTTPTransport.swift
//  Starscream
//
//  Created by Dalton Cherry on 1/23/19.
//  Copyright © 2019 Vluxe. All rights reserved.
//

#if canImport(Network)
import Foundation
import Network

public enum TCPTransportError: Error {
    case invalidRequest
}

@available(macOS 10.14, iOS 12.0, watchOS 5.0, tvOS 12.0, *)
public class TCPTransport: Transport {
    private var connection: NWConnection?
    private let queue = DispatchQueue(label: "com.vluxe.starscream.networkstream", attributes: [])
    private weak var delegate: TransportEventClient?
    private var isRunning = false
    
    public func connect(url: URL, timeout: Double = 10, isTLS: Bool = true) {
        guard let host = url.host, let port = url.port else {
            delegate?.connectionChanged(state: .failed(TCPTransportError.invalidRequest))
            return
        }
        //TODO: timeout?
        let parameters: NWParameters = isTLS ? .tls : .tcp
        let conn = NWConnection(host: NWEndpoint.Host.name(host, nil), port: NWEndpoint.Port(rawValue: UInt16(port))!, using: parameters)

        conn.stateUpdateHandler = { [weak self] (newState) in
            switch newState {
            case .ready:
                self?.delegate?.connectionChanged(state: .connected)
            case .waiting:
                self?.delegate?.connectionChanged(state: .waiting)
            case .cancelled:
                self?.delegate?.connectionChanged(state: .cancelled)
            case .failed(let error):
                self?.delegate?.connectionChanged(state: .failed(error))
            case .setup, .preparing:
                break
            }
        }
        
        conn.viabilityUpdateHandler = { [weak self] (isViable) in
            self?.delegate?.connectionChanged(state: .viability(isViable))
        }
        
        conn.betterPathUpdateHandler = { [weak self] (isBetter) in
            self?.delegate?.connectionChanged(state: .shouldReconnect(isBetter))
        }
        
        conn.start(queue: queue)
        connection = conn
        isRunning = true
        readLoop()
    }
    
    public func disconnect() {
        isRunning = false
        connection?.cancel()
    }
    
    public func register(delegate: TransportEventClient) {
        self.delegate = delegate
    }
    
    public func write(data: Data, completion: @escaping ((Error?) -> ())) {
        connection?.send(content: data, completion: .contentProcessed { (error) in
            completion(error)
        })
    }
    
    //readLoop keeps reading from the connection to get the latest content
    private func readLoop() {
        if !isRunning {
            return
        }
        connection?.receive(minimumIncompleteLength: 2, maximumLength: 4096, completion: {[weak self] (data, context, isComplete, error) in
            guard let s = self else {return}
            if let data = data {
                s.delegate?.connectionChanged(state: .receive(data))
            }
            s.readLoop()
        })
    }
}
#else
typealias TCPTransport = FoundationTransport
#endif
