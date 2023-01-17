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

struct ExpandablePeerTitleTextNodeState {
    let string: NSAttributedString
    let alpha: CGFloat
}

var debugShouldChangeSpacingForReweight = false

final class ExpandablePeerTitleTextNode: ASDisplayNode {
    struct ExpandableTextNodeLayout {
        let rangeToFrame: [NSRange: CGRect]
        let constrainedSize: CGSize
        let alignment: NSTextAlignment
        let isTruncated: Bool
        let lines: [LayoutLine]
    }
    private(set) var currentString: NSAttributedString?
    private(set) var currentLayout: ExpandableTextNodeLayout?
    private(set) var currentExpansion: CGFloat?
    private(set) var currentConstrainedSize: CGSize?
    private var ctLine: CTLine?
    private var prevAlignment: NSTextAlignment?
    
    var maxNumberOfLines: Int { 2 }
    var textContainer: ASDisplayNode {
        maskedContainerNode
    }
    private let maskedContainerNode = ASDisplayNode()
    private let textContainerNode = ASDisplayNode()
    private(set) var textFragmentsNodes: [ImmediateTextNode] = []
    
    
    private var maskLayerContainer: CALayer?
    
    private(set) var currentExpandedTotalSize: CGSize?
    private(set) var singleLineInfo: LayoutLine?
    private var singleInfoReweight: LayoutLine?
    
    private var shouldReweightString: Bool { true }
    private var shouldChangeSpacingForReweight: Bool { debugShouldChangeSpacingForReweight /*true*/ }
    private var shouldChangeStrokeForReweight: Bool { true }
    
    private var prevExpansion: CGFloat?
    
    private var maskLayer = CALayer()
    private var maskGradientLayer = CAGradientLayer()
    private var topSolidArea = CALayer()
    private var bottomSolidArea = CALayer()
    private var blockExpansionUpdate: Bool = false
    private var transitionAnimation: CABasicAnimation?
    
    override init() {
        super.init()
        
        self.addSubnode(maskedContainerNode)
        self.maskedContainerNode.addSubnode(textContainerNode)
    }
    
    fileprivate func updateTextFrame(_ frame: CGRect, extraIconPadding: CGFloat, transition: ContainedViewLayoutTransition) {
        transition.updateFrame(node: maskedContainerNode, frame: frame)
        transition.updateFrame(node: textContainerNode, frame: maskedContainerNode.bounds)
        updateContainerFading(extraIconPadding: extraIconPadding, transition: transition)
    }
    
    private func needsContainerFading(layout: ExpandableTextNodeLayout) -> Bool {
        return true
    }
    
