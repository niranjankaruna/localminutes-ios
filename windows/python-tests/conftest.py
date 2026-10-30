from pathlib import Path
from uuid import uuid4


def pytest_configure(config):
    (Path(config.rootpath) / ".python-build").mkdir(exist_ok=True)
    if not config.option.basetemp:
        config.option.basetemp = str(Path(config.rootpath) / ".python-build" / ("pytest-" + uuid4().hex))
