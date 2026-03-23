import Foundation
import zlib

enum ParseError: Error {
    case decompressionFailed
    case noSequenceFound
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Constants

// Premiere's internal tick rate (constant across all modern project versions)
private let kTicksPerSec: Double = 254_016_000_000

// Media type UUIDs used to identify video vs audio track groups in a Sequence
private let kVideoMedia = "228cda18-3625-4d2d-951e-348879e4ed93"
private let kAudioMedia = "80b8e3d5-6dca-4195-aefb-cb5f407ab009"

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Raw accumulated objects (phase 1)

private final class RSeq  { var uid=""; var name="Sequence"; var vgID = -1; var agID = -1 }
private final class RVTG  { var trackURefs = [String]() }
private final class RATG  { var trackURefs = [String]() }
private final class RVCT  { var itemRefs   = [Int]()    }   // VideoClipTrack
private final class RACT  { var itemRefs   = [Int]()    }   // AudioClipTrack
private final class RItem { var start=0.0; var end=0.0; var subClipRef = -1 }
private final class RSC   { var name = ""; var clipRef  = -1; var masterUID = "" }  // SubClip
private final class RMaster { var sourceClipRef = -1 }  // MasterClip
private final class RClip { var labelName = ""; var colorInt = -1 }  // VideoClip / AudioClip

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Parser

final class ProjectParser: NSObject, XMLParserDelegate {

    func parse(url: URL) throws -> [PremiereProject] {
        let raw = try Data(contentsOf: url)
        let xml  = (try? gunzip(raw)) ?? raw
        let p    = XMLParser(data: xml)
        p.delegate = self
        p.parse()
        let result = buildAll()
        if result.isEmpty { throw ParseError.noSequenceFound }
        return result
    }

    // ── Storage (keyed by ObjectID int or ObjectUID string) ──────────────────

    private var seqsOrdered  = [RSeq]()          // preserves document order
    private var seqsByUID    = [String: RSeq]()
    private var vtgs         = [Int: RVTG]()
    private var atgs         = [Int: RATG]()
    private var vcts         = [String: RVCT]()
    private var acts         = [String: RACT]()
    private var vitems       = [Int: RItem]()
    private var aitems       = [Int: RItem]()
    private var scs          = [Int: RSC]()
    private var vclips       = [Int: RClip]()
    private var masters      = [String: RMaster]()
    private var slotColorMap = [Int: Int]()       // slot id → colorInt from project-panel clips

    // ── Per-element current objects ──────────────────────────────────────────

    private var curSeq:    RSeq?
    private var curVTG:    (id: Int, obj: RVTG)?
    private var curATG:    (id: Int, obj: RATG)?
    private var curVCT:    (uid: String, obj: RVCT)?
    private var curACT:    (uid: String, obj: RACT)?
    private var curVI:     (id: Int, obj: RItem)?
    private var curAI:     (id: Int, obj: RItem)?
    private var curSC:     (id: Int, obj: RSC)?
    private var curClip:   (id: Int, obj: RClip)?
    private var curMaster: (uid: String, obj: RMaster)?

    // ── State flags ──────────────────────────────────────────────────────────

    private var inSeqTGs      = false   // inside Sequence > TrackGroups
    private var curTGFirst    = ""      // current seq-level TrackGroup's <First> value
    private var inVTGTracks   = false   // inside VideoTrackGroup > TrackGroup > Tracks
    private var inATGTracks   = false
    private var inVCTItems    = false   // inside VideoClipTrack > ClipItems > TrackItems
    private var inACTItems    = false
    private var inItemTI      = false   // inside *ClipTrackItem > TrackItem (timing)
    private var inVClipProps  = false   // inside VideoClip/AudioClip > Clip > Node > Properties
    private var inMasterClips = false   // inside MasterClip > Clips

    private var charBuf = ""

