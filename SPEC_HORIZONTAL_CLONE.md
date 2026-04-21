# Horizontal Batt Fill Clone Specification

This document describes the algorithm used in `hori-fill.html` to generate a horizontally repeating insulation-batt fill inside a rectangle.

The intent of this spec is portability: it should be possible to reimplement the same behavior in other languages and graphics systems without depending on Paper.js.

---

## 1. Goal

Fill a rectangle with the same batt / insulation curl motif used by the path-based generator, but constrained to a simple horizontal layout.

Key requirements:

- The pattern must **not** stretch to fit width.
- Rectangle **height** determines the pattern's vertical scale.
- Rectangle **width** only reveals more or fewer repetitions of the pattern.
- The visible top and bottom caps of the batt symbol should look round, not faceted.
- The pattern is clipped to the rectangle bounds.
- Optional upper and lower gaps reduce the usable vertical band.
- Optional interactive resizing changes the rectangle and regenerates the fill.

---

## 2. Core design idea

The important design choice is this:

> The horizontal batt fill is generated as if it were an effectively infinite batt path on a straight horizontal axis. The rectangle does not define the batt wavelength. Instead, the rectangle height defines batt thickness, and batt spacing is derived from that thickness.

This avoids the common bad result where a symbol is stretched or squashed horizontally just because the box width changes.

So:

- **height controls batt scale**
- **width controls clipping only**

---

## 3. Inputs

The current implementation uses these inputs.

### Rectangle
- `width`
- `height`
- `centerX`, `centerY`

### Pattern controls
- `spacingFactor`
  - current UI range: `0.65 .. 1.75`
  - default: `1.0`
- `upperGap`
  - default: `12`
- `lowerGap`
  - default: `12`
- `strokeWidth`

### Rendering options
- `showBounds`
- `autoPreview`

---

## 4. Rectangle state model

The page keeps an internal rectangle state:

```text
rectState = {
  center: Point,
  width: Number,
  height: Number
}
```

This state is the single source of truth.

The rectangle is reconstructed from it as:

```text
left   = center.x - width / 2
right  = center.x + width / 2
top    = center.y - height / 2
bottom = center.y + height / 2
```

The implementation also enforces minimum size:

```text
minWidth  = 40
minHeight = 24
```

---

## 5. Usable vertical band

The pattern is not drawn across the full rectangle height if gaps are specified.

Given rectangle bounds:

```text
usableTop    = rect.top + upperGap
usableBottom = rect.bottom - lowerGap
usableHeight = usableBottom - usableTop
```

If:

```text
usableHeight <= 8
```

the algorithm refuses to generate the pattern.

The horizontal centerline of the batt is:

```text
axisY = (usableTop + usableBottom) / 2
```

The batt thickness is set equal to usable height:

```text
thickness = usableHeight
```

This is the most important scale coupling in the whole algorithm.

---

## 6. Horizontal batt spacing

The horizontal batt spacing is derived from batt thickness.

The current implementation uses the same base proportion as the straight-path batt generator:

```text
slength = max(6, thickness * 0.2 * spacingFactor)
```

Where:
- `slength` = one S-segment length along the axis
- `spacingFactor` = user scale for horizontal spacing only

A full left-right alternation cycle spans two S-segments:

```text
cycle = slength * 2
```

This means:
- taller usable band -> larger batt curls and longer wavelength
- narrower / wider rectangle -> no distortion, only fewer or more repeated cycles visible

---

## 7. Pattern extent beyond the box

The generator does not start exactly at the left edge or end exactly at the right edge.
Instead it extends the pattern beyond the rectangle and clips later.

This avoids awkward partial-shape construction at the edges.

Current implementation:

```text
phaseOrigin = rect.center.x
extra = cycle * 3
xStart = phaseOrigin - ceil((phaseOrigin - (rect.left - extra)) / cycle) * cycle
xEnd   = phaseOrigin + ceil(((rect.right + extra) - phaseOrigin) / cycle) * cycle
segmentCount = max(2, round((xEnd - xStart) / slength))
```

