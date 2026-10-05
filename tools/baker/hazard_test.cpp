#include <Recast.h>
#include <algorithm>
#include <cfloat>
#include <cmath>
#include <cstdint>
#include <cstdio>
#include <unordered_map>
#include <vector>
using uint8 = uint8_t;
using uint32 = uint32_t;
using uint64 = uint64_t;
using int64 = int64_t;
enum {
  NAV_AREA_GROUND = 11,
  NAV_AREA_MAGMA_SLIME = 8,
  NAV_AREA_ALL_MASK = 0x3F
};
enum { NAV_FLAG_UNDER_HAZARD = 0x80 };
namespace {
#include "hazard.inc"
}
static int fails = 0;
// one ground polygon (square, nvp 4) with verts in cell units; bmin 0, cs 1, ch
// 0.2
static bool run(float gx0, float gx1, float gz0, float gz1, float gy,
                std::vector<float> hv, std::vector<int> ht, float ox = 0,
                float oz = 0) {
  rcPolyMesh m = {};
  unsigned short verts[12] = {
      (unsigned short)(gx0 - ox),  (unsigned short)(gy / 0.2f),
      (unsigned short)(gz0 - oz),  (unsigned short)(gx1 - ox),
      (unsigned short)(gy / 0.2f), (unsigned short)(gz0 - oz),
      (unsigned short)(gx1 - ox),  (unsigned short)(gy / 0.2f),
      (unsigned short)(gz1 - oz),  (unsigned short)(gx0 - ox),
      (unsigned short)(gy / 0.2f), (unsigned short)(gz1 - oz)};
  unsigned short polys[8] = {0,
                             1,
                             2,
                             3,
                             RC_MESH_NULL_IDX,
                             RC_MESH_NULL_IDX,
                             RC_MESH_NULL_IDX,
                             RC_MESH_NULL_IDX};
  unsigned char area = NAV_AREA_GROUND;
  unsigned short flags = 0;
  m.verts = verts;
  m.polys = polys;
  m.areas = &area;
  m.flags = &flags;
  m.npolys = 1;
  m.nverts = 4;
  m.nvp = 4;
  m.cs = 1;
  m.bmin[0] = ox;
  m.bmin[1] = 0;
  m.bmin[2] = oz;
  m.ch = 0.2f;
  std::vector<uint8> tf(ht.size() / 3, NAV_AREA_MAGMA_SLIME);
  MarkGroundUnderHazard(m, hv.data(), ht.data(), tf.data(), int(ht.size() / 3));
  m.verts = nullptr;
  m.polys = nullptr;
  m.areas = nullptr;
  m.flags = nullptr; // stack storage, not rcAlloc'd
  return flags & NAV_FLAG_UNDER_HAZARD;
}
static void expect(char const *n, bool got, bool want) {
  printf("%-52s %s (got %d want %d)\n", n, got == want ? "PASS" : "FAIL", got,
         want);
  fails += got != want;
}
int main() {
  // 100x100 ground at y=0; small hazard triangle (60,60)-(64,60)-(60,64) at
  // y=5, far from centroid (50,50) and vertices
  expect("contained small hazard above ground",
         run(0, 100, 0, 100, 0, {60, 5, 60, 64, 5, 60, 60, 5, 64}, {0, 1, 2}),
         true);
  expect("contained small hazard, reversed winding",
         run(0, 100, 0, 100, 0, {60, 5, 60, 60, 5, 64, 64, 5, 60}, {0, 1, 2}),
         true);
  expect("bridge: ground 5 above hazard at 0",
         run(0, 100, 0, 100, 5, {60, 0, 60, 64, 0, 60, 60, 0, 64}, {0, 1, 2}),
         false);
  expect("bridge over large hazard",
         run(0, 100, 0, 100, 5, {-10, 0, -10, 200, 0, -10, -10, 0, 200},
             {0, 1, 2}),
         false);
  expect("hazard disjoint from ground",
         run(0, 100, 0, 100, 0, {150, 5, 150, 154, 5, 150, 150, 5, 154},
             {0, 1, 2}),
         false);
  expect("hazard sharing only an edge",
         run(0, 100, 0, 100, 0, {100, 5, 0, 110, 5, 0, 100, 5, 10}, {0, 1, 2}),
         false);
  expect("hazard only slightly above (within ch/2)",
         run(0, 100, 0, 100, 0, {60, 0.05f, 60, 64, 0.05f, 60, 60, 0.05f, 64},
             {0, 1, 2}),
         false);
  expect("sloped hazard crosses ground: partly above",
         run(0, 100, 0, 100, 2, {60, -4, 60, 90, 6, 60, 60, 6, 90}, {0, 1, 2}),
         true);
  expect("hazard partially overlapping ground edge",
         run(0, 100, 0, 100, 0, {90, 5, 90, 120, 5, 90, 90, 5, 120}, {0, 1, 2}),
         true);
  expect("negative coordinates bucket key",
         run(-100, 0, -100, 0, 0, {-60, 5, -60, -56, 5, -60, -60, 5, -56},
             {0, 1, 2}, -100, -100),
         true);
  printf("%s\n", fails ? "FAILED" : "ALL PASS");
  return fails != 0;
}