    fileprivate func updateContainerFading(extraIconPadding: CGFloat, transition: ContainedViewLayoutTransition) {
        if let currentLayout = self.currentLayout, needsContainerFading(layout: currentLayout), let lastLine = currentLayout.lines.last, currentLayout.isTruncated || lastLine.frame.width > currentLayout.constrainedSize.width - extraIconPadding {
//            maskLayerContainer?.removeFromSuperlayer()
            maskGradientLayer.colors = [UIColor.cyan.cgColor, UIColor.clear.cgColor]
            
            let lastLineWidth: CGFloat
            let bottomY: CGFloat
            let isRTL = lastLine.isRTL
            // Long mixed adjustment
            let singleLineIsRTL = isRTL // currentLayout.lines[0].isRTL
            
            if isRTL {
                maskGradientLayer.startPoint = .init(x: 1, y: 0.5)
                maskGradientLayer.endPoint = .init(x: 0, y: 0.5)
            } else {
                maskGradientLayer.startPoint = .init(x: 0, y: 0.5)
                maskGradientLayer.endPoint = .init(x: 1, y: 0.5)
            }
            
            var lastFrame: CGRect?
            if isRTL && singleLineIsRTL {
                if let lastNode = textFragmentsNodes.last {
                    let expansion = self.prevExpansion ?? 1.0
                    lastFrame = CGRect(
                        x: (lastNode.frame.maxX - textContainerNode.bounds.width) * (1.0 - expansion),
                        y: lastNode.frame.minY,
                        width: textContainerNode.bounds.width,
                        height: lastNode.frame.height)
                }
            } else {
                if let lastNode = textFragmentsNodes.last {
                    lastFrame = CGRect(x: lastNode.frame.minX, y: lastNode.frame.minY, width: textContainerNode.bounds.width, height: lastNode.frame.height)
                }
            }
            
            if let lastTextLayerFrame = lastFrame {
                if isRTL && singleLineIsRTL {
                    lastLineWidth = textContainerNode.bounds.width - lastTextLayerFrame.minX
                } else {
                    let borrowedWidth = max(lastTextLayerFrame.width + extraIconPadding - currentLayout.constrainedSize.width, 0.0)
                    lastLineWidth = lastTextLayerFrame.maxX - borrowedWidth
                }
                bottomY = lastTextLayerFrame.maxY
            } else {
                lastLineWidth = textContainerNode.bounds.width
                bottomY = textContainerNode.bounds.height
            }
            topSolidArea.backgroundColor = UIColor.blue.cgColor
            
            bottomSolidArea.backgroundColor = UIColor.blue.cgColor
            
            let bottomLineHeight: CGFloat = lastLine.frame.height
            let fadeRadius: CGFloat = 50
            transition.updateFrame(layer: maskLayer, frame: textContainerNode.bounds)
            
            // Adjusting for cases when top line becomes wider (currently due to kern increase used to fake weight transition)
            let collapseAdjustment: CGFloat = shouldChangeSpacingForReweight ? 32 : 0
            let topLineHeight = bottomLineHeight
            let topLineWidth: CGFloat
            if isRTL && singleLineIsRTL {
                let safeWhitespacePadding: CGFloat = 16.0
                topLineWidth = max(textContainerNode.bounds.width, lastLineWidth) + safeWhitespacePadding
            } else {
                topLineWidth = textContainerNode.bounds.width
            }
            
            transition.updateFrame(layer: topSolidArea, frame: CGRect(x: 0, y: -collapseAdjustment, width: topLineWidth + collapseAdjustment * 2, height: topLineHeight + collapseAdjustment))
            
            if isRTL {
                if singleLineIsRTL {
                    if transition.isAnimated {
                        transition.updateFrame(layer: bottomSolidArea, frame: CGRect(x: textContainer.bounds.width - lastLineWidth + fadeRadius + extraIconPadding, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight))
                        transition.updateFrame(layer: maskGradientLayer, frame: CGRect(x: bottomSolidArea.frame.minX - fadeRadius, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight))
                    } else {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        bottomSolidArea.frame = CGRect(x: textContainer.bounds.width - lastLineWidth + fadeRadius + extraIconPadding, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight)
                        maskGradientLayer.frame = CGRect(x: /*0 + extraIconPadding*/bottomSolidArea.frame.minX - fadeRadius, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight)
                        CATransaction.commit()
                    }
                } else {
                    if transition.isAnimated {
                        transition.updateFrame(layer: bottomSolidArea, frame: CGRect(x: fadeRadius + extraIconPadding, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight))
                        transition.updateFrame(layer: maskGradientLayer, frame: CGRect(x: bottomSolidArea.frame.minX - fadeRadius, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight))
                    } else {
                        CATransaction.begin()
                        CATransaction.setDisableActions(true)
                        bottomSolidArea.frame = CGRect(x: fadeRadius + extraIconPadding, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight)
                        maskGradientLayer.frame = CGRect(x: /*0 + extraIconPadding*/bottomSolidArea.frame.minX - fadeRadius, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight)
                        CATransaction.commit()
                    }
                }
            } else {
                if transition.isAnimated {
                    transition.updateFrame(layer: bottomSolidArea, frame: CGRect(x: 0, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight))
                    transition.updateFrame(layer: maskGradientLayer, frame: CGRect(x: bottomSolidArea.frame.maxX, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight))
                } else {
                    CATransaction.begin()
                    CATransaction.setDisableActions(true)
                    bottomSolidArea.frame = .init(x: 0, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight)
                    maskGradientLayer.frame = .init(x: bottomSolidArea.frame.maxX, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight)
                    CATransaction.commit()
                }
            }
            
            transition.updateBackgroundColor(layer: maskGradientLayer, color: UIColor.blue.withAlphaComponent(1 - (self.prevExpansion ?? 0))/*.cgColor*/)
            
            if topSolidArea.superlayer == nil {
                maskLayer.addSublayer(topSolidArea)
                maskLayer.addSublayer(bottomSolidArea)
                maskLayer.addSublayer(maskGradientLayer)
            }
            textContainerNode.layer.mask = maskLayer
            maskLayerContainer = maskLayer
//            if maskLayer.superlayer == nil {
//                textContainerNode.layer.addSublayer(maskLayer)
//                maskLayer.opacity = 0.5
//            }
        } else {
            textContainerNode.layer.mask = nil
        }
    }
    
