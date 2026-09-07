#pragma once

#include "core/animation.h"

#include <array>
#include <optional>
#include <string>
#include <unordered_map>
#include <vector>

struct wlr_scene_tree;
struct wlr_scene_rect;
struct wlr_scene_blur;

namespace umbriel {

  class Output;
  class Server;
  class View;
  class Workspace;
  class ScratchpadManager : public Animatable {
  public:
    ScratchpadManager(Server& server, wlr_scene_tree* root, wlr_scene_tree* shadowRoot);
    ~ScratchpadManager() override;

    [[nodiscard]] AnimationPhase animationPhase() const override { return AnimationPhase::Overlays; }
    bool tickAnimations(uint64_t nowMsec) override;
    [[nodiscard]] bool hasActiveAnimations() const override;
    [[nodiscard]] bool animatesOn(const Output* output) const override;

    [[nodiscard]] bool contains(const View* view) const;
    [[nodiscard]] Output* outputFor(const View* view) const;
    [[nodiscard]] bool moveToScratchpad(View* view, Output* output);
    bool toggle(Output* output);
    void hideAll();
    bool restoreFocused(Output* output);
    bool focusNext(Output* output);
    [[nodiscard]] View* focused(Output* output) const;
    [[nodiscard]] bool hasFocus(Output* output) const;
    void noteFocus(View* view);
    void finishMove(View* view, Output* output);
    // Apply the manager-owned floating presentation after a commit or while a
    // detached view animation advances.
    void syncViewPresentation(View* view);
    // Restore the manager-owned scene parents after a temporary global drag.
    void restorePresentation(View* view);
    void remove(View* view);
    void moveOutput(Output* from, Output* to);
    void releaseOutput(Output* output);
    void applyConfig();
    // Return entries to the output they were parked on. Entries whose output is still gone park on `fallback`.
    size_t restoreDisplaced(Output* fallback);

  private:
    struct Entry {
      View* view = nullptr;
      Output* output = nullptr;
      std::string returnOutput;
      std::string displacedOutput;
      // Full-output-relative x/y fractions retained until the displaced output returns.
      std::optional<std::array<double, 2>> displacedPosition;
      std::string returnWorkspace;
      bool returnTiled = false;
      bool lastFocused = false;
    };

    void setVisible(Output* output, bool visible, bool animateTransition = true);
    // Retarget the backdrop dim/blur fade for `output` and refresh its scene nodes.
    void retargetBackdrop(Output* output, bool visible, bool animateTransition = true);
    wlr_scene_rect* dimRectFor(Output* output);
    wlr_scene_blur* blurNodeFor(Output* output);
    void updateDimAndBlur(Output* output);

    Server* m_server = nullptr;
    wlr_scene_tree* m_root = nullptr;
    wlr_scene_tree* m_shadowRoot = nullptr;
    std::vector<Entry> m_entries;
    std::vector<Output*> m_visibleOutputs;
    // Views mid fade-out on hide, still enabled until tickAnimations disables the node once the fade completes.
    std::vector<View*> m_hidingViews;
    std::unordered_map<Output*, wlr_scene_rect*> m_dimRects;
    std::unordered_map<Output*, wlr_scene_blur*> m_blurNodes;
    std::unordered_map<Output*, AnimatedValue> m_backdropFades;
    View* m_focusedView = nullptr;
  };

} // namespace umbriel
