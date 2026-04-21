# Insulation Batting / Curl Generation Algorithm

This document describes the algorithm currently used in `insul-batting-paper.html` to generate an insulation-batting style curl path from a user-supplied base path.

The goal is to preserve the visual idea of batt insulation drawn as alternating loops / S-curves along a guide path, while being practical to reimplement in other languages and graphics systems.

---

## 1. Purpose

Given a **base path** and a **thickness**, generate a new path that looks like a continuous batt-insulation symbol:

- alternating curls on opposite sides of the base path
- approximately constant visual thickness
- optional left/right/center justification relative to the base path
- optional special handling for sharp polyline corners

The algorithm is geometric. It does **not** depend on Paper.js specifically, except for convenience functions like point-at-distance and tangent-at-distance. Those can be replaced in any language.

---

## 2. Inputs

The generator needs these inputs:

- `basePath`
  - Any path that can return:
    - total length
    - point at arc-length distance
    - tangent at arc-length distance
    - whether it is closed
  - For corner handling, polyline-like paths also need access to vertices.

- `thickness`
  - The visual insulation thickness.
  - This is the main scaling parameter.

- `justificationMode`
  - `center`
  - `left`
  - `right`

- `cornerMode`
  - `rounded`
  - `break`

- `cornerRadiusFactor`
  - A multiplier controlling how much a sharp polyline corner is trimmed.
  - Around `1.0` is the current default.

---

## 3. High-level pipeline

The generator works in these stages:

1. **Prepare the base path**
   - Either keep it as-is
   - Or modify sharp corners before curl generation

2. **Apply justification**
   - Create a temporary working path offset from the base path by half the thickness for left/right modes

3. **Convert the working path into repeated S-segments**
   - Split the path into a number of equally sized arc-length segments
   - For each segment, compute a fixed pattern of offset sample points

4. **Build the final curl path**
   - Connect all sample points in order
   - Optionally smooth if the source path is curved

---

## 4. Geometry primitives required in any implementation

A reimplementation should provide these low-level operations:

### 4.1 Point along path by distance

```text
pointAtDistance(path, d) -> Point
```

Returns the point at arc-length `d` along the path.

### 4.2 Tangent along path by distance

```text
tangentAtDistance(path, d) -> Vector
```

Returns the local tangent direction at arc-length `d`.

### 4.3 Left normal

If `tangent = (tx, ty)` is normalized, the left normal is:

```text
leftNormal = (ty, -tx)
```

This matches the convention used by the current implementation.

### 4.4 Clamp distance

For open paths:

```text
d = clamp(d, 0, pathLength)
```

For closed paths:

```text
d = d mod pathLength
```

### 4.5 Local frame

At any distance `d`, define:

- `P(d)` = point on path
- `T(d)` = normalized tangent
- `N(d)` = normalized left normal

Then any offset point is:

```text
offsetPoint(d, offset) = P(d) + N(d) * offset
```

---

## 5. Justification

The generator supports three justification modes.

### 5.1 Center

No offset is applied to the source path.

```text
justificationOffset = 0
```

### 5.2 Left

The temporary working path is offset to the left by half the thickness.

```text
justificationOffset = +0.5 * thickness
```

### 5.3 Right

The temporary working path is offset to the right by half the thickness.

```text
justificationOffset = -0.5 * thickness
```

### 5.4 How the offset working path is built

The current implementation does not rely on a CAD-style exact offset command.
Instead it samples the source path and creates a new path from offset points.

Procedure:

1. Choose a sample count based on path length:

```text
sampleCount = clamp(ceil(pathLength / 8), 48, 900)
```

2. For each sample distance:

```text
samplePoint = pointAtDistance(path, d)
sampleNormal = leftNormal(tangentAtDistance(path, d))
workingPoint = samplePoint + sampleNormal * justificationOffset
```

3. Join those sampled points into a temporary `workingPath`
4. If the original path is curved, optionally smooth the working path

This produces a visually acceptable offset for browser rendering.

---

## 6. Corner handling

Corner handling is applied **before** curl generation and only matters for polyline-like paths.

A path is considered polyline-like when all of its segments are straight.

### 6.1 Why corner handling exists

