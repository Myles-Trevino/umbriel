#pragma once

#include <chrono>
#include <cstdint>
#include <string>
#include <sys/types.h>
#include <utility>
#include <vector>

struct wl_event_loop;
struct wl_event_source;

namespace umbriel {

  // Keeps an xwayland-satellite process alive for the lifetime of the session. Umbriel does not implement X11 itself;
  // xwayland-satellite is a separate program that owns an X display and translates for it. All this class does is pick
  // a display number, spawn the process, notice when it dies, and restart it, with a failure budget, so a satellite
  // that cannot start (missing Xwayland, wrong version) stops rather than spinning forever. Death is detected through a
  // pidfd on the event loop rather than SIGCHLD: the compositor sets SIGCHLD to SIG_IGN so it never has to reap, and a
  // pidfd gives the same notification without a signal handler racing the main loop.
  class XwaylandSupervisor {
  public:
    XwaylandSupervisor(wl_event_loop* loop, std::string waylandSocket);
    ~XwaylandSupervisor();

    XwaylandSupervisor(const XwaylandSupervisor&) = delete;
    XwaylandSupervisor& operator=(const XwaylandSupervisor&) = delete;

    // Find a free display and spawn. Does nothing when xwayland-satellite is not
    // installed, which is a supported configuration rather than an error.
    void start();
    // Stop watching, then signal the child. Safe to call more than once, and
    // called by the destructor.
    void stop();

    // The DISPLAY the satellite owns, or empty when no satellite is running. Children inherit this; when it is empty
    // they must have DISPLAY *unset* rather than inherited, or X11 clients fall back to the outer session.
    [[nodiscard]] const std::string& display() const { return m_display; }
    [[nodiscard]] bool executableAvailable() const { return !m_executable.empty(); }
    [[nodiscard]] pid_t pid() const { return m_pid; }

  private:
    void spawn();
    void handleExit();
    void closeWatch();
    static int onPidfd(int fd, uint32_t mask, void* data);
    static int onRespawnTimer(void* data);

    wl_event_loop* m_loop = nullptr;
    std::string m_waylandSocket;
    std::string m_executable;
    std::string m_display;
    std::vector<std::pair<std::string, std::string>> m_environment;
    pid_t m_pid = -1;
    int m_pidfd = -1;
    wl_event_source* m_exitSource = nullptr;
    wl_event_source* m_respawnTimer = nullptr;
    int m_failures = 0;
    std::chrono::steady_clock::time_point m_spawnTime;
  };

} // namespace umbriel