Interpretation:
- choose a pattern origin at the rectangle center
- extend several full cycles past both left and right boundaries
- build enough S-segments to cover the extended range
- later clip to the actual rectangle

---

## 8. Straight-axis batt point formula

Unlike the general path generator, this page uses a fixed straight horizontal centerline.
So no tangent/normal computation is required.

For any sample point:

```text
x = segmentBaseX + advPro * slength
y = axisY - sideSign * offPro * thickness
```

Where:
- `segmentBaseX` = x-start of the current S-segment
- `advPro` = longitudinal proportion in `[0, 1]`
- `offPro` = perpendicular offset as proportion of `thickness`
- `sideSign` = `+1` or `-1`

This is a direct simplification of the general batt point formula.

---

## 9. Batt point sequence

The visual shape is driven by a hard-coded sequence of normalized samples.

The current implementation uses the following high-resolution sequence.

### Initial point
Before the loop starts:

```text
(0.0, 0.50) with side = +1
kind = peak
```

### For each S-segment
For each `baseX = xStart + i * slength`:

#### First half on current side
```text
(0.3, 0.49) kind=shoulder
(0.6, 0.46) kind=capInner
(0.8, 0.42) kind=capEdge
(1.0, 0.30)
(0.9, 0.19)
(0.8, 0.14)
```

Then flip side:

```text
side = -side
```

#### Second half on opposite side
```text
(0.2, 0.14)
(0.1, 0.19)
(0.0, 0.30)
(0.2, 0.42) kind=capEdge
(0.4, 0.46) kind=capInner
(0.7, 0.49) kind=shoulder
(1.0, 0.50) kind=peak
```

This produces the repeating batt motif.

---

## 10. Why the points have semantic kinds

The current implementation does not treat every point equally.
Some points are tagged with a semantic role:

- `peak`
- `shoulder`
- `capInner`
- `capEdge`
- `normal`

These tags are used later to choose whether a region should be drawn as:
- a circular arc
- or a cubic Bézier segment

This is important for getting the upper/lower caps round.

---

## 11. Point collection and deduplication

Sample points are stored as entries like:

```text
entry = {
  point: Point,
  offPro: Number,
  side: +1 or -1,
  kind: String
}
```

Consecutive near-duplicates are skipped:

```text
if distance(currentPoint, previousPoint) <= 0.01
    do not add
```

This avoids zero-length segments.

---

## 12. Hybrid curve construction

The final path is not a raw polyline and not a generic smoothed line.
It is built as a **hybrid path**:

- wide circular arcs for top/bottom caps
- cubic Bézier segments for everything else

This is the current best approximation in `hori-fill.html`.

---

## 13. Tangent estimation for Bézier segments

For each sampled point, a local tangent is estimated from neighboring points.

Given point `i`:

```text
prev = points[i - 1] or points[i]
next = points[i + 1] or points[i]
before = point - prev
after  = next - point
xTurn = before.x * after.x <= 0
yTurn = before.y * after.y <= 0
xSpan = max(abs(before.x), abs(after.x))
localSpan = min(length(before), length(after))
```

Initial tangent:

```text
tangent = (next - prev) * (0.5 * tension)
```

Current call uses:

```text
tension = 1.08
```

### Special tangent rules

#### Endpoints
For first/last point:

```text
kind = end
tangent = (next.x - prev.x, 0) * (0.5 * tension)
```

That forces the ends to be horizontally oriented.

#### Peaks
If point is tagged `peak`, or looks like a vertical extremum (`yTurn && !xTurn`):

```text
kind = peak
signX = sign(next.x - prev.x) or 1
tangent = (signX * xSpan * 1.5 * tension, 0)
```

So peaks get strong horizontal tangents.

