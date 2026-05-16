#!/usr/bin/env python3
# -*- coding: utf-8 -*-
# ---------------------------------------------------------------------------
# Reference for details:
# https://docs.checkmk.com/latest/en/bakery_api.html
# ---------------------------------------------------------------------------

from pathlib import Path

from .bakery_api.v1 import (
    OS,
    Plugin,
    register,
    FileGenerator,
)

DEBUG = False  # Set to True to enable debug output

def get_oracle_dataguard_broker_plugin_files(conf: dict) -> FileGenerator:
    if DEBUG: print(f"Generating Oracle Data Guard Broker plugin files for configuration: {conf}")

    if conf.get('enabled', False):
        for base_os in (OS.LINUX, OS.AIX):
            yield Plugin(
                base_os = base_os,
                source = Path("oracle_dataguard_broker.pl"),
                target = Path("oracle_dataguard_broker.pl"),
            )

register.bakery_plugin(
    name = "oracle_dataguard_broker",
    files_function = get_oracle_dataguard_broker_plugin_files,
)
