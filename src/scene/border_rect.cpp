#include "scene/border_rect.h"

extern "C" {
#include <umbrielfx/types/fx/clipped_region.h>
}

namespace umbriel {

  void applyBorderGeometry(wlr_scene_border* border, const BorderRing& ring, int innerWidth, int outerWidth) {
    if (border == nullptr) {
      return;
    }

    wlr_scene_node_set_position(&border->node, ring.box.x, ring.box.y);
    wlr_scene_border_set_geometry(
        border, ring.box.width, ring.box.height, innerWidth, outerWidth,
        clipped_region{.area = ring.hole, .corners = ring.inner}, ring.seam, ring.outer
    );
  }

} // namespace umbriel
