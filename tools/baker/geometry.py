"""Convex Detour polygons in world coordinates (X north, Y west, Z up): containment, planes and distances."""

import math


def plane(pts, c):
    """(cx, cy, cz, gx, gy): height at (x, y) is cz + gx (x - cx) + gy (y - cy), from the Newell normal."""
    nx = ny = nz = 0.0
    for i in range(len(pts)):
        (x1, y1, z1), (x2, y2, z2) = pts[i], pts[(i + 1) % len(pts)]
        nx += (y1 - y2) * (z1 + z2)
        ny += (z1 - z2) * (x1 + x2)
        nz += (x1 - x2) * (y1 + y2)
    if abs(nz) < 1e-9:
        return (*c, 0.0, 0.0)
    return (*c, -nx / nz, -ny / nz)


def height(p, x, y):
    cx, cy, cz, gx, gy = p["plane"]
    return cz + gx * (x - cx) + gy * (y - cy)


def point_in_convex(px, py, pts):
    sign = 0
    n = len(pts)
    for i in range(n):
        (x1, y1), (x2, y2) = pts[i], pts[(i + 1) % n]
        c = (x2 - x1) * (py - y1) - (y2 - y1) * (px - x1)
        if abs(c) < 1e-9:
            continue
        s = 1 if c > 0 else -1
        if sign == 0:
            sign = s
        elif s != sign:
            return False
    return True


def seg_in_box(a, b, box):
    """Does segment a-b touch the axis-aligned box (x0, x1, y0, y1)? (Liang-Barsky clip.)"""
    x0, x1, y0, y1 = box
    t0, t1 = 0.0, 1.0
    dx, dy = b[0] - a[0], b[1] - a[1]
    for p, q in ((-dx, a[0] - x0), (dx, x1 - a[0]), (-dy, a[1] - y0), (dy, y1 - a[1])):
        if p == 0:
            if q < 0:
                return False
            continue
        r = q / p
        if p < 0:
            t0 = max(t0, r)
        else:
            t1 = min(t1, r)
        if t0 > t1:
            return False
    return True


def poly_distance2(px, py, pts):
    """Distance from a point to a convex polygon in the horizontal plane: zero inside its outline, else to its
    nearest edge."""
    if point_in_convex(px, py, pts):
        return 0.0
    best = math.inf
    for i in range(len(pts)):
        (ax, ay), (bx, by) = pts[i], pts[(i + 1) % len(pts)]
        dx, dy = bx - ax, by - ay
        length = dx * dx + dy * dy
        t = 0.0 if length == 0 else max(0.0, min(1.0, ((px - ax) * dx + (py - ay) * dy) / length))
        best = min(best, math.hypot(px - (ax + t * dx), py - (ay + t * dy)))
    return best


def poly_distance(point, pts):
    """Distance from a point to a convex polygon in 3D: to its plane inside its outline, else to its nearest edge."""
    x, y, z = point
    if point_in_convex(x, y, [p[:2] for p in pts]):
        c = tuple(sum(p[a] for p in pts) / len(pts) for a in range(3))
        return abs(z - height({"plane": plane(pts, c)}, x, y))
    best = math.inf
    for i in range(len(pts)):
        a, b = pts[i], pts[(i + 1) % len(pts)]
        d = [b[k] - a[k] for k in range(3)]
        length = sum(v * v for v in d)
        t = 0.0 if length == 0 else max(0.0, min(1.0, sum((point[k] - a[k]) * d[k] for k in range(3)) / length))
        best = min(best, math.dist(point, [a[k] + t * d[k] for k in range(3)]))
    return best