#### Side turnarounds
If `xTurn && !yTurn`:

```text
kind = side
tangent = (0, tangent.y)
```

So those areas get vertical tangents.

### Tangent clamping
Tangents are clamped by local geometric span.

For peak points:

```text
maxTangent = localSpan * 2.1
```

For other points:

```text
maxTangent = localSpan * 1.55
```

If the tangent exceeds this length, normalize it down.

---

## 14. Wide cap arc detection

This is the key step that makes the top and bottom look truly round.

The builder scans the sample entries and looks for this exact semantic pattern across 7 consecutive entries:

```text
capEdge, capInner, shoulder, peak, shoulder, capInner, capEdge
```

Additionally, all 7 entries must have the same `side`.

If that pattern exists, the region is treated as a wide peak cap.

### Current detection rule

```text
canUseWidePeakArc(index):
    if index + 6 >= entries.length: return false
    seq = entries[index .. index+6]
    kinds = seq.map(kind)
    sameSide = all seq.side equal
    return sameSide && kinds ==
        [capEdge, capInner, shoulder, peak, shoulder, capInner, capEdge]
```

---

## 15. Drawing a cap with an arc

When a wide cap pattern is found at index `i`, the builder draws:

```text
arc from points[i] to points[i+6], passing through points[i+3]
```

In Paper.js this is implemented as:

```text
path.arcTo(points[i + 3], points[i + 6])
```

Meaning:
- current path position is already at `points[i]`
- `points[i+3]` is the top or bottom peak
- `points[i+6]` is the opposite cap edge

Then the builder advances by 6 samples.

This creates a much smoother, more circular top/bottom cap than ordinary segment smoothing.

---

## 16. Drawing non-cap regions with cubic Bézier segments

If no wide peak arc applies, the builder draws the next interval `[p1, p2]` as a cubic Bézier.

Given tangent vectors at the endpoints:

```text
handleOut = tangent[i] / 3
handleIn  = tangent[i+1] / 3
```

Let:

```text
segmentLength = distance(p1, p2)
peakAdjacent = pointInfo[i].kind == peak OR pointInfo[i+1].kind == peak
```

Maximum handle length:

```text
maxHandle = segmentLength * 0.74   if peakAdjacent
maxHandle = segmentLength * 0.56   otherwise
```

Clamp `handleOut` and `handleIn` to this max length.

Then cubic control points are:

```text
cp1 = p1 + handleOut
cp2 = p2 - handleIn
```

Draw:

```text
cubicCurveTo(cp1, cp2, p2)
```

This is used for the neck / pinch / transition parts of the batt.

---

## 17. Complete path-building pseudocode

```text
function buildHybridBattPath(entries, tension):
    path = new Path()
    if entries is empty: return path

    points = entries.map(point)
    path.moveTo(points[0])

    pointInfo = []
    for each index i:
        compute prev, next, before, after, xTurn, yTurn, xSpan, localSpan
        tangent = (next - prev) * (0.5 * tension)
        kind = entries[i].kind or normal

        if i is first or last:
            kind = end
            tangent = ((next.x - prev.x), 0) * (0.5 * tension)
        else if kind == peak or (yTurn and not xTurn):
            kind = peak
            tangent = (sign(next.x - prev.x) * xSpan * 1.5 * tension, 0)
        else if xTurn and not yTurn:
            kind = side
            tangent = (0, tangent.y)

        clamp tangent length:
            localSpan * 2.1 for peaks
            localSpan * 1.55 otherwise

        pointInfo[i] = { tangent, kind }

    i = 0
    while i < points.length - 1:
        if entries[i..i+6] match wide cap pattern:
            path.arcTo(points[i+3], points[i+6])
            i += 6
            continue

        p1 = points[i]
        p2 = points[i+1]
        handleOut = pointInfo[i].tangent / 3
        handleIn = pointInfo[i+1].tangent / 3
        segmentLength = distance(p1, p2)
        peakAdjacent = pointInfo[i].kind == peak or pointInfo[i+1].kind == peak
        maxHandle = segmentLength * (0.74 if peakAdjacent else 0.56)
        clamp handles to maxHandle
        cp1 = p1 + handleOut
        cp2 = p2 - handleIn
        path.cubicCurveTo(cp1, cp2, p2)
        i += 1

    return path
```

