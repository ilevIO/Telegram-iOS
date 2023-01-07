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

//typealias ExpandablePeerTitleTextNodeState = MultiScaleTextState
struct ExpandablePeerTitleTextNodeState {
    let string: NSAttributedString
    let alpha: CGFloat
}

final class ExpandablePeerTitleContainerNode: ASDisplayNode {
    let invertedContainerNode: ASDisplayNode = ASDisplayNode()
    
    var allAlignedBy: AnyHashable?
    var textSubnodes: [AnyHashable: ExpandablePeerTitleTextNode] = [:]
    var isTransitioning: Bool = false
    
    var trailingFadeIntensity: CGFloat = 0
    let trailingFadeMaskLayer = CALayer()
    var lastMainLayout: ExpandablePeerTitleTextNode.ExpandableTextNodeLayout?
    var gradientFadeMask = CALayer()
    
    let fadableContainerNode = ASDisplayNode()
    
    func update(states: [AnyHashable: ExpandablePeerTitleTextNodeState], mainState: AnyHashable?, constrainedSize: CGSize, textExpansionFraction: CGFloat, isAvatarExpanded: Bool, needsExpansionLayoutUpdate: Bool, transition: ContainedViewLayoutTransition) -> [AnyHashable: MultiScaleTextLayout] {
        var commonExpandedLayout: ExpandablePeerTitleTextNode.ExpandableTextNodeLayout? = nil
        
        var mainLayout: MultiScaleTextLayout?
        var result: [AnyHashable: MultiScaleTextLayout] = [:]
        self.allAlignedBy = mainState
        
        if let allAlignedBy = mainState {
            commonExpandedLayout = textSubnodes[allAlignedBy]?.getExpandedLayout(string: states[allAlignedBy]?.string ?? .init(), forcedAlignment: isAvatarExpanded ? .left : .center, constrainedSize: constrainedSize)
            lastMainLayout = commonExpandedLayout
        }
        
        for (key, state) in states {
            guard let node = textSubnodes[key], let layout = commonExpandedLayout ?? textSubnodes[key]?.getExpandedLayout(string: state.string, forcedAlignment: isAvatarExpanded ? .left : .center, constrainedSize: constrainedSize) else {
//                assertionFailure("check")
                continue
            }
            let size = node.updateIfNeeded(string: state.string, expandedLayout: layout, expansionFraction: textExpansionFraction, needsExpansionLayoutUpdate: needsExpansionLayoutUpdate, transition: transition)
            if key == mainState {
                mainLayout = MultiScaleTextLayout(size: size)
            }
            result[key] = MultiScaleTextLayout(size: size)
        }
        
        if let mainLayout = mainLayout {
            let mainBounds = CGRect(origin: CGPoint(x: -mainLayout.size.width / 2.0, y: -mainLayout.size.height / 2.0), size: mainLayout.size)
            for (key, _) in states {
                if let node = self.textSubnodes[key]/*, let nodeLayout = result[key]*/ {
                    let nodeLayout = mainLayout
                    node.updateTextFrame(CGRect(origin: CGPoint(x: mainBounds.minX, y: mainBounds.minY + floor((mainBounds.height - nodeLayout.size.height) / 2.0)), size: nodeLayout.size))
                }
            }
        }
        
        if !isTransitioning {
            for (key, state) in states {
                self.textSubnodes[key]?.alpha = state.alpha
                self.accessoryViews[key]?.alpha = state.alpha
            }
        }
        
        return result
    }
    
//    var alignedNodeSingleLineInfo: (key: AnyHashable, info: [LayoutLine])?
    
