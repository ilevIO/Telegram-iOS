import Foundation
import UIKit
import AsyncDisplayKit
import Display

enum PeerHeaderTitleState: Int {
    /// Normal
    case thin = 0
    /// Intersected by avatar
    case thinInverted = 3
    /// Covered by avatar
    case thic = 1
    /// Outside avatar
    case thicInverted = 2
}

final class ExpandableTextNode: ASDisplayNode {
    
}

final class ExpandablePeerTitleContainerNode: ASDisplayNode {
    var allAlignedBy: AnyHashable?
    var textSubnodes: [AnyHashable: ExpandablePeerTitleTextNode] = [:]
    var isTransitioning: Bool = false
    
    var trailingFadeIntensity: CGFloat = 0
    let trailingFadeMaskLayer = CALayer()
    
    var gradientFadeMask = CALayer()
    
    func update(strings: [AnyHashable: NSAttributedString], mainState: AnyHashable?, constrainedSize: CGSize, textExpansionFraction: CGFloat, isAvatarExpanded: Bool, needsExpansionLayoutUpdate: Bool, transition: ContainedViewLayoutTransition) -> [AnyHashable: MultiScaleTextLayout] {
        var commonExpandedLayout: ExpandablePeerTitleTextNode.ExpandableTextNodeLayout? = nil
        
        var mainLayout: MultiScaleTextLayout?
        var result: [AnyHashable: MultiScaleTextLayout] = [:]
        self.allAlignedBy = mainState
        
        if let allAlignedBy = mainState {
            commonExpandedLayout = textSubnodes[allAlignedBy]?.getExpandedLayout(string: strings[allAlignedBy]!, forcedAlignment: isAvatarExpanded ? .left : .center, constrainedSize: constrainedSize)
        }
        
        for (key, string) in strings {
            guard let node = textSubnodes[key], let layout = commonExpandedLayout ?? textSubnodes[key]?.getExpandedLayout(string: string, forcedAlignment: isAvatarExpanded ? .left : .center, constrainedSize: constrainedSize) else {
//                assertionFailure("check")
                continue
            }
            let size = node.updateIfNeeded(string: string, expandedLayout: layout, expansionFraction: textExpansionFraction, needsExpansionLayoutUpdate: needsExpansionLayoutUpdate, transition: transition)
            if key == mainState {
                mainLayout = MultiScaleTextLayout(size: size)
            }
            result[key] = MultiScaleTextLayout(size: size)
        }
        if let mainLayout = mainLayout {
            let mainBounds = CGRect(origin: CGPoint(x: -mainLayout.size.width / 2.0, y: -mainLayout.size.height / 2.0), size: mainLayout.size)
            for (key, _) in strings {
                if let node = self.textSubnodes[key], let nodeLayout = result[key] {
                    node.updateTextFrame(CGRect(origin: CGPoint(x: mainBounds.minX, y: mainBounds.minY + floor((mainBounds.height - nodeLayout.size.height) / 2.0)), size: nodeLayout.size))
                }
            }
        }
        
        if !isTransitioning {
            self.textSubnodes[PeerHeaderTitleState.thin]?.alpha = isAvatarExpanded ? 0 : 1
            self.textSubnodes[PeerHeaderTitleState.thinInverted]?.alpha = isAvatarExpanded ? 0 : 1
            self.textSubnodes[PeerHeaderTitleState.thic]?.alpha = (1 - self.textSubnodes[PeerHeaderTitleState.thin]!.alpha)
            self.textSubnodes[PeerHeaderTitleState.thicInverted]?.alpha = (1 - self.textSubnodes[PeerHeaderTitleState.thin]!.alpha)
        }
        
        return result
    }
    