If the curl pattern is generated directly across a sharp vertex:

- the local tangent changes abruptly
- adjacent curls can become distorted
- loops can bunch up or intersect

The current solution is to modify the base path near sharp corners.

### 6.2 Detecting sharp corners

For each internal polyline vertex:

- `prev` = previous vertex
- `current` = current vertex
- `next` = next vertex

Compute:

```text
incoming = normalize(current - prev)
outgoing = normalize(next - current)
dot = clamp(dot(incoming, outgoing), -1, 1)
angle = acos(dot) in degrees
```

If:

```text
angle >= 24°
```

the vertex is treated as a sharp corner.

### 6.3 Cut distance at corners

For each detected corner:

```text
sharpness = clamp((angle - 24) / 96, 0, 1)
adjacent = min(length(current - prev), length(next - current))
maxCut = adjacent * 0.42
preferred = thickness * (0.75 + 0.85 * sharpness) * cornerRadiusFactor
minCut = min(thickness * 0.2 * cornerRadiusFactor, maxCut)
cutDistance = clamp(preferred, minCut, maxCut)
```

If `cutDistance <= 0.5`, the corner is ignored.

For accepted corners, define:

- `entry = current - incoming * cutDistance`
- `exit = current + outgoing * cutDistance`

These are the trimmed points on either side of the vertex.

---

## 7. Corner mode: `rounded`

In rounded mode, the source path is replaced with a path that trims sharp vertices and inserts a curve through each corner.

### 7.1 Open polyline

For each internal vertex:

- if it is **not** a sharp corner, keep the original point
- if it **is** a sharp corner:
  - draw a line to `entry`
  - draw a quadratic curve from `entry` to `exit` using `current` as the control point

Conceptually:

```text
... -> entry --quadratic(control=current)--> exit -> ...
```

### 7.2 Closed polyline

Same idea, but wrapped cyclically.

### 7.3 Effect

This does **not** shrink curls directly.
Instead, it creates a smoother guide path so the later curl generator sees a continuous direction change.

This is the currently preferred solution for preserving curl size.

---

## 8. Corner mode: `break`

In break mode, the source path is split into multiple spans at sharp corners.

### 8.1 Open polyline

At each sharp corner:

- end the current span at `entry`
- start a new span at `exit`

So the corner itself is skipped.

### 8.2 Closed polyline

The closed path is cut into multiple open spans between corners.

### 8.3 Effect

The curl pattern is generated independently on each span.
This intentionally breaks continuity at sharp corners, which can look cleaner for very angular geometry.

### 8.4 Output type

In break mode, the final result is not necessarily one path.
It can be a **group of multiple curl subpaths**.

---

## 9. Curl generation on a prepared path

Once corner handling is done, the algorithm generates curls along the prepared path.

This prepared path may be:

- the original path
- a rounded version of it
- or a single span from a broken path

---

## 10. Segment count and S-length

The prepared path is divided into a number of repeated S-pattern segments.

Let:

- `L` = prepared path length
- `T` = thickness

Then:

### 10.1 Open path

```text
ssegs = max(1, round(L / T / 0.2))
```

### 10.2 Closed path

```text
ssegs = max(2, round(L / T / 0.4) * 2)
```

This forces an even number of S-segments on closed paths.

### 10.3 Arc-length of one S-segment

```text
slength = L / ssegs
```

---

## 11. Core curl point formula

Each curl point is defined from:

- `segmentBase` = start distance of current S-segment
- `advPro` = fraction of `slength` to move forward along the path
- `offPro` = fraction of `thickness` to offset perpendicular to the path
- `sideSign` = `+1` or `-1`, alternating each half-wave

Distance along path:

```text
d = segmentBase + advPro * slength
```

Sample the local frame at that distance:

```text
P = pointAtDistance(workingPath, d)
N = leftNormal(tangentAtDistance(workingPath, d))
```

Final curl point:

```text
curlPoint = P + N * (sideSign * offPro * thickness)
```

This is the essential formula.

---

## 12. Point pattern for one repeated S segment

The shape of the batting comes from a hard-coded sequence of `(advPro, offPro)` pairs.

The current implementation follows the same overall idea as the original AutoLISP routine.

### 12.1 Starting point

