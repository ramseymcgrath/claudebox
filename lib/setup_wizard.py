#!/usr/bin/env python3
"""
ClaudeBox Setup Wizard - Interactive Terminal UI

Reads available profiles and plugins from stdin as:
    [profiles]
    name|Description
    [plugins]
    name|Description

Writes results to stdout as KEY=value lines.
All UI renders to /dev/tty so stdout stays clean.
"""

import sys
import os
import re
import tty
import termios
import signal
import atexit
import threading
import subprocess


# ── Styles ────────────────────────────────────────────────────

RESET = '\033[0m'
BOLD = '\033[1m'
DIM = '\033[2m'
RED = '\033[31m'
GREEN = '\033[32m'
YELLOW = '\033[33m'
CYAN = '\033[36m'
WHITE = '\033[37m'
BR_WHITE = '\033[97m'
BR_CYAN = '\033[96m'
BR_GREEN = '\033[92m'
BR_RED = '\033[91m'
BR_YELLOW = '\033[93m'

HIDE_CURSOR = '\033[?25l'
SHOW_CURSOR = '\033[?25h'
CLEAR = '\033[2J\033[H'

NEXT = 'next'
BACK = 'back'
QUIT = 'quit'

SPINNER = ['\u280b', '\u2819', '\u2839', '\u2838',
           '\u283c', '\u2834', '\u2826', '\u2827',
           '\u2807', '\u280f']


# ── Validators ────────────────────────────────────────────────

def validate_org_name(value):
    """Check that value looks like a valid CF org/team name."""
    if not value:
        return True, ''  # empty is allowed (skip)
    value = value.strip()
    if ' ' in value or '\t' in value:
        return False, 'Org name cannot contain spaces'
    if not re.match(r'^[a-zA-Z0-9]([a-zA-Z0-9\-]*[a-zA-Z0-9])?$', value):
        return False, 'Only letters, numbers, and hyphens allowed'
    return True, ''


def validate_nonempty(value):
    """Check that value is not empty or whitespace."""
    if not value or not value.strip():
        return False, 'This field is required'
    return True, ''



def validate_token_field(value):
    """Check that a token field has no spaces and is non-empty."""
    if not value or not value.strip():
        return False, 'This field is required'
    if ' ' in value:
        return False, 'Token cannot contain spaces'
    return True, ''


# ── Terminal ──────────────────────────────────────────────────

class Terminal:
    def __init__(self):
        self.tty_fd = os.open('/dev/tty', os.O_RDWR)
        self.tty_in = os.fdopen(self.tty_fd, 'r', closefd=False)
        self.tty_out = open('/dev/tty', 'w')
        self.old_settings = termios.tcgetattr(self.tty_fd)
        atexit.register(self.restore)
        signal.signal(signal.SIGINT, lambda *_: (self.restore(), sys.exit(130)))
        signal.signal(signal.SIGTERM, lambda *_: (self.restore(), sys.exit(143)))
        self._raw()
        self.write(HIDE_CURSOR)

    def _raw(self):
        new = termios.tcgetattr(self.tty_fd)
        new[3] = new[3] & ~(termios.ECHO | termios.ICANON | termios.ISIG)
        new[1] = new[1] | termios.OPOST | termios.ONLCR
        new[6][termios.VMIN] = 1
        new[6][termios.VTIME] = 0
        termios.tcsetattr(self.tty_fd, termios.TCSANOW, new)

    def restore(self):
        if self.old_settings:
            try:
                termios.tcsetattr(self.tty_fd, termios.TCSADRAIN,
                                  self.old_settings)
            except Exception:
                pass
            self.write(SHOW_CURSOR + RESET)
            self.old_settings = None

    def write(self, text):
        self.tty_out.write(text)
        self.tty_out.flush()

    def size(self):
        try:
            r, c = os.get_terminal_size(self.tty_fd)
            return r, c
        except Exception:
            return 24, 80

    def has_input(self):
        """Non-blocking check if a key has been pressed."""
        import select
        r, _, _ = select.select([self.tty_in], [], [], 0)
        return bool(r)

    def read_key(self):
        ch = self.tty_in.read(1)
        if ch == '\x1b':
            c2 = self.tty_in.read(1)
            if c2 == '[':
                c3 = self.tty_in.read(1)
                if c3 == 'A': return 'up'
                if c3 == 'B': return 'down'
                if c3 == 'C': return 'right'
                if c3 == 'D': return 'left'
                if c3 in '0123456789':
                    c4 = self.tty_in.read(1)
                    if c4 == '~':
                        if c3 == '5': return 'pgup'
                        if c3 == '6': return 'pgdn'
                return 'esc'
            return 'esc'
        if ch in ('\r', '\n'): return 'enter'
        if ch == ' ': return 'space'
        if ch in ('\x7f', '\x08'): return 'bs'
        if ch == '\x03': return 'ctrl-c'
        if ch == '\x04': return 'ctrl-d'
        if ch == '\t': return 'tab'
        return ch


