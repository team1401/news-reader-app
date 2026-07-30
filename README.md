# Private Native News Reader

A private iPhone/iPad news reader with configurable sources, native house formatting for every article, political-context provenance, no ads or sponsored placements, and direct canonical links to publishers.

## Current stage

Shape research and architecture validation. Production UI work is intentionally gated on approval of `SHAPE-BRIEF.md`.

## Documents

- `PRODUCT.md`: confirmed product requirements and principles.
- `SHAPE-BRIEF.md`: proposed visual and interaction shape for approval.
- `research/claude/REPORT.md`: product, UX, extraction, persistence, bias, and risk research.
- `research/gemini/REPORT.md`: independent visual direction.
- `research/gemini/quiet_desk_ui_mockup.jpg`: Gemini visual probe, retained as research rather than an approved design.

## Next verified milestone

After shape approval, create two isolated runnable SwiftUI visual spikes from the same fixture dataset, build both with Xcode, capture iPhone and iPad screenshots, and select or merge the stronger direction before implementing live feed ingestion.
