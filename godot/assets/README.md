# Tycho Companion generated-art provenance

Both raster assets were generated and edited with OpenAI GPT Image during local
development. The inputs were text prompts and earlier project-generated versions
of the same artwork; no third-party source images are incorporated. Image
post-processing removed a flat chroma background and preserved alpha. The files
contain no embedded prompt, local path, credential, log, or user-data metadata.

| File | Tracked dimensions | SHA-256 | Generation / integration notes |
| --- | --- | --- | --- |
| `coastal-workshop.png` | 2048 × 500, RGBA | `3d8d2f047dd830a45e7e345c0e73d1e77c6aa63d659ccaa1350bd757ff9825b9` | GPT Image edit of the earlier project-generated workshop. The prompt requested a wide coastal pier with three workshops and attached objects, no sky or background, sized for a 2K desktop strip. A flat chroma background was converted to alpha, then the cutout was tightly cropped and scaled to 2048 px. The renderer preserves its aspect ratio. |
| `caretaker-poses.png` | 1536 × 1024, RGBA | `55b5fa35ab247544d9c1de36d8d5cbc13bedd97ccc17cf329a01d37968db7c82` | GPT Image edit of the earlier project-generated six-pose caretaker atlas. The prompt preserved the exact character, poses, 3 × 2 grid, and 512 px cells while strengthening the black outer silhouette to remain legible at 120 px. Exact magenta pixel filtering converted the flat chroma background to alpha without softening the pixel art. Pose order: idle, running, awaiting-input/partial, succeeded, failed/blocked, and stopped/offline/stale. |

Every caretaker pose has state-specific procedural idle motion: breathing for idle, a working bob for running, an alert sway for awaiting input, a proud lift for success, a slow slump for failed/blocked, and restrained motion for partial, stopped, and stale states.