# ── Header helper ─────────────────────────────────────────────

def draw_header(term, title, subtitle, step, total):
    rows, cols = term.size()
    w = min(cols - 4, 64)
    step_txt = 'Step %d/%d' % (step, total)
    pad = max(1, w - len(title) - len(step_txt) - 2)

    term.write(CLEAR)
    term.write('\n  %s%s%s\n' % (DIM, '\u2500' * w, RESET))
    term.write('  %s%s%s%s%s%s%s\n' % (
        BOLD, CYAN, title, RESET,
        ' ' * pad,
        DIM, step_txt + RESET))
    if subtitle:
        term.write('  %s%s%s\n' % (DIM, subtitle, RESET))
    term.write('  %s%s%s\n\n' % (DIM, '\u2500' * w, RESET))


# ── Checkbox screen ───────────────────────────────────────────

class CheckboxScreen:
    def __init__(self, term, title, subtitle, items, step, total,
                 show_back=True):
        self.term = term
        self.title = title
        self.subtitle = subtitle
        self.names = [n for n, _ in items]
        self.descs = [d for _, d in items]
        self.selected = [False] * len(items)
        self.cursor = 0
        self.scroll = 0
        self.step = step
        self.total = total
        self.show_back = show_back

    def set_selected(self, names):
        s = set(names)
        for i, n in enumerate(self.names):
            self.selected[i] = n in s

    def _visible(self):
        rows, _ = self.term.size()
        return max(5, rows - 13)

    def _render(self):
        rows, cols = self.term.size()
        vis = self._visible()
        n = len(self.names)

        draw_header(self.term, self.title, self.subtitle,
                    self.step, self.total)

        if self.cursor < self.scroll:
            self.scroll = self.cursor
        elif self.cursor >= self.scroll + vis:
            self.scroll = self.cursor - vis + 1

        if self.scroll > 0:
            self.term.write('  %s  \u2191 %d more%s\n' % (
                DIM, self.scroll, RESET))

        end = min(self.scroll + vis, n)
        for i in range(self.scroll, end):
            active = i == self.cursor
            sel = self.selected[i]

            arrow = '%s\u276f%s' % (BR_CYAN, RESET) if active else ' '
            box = ('%s[\u2713]%s' % (BR_GREEN, RESET) if sel
                   else '%s[ ]%s' % (DIM, RESET))

            if active:
                name = '%s%s%-16s%s' % (BOLD, BR_WHITE, self.names[i], RESET)
                desc = self.descs[i]
            elif sel:
                name = '%s%-16s%s' % (GREEN, self.names[i], RESET)
                desc = '%s%s%s' % (DIM, self.descs[i], RESET)
            else:
                name = '%-16s' % self.names[i]
                desc = '%s%s%s' % (DIM, self.descs[i], RESET)

            self.term.write('  %s %s %s %s\n' % (arrow, box, name, desc))

        remaining = n - end
        if remaining > 0:
            self.term.write('  %s  \u2193 %d more%s\n' % (
                DIM, remaining, RESET))

        chosen = [self.names[i] for i in range(n) if self.selected[i]]
        self.term.write('\n')
        if chosen:
            txt = ', '.join(chosen)
            maxw = min(cols - 14, 60)
            if len(txt) > maxw:
                txt = txt[:maxw - 3] + '...'
            self.term.write('  %sSelected:%s %s%s%s\n' % (
                DIM, RESET, GREEN, txt, RESET))
        else:
            self.term.write('  %sSelected: (none)%s\n' % (DIM, RESET))

        self.term.write('\n')
        ctrl = '  %s\u2191\u2193 move   Space select   a all   Enter next' % DIM
        if self.show_back:
            ctrl += '   b back'
        ctrl += '   q quit%s' % RESET
        self.term.write(ctrl + '\n')

    def run(self):
        while True:
            self._render()
            key = self.term.read_key()
            n = len(self.names)

            if key in ('up', 'k'):
                if self.cursor > 0:
                    self.cursor -= 1
            elif key in ('down', 'j'):
                if self.cursor < n - 1:
                    self.cursor += 1
            elif key == 'space':
                self.selected[self.cursor] = not self.selected[self.cursor]
            elif key == 'a':
                val = not all(self.selected)
                self.selected = [val] * n
            elif key == 'enter':
                return NEXT
            elif key in ('b', 'left') and self.show_back:
                return BACK
            elif key in ('q', 'ctrl-c', 'ctrl-d'):
                return QUIT
            elif key == 'pgup':
                self.cursor = max(0, self.cursor - self._visible())
            elif key == 'pgdn':
                self.cursor = min(n - 1, self.cursor + self._visible())

    def get_selected(self):
        return [self.names[i] for i in range(len(self.names))
                if self.selected[i]]


