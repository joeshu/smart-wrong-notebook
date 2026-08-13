#!/usr/bin/env python3
"""Parse a `flutter test --machine` JSON-lines result file and emit GitHub
Actions annotations for failures / errors, then exit non-zero when any test
failed.

This is used by CI so the test summary shows which test failed inline. It is a
standalone script (no heredoc) so it works both in a normal `run:` step and in
actions (e.g. android-emulator-runner) that execute each script line separately.

Usage: python3 scripts/parse_flutter_test.py <test-results.jsonl>
"""
import json
import sys
from pathlib import Path


def esc(message: str) -> str:
    return message.replace('%', '%25').replace('\r', '%0D').replace('\n', '%0A')


def main() -> int:
    if len(sys.argv) < 2:
        print('usage: parse_flutter_test.py <test-results.jsonl>', file=sys.stderr)
        return 2
    path = Path(sys.argv[1])
    if not path.exists():
        print(f'::error title=Flutter Test::result file not found: {path}')
        return 1

    lines = path.read_text(encoding='utf-8', errors='replace').splitlines()
    tests = {}
    failures = 0
    for raw in lines:
        try:
            event = json.loads(raw)
        except json.JSONDecodeError:
            continue
        if not isinstance(event, dict):
            continue
        etype = event.get('type')
        if etype == 'testStart':
            test = event.get('test') or {}
            tests[test.get('id')] = test.get('name', test.get('url', 'unknown test'))
        elif etype == 'print' and ('EXCEPTION' in str(event.get('message')) or 'TestFailure' in str(event.get('message'))):
            message = str(event.get('message', 'Test failure'))[:1200]
            print(f'::error title=Flutter Test exception::{esc(message)}')
            failures += 1
        elif etype == 'error':
            message = str(event.get('error', 'Test error'))[:1200]
            print(f'::error title=Flutter Test error::{esc(message)}')
            failures += 1
        elif etype == 'testDone' and event.get('result') not in ('success', 'skipped'):
            test_id = event.get('testID')
            message = f"{tests.get(test_id, test_id)} ({event.get('result')})"
            print(f'::error title=Flutter Test failed::{esc(message)}')
            failures += 1

    total = len(tests)
    if total == 0:
        # flutter test produced no machine events -> it likely crashed (compile
        # error, runner crash) rather than running tests. Surface as a failure.
        print(f'::error title=Flutter Test::no tests recorded in {path} '
              f'(flutter test may have crashed before producing results)')
        return 1

    print(f'Flutter tests: {total} started, {failures} failure(s).')
    return 1 if failures > 0 else 0


if __name__ == '__main__':
    sys.exit(main())