    // Depth tracking to detect element close events for the right instance
    private var depth     = 0
    private var seqD = -1; private var vtgD = -1; private var atgD = -1
    private var vctD = -1; private var actD = -1
    private var viD  = -1; private var aiD  = -1
    private var scD  = -1; private var vcD  = -1; private var masterD = -1

    // ── XMLParserDelegate ────────────────────────────────────────────────────

    func parser(_ p: XMLParser, didStartElement el: String,
                namespaceURI: String?, qualifiedName: String?,
                attributes a: [String: String]) {
        charBuf = ""; depth += 1

        switch el {

        // ── Sequence ─────────────────────────────────────────────────────────
        case "Sequence":
            if let uid = a["ObjectUID"] {
                let s = RSeq(); s.uid = uid; curSeq = s; seqD = depth
            }

        case "TrackGroups":
            if curSeq != nil { inSeqTGs = true }

        case "TrackGroup":
            if inSeqTGs { curTGFirst = "" }

        case "Second":
            // <Second ObjectRef="N"/> inside Sequence > TrackGroups > TrackGroup
            if inSeqTGs, let refStr = a["ObjectRef"], let ref = Int(refStr), let s = curSeq {
                if   curTGFirst == kVideoMedia { s.vgID = ref }
                else if curTGFirst == kAudioMedia { s.agID = ref }
            }

        // ── VideoTrackGroup / AudioTrackGroup ─────────────────────────────────
        case "VideoTrackGroup":
            if let idStr = a["ObjectID"], let id = Int(idStr) {
                curVTG = (id, RVTG()); vtgD = depth
            }

        case "AudioTrackGroup":
            if let idStr = a["ObjectID"], let id = Int(idStr) {
                curATG = (id, RATG()); atgD = depth
            }

        case "Tracks":
            if curVTG != nil { inVTGTracks = true }
            if curATG != nil { inATGTracks = true }

        case "Track":
            // <Track Index="N" ObjectURef="UUID"/> inside TrackGroup > Tracks
            if let uref = a["ObjectURef"] {
                if inVTGTracks, let vtg = curVTG { vtg.obj.trackURefs.append(uref) }
                if inATGTracks, let atg = curATG { atg.obj.trackURefs.append(uref) }
            }

        // ── VideoClipTrack / AudioClipTrack ───────────────────────────────────
        case "VideoClipTrack":
            if let uid = a["ObjectUID"] {
                curVCT = (uid, RVCT()); vctD = depth
            }

        case "AudioClipTrack":
            if let uid = a["ObjectUID"] {
                curACT = (uid, RACT()); actD = depth
            }

        case "ClipItems":
            // only set flags when actually building a track
            if curVCT != nil { inVCTItems = false }   // wait for TrackItems
            if curACT != nil { inACTItems = false }

        case "TrackItems":
            if curVCT != nil { inVCTItems = true }
            if curACT != nil { inACTItems = true }

        case "TrackItem":
            // Two meanings:
            // (A) <TrackItem Index="N" ObjectRef="M"/> inside ClipItems/TrackItems → ref
            // (B) <TrackItem Version="N"> inside ClipTrackItem → timing container
            if let refStr = a["ObjectRef"], let ref = Int(refStr) {
                if inVCTItems, let vct = curVCT { vct.obj.itemRefs.append(ref) }
                if inACTItems, let act = curACT { act.obj.itemRefs.append(ref) }
            } else if a["Version"] != nil {
                // timing container (inside VideoClipTrackItem or AudioClipTrackItem)
                if curVI != nil || curAI != nil { inItemTI = true }
            }

        // ── VideoClipTrackItem / AudioClipTrackItem ───────────────────────────
        case "VideoClipTrackItem":
            if let idStr = a["ObjectID"], let id = Int(idStr) {
                curVI = (id, RItem()); viD = depth
            }

        case "AudioClipTrackItem":
            if let idStr = a["ObjectID"], let id = Int(idStr) {
                curAI = (id, RItem()); aiD = depth
            }

        // ── SubClip ───────────────────────────────────────────────────────────
        case "MasterClip":
            if let uid = a["ObjectUID"] {
                // Full MasterClip definition
                curMaster = (uid, RMaster()); masterD = depth
            } else if let uref = a["ObjectURef"], let sc = curSC {
                // <MasterClip ObjectURef="..."/> inside SubClip → record the UID for fallback
                sc.obj.masterUID = uref
            }

        case "Clips":
            if curMaster != nil { inMasterClips = true }

        case "SubClip":
            if let idStr = a["ObjectID"], let id = Int(idStr) {
                // Full SubClip definition
                curSC = (id, RSC()); scD = depth
            } else if let refStr = a["ObjectRef"], let ref = Int(refStr) {
                // <SubClip ObjectRef="N"/> inside ClipTrackItem → set subClipRef
                if let vi = curVI { vi.obj.subClipRef = ref }
                if let ai = curAI { ai.obj.subClipRef = ref }
            }

        case "Clip":
            if let refStr = a["ObjectRef"], let ref = Int(refStr) {
                // <Clip ObjectRef="N"/> inside SubClip → sequence-level VideoClip
                if let sc = curSC { sc.obj.clipRef = ref }
                // <Clip Index="0" ObjectRef="N"/> inside MasterClip > Clips → source VideoClip
                if inMasterClips, a["Index"] == "0", let m = curMaster { m.obj.sourceClipRef = ref }
            }

        // ── VideoClip / AudioClip (for label info) ────────────────────────────
        case "VideoClip", "AudioClip":
            if let idStr = a["ObjectID"], let id = Int(idStr) {
                curClip = (id, RClip()); vcD = depth
            }

        case "Properties":
            if curClip != nil { inVClipProps = true }

        default: break
        }
    }