# ── Confirm screen ────────────────────────────────────────────

class ConfirmScreen:
    def __init__(self, term, title, subtitle, message, step, total,
                 default=True, show_back=True):
        self.term = term
        self.title = title
        self.subtitle = subtitle
        self.message = message
        self.step = step
        self.total = total
        self.value = default
        self.show_back = show_back

    def _render(self):
        draw_header(self.term, self.title, self.subtitle,
                    self.step, self.total)

        for line in self.message.split('\n'):
            self.term.write('  %s\n' % line)
        self.term.write('\n')

        if self.value:
            self.term.write('  %s\u276f%s %s%sYes%s\n' % (
                BR_CYAN, RESET, BOLD, BR_GREEN, RESET))
            self.term.write('    %sNo%s\n' % (DIM, RESET))
        else:
            self.term.write('    %sYes%s\n' % (DIM, RESET))
            self.term.write('  %s\u276f%s %s%sNo%s\n' % (
                BR_CYAN, RESET, BOLD, BR_GREEN, RESET))

        self.term.write('\n')
        ctrl = '  %s\u2191\u2193 select   Enter confirm' % DIM
        if self.show_back:
            ctrl += '   b back'
        ctrl += '   q quit%s' % RESET
        self.term.write(ctrl + '\n')

    def run(self):
        while True:
            self._render()
            key = self.term.read_key()

            if key in ('up', 'down', 'k', 'j', 'space'):
                self.value = not self.value
            elif key == 'y':
                self.value = True
            elif key == 'n':
                self.value = False
            elif key == 'enter':
                return NEXT
            elif key in ('b', 'left') and self.show_back:
                return BACK
            elif key in ('q', 'ctrl-c', 'ctrl-d'):
                return QUIT


# ── Toggle list screen ────────────────────────────────────────

class ToggleScreen:
    def __init__(self, term, title, subtitle, options, step, total,
                 show_back=True):
        self.term = term
        self.title = title
        self.subtitle = subtitle
        self.keys = [k for k, _, _ in options]
        self.labels = [l for _, l, _ in options]
        self.values = [v for _, _, v in options]
        self.cursor = 0
        self.step = step
        self.total = total
        self.show_back = show_back

    def _render(self):
        draw_header(self.term, self.title, self.subtitle,
                    self.step, self.total)

        for i, (label, val) in enumerate(zip(self.labels, self.values)):
            active = i == self.cursor
            arrow = '%s\u276f%s' % (BR_CYAN, RESET) if active else ' '
            box = ('%s[\u2713]%s' % (BR_GREEN, RESET) if val
                   else '%s[ ]%s' % (DIM, RESET))
            if active:
                text = '%s%s%s%s' % (BOLD, BR_WHITE, label, RESET)
            else:
                text = label
            self.term.write('  %s %s %s\n' % (arrow, box, text))

        self.term.write('\n')
        ctrl = '  %s\u2191\u2193 move   Space toggle   Enter next' % DIM
        if self.show_back:
            ctrl += '   b back'
        ctrl += '   q quit%s' % RESET
        self.term.write(ctrl + '\n')

    def run(self):
        while True:
            self._render()
            key = self.term.read_key()
            n = len(self.keys)

            if key in ('up', 'k'):
                if self.cursor > 0:
                    self.cursor -= 1
            elif key in ('down', 'j'):
                if self.cursor < n - 1:
                    self.cursor += 1
            elif key == 'space':
                self.values[self.cursor] = not self.values[self.cursor]
            elif key == 'enter':
                return NEXT
            elif key in ('b', 'left') and self.show_back:
                return BACK
            elif key in ('q', 'ctrl-c', 'ctrl-d'):
                return QUIT

    def get_values(self):
        return dict(zip(self.keys, self.values))


