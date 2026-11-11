// Exercises the patched ledge-drop helper (TileBuilder.cpp SPF-DROP block) on hand-built compact heightfields.
#include <Recast.h>
#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <cstring>
#include <deque>
#include <memory>
#include <vector>
using uint8 = uint8_t;
enum { NAV_AREA_GROUND = 11, NAV_AREA_GROUND_STEEP = 10, NAV_AREA_WATER = 9, NAV_AREA_MAGMA_SLIME = 8, NAV_AREA_UNDER_LIQUID = 7 };
namespace {
#include "drops.inc"
}
static int fails = 0;

// A compact heightfield of open spans: each walkable span is a floor plus the player's clearance above it, as
// rcBuildCompactHeightfield makes them. A wall stays a null-area span here so the helper's shelf test can see it.
struct Field
{
  std::vector<rcCompactCell> cells;
  std::vector<rcCompactSpan> spans;
  std::vector<unsigned char> areas;
  rcCompactHeightfield chf;

  Field(int width, int height) {
    std::memset(&chf, 0, sizeof chf);
    cells.assign(width * height, rcCompactCell{});
    chf.width = width;
    chf.height = height;
    chf.walkableClimb = 4;
    chf.cs = 0.53333336f;
    chf.ch = 0.5f;
    chf.bmin[0] = chf.bmin[1] = chf.bmin[2] = 0;
    chf.bmax[0] = width * chf.cs;
    chf.bmax[1] = 50;
    chf.bmax[2] = height * chf.cs;
    chf.cells = cells.data();
  }

  // the vectors own the storage; the field must not free them through Recast's destructor
  ~Field() {
    chf.cells = nullptr;
    chf.spans = nullptr;
    chf.areas = nullptr;
  }

  void add(int x, int z, float bottom, float top, unsigned char area) {
    rcCompactSpan span{};
    span.y = (unsigned short)std::lround(bottom / chf.ch);
    span.h = (unsigned char)std::lround((top - bottom) / chf.ch);
    for (int dir = 0; dir < 4; ++dir)
      rcSetCon(span, dir, RC_NOT_CONNECTED);
    rcCompactCell &cell = cells[x + z * chf.width];
    cell.index = cell.count ? cell.index : (unsigned int)spans.size();
    cell.count += 1;
    spans.push_back(span);
    areas.push_back(area);
  }

  // a walkable floor and the 1.5 yards of clearance the player needs above it
  void surface(int x, int z, float height, unsigned char area = NAV_AREA_GROUND) {
    add(x, z, height, height + 1.5f, area);
  }

  // solid only: a wall the compact field keeps as a null-area span
  void wall(int x, int z, float bottom, float top) { add(x, z, bottom, top, RC_NULL_AREA); }

  // join the floors of two neighbouring columns when their surfaces are within the climb, as compaction does
  void link(int x, int z, int dx, int dz) {
    int nx = x + dx, nz = z + dz;
    if (nx < 0 || nz < 0 || nx >= chf.width || nz >= chf.height)
      return;
    rcCompactCell const &a = cells[x + z * chf.width], &b = cells[nx + nz * chf.width];
    int dir = dx > 0 ? 1 : dx < 0 ? 0 : dz > 0 ? 3 : 2;
    int other = dx > 0 ? 0 : dx < 0 ? 1 : dz > 0 ? 2 : 3;
    for (int i = a.index; i < a.index + a.count; ++i) {
      if (areas[i] == RC_NULL_AREA)
        continue;
      float const floorA = chf.bmin[1] + spans[i].y * chf.ch;
      for (int j = b.index; j < b.index + b.count; ++j) {
        if (areas[j] == RC_NULL_AREA)
          continue;
        float const floorB = chf.bmin[1] + spans[j].y * chf.ch;
        if (std::fabs(floorA - floorB) > chf.walkableClimb * chf.ch)
          continue;
        rcSetCon(spans[i], dir, 0); // a neighbour exists; the builder only asks whether one does
        rcSetCon(spans[j], other, 0);
      }
    }
  }

  void linkAll() {
    for (int z = 0; z < chf.height; ++z)
      for (int x = 0; x < chf.width; ++x) {
        link(x, z, 1, 0);
        link(x, z, 0, 1);
      }
  }

  void markBeds() {
    rcCompactHeightfield view{};
    view = chf;
    view.cells = cells.data();
    view.spans = spans.data();
    view.areas = areas.data();
    MarkGroundUnderLiquid(view);
    view.cells = nullptr;
    view.spans = nullptr;
    view.areas = nullptr;
  }

  std::vector<LedgeDrop> drops(float tileMaxX = 1e30f, float tileMaxZ = 1e30f) {
    // the helper reads the field through its pointers; clear them before the view is destroyed
    rcCompactHeightfield view{};
    view = chf;
    view.cells = cells.data();
    view.spans = spans.data();
    view.areas = areas.data();
    float const min[3] = { chf.bmin[0], chf.bmin[1], chf.bmin[2] };
    float const max[3] = { tileMaxX, chf.bmax[1], tileMaxZ };
    std::vector<LedgeDrop> found = CollectLedgeDrops(view, min, max);
    view.cells = nullptr;
    view.spans = nullptr;
    view.areas = nullptr;
    return found;
  }
};