    func updateFading(solidWidth: CGFloat, containerWidth: CGFloat, height: CGFloat, offset: CGFloat) {
        self.textSubnodes.forEach { $0.value.updateContainerFading() }
        
        gradientFadeMask.removeFromSuperlayer()
        guard let allAlignedBy,
              let string = self.textSubnodes[allAlignedBy]?.currentString,
              let singleLineInfo = self.textSubnodes[allAlignedBy]?.singleLineInfo ?? getLayoutLines(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).first
        else { return }
        
//        self.singleLineInfo = singleLineInfo
        
        gradientFadeMask = .init()
        // Pass fade side from AnimatedHeaderLabelNode
//            let fadeSide_isRight = true
//        let isRTL = false
//        let solidMask = CALayer()
//        solidMask.backgroundColor = UIColor.black.cgColor
//        solidMask.frame = CGRect(x: 0, y: 0, width: availableWidth, height: height)
//
//        gradientFadeMask.addSublayer(solidMask)
//
//        let fadeRadius: CGFloat = 30
//        let gradientLayer = CAGradientLayer()
//        gradientLayer.frame = CGRect(x: availableWidth, y: 0, width: fadeRadius, height: height)
//        gradientLayer.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
//        gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
//        gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
//        gradientFadeMask.addSublayer(gradientLayer)
//        gradientFadeMask.masksToBounds = false
//        gradientFadeMask.frame = CGRect(x: -containerWidth / 2, y: -height / 2, width: availableWidth + fadeRadius, height: height)
        ///
        ///
        ///
        let gradientInset: CGFloat = 0
        let gradientRadius: CGFloat = 30
        
        let solidPartLayer = CALayer()
        solidPartLayer.backgroundColor = UIColor.blue.cgColor
        if singleLineInfo.isRTL {
            // TODO: fix rtl layout offsets
            let adjustForRTL: CGFloat = 12
            // TODO: remove safe
            let safeSolidWidth: CGFloat = containerWidth + adjustForRTL
            solidPartLayer.frame = CGRect(
                origin: CGPoint(x: max(containerWidth - solidWidth, gradientRadius), y: 0),
                size: CGSize(width: safeSolidWidth, height: height))
        } else {
            solidPartLayer.frame = CGRect(
                origin: .zero,
                size: CGSize(width: solidWidth + gradientInset, height: height))
        }
        gradientFadeMask.addSublayer(solidPartLayer)
        
        let gradientLayer = CAGradientLayer()
        gradientLayer.colors = [UIColor.blue.cgColor, UIColor.clear.cgColor]
        if singleLineInfo.isRTL {
            gradientLayer.startPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.frame = CGRect(x: solidPartLayer.frame.minX - gradientRadius, y: 0, width: gradientRadius, height: height)
        } else {
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            var adjustmentCoof: CGFloat { 1.5 }
            gradientLayer.frame = CGRect(x: solidWidth + gradientInset, y: 0, width: gradientRadius * adjustmentCoof, height: height)
        }
      //  gradientLayer.backgroundColor = UIColor.black.withAlphaComponent(0.4).cgColor
        gradientFadeMask.addSublayer(gradientLayer)
        gradientFadeMask.masksToBounds = false
        let offsetX: CGFloat
        if singleLineInfo.isRTL {
            offsetX = 0// -gradientRadius
        } else {
            offsetX = 0
        }
        gradientFadeMask.frame = CGRect(x: -containerWidth / 2 + offsetX + offset, y: -height / 2, width: /*solidWidth + gradientInset + gradientRadius*/0.0, height: height)
//        fadableContainerNode.layer.addSublayer(gradientFadeMask)
//        gradientFadeMask.opacity = 0.5
        fadableContainerNode.layer.mask = gradientFadeMask
    }
//
//    // Temporary convenience
//    static func initAsPeerHeaderTitle() -> ExpandableTextNodesContainer {
//        let container = ExpandableTextNodesContainer()
//        container.textSubnodes = [
//            PeerHeaderTitleState.thin.rawValue:
//        ]
//    }
    var accessoryViews: [AnyHashable: UIView] = [:]
    
    func addAccessory(for state: AnyHashable, accessoryView: UIView) {
        accessoryViews[state]?.removeFromSuperview()
        accessoryViews[state] = accessoryView
        view.addSubview(accessoryView)
    }
    
    init(stateKeys: [AnyHashable], order: [AnyHashable: Int]?) {
        self.textSubnodes = Dictionary(stateKeys.map { ($0, ExpandablePeerTitleTextNode()) }, uniquingKeysWith: { lhs, _ in lhs })
        
        super.init()
        
        addSubnode(fadableContainerNode)
        fadableContainerNode.addSubnode(invertedContainerNode)
        
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
            fadableContainerNode.addSubnode(node)
        }
    }
    
    func stateNode(forKey key: AnyHashable) -> ASDisplayNode? {
        return self.textSubnodes[key]?.textContainer
    }
}

final class ExpandablePeerTitleTextNode: ASDisplayNode {
    struct ExpandableTextNodeLayout {
        let rangeToFrame: [NSRange: CGRect]
        let constrainedSize: CGSize
        let alignment: NSTextAlignment
        let isTruncated: Bool
        // Quick convenience, replace with more minimal
        let lines: [LayoutLine]
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
        maskedContainerNode
    }
    let maskedContainerNode = ASDisplayNode()
    let textContainerNode = ASDisplayNode()
    var textFragmentsNodes: [ImmediateTextNode] = []
    
    var maxNumberOfLines: Int = 2
    /// Quick fix for regular collapsed state
    let rtlOneliner = ImmediateTextNode()
    
    override init() {
        super.init()
        
        self.addSubnode(maskedContainerNode)
        self.maskedContainerNode.addSubnode(textContainerNode)
    }
    var maskLayerContainer: CALayer?
    /// Update position
    func updateTextFrame(_ frame: CGRect) {
        maskedContainerNode.frame = frame
        textContainerNode.frame = maskedContainerNode.bounds
        debugTextNode?.frame = CGRect(x: frame.midX, y: frame.midY, width: frame.width, height: frame.height)
        _ = debugTextNode?.updateLayout(frame.size)
        
        updateContainerFading()
    }
    
    func needsContainerFading(layout: ExpandableTextNodeLayout) -> Bool {
        let lines = layout.lines
        if layout.isTruncated, lines.count > 1, lines[0].isRTL != lines[1].isRTL {
            return false
        }
       
        return true
    }
    
