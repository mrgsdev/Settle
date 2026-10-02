#include <flutter/dart_project.h>
#include <flutter/flutter_view_controller.h>
#include <windows.h>

#include <algorithm>

#include "flutter_window.h"
#include "utils.h"

int APIENTRY wWinMain(_In_ HINSTANCE instance, _In_opt_ HINSTANCE prev,
                      _In_ wchar_t *command_line, _In_ int show_command) {
  // Attach to console when present (e.g., 'flutter run') or create a
  // new console when running with a debugger.
  if (!::AttachConsole(ATTACH_PARENT_PROCESS) && ::IsDebuggerPresent()) {
    CreateAndAttachConsole();
  }

  // Initialize COM, so that it is available for use in the library and/or
  // plugins.
  ::CoInitializeEx(nullptr, COINIT_APARTMENTTHREADED);

  flutter::DartProject project(L"data");

  std::vector<std::string> command_line_arguments =
      GetCommandLineArguments();

  project.set_dart_entrypoint_arguments(std::move(command_line_arguments));

  FlutterWindow window(project);
  // Open a 1440x900 window centered on the primary work area.
  RECT work_area;
  ::SystemParametersInfo(SPI_GETWORKAREA, 0, &work_area, 0);
  const POINT primary_point = {0, 0};
  const double scale = FlutterDesktopGetDpiForMonitor(::MonitorFromPoint(
                           primary_point, MONITOR_DEFAULTTOPRIMARY)) /
                       96.0;
  const int work_left = static_cast<int>(work_area.left / scale);
  const int work_top = static_cast<int>(work_area.top / scale);
  const int work_width =
      static_cast<int>((work_area.right - work_area.left) / scale);
  const int work_height =
      static_cast<int>((work_area.bottom - work_area.top) / scale);
  const int width = (std::max)(800, (std::min)(1440, work_width - 40));
  const int height = (std::max)(600, (std::min)(900, work_height - 40));
  const int left = (std::max)(0, work_left + (work_width - width) / 2);
  const int top = (std::max)(0, work_top + (work_height - height) / 2);
  Win32Window::Point origin(static_cast<unsigned int>(left),
                            static_cast<unsigned int>(top));
  Win32Window::Size size(static_cast<unsigned int>(width),
                         static_cast<unsigned int>(height));
  if (!window.Create(L"Settle", origin, size)) {
    return EXIT_FAILURE;
  }
  window.SetQuitOnClose(true);

  ::MSG msg;
  while (::GetMessage(&msg, nullptr, 0, 0)) {
    ::TranslateMessage(&msg);
    ::DispatchMessage(&msg);
  }

  ::CoUninitialize();
  return EXIT_SUCCESS;
}