    func parser(_ p: XMLParser, foundCharacters s: String) { charBuf += s }

    func parser(_ p: XMLParser, didEndElement el: String,
                namespaceURI: String?, qualifiedName: String?) {
        let t = charBuf.trimmingCharacters(in: .whitespacesAndNewlines)
        charBuf = ""; depth -= 1

        switch el {

        case "First":
            if inSeqTGs { curTGFirst = t }

        case "Name":
            if let s = curSeq,           !t.isEmpty { s.name = t }
            if let sc = curSC,           !t.isEmpty { sc.obj.name = t }

        case "Start":
            if inItemTI {
                if let vi = curVI { vi.obj.start = Double(t) ?? 0 }
                if let ai = curAI { ai.obj.start = Double(t) ?? 0 }
            }

        case "End":
            if inItemTI {
                if let vi = curVI { vi.obj.end = Double(t) ?? 0 }
                if let ai = curAI { ai.obj.end = Double(t) ?? 0 }
            }

        case "asl.clip.label.name":
            if inVClipProps, let c = curClip { c.obj.labelName = t }

        case "asl.clip.label.color":
            if inVClipProps, let c = curClip, let v = Int(t) { c.obj.colorInt = v }

        // ── Close elements ────────────────────────────────────────────────────

        case "Sequence":
            if depth == seqD - 1, let s = curSeq {
                seqsOrdered.append(s); seqsByUID[s.uid] = s
                curSeq = nil; seqD = -1; inSeqTGs = false
            }

        case "TrackGroups":
            inSeqTGs = false

        case "VideoTrackGroup":
            if depth == vtgD - 1, let (id, obj) = curVTG {
                vtgs[id] = obj; curVTG = nil; vtgD = -1; inVTGTracks = false
            }

        case "AudioTrackGroup":
            if depth == atgD - 1, let (id, obj) = curATG {
                atgs[id] = obj; curATG = nil; atgD = -1; inATGTracks = false
            }

        case "Tracks":
            inVTGTracks = false; inATGTracks = false

        case "VideoClipTrack":
            if depth == vctD - 1, let (uid, obj) = curVCT {
                vcts[uid] = obj; curVCT = nil; vctD = -1
                inVCTItems = false
            }

        case "AudioClipTrack":
            if depth == actD - 1, let (uid, obj) = curACT {
                acts[uid] = obj; curACT = nil; actD = -1
                inACTItems = false
            }

        case "TrackItems":
            inVCTItems = false; inACTItems = false

        case "TrackItem":
            inItemTI = false

        case "VideoClipTrackItem":
            if depth == viD - 1, let (id, obj) = curVI {
                vitems[id] = obj; curVI = nil; viD = -1
            }

        case "AudioClipTrackItem":
            if depth == aiD - 1, let (id, obj) = curAI {
                aitems[id] = obj; curAI = nil; aiD = -1
            }

        case "SubClip":
            if depth == scD - 1, let (id, obj) = curSC {
                scs[id] = obj; curSC = nil; scD = -1
            }

        case "Clips":
            inMasterClips = false

        case "MasterClip":
            if depth == masterD - 1, let (uid, obj) = curMaster {
                masters[uid] = obj; curMaster = nil; masterD = -1
            }

        case "VideoClip", "AudioClip":
            if depth == vcD - 1, let (id, obj) = curClip {
                vclips[id] = obj; curClip = nil; vcD = -1; inVClipProps = false
            }

        case "Properties":
            inVClipProps = false

        default: break
        }
    }