    func updateContainerFading() {
        // TODO: cache and reuse "class FadingMaskLayer: CALayer"
        if let currentLayout = self.currentLayout, needsContainerFading(layout: currentLayout), currentLayout.isTruncated, let lastLine = currentLayout.lines.last {
            maskLayerContainer?.removeFromSuperlayer()
            let maskLayer = CALayer()
            
            let maskGradientLayer = CAGradientLayer()
            maskGradientLayer.colors = [UIColor.black.cgColor, UIColor.clear.cgColor]
            
            let lastLineWidth: CGFloat
            let bottomY: CGFloat
            
            let isRTL = lastLine.isRTL
            
            if isRTL {
                maskGradientLayer.startPoint = .init(x: 1, y: 0.5)
                maskGradientLayer.endPoint = .init(x: 0, y: 0.5)
            } else {
                maskGradientLayer.startPoint = .init(x: 0, y: 0.5)
                maskGradientLayer.endPoint = .init(x: 1, y: 0.5)
            }
            // TODO: determine trailing node
            let lastFrame: CGRect? // = self.textFragmentsNodes.last?.frame
            if isRTL {
                lastFrame = textFragmentsNodes.last?.frame// textContainerNode.subnodes?.max(by: { $0.layer.frame.maxY < $1.layer.frame.maxY || $0.layer.frame.maxY == $1.layer.frame.maxY && $0.layer.frame.maxX > $1.layer.frame.maxX })?.frame
            } else {
                lastFrame = textFragmentsNodes.last?.frame// textContainerNode.subnodes?.max(by: { $0.layer.frame.maxY < $1.layer.frame.maxY || $0.layer.frame.maxY == $1.layer.frame.maxY && $0.layer.frame.maxX < $1.layer.frame.maxX })?.frame
            }
            // let TEMP_REMOVE_LATER_LINE_Info = // getLayoutLines(lastNode.attributedText!, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).first
            // let isRTL = TEMP_REMOVE_LATER_LINE_Info?.isRTL == true
            
            if let lastTextLayerFrame = lastFrame {
                if isRTL {
                    lastLineWidth = textContainerNode.bounds.width
                } else {
                    lastLineWidth = lastTextLayerFrame.maxX
                }
                bottomY = lastTextLayerFrame.maxY
            } else {
                lastLineWidth = textContainerNode.bounds.width
                bottomY = textContainerNode.bounds.height
            }
            let topSolidArea = CALayer()
            topSolidArea.backgroundColor = UIColor.black.cgColor
            
            let bottomSolidArea = CALayer()
            bottomSolidArea.backgroundColor = UIColor.black.cgColor
            
            let bottomLineHeight: CGFloat = lastLine.frame.height
            let fadeRadius: CGFloat = 50
            maskLayer.frame = textContainerNode.bounds
            // Adjusting for cases when top line becomes wider (currently due to kern increase used to fake weight transition)
            let collapseAdjustment: CGFloat = shouldChangeKernForReweight ? 32 : 0
            topSolidArea.frame = .init(x: 0, y: -collapseAdjustment, width: /*textContainerNode.bounds.width*/max(textContainerNode.bounds.width, lastLineWidth) + collapseAdjustment * 2, height: bottomY - bottomLineHeight)
            if isRTL {
                bottomSolidArea.frame = .init(x: fadeRadius, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight)
                maskGradientLayer.frame = .init(x: 0, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight)
            } else {
                bottomSolidArea.frame = .init(x: 0, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight)
                maskGradientLayer.frame = .init(x: bottomSolidArea.frame.maxX, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight)
            }
            maskLayer.addSublayer(topSolidArea)
            maskLayer.addSublayer(bottomSolidArea)
            maskLayer.addSublayer(maskGradientLayer)
           // textContainerNode.backgroundColor = UIColor.red.withAlphaComponent(0.7)
            textContainerNode.layer.mask = maskLayer
            maskLayerContainer = maskLayer
        } else {
//            maskLayerContainer?.removeFromSuperlayer()
            textContainerNode.layer.mask = nil
        }
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
            
            let (textNodeLayout, _) = TextNode.asyncLayout(nil)(.init(
                attributedString: string,
                backgroundColor: nil,
                minimumNumberOfLines: 0,
                maximumNumberOfLines: maxNumberOfLines,
                truncationType: .end,
                constrainedSize: constrainedSize,
                alignment: forcedAlignment ?? .left,
                verticalAlignment: .top,
                lineSpacing: 0,
                cutout: nil,
                insets: .zero,
                lineColor: nil,
                textShadowColor: nil,
                textStroke: nil,
                displaySpoilers: false,
                displayEmbeddedItemsUnderSpoilers: false
            ))
            let ranges = textNodeLayout.linesRanges
            let rects = textNodeLayout.linesRects()
            let lines: [LayoutLine] = ranges.enumerated().map { (index, range) in
                LayoutLine(
                    attributedString: string.attributedSubstring(from: range),
                    isRTL: textNodeLayout.lineIsRTL(at: index),
                    frame: rects[index],
                    ctLine: textNodeLayout.lines[index].line,
                    lineRange: range,
                    glyphRuns: CTLineGetGlyphRuns(textNodeLayout.lines[index].line) as? [CTRun] ?? [],
                    glyphRunsRanges: (CTLineGetGlyphRuns(textNodeLayout.lines[index].line) as? [CTRun] ?? []).map {
                        let cfRange = CTRunGetStringRange($0)
                        return NSRange(location: cfRange.location, length: cfRange.length)
                    }
                )
            }
            // let lines: [LayoutLine] = getLayoutLines(string, textSize: constrainedSize, maxNumberOfLines: self.maxNumberOfLines)
            var width: CGFloat = 0
            var height: CGFloat = 0
            for line in lines {
                width = max(width, min(line.frame.width, constrainedSize.width))
                height += line.frame.height
            }
            let totalSize = CGSize(width: width, height: height)
            let containerBounds = CGRect(x: 0, y: 0, width: totalSize.width, height: totalSize.height)
            var prevLineIsRTL = false
            var offsetY: CGFloat = 0
            var rangeExpandedFrames = [NSRange: CGRect]()
            let lineSpacing: CGFloat = 0
            let typeSetterWasRTL = lines.first?.isRTL == true
            for (lineIndex, line) in lines.enumerated() {
                let actualSize = line.frame.size
                // if line.isRTL {
                var glyphRunIndex = 0
                var glyphOffset: CGFloat = 0
                let lineString = line.attributedString
                let lineFrame: CGRect = self.expandedFrame(
                    lineSize: CGSize(width: min(actualSize.width, containerBounds.width), height: actualSize.height), // actualSize.size,
                    offsetY: offsetY,
                    containerBounds: containerBounds,
                    alignment: forcedAlignment ?? (lineString.length > 0 ? (lineString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment : .left),
                    isRTL: line.isRTL
                )
                
                let sequence: [EnumeratedSequence<[NSRange]>.Element]
                if line.isRTL && !typeSetterWasRTL {
                    sequence = line.glyphRunsRanges.enumerated().sorted(by: { $0.element.location < $1.element.location })// .map { $0 }// .map({ $0 })
                } else {
                    sequence = line.glyphRunsRanges.enumerated().map { $0 }// .map({ $0 })
                }
                for (index, glyphRunRange) in sequence {
//                    let cfRange = glyphRun// CTRunGetStringRange(glyphRun)
                    let glyphRun = line.glyphRuns[index]
                    let absoluteRange = glyphRunRange// NSRange(location: cfRange.location, length: cfRange.length)
//                    let substring = string.attributedSubstring(from: range)
                    var secondaryOffset: CGFloat = 0//; CTRunGetStatus(glyphRun)
                    var xOffset = CTLineGetOffsetForStringIndex(line.ctLine, absoluteRange.location - line.lineRange.location, &secondaryOffset)
                    
                    // TODO: maybe remove trailing whitespaces
                    let glyphWidth = CTRunGetTypographicBounds(glyphRun, CFRangeMake(0, 0), nil, nil, nil)
//                    CTRunGetImageBounds(glyphRun, nil, CFRangeMake(0, 0))
                    if line.isRTL && lineIndex > 0 && !prevLineIsRTL {//*CTRunGetStatus(glyphRun).contains(.rightToLeft)*/ /*&& absoluteRange.location - line.lineRange.location == 0*/ {
                        xOffset = line.frame.width - glyphOffset - glyphWidth// line.frame.width - secondaryOffset
                    } else if line.isRTL {
                        xOffset = glyphOffset
                    } else {
                        xOffset = glyphOffset
                    }
                     glyphOffset += glyphWidth
                    
                    let expandedFrame = CGRect(x: xOffset + lineFrame.origin.x, y: offsetY, width: glyphWidth, height: actualSize.height)/*expandedFrame(
                        lineSize: CGSize(width: min(actualSize.width, containerBounds.width), height: actualSize.height), // actualSize.size,
                        offsetY: offsetY,
                        containerBounds: containerBounds,
                        alignment: forcedAlignment ?? (attrString.length > 0 ? (attrString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment : .left),
                        isRTL: line.isRTL
                    )*/
//                    let absoluteRange = NSRange(location: line.lineRange.location + rangeInLine.location, length: rangeInLine.length)
                    rangeExpandedFrames[absoluteRange] = expandedFrame
                    glyphRunIndex += absoluteRange.length
                }
                print(glyphRunIndex)
//                let actualSize = lineTextNode.updateLayout(line.frame.size)
               /* let attrString = line.attributedString
                
                let expandedFrame: CGRect = expandedFrame(
                    lineSize: CGSize(width: min(actualSize.width, containerBounds.width), height: actualSize.height), // actualSize.size,
                    offsetY: offsetY,
                    containerBounds: containerBounds,
                    alignment: forcedAlignment ?? (attrString.length > 0 ? (attrString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment : .left),
                    isRTL: line.isRTL
                )
                rangeExpandedFrames[line.lineRange] = expandedFrame*/
                offsetY += /*expandedFrame*/actualSize.height + lineSpacing
                prevLineIsRTL = line.isRTL
            }
            
            return ExpandableTextNodeLayout(rangeToFrame: rangeExpandedFrames, constrainedSize: constrainedSize, alignment: forcedAlignment ?? .left, isTruncated: textNodeLayout.truncated, lines: lines)
        }
    }
    var prevExpansion: CGFloat?
    func updateIfNeeded(string: NSAttributedString, expandedLayout: ExpandableTextNodeLayout, expansionFraction: CGFloat, needsExpansionLayoutUpdate: Bool, transition: ContainedViewLayoutTransition) -> CGSize {
        var shouldRemake = false
        
        if currentString != string || expandedLayout.rangeToFrame != currentLayout?.rangeToFrame {
            shouldRemake = true
        }
        if currentString != string {
            self.singleLineInfo = getLayoutLines(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)).first
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
//            let lines = getLayoutLines(string, textSize: expandedLayout.constrainedSize, maxNumberOfLines: self.maxNumberOfLines)
//
//            for line in lines {
//                for glyphRun in line.glyphRuns {
//                    let range = CTRunGetStringRange(glyphRun)
//                    let substring = string.attributedSubstring(from: range)
//                    var secondaryOffset: CGFloat = 0
//                    let xOffset = CTLineGetOffsetForStringIndex(line.ctLine, range.location, &secondaryOffset)
//
//                }
//            }
            // Split into separate letters
//            let lines = getLayoutLines(string, textSize: expandedLayout.constrainedSize)
//            lines.forEach { line in
//            }
            
            let needsFading = self.needsContainerFading(layout: expandedLayout)
            
            for (index, (range, textFrame)) in expandedLayout.rangeToFrame.sorted(by: { $0.key.location < $1.key.location }).enumerated() {
                var substring = string.attributedSubstring(from: range)
                let textNode = ImmediateTextNode()
                if expandedLayout.isTruncated, index == expandedLayout.rangeToFrame.count - 1, !needsFading/*, string.length > 0*/ {
                    /*let maskLayer = CAGradientLayer()
                    maskLayer.colors = [UIColor.black.withAlphaComponent(0.7).cgColor, UIColor.clear.cgColor]
                    maskLayer.startPoint = .init(x: 0, y: 0.5)
                    maskLayer.endPoint = .init(x: 1, y: 0.5)
                    maskLayer.frame = .init(x: 0, y: 0, width: 18, height: 100)
                    textNode.layer.addSublayer(maskLayer)*/
                    substring = NSAttributedString(string: "\u{2026}", attributes: string.length > 0 ? string.attributes(at: 0, effectiveRange: nil) : [:])// NSAttributedString(string: substring.string + "\u{2026}", attributes: substring.length > 0 ? substring.attributes(at: 0, effectiveRange: nil) : [:])
                }// TextNodeFracture()// ImmediateTextNode()
//                textNode.lineIndex = index
                textNode.displaysAsynchronously = false
                textNode.attributedText = substring
//                print(index)
//                textNode.fullText = string
//                textNode.textAlignment = .natural
//                textNode.bounds.origin.y = -frame.minY
//                textNode.bounds.size.height = frame.height
                textNode.maximumNumberOfLines = 1// maxNumberOfLines // 1
                textNode.layer.masksToBounds = false
//                textNode.clipsToBounds = true
                if needsFading {
                    _ = textNode.updateLayout(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))// expandedLayout.constrainedSize)
                } else {
                    _ = textNode.updateLayout(CGSize(width: textFrame.width, height: textFrame.height))
                }
                textFragmentsNodes.append(textNode)
                textContainerNode.addSubnode(textNode)
            }
            
