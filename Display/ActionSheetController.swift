import Foundation

open class ActionSheetController: ViewController {
    private var actionSheetNode: ActionSheetControllerNode {
        return self.displayNode as! ActionSheetControllerNode
    }
    
    private let theme: ActionSheetControllerTheme
    
    private var groups: [ActionSheetItemGroup] = []
    
    private var isDismissed: Bool = false
    
    public init(theme: ActionSheetControllerTheme) {
        self.theme = theme
        
        super.init(navigationBarPresentationData: nil)
    }
    
    required public init(coder aDecoder: NSCoder) {
        fatalError("init(coder:) has not been implemented")
    }
    
    public func dismissAnimated() {
        if !self.isDismissed {
            self.isDismissed = true
            self.actionSheetNode.animateOut()
        }
    }
    
    open override func loadDisplayNode() {
        self.displayNode = ActionSheetControllerNode(theme: self.theme)
        self.displayNodeDidLoad()
        
        self.actionSheetNode.dismiss = { [weak self] in
            self?.presentingViewController?.dismiss(animated: false)
        }
        
        self.actionSheetNode.setGroups(self.groups)
    }
    
    override open func containerLayoutUpdated(_ layout: ContainerViewLayout, transition: ContainedViewLayoutTransition) {
        super.containerLayoutUpdated(layout, transition: transition)
        
        self.actionSheetNode.containerLayoutUpdated(layout, transition: transition)
    }
    
    open override func viewWillAppear(_ animated: Bool) {
        super.viewWillAppear(animated)
        
        self.actionSheetNode.animateIn()
    }
    
    public func setItemGroups(_ groups: [ActionSheetItemGroup]) {
        self.groups = groups
        if self.isViewLoaded {
            self.actionSheetNode.setGroups(groups)
        }
    }
    
    public func updateItem(groupIndex: Int, itemIndex: Int, _ f: (ActionSheetItem) -> ActionSheetItem) {
        if self.isViewLoaded {
            self.actionSheetNode.updateItem(groupIndex: groupIndex, itemIndex: itemIndex, f)
        }
    }
}
