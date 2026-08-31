class_name DesktopLayout
extends RefCounted

## The window grows upward for an overlay and keeps its bottom edge on the
## usable desktop edge.  This keeps the compact strip stable and makes the
## entire overlay reachable instead of clipping it at the 160 px viewport.
const COMPACT_HEIGHT := 160
const CONTROL_MARGIN := 8
const CONTROL_HEIGHT := 34
const OVERLAY_TOP := 48
const SETTINGS_HEIGHT := 220
const INSPECT_HEIGHT := 270

static func overlay_height(kind: String) -> int:
	match kind:
		"settings": return SETTINGS_HEIGHT
		"inspect": return INSPECT_HEIGHT
		_: return 0

static func window_height(kind: String) -> int:
	return max(COMPACT_HEIGHT, OVERLAY_TOP + overlay_height(kind) + CONTROL_MARGIN)

static func bottom_anchored_position(usable: Rect2i, height: int) -> Vector2i:
	return Vector2i(usable.position.x, usable.end.y - height)

static func overlay_rect(viewport_width: float, kind: String) -> Rect2:
	var width := minf(394.0, maxf(260.0, viewport_width - 16.0))
	return Rect2(viewport_width - width - CONTROL_MARGIN, OVERLAY_TOP, width, overlay_height(kind))
