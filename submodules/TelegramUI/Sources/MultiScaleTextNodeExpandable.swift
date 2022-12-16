// Temporary and safe
import Foundation
import UIKit
import AsyncDisplayKit
import Display

// Currently implementing just toggled expansion (1 line, multiline)
// TODO: move transition and layout to separate Text class (substituting ImmediateTextNode) (to reuse for ChatHeader)
final class MultiScaleTextStateNodeExpandable: ASDisplayNode {
    var textContainerNode: ASDisplayNode {
        textContainer
    }
    var currentLayout: MultiScaleTextLayoutExpandable?
    
    var maxNumberOfLines: Int = 2
    
    var textSubnodes: [ImmediateTextNode] = []
    let textContainer: ASDisplayNode = ASDisplayNode()
    
    // Convenience, remove
    var prevSize: CGSize?
    var prevString: NSAttributedString?
    var wasExpanded = false
    var lastProgress: CGFloat = 0
    
    private var prevLines: [LayoutLine]?
    
    override init() {
        super.init()
        
        self.addSubnode(textContainer)
    }
    /// Update position
    func updateTextFrame(_ frame: CGRect) {
        textContainerNode.frame = frame
    }
    
    /// UIFont.systemFont only, for other fonts use CoreText with variationAxis
    func reweightString(string: NSAttributedString, weight: CGFloat) -> NSAttributedString {
        let reweightString = NSMutableAttributedString(attributedString: string)
//        reweightString.addAttribute(.kern, value: 0 + 1 * weight, range: NSRange(location: 0, length: reweightString.length))
        
        return reweightString
    }

