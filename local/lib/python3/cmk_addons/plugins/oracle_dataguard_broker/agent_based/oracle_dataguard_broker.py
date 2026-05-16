#!/usr/bin/env python3

from collections.abc import Mapping

try:
    from cmk.ccc import debug
except ImportError:
    from cmk.utils import debug

from cmk.agent_based.v2 import (
    AgentSection,
    CheckPlugin,
    CheckResult,
    DiscoveryResult,
    StringTable,
)

from cmk_addons.plugins.oracle_dataguard_broker.oracle_dataguard_broker_metrics import METRIC_DEF

from cmk_addons.plugins.oracle_dataguard_broker.agent_based.oracle_dataguard_broker_lib import (
    MetricData,
    parse_oracle,
    discover_oracle,
    check_oracle,
    cluster_check_oracle,
)

agent_section_oracle_dataguard_broker = AgentSection(
    name = "oracle_dataguard_broker",
    parse_function = parse_oracle,
)

_default_parameters = { k: {m: v.get(m, '') for m in ('enabled', 'type', 'critical', 'warning')} for k,v in METRIC_DEF.items() }

# Below is generated code

def discover_oracle_m5100(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5100')

def check_oracle_m5100(item: str, params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(item, params, section, 'm5100', METRIC_DEF)

def cluster_check_oracle_m5100(item: str, params, section) -> CheckResult:
    yield from cluster_check_oracle(item, params, section, 'm5100', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5100 = CheckPlugin(
    name = 'oracle_m5100',
    sections = ['oracle_dataguard_broker'],
    service_name = 'Oracle DG Configuration Status %s',
    discovery_function = discover_oracle_m5100,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_dataguard_broker_parameters',
    check_function = check_oracle_m5100,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_dataguard_broker_parameters',
    cluster_check_function = cluster_check_oracle_m5100,
)

def discover_oracle_m5110(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5110')

def check_oracle_m5110(item: str, params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(item, params, section, 'm5110', METRIC_DEF)

def cluster_check_oracle_m5110(item: str, params, section) -> CheckResult:
    yield from cluster_check_oracle(item, params, section, 'm5110', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5110 = CheckPlugin(
    name = 'oracle_m5110',
    sections = ['oracle_dataguard_broker'],
    service_name = 'Oracle DG Database Status %s',
    discovery_function = discover_oracle_m5110,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_dataguard_broker_parameters',
    check_function = check_oracle_m5110,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_dataguard_broker_parameters',
    cluster_check_function = cluster_check_oracle_m5110,
)

def discover_oracle_m5120(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5120')

def check_oracle_m5120(item: str, params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(item, params, section, 'm5120', METRIC_DEF)

def cluster_check_oracle_m5120(item: str, params, section) -> CheckResult:
    yield from cluster_check_oracle(item, params, section, 'm5120', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5120 = CheckPlugin(
    name = 'oracle_m5120',
    sections = ['oracle_dataguard_broker'],
    service_name = 'Oracle DG Inconsistent Properties %s',
    discovery_function = discover_oracle_m5120,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_dataguard_broker_parameters',
    check_function = check_oracle_m5120,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_dataguard_broker_parameters',
    cluster_check_function = cluster_check_oracle_m5120,
)

def discover_oracle_m5130(params, section: Mapping[str, MetricData]) -> DiscoveryResult:
    yield from discover_oracle(params, section, 'm5130')

def check_oracle_m5130(item: str, params, section: Mapping[str, MetricData]) -> CheckResult:
    yield from check_oracle(item, params, section, 'm5130', METRIC_DEF)

def cluster_check_oracle_m5130(item: str, params, section) -> CheckResult:
    yield from cluster_check_oracle(item, params, section, 'm5130', 'WorstOf', METRIC_DEF)

check_plugin_oracle_m5130 = CheckPlugin(
    name = 'oracle_m5130',
    sections = ['oracle_dataguard_broker'],
    service_name = 'Oracle DG Inconsistent Log Transport Props %s',
    discovery_function = discover_oracle_m5130,
    discovery_default_parameters = _default_parameters,
    discovery_ruleset_name = 'oracle_dataguard_broker_parameters',
    check_function = check_oracle_m5130,
    check_default_parameters = _default_parameters,
    check_ruleset_name = 'oracle_dataguard_broker_parameters',
    cluster_check_function = cluster_check_oracle_m5130,
)
