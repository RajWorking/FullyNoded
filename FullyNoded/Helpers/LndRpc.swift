//
//  LndRpc.swift
//  FullyNoded
//
//  Created by Peter Denton on 6/5/21.
//  Copyright © 2021 Fontaine. All rights reserved.
//

import Foundation

class LndRpc {
    
    static let sharedInstance = LndRpc()
    lazy var torClient = TorClient.sharedInstance
    
    private init() {}
    
    func makeLndCommand(command: LND_REST, param: [String:Any], urlExt: String?, completion: @escaping ((response: [String:Any]?, error: String?)) -> Void) {
        #if DEBUG
        print("makeLndCommand")
        #endif
        
        CoreDataService.retrieveEntity(entityName: .newNodes) { [weak self] nodes in
            guard let self = self else { return }
            
            guard let nodes = nodes, nodes.count > 0 else {
                completion((nil, "error getting nodes from core data"))
                return
            }
            
            var potentialLightningNode: [String:Any]?
                        
            for node in nodes {
                if let isLightning = node["isLightning"] as? Bool, isLightning {
                    if node["macaroon"] != nil {
                        potentialLightningNode = node
                    }
                }
            }
            
            guard let lightningNode = potentialLightningNode, let encryptedMacaroon = lightningNode["macaroon"] as? Data else {
                completion((nil, "No LND node."))
                return
            }
            
            let node = NodeStruct(dictionary: lightningNode)
            
            guard let encAddress = node.onionAddress else {
                completion((nil, "Error getting node address."))
                return
            }
            
            let onionAddress = decryptedValue(encAddress)
            let macaroonHex = decryptedValue(encryptedMacaroon)
            
            var urlString = "https://\(onionAddress)/\(command.rawValue)"
            
            if command == .payreq {
                urlString += "/\(param)"
            }
            
            guard let url = URL(string: urlString) else {
                completion((nil, "error converting your url"))
                return
            }
            
            #if DEBUG
                print("url: \(url)")
            #endif
            
            var request = URLRequest(url: url)
            request.addValue(macaroonHex, forHTTPHeaderField: "Grpc-Metadata-macaroon")
            
            
            switch command {
            case .addinvoice:
                guard let jsonData = try? JSONSerialization.data(withJSONObject: param) else { return }
                
                request.setValue("application/json", forHTTPHeaderField: "Content-Type")
                request.httpBody = jsonData
                request.setValue("\(jsonData.count)", forHTTPHeaderField: "Content-Length")
                request.httpMethod = "POST"
                #if DEBUG
                print("request: {\"jsonrpc\":\"1.0\",\"id\":\"curltest\",\"method\":\"addinvoice\",\"params\":[\(param)]}")
                #endif
            default:
                request.httpMethod = "GET"
                #if DEBUG
                print("request: \(request)")
                #endif
            }            
            
            let task = self.torClient.session.dataTask(with: request as URLRequest) { (data, response, error) -> Void in
                guard let urlContent = data,
                      let json = try? JSONSerialization.jsonObject(with: urlContent, options: [.mutableContainers]) as? [String : Any] else {
                    
                    if let error = error {
                        #if DEBUG
                        print("lnd error: \(error.localizedDescription)")
                        #endif
                        
                        completion((nil, error.localizedDescription))
                        
                    } else if let httpResponse = response as? HTTPURLResponse {
                        switch httpResponse.statusCode {
                        case 401:
                            completion((nil, "Looks like your LND credentials are incorrect, please double check them."))
                        case 404:
                            completion((nil, "Command not found."))
                        default:
                            completion((nil, "Unable to decode the response from your node, http status code: \(httpResponse.statusCode)"))
                        }
                        
                    } else {
                        completion((nil, "Unable to decode the response from your node..."))
                    }
                    
                    return
                }
                
                #if DEBUG
                print("lnd json: \(json)")
                #endif
                
                completion((json, nil))
            }
            
            task.resume()
        }
    }
}