    fileprivate func getExpandedLayout(string: NSAttributedString, forcedAlignment: NSTextAlignment?, constrainedSize: CGSize, iconPadding: CGFloat) -> ExpandableTextNodeLayout {
        var shouldRecalculate = false
        
        if currentString != string || constrainedSize != currentConstrainedSize {
            shouldRecalculate = true
        }
        
        if !shouldRecalculate, let currentLayout = self.currentLayout, prevAlignment == forcedAlignment {
            return currentLayout
        } else {
            let (lines, isTruncated) = getLayoutLines(string, textSize: constrainedSize, maxNumberOfLines: self.maxNumberOfLines)
            
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
                
                var glyphRunIndex = 0
                var glyphOffset: CGFloat = 0
                let lineString = line.attributedString
                let lineFrame: CGRect = self.expandedFrame(
                    lineSize: actualSize,
                    offsetY: offsetY,
                    containerBounds: containerBounds,
                    alignment: forcedAlignment ?? (lineString.length > 0 ? (lineString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment : .left),
                    isRTL: line.isRTL,
                    extraPadding: iconPadding
                )
                
                let sequence: [EnumeratedSequence<[NSRange]>.Element]
                if line.isRTL && !typeSetterWasRTL {
                    sequence = line.glyphRunsRanges.enumerated().sorted(by: { $0.element.location < $1.element.location })
                } else {
                    sequence = line.glyphRunsRanges.enumerated().map { $0 }
                }
                for (index, glyphRunRange) in sequence {
                    let glyphRun = line.glyphRuns[index]
                    let absoluteRange = glyphRunRange
                    var secondaryOffset: CGFloat = 0
                    var xOffset = CTLineGetOffsetForStringIndex(line.ctLine, absoluteRange.location - line.lineRange.location, &secondaryOffset)
                    
                    let glyphWidth = CTRunGetTypographicBounds(glyphRun, CFRangeMake(0, 0), nil, nil, nil)
                    if line.isRTL && lineIndex > 0 && !prevLineIsRTL {
                        xOffset = line.frame.width - glyphOffset - glyphWidth
                    } else {
                        xOffset = glyphOffset
                    }
                    
                    glyphOffset += glyphWidth
                    
                    let expandedFrame = CGRect(x: xOffset + lineFrame.origin.x, y: offsetY, width: glyphWidth, height: actualSize.height)
                    rangeExpandedFrames[absoluteRange] = expandedFrame
                    glyphRunIndex += absoluteRange.length
                }
                offsetY += actualSize.height + lineSpacing
                prevLineIsRTL = line.isRTL
            }
            
            return ExpandableTextNodeLayout(rangeToFrame: rangeExpandedFrames, constrainedSize: constrainedSize, alignment: forcedAlignment ?? .left, isTruncated: isTruncated/*textNodeLayout.truncated*/, lines: lines)
        }
    }
    
    fileprivate func updateIfNeeded(string: NSAttributedString, expandedLayout: ExpandableTextNodeLayout, expansionFraction: CGFloat, needsExpansionLayoutUpdate: Bool, forceRemake: Bool = false, extraIconPadding: CGFloat, transition: ContainedViewLayoutTransition) -> CGSize {
        var shouldRemake = forceRemake
        
        if currentString != string || expandedLayout.rangeToFrame != currentLayout?.rangeToFrame {
            shouldRemake = true
        }
        if currentString != string {
            self.singleLineInfo = getLayoutLines(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)).0.first
        }
        currentString = string
        currentConstrainedSize = expandedLayout.constrainedSize
        let prevLayout = self.currentLayout
        currentLayout = expandedLayout
        prevAlignment = expandedLayout.alignment
        
