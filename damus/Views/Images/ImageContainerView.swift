//
//  ImageContainerView.swift
//  damus
//
//  Created by William Casarin on 2023-03-23.
//

import SwiftUI
import Kingfisher

func process_blurhash2(blurhash: String, size: CGSize?) -> UIImage? {
    let size = get_blurhash_size(img_size: size ?? CGSize(width: 100.0, height: 100.0))
    guard let img = UIImage.init(blurHash: blurhash, size: size) else {
        let noimg: UIImage? = nil
        return noimg
    }
    
    return img
}

    struct ImageContainerView: View {
        @State private var image: UIImage?
        @State private var showShareSheet = false
        @State var allowHttpAuthDomainRequired: String? = nil
        
        let state: DamusState
        
        init(state: DamusState, url: URL, disable_animation: Bool) {
            self.state = state
            self.url = url
            self.disable_animation = disable_animation
        }
        
        let url: URL
        let disable_animation: Bool
                
        var body: some View {
            ZStack {
                VStack {
                    VStack {
                        if (self.allowHttpAuthDomainRequired != nil) {
                            Text("Allow \(self.allowHttpAuthDomainRequired!) for Nostr HTTP Auth?")
                            HStack {
                                // Add domain with no expiry
                                Button(action: {
                                    state.http_auth_manager.addDomain(url.host!, expiration: nil)
                                    // Now need to trigger image reload
                                    state.http_auth_manager.loadImage(url: self.url, withHttpAuthHeader: true, completion: { [self] result in
                                        switch result {
                                        case .success(let image):
                                            DispatchQueue.main.async {
                                                self.image = image
                                            }
                                        case .domainTrustRequired(let domain):
                                            self.allowHttpAuthDomainRequired = domain
                                        case .hardFailure(let error):
                                            print("Hard Failure for image load: \(error.localizedDescription)")
                                        }
                                    })
                                }) {
                                    Text("Always")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.blue)
                                        .cornerRadius(10)
                                }
                                Button(action: {
                                    // Add domain with 24 hour expiry
                                    let currentDate = Date()
                                    let futureDate = currentDate.addingTimeInterval(24 * 60 * 60) // Adding 24 hours (24 hours * 60 minutes * 60 seconds)
                                    state.http_auth_manager.addDomain(url.host!, expiration: futureDate)
                                    // Now need to trigger image reload
                                    state.http_auth_manager.loadImage(url: self.url, withHttpAuthHeader: true, completion: { [self] result in
                                        switch result {
                                        case .success(let image):
                                            DispatchQueue.main.async {
                                                self.image = image
                                            }
                                        case .domainTrustRequired(let domain):
                                            self.allowHttpAuthDomainRequired = domain
                                        case .hardFailure(let error):
                                            print("Hard Failure for image load: \(error.localizedDescription)")
                                        }
                                    })
                                }) {
                                    Text("24 Hours")
                                        .font(.headline)
                                        .foregroundColor(.white)
                                        .padding()
                                        .background(Color.cyan)
                                        .cornerRadius(10)
                                }
                            }
                        }
                    }
                }
                
                VStack {
                    if let image = image {
                        Image(uiImage: image)
                            .resizable()
                            .scaledToFit()
                            .modifier(ImageContextMenuModifier(url: url, image: image, showShareSheet: $showShareSheet))
                            .sheet(isPresented: $showShareSheet) {
                                ShareSheet(activityItems: [url])
                            }
                    } else if (self.allowHttpAuthDomainRequired == nil) {
                        ProgressView()
                    }
                }
                .onAppear {
                    // Clear the Kingfisher image cache
                    // TODO: ONLY FOR TESTING!!!
                    KingfisherManager.shared.cache.clearMemoryCache()
                    KingfisherManager.shared.cache.clearDiskCache()
                    KingfisherManager.shared.cache.cleanExpiredDiskCache()
                    
                    state.http_auth_manager.loadImage(url: self.url, withHttpAuthHeader: false, completion: { [self] result in
                        switch result {
                        case .success(let image):
                            DispatchQueue.main.async {
                                self.image = image
                            }
                        case .domainTrustRequired(let domain):
                            self.allowHttpAuthDomainRequired = domain
                        case .hardFailure(let error):
                            print("Hard Failure for image load: \(error.localizedDescription)")
                        }
                    })
                }
            }
        }

    }

struct ImageContainerView_Previews: PreviewProvider {
    static var previews: some View {
        let test_image_url = URL(string: "https://cdn.wako.ws/public/AUTHIMAGE.jpg")!
        ImageContainerView(state: test_damus_state(), url: test_image_url, disable_animation: false)
    }
}
