class_name DesktopLayout
extends RefCounted

## The compact strip is always the bottom-most 160 px. An overlay grows the
## window upward above it, while the native bottom edge remains fixed.
const STRIP_HEIGHT := 160
const CONTROL_MARGIN := 0
const CONTROL_HEIGHT := 34
const SETTINGS_HEIGHT := 228
const INSPECT_HEIGHT := 278

static func overlay_height(kind: String) -> int:
	match kind:
		"settings": return SETTINGS_HEIGHT
		"inspect": return INSPECT_HEIGHT
		_: return 0

static func window_height(kind: String) -> int:
	# Expanded windows contain the complete overlay space plus the complete,
	# bottom-most ambient strip. There is no shared or clipped row between them.
	return overlay_height(kind) + STRIP_HEIGHT

static func strip_top(kind: String) -> float:
	return float(window_height(kind) - STRIP_HEIGHT)

static func bottom_anchored_position(usable: Rect2i, height: int) -> Vector2i:
	return Vector2i(usable.position.x, usable.end.y - height)

static func overlay_rect(viewport_width: float, kind: String) -> Rect2:
	var width := minf(394.0, maxf(260.0, viewport_width - 16.0))
	return Rect2(viewport_width - width - 8.0, 0.0, width, overlay_height(kind))

static func control_rect(viewport_width: float, kind: String, width: float) -> Rect2:
	return Rect2(viewport_width - width - 8.0, strip_top(kind) + CONTROL_MARGIN, width, CONTROL_HEIGHT)

static func strip_rect(viewport_width: float, kind: String) -> Rect2:
	return Rect2(0.0, strip_top(kind), viewport_width, STRIP_HEIGHT)

static func input_polygon(viewport_width: float, kind: String, control_width: float) -> PackedVector2Array:
	var control := control_rect(viewport_width, kind, control_width)
	if kind.is_empty():
		return PackedVector2Array([control.position, Vector2(control.end.x, control.position.y), control.end, Vector2(control.position.x, control.end.y)])
	var overlay := overlay_rect(viewport_width, kind)
	# The connected overlay and shelf form an L. This concave outline admits only
	# the actual visible panel shapes, not their enclosing bounding rectangle.
	return PackedVector2Array([
		overlay.position,
		Vector2(overlay.end.x, overlay.position.y),
		Vector2(control.end.x, control.end.y),
		Vector2(control.position.x, control.end.y),
		Vector2(control.position.x, control.position.y),
		Vector2(overlay.position.x, overlay.end.y),
	])

static func passthrough_polygon(viewport_width: float, kind: String, control_width: float) -> PackedVector2Array:
	# Compatibility name for callers outside this project. input_polygon is the
	# canonical exact hit shape.
	return input_polygon(viewport_width, kind, control_width)