    // ── Phase 2: build PremiereProject list ───────────────────────────────────

    private func buildAll() -> [PremiereProject] {
        buildSlotColorMap()
        return seqsOrdered.compactMap { buildProject($0) }
    }

    /// Populate slotColorMap from project-panel clips (MasterClip sources only).
    /// These are the clips whose colorInt was set when the user labeled them in the
    /// Project panel — giving us the "canonical" colorInt for each label slot.
    private func buildSlotColorMap() {
        for master in masters.values {
            guard master.sourceClipRef >= 0,
                  let clip = vclips[master.sourceClipRef],
                  clip.colorInt > 0, !clip.labelName.isEmpty,
                  let dot = clip.labelName.lastIndex(of: "."),
                  let id  = Int(clip.labelName[clip.labelName.index(after: dot)...]),
                  slotColorMap[id] == nil else { continue }
            slotColorMap[id] = clip.colorInt
        }
    }

    private func buildProject(_ seq: RSeq) -> PremiereProject? {
        let vTracks = buildVideoTracks(vgID: seq.vgID)
        let aTracks = buildAudioTracks(agID: seq.agID)
        guard !vTracks.isEmpty || !aTracks.isEmpty else { return nil }
        let dur = (vTracks + aTracks).flatMap(\.clips).map(\.endTime).max() ?? 60

        return PremiereProject(sequenceName: seq.name,
                               videoTracks: vTracks, audioTracks: aTracks,
                               duration: dur, fps: 25)
    }

    private func buildVideoTracks(vgID: Int) -> [Track] {
        guard vgID >= 0, let vtg = vtgs[vgID] else { return [] }
        return vtg.trackURefs.enumerated().compactMap { i, uid -> Track? in
            guard let vct = vcts[uid] else { return nil }
            let clips = vct.itemRefs.compactMap { ref -> Clip? in
                guard let item = vitems[ref], item.end > item.start else { return nil }
                let s = item.start / kTicksPerSec
                let e = item.end   / kTicksPerSec
                let sc       = scs[item.subClipRef]
                let name     = sc?.name ?? ""
                let (label, colorInt) = colorInfo(clipRef: sc?.clipRef ?? -1,
                                                  masterUID: sc?.masterUID ?? "",
                                                  fallback: .green)
                return Clip(name: name, startTime: s, endTime: e, label: label, colorInt: colorInt)
            }
            return clips.isEmpty ? nil : Track(name: "V\(i+1)", trackType: .video, clips: clips)
        }
    }

