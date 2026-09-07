#pragma once

#include "core/animation.h"

#include <array>
#include <map>
#include <optional>
#include <string>
#include <string_view>
#include <unordered_map>
#include <vector>

extern "C" {
#include <wlr/util/box.h>
}

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
    [[nodiscard]] std::string_view nameFor(const View* view) const;
    [[nodiscard]] bool hasScratchpad(std::string_view name) const;
    [[nodiscard]] bool moveToScratchpad(View* view, std::string_view name, Output* invokingOutput);
    bool toggle(std::string_view name, Output* invokingOutput);
    void hideAll();
    bool restoreFocused(std::string_view name);
    bool focusNext(std::string_view name);
    [[nodiscard]] View* focused(std::string_view name) const;
    [[nodiscard]] bool hasFocus(std::string_view name) const;
    void noteFocus(View* view);
    void finishMove(View* view, Output* output);
    // Apply the manager-owned floating presentation after a commit or while a
    // detached view animation advances.
    void syncViewPresentation(View* view, bool refreshMaximized = false);
    // Restore the manager-owned scene parents after a temporary global drag.
    void restorePresentation(View* view);
    void remove(View* view);
    void moveOutput(Output* from, Output* to);
    void releaseOutput(Output* output);
    // Keep assigned scratchpads in output-local coordinates after the output
    // layout or usable area changes.
    void refreshOutputGeometry(Output* output);
    void applyConfig();
    // Reconcile runtime scratchpads after a successful [[scratchpad]] reload.
    // Windows belonging to removed definitions return to their saved workspaces.
    void reconcileConfig();
    // Return entries to the output they were parked on. Entries whose output is still gone park on `fallback`.
    size_t restoreDisplaced(Output* fallback);

  private:
    struct Scratchpad {
      Output* output = nullptr;
      bool visible = false;
      View* lastFocused = nullptr;
      // Set only while an output disappearance has temporarily parked this
      // scratchpad elsewhere.
      std::string displacedOutput;
      std::optional<wlr_box> usableArea;
    };

    struct Entry {
      View* view = nullptr;
      std::string scratchpad;
      std::string returnOutput;
      // Full-output-relative x/y fractions retained until the displaced output returns.
      std::optional<std::array<double, 2>> displacedPosition;
      std::string returnWorkspace;
      bool returnTiled = false;
    };

    [[nodiscard]] Scratchpad* findScratchpad(std::string_view name);
    [[nodiscard]] const Scratchpad* findScratchpad(std::string_view name) const;
    [[nodiscard]] Entry* findEntry(const View* view);
    [[nodiscard]] const Entry* findEntry(const View* view) const;
    [[nodiscard]] bool hasEntries(std::string_view name) const;
    [[nodiscard]] bool visibleOn(Output* output) const;
    void setVisible(std::string_view name, bool visible, bool animateTransition = true);
    void moveScratchpad(
        std::string_view name, Output* output, View* alreadyPositioned = nullptr, bool clearDisplacement = true
    );
    void remapViewRestoreGeometry(View* view, const wlr_box& previousArea, const wlr_box& targetArea);
    bool restoreView(View* view, Output* fallback, bool focus);
    // Retarget the backdrop dim/blur fade for `output` and refresh its scene nodes.
    void retargetBackdrop(Output* output, bool visible, bool animateTransition = true);
    wlr_scene_rect* dimRectFor(Output* output);
    wlr_scene_blur* blurNodeFor(Output* output);
    void updateDimAndBlur(Output* output);

    Server* m_server = nullptr;
    wlr_scene_tree* m_root = nullptr;
    wlr_scene_tree* m_shadowRoot = nullptr;
    std::map<std::string, Scratchpad, std::less<>> m_scratchpads;
    std::vector<Entry> m_entries;
    // Views mid fade-out on hide, still enabled until tickAnimations disables the node once the fade completes.
    std::vector<View*> m_hidingViews;
    std::unordered_map<Output*, wlr_scene_rect*> m_dimRects;
    std::unordered_map<Output*, wlr_scene_blur*> m_blurNodes;
    std::unordered_map<Output*, AnimatedValue> m_backdropFades;
    View* m_focusedView = nullptr;
  };

} // namespace umbriel