# ── Input screen with validation ─────────────────────────────

class InputScreen:
    def __init__(self, term, title, subtitle, prompt, step, total,
                 placeholder='', show_back=True, validator=None,
                 required=False):
        self.term = term
        self.title = title
        self.subtitle = subtitle
        self.prompt = prompt
        self.step = step
        self.total = total
        self.placeholder = placeholder
        self.show_back = show_back
        self.validator = validator
        self.required = required
        self.value = ''
        self.error = ''

    def _render(self):
        draw_header(self.term, self.title, self.subtitle,
                    self.step, self.total)

        for line in self.prompt.split('\n'):
            self.term.write('  %s\n' % line)
        self.term.write('\n')

        self.term.write(SHOW_CURSOR)
        if self.value:
            display = self.value
        else:
            display = '%s%s%s' % (DIM, self.placeholder, RESET)
        self.term.write('  %s\u203a%s %s\n' % (BR_CYAN, RESET, display))
        self.term.write(HIDE_CURSOR)

        # Show validation error
        if self.error:
            self.term.write('  %s%s\u2717 %s%s\n' % (
                BR_RED, BOLD, self.error, RESET))
        self.term.write('\n')

        ctrl = '  %sEnter confirm' % DIM
        if self.show_back:
            ctrl += '   Esc back'
        ctrl += '   Ctrl-C quit%s' % RESET
        self.term.write(ctrl + '\n')

    def run(self):
        while True:
            self._render()
            key = self.term.read_key()

            if key == 'enter':
                self.error = ''
                # Required check
                if self.required and not self.value.strip():
                    self.error = 'This field is required'
                    continue
                # Run validator
                if self.validator and self.value:
                    ok, msg = self.validator(self.value)
                    if not ok:
                        self.error = msg
                        continue
                return NEXT
            elif key == 'esc' and self.show_back:
                return BACK
            elif key in ('ctrl-c', 'ctrl-d'):
                return QUIT
            elif key == 'bs':
                if self.value:
                    self.value = self.value[:-1]
                    self.error = ''
            elif isinstance(key, str) and len(key) == 1 and key.isprintable():
                self.value += key
                self.error = ''


# ── Status screen (for async validation) ─────────────────────

class StatusScreen:
    """Shows a spinner while running a background check, then result."""

    def __init__(self, term, title, subtitle, step, total):
        self.term = term
        self.title = title
        self.subtitle = subtitle
        self.step = step
        self.total = total

    def run_check(self, label, check_fn):
        """
        Run check_fn in a background thread, showing a spinner.
        check_fn() should return (success: bool, message: str).
        Returns (success, message).
        """
        result = [None]

        def worker():
            try:
                result[0] = check_fn()
            except Exception as e:
                result[0] = (False, str(e))

        t = threading.Thread(target=worker, daemon=True)
        t.start()

        frame = 0
        import time
        while t.is_alive():
            draw_header(self.term, self.title, self.subtitle,
                        self.step, self.total)
            spin = SPINNER[frame % len(SPINNER)]
            self.term.write('  %s%s%s %s%s%s\n' % (
                BR_CYAN, spin, RESET, DIM, label, RESET))
            self.term.write('\n  %sPress Ctrl-C to cancel%s\n' % (
                DIM, RESET))
            frame += 1
            time.sleep(0.1)

            # Check for ctrl-c
            if self.term.has_input():
                key = self.term.read_key()
                if key in ('ctrl-c', 'ctrl-d', 'q'):
                    return None, 'Cancelled'

        t.join()
        return result[0] if result[0] else (False, 'Unknown error')

    def show_result(self, success, message, extra_lines=None):
        """Show check result and wait for keypress."""
        draw_header(self.term, self.title, self.subtitle,
                    self.step, self.total)

        if success:
            self.term.write('  %s%s\u2713 %s%s\n' % (
                BR_GREEN, BOLD, message, RESET))
        else:
            self.term.write('  %s%s\u2717 %s%s\n' % (
                BR_RED, BOLD, message, RESET))

        if extra_lines:
            self.term.write('\n')
            for line in extra_lines:
                self.term.write('  %s%s%s\n' % (DIM, line, RESET))

        self.term.write('\n')
        self.term.write('  %sPress Enter to continue   b to go back%s\n' % (
            DIM, RESET))

        while True:
            key = self.term.read_key()
            if key == 'enter':
                return NEXT
            elif key in ('b', 'left', 'esc'):
                return BACK
            elif key in ('q', 'ctrl-c', 'ctrl-d'):
                return QUIT