    // Just going straight with expansion
    func updateExpansion(progress: CGFloat, transition: ContainedViewLayoutTransition, forcedAlignment: NSTextAlignment?, shouldReweight: Bool) {
        guard var attrString = prevString, let singleLineInfo = getLinesArrayOfString(attrString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).first, let prevLines else { return }
        let isAvatarExpanded = forcedAlignment == .left
        
        var totalSize = prevSize! // dummyNode.updateLayout(prevSize!)
        totalSize.width += 16
        var offsetY: CGFloat = 0
        // Only from expanded state
        // self.wasExpanded == true
        
        let expandedWeight: CGFloat = isAvatarExpanded ? UIFont.Weight.semibold.rawValue : UIFont.Weight.regular.rawValue
        let collapsedWeight: CGFloat = UIFont.Weight.semibold.rawValue
        let newWeight = expandedWeight * progress + collapsedWeight * (1 - progress)
        if shouldReweight {
            attrString = reweightString(string: attrString, weight: newWeight)
        }
        for (index, lineInfo) in prevLines.enumerated() {
            // TEST: dynamic weight
            let reweightString = shouldReweight ? reweightString(string: lineInfo.attributedString, weight: newWeight) : lineInfo.attributedString
            
            let lineTextNode = textSubnodes[index]
            
            lineTextNode.attributedText = reweightString
            _ = lineTextNode.updateLayout(.init(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
            let actualSize = lineTextNode.frame // (?).updateLayout(...)
//            lineTextNode.backgroundColor = .green
            let startIndexOfSubstring = lineInfo.lineRange.location
            var secondaryOffset: CGFloat = 0.0
            var offsetX = floor(CTLineGetOffsetForStringIndex(singleLineInfo.ctLine, startIndexOfSubstring, &secondaryOffset))
            secondaryOffset = floor(secondaryOffset)
            if lineInfo.isRTL {
                offsetX -= actualSize.width
            }
            let collapsedFrame = CGRect(x: offsetX, y: 0, width: actualSize.width, height: actualSize.height)
            
            // Currently centered alignment only
            let containerBounds = CGRect(x: 0, y: 0, width: totalSize.width, height: totalSize.height)
            
            let expandedFrame = expandedFrame(lineSize: actualSize.size, offsetY: offsetY, containerBounds: containerBounds, alignment: forcedAlignment ?? (attrString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, isRTL: lineInfo.isRTL)
            let yProgress = sqrt(1 - (progress - 1) * (progress - 1))
            let xProgress = progress// 1 - sqrt(1 - progress * progress)
            let currentProgressFrame = CGRect(
                x: expandedFrame.origin.x * xProgress - collapsedFrame.origin.x * (xProgress - 1),
                y: expandedFrame.origin.y * yProgress - collapsedFrame.origin.y * (yProgress - 1),
                width: expandedFrame.width * progress - collapsedFrame.width * (progress - 1),
                height: expandedFrame.height * progress - collapsedFrame.height * (progress - 1)
            )
            
            transition.updateFrame(node: lineTextNode, frame: currentProgressFrame)
            offsetY += expandedFrame.height + 0
        }
    }
    
    private func expandedFrame(lineSize actualSize: CGSize, offsetY: CGFloat, containerBounds: CGRect, alignment: NSTextAlignment?, isRTL: Bool) -> CGRect {
        let lineOriginX: CGFloat
        switch alignment {
        case .left:
            if isRTL {
                lineOriginX = containerBounds.width - actualSize.width
            } else {
                lineOriginX = 0
            }
        case .right:
            if isRTL {
                lineOriginX = 0
            } else {
                lineOriginX = containerBounds.width - actualSize.width
            }
        case .center, .none:
            lineOriginX = (containerBounds.width - actualSize.width) / 2
        case .justified:
            lineOriginX = 0
        case .natural:
            if isRTL {
                lineOriginX = containerBounds.width - actualSize.width
            } else {
                lineOriginX = 0
            }
        default:
            if isRTL {
                lineOriginX = containerBounds.width - actualSize.width
            } else {
                lineOriginX = 0
            }
        }
        
        return CGRect(x: lineOriginX, y: offsetY, width: actualSize.width, height: actualSize.height)
    }
    
    let singleLineFadeMask: CALayer = CALayer()
    
    /// Currently only toggling between 1 and multiple number of lines (expanded/not expanded)
    func update(
        string: NSAttributedString,
        constrainedSize: CGSize,
        transition: ContainedViewLayoutTransition,
        isExpanded: Bool
    ) -> CGSize {
        guard !string.string.replacingOccurrences(of: " ", with: "").isEmpty else { return .zero }
        
        let shouldReset: Bool
        
        if string != prevString || constrainedSize != prevSize {
            shouldReset = true
        } else {
            shouldReset = false
        }
        
        if shouldReset {
            textSubnodes.removeAll()
            prevString = nil
            prevSize = nil
            prevLines = nil
            lastProgress = 0
//            currentLayout = nil
            textContainer.subnodes?.forEach { $0.removeFromSupernode() }
//            wasExpanded = false
        }
        
        let lines: [LayoutLine]
        if isExpanded {
            // Temporary (setting initial string)
            if textSubnodes.isEmpty {
                _ = update(string: string, constrainedSize: constrainedSize, transition: .immediate, isExpanded: false)
            }
            lines = getLinesArrayOfString(string, textSize: constrainedSize)
        } else {
            // Also assuming there are no newlines in text (otherwise remove preemtively)
            lines = getLinesArrayOfString(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        }
        
//        let stringChanged = prevString != string
//        guard !stringChanged else {
            // Simple set new string
            
//        }
        // TODO: Check diff
        // Currently only diffing by size
//        let linesLayout = TextNode.calculateLayout(
//            attributedString: string,
//            minimumNumberOfLines: 1,
//            maximumNumberOfLines: maxNumberOfLines,
//            truncationType: .end,
//            backgroundColor: nil,
//            constrainedSize: constrainedSize,
//            alignment: .center,
//            verticalAlignment: .middle,
//            lineSpacingFactor: 1.0,
//            cutout: nil,
//            insets: .zero,
//            lineColor: nil,
//            textShadowColor: nil,
//            textStroke: nil,
//            displaySpoilers: false,
//            displayEmbeddedItemsUnderSpoilers: false
//        )
        var totalSize = CGSize()
        // Temporary:
        let dummyNode = ImmediateTextNode()
        dummyNode.attributedText = string
        dummyNode.maximumNumberOfLines = 10
        totalSize = dummyNode.updateLayout(constrainedSize)
        // Temporary
        var singleLineTextnode: ASDisplayNode?
        if !wasExpanded && isExpanded {
            singleLineTextnode = textContainer.subnodes?.first
            singleLineTextnode?.removeFromSupernode()
            textSubnodes = []
            
            singleLineFadeMask.frame.size.height = totalSize.height
        } else if !isExpanded {
            transition.updateAlpha(layer: singleLineFadeMask, alpha: 1, completion: nil)
            let dummyNode = ImmediateTextNode()
            dummyNode.attributedText = string
            dummyNode.maximumNumberOfLines = 1
            let singleLineSize = dummyNode.updateLayout(.init(width: 100000, height: 100000))
            singleLineFadeMask.frame = .init(origin: .zero, size: .init(width: max(180, singleLineSize.width), height: singleLineSize.height))
//            self.textContainerNode.layer.mask = singleLineFadeMask
        }
        do {
            singleLineFadeMask.sublayers?.forEach { $0.removeFromSuperlayer() }
            
            let gradientRadius: CGFloat = 50
            let opaqueArea = CALayer()
            opaqueArea.backgroundColor = UIColor.black.cgColor
            opaqueArea.frame = CGRect(x: 0, y: 0, width: singleLineFadeMask.bounds.width - gradientRadius, height: singleLineFadeMask.bounds.height)
            singleLineFadeMask.addSublayer(opaqueArea)
            
            let gradient = CAGradientLayer()
            gradient.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
            gradient.startPoint = .init(x: 0, y: 0.5)
            gradient.endPoint = .init(x: 1, y: 0.5)
            gradient.frame = CGRect(x: singleLineFadeMask.bounds.width - gradientRadius, y: 0, width: gradientRadius, height: totalSize.height)
            singleLineFadeMask.addSublayer(gradient)
        }
        var offsetY: CGFloat = 0
        let lineSpacing: CGFloat = -4
        for line in lines {
            let lineTextNode = ImmediateTextNode()
            lineTextNode.attributedText = line.attributedString
            lineTextNode.displaysAsynchronously = false
            let actualSize = lineTextNode.updateLayout(line.frame.size)
            // String shouldn't change
            if let prevString = prevString, let prevSize = prevSize {
                // Place new lineTextNode at the current position
                // TODO: remove recalculation for previous (convenience)
                let prevLinesInfo = getLinesArrayOfString(prevString, textSize: prevSize)
                // Since implementing only binary expansion (for initial animation state)
                if !wasExpanded && isExpanded, let prevLineInfo = prevLinesInfo.first {
                    let prevCTLine = prevLineInfo.ctLine
                    
                    let startIndexOfSubstring = line.lineRange.location
                    var secondaryOffset: CGFloat = 0.0
                    let offsetX = floor(CTLineGetOffsetForStringIndex(prevCTLine, startIndexOfSubstring, &secondaryOffset))
                    secondaryOffset = floor(secondaryOffset)
                    // initial frame
                    lineTextNode.frame = CGRect(x: offsetX, y: 0, width: actualSize.width, height: actualSize.height)
                    
                    // Currently centered alignment only
                    let containerBounds = CGRect(x: 0, y: 0, width: totalSize.width, height: totalSize.height)
                    let expandedFrame = CGRect(x: (containerBounds.width - actualSize.width) / 2, y: offsetY, width: actualSize.width, height: actualSize.height)
                    textContainer.addSubnode(lineTextNode)
                    textSubnodes.append(lineTextNode)
                    transition.updateFrame(node: lineTextNode, frame: expandedFrame)
                    offsetY += actualSize.height + lineSpacing
                } else if wasExpanded && !isExpanded {
                    let singleLineCTLine = line.ctLine // Only one iteration (refactor)
                    // Animate previous text nodes transition into single line
                    textContainer.addSubnode(lineTextNode)
                    // for textSubnode in textSubnodes {
                    for (lineIndex, prevLine) in prevLinesInfo.enumerated() {
                        // Animate frame to single line
                        let startIndexOfSubstring = prevLine.lineRange.location
                        var secondaryOffset: CGFloat = 0.0
                        let offsetX = floor(CTLineGetOffsetForStringIndex(singleLineCTLine, startIndexOfSubstring, &secondaryOffset))
                        // Animate:
                        textSubnodes[lineIndex].frame.origin = CGPoint(x: offsetX, y: 0)
                        let subnode = textSubnodes[lineIndex]
                        // TODO: remove on completion
                        DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                            subnode.removeFromSupernode()
                        }
                    }
                } else if wasExpanded == isExpanded {
                    if !isExpanded {
                        lineTextNode.frame = bounds
                        // Temp
                        if textContainer.subnodes?.isEmpty == true {
                            textContainer.addSubnode(lineTextNode)
                        }
                    }
                } else {
                    assertionFailure()
                }
            } else {
                lineTextNode.frame = CGRect(origin: .zero, size: actualSize)
                textContainer.addSubnode(lineTextNode)
            }
        }
        if wasExpanded == isExpanded && isExpanded {
//           updateExpansion(progress: 1, transition: transition, forcedAlignment: <#T##NSTextAlignment?#>)
        }
        prevSize = totalSize
        prevString = string
        prevLines = lines
        wasExpanded = isExpanded
        return totalSize
    }
    
    private struct LayoutLine {
        let attributedString: NSAttributedString
        let isRTL: Bool
        let frame: CGRect
        let ctLine: CTLine
        let lineRange: NSRange
    }
    
    private func getLinesArrayOfString(_ attStr: NSAttributedString, textSize: CGSize) -> [LayoutLine] {
        var linesArray = [LayoutLine]()
        
        let frameSetter: CTFramesetter = CTFramesetterCreateWithAttributedString(attStr as CFAttributedString)
        let path: CGMutablePath = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: textSize.width, height: 100000), transform: .identity)
        let frame: CTFrame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, 0), path, nil)
        guard let lines = CTFrameGetLines(frame) as? [Any] else { return linesArray }
        // TODO: reuse logic from TextNode
        for line in lines {
            // TODO: remove trailing spaces
            let lineRef = line as! CTLine
            let lineRange: CFRange = CTLineGetStringRange(lineRef)
            let range = NSRange(location: lineRange.location, length: lineRange.length)
            let lineString = attStr.attributedSubstring(from: range)
            
            let lineOriginY: CGFloat = 0
            let headIndent: CGFloat = 0
            let fontLineHeight: CGFloat = 36
            let lineCutoutOffset: CGFloat = 0
            
            let lineConstrainedSizeWidth = textSize.width
            // TODO: use proper (as in TextNode) lineOriginY
            let lineWidth = min(lineConstrainedSizeWidth, ceil(CGFloat(CTLineGetTypographicBounds(lineRef, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(lineRef))))
            let lineFrame = CGRect(x: lineCutoutOffset + headIndent, y: lineOriginY, width: lineWidth, height: fontLineHeight)
            
            var isRTL = false
            let glyphRuns = CTLineGetGlyphRuns(lineRef) as NSArray
            if glyphRuns.count != 0 {
                let run = glyphRuns[0] as! CTRun
                if CTRunGetStatus(run).contains(CTRunStatus.rightToLeft) {
                    isRTL = true
                }
            }
            
            linesArray.append(LayoutLine(attributedString: lineString, isRTL: isRTL, frame: lineFrame, ctLine: lineRef, lineRange: range))
        }
        return linesArray
    }
}

