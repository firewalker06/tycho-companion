# Tycho Companion generated art

These are project-owned generated assets. They are not third-party material and
carry no implied third-party licence.

| File | Source dimensions | SHA-256 | Generation / integration notes |
| --- | --- | --- | --- |
| `coastal-workshop.png` | 1774 × 887, opaque RGB | `37f9eb4be80663bd6fae6d67752d0810576fbc6ab2d0f074bf6d4cea029f1ee4` | Generated from the supplied coastal-workshop prompt. The app draws source region `x=0..1774, y=400..784` into the strip. This deliberate 1774 × 384 crop contains all three lit work bays and fits the compact bottom strip without letterboxing. |
| `caretaker-poses.png` | 1536 × 1024, RGBA | `04a66973bdc564463df5508543b444de5e0b1e0ce4ebda311be0a9b2bfd7aa98` | Generated from the supplied caretaker sprite-sheet prompt, then made RGBA using the corrected chroma-key edit with the system `remove_chroma_key.py` script. It is exactly 3 columns × 2 rows of 512 × 512 cells: idle top-left, running top-centre, awaiting-input/partial top-right, succeeded bottom-left, failed/blocked bottom-centre, stopped/offline/stale bottom-right. |

The running pose alone has a subtle two-pixel bob. All other poses remain still.
