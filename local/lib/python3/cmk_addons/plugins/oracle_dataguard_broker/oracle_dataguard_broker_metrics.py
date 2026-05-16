#!/usr/bin/env python3

METRIC_DEF = {
    'm5100': {'enabled': True, 'interval': '10m', 'type': 'MAX', 'critical': 'NaN', 'warning': '0.9', 'name': 'Oracle DG Configuration Status',              'alert': "Data Guard Broker configuration for '<OBJECT>' has status: <STATUS>.",                                                        'counter': '',                              },
    'm5110': {'enabled': True, 'interval': '10m', 'type': 'MAX', 'critical': 'NaN', 'warning': '0.9', 'name': 'Oracle DG Database Status',                   'alert': "Data Guard Broker database '<OBJECT>' has status: <STATUS>. <REPORT>",                                                          'counter': '',                              },
    'm5120': {'enabled': True, 'interval': '10m', 'type': 'MAX', 'critical': 'NaN', 'warning': '0.9', 'name': 'Oracle DG Inconsistent Properties',           'alert': "<MONVALUE> inconsistent DG propert(y/ies) found for database '<OBJECT>': <ERRORLINE>",                                          'counter': 'dg_inconsistent_properties',    },
    'm5130': {'enabled': True, 'interval': '10m', 'type': 'MAX', 'critical': 'NaN', 'warning': '0.9', 'name': 'Oracle DG Inconsistent Log Transport Props',  'alert': "<MONVALUE> inconsistent DG log transport propert(y/ies) found for database '<OBJECT>': <ERRORLINE>",                            'counter': 'dg_inconsistent_log_xpt_props', },
}
