#!/usr/bin/env python3

from cmk.rulesets.v1 import Title, Help, Label
from cmk.rulesets.v1.form_specs import (
    BooleanChoice,
    DefaultValue,
    DictElement,
    Dictionary,
)

from cmk.rulesets.v1.rule_specs import (
    AgentConfig,
    CheckParameters,
    HostAndItemCondition,
    Topic,
)

from cmk_addons.plugins.oracle_dataguard_broker.oracle_dataguard_broker_metrics import METRIC_DEF
from cmk_addons.plugins.oracle_dataguard_broker.rulesets.ruleset_oracle_dataguard_broker_lib import metric_dict_elements


def _agent_parameter_form():
    return Dictionary(
        title=Title("Oracle Data Guard Broker Agent Plugin"),
        help_text=Help("Deploy the Oracle Data Guard Broker agent plugin to monitored hosts."),
        elements={
            "enabled": DictElement(
                parameter_form=BooleanChoice(
                    label=Label("Enable Oracle Data Guard Broker agent plugin"),
                    prefill=DefaultValue(True),
                ),
                required=True,
            ),
        },
    )


rule_spec_oracle_dataguard_broker_agent = AgentConfig(
    name="oracle_dataguard_broker",
    title=Title("Oracle Data Guard Broker"),
    topic=Topic.DATABASES,
    parameter_form=_agent_parameter_form,
)


def _parameter_form():
    return Dictionary(
        title=Title("Oracle Data Guard Broker Thresholds"),
        help_text=Help("Configure thresholds for specific Oracle Data Guard Broker counters."),
        elements=metric_dict_elements(METRIC_DEF),
    )


rule_spec_oracle_dataguard_broker = CheckParameters(
    name="oracle_dataguard_broker_parameters",
    title=Title("Oracle Data Guard Broker Metrics"),
    topic=Topic.DATABASES,
    parameter_form=_parameter_form,
    condition=HostAndItemCondition(item_title=Title("Oracle Data Guard Broker Metrics")),
)
