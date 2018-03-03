import Foundation
import UIKit
import SwiftSignalKit

private func traceDeceleratingScrollView(_ view: UIView, at point: CGPoint) -> Bool {
    if view.bounds.contains(point), let view = view as? UIScrollView, view.isDecelerating {
        return true
    }
    for subview in view.subviews {
        let subviewPoint = view.convert(point, to: subview)
        if traceDeceleratingScrollView(subview, at: subviewPoint) {
            return true
        }
    }
    return false
}

public final class PeekControllerGestureRecognizer: UIPanGestureRecognizer {
    private let contentAtPoint: (CGPoint) -> Signal<(ASDisplayNode, PeekControllerContent)?, NoError>?
    private let present: (PeekControllerContent, ASDisplayNode) -> PeekController?
    private let updateContent: (PeekControllerContent?) -> Void
    private let activateBySingleTap: Bool
    
    private var tapLocation: CGPoint?
    private var longTapTimer: SwiftSignalKit.Timer?
    private var pressTimer: SwiftSignalKit.Timer?
    
    private let candidateContentDisposable = MetaDisposable()
    private var candidateContent: (ASDisplayNode, PeekControllerContent)? {
        didSet {
            self.updateContent(self.candidateContent?.1)
        }
    }
    
    private var menuActivation: PeerkControllerMenuActivation?
    private weak var presentedController: PeekController?
    
    public init(contentAtPoint: @escaping (CGPoint) -> Signal<(ASDisplayNode, PeekControllerContent)?, NoError>?, present: @escaping (PeekControllerContent, ASDisplayNode) -> PeekController?, updateContent: @escaping (PeekControllerContent?) -> Void = { _ in }, activateBySingleTap: Bool = false) {
        self.contentAtPoint = contentAtPoint
        self.present = present
        self.updateContent = updateContent
        self.activateBySingleTap = activateBySingleTap
        
        super.init(target: nil, action: nil)
    }
    
    deinit {
        self.longTapTimer?.invalidate()
        self.pressTimer?.invalidate()
        self.candidateContentDisposable.dispose()
    }
    
    private func startLongTapTimer() {
        self.longTapTimer?.invalidate()
        let longTapTimer = SwiftSignalKit.Timer(timeout: 0.4, repeat: false, completion: { [weak self] in
            self?.longTapTimerFired()
        }, queue: Queue.mainQueue())
        self.longTapTimer = longTapTimer
        longTapTimer.start()
    }
    
    private func startPressTimer() {
        self.pressTimer?.invalidate()
        let pressTimer = SwiftSignalKit.Timer(timeout: 1.0, repeat: false, completion: { [weak self] in
            self?.pressTimerFired()
        }, queue: Queue.mainQueue())
        self.pressTimer = pressTimer
        pressTimer.start()
    }
    
    private func stopLongTapTimer() {
        self.longTapTimer?.invalidate()
        self.longTapTimer = nil
    }
    
    private func stopPressTimer() {
        self.pressTimer?.invalidate()
        self.pressTimer = nil
    }
    
    override public func reset() {
        super.reset()
        
        self.stopLongTapTimer()
        self.stopPressTimer()
        self.tapLocation = nil
        self.candidateContent = nil
        self.menuActivation = nil
        self.presentedController = nil
    }
    