# ── Network validation helpers ────────────────────────────────

def check_gateway_url(account_id, gateway_id):
    """Test connectivity to Cloudflare AI Gateway endpoint."""
    import urllib.request
    import urllib.error
    import ssl

    url = 'https://gateway.ai.cloudflare.com/v1/%s/%s/anthropic' % (
        account_id, gateway_id)
    req = urllib.request.Request(url, method='HEAD')
    req.add_header('User-Agent', 'ClaudeBox-Setup/1.0')
    ctx = ssl.create_default_context()

    try:
        resp = urllib.request.urlopen(req, timeout=10, context=ctx)
        return True, 'Gateway reachable (HTTP %d)' % resp.getcode()
    except urllib.error.HTTPError as e:
        # 4xx from the gateway means the endpoint exists
        if e.code in (400, 401, 403, 404, 405, 415):
            return True, 'Gateway reachable (HTTP %d)' % e.code
        return False, 'HTTP error: %d %s' % (e.code, e.reason)
    except urllib.error.URLError as e:
        reason = str(e.reason) if hasattr(e, 'reason') else str(e)
        return False, 'Connection failed: %s' % reason
    except Exception as e:
        return False, 'Error: %s' % str(e)


def check_docker_available():
    """Check if Docker daemon is reachable."""
    try:
        result = subprocess.run(
            ['docker', 'info'],
            stdout=subprocess.DEVNULL,
            stderr=subprocess.DEVNULL,
            timeout=10)
        if result.returncode == 0:
            return True, 'Docker is running'
        return False, 'Docker daemon not responding'
    except FileNotFoundError:
        return False, 'Docker not found in PATH'
    except subprocess.TimeoutExpired:
        return False, 'Docker timed out'
    except Exception as e:
        return False, 'Docker check failed: %s' % str(e)


# ── Wizard ────────────────────────────────────────────────────