        if !shouldRemake {
            if needsExpansionLayoutUpdate {
                self.updateExpansion(fraction: expansionFraction, changeStringWeight: false, extraIconPadding: extraIconPadding, transition: transition)
            }
        } else {
            blockExpansionUpdate = false
            // Only this specific (yet apparentely common) case. For more general would need to keep track of each symbol
            if transition.isAnimated, let prevLayout, prevLayout.lines.count > 1 && expandedLayout.lines.count == 1 {
                self.updateExpansion(fraction: 0, changeStringWeight: false, usingLayout: prevLayout, usingContainerWidth: self.currentExpandedTotalSize?.width, extraIconPadding: extraIconPadding, transition: transition)
                blockExpansionUpdate = true
                
                let animationDuration = transition.animation()?.duration ?? .zero
                let remakeThreshold: Double = 0.6
                
                DispatchQueue.main.asyncAfter(deadline: .now() + animationDuration * remakeThreshold) { [weak self] in
                    self?.transitionAnimation = nil
                    self?.blockExpansionUpdate = false
                    // Forcing remake
                    _ = self?.updateIfNeeded(
                        string: string,
                        expandedLayout: expandedLayout,
                        expansionFraction: expansionFraction,
                        needsExpansionLayoutUpdate: true,
                        forceRemake: true,
                        extraIconPadding: extraIconPadding,
                        transition: .animated(duration: (1 - remakeThreshold) * animationDuration, curve: .easeInOut)
                    )
                }
            } else if transition.isAnimated, let prevLayout, prevLayout.lines.count == 1 && expandedLayout.lines.count > 1 {
                textFragmentsNodes.forEach { $0.removeFromSupernode() }
                textFragmentsNodes = []
                
                for (_, (range, _)) in expandedLayout.rangeToFrame.sorted(by: { $0.key.location < $1.key.location }).enumerated() {
                    let substring = string.attributedSubstring(from: range)
                    let textNode = ImmediateTextNode()
                    textNode.displaysAsynchronously = false
                    textNode.attributedText = substring
                    textNode.textAlignment = .natural
                    textNode.maximumNumberOfLines = 1
                    textNode.layer.masksToBounds = false
                    _ = textNode.updateLayout(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
                    textFragmentsNodes.append(textNode)
                    textContainerNode.addSubnode(textNode)
                }
                
                self.updateExpansion(fraction: 0, changeStringWeight: false, extraIconPadding: extraIconPadding, transition: .immediate)
                _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: expansionFraction, needsExpansionLayoutUpdate: true, extraIconPadding: extraIconPadding, transition: transition)
            } else {
                // Aligning only by the first
                let currentFirstFrame = textFragmentsNodes.first?.frame
                textFragmentsNodes.forEach { $0.removeFromSupernode() }
                textFragmentsNodes = []
                
                for (index, (range, frame)) in expandedLayout.rangeToFrame.sorted(by: { $0.key.location < $1.key.location }).enumerated() {
                    let substring = string.attributedSubstring(from: range)
                    let textNode = ImmediateTextNode()
                    textNode.displaysAsynchronously = false
                    textNode.attributedText = substring
                    textNode.textAlignment = .natural
                    textNode.maximumNumberOfLines = 1
                    textNode.layer.masksToBounds = false
                    _ = textNode.updateLayout(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
                    if index == 0, let currentFirstFrame, currentFirstFrame.size != .zero {
                        textNode.frame = CGRect(origin: currentFirstFrame.origin, size: frame.size)
                    } else {
                        textNode.frame = frame
                    }
                    textFragmentsNodes.append(textNode)
                    textContainerNode.addSubnode(textNode)
                }
                
                if let prevExpansion = self.prevExpansion, abs(prevExpansion - expansionFraction) > .ulpOfOne {
                    _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: prevExpansion, needsExpansionLayoutUpdate: true, extraIconPadding: extraIconPadding, transition: transition)
                }
                _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: expansionFraction, needsExpansionLayoutUpdate: true, extraIconPadding: extraIconPadding, transition: transition)
            }
        }
        
        if !shouldRemake, let currentExpandedTotalSize = self.currentExpandedTotalSize {
            return currentExpandedTotalSize
        } else {
            let totalSize: CGSize = expandedLayout.lines.reduce(CGSize.zero) {
                return CGSize(
                    width: max($0.width, min($1.frame.width, expandedLayout.constrainedSize.width)),
                    height: $0.height + $1.frame.height)
            }
            self.currentExpandedTotalSize = totalSize
            return totalSize
        }
    }
    
    func updateExpansion(fraction expansionFraction: CGFloat, changeStringWeight: Bool, usingLayout layout: ExpandableTextNodeLayout? = nil, usingContainerWidth containerWidth: CGFloat? = nil, extraIconPadding: CGFloat, transition: ContainedViewLayoutTransition) {
        guard !self.blockExpansionUpdate else { return }
        guard let expandedLayout = layout ?? self.currentLayout else { return }
        let singleLineInfo: LayoutLine
        
        if changeStringWeight && self.shouldReweightString && self.shouldChangeSpacingForReweight {
            guard
                let _adjustedString = self.currentString.flatMap({ reweightString(string: $0, weight: 1/* - expansionFraction*/, in: nil) }),
                let _singleLineInfo = getLayoutLines(_adjustedString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).0.first
            else { return }
            singleLineInfo = _singleLineInfo
            self.singleInfoReweight = singleLineInfo
        } else {
            guard let currentString = self.currentString,
                  let _singleLineInfo = self.singleLineInfo ?? getLayoutLines(currentString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).0.first
            else { return }
            singleLineInfo = _singleLineInfo
            self.singleLineInfo = singleLineInfo
        }
        
        let sortedFrames = expandedLayout.rangeToFrame.sorted(by: { $0.key.location < $1.key.location }).map { $0 }
        
        var rtlAdjustment: CGFloat = 0.0
        let firstLineIsRTL = singleLineInfo.isRTL
        
        if firstLineIsRTL {
            let currentContainerWidth = containerWidth ?? textContainerNode.bounds.width
            rtlAdjustment = max(singleLineInfo.frame.width - currentContainerWidth, 0.0)
        }
        
        let newWeight = 1 - expansionFraction
        for (index, (range, frame)) in sortedFrames.enumerated() {
            let textFragmentNode = self.textFragmentsNodes[index]
            let currentProgressFrame: CGRect
            let expandedFrame = frame
            if changeStringWeight && shouldReweightString {
                let _ = reweightString(string: textFragmentNode.attributedText ?? NSAttributedString(string: ""), weight: newWeight, in: textFragmentNode)
            } else {
                textFragmentNode.textStroke = nil
                textFragmentNode.extraGlyphSpacing = nil
            }
            
            if expansionFraction == 1 {
                currentProgressFrame = expandedFrame
            } else {
                let startIndexOfSubstring = range.location
                var secondaryOffset: CGFloat = 0.0
                var offsetX = floor(CTLineGetOffsetForStringIndex(singleLineInfo.ctLine, startIndexOfSubstring, &secondaryOffset))
                
                secondaryOffset = floor(secondaryOffset)
                offsetX = secondaryOffset
                let actualSize = expandedFrame.size
                
                if let glyphRangeIndex = singleLineInfo.glyphRunsRanges.firstIndex(where: { $0.location == range.location }), CTRunGetStatus(singleLineInfo.glyphRuns[glyphRangeIndex]).contains(.rightToLeft) {
                    let glyphRun = singleLineInfo.glyphRuns[glyphRangeIndex]
                    var positions = [CGPoint].init(repeating: .zero, count: 1)
                    
                    CTRunGetPositions(glyphRun, CFRangeMake(0, 1), &positions)
                    if range.length > 0 {
                        let pos = positions[0]
                        offsetX = pos.x
                    }
                }

                let collapsedFrame = CGRect(
                    x: offsetX - rtlAdjustment,
                    y: 0,
                    width: actualSize.width * (shouldChangeSpacingForReweight ? 1.1 : 1),
                    height: actualSize.height)
                
                let yProgress = sqrt(1 - (expansionFraction - 1) * (expansionFraction - 1))
                let xProgress = expansionFraction // 1 - sqrt(1 - progress * progress)
                currentProgressFrame = CGRect(
                    x: expandedFrame.origin.x * xProgress - collapsedFrame.origin.x * (xProgress - 1),
                    y: expandedFrame.origin.y * yProgress - collapsedFrame.origin.y * (yProgress - 1),
                    width: expandedFrame.width * expansionFraction - collapsedFrame.width * (expansionFraction - 1),
                    height: expandedFrame.height * expansionFraction - collapsedFrame.height * (expansionFraction - 1)
                )
            }
            _ = textFragmentNode.updateLayout(.init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            transition.updateFrame(node: textFragmentNode, frame: CGRect(origin: currentProgressFrame.origin, size: CGSize(width: currentProgressFrame.width, height: expandedFrame.height)))
        }
        
        prevExpansion = expansionFraction
        updateContainerFading(extraIconPadding: extraIconPadding, transition: transition)
    }
    
    private func reweightString(string: NSAttributedString, weight: CGFloat, in node: ImmediateTextNode?) -> NSAttributedString {
        guard shouldReweightString else {
            return string
        }
        
        guard string.length > 0, let strokeColor = string.attribute(.foregroundColor, at: 0, effectiveRange: nil) as? UIColor
        else { return string }
        let nodeLastWeight = node?.textStroke?.1
        
        if let lastWeight = nodeLastWeight {
            let underOptimalThreshold = !shouldChangeSpacingForReweight && abs(lastWeight - weight) < 0.15 && (abs(1.0 - weight) > .ulpOfOne || weight > .ulpOfOne)
            if underOptimalThreshold || abs(lastWeight - weight) < .ulpOfOne {
                return string
            }
        }
        
        if weight > CGFloat.ulpOfOne {
            let strokeRegularToSemiboldCoeff: CGFloat = 0.8
            let width = weight * strokeRegularToSemiboldCoeff
            node?.textStroke = (strokeColor, width)
            node?.cachedLayout?.updateTextStroke((strokeColor, width))
        } else {
            node?.textStroke = nil
            node?.cachedLayout?.updateTextStroke(nil)
        }
        
        let reweightString = NSMutableAttributedString(attributedString: string)
        let stringRange = NSRange.init(location: 0, length: reweightString.length)
        // Faking weight with stroke
        if weight > .ulpOfOne {
            if shouldChangeStrokeForReweight {
//                reweightString.addAttribute(.strokeColor, value: strokeColor, range: stringRange)
                // Assuming the passed weight varies from actual base value to 1 representing final value (from regular to semibold omitting thinner and thicker values)
//                let strokeRegularToSemiboldCoeff: CGFloat = 2.0
//                reweightString.addAttribute(.strokeWidth, value: -weight * strokeRegularToSemiboldCoeff, range: stringRange)
            }
            if shouldChangeSpacingForReweight {
                if let currentFont = string.attribute(.font, at: 0, effectiveRange: nil) as? UIFont {
                    let newFont = UIFont.systemFont(ofSize: currentFont.pointSize, weight: .semibold)
                    reweightString.addAttribute(.font, value: newFont, range: stringRange)
                }
                if weight > CGFloat.ulpOfOne {
                    node?.extraGlyphSpacing = weight * 1.0
                } else {
                    node?.extraGlyphSpacing = nil
                }
//                let kernRegularToSemiboldCoeff: CGFloat = 1.0
//                reweightString.addAttribute(.kern, value: weight * kernRegularToSemiboldCoeff, range: stringRange)
            }
        } else {
//            reweightString.removeAttribute(.strokeColor, range: stringRange)
//            reweightString.removeAttribute(.strokeWidth, range: stringRange)
//            reweightString.removeAttribute(.kern, range: stringRange)
            node?.extraGlyphSpacing = nil
        }
        
        // Requesting update with textStroke
        node?.contents = nil
        node?.setNeedsDisplay()
        
        return reweightString
    }
    
    private func expandedFrame(lineSize actualSize: CGSize, offsetY: CGFloat, containerBounds: CGRect, alignment: NSTextAlignment?, isRTL: Bool, extraPadding: CGFloat) -> CGRect {
        let lineOriginX: CGFloat
        let extraPadding: CGFloat = 0
        let lineExtraOffset: CGFloat
        if isRTL {
            lineExtraOffset = max(actualSize.width - containerBounds.width, 0.0)
        } else {
            lineExtraOffset = max(actualSize.width - containerBounds.width, 0.0)
        }
        let limitedSize = CGSize(width: min(actualSize.width, containerBounds.width), height: actualSize.height)
        
        switch alignment {
        case .left:
            if isRTL {
                lineOriginX = containerBounds.width - actualSize.width - extraPadding
            } else {
                lineOriginX = 0.0
            }
        case .right:
            if isRTL {
                lineOriginX = 0
            } else {
                lineOriginX = containerBounds.width - actualSize.width
            }
        case .center, .none:
            if isRTL {
                lineOriginX = (containerBounds.width - limitedSize.width) / 2 - lineExtraOffset
            } else {
                lineOriginX = (containerBounds.width - limitedSize.width) / 2
            }
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

/*private */func getLayoutLines(_ attStr: NSAttributedString, textSize: CGSize, maxNumberOfLines: Int = .max) -> ([LayoutLine], isTruncated: Bool) {
    var linesArray = [LayoutLine]()
    
    let frameSetter: CTFramesetter = CTFramesetterCreateWithAttributedString(attStr as CFAttributedString)
    let path: CGMutablePath = CGMutablePath()
    path.addRect(CGRect(x: 0, y: 0, width: textSize.width, height: 100000), transform: .identity)
    let frame: CTFrame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, 0), path, nil)
    guard let allLines = CTFrameGetLines(frame) as? [Any], !allLines.isEmpty else { return (linesArray, isTruncated: false) }
    
    // Combine exceeding lines into last line
    let lines = allLines[0..<min(allLines.count, maxNumberOfLines)]
    
    if allLines.count > maxNumberOfLines, let lastLine = lines.last {
        let lineRange: CFRange = CTLineGetStringRange(lastLine as! CTLine)
        let lastVisibleRange = NSRange(location: lineRange.location, length: lineRange.length)
        
        let lastLineRangeWithExcess = NSRange(location: lastVisibleRange.location, length: attStr.length - lastVisibleRange.location)
        let lastString = attStr.attributedSubstring(from: lastLineRangeWithExcess)
        
        let unaffectedString = attStr.attributedSubstring(from: NSRange(location: 0, length: lastVisibleRange.location))
        let firstLines: [LayoutLine]
        if lastVisibleRange.location > 0 {
            (firstLines, _) = getLayoutLines(unaffectedString, textSize: textSize)
        } else {
            firstLines = []
        }
        
        let (lastLines, _) = getLayoutLines(lastString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
        let lastLine = lastLines.first
            .flatMap { line in
                return LayoutLine(attributedString: line.attributedString, isRTL: line.isRTL, frame: line.frame, ctLine: line.ctLine, lineRange: NSRange(location: lastVisibleRange.location, length: attStr.length - lastVisibleRange.location), glyphRuns: line.glyphRuns, glyphRunsRanges: line.glyphRunsRanges.map { NSRange(location: $0.location + lastVisibleRange.location, length: $0.length) })
            }
            .map { [$0] } ?? lastLines
        return (firstLines + lastLine, isTruncated: true)
    } else {
        let font: CTFont
        if attStr.length > 0, let stringFont = attStr.attribute(NSAttributedString.Key.font, at: 0, effectiveRange: nil) {
            font = stringFont as! CTFont
        } else {
            font = UIFont.systemFont(ofSize: 30.0)
        }
        
        let fontAscent = CTFontGetAscent(font)
        let fontDescent = CTFontGetDescent(font)
        let fontLineHeight: CGFloat = floor(fontAscent + fontDescent)
        
        for line in lines {
            // TODO: remove trailing spaces
            let lineRef = line as! CTLine
            let lineRange: CFRange = CTLineGetStringRange(lineRef)
            let range = NSRange(location: lineRange.location, length: lineRange.length)
            let lineString = attStr.attributedSubstring(from: range)
            
            let lineOriginY: CGFloat = 0
            let headIndent: CGFloat = 0
            
            let lineCutoutOffset: CGFloat = 0
            
            let lineConstrainedSizeWidth = textSize.width
            let whitespaceWidth = CTLineGetTrailingWhitespaceWidth(lineRef)
            let lineWidth = min(lineConstrainedSizeWidth, ceil(CGFloat(CTLineGetTypographicBounds(lineRef, nil, nil, nil) - whitespaceWidth)))
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
        return (linesArray, isTruncated: false)
    }
}

// MARK: - Container

final class ExpandablePeerTitleContainerNode: ASDisplayNode {
    private final class GradientFadeMask: CALayer {
        let solidArea = CALayer()
        let gradientLayer = CAGradientLayer()
    }
    
    private var allAlignedBy: AnyHashable?
    
    private let fadableContainerNode = ASDisplayNode()
    private let gradientFadeMask = GradientFadeMask()
    
    private(set) var accessoryViews: [AnyHashable: UIView] = [:]
    
    private(set) var textSubnodes: [AnyHashable: ExpandablePeerTitleTextNode] = [:]
    var isTransitioning: Bool = false
    private(set) var lastMainLayout: ExpandablePeerTitleTextNode.ExpandableTextNodeLayout?
    
    func update(states: [AnyHashable: ExpandablePeerTitleTextNodeState], mainState: AnyHashable?, constrainedSize: CGSize, textExpansionFraction: CGFloat, isAvatarExpanded: Bool, needsExpansionLayoutUpdate: Bool, iconPadding: CGFloat, transition: ContainedViewLayoutTransition) -> [AnyHashable: MultiScaleTextLayout] {
        var commonExpandedLayout: ExpandablePeerTitleTextNode.ExpandableTextNodeLayout? = nil
        
        var mainLayout: MultiScaleTextLayout?
        var result: [AnyHashable: MultiScaleTextLayout] = [:]
        self.allAlignedBy = mainState
        
        if let allAlignedBy = mainState {
            commonExpandedLayout = textSubnodes[allAlignedBy]?.getExpandedLayout(string: states[allAlignedBy]?.string ?? .init(), forcedAlignment: isAvatarExpanded ? .left : .center, constrainedSize: constrainedSize, iconPadding: iconPadding)
            lastMainLayout = commonExpandedLayout
        }
        
        for (key, state) in states {
            guard let node = textSubnodes[key], let layout = commonExpandedLayout ?? textSubnodes[key]?.getExpandedLayout(string: state.string, forcedAlignment: isAvatarExpanded ? .left : .center, constrainedSize: constrainedSize, iconPadding: iconPadding) else {
                continue
            }
            let size = node.updateIfNeeded(string: state.string, expandedLayout: layout, expansionFraction: textExpansionFraction, needsExpansionLayoutUpdate: needsExpansionLayoutUpdate, extraIconPadding: iconPadding, transition: transition)
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
                    node.updateTextFrame(CGRect(origin: CGPoint(x: mainBounds.minX, y: mainBounds.minY + floor((mainBounds.height - nodeLayout.size.height) / 2.0)), size: nodeLayout.size), extraIconPadding: iconPadding, transition: transition)
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
    
    func updateFading(solidWidth: CGFloat, containerWidth: CGFloat, height: CGFloat, offset: CGFloat, extraIconPadding: CGFloat, transition: ContainedViewLayoutTransition) {
        self.textSubnodes.forEach { $0.value.updateContainerFading(extraIconPadding: extraIconPadding, transition: transition) }
        
        if !transition.isAnimated {
            CATransaction.begin()
            CATransaction.setDisableActions(true)
        }
        defer {
            if !transition.isAnimated {
                CATransaction.commit()
            }
        }
        gradientFadeMask.removeFromSuperlayer()
        guard let allAlignedBy,
              let string = self.textSubnodes[allAlignedBy]?.currentString,
              let singleLineInfo = self.textSubnodes[allAlignedBy]?.singleLineInfo ?? getLayoutLines(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).0.first
        else { return }
        
        let gradientInset: CGFloat = 0
        let gradientRadius: CGFloat = 30
        
        let solidPartLayer = gradientFadeMask.solidArea
        solidPartLayer.backgroundColor = UIColor.blue.cgColor
        let solidFrame: CGRect
        if singleLineInfo.isRTL {
            let adjustForRTL: CGFloat = 12
            let safeSolidWidth: CGFloat = containerWidth + adjustForRTL
            solidFrame = CGRect(
                origin: CGPoint(x: containerWidth - solidWidth, y: 0),
                size: CGSize(width: safeSolidWidth, height: height))
        } else {
            solidFrame = CGRect(
                origin: .zero,
                size: CGSize(width: solidWidth + gradientInset, height: height))
        }
        if solidPartLayer.superlayer == nil {
            gradientFadeMask.addSublayer(solidPartLayer)
        }
        
        transition.updateFrame(layer: solidPartLayer, frame: solidFrame)
        
        let gradientLayer = gradientFadeMask.gradientLayer
        gradientLayer.colors = [UIColor.blue.cgColor, UIColor.clear.cgColor]
        
        let gradientFrame: CGRect
        
        if singleLineInfo.isRTL {
            gradientLayer.startPoint = CGPoint(x: 1, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 0, y: 0.5)
            gradientFrame = CGRect(x: solidPartLayer.frame.minX - gradientRadius, y: 0, width: gradientRadius, height: height)
        } else {
            gradientLayer.startPoint = CGPoint(x: 0, y: 0.5)
            gradientLayer.endPoint = CGPoint(x: 1, y: 0.5)
            var adjustmentCoof: CGFloat { 1.0 }
            gradientFrame = CGRect(x: solidWidth + gradientInset, y: 0, width: gradientRadius * adjustmentCoof, height: height)
        }
        
        transition.updateFrame(layer: gradientLayer, frame: gradientFrame)
        if gradientLayer.superlayer == nil {
            gradientFadeMask.addSublayer(gradientLayer)
        }
        gradientFadeMask.masksToBounds = false
        let offsetX: CGFloat
        if singleLineInfo.isRTL {
            offsetX = 0
        } else {
            offsetX = 0
        }
        transition.updateFrame(layer: gradientFadeMask, frame: CGRect(x: -containerWidth / 2 + offsetX + offset, y: -height / 2, width: 0.0, height: height))
        fadableContainerNode.layer.mask = gradientFadeMask
    }
    
    func addAccessory(for state: AnyHashable, accessoryView: UIView) {
        accessoryViews[state]?.removeFromSuperview()
        accessoryViews[state] = accessoryView
        view.addSubview(accessoryView)
    }
    
    init(stateKeys: [AnyHashable], order: [AnyHashable: Int]?) {
        self.textSubnodes = Dictionary(stateKeys.map { ($0, ExpandablePeerTitleTextNode()) }, uniquingKeysWith: { lhs, _ in lhs })
        
        super.init()
        
        addSubnode(fadableContainerNode)
        
        let orderedNodes: [ExpandablePeerTitleTextNode]
        if let order {
            orderedNodes = self.textSubnodes.sorted(by: { a, b in order[a.key] ?? -1 < order[b.key] ?? -1 }).map(\.value)
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

