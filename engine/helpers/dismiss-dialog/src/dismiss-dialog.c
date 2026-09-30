/*
 * SPDX-License-Identifier: MIT
 *
 * dismiss-dialog: presses one button on a dialog that a named program raises.
 *
 * Usage
 * -----
 *   dismiss-dialog.exe <window title> <program> <button text> <seconds>
 *
 * Runs inside the same Wine session as the program, so it can only see that
 * bottle's windows. A window is touched only when all of these hold:
 *   - it is visible and its title equals <window title> exactly
 *   - the process that owns it has the file name <program>
 * The button is found by its text (an "&" accelerator marker is ignored).
 * When the dialog has no such child window, Return is sent to the dialog
 * instead. It gives up after <seconds> or after MAX_PRESSES presses, and
 * exits without doing anything if no such dialog ever shows up.
 *
 * Why it exists: Kynseed sets its window resizable before its graphics
 * device exists, which raises a .NET error dialog at startup that Continue
 * skips. See CLAUDE.md.
 */
#include <windows.h>
#include <shellapi.h>
#include <stdio.h>
#include <wchar.h>

#define MAX_PRESSES 6
#define POLL_MS     250
#define RETRY_MS    700

typedef struct {
    const wchar_t *title;
    const wchar_t *program;
    const wchar_t *button;
    HWND dialog;
    HWND button_window;
} Target;

static void say(const char *text)
{
    HANDLE out = GetStdHandle(STD_OUTPUT_HANDLE);
    DWORD written;
    if (out != NULL && out != INVALID_HANDLE_VALUE)
        WriteFile(out, text, (DWORD)lstrlenA(text), &written, NULL);
}

static BOOL owned_by(HWND window, const wchar_t *program)
{
    DWORD pid = 0;
    wchar_t path[MAX_PATH];
    DWORD size = MAX_PATH;
    const wchar_t *name;
    HANDLE process;
    BOOL ok;

    GetWindowThreadProcessId(window, &pid);
    process = OpenProcess(PROCESS_QUERY_LIMITED_INFORMATION, FALSE, pid);
    if (process == NULL)
        return FALSE;
    ok = QueryFullProcessImageNameW(process, 0, path, &size);
    CloseHandle(process);
    if (!ok)
        return FALSE;
    name = wcsrchr(path, L'\\');
    name = name != NULL ? name + 1 : path;
    return _wcsicmp(name, program) == 0;
}

static BOOL CALLBACK on_child(HWND child, LPARAM param)
{
    Target *target = (Target *)param;
    wchar_t text[128];
    wchar_t plain[128];
    int from, to = 0;

    if (GetWindowTextW(child, text, 128) == 0)
        return TRUE;
    for (from = 0; text[from] != L'\0'; from++) {
        if (text[from] != L'&')
            plain[to++] = text[from];
    }
    plain[to] = L'\0';
    if (wcscmp(plain, target->button) != 0)
        return TRUE;
    target->button_window = child;
    return FALSE;
}

static BOOL CALLBACK on_window(HWND window, LPARAM param)
{
    Target *target = (Target *)param;
    wchar_t title[256];

    if (!IsWindowVisible(window))
        return TRUE;
    if (GetWindowTextW(window, title, 256) == 0 || wcscmp(title, target->title) != 0)
        return TRUE;
    if (!owned_by(window, target->program))
        return TRUE;
    target->dialog = window;
    target->button_window = NULL;
    EnumChildWindows(window, on_child, param);
    return FALSE;
}

static void click(HWND button)
{
    RECT rect;
    LPARAM where;

    GetClientRect(button, &rect);
    where = MAKELPARAM((rect.right - rect.left) / 2, (rect.bottom - rect.top) / 2);
    PostMessageW(button, WM_LBUTTONDOWN, MK_LBUTTON, where);
    PostMessageW(button, WM_LBUTTONUP, 0, where);
}

static void press_return(HWND window)
{
    PostMessageW(window, WM_KEYDOWN, VK_RETURN, 0x00000001);
    PostMessageW(window, WM_KEYUP, VK_RETURN, 0xC0000001);
}

int WINAPI wWinMain(HINSTANCE instance, HINSTANCE previous, PWSTR command, int show)
{
    int argc = 0;
    wchar_t **argv = CommandLineToArgvW(GetCommandLineW(), &argc);
    Target target;
    unsigned long seconds;
    ULONGLONG deadline;
    int presses = 0;
    char line[256];

    (void)instance; (void)previous; (void)command; (void)show;
    if (argv == NULL || argc != 5) {
        say("usage: dismiss-dialog.exe <window title> <program> <button text> <seconds>\n");
        return 2;
    }
    target.title = argv[1];
    target.program = argv[2];
    target.button = argv[3];
    seconds = wcstoul(argv[4], NULL, 10);
    if (seconds == 0 || seconds > 600) {
        say("dismiss-dialog: seconds must be 1 to 600\n");
        return 2;
    }

    deadline = GetTickCount64() + (ULONGLONG)seconds * 1000ULL;
    while (GetTickCount64() < deadline && presses < MAX_PRESSES) {
        target.dialog = NULL;
        target.button_window = NULL;
        EnumWindows(on_window, (LPARAM)&target);
        if (target.dialog == NULL) {
            Sleep(POLL_MS);
            continue;
        }
        if (target.button_window != NULL && presses % 2 == 0)
            click(target.button_window);
        else
            press_return(target.dialog);
        presses++;
        snprintf(line, sizeof line, "dismiss-dialog: press %d on %ls dialog of %ls (%s)\n",
                 presses, target.title, target.program,
                 target.button_window != NULL && (presses - 1) % 2 == 0 ? "button" : "return");
        say(line);
        Sleep(RETRY_MS);
    }
    return 0;
}