class Wizard:
    def __init__(self, term, profiles, plugins):
        self.term = term
        self.profiles = profiles
        self.plugins = plugins
        self.results = {}
        self.total = 5

    def run(self):
        steps = [
            self._profiles,
            self._slot,
            self._gateway,
            self._plugins,
            self._settings,
        ]
        current = 0
        while 0 <= current < len(steps):
            result = steps[current]()
            if result == NEXT:
                current += 1
            elif result == BACK:
                current = max(0, current - 1)
            elif result == QUIT:
                self._cancelled()
                return False

        self._summary()
        return True

    # ── Steps ─────────────────────────────────────────────────

    def _profiles(self):
        scr = CheckboxScreen(
            self.term, 'Development Profiles',
            'Select profiles for your project',
            self.profiles, 1, self.total, show_back=False)
        if 'profiles' in self.results:
            scr.set_selected(self.results['profiles'])
        r = scr.run()
        if r == NEXT:
            self.results['profiles'] = scr.get_selected()
        return r

    def _slot(self):
        scr = ConfirmScreen(
            self.term, 'Create Container Slot',
            'A slot is an authenticated Claude instance',
            ('You need at least one slot to use ClaudeBox.\n'
             'You can create more later with \'claudebox create\'.\n'
             '\n'
             'Create your first slot now?'),
            2, self.total,
            default=self.results.get('create_slot', True))
        r = scr.run()
        if r == NEXT:
            self.results['create_slot'] = scr.value
            # Validate Docker is available if they want a slot
            if scr.value:
                return self._validate_docker()
        return r

    def _validate_docker(self):
        """Check Docker is running before promising to create a slot."""
        status = StatusScreen(self.term, 'Create Container Slot',
                              'Checking prerequisites', 2, self.total)
        ok, msg = status.run_check('Checking Docker...', check_docker_available)

        if ok is None:
            return QUIT

        if ok:
            r = status.show_result(True, msg,
                                   ['Slot will be created after setup completes.'])
            return r

        r = status.show_result(
            False, msg,
            ['Docker must be running to create slots.',
             'Start Docker and re-run setup, or skip this step.'])
        if r == BACK:
            return BACK
        # Let them continue anyway - Bash side will handle the error
        self.results['create_slot'] = False
        return NEXT

    def _gateway(self):
        scr = ConfirmScreen(
            self.term, 'Cloudflare AI Gateway',
            'Route API traffic through Cloudflare AI Gateway',
            ('AI Gateway provides caching, rate limiting,\n'
             'cost tracking, and logging for API requests.\n'
             '\n'
             'Set up Cloudflare AI Gateway?'),
            3, self.total,
            default=self.results.get('gateway_enabled', False))
        r = scr.run()
        if r == NEXT:
            self.results['gateway_enabled'] = scr.value
            if scr.value:
                return self._gateway_details()
        return r

    def _gateway_details(self):
        # ── Account ID ──
        scr = InputScreen(
            self.term, 'Cloudflare AI Gateway', 'Account ID',
            ('Cloudflare account ID:\n'
             '%sFound in your Cloudflare dashboard URL%s' % (DIM, RESET)),
            3, self.total, placeholder='abc123def456',
            required=True)
        scr.value = self.results.get('gateway_account_id', '')
        r = scr.run()
        if r != NEXT:
            return r
        account_id = scr.value.strip()
        self.results['gateway_account_id'] = account_id

        # ── Gateway ID ──
        scr = InputScreen(
            self.term, 'Cloudflare AI Gateway', 'Gateway ID',
            ('AI Gateway name:\n'
             '%sThe name you gave when creating the gateway%s' % (
                 DIM, RESET)),
            3, self.total, placeholder='my-gateway',
            required=True)
        scr.value = self.results.get('gateway_id', '')
        r = scr.run()
        if r != NEXT:
            return r
        gateway_id = scr.value.strip()
        self.results['gateway_id'] = gateway_id

        # ── API Token ──
        scr = InputScreen(
            self.term, 'Cloudflare AI Gateway', 'API Token',
            ('Cloudflare API token with AI Gateway permissions:\n'
             '%sCreate at: My Profile > API Tokens%s\n'
             '%sPermissions: AI Gateway Read + Edit%s' % (
                 DIM, RESET, DIM, RESET)),
            3, self.total, placeholder='your-api-token',
            required=True)
        scr.value = self.results.get('gateway_token', '')
        r = scr.run()
        if r != NEXT:
            return r
        self.results['gateway_token'] = scr.value.strip()

        # ── Validate gateway connectivity ──
        status = StatusScreen(self.term, 'Cloudflare AI Gateway',
                              'Testing connection', 3, self.total)
        ok, msg = status.run_check(
            'Connecting to AI Gateway...',
            lambda: check_gateway_url(account_id, gateway_id))

        if ok is None:
            return QUIT

        if ok:
            extra = ['Gateway endpoint verified.']
            r = status.show_result(True, msg, extra)
        else:
            extra = ['Could not reach the gateway endpoint.',
                     'Check account ID and gateway name.',
                     '',
                     'You can continue anyway or go back to fix settings.']
            r = status.show_result(False, msg, extra)
        if r == BACK:
            return self._gateway_details()
        return r

    def _plugins(self):
        scr = CheckboxScreen(
            self.term, 'Plugins',
            'Popular Claude Code plugins (optional)',
            self.plugins, 4, self.total)
        if 'plugins' in self.results:
            scr.set_selected(self.results['plugins'])
        r = scr.run()
        if r == NEXT:
            self.results['plugins'] = scr.get_selected()
        return r

    def _settings(self):
        prev = self.results.get('settings', {})
        scr = ToggleScreen(
            self.term, 'Default Settings',
            'Configure default container behavior',
            [('enable_sudo', 'Enable sudo in containers by default',
              prev.get('enable_sudo', False)),
             ('disable_firewall', 'Disable firewall by default',
              prev.get('disable_firewall', False))],
            5, self.total)
        r = scr.run()
        if r == NEXT:
            self.results['settings'] = scr.get_values()
        return r

    # ── Final screens ─────────────────────────────────────────

    def _summary(self):
        self.term.write(CLEAR)
        w = 60
        self.term.write('\n  %s%s%s\n' % (DIM, '\u2500' * w, RESET))
        self.term.write('  %s%sSetup Complete%s\n' % (BOLD, CYAN, RESET))
        self.term.write('  %s%s%s\n\n' % (DIM, '\u2500' * w, RESET))

        profs = self.results.get('profiles', [])
        if profs:
            self.term.write('  %s\u2713%s Profiles: %s\n' % (
                GREEN, RESET, ', '.join(profs)))

        if self.results.get('create_slot'):
            self.term.write('  %s\u2713%s Container slot will be created\n' % (
                GREEN, RESET))

        if self.results.get('gateway_enabled'):
            gw_acct = self.results.get('gateway_account_id', '')
            gw_id = self.results.get('gateway_id', '')
            if gw_acct and gw_id:
                self.term.write('  %s\u2713%s AI Gateway: %s/%s\n' % (
                    GREEN, RESET, gw_acct, gw_id))

        plugs = self.results.get('plugins', [])
        if plugs:
            self.term.write('  %s\u2713%s Plugins: %s\n' % (
                GREEN, RESET, ', '.join(plugs)))

        st = self.results.get('settings', {})
        if st.get('enable_sudo'):
            self.term.write('  %s\u2713%s Sudo enabled by default\n' % (
                GREEN, RESET))
        if st.get('disable_firewall'):
            self.term.write('  %s\u2713%s Firewall disabled by default\n' % (
                GREEN, RESET))

        self.term.write('\n  %sApplying configuration...%s\n\n' % (
            DIM, RESET))

    def _cancelled(self):
        self.term.write(CLEAR)
        self.term.write('\n  %sSetup cancelled.%s\n' % (YELLOW, RESET))
        self.term.write('  %sRun \'claudebox setup\' anytime to try again.'
                        '%s\n\n' % (DIM, RESET))

    def output(self):
        """Print results as KEY=value to stdout."""
        r = self.results
        profs = r.get('profiles', [])
        plugs = r.get('plugins', [])
        st = r.get('settings', {})

        print('PROFILES=%s' % ' '.join(profs))
        print('CREATE_SLOT=%s' % ('yes' if r.get('create_slot') else 'no'))
        print('GATEWAY_ENABLED=%s' % (
            'yes' if r.get('gateway_enabled') else 'no'))

        if r.get('gateway_enabled'):
            print('GATEWAY_ACCOUNT_ID=%s' % r.get('gateway_account_id', ''))
            print('GATEWAY_ID=%s' % r.get('gateway_id', ''))
            print('GATEWAY_TOKEN=%s' % r.get('gateway_token', ''))

        print('PLUGINS=%s' % ' '.join(plugs))
        print('ENABLE_SUDO=%s' % ('yes' if st.get('enable_sudo') else 'no'))
        print('DISABLE_FIREWALL=%s' % (
            'yes' if st.get('disable_firewall') else 'no'))


# ── Config parsing ────────────────────────────────────────────

def parse_config(text):
    profiles = []
    plugins = []
    section = None
    for line in text.strip().split('\n'):
        line = line.strip()
        if not line:
            continue
        if line == '[profiles]':
            section = 'profiles'
            continue
        if line == '[plugins]':
            section = 'plugins'
            continue
        if '|' in line:
            name, desc = line.split('|', 1)
            pair = (name.strip(), desc.strip())
            if section == 'profiles':
                profiles.append(pair)
            elif section == 'plugins':
                plugins.append(pair)
    return profiles, plugins


# ── Main ──────────────────────────────────────────────────────

def main():
    config = sys.stdin.read()
    profiles, plugins = parse_config(config)

    if not profiles and not plugins:
        sys.exit(1)

    term = Terminal()
    wiz = Wizard(term, profiles, plugins)
    try:
        ok = wiz.run()
        term.restore()
        if ok:
            wiz.output()
        else:
            print('CANCELLED=yes')
            sys.exit(1)
    except Exception as e:
        term.restore()
        print('ERROR=%s' % e, file=sys.stderr)
        sys.exit(1)


if __name__ == '__main__':
    main()
