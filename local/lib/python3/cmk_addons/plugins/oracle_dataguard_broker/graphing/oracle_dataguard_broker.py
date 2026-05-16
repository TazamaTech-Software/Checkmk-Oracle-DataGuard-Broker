#!/usr/bin/env python3

from cmk.graphing.v1 import Title
from cmk.graphing.v1.graphs import Graph, MinimalRange
from cmk.graphing.v1.metrics import Color, DecimalNotation, Metric, Unit
from cmk.graphing.v1.perfometers import Closed, FocusRange, Open, Perfometer

from cmk_addons.plugins.oracle_dataguard_broker.oracle_dataguard_broker_metrics import METRIC_DEF


metric_oracle_m5120 = Metric(
    name = METRIC_DEF['m5120']['counter'],
    title = Title("Oracle DG Inconsistent Properties"),
    unit = Unit(DecimalNotation("")),
    color = Color.LIGHT_BLUE,
)
perfometer_oracle_m5120 = Perfometer(
    name = METRIC_DEF['m5120']['counter'],
    focus_range = FocusRange(Closed(0), Open(10)),
    segments = [ METRIC_DEF['m5120']['counter'] ],
)

metric_oracle_m5130 = Metric(
    name = METRIC_DEF['m5130']['counter'],
    title = Title("Oracle DG Inconsistent Log Transport Properties"),
    unit = Unit(DecimalNotation("")),
    color = Color.LIGHT_BLUE,
)
perfometer_oracle_m5130 = Perfometer(
    name = METRIC_DEF['m5130']['counter'],
    focus_range = FocusRange(Closed(0), Open(10)),
    segments = [ METRIC_DEF['m5130']['counter'] ],
)
