//
//  Custom.swift
//  r2-navigator-swift
//
//  Created by Max Wilhelm on 26/10/2019.
//
//  Copyright 2019 Readium Foundation. All rights reserved.
//  Use of this source code is governed by a BSD-style license which is detailed
//  in the LICENSE file present in the project repository where this source code is maintained.
//

import Foundation
import R2Shared
import WebKit

/*
 To make these customizations work it is necessary to mark certain methods in
 EPUBNavigatorViewController with @objc as they need to be overriden here. See which here:
 
 @objc func spreadViewWillAnimate(_ spreadView: EPUBSpreadView)
 @objc func spreadViewDidAnimate(_ spreadView: EPUBSpreadView)
 @objc func spreadView(_ spreadView: EPUBSpreadView, didTapAt point: CGPoint)
 @objc func spreadView(_ spreadView: EPUBSpreadView, didTapOnExternalURL url: URL)
 @objc func spreadView(_ spreadView: EPUBSpreadView, didTapOnInternalLink href: String)
 @objc func spreadViewPagesDidChange(_ spreadView: EPUBSpreadView) {
 
 To observe when conten is loaded into a view it is necessary to mark following variable
 in EPUBSpreadView with @objc dynamic:
 
 @objc dynamic private(set) var spreadLoaded = false
 
 Fix a bug:
 let viewport = "<meta name=\"viewport\" content=\"width=device-width, height=device-height, initial-scale=1.0, shrink-to-fit=no\"/>\n"
 
 Adding custom script in EpubSpreadView handling highlighting;
 WKUserScript(source: EPUBSpreadView.loadScript(named: "custom"), injectionTime: .atDocumentEnd, forMainFrameOnly: false) // Custom
 
 */

public protocol CustomNavigatorDelegate {
    // Custom
    func navigator(_ navigator: Navigator, presentInternalLink link: Link)
    func navigator(_ navigator: Navigator, locatorDidChange locator: CustomLocator)
}

public struct CustomLocator {
    public var locator: Locator
    public var progression: Double
    public var nextProgression: Double
    public init(locator: Locator, progression: Double, nextProgression: Double) {
        self.locator = locator
        self.progression = progression
        self.nextProgression = nextProgression
    }
}

public struct Annotation {
    public var startCfi: String
    public var endCfi: String
    public init(startCfi: String, endCfi: String) {
        self.startCfi = startCfi
        self.endCfi = endCfi
    }
}

public class CustomEPUBNavigatorViewController: EPUBNavigatorViewController {
    public var customDelegate: CustomNavigatorDelegate?
    public var totalPositions: Double = 0
    public var progressionDelta: Double = 0
    public var progression: Double = 0
    public var nextProgression: Double = 0
    public var totalProgression: Double = 0
    public var totalNextProgression: Double = 0
    
    private var publication: Publication
    private var observerContext = 0
    private var token: NSKeyValueObservation?
    private let customScript = EPUBSpreadView.loadScript(named: "custom")
    private var spreadView: EPUBSpreadView? {
        didSet {
            if let spreadView = self.spreadView {
                self.spreadLoaded = spreadView.spreadLoaded
                token = spreadView.observe(\.spreadLoaded, options: [.new, .old]) { [weak self] object, change in
                    self?.spreadLoaded = object.spreadLoaded
                }
            }
        }
    }
    private var spreadLoaded = false {
        didSet {
            if self.spreadLoaded {
                // Debounce: wait until the user stops typing to send search requests
                NSObject.cancelPreviousPerformRequests(withTarget: self)
                perform(#selector(update), with: nil, afterDelay: 0.05)
            }
        }
    }
    
    // MARK: - Life Cycle
    
    override public init(publication: Publication, license: DRMLicense? = nil, initialLocation: Locator? = nil, resourcesServer: ResourcesServer, config: Configuration = .init()) {
        self.publication = publication
        super.init(publication: publication, license: license, initialLocation: initialLocation, resourcesServer: resourcesServer, config: config)
    }
    
    // MARK: - Helpers
    
    @objc private func update() {
        if let spreadView = self.spreadView, spreadView.scrollView.contentSize != .zero {
            if spreadView.isScrollEnabled {
                let insetTop = spreadView.scrollView.contentInset.top
                let insetBottom = spreadView.scrollView.contentInset.bottom
                let screenHeight = spreadView.frame.size.height
                let scrollHeight = spreadView.scrollView.contentSize.height + insetTop + insetBottom
                let y = spreadView.scrollView.contentOffset.y + insetTop
                self.progressionDelta = Double(screenHeight / scrollHeight)
                self.progression = Double(y / scrollHeight)
                self.nextProgression = self.progression + self.progressionDelta
                self.totalPositions = 1/self.progressionDelta
            } else {
                let screenWidth = spreadView.webView.frame.size.width
                let scrollWidth = spreadView.webView.scrollView.contentSize.width
                let x = spreadView.webView.scrollView.contentOffset.x
                self.progressionDelta = Double(screenWidth / scrollWidth)
                self.progression = Double(x / scrollWidth)
                self.nextProgression = self.progression + self.progressionDelta
                self.totalPositions = 1/self.progressionDelta
            }

            let href = spreadView.spread.leading.href
            let length = publication.positionListByResource[href]?.count ?? 0
            let first = (publication.positionListByResource[href]?.first?.locations.position ?? 1) - 1
            self.totalProgression = Double(length) * progression + Double(first)
            self.totalNextProgression = Double(length) * nextProgression + Double(first)
            let locator = CustomLocator(locator: self.currentLocation!, progression: self.totalProgression, nextProgression: self.totalNextProgression)
            self.customDelegate?.navigator(self, locatorDidChange: locator)
        }
    }
    
    // MARK: - Public Setters
    
    public func removeAnnotations() {
        if let spreadView = self.spreadView {
            spreadView.webView.evaluateJavaScript("removeHighlights()") { result, error in
                print(result, error)
            }
        }
    }

    public func addAnnotation(annotation: Annotation) {
        if let spreadView = self.spreadView {
            let highlight = "{\"start\": \"\(annotation.startCfi)\", \"end\": \"\(annotation.endCfi)\"}"
            spreadView.webView.evaluateJavaScript("placeHighlight(\(highlight))") { result, error in
                print(result, error)
            }
        }
    }

    public func addAnnotations(annotations: [Annotation]) {
        self.removeAnnotations()
        for annotation in annotations {
            self.addAnnotation(annotation: annotation)
        }
    }
    
    // MARK: - Overrides
    
    override func spreadView(_ spreadView: EPUBSpreadView, didTapOnInternalLink href: String) {
        self.customDelegate?.navigator(self, presentInternalLink: Link(href: href))
    }
    
    // Updates on page change inside chapter
    override func spreadViewPagesDidChange(_ spreadView: EPUBSpreadView) {
        super.spreadViewPagesDidChange(spreadView)
        self.spreadLoaded = spreadView.spreadLoaded
    }
    
    override func spreadViewWillAnimate(_ spreadView: EPUBSpreadView) {
        super.spreadViewWillAnimate(spreadView)
    }
    
    override func spreadViewDidAnimate(_ spreadView: EPUBSpreadView) {
        super.spreadViewDidAnimate(spreadView)
    }
    
    // Updates on chapter change
    override func paginationViewDidUpdateViews(_ paginationView: PaginationView) {
        super.paginationViewDidUpdateViews(paginationView)
        guard let spreadView = paginationView.currentView as? EPUBSpreadView else { return }
        self.spreadView = spreadView
    }
}
