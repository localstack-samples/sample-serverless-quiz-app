"""Registered as an early pytest plugin via pytest.ini's `addopts = -p tests._version_guard`.

Early `-p` plugins are imported before pytest autoloads setuptools
entry-point plugins (see `_pytest.config.Config._preparse`). `localstack-sdk-python`
registers one such entry-point plugin, and on Python < 3.10 it crashes at
import time with `TypeError: unsupported operand type(s) for |: 'type' and
'NoneType'` (it uses `X | Y` type hints). Failing fast here, before that
plugin loads, turns that cryptic error into an actionable one.
"""
import sys

MIN_VERSION = (3, 11)

if sys.version_info < MIN_VERSION:
    sys.exit(
        "Python {}.{}+ is required to run this test suite (found {}.{}.{}), "
        "because localstack-sdk-python needs 3.10+ type-hint syntax.\n"
        "Recreate the virtualenv with a newer interpreter, e.g.:\n"
        "  python3.11 -m venv .venv".format(
            *MIN_VERSION, *sys.version_info[:3]
        )
    )