---

## 18. Clipping to the rectangle

The pattern is generated larger than the box, then clipped.

In the current implementation:

1. Build the pattern path.
2. Build a rectangle path equal to the target box.
3. Use that rectangle as a clip mask.
4. Group mask + pattern.

Conceptually:

```text
clipMask = rectangle(rect)
output = clip(pattern, clipMask)
```

This is preferable to trying to terminate the pattern exactly at the left/right edges.

---

## 19. Optional visible bounds / resize controls

If `showBounds` is enabled, an extra overlay is added on top of the clipped pattern:

- dashed rectangle outline
- 8 resize handles:
  - `nw`, `n`, `ne`, `e`, `se`, `s`, `sw`, `w`

Handle size:

```text
handleSize = clamp(min(rect.width, rect.height) * 0.035, 7, 12)
```

This overlay is purely for interaction / display and does not affect clipping.

---

## 20. Interactive resize algorithm

The current resize system does **not** rely on hit-testing the drawn handle shapes.
It computes proximity directly against the current rectangle geometry.

### 20.1 Mouse hit tolerance

Tolerance is made zoom-aware:

```text
tol = 12 / max(view.zoom, 0.001)
```

### 20.2 Handle detection

For each mouse point, test proximity to these locations:

- top-left
- top-center
- top-right
- right-center
- bottom-right
- bottom-center
- bottom-left
- left-center

If none match, also test proximity to rectangle edges.

Result is one of:

```text
nw, n, ne, e, se, s, sw, w, or null
```

### 20.3 Drag start

On mouse down over a resize role:

Store the rectangle bounds at drag start:

```text
dragState = {
  role,
  left, right, top, bottom
}
```

### 20.4 Drag update

While dragging:

- west handles change `left`
- east handles change `right`
- north handles change `top`
- south handles change `bottom`

With minimum size clamping:

```text
left  <= right - minWidth
right >= left + minWidth
top   <= bottom - minHeight
bottom>= top + minHeight
```

Then rebuild `rectState` from the updated bounds and regenerate the pattern.

### 20.5 Drag end

Clear drag state and update cursor.

---

## 21. View fitting algorithm

When presets are loaded or the page initializes, the view is fit manually.

Given expanded rectangle bounds:

```text
bounds = rect.expand(80)
zoom = min(viewWidth / bounds.width, viewHeight / bounds.height)
view.center = bounds.center
view.zoom = zoom
```

This is independent of the batt algorithm, but useful if porting the exact UI behavior.

---

## 22. Generation pipeline summary

The full pipeline in `hori-fill.html` is:

1. Read rectangle state.
2. Apply upper/lower gaps.
3. Compute usable band.
4. Set `thickness = usableHeight`.
5. Set `slength = max(6, thickness * 0.2 * spacingFactor)`.
6. Compute extended horizontal range beyond the box.
7. Generate batt sample entries using the fixed normalized sequence.
8. Convert entries into a hybrid path:
   - wide cap arcs
   - cubic Bézier transition segments
9. Clip the path to the rectangle.
10. Optionally draw bounds + resize handles.
11. Render.

---

## 23. Minimal language-agnostic pseudocode