Before the loop begins, emit:

```text
(0.0, 0.5) on side = +1
```

### 12.2 For each S-segment

Each segment emits points in this order.

#### Optional detail points for curved paths

These are only added when the prepared path is considered curved:

```text
(0.3, 0.49) on current side
(0.6, 0.46) on current side
```

#### Then main points on current side

```text
(0.8, 0.42)
(1.0, 0.30)
(0.9, 0.19)
(0.8, 0.14)
```

Then flip side:

```text
side = -side
```

#### Main points on opposite side

```text
(0.2, 0.14)
(0.1, 0.19)
(0.0, 0.30)
(0.2, 0.42)
```

#### Optional detail points for curved paths

```text
(0.4, 0.46)
(0.7, 0.49)
```

#### Final point of the S-segment

```text
(1.0, 0.5)
```

This repeated sequence creates the recognizable alternating batt/curl pattern.

---

## 13. Why those fractions matter

The exact numbers:

- `0.5`
- `0.49`
- `0.46`
- `0.42`
- `0.30`
- `0.19`
- `0.14`

are shape-tuning constants.

They control:

- loop fullness
- neck width
- how strongly the curve bulges away from the centerline
- how the shape transitions when crossing from one side to the other

The `advPro` values control where the points land along each S-length.
The `offPro` values control perpendicular amplitude.

In another implementation, these constants can be kept exactly as-is for compatibility, or adjusted for a different visual style.

---

## 14. Detail boost on curved paths

The algorithm uses an extra-detail mode when the prepared path is curved.

Definition of curved in the current implementation:

- a path is curved if any segment/curve is not straight

When curved:

- additional sample points are emitted in each S-segment
- final smoothing is stronger than on purely straight spans

This helps the curl path follow arcs, circles, ellipses, and spline-like guides more cleanly.

---

## 15. De-duplicating points

When adding points to the output polyline, the implementation avoids adding nearly identical consecutive points.

Rule:

```text
if distance(newPoint, lastPoint) <= 0.01
    skip it
```

This prevents zero-length edges and numerical noise.

---

## 16. Smoothing stage

After all curl points are generated, they are connected into a path.

### 16.1 If the prepared path is curved

Apply Catmull-Rom smoothing.

Current factors:

- `0.32` normally
- `0.18` if corners were rounded first

The reduced factor for rounded-corner paths avoids over-softening the result.

### 16.2 If the prepared path is straight/polyline-like

No extra smoothing is applied in the current version.

This preserves the intended geometry of the sampled curl points.

---

## 17. Output forms

### 17.1 Rounded mode

Output is usually a single path.

Metadata kept in the current implementation:

- `cornerCount`
- `cornerMode = "rounded"`

### 17.2 Break mode

Output may be multiple paths grouped together.

Metadata:

- `cornerCount`
- `cornerMode = "break"`

---

## 18. Pseudocode

## 18.1 Top-level

```text
function createBatting(basePath, thickness, justificationMode, cornerMode, cornerRadiusFactor):
    if basePath.length is too small:
        return null

    justificationOffset = getJustificationOffset(thickness, justificationMode)

    if cornerMode == "break":
        spans, cornerCount = prepareBrokenSpans(basePath, thickness, cornerRadiusFactor)
        if cornerCount > 0:
            resultGroup = []
            for span in spans:
                curl = createBattingOnPreparedPath(span, thickness, justificationOffset, 0)
                if curl exists:
                    resultGroup.add(curl)
            return resultGroup

    preparedPath, cornerCount = prepareRoundedBasePath(basePath, thickness, cornerRadiusFactor)
    return createBattingOnPreparedPath(preparedPath, thickness, justificationOffset, cornerCount)
```

## 18.2 Curl generation on one path/span

