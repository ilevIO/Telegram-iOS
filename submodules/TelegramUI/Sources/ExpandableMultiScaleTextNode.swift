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

final class ExpandablePeerTitleTextNode: ASDisplayNode {
    struct ExpandableTextNodeLayout {
        let rangeToFrame: [NSRange: CGRect]
        let constrainedSize: CGSize
        let alignment: NSTextAlignment
        let isTruncated: Bool
        // Quick convenience, replace with more minimal
        let lines: [LayoutLine]
    }
    private(set) var currentString: NSAttributedString?
    private(set) var currentLayout: ExpandableTextNodeLayout?
    private(set) var currentExpansion: CGFloat?
    private(set) var currentConstrainedSize: CGSize?
    private var ctLine: CTLine?
    private var prevAlignment: NSTextAlignment?
    
    var textContainer: ASDisplayNode {
        maskedContainerNode
    }
    private let maskedContainerNode = ASDisplayNode()
    let textContainerNode = ASDisplayNode()
    private(set) var textFragmentsNodes: [ImmediateTextNode] = []
    
    var maxNumberOfLines: Int { 2 }
    
    private var maskLayerContainer: CALayer?
    
    private(set) var currentExpandedTotalSize: CGSize?
    private(set) var singleLineInfo: LayoutLine?
    /// Performance hit
    private var shouldReweightString: Bool { false }
    private var shouldChangeKernForReweight: Bool { false }
    private var shouldChangeStrokeForReweight: Bool { false }
    
    private var prevExpansion: CGFloat?
    
    override init() {
        super.init()
        
        self.addSubnode(maskedContainerNode)
        self.maskedContainerNode.addSubnode(textContainerNode)
    }
    
    func updateTextFrame(_ frame: CGRect) {
        maskedContainerNode.frame = frame
        textContainerNode.frame = maskedContainerNode.bounds
        
        updateContainerFading()
    }
    