// A plateau at 20 yards over a landing `gap` columns out, with an optional wall in between.
static std::unique_ptr<Field> ledge(float fall, bool wall, int gap = 3) {
  auto f = std::make_unique<Field>(16, 6);
  for (int z = 0; z < 6; ++z)
    for (int x = 0; x < 6; ++x)
      f->surface(x, z, 20);
  if (wall)
    for (int z = 0; z < 6; ++z)
      f->wall(7, z, 0, 30);
  for (int z = 0; z < 6; ++z)
    for (int x = 5 + gap; x < 16; ++x)
      f->surface(x, z, 20 - fall);
  f->linkAll();
  return f;
}

static void expect(char const *name, bool got, bool want) {
  printf("%-56s %s (got %d want %d)\n", name, got == want ? "PASS" : "FAIL", got,
         want);
  fails += got != want;
}

int main() {
  auto clear = ledge(10, false);
  std::vector<LedgeDrop> drops = clear->drops();
  expect("a clear ledge yields a drop", !drops.empty(), true);
  bool spaced = drops.size() <= 3;
  for (std::size_t a = 0; a < drops.size(); ++a)
    for (std::size_t b = a + 1; b < drops.size(); ++b)
      spaced = spaced && (std::fabs(drops[a].from[0] - drops[b].from[0]) > 1.0f ||
                          std::fabs(drops[a].from[2] - drops[b].from[2]) > 1.0f);
  expect("one connection per ledge run, not per voxel", spaced, true);
  if (!drops.empty()) {
    expect("the drop starts on the ledge's surface", std::fabs(drops[0].from[1] - 20) < 0.01f,
           true);
    expect("the drop lands on the lower surface",
           std::fabs(drops[0].to[1] - 10) < 0.01f, true);
    expect("the drop falls downhill", drops[0].to[1] < drops[0].from[1], true);
  }

  expect("a wall between ledge and landing yields none", ledge(10, true)->drops().empty(),
         true);
  expect("a fall over 14.57 yards yields none", ledge(16, false)->drops().empty(), true);
  // four columns out is 2.13 yards: 2.5 yards down is a 50 degree face the player walks, 3.5 is a drop
  expect("a face gentler than 50 degrees is walked, not dropped",
         ledge(2.5f, false, 4)->drops().empty(), true);
  expect("a face steeper than 50 degrees is a drop",
         ledge(3.5f, false, 4)->drops().empty(), false);

  // a landing just across the tile boundary: Detour keeps the connection by its start tile, and the heightfield's
  // border cells still hold the landing
  auto crossing = ledge(10, false);
  bool found = false;
  for (LedgeDrop const &drop : crossing->drops(8 * crossing->chf.cs, 1e30f))
    found = found || (drop.from[0] < 8 * crossing->chf.cs && drop.to[0] > 8 * crossing->chf.cs);
  expect("a landing in the neighbouring tile is kept", found, true);
  // no landing at all: the same ledge but the field ends before where a landing would be
  Field edge(8, 6);
  for (int z = 0; z < 6; ++z)
    for (int x = 0; x < 6; ++x)
      edge.surface(x, z, 20);
  edge.linkAll();
  expect("a landing beyond the heightfield border yields none", edge.drops().empty(), true);

  // no ledge at all: a single walkable floor joined across every column
  Field flat(16, 6);
  for (int z = 0; z < 6; ++z)
    for (int x = 0; x < 16; ++x)
      flat.surface(x, z, 20);
  flat.linkAll();
  expect("joined ground yields none", flat.drops().empty(), true);

  // steep ground walks down by itself, so it is never the start of a drop
  Field steep(16, 6);
  for (int z = 0; z < 6; ++z)
    for (int x = 0; x < 6; ++x)
      steep.surface(x, z, 20, NAV_AREA_GROUND_STEEP);
  for (int z = 0; z < 6; ++z)
    for (int x = 8; x < 16; ++x)
      steep.surface(x, z, 10);
  steep.linkAll();
  expect("a steep face is no ledge", steep.drops().empty(), true);

  // a canal: its bed lies under the water surface, a quay stands above it in the same column
  Field canal(2, 1);
  canal.surface(0, 0, 5);
  canal.surface(0, 0, 15, NAV_AREA_WATER);
  canal.surface(0, 0, 20);
  canal.surface(1, 0, 6, NAV_AREA_GROUND_STEEP);
  canal.surface(1, 0, 15, NAV_AREA_WATER);
  canal.markBeds();
  expect("ground under water is a bed", canal.areas[0] == NAV_AREA_UNDER_LIQUID, true);
  expect("the water surface stays water", canal.areas[1] == NAV_AREA_WATER, true);
  expect("ground above the water stays ground", canal.areas[2] == NAV_AREA_GROUND, true);
  expect("steep ground under water is a bed", canal.areas[3] == NAV_AREA_UNDER_LIQUID, true);

  // a ledge over a pool lands in the water, never on the bed below it
  Field pool(16, 6);
  for (int z = 0; z < 6; ++z) {
    for (int x = 0; x < 6; ++x)
      pool.surface(x, z, 20);
    for (int x = 6; x < 16; ++x) {
      pool.surface(x, z, 8);
      pool.surface(x, z, 14, NAV_AREA_WATER);
    }
  }
  pool.linkAll();
  pool.markBeds();
  std::vector<LedgeDrop> const into = pool.drops();
  expect("a ledge over a pool drops", !into.empty(), true);
  if (!into.empty())
    expect("the drop lands on the water surface", std::fabs(into[0].to[1] - 14) < 0.01f, true);

  printf("%s\n", fails ? "FAILED" : "ALL PASS");
  return fails != 0;
}