    func updateFading(availableWidth: CGFloat, containerWidth: CGFloat, height: CGFloat) {
        gradientFadeMask.removeFromSuperlayer()
        gradientFadeMask = .init()
        // Pass fade side from AnimatedHeaderLabelNode
//            let fadeSide_isRight = true
//        let isRTL = false
        let solidMask = CALayer()
        solidMask.backgroundColor = UIColor.black.cgColor
        solidMask.frame = CGRect(x: 0, y: 0, width: availableWidth, height: height)
        
        gradientFadeMask.addSublayer(solidMask)
        
        let fadeRadius: CGFloat = 30
        let gradientLayer = CAGradientLayer()
        gradientLayer.frame = CGRect(x: availableWidth, y: 0, width: fadeRadius, height: height)
        gradientLayer.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
        gradientFadeMask.addSublayer(gradientLayer)
        gradientFadeMask.masksToBounds = false
        gradientFadeMask.frame = CGRect(x: -containerWidth / 2, y: -height / 2, width: availableWidth + fadeRadius, height: height)
        self.layer.mask = gradientFadeMask
    }
//
//    // Temporary convenience
//    static func initAsPeerHeaderTitle() -> ExpandableTextNodesContainer {
//        let container = ExpandableTextNodesContainer()
//        container.textSubnodes = [
//            PeerHeaderTitleState.thin.rawValue:
//        ]
//    }
    
    init(stateKeys: [AnyHashable], order: [AnyHashable: Int]?) {
        self.textSubnodes = Dictionary(stateKeys.map { ($0, ExpandablePeerTitleTextNode()) }, uniquingKeysWith: { lhs, _ in lhs })
        
        super.init()
        
        let orderedNodes: [ExpandablePeerTitleTextNode]
        if let order {
            orderedNodes = self.textSubnodes.sorted(by: { a, b in order[a.key] ?? -1 < order[b.key] ?? -1 }).map(\.value)
            //        let order: [Int: Int] = [
            //            0: 0,
            //            2: 1,
            //            1: 2
            //        ]
        } else {
            orderedNodes = self.textSubnodes.map(\.value)
        }
        for node in orderedNodes {
            self.addSubnode(node)
        }
    }
    
    func stateNode(forKey key: AnyHashable) -> ASDisplayNode? {
        return self.textSubnodes[key]?.textContainer
    }
}

final class ExpandablePeerTitleTextNode: ASDisplayNode {
    struct ExpandableTextNodeLayout: Equatable {
        let rangeToFrame: [NSRange: CGRect]
        let constrainedSize: CGSize
        let alignment: NSTextAlignment
//        let currentSize: CGSize
//        let expandedSize: CGSize
//        let collapsedSize: CGSize
    }
    var currentString: NSAttributedString?
    public var currentLayout: ExpandableTextNodeLayout?
    var currentExpansion: CGFloat?
    var currentConstrainedSize: CGSize?
    var ctLine: CTLine?
    var prevAlignment: NSTextAlignment?
    
    var textContainer: ASDisplayNode {
        textContainerNode
    }
    let textContainerNode = ASDisplayNode()
    var textFragmentsNodes: [ImmediateTextNode] = []
    
    var maxNumberOfLines: Int = 2
    
    override init() {
        super.init()
        
        self.addSubnode(textContainer)
    }
    
    /// Update position
    func updateTextFrame(_ frame: CGRect) {
        textContainerNode.frame = frame
    }
    