```text
function createBattingOnPreparedPath(path, thickness, justificationOffset, cornerCount):
    workingPath = buildOffsetWorkingPath(path, justificationOffset)
    L = workingPath.length
    closed = path.closed
    curved = pathHasAnyNonStraightSegment(path)

    if closed:
        ssegs = max(2, round(L / thickness / 0.4) * 2)
    else:
        ssegs = max(1, round(L / thickness / 0.2))

    slength = L / ssegs
    side = +1
    out = []

    push battPoint(segmentBase=0, advPro=0.0, offPro=0.5, side)

    for i in 0 .. ssegs-1:
        base = i * slength

        if curved:
            push battPoint(base, 0.3, 0.49, side)
            push battPoint(base, 0.6, 0.46, side)

        push battPoint(base, 0.8, 0.42, side)
        push battPoint(base, 1.0, 0.30, side)
        push battPoint(base, 0.9, 0.19, side)
        push battPoint(base, 0.8, 0.14, side)

        side = -side

        push battPoint(base, 0.2, 0.14, side)
        push battPoint(base, 0.1, 0.19, side)
        push battPoint(base, 0.0, 0.30, side)
        push battPoint(base, 0.2, 0.42, side)

        if curved:
            push battPoint(base, 0.4, 0.46, side)
            push battPoint(base, 0.7, 0.49, side)

        push battPoint(base, 1.0, 0.5, side)

    battingPath = polylineFrom(out)

    if curved:
        smoothFactor = 0.18 if cornerCount > 0 else 0.32
        battingPath = catmullRomSmooth(battingPath, smoothFactor)

    return battingPath
```

## 18.3 Single curl point

```text
function battPoint(segmentBase, advPro, offPro, side):
    d = segmentBase + advPro * slength
    d = clampOrWrap(d, workingPath.length, closed)

    P = pointAtDistance(workingPath, d)
    T = normalize(tangentAtDistance(workingPath, d))
    N = leftNormal(T)

    return P + N * (side * offPro * thickness)
```

---

## 19. Design rationale

The algorithm works well because it separates concerns:

- **base path preparation** handles geometric trouble spots like sharp corners
- **working path offset** handles justification
- **repeated S-pattern sampling** defines the visual batting motif
- **optional smoothing** improves appearance on curved guides

This makes the method portable.

A non-browser implementation can replace only the path API and keep all higher-level logic unchanged.

---

## 20. Porting notes for other languages

To port this to another environment (CAD, SVG, canvas, game engine, etc.), implement these abstractions:

1. Path length
2. Point at arc-length
3. Tangent at arc-length
4. Path construction from points
5. Optional quadratic/cubic curve support for rounded corners
6. Optional smoothing

If exact smoothing is not available, the algorithm still works as a polyline.
The curl look comes primarily from the sampled point pattern, not from the smoothing step.

---

## 21. Constants summary

### Corner detection / trimming

```text
corner angle threshold = 24 degrees
sharpness = clamp((angle - 24) / 96, 0, 1)
maxCut = adjacentSegmentLength * 0.42
preferredCut = thickness * (0.75 + 0.85 * sharpness) * cornerRadiusFactor
minCut = min(thickness * 0.2 * cornerRadiusFactor, maxCut)
```

### Segment count

```text
open:   ssegs = max(1, round(L / T / 0.2))
closed: ssegs = max(2, round(L / T / 0.4) * 2)
```

### Curl point pattern

```text
start:
(0.0, 0.5)

curved extras before main lobe:
(0.3, 0.49)
(0.6, 0.46)

main current side:
(0.8, 0.42)
(1.0, 0.30)
(0.9, 0.19)
(0.8, 0.14)

main opposite side:
(0.2, 0.14)
(0.1, 0.19)
(0.0, 0.30)
(0.2, 0.42)

curved extras after crossing:
(0.4, 0.46)
(0.7, 0.49)

segment end:
(1.0, 0.5)
```

---

## 22. Current behavior summary

The current implementation's defining characteristics are:

- curl geometry is driven by fixed normalized sample pairs
- curl amplitude is always proportional to `thickness`
- left/right justification is implemented by offsetting the guide path first
- sharp polyline corners are handled structurally, not by shrinking curls
- hard-break mode intentionally skips the corner region
- rounded mode is usually the best default for consistent curl size

---

## 23. Recommended future extensions

Useful improvements for future implementations:

- expose the S-pattern constants as style parameters
- allow different corner radius policies
- add miter/bevel/fillet corner modes
- use exact geometric offsetting instead of sampled offsetting where available
- add adaptive segment density based on curvature
- support separate inside/outside lobe widths

---

End of description.
