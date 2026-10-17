//
//  SkiaTextBlob.swift
//  NucleantSkia
//
import CSkia

/// SkTextBlob — runs of positioned glyphs, each run with its font: text
/// laid out once and drawn as often as needed.
public protocol SkiaTextBlob {
    var base: OpaquePointer { get }
}

public extension SkiaTextBlob {

    /// Conservative bounds of everything in it, from its origin.
    func bounds() -> (pos: SIMD2<Float>, size: SIMD2<Float>) {
        var rect = cskia_rect()
        cskia_text_blob_get_bounds(base, &rect)
        return (rect.pos, rect.size)
    }

    /// Where the glyphs cross the horizontal band `upper`…`lower` (relative
    /// to the baseline), as x ranges — what an underline skips.
    func getIntercepts(upper: Float, lower: Float) -> [ClosedRange<Float>] {
        intercepts(upper: upper, lower: lower, paint: nil)
    }
    func getIntercepts<P: SkiaPaint>(upper: Float, lower: Float, paint: P) -> [ClosedRange<Float>] {
        intercepts(upper: upper, lower: lower, paint: paint.base)
    }

    private func intercepts(upper: Float, lower: Float, paint: OpaquePointer?) -> [ClosedRange<Float>] {
        let count = cskia_text_blob_get_intercepts(base, upper, lower, nil, 0, paint)
        guard count > 0 else { return [] }
        var values = [Float](repeating: 0, count: Int(count))
        _ = cskia_text_blob_get_intercepts(base, upper, lower, &values, count, paint)
        return stride(from: 0, to: values.count - 1, by: 2).map { min(values[$0], values[$0 + 1])...max(values[$0], values[$0 + 1]) }
    }
}

public final class SkTextBlob: SkiaTextBlob {
    public let base: OpaquePointer

    init(adopting base: OpaquePointer) { self.base = base }

    deinit { cskia_text_blob_unref(base) }

    /// `text` in one run with `font`, from (0, 0); nil for no glyphs.
    public convenience init?<Font: SkiaFont>(text: String, font: Font) {
        var text = text
        let made = text.withUTF8 { utf8 in
            utf8.withMemoryRebound(to: CChar.self) { cskia_text_blob_make_from_text($0.baseAddress, $0.count, font.base) }
        }
        guard let made else { return nil }
        self.init(adopting: made)
    }

    /// Glyphs at their own positions.
    public convenience init?<Font: SkiaFont>(glyphs: [UInt16], positions: [SIMD2<Float>], font: Font) {
        precondition(glyphs.count == positions.count, "one position per glyph")
        let xy = positions.flatMap { [$0.x, $0.y] }
        guard let made = cskia_text_blob_make_from_pos_glyphs(glyphs, xy, Int32(glyphs.count), font.base) else { return nil }
        self.init(adopting: made)
    }

    /// Glyphs at their own x on one baseline `y`.
    public convenience init?<Font: SkiaFont>(glyphs: [UInt16], xpos: [Float], y: Float, font: Font) {
        precondition(glyphs.count == xpos.count, "one x per glyph")
        guard let made = cskia_text_blob_make_from_pos_h_glyphs(glyphs, xpos, Int32(glyphs.count), y, font.base) else { return nil }
        self.init(adopting: made)
    }
}

/// SkTextBlobBuilder — a blob run by run, each with its own font.
public final class SkTextBlobBuilder {
    private let base: OpaquePointer

    public init() { base = cskia_text_blob_builder_new() }

    deinit { cskia_text_blob_builder_delete(base) }

    /// Glyphs laid one after another from `origin`.
    public func addRun<Font: SkiaFont>(_ glyphs: [UInt16], font: Font, origin: SIMD2<Float>) {
        cskia_text_blob_builder_add_run(base, font.base, glyphs, Int32(glyphs.count), origin.x, origin.y)
    }

    /// Glyphs at their own x, on baseline `y`.
    public func addRun<Font: SkiaFont>(_ glyphs: [UInt16], font: Font, xpos: [Float], y: Float) {
        precondition(glyphs.count == xpos.count, "one x per glyph")
        cskia_text_blob_builder_add_run_pos_h(base, font.base, glyphs, xpos, Int32(glyphs.count), y)
    }

    /// Glyphs at their own positions.
    public func addRun<Font: SkiaFont>(_ glyphs: [UInt16], font: Font, positions: [SIMD2<Float>]) {
        precondition(glyphs.count == positions.count, "one position per glyph")
        let xy = positions.flatMap { [$0.x, $0.y] }
        cskia_text_blob_builder_add_run_pos(base, font.base, glyphs, xy, Int32(glyphs.count))
    }

    /// The blob of the runs so far; the builder starts empty again. nil
    /// when there were none.
    public func make() -> SkTextBlob? {
        cskia_text_blob_builder_make(base).map(SkTextBlob.init(adopting:))
    }
}