    func getExpandedLayout(string: NSAttributedString, forcedAlignment: NSTextAlignment?, constrainedSize: CGSize) -> ExpandableTextNodeLayout {
        var shouldRecalculate = false
        
        if currentString != string || constrainedSize != currentConstrainedSize {
            // In the future may also diff strings
            shouldRecalculate = true
        }
        
        if !shouldRecalculate, let currentLayout = self.currentLayout, prevAlignment == forcedAlignment {
            return currentLayout
        } else {
            let lines = getLinesArrayOfString(string, textSize: constrainedSize, maxNumberOfLines: self.maxNumberOfLines)
            
            var width: CGFloat = 0
            var height: CGFloat = 0
            for line in lines {
                width = max(width, min(line.frame.width, constrainedSize.width))
                height += line.frame.height
            }
            let totalSize = CGSize(width: width, height: height)
            let containerBounds = CGRect(x: 0, y: 0, width: totalSize.width, height: totalSize.height)
            
            var offsetY: CGFloat = 0
            var rangeExpandedFrames = [NSRange: CGRect]()
            let lineSpacing: CGFloat = 0
            
            for line in lines {
                let actualSize = line.frame.size
//                let actualSize = lineTextNode.updateLayout(line.frame.size)
                let attrString = line.attributedString
                
                let expandedFrame = expandedFrame(
                    lineSize: CGSize(width: min(actualSize.width, containerBounds.width), height: actualSize.height), // actualSize.size,
                    offsetY: offsetY,
                    containerBounds: containerBounds,
                    alignment: forcedAlignment ?? (attrString.length > 0 ? (attrString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment : .left),
                    isRTL: line.isRTL
                )
                offsetY += expandedFrame.height + lineSpacing
                rangeExpandedFrames[line.lineRange] = expandedFrame
            }
            
            return ExpandableTextNodeLayout(rangeToFrame: rangeExpandedFrames, constrainedSize: constrainedSize, alignment: forcedAlignment ?? .left)
        }
    }
    var prevExpansion: CGFloat?
    func updateIfNeeded(string: NSAttributedString, expandedLayout: ExpandableTextNodeLayout, expansionFraction: CGFloat, needsExpansionLayoutUpdate: Bool, transition: ContainedViewLayoutTransition) -> CGSize {
        // TODO: store
//        guard let singleLineInfo = getLinesArrayOfString(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).first else { return .zero }
        
        var shouldRemake = false
        
        if currentString != string || expandedLayout.rangeToFrame.keys != currentLayout?.rangeToFrame.keys {
            shouldRemake = true
        }
        
        currentString = string
        currentConstrainedSize = expandedLayout.constrainedSize
        currentLayout = expandedLayout
        prevAlignment = expandedLayout.alignment
        
        if !shouldRemake/*, currentLayout == expandedLayout*/ { // let currentLayout = self.currentLayout,  {
            if needsExpansionLayoutUpdate {
                updateExpansion(fraction: expansionFraction, transition: transition)
            }
        } else {
            textFragmentsNodes.forEach { $0.removeFromSupernode() }
            textFragmentsNodes = []
            
            for (range, _) in expandedLayout.rangeToFrame.sorted(by: { $0.key.location < $1.key.location }) {
                let substring = string.attributedSubstring(from: range)
                let textNode = ImmediateTextNode()
                textNode.displaysAsynchronously = false
                textNode.attributedText = substring
                textNode.maximumNumberOfLines = 1
                
                _ = textNode.updateLayout(expandedLayout.constrainedSize)
                textFragmentsNodes.append(textNode)
                textContainerNode.addSubnode(textNode)
            }
            
            if prevExpansion != nil {
                // For animation
                _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: 0, needsExpansionLayoutUpdate: true, transition: .immediate)
            }
            _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: expansionFraction, needsExpansionLayoutUpdate: true, transition: transition)
        }
        let dummyNode = ImmediateTextNode()
        dummyNode.attributedText = string
        dummyNode.maximumNumberOfLines = maxNumberOfLines
        let totalSize = dummyNode.updateLayout(expandedLayout.constrainedSize)
        
