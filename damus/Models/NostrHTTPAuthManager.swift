//
//  NostrHTTPAuthManager.swift
//  damus
//
//  Created by Blake Jakopovic on 15/5/2023.
//

import Foundation
import Kingfisher
import UIKit

class NostrHTTPAuthManager {
    struct DomainData {
        let domain: String
        let expiration: Date?
    }
    
    private let keypair: Keypair
    private var domains: [DomainData]
    
    init(keypair: Keypair, domainExpiries: [(domain: String, expiry: Date?)]) {
        self.keypair = keypair
        
        // TODO: Ideally we load the domains from a persistant store without param
        self.domains = domainExpiries.map { domainExpiry in
            return DomainData(domain: domainExpiry.domain, expiration: domainExpiry.expiry)
        }
        
        // TODO: Will need a mechanism to cleanup/remove all stale trusted domains
//        domains.removeAll { $0.expiration < Date() }
    }
    
    func isDomainTrusted(_ domain: String) -> Bool {
        return domains.contains { $0.domain == domain && isValidDomain($0) }
    }
        
    func addDomain(_ domain: String, expiration: Date?) {
        // TODO: Persist this change
        domains.append(DomainData(domain: domain, expiration: expiration))
        if expiration == nil {
            print("Adding domain for nostr http auth: \(domain) - no expiry")
        } else {
            print("Adding domain for nostr http auth: \(domain) - with expiry")
        }
        print(self.domains)
    }
    
    // TODO: We likely want a list view in settings that displays these domains
    func removeDomain(_ domain: String) {
        // TODO: Persist this change
        domains.removeAll { $0.domain == domain }
        print("Removing domain for nostr http auth: \(domain)")
    }
    
    private func isValidDomain(_ domainData: DomainData) -> Bool {
        // If a domain expiry is set, make sure it's in the future
        if let expiration = domainData.expiration {
            return expiration > Date()
        }
        return true
    }
    
    func testNostHttpAuthHeader(headers: NSDictionary) -> Bool {
        if let dict = headers as? [String: String],
           dict.contains(where: {
               $0.key.uppercased()   == "WWW-AUTHENTICATE" &&
               $0.value.uppercased() == "NOSTR-NIP-98" }
           ) {
            return true
        } else {
            return false
        }
    }
    
    func getHttpAuthHeaderValue(url: URL) -> String? {
        
        var tags: [[String]] = [["method", "GET"]]
        
        // For now the spec only specifies a single u tag.. but I expect that to change
        tags.append(["u", url.absoluteString])
        
        let auth_event = NostrEvent(content: "", pubkey: keypair.pubkey, kind: 27235, tags: tags)
        auth_event.calculate_id()
        // TODO: This can error when state.keypair.privkey is nil
        if keypair.privkey == nil {
            return nil
        }
        auth_event.sign(privkey: keypair.privkey!)
        
        let signed_auth_event_base64: String = Data(encode_json(auth_event)!.utf8).base64EncodedString()
        
        // Authorization: Nostr BASE64_HTTP_AUTH_EVENT
        let auth_header_value = "Nostr \(signed_auth_event_base64)"
        
        return auth_header_value
    }
    
    func getRequestModifier(url: URL) -> AnyModifier {
        // TODO: Fix error handling when private key is not set, so cannot sign event
        //       This is likely mostly a xcode preview issue, rather than normal ops
        let auth_header_value = getHttpAuthHeaderValue(url: url) ?? ""
        
        return AnyModifier { request in
            var req = request
            req.addValue(auth_header_value, forHTTPHeaderField: "Authorization")
            return req
        }
    }
    
    enum Result {
        case success(KFCrossPlatformImage)
        case domainTrustRequired(String)
        case hardFailure(Error)
    }
    
    func loadImage(url: URL, withHttpAuthHeader: Bool, completion: ((_ image: Result) -> Void?)?) {
        
        print("loadImage called: \(url), \(withHttpAuthHeader)")
        let _retry = DelayRetryStrategy(maxRetryCount: 3, retryInterval: .seconds(3))
        var options: KingfisherOptionsInfo = []; // .retryStrategy(retry)
        
        // Check if domain is trusted, or auth has been requested
        let is_http_auth_domain = isDomainTrusted(url.host!)
        
        if withHttpAuthHeader && !isDomainTrusted(url.host!) {
            completion!(.domainTrustRequired(url.host!))
            return
        }
        
        let use_nostr_http_auth = withHttpAuthHeader || is_http_auth_domain
        
        if use_nostr_http_auth {
            let authModifier = getRequestModifier(url: url);
            options += [.requestModifier(authModifier)]
        }
        
        KingfisherManager.shared.retrieveImage(with: url, options: options) { result in
            switch result {
            case .success(let value):
                print("Successful Image Nostr HTTP AUTH \(url)")
                completion!(.success(value.image))
                return
            case .failure(let error):
                print("Error: Failed to fetch image with auth \(String(describing: error.failureReason))")
            
                // Check if we already tried using Nostr HTTP Auth - if we did, likely no point trying again
                if !use_nostr_http_auth {
                    print("!use_nostr_http_auth")
                    if !error.isInvalidResponseStatusCode(401) && !error.isInvalidResponseStatusCode(402) {
                        
                        print("Error, but wasn't !401 && !402 - so we can't handle it")
                        // It wasn't 401 Unauthorized or 402 Payment Required
                        completion!(.hardFailure(error))
                        return
                    }
                    
                    // Check the headers to see if Nostr HTTP AUTH is supported
                    if case let .responseError(.invalidHTTPStatusCode(response)) = error {
                    
                        if self.testNostHttpAuthHeader(headers: response.allHeaderFields as NSDictionary) {
                            
                            // We have found a header match, so we can retry with auth
                            print("NostHttpAuthHeader match - retrying request with auth header")
                            
                            // If we match on the auth header, but don't yet trust this domain, use completion handler to let the UI show this
                            if !self.isDomainTrusted(url.host!) {
                                completion!(.domainTrustRequired(url.host!))
                                return
                            }
                            
                            self.loadImage(url: url, withHttpAuthHeader: true, completion: completion)
                        }
                    }
                }
            }
        }
    }
}