final class MultiScaleTextStateExpandable {
    let attributedText: NSAttributedString
    let constrainedSize: CGSize
    
    init(attributedText: NSAttributedString, constrainedSize: CGSize) {
        self.attributedText = attributedText
        self.constrainedSize = constrainedSize
    }
}

struct MultiScaleTextLayoutExpandable {
    var size: CGSize
}

final class MultiScaleTextNodeExpandable: ASDisplayNode {
    var doTransitionBetweenWeight: Bool { false }
    
    private let stateNodes: [AnyHashable: MultiScaleTextStateNodeExpandable]
    
    init(stateKeys: [AnyHashable]) {
        self.stateNodes = Dictionary(stateKeys.map { ($0, MultiScaleTextStateNodeExpandable()) }, uniquingKeysWith: { lhs, _ in lhs })
        
        super.init()
        let order: [Int: Int] = [
            0: 0,
            2: 1,
            1: 2
        ]
        for (_, node) in self.stateNodes.sorted(by: { a, b in order[a.key as! Int]! < order[b.key as! Int]! }) {
            self.addSubnode(node)
        }
    }
    
    func stateNode(forKey key: AnyHashable) -> ASDisplayNode? {
        return self.stateNodes[key]?.textContainerNode
    }
    
    func updateExpansion(progress: CGFloat, transition: ContainedViewLayoutTransition) {
        isTransitioning = true
        let crossFadeDuration: Double
        if case let .animated(duration, _) = transition {
            crossFadeDuration = duration
        } else {
            crossFadeDuration = 0.5
        }
        
        let switchToNavTitleThreshold: CGFloat = doTransitionBetweenWeight ? 0.2 : -1
        
        for node in self.stateNodes {
            node.value.updateExpansion(progress: progress, transition: transition, forcedAlignment: lastAvatarStateIsExpanded ? .left : .center, shouldReweight: node.key as? Int == 0)
            if !lastAvatarStateIsExpanded {
                if progress < switchToNavTitleThreshold {
                    if node.key as? Int == 0 {
                        let altNode = self.stateNodes[2]!
                        if altNode.alpha == 0 {
                            altNode.alpha = 1
                            altNode.layer.animateAlpha(from: 0, to: 1, duration: crossFadeDuration)
                        }
                        
                        if node.value.alpha == 1 {
                            node.value.alpha = 0
                            node.value.layer.animateAlpha(from: 1, to: 0, duration: crossFadeDuration)
                        }
                    }
                } else {
                    if node.key as? Int == 0 {
                        let altNode = self.stateNodes[2]!
                        if altNode.alpha == 1 {
                            altNode.alpha = 0
                            altNode.layer.animateAlpha(from: 1, to: 0, duration: crossFadeDuration)
                        }
                        
                        if node.value.alpha == 0 {
                            node.value.alpha = 1
                            node.value.layer.animateAlpha(from: 0, to: 1, duration: crossFadeDuration)
                        }
                    }
                }
            } else {
                self.stateNodes[0]?.alpha = lastAvatarStateIsExpanded ? 0 : 1
                self.stateNodes[2]?.alpha = (1 - (self.stateNodes[0]?.alpha ?? 0))
            }
        }
    }
    var lastAvatarStateIsExpanded: Bool = false
    var isTransitioning: Bool = false
    
