#!/usr/bin/env python3
"""Drive one Logger prompt scenario through an isolated POSIX PTY.

Dart's standard library cannot create a controlling PTY, so this helper owns
only the terminal setup and key presses, and reports what it saw back to the
Dart test as JSON.
"""

import argparse
import errno
import json
import os
import pty
import re
import select
import signal
import sys
import termios
import time

ROLE_ENVIRONMENT_KEY = "FVM_LOGGER_PROMPT_PTY_ROLE"
SCENARIO_ENVIRONMENT_KEY = "FVM_LOGGER_PROMPT_PTY_SCENARIO"
READY = b"FVM_PROMPT_TEST:READY"
RESULT_PATTERN = re.compile(rb"FVM_PROMPT_TEST:RESULT:([^\r\n]*)")
EXIT_PATTERN = re.compile(rb"FVM_PROMPT_TEST:EXIT:(\d+)")
HIDE_CURSOR = b"\x1b[?25l"
SHOW_CURSOR = b"\x1b[?25h"


def _read_once(master_fd, output, timeout):
    readable, _, _ = select.select([master_fd], [], [], timeout)
    if not readable:
        return
    try:
        output.extend(os.read(master_fd, 65536))
    except OSError as error:
        if error.errno != errno.EIO:
            raise


def _wait_for(master_fd, output, predicate, description, timeout):
    deadline = time.monotonic() + timeout
    while time.monotonic() < deadline:
        if predicate():
            return
        _read_once(master_fd, output, 0.05)
    if not predicate():
        raise RuntimeError(f"Timed out waiting for {description}")


def _in_raw_mode(master_fd):
    lflag = termios.tcgetattr(master_fd)[3]
    return not (lflag & termios.ICANON) and not (lflag & termios.ECHO)


def _in_cooked_mode(master_fd):
    lflag = termios.tcgetattr(master_fd)[3]
    return bool(lflag & termios.ICANON) and bool(lflag & termios.ECHO)


def _run(args):
    keys = [bytes.fromhex(key) for key in args.keys.split(",") if key]

    child_pid, master_fd = pty.fork()
    if child_pid == 0:
        environment = os.environ.copy()
        environment[ROLE_ENVIRONMENT_KEY] = "prompt"
        environment[SCENARIO_ENVIRONMENT_KEY] = args.scenario
        os.chdir(args.cwd)
        os.execve(args.dart, [args.dart, args.harness], environment)

    output = bytearray()
    reaped = False
    status = None

    try:
        os.set_blocking(master_fd, False)
        _wait_for(master_fd, output, lambda: READY in output, "READY", 30)

        for index, key in enumerate(keys):
            # dart_console turns raw mode on only while it waits for a key, so
            # raw mode means the prompt is ready for the next one.
            _wait_for(
                master_fd,
                output,
                lambda: _in_raw_mode(master_fd),
                f"raw mode before key {index}",
                10,
            )
            os.write(master_fd, key)
            # Let the prompt read the key and leave raw mode before the next.
            time.sleep(0.3)

        _wait_for(
            master_fd,
            output,
            lambda: RESULT_PATTERN.search(output) or EXIT_PATTERN.search(output),
            "a result or an exit",
            10,
        )

        # The harness pauses after reporting an exit, so the terminal can be
        # checked while the process is still alive.
        cooked_after_prompt = _in_cooked_mode(master_fd)

        deadline = time.monotonic() + 10
        while not reaped and time.monotonic() < deadline:
            _read_once(master_fd, output, 0.05)
            waited_pid, waited_status = os.waitpid(child_pid, os.WNOHANG)
            if waited_pid != 0:
                reaped = True
                status = waited_status
        if not reaped or status is None:
            raise RuntimeError("Timed out waiting for the Dart harness to exit")
        _read_once(master_fd, output, 0.1)

        result = RESULT_PATTERN.search(output)
        exit_request = EXIT_PATTERN.search(output)
        return {
            "result": result.group(1).decode() if result else None,
            "exitRequested": int(exit_request.group(1)) if exit_request else None,
            "exitCode": os.WEXITSTATUS(status) if os.WIFEXITED(status) else None,
            "terminalRestored": cooked_after_prompt,
            "cursorShown": output.rfind(SHOW_CURSOR) > output.rfind(HIDE_CURSOR),
            "transcript": output.decode("utf-8", "replace"),
        }
    except Exception as error:
        transcript = repr(bytes(output))
        raise RuntimeError(f"{error}\nPTY transcript: {transcript}") from error
    finally:
        try:
            os.kill(child_pid, signal.SIGKILL)
        except ProcessLookupError:
            pass
        try:
            os.close(master_fd)
        except OSError:
            pass
        if not reaped:
            try:
                os.waitpid(child_pid, 0)
            except ChildProcessError:
                pass


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--dart", required=True)
    parser.add_argument("--harness", required=True)
    parser.add_argument("--cwd", required=True)
    parser.add_argument("--scenario", required=True)
    parser.add_argument(
        "--keys",
        required=True,
        help="Comma-separated key presses, each as hex bytes",
    )
    args = parser.parse_args()

    try:
        report = _run(args)
    except Exception as error:
        print(error, file=sys.stderr)
        return 1

    print(json.dumps(report, sort_keys=True))
    return 0


if __name__ == "__main__":
    sys.exit(main())