    private func needsContainerFading(layout: ExpandableTextNodeLayout) -> Bool {
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
            
            var lastFrame: CGRect?
            if isRTL {
                lastFrame = textFragmentsNodes.last?.frame
            } else {
                if let lastNode = textFragmentsNodes.last {
                    lastFrame = CGRect(x: lastNode.frame.minX, y: lastNode.frame.minY, width: textContainerNode.bounds.width, height: lastNode.frame.height)
                }
            }
            
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
            let topLineHeight = bottomLineHeight
            let topLineWidth: CGFloat
            if isRTL {
                topLineWidth = max(textContainerNode.bounds.width, lastLineWidth) + 16.0
            } else {
                topLineWidth = textContainerNode.bounds.width
            }
            topSolidArea.frame = .init(x: 0, y: -collapseAdjustment, width: topLineWidth + collapseAdjustment * 2, height: topLineHeight + collapseAdjustment)
            if isRTL {
                bottomSolidArea.frame = .init(x: fadeRadius, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight)
                maskGradientLayer.frame = .init(x: 0, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight)
            } else {
                bottomSolidArea.frame = .init(x: 0, y: bottomY - bottomLineHeight, width: lastLineWidth - fadeRadius + collapseAdjustment, height: bottomLineHeight)
                maskGradientLayer.frame = .init(x: bottomSolidArea.frame.maxX, y: bottomY - bottomLineHeight, width: fadeRadius, height: bottomLineHeight)
            }
            
            maskGradientLayer.backgroundColor = UIColor.black.withAlphaComponent(1 - (self.prevExpansion ?? 0)).cgColor
            
            maskLayer.addSublayer(topSolidArea)
            maskLayer.addSublayer(bottomSolidArea)
            maskLayer.addSublayer(maskGradientLayer)
            textContainerNode.layer.mask = maskLayer
            maskLayerContainer = maskLayer
        } else {
            textContainerNode.layer.mask = nil
        }
    }
    
    func getExpandedLayout(string: NSAttributedString, forcedAlignment: NSTextAlignment?, constrainedSize: CGSize) -> ExpandableTextNodeLayout {
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
                    lineSize: CGSize(width: actualSize.width, height: actualSize.height), // actualSize.size,
                    offsetY: offsetY,
                    containerBounds: containerBounds,
                    alignment: forcedAlignment ?? (lineString.length > 0 ? (lineString.attribute(.paragraphStyle, at: 0, effectiveRange: nil) as? NSParagraphStyle)?.alignment : .left),
                    isRTL: line.isRTL
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
                    
                    // TODO: remove trailing/leading whitespaces
                    let glyphWidth = CTRunGetTypographicBounds(glyphRun, CFRangeMake(0, 0), nil, nil, nil)
                    if line.isRTL && lineIndex > 0 && !prevLineIsRTL {
                        xOffset = line.frame.width - glyphOffset - glyphWidth
                    } else if line.isRTL {
                        xOffset = glyphOffset
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
    
    func updateIfNeeded(string: NSAttributedString, expandedLayout: ExpandableTextNodeLayout, expansionFraction: CGFloat, needsExpansionLayoutUpdate: Bool, transition: ContainedViewLayoutTransition) -> CGSize {
        var shouldRemake = false
        
        if currentString != string || expandedLayout.rangeToFrame != currentLayout?.rangeToFrame {
            shouldRemake = true
        }
        if currentString != string {
            self.singleLineInfo = getLayoutLines(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude)).0.first
        }
        currentString = string
        currentConstrainedSize = expandedLayout.constrainedSize
        currentLayout = expandedLayout
        prevAlignment = expandedLayout.alignment
        
        if !shouldRemake {
            if needsExpansionLayoutUpdate {
                updateExpansion(fraction: expansionFraction, transition: transition)
            }
        } else {
            textFragmentsNodes.forEach { $0.removeFromSupernode() }
            textFragmentsNodes = []
            
            for (_, (range, _)) in expandedLayout.rangeToFrame.sorted(by: { $0.key.location < $1.key.location }).enumerated() {
                let substring = string.attributedSubstring(from: range)
                let textNode = ImmediateTextNode()
                textNode.displaysAsynchronously = false
                textNode.attributedText = substring
                textNode.textAlignment = .left
                textNode.maximumNumberOfLines = 1
                textNode.layer.masksToBounds = false
                    _ = textNode.updateLayout(CGSize(width: CGFloat.greatestFiniteMagnitude, height: .greatestFiniteMagnitude))
                textFragmentsNodes.append(textNode)
                textContainerNode.addSubnode(textNode)
            }
            
            if let prevExpansion = self.prevExpansion {
                _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: prevExpansion, needsExpansionLayoutUpdate: true, transition: .immediate)
            }
            _ = updateIfNeeded(string: string, expandedLayout: expandedLayout, expansionFraction: expansionFraction, needsExpansionLayoutUpdate: true, transition: transition)
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
    
    func updateExpansion(fraction expansionFraction: CGFloat, transition: ContainedViewLayoutTransition) {
        guard let expandedLayout = currentLayout else { return }
        let singleLineInfo: LayoutLine
        
        if shouldReweightString && shouldChangeKernForReweight {
            guard
                let _adjustedString = self.currentString.flatMap({ reweightString(string: $0, weight: 1 - expansionFraction, in: ImmediateTextNode()) }),
                let _singleLineInfo = getLayoutLines(_adjustedString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).0.first
            else { return }
            singleLineInfo = _singleLineInfo
        } else {
            guard let currentString = self.currentString,
                  let _singleLineInfo = self.singleLineInfo ?? getLayoutLines(currentString, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).0.first
            else { return }
            singleLineInfo = _singleLineInfo
        }
        
        self.singleLineInfo = singleLineInfo
        let sortedFrames = expandedLayout.rangeToFrame.sorted(by: { $0.key.location < $1.key.location }).map { $0 }
        
        var rtlAdjustment: CGFloat = 0.0
        let firstLineIsRTL = singleLineInfo.isRTL
        
        if firstLineIsRTL {
            let currentContainerWidth = textContainerNode.bounds.width
            rtlAdjustment = max(singleLineInfo.frame.width - currentContainerWidth, 0.0)
        }
        
        for (index, (range, frame)) in sortedFrames.enumerated() {
            let textFragmentsNode = self.textFragmentsNodes[index]
            let currentProgressFrame: CGRect
            let expandedFrame = frame
            let newWeight = 1 - expansionFraction
            let _ = reweightString(string: textFragmentsNode.attributedText!, weight: newWeight, in: textFragmentsNode)
            
            if expansionFraction == 1 {
                currentProgressFrame = expandedFrame
            } else {
                let startIndexOfSubstring = range.location
                var secondaryOffset: CGFloat = 0.0
                var offsetX = floor(CTLineGetOffsetForStringIndex(singleLineInfo.ctLine, startIndexOfSubstring, &secondaryOffset))
                secondaryOffset = floor(secondaryOffset)
                offsetX = secondaryOffset
                let actualSize = expandedFrame.size
                
                if let glyphRangeIndex = singleLineInfo.glyphRunsRanges.firstIndex(where: { $0.contains(range.location) }), CTRunGetStatus(singleLineInfo.glyphRuns[glyphRangeIndex]).contains(.rightToLeft) {
                    let glyphRun = singleLineInfo.glyphRuns[glyphRangeIndex]
                    let runRange = CTRunGetStringRange(glyphRun)
                    
                    let positions = UnsafeMutablePointer<CGPoint>.allocate(capacity: runRange.length)
                    
                    CTRunGetPositions(glyphRun, CFRangeMake(0, range.length), positions)
                    if range.length > 0 {
                        let pos = positions[0]
                        offsetX = pos.x
                    }
                    
                    positions.deallocate()
                }

                let collapsedFrame = CGRect(
                    x: offsetX - rtlAdjustment,
                    y: 0,
                    width: actualSize.width * (shouldChangeKernForReweight ? 1.1 : 1),
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
            
            _ = textFragmentsNode.updateLayout(.init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude))
            transition.updateFrame(node: textFragmentsNode, frame: CGRect(origin: currentProgressFrame.origin, size: CGSize(width: currentProgressFrame.width, height: expandedFrame.height)))
        }
        
        prevExpansion = expansionFraction
        updateContainerFading()
    }
    
    private func reweightString(string: NSAttributedString, weight: CGFloat, in node: ImmediateTextNode) -> NSAttributedString {
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
            
        guard pow(2, 2) == 4 else { return string }
        
        let reweightString = NSMutableAttributedString(attributedString: string)
        let stringRange = NSRange.init(location: 0, length: reweightString.length)
        // Faking weight with stroke
        if weight > 0 {
            if shouldChangeStrokeForReweight {
                reweightString.addAttribute(.strokeColor, value: strokeColor, range: stringRange)
                // Assuming the passed weight varies from actual base value to 1 representing final value (from regular to semibold omitting thinner and thicker values)
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
        node.attributedText = reweightString
        
        return reweightString
    }
    
    private func expandedFrame(lineSize actualSize: CGSize, offsetY: CGFloat, containerBounds: CGRect, alignment: NSTextAlignment?, isRTL: Bool) -> CGRect {
        let lineOriginX: CGFloat
        
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
                lineOriginX = containerBounds.width - actualSize.width // - lineExtraOffset
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
            if isRTL {
                lineOriginX = (containerBounds.width - limitedSize.width) / 2 - lineExtraOffset
            } else {
                lineOriginX = (containerBounds.width - limitedSize.width) / 2 // + lineExtraOffset
            }
        case .justified:
            lineOriginX = 0
        case .natural:
            if isRTL {
                lineOriginX = containerBounds.width - actualSize.width // - lineExtraOffset
            } else {
                lineOriginX = 0
            }
        default:
            if isRTL {
                lineOriginX = containerBounds.width - actualSize.width // - lineExtraOffset
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

private func getLayoutLines(_ attStr: NSAttributedString, textSize: CGSize, maxNumberOfLines: Int = .max) -> ([LayoutLine], isTruncated: Bool) {
    var linesArray = [LayoutLine]()
    
    let frameSetter: CTFramesetter = CTFramesetterCreateWithAttributedString(attStr as CFAttributedString)
    let path: CGMutablePath = CGMutablePath()
    path.addRect(CGRect(x: 0, y: 0, width: textSize.width, height: 100000), transform: .identity)
    let frame: CTFrame = CTFramesetterCreateFrame(frameSetter, CFRangeMake(0, 0), path, nil)
    guard let allLines = CTFrameGetLines(frame) as? [Any], !allLines.isEmpty else { return (linesArray, isTruncated: false) }
    
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
            (firstLines, _) = getLayoutLines(unaffectedString, textSize: textSize)
        } else {
            firstLines = []
        }
        // MARK: maybe here runs get broken
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
            font = UIFont.systemFont(ofSize: 30)
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
        return (linesArray, isTruncated: false)
    }
}

// MARK: - Container

final class ExpandablePeerTitleContainerNode: ASDisplayNode {
    let invertedContainerNode: ASDisplayNode = ASDisplayNode()
    
    var allAlignedBy: AnyHashable?
    var textSubnodes: [AnyHashable: ExpandablePeerTitleTextNode] = [:]
    var isTransitioning: Bool = false
    
    var trailingFadeIntensity: CGFloat = 0
    let trailingFadeMaskLayer = CALayer()
    var lastMainLayout: ExpandablePeerTitleTextNode.ExpandableTextNodeLayout?
    var gradientFadeMask = CALayer()
    
    private let fadableContainerNode = ASDisplayNode()
    private(set) var accessoryViews: [AnyHashable: UIView] = [:]
    
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
    
    func updateFading(solidWidth: CGFloat, containerWidth: CGFloat, height: CGFloat, offset: CGFloat) {
        self.textSubnodes.forEach { $0.value.updateContainerFading() }
        
        gradientFadeMask.removeFromSuperlayer()
        guard let allAlignedBy,
              let string = self.textSubnodes[allAlignedBy]?.currentString,
              let singleLineInfo = self.textSubnodes[allAlignedBy]?.singleLineInfo ?? getLayoutLines(string, textSize: .init(width: CGFloat.greatestFiniteMagnitude, height: CGFloat.greatestFiniteMagnitude)).0.first
        else { return }
        
        gradientFadeMask = .init()
        let gradientInset: CGFloat = 0
        let gradientRadius: CGFloat = 30
        
        let solidPartLayer = CALayer()
        solidPartLayer.backgroundColor = UIColor.blue.cgColor
        if singleLineInfo.isRTL {
            let adjustForRTL: CGFloat = 12
            let safeSolidWidth: CGFloat = containerWidth + adjustForRTL
            solidPartLayer.frame = CGRect(
                origin: CGPoint(x: containerWidth - solidWidth, y: 0),
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
            var adjustmentCoof: CGFloat { 1.0 }
            gradientLayer.frame = CGRect(x: solidWidth + gradientInset, y: 0, width: gradientRadius * adjustmentCoof, height: height)
        }
        
        gradientFadeMask.addSublayer(gradientLayer)
        gradientFadeMask.masksToBounds = false
        let offsetX: CGFloat
        if singleLineInfo.isRTL {
            offsetX = 0
        } else {
            offsetX = 0
        }
        gradientFadeMask.frame = CGRect(x: -containerWidth / 2 + offsetX + offset, y: -height / 2, width: 0.0, height: height)
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