            if let prevExpansion = self.prevExpansion {
                _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: prevExpansion, needsExpansionLayoutUpdate: true, transition: .immediate)
            }
            _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: expansionFraction, needsExpansionLayoutUpdate: true, transition: transition)
        }
        
//        let dummyNode = ImmediateTextNode()
//        dummyNode.attributedText = string
//        dummyNode.maximumNumberOfLines = maxNumberOfLines
//        let testSize = dummyNode.updateLayout(expandedLayout.constrainedSize)
//        print(testSize)
//        dummyNode.backgroundColor = UIColor.green.withAlphaComponent(0.2)
//        dummyNode.alpha = 0.6
//        dummyNode.textAlignment = .center
//        debugTextNode?.removeFromSupernode()
//        textContainerNode.addSubnode(dummyNode)
//        debugTextNode = dummyNode
        if !shouldRemake, let currentExpandedTotalSize = self.currentExpandedTotalSize {
            return currentExpandedTotalSize
        } else {
            // TODO: iterate layout runs
            let lines: [LayoutLine] = getLayoutLines(string, textSize: expandedLayout.constrainedSize, maxNumberOfLines: self.maxNumberOfLines)
            var width: CGFloat = 0
            var height: CGFloat = 0
            for line in lines {
                width = max(width, min(line.frame.width, expandedLayout.constrainedSize.width))
                height += line.frame.height
            }
            let totalSize = CGSize(width: width, height: height)
            self.currentExpandedTotalSize = totalSize
            return totalSize// CGSize(width: width, height: height)// totalSize
        }
    }
    
    var currentExpandedTotalSize: CGSize?
    
    var debugTextNode: ImmediateTextNode?
    
    var singleLineInfo: LayoutLine?
    
    func updateExpansion(fraction expansionFraction: CGFloat, transition: ContainedViewLayoutTransition) {
        guard let expandedLayout = currentLayout else { return }
        // TODO: store
        guard // let string = self.currentString,
            let adjustedString = self.currentString.flatMap({ reweightString(string: $0, weight: 1 - expansionFraction, in: ImmediateTextNode()) }),
              let singleLineInfo = /*self.singleLineInfo ?? */ getLayoutLines(adjustedString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).first
        else { return }
        
        self.singleLineInfo = singleLineInfo
        
        let sortedFrames = expandedLayout.rangeToFrame.sorted(by: { $0.key.location < $1.key.location }).map { $0 }
        
//        var width: CGFloat = 0
//        var height: CGFloat = 0
//        for line in sortedFrames {
//            width = max(width, line.value.width)
//            height += line.value.height
//        }
        let totalSize: CGSize
        if let currentSize = self.currentExpandedTotalSize {
            totalSize = currentSize
        } else {
            let sizeTextnode = ImmediateTextNode()
            sizeTextnode.displaysAsynchronously = false
            sizeTextnode.attributedText = self.currentString
            sizeTextnode.maximumNumberOfLines = self.maxNumberOfLines
            totalSize = sizeTextnode.updateLayout(expandedLayout.constrainedSize)
        }
//            let totalSize = CGSize(width: width, height: height)
        print(totalSize)
        // for (index, textFragmentsNode) in self.textFragmentsNodes.enumerated() {
        var rtlAdjustment: CGFloat = 0.0
        let firstLineIsRTL = singleLineInfo.isRTL
        
        if firstLineIsRTL {
            let currentContainerWidth = expandedLayout.constrainedSize.width// textContainerNode.bounds.width
            rtlAdjustment = max(singleLineInfo.frame.width - currentContainerWidth, 0.0) / 2.0
        }
        
        for (index, (range, frame)) in sortedFrames.enumerated() {
            let textFragmentsNode = self.textFragmentsNodes[index]
            let currentProgressFrame: CGRect
            let expandedFrame = frame // sortedFrames[index].value // expandedFrame(lineSize: actualSize.size, offsetY: offsetY, containerBounds: containerBounds, alignment: forcedAlignment ?? (attrString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment, isRTL: lineInfo.isRTL)
//            textFragmentsNode.backgroundColor = .blue.withAlphaComponent(0.4)
//            if expandedFrame.minY == 0 {
//                textFragmentsNode.backgroundColor = .red.withAlphaComponent(0.4)
//            } else {
//                textFragmentsNode.backgroundColor = .green.withAlphaComponent(0.4)
//            }
            let newWeight = 1 - expansionFraction// expandedWeight * progress + collapsedWeight * (1 - progress)
//            let prevString = textFragmentsNode.attributedText!
            let _ = reweightString(string: textFragmentsNode.attributedText!, weight: newWeight, in: textFragmentsNode)
            
            if expansionFraction == 1 {
                currentProgressFrame = expandedFrame
            } else {
                let startIndexOfSubstring = range.location// sortedFrames[index].key.location// lineInfo.lineRange.location
                var secondaryOffset: CGFloat = 0.0
                var offsetX = floor(CTLineGetOffsetForStringIndex(singleLineInfo.ctLine, startIndexOfSubstring, &secondaryOffset))
                secondaryOffset = floor(secondaryOffset)
                offsetX = secondaryOffset
                let actualSize = expandedFrame.size
                
               /* if let glyphRangeIndex = singleLineInfo.glyphRunsRanges.firstIndex(where: { $0.contains(range.location) }),
                   CTRunGetStatus(singleLineInfo.glyphRuns[glyphRangeIndex]).contains(.rightToLeft) {
                   
//                   singleLineInfo.glyphRuns.contains(where: { CTRunGetStatus($0).contains(.rightToLeft) }) {
                    offsetX = secondaryOffset - expandedFrame.width// -= actualSize.width
                }*/
                // TODO: cache
                if let glyphRangeIndex = singleLineInfo.glyphRunsRanges.firstIndex(where: { $0.contains(range.location) }), CTRunGetStatus(singleLineInfo.glyphRuns[glyphRangeIndex]).contains(.rightToLeft) {
//                    var pointBuffer = CGPoint.zero//[CGPoint]()
                    let glyphRun = singleLineInfo.glyphRuns[glyphRangeIndex]
                    let runRange = CTRunGetStringRange(glyphRun)
                    // TODO: research if always matches
                    let positions = UnsafeMutablePointer<CGPoint>.allocate(capacity: runRange.length)
                    
                    CTRunGetPositions(glyphRun, CFRangeMake(/*range.location*/0, range.length), positions)
//                    print(pointBuffer)
                    if range.length > 0 {
                        let pos = positions[0]
                        offsetX = pos.x
                    }
                    
                    positions.deallocate()
//                    offsetX = pointBuffer.x // - expandedFrame.size.width// singleLineInfo.frame.width - offsetX + expandedFrame.size.width
                    //                   singleLineInfo.glyphRuns.contains(where: { CTRunGetStatus($0).contains(.rightToLeft) }) {
//                    offsetX = secondaryOffset - expandedFrame.width// -= actualSize.width
                    //                    offsetX = offsetX - expandedFrame.width// -= actualSize.width
//                    free(pointBuffer)
//                    pointBuffer.deallocate()
                }

//                    if line.isRTL {
//                        offsetX -= actualSize.width
//                    }
                let collapsedFrame = CGRect(
                    x: offsetX - rtlAdjustment,
                    y: 0,
                    width: actualSize.width * (shouldChangeKernForReweight ? 1.1 : 1),// max(actualSize.width, newString.boundingRect(with: CGSize(width: CGFloat.greatestFiniteMagnitude, height: 1000.0), context: nil).width + 4),
                    height: actualSize.height)
                
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
            
//            let expandedWeight: CGFloat = isAvatarExpanded ? UIFont.Weight.semibold.rawValue : UIFont.Weight.regular.rawValue
//            let collapsedWeight: CGFloat = UIFont.Weight.semibold.rawValue
             /*NSMutableAttributedString(attributedString: textFragmentsNode.attributedText!)
            newString.addAttributes([.font: UIFont.systemFont(ofSize: 30, weight: .init(newWeight))], range: NSRange(location: 0, length: newString.length))*/
//            let layerTransition = CATransition()
//            layerTransition.type = CATransitionType.fade
//            transition.subtype = kCATransitionFromRight
//            layerTransition.duration = 1
            
//            textFragmentsNode.layer.add(layerTransition, forKey: "transition")
            
//            textFragmentsNode.layer.masksToBounds = false
//            textFragmentsNode.attributedText = newString
//            textFragmentsNode.backgroundColor = .red.withAlphaComponent(0.4)
            textFragmentsNode.attributedText = NSAttributedString(attributedString: textFragmentsNode.attributedText!)
            _ = textFragmentsNode.updateLayout(expandedLayout.constrainedSize)
            textFragmentsNode.redrawIfPossible()
            textFragmentsNode.recursivelyEnsureDisplaySynchronously(true)
            
            transition.updateFrame(node: textFragmentsNode, frame: CGRect(origin: currentProgressFrame.origin, size: CGSize(width: currentProgressFrame.width, height: expandedFrame.height)))// currentProgressFrame)
            // TODO: decide on whether to stick to node.updateLayout() size or CTLine size
//            textFragmentsNode.layer.masksToBounds = false
//            textFragmentsNode.attributedText = prevString
//            textFragmentsNode.backgroundColor = UIColor.red.withAlphaComponent(0.2)
//            _ = textFragmentsNode.updateLayout(CGSize(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)/*currentProgressFrame.size*/)// CGSize(width: totalSize.width, height: totalSize.height))//.init(width: currentProgressFrame.width, height: currentProgressFrame.height)) // Because assigning bigger frame leads to extra specing
        }
        prevExpansion = expansionFraction
    }
//
//    func update(string: NSAttributedString, alignment: NSTextAlignment?, constrainedSize: CGSize, expansionFraction: CGFloat, transition: ContainedViewLayoutTransition) {
//
//
//    }
    var varyingKerning: Bool { false }
    
    private enum VariableFontAttribute: String, RawRepresentable {
        case name         = "NSCTVariationAxisName"
        case identifier   = "NSCTVariationAxisIdentifier"
        case defaultValue = "NSCTVariationAxisDefaultValue"
        case currentValue = "CZCTVariationAxisCurrentValue"
        case maxValue     = "NSCTVariationAxisMaximumValue"
        case minValue     = "NSCTVariationAxisMinimumValue"
    }
    
    private struct VariationAxis {
        var name: String
        var identifier: NSNumber
        var defaultValue: Double
        var currentValue: Double
        var minValue: Double
        var maxValue: Double
        
        var variationDirection: Int
        
        var minMaxDelta: Double { maxValue - minValue }
        
        init(
            name: String,
            identifier: NSNumber,
            defaultValue: Double,
            currentValue: Double,
            minValue: Double,
            maxValue: Double
        ) {
            self.name = name
            self.identifier = identifier
            self.defaultValue = defaultValue
            self.currentValue = currentValue
            self.minValue = minValue
            self.maxValue = maxValue
            self.variationDirection = 1
        }
        
        init(attributes: [String: Any]) {
            let name = attributes[VariableFontAttribute.name.rawValue] as? String ?? "<no name>"
            let identifier = attributes[VariableFontAttribute.identifier.rawValue] as? NSNumber ?? -1
            let defaultValue = attributes[VariableFontAttribute.defaultValue.rawValue] as? Double ?? 0.0
            let currentValue = defaultValue
            let minValue = attributes[VariableFontAttribute.minValue.rawValue] as? Double ?? 0.0
            let maxValue = attributes[VariableFontAttribute.maxValue.rawValue] as? Double ?? 0.0
            self.init(
                name: name,
                identifier: identifier,
                defaultValue: defaultValue,
                currentValue: currentValue,
                minValue: minValue,
                maxValue: maxValue
            )
        }
    }
    
    /// Performance hit
    var shouldReweightString: Bool { false }
    var shouldChangeKernForReweight: Bool { false }
    var shouldChangeStrokeForReweight: Bool { false }
    
    /// UIFont.systemFont only, for other fonts use CoreText with variationAxis
    func reweightString(string: NSAttributedString, weight: CGFloat, in node: ImmediateTextNode) -> NSAttributedString {
        guard shouldReweightString else {
            return string
        }
        
        guard string.length > 0, let strokeColor = string.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        else { return string }
        
        if weight > CGFloat.ulpOfOne {
            let strokeRegularToSemiboldCoeff: CGFloat = 1.0
            node.textStroke = (strokeColor, weight * strokeRegularToSemiboldCoeff)
        } else {
            node.textStroke = nil
        }
            
        guard pow(2, 2) == 5 else { return string }
        
//        layer.shadowColor = strokeColor.cgColor
//        layer.shadowOffset = .zero
//        layer.shadowOpacity = Float(weight)
//        layer.shadowRadius = 0.3 // weight
        
        let reweightString = NSMutableAttributedString(attributedString: string)
        let stringRange = NSRange.init(location: 0, length: reweightString.length)
        // Faking weight with stroke
        if weight > 0 {
            if shouldChangeStrokeForReweight {
                reweightString.addAttribute(.strokeColor, value: strokeColor, range: stringRange)
                // Assuming weight passed changes from actual base value to 1 representing final value (from regular to semibold omitting thinner and thicker values)
                let strokeRegularToSemiboldCoeff: CGFloat = 2.0
                reweightString.addAttribute(.strokeWidth, value: -weight * strokeRegularToSemiboldCoeff, range: stringRange)
            }
            if shouldChangeKernForReweight {
                let kernRegularToSemiboldCoeff: CGFloat = 1.0
                reweightString.addAttribute(.kern, value: weight * kernRegularToSemiboldCoeff, range: stringRange)
            }
        } else {
            reweightString.removeAttribute(.strokeColor, range: stringRange)
            reweightString.removeAttribute(.strokeWidth, range: stringRange)
            reweightString.removeAttribute(.kern, range: stringRange)
        }
        return reweightString
        // Variable test
        //        reweightString.addAttribute(.font, value: UIFont.systemFont(ofSize: 30, weight: .init(rawValue: weight)), range: NSRange(location: 0, length: reweightString.length))
//        reweightString.addAttribute(.kern, value: 0 + 1 * weight, range: NSRange(location: 0, length: reweightString.length))
        //        reweightString.addAttribute(.kern, value: 0 + 1 * weight, range: NSRange(location: 0, length: reweightString.length))
        
//        return reweightString
//        let size: CGFloat = 30
//        let fontName = UIFont.systemFont(ofSize: 30).fontName
//        
//        let ctFontName = UIFont.systemFont(ofSize: 30) as CTFont // CTFontCreateWithName(fontName as CFString, size, nil)
//        var fontVariationAxes: [VariationAxis] = (CTFontCopyVariationAxes(ctFontName)! as Array)
//            .map { .init(attributes: $0 as? [String: Any] ?? [:]) }
//        var weightAxis = fontVariationAxes[0]
//        let weightValue = weight // weightAxis.minValue + weightAxis.minMaxDelta * Double((weight.rawValue + 1) / 2)
//        weightAxis.currentValue = weightValue
//        fontVariationAxes[0] = weightAxis
//        let ctFontVariationAttribute = kCTFontVariationAttribute as UIFontDescriptor.AttributeName
       /* let intermediateFont = UIFont.systemFont(ofSize: 30, weight: .init(weight))/*UIFont(
            descriptor: .init(
                fontAttributes: [
//                    .name: fontName,
                    ctFontVariationAttribute: fontVariationAxes
                        .reduce(into: [NSNumber: Any]()) { buffer, variationAxis in
                            buffer[variationAxis.identifier] = variationAxis.currentValue
                        }
                ]
            ),
            size: size
        )*/
        
        reweightString.addAttribute(.font, value: intermediateFont, range: NSRange.init(location: 0, length: reweightString.length))
        return reweightString*/
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

struct LayoutLine {
    let attributedString: NSAttributedString
    let isRTL: Bool
    let frame: CGRect
    let ctLine: CTLine
    let lineRange: NSRange
    let glyphRuns: [CTRun]
    let glyphRunsRanges: [NSRange]
}

func getLayoutLines(_ attStr: NSAttributedString, textSize: CGSize, maxNumberOfLines: Int = .max) -> [LayoutLine] {
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
            firstLines = getLayoutLines(unaffectedString, textSize: textSize)
        } else {
            firstLines = []
        }
        // MARK: maybe here runs get broken
        let lastLines = getLayoutLines(lastString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let lastLine = lastLines.first
            .flatMap { line in
                return LayoutLine(attributedString: line.attributedString, isRTL: line.isRTL, frame: line.frame, ctLine: line.ctLine, lineRange: NSRange(location: lastVisibleRange.location, length: attStr.length - lastVisibleRange.location), glyphRuns: line.glyphRuns, glyphRunsRanges: line.glyphRunsRanges.map { NSRange(location: $0.location + lastVisibleRange.location, length: $0.length) })
            }
            .map { [$0] } ?? lastLines
        return firstLines + lastLine
    } else {
        let font: CTFont
        if attStr.length > 0, let stringFont = attStr.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) {
            font = stringFont as! CTFont
        } else {
            font = UIFont.systemFont(ofSize: 30)
        }
        
        let fontAscent = CTFontGetAscent(font)
        let fontDescent = CTFontGetDescent(font)
//            let lineBounds = CTLineGetBoundsWithOptions(line, .useOpticalBounds)
        let fontLineHeight: CGFloat = floor(fontAscent + fontDescent) // floor(lineBounds.height + lineBounds.origin.y) // 35
        
        // TODO: reuse logic from TextNode
        for line in lines {
            // TODO: remove trailing spaces
            let lineRef = line as! CTLine
            let lineRange: CFRange = CTLineGetStringRange(lineRef)
            let range = NSRange(location: lineRange.location, length: lineRange.length)
            let lineString = attStr.attributedSubstring(from: range)
            
            let lineOriginY: CGFloat = 0
            let headIndent: CGFloat = 0
            
//            var fontAscent: CGFloat = 0
//            var fontDescent: CGFloat = 0
//            _ = CTLineGetTypographicBounds(lineRef, &fontAscent, &fontDescent, nil)
            
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
            let ctRuns = glyphRuns.map { $0 as! CTRun }
            linesArray.append(LayoutLine(attributedString: lineString, isRTL: isRTL, frame: lineFrame, ctLine: lineRef, lineRange: range, glyphRuns: ctRuns, glyphRunsRanges: ctRuns.map {
                let range = CTRunGetStringRange($0)
                return NSRange(location: range.location, length: range.length)
            }))
        }
        return linesArray
    }
}