```text
function generateHorizontalBattFill(rect, spacingFactor, upperGap, lowerGap):
    usableTop = rect.top + upperGap
    usableBottom = rect.bottom - lowerGap
    usableHeight = usableBottom - usableTop
    if usableHeight <= 8:
        return null

    axisY = (usableTop + usableBottom) / 2
    thickness = usableHeight
    slength = max(6, thickness * 0.2 * spacingFactor)
    cycle = slength * 2

    phaseOrigin = rect.center.x
    extra = cycle * 3
    xStart = aligned start left of rect with extra margin
    xEnd = aligned end right of rect with extra margin
    segmentCount = max(2, round((xEnd - xStart) / slength))

    entries = []
    side = +1
    push(entries, point(xStart + 0.0 * slength, axisY - side * 0.5 * thickness), kind=peak)

    for each segment i:
        baseX = xStart + i * slength

        push(baseX, 0.3, 0.49, side, shoulder)
        push(baseX, 0.6, 0.46, side, capInner)
        push(baseX, 0.8, 0.42, side, capEdge)
        push(baseX, 1.0, 0.30, side, normal)
        push(baseX, 0.9, 0.19, side, normal)
        push(baseX, 0.8, 0.14, side, normal)

        side = -side

        push(baseX, 0.2, 0.14, side, normal)
        push(baseX, 0.1, 0.19, side, normal)
        push(baseX, 0.0, 0.30, side, normal)
        push(baseX, 0.2, 0.42, side, capEdge)
        push(baseX, 0.4, 0.46, side, capInner)
        push(baseX, 0.7, 0.49, side, shoulder)
        push(baseX, 1.0, 0.5, side, peak)

    battPath = buildHybridBattPath(entries, tension=1.08)
    return clipPathToRectangle(battPath, rect)
```

---

## 24. Constants summary

### Validation / geometry
```text
minimum usable height = 8
minimum rectangle width = 40
minimum rectangle height = 24
```

### Batt scaling
```text
thickness = usableHeight
slength = max(6, thickness * 0.2 * spacingFactor)
cycle = slength * 2
extra coverage = cycle * 3
```

### Deduplication
```text
min point distance = 0.01
```

### Hybrid curve builder
```text
tension = 1.08
peak tangent factor = 1.5 * tension
peak tangent clamp = localSpan * 2.1
normal tangent clamp = localSpan * 1.55
peak-adjacent max handle = segmentLength * 0.74
normal max handle = segmentLength * 0.56
```

### Resize interaction
```text
resize tolerance = 12 / zoom
handle size = clamp(min(width, height) * 0.035, 7, 12)
```

---

## 25. Important behavioral characteristics

A faithful port should preserve these behaviors:

1. **Height defines batt scale.**
2. **Width never stretches the motif.**
3. **Pattern starts and ends outside the box, then gets clipped.**
4. **Top/bottom caps are built as broad arcs, not just smoothed polylines.**
5. **Transitions between caps are cubic curves.**
6. **Pattern alternates side sign every S-segment.**
7. **Spacing is controlled only by `spacingFactor`, not by box width.**

---

## 26. Porting advice

To clone this algorithm in another language or environment, you need these capabilities:

- 2D point/vector math
- rectangle geometry
- path construction
- cubic Bézier segment creation
- circular or arc-through-three-points creation
- clipping a path by a rectangle (or equivalent viewport masking)
- optional mouse interaction for resizing

If an environment does not support a built-in `arcTo(through, end)` primitive, implement the peak cap as:

- an arc defined by three points (`start`, `peak`, `end`), or
- a cubic Bézier approximation of a circular arc

The three-point arc is preferred for fidelity.

---

## 27. Output structure in the current implementation

The generated item stores metadata:

```text
root.data = {
  slength,
  cycle,
  usableHeight,
  thickness,
  axisY,
  rectBounds
}
```

A port does not need this exact structure, but preserving these values is useful for debugging and status display.

---

## 28. Final note

This horizontal clone is not a generic wave filler.
It is specifically a batt-symbol repeater derived from the same normalized point logic as the main insulation path generator, with extra geometry rules to make the caps look circular and clean in a horizontal fill use case.

That distinction matters if you need a visually faithful reimplementation.