        return totalSize
    }
    
    func updateExpansion(fraction expansionFraction: CGFloat, transition: ContainedViewLayoutTransition) {
        guard let expandedLayout = currentLayout else { return }
        // TODO: store
        guard let string = currentString, let singleLineInfo = getLinesArrayOfString(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).first else { return }
        
        let sortedFrames = expandedLayout.rangeToFrame.sorted(by: { $0.key.lowerBound < $1.key.lowerBound }).map { $0 }
        
        var width: CGFloat = 0
        var height: CGFloat = 0
        for line in sortedFrames {
            width = max(width, line.value.width)
            height += line.value.height
        }
//            let totalSize = CGSize(width: width, height: height)
        
        for (index, textFragmentsNode) in self.textFragmentsNodes.enumerated() {
            let currentProgressFrame: CGRect
            let expandedFrame = sortedFrames[index].value // expandedFrame(lineSize: actualSize.size, offsetY: offsetY, containerBounds: containerBounds, alignment: forcedAlignment ?? (attrString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, isRTL: lineInfo.isRTL)
            
            if expansionFraction == 1 {
                currentProgressFrame = expandedFrame
            } else {
                let startIndexOfSubstring = sortedFrames[index].key.location// lineInfo.lineRange.location
                var secondaryOffset: CGFloat = 0.0
                var offsetX = floor(CTLineGetOffsetForStringIndex(singleLineInfo.ctLine, startIndexOfSubstring, &secondaryOffset))
                secondaryOffset = floor(secondaryOffset)
                
                let actualSize = expandedFrame.size
                
                if singleLineInfo.isRTL {
                    offsetX -= actualSize.width
                }
//                    if line.isRTL {
//                        offsetX -= actualSize.width
//                    }
                let collapsedFrame = CGRect(x: offsetX, y: 0, width: actualSize.width, height: actualSize.height)
                
//                    let containerBounds = CGRect(x: 0, y: 0, width: totalSize.width, height: totalSize.height)
                
                let yProgress = sqrt(1 - (expansionFraction - 1) * (expansionFraction - 1))
                let xProgress = expansionFraction // 1 - sqrt(1 - progress * progress)
                currentProgressFrame = CGRect(
                    x: expandedFrame.origin.x * xProgress - collapsedFrame.origin.x * (xProgress - 1),
                    y: expandedFrame.origin.y * yProgress - collapsedFrame.origin.y * (yProgress - 1),
                    width: expandedFrame.width * expansionFraction - collapsedFrame.width * (expansionFraction - 1),
                    height: expandedFrame.height * expansionFraction - collapsedFrame.height * (expansionFraction - 1)
                )
            }
//            textFragmentsNode.backgroundColor = .red.withAlphaComponent(0.4)
            transition.updateFrame(node: textFragmentsNode, frame: currentProgressFrame)
            // TODO: decide on whether stick to node.updateLayout() size or CTLine size
            _ = textFragmentsNode.updateLayout(.init(width: currentProgressFrame.width, height: currentProgressFrame.height)) // Because assigning bigger frame leads
        }
        prevExpansion = expansionFraction
    }
//
//    func update(string: NSAttributedString, alignment: NSTextAlignment?, constrainedSize: CGSize, expansionFraction: CGFloat, transition: ContainedViewLayoutTransition) {
//
//
//    }
    
    private struct LayoutLine {
        let attributedString: NSAttributedString
        let isRTL: Bool
        let frame: CGRect
        let ctLine: CTLine
        let lineRange: NSRange
    }
    
    private func getLinesArrayOfString(_ attStr: NSAttributedString, textSize: CGSize, maxNumberOfLines: Int = .max) -> [LayoutLine] {
        var linesArray = [LayoutLine]()
        
        let frameSetter: CTFramesetter = CTFramesetterCreateWithAttributedString(attStr as CFAttributedString)
        let path: CGMutablePath = CGMutablePath()
        path.addRect(CGRect(x: 0, y: 0, width: textSize.width, height: 100000), transform: .identity)
        let frame: CTFrame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, 0), path, nil)
        guard let allLines = CTFrameGetLines(frame) as? [Any], !allLines.isEmpty else { return linesArray }
        
        // Combine exceeding lines into last line
//        var lines = [CTLine]()
        let lines = allLines[0..<min(allLines.count, maxNumberOfLines)]
        
        if allLines.count > maxNumberOfLines, let lastLine = lines.last {
            let lineRange: CFRange = CTLineGetStringRange(lastLine as! CTLine)
            let lastVisibleRange = NSRange(location: lineRange.location, length: lineRange.length)
            
//            let exceedingRange = NSRange(location: lastVisibleRange, length: attStr.length - lastVisibleRange.upperBound)
            let lastLineRangeWithExcess = NSRange(location: lastVisibleRange.location, length: attStr.length - lastVisibleRange.location)
            let lastString = attStr.attributedSubstring(from: lastLineRangeWithExcess)
            
            let unaffectedString = attStr.attributedSubstring(from: NSRange(location: 0, length: lastVisibleRange.location))
            let firstLines: [LayoutLine]
            if lastVisibleRange.location > 0 {
                firstLines = getLinesArrayOfString(unaffectedString, textSize: textSize)
            } else {
                firstLines = []
            }
            
            let lastLines = getLinesArrayOfString(lastString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            let lastLine = lastLines.first
                .flatMap { line in
                    return LayoutLine(attributedString: line.attributedString, isRTL: line.isRTL, frame: line.frame, ctLine: line.ctLine, lineRange: NSRange(location: lastVisibleRange.location, length: attStr.length - lastVisibleRange.location))
                }
                .map { [$0] } ?? lastLines
            return firstLines + lastLine
        } else {
            
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
}