    func updateLayout(states: [AnyHashable: MultiScaleTextStateExpandable], mainState: AnyHashable, transition: ContainedViewLayoutTransition, isExpanded: Bool) -> [AnyHashable: MultiScaleTextLayoutExpandable] {
        assert(Set(states.keys) == Set(self.stateNodes.keys))
        assert(states[mainState] != nil)
        
        var result: [AnyHashable: MultiScaleTextLayoutExpandable] = [:]
        var mainLayout: MultiScaleTextLayoutExpandable?
        for (key, state) in states {
            if let node = self.stateNodes[key] {
                let nodeSize = node.update(string: state.attributedText, constrainedSize: state.constrainedSize, transition: transition, isExpanded: isExpanded)
                let nodeLayout = MultiScaleTextLayoutExpandable(size: nodeSize)
                if key == mainState {
                    mainLayout = nodeLayout
                }
                node.currentLayout = nodeLayout
                result[key] = nodeLayout
            }
        }
        if let mainLayout = mainLayout {
            let mainBounds = CGRect(origin: CGPoint(x: -mainLayout.size.width / 2.0, y: -mainLayout.size.height / 2.0), size: mainLayout.size)
            for (key, _) in states {
                if let node = self.stateNodes[key], let nodeLayout = result[key] {
                    node.updateTextFrame(CGRect(origin: CGPoint(x: mainBounds.minX, y: mainBounds.minY + floor((mainBounds.height - nodeLayout.size.height) / 2.0)), size: nodeLayout.size))
                }
            }
        }
        return result
    }
    // TODO: mask here
    func update(stateFractions: [AnyHashable: CGFloat], alpha: CGFloat = 1.0, alignment: NSTextAlignment, transition: ContainedViewLayoutTransition) {
        var fractionSum: CGFloat = 0.0
        for (_, fraction) in stateFractions {
            fractionSum += fraction
        }
        // TODO: moveisTransitioning
        let isAvatarExpanded = alignment == .left
        self.lastAvatarStateIsExpanded = isAvatarExpanded
        for (key, _) in stateFractions {
            if let node = self.stateNodes[key], let _ = node.currentLayout {
                if !transition.isAnimated {
//                    node.layer.removeAllAnimations()
                }
//                node.layer.opacity = 1
//                node.alpha = 1
                if !isTransitioning {
                    node.updateExpansion(progress: 1, transition: transition, forcedAlignment: alignment, shouldReweight: key as? Int == 0)
                }
//                transition.updateAlpha(node: node, alpha: fraction / fractionSum * alpha)
            }
        }
        if !isTransitioning {
            self.stateNodes[0]?.alpha = isAvatarExpanded ? 0 : 1
            self.stateNodes[2]?.alpha = (1 - self.stateNodes[0]!.alpha)
        }
    }
}
