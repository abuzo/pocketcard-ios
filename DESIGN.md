# PocketCard design

## Purpose
A personal photograph of loved ones in a digital wallet. The photograph is the focus; controls should be quiet and familiar. Russian is the current app locale.

## Native UI ownership
SwiftUI owns typography, semantic colors, navigation, sheets and controls. Existing card colors remain owned by CardTheme in PocketCardCore and its SwiftUI mapping in CardPreview.swift. No web token layer applies.

## Photo cropping
PhotoCropView owns the single crop interaction. Present a full-screen editor with a large fixed frame, one-finger drag, two-finger zoom, optional aspect selection and Reset. Use system background/text colors, a thin white crop boundary, native navigation actions, and existing app tint. No sliders. Photo content remains inside the frame. No decorative animation.

CropSettings and applyingGesture own the shared geometry for preview/export compatibility. The editor keeps a local draft: Done applies it to the card editor, Cancel discards it; the parent Save persists the card. Existing stored crop fields and image data remain compatible. VoiceOver has adjustable zoom and named directional actions.

## Verification (2026-09-27)
27 Swift tests passed; 7 native tests passed, 1 device-only protection test skipped in Simulator. Device and Simulator builds succeeded. Drag and edge clamping visually checked using a standard Simulator photo. Pinch, VoiceOver and landscape ergonomics still need hands-on device verification. Updated app installed and launched on the user's iPhone without uninstalling it.

Structural checks passed on a clean source copy excluding ignored Local.xcconfig. Running those checks in a configured checkout still fails the pre-existing assertion that Local.xcconfig must not exist; the user's local signing config is intentionally retained.
