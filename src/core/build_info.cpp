#include "core/build_info.h"

#include "umbriel_git_revision.h"

#ifndef UMBRIEL_VERSION
#define UMBRIEL_VERSION "unknown"
#endif

namespace umbriel::build_info {

  std::string_view version() noexcept { return UMBRIEL_VERSION; }

  std::string_view revision() noexcept { return UMBRIEL_GIT_REVISION; }

} // namespace umbriel::build_info