    private func buildAudioTracks(agID: Int) -> [Track] {
        guard agID >= 0, let atg = atgs[agID] else { return [] }
        return atg.trackURefs.enumerated().compactMap { i, uid -> Track? in
            guard let act = acts[uid] else { return nil }
            let clips = act.itemRefs.compactMap { ref -> Clip? in
                guard let item = aitems[ref], item.end > item.start else { return nil }
                let s = item.start / kTicksPerSec
                let e = item.end   / kTicksPerSec
                let sc       = scs[item.subClipRef]
                let name     = sc?.name ?? ""
                let (label, colorInt) = colorInfo(clipRef: sc?.clipRef ?? -1,
                                                  masterUID: sc?.masterUID ?? "",
                                                  fallback: .cerulean)
                return Clip(name: name, startTime: s, endTime: e, label: label, colorInt: colorInt)
            }
            return clips.isEmpty ? nil : Track(name: "A\(i+1)", trackType: .audio, clips: clips)
        }
    }

    /// Returns (label, colorInt) for a clip.
    /// Resolution order:
    ///   1. Sequence-level VideoClip's label name (if set)
    ///   2. MasterClip's project-panel source (when sequence clip has no label)
    ///   3. colorInt from slotColorMap — the canonical colorInt for this slot derived
    ///      from project-panel clips. Avoids using stale inherited colorInts that are
    ///      the same across clips with different slots (e.g. ColorTest Black Video clips).
    ///   4. -1 → fillHex falls back to label's built-in default hex
    private func colorInfo(clipRef: Int, masterUID: String, fallback: PremiereLabel) -> (PremiereLabel, Int) {
        let c: RClip?
        if clipRef >= 0, let seqClip = vclips[clipRef],
           !seqClip.labelName.isEmpty || seqClip.colorInt > 0 {
            c = seqClip
        } else if !masterUID.isEmpty,
                  let master = masters[masterUID], master.sourceClipRef >= 0 {
            c = vclips[master.sourceClipRef]
        } else {
            c = nil
        }
        guard let clip = c else { return (fallback, -1) }

        let label = labelFrom(clip, fallback: fallback)

        if label != .none,
           let dot = clip.labelName.lastIndex(of: "."),
           let slotID = Int(clip.labelName[clip.labelName.index(after: dot)...]) {
            return (label, slotColorMap[slotID] ?? -1)
        }
        return (label, -1)
    }

    private func labelFrom(_ clip: RClip, fallback: PremiereLabel) -> PremiereLabel {
        guard !clip.labelName.isEmpty,
              let dot = clip.labelName.lastIndex(of: "."),
              let id  = Int(clip.labelName[clip.labelName.index(after: dot)...]) else {
            return fallback
        }
        return .from(id: id)
    }
}

// ─────────────────────────────────────────────────────────────────────────────
// MARK: - Gzip decompression

private func gunzip(_ data: Data) throws -> Data {
    guard data.count > 18 else { throw ParseError.decompressionFailed }
    var out    = Data(capacity: data.count * 4)
    var stream = z_stream()
    let buf    = UnsafeMutablePointer<UInt8>.allocate(capacity: 65536)
    defer { buf.deallocate() }
    let rc: Int32 = data.withUnsafeBytes { ptr in
        guard let base = ptr.baseAddress else { return Z_MEM_ERROR }
        stream.next_in  = UnsafeMutablePointer(mutating: base.assumingMemoryBound(to: UInt8.self))
        stream.avail_in = uInt(data.count)
        return inflateInit2_(&stream, 47, ZLIB_VERSION, Int32(MemoryLayout<z_stream>.size))
    }
    guard rc == Z_OK else { throw ParseError.decompressionFailed }
    defer { inflateEnd(&stream) }
    repeat {
        stream.next_out  = buf; stream.avail_out = 65536
        let st = inflate(&stream, Z_SYNC_FLUSH)
        guard st == Z_OK || st == Z_STREAM_END else { throw ParseError.decompressionFailed }
        out.append(buf, count: 65536 - Int(stream.avail_out))
        if st == Z_STREAM_END { break }
    } while stream.avail_out == 0
    return out
}