    private func longTapTimerFired() {
        guard let _ = self.tapLocation, let (sourceNode, content) = self.candidateContent else {
            return
        }
        
        self.state = .began
        
        if let presentedController = self.present(content, sourceNode) {
            self.menuActivation = content.menuActivation()
            self.presentedController = presentedController
            
            switch content.menuActivation() {
                case .drag:
                    break
                case .press:
                    if #available(iOSApplicationExtension 9.0, *) {
                        if presentedController.traitCollection.forceTouchCapability != .available {
                            self.startPressTimer()
                        }
                    } else {
                        self.startPressTimer()
                    }
            }
        }
    }
    
    private func pressTimerFired() {
        if let _ = self.tapLocation, let menuActivation = self.menuActivation, case .press = menuActivation {
            if let presentedController = self.presentedController {
                if presentedController.isNodeLoaded {
                    (presentedController.displayNode as? PeekControllerNode)?.activateMenu()
                }
                self.menuActivation = nil
                self.presentedController = nil
                self.state = .ended
            }
        }
    }
    
    override public func touchesBegan(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesBegan(touches, with: event)
        
        if let view = self.view, let tapLocation = touches.first?.location(in: view) {
            if traceDeceleratingScrollView(view, at: tapLocation) {
                self.candidateContent = nil
                self.state = .failed
            } else {
                if let contentSignal = self.contentAtPoint(tapLocation) {
                    self.candidateContentDisposable.set((contentSignal |> deliverOnMainQueue).start(next: { [weak self] result in
                        if let strongSelf = self {
                            switch strongSelf.state {
                                case .possible, .changed:
                                    if let (sourceNode, content) = result {
                                        strongSelf.tapLocation = tapLocation
                                        strongSelf.candidateContent = (sourceNode, content)
                                        strongSelf.menuActivation = content.menuActivation()
                                        strongSelf.startLongTapTimer()
                                    } else {
                                        strongSelf.state = .failed
                                    }
                                default:
                                    break
                            }
                        }
                    }))
                } else {
                    self.state = .failed
                }
            }
        }
    }
    
    override public func touchesEnded(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesEnded(touches, with: event)
        
        if self.activateBySingleTap, candidateContent != nil {
            self.longTapTimerFired()
            self.pressTimerFired()
        } else {
            let velocity = self.velocity(in: self.view)
            
            if let presentedController = self.presentedController, presentedController.isNodeLoaded {
                (presentedController.displayNode as? PeekControllerNode)?.endDraggingWithVelocity(velocity.y)
                self.presentedController = nil
                self.menuActivation = nil
            }
            
            self.tapLocation = nil
            self.candidateContent = nil
            self.state = .failed
        }
    }
    
    override public func touchesCancelled(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesCancelled(touches, with: event)
        
        self.tapLocation = nil
        self.candidateContent = nil
        self.state = .failed
        
        if let presentedController = self.presentedController {
            self.menuActivation = nil
            self.presentedController = nil
            presentedController.dismiss()
        }
    }
    
    override public func touchesMoved(_ touches: Set<UITouch>, with event: UIEvent) {
        super.touchesMoved(touches, with: event)
        
        if let touch = touches.first, let initialTapLocation = self.tapLocation, let menuActivation = self.menuActivation {
            let touchLocation = touch.location(in: self.view)
            if let presentedController = self.presentedController {
                switch menuActivation {
                    case .drag:
                        var offset = touchLocation.y - initialTapLocation.y
                        let delta = abs(offset)
                        let factor: CGFloat = 60.0
                        offset = (-((1.0 - (1.0 / (((delta) * 0.55 / (factor)) + 1.0))) * factor)) * (offset < 0.0 ? 1.0 : -1.0)
                        
                        if presentedController.isNodeLoaded {
                            (presentedController.displayNode as? PeekControllerNode)?.applyDraggingOffset(offset)
                        }
                    case .press:
                        if #available(iOSApplicationExtension 9.0, *) {
                            if touch.force >= 2.5 {
                                if presentedController.isNodeLoaded {
                                    (presentedController.displayNode as? PeekControllerNode)?.activateMenu()
                                    self.menuActivation = nil
                                    self.presentedController = nil
                                    self.state = .ended
                                }
                            }
                        }
                        
                        if self.pressTimer != nil {
                            let dX = touchLocation.x - initialTapLocation.x
                            let dY = touchLocation.y - initialTapLocation.y
                            
                            if dX * dX + dY * dY > 3.0 * 3.0 {
                                self.startPressTimer()
                            }
                        }
                    
                        if self.presentedController != nil {
                            self.checkCandidateContent(at: touchLocation)
                        }
                }
            } else {
                let dX = touchLocation.x - initialTapLocation.x
                let dY = touchLocation.y - initialTapLocation.y
                
                if dX * dX + dY * dY > 3.0 * 3.0 {
                    self.stopLongTapTimer()
                    self.tapLocation = nil
                    self.candidateContent = nil
                    self.state = .failed
                }
            }
        }
    }
    
    private func checkCandidateContent(at touchLocation: CGPoint) {
        if let contentSignal = self.contentAtPoint(touchLocation) {
            self.candidateContentDisposable.set((contentSignal |> deliverOnMainQueue).start(next: { [weak self] result in
                if let strongSelf = self {
                    switch strongSelf.state {
                        case .possible, .changed:
                            if let (sourceNode, content) = result, let currentContent = strongSelf.candidateContent, !currentContent.1.isEqual(to: content) {
                                strongSelf.tapLocation = touchLocation
                                strongSelf.candidateContent = (sourceNode, content)
                                strongSelf.menuActivation = content.menuActivation()
                                if let presentedController = strongSelf.presentedController, presentedController.isNodeLoaded {
                                    presentedController.sourceNode = {
                                        return sourceNode
                                    }
                                    (presentedController.displayNode as? PeekControllerNode)?.updateContent(content: content)
                                } else {
                                    strongSelf.startLongTapTimer()
                                }
                            } else if strongSelf.presentedController == nil {
                                strongSelf.state = .failed
                            }
                        default:
                            break
                    }
                }
            }))
        } else if self.presentedController == nil {
            self.state = .failed
        }
    }
}