# Oracle Data Guard Broker — Checkmk Extension Package (MKP)

> Developed and maintained by **[TazamaTech Software GmbH](https://www.tazamatech.com)** — a software company
> specializing in monitoring, automation, and IT infrastructure solutions.
>
> Need help with this project? TazamaTech offers professional support contracts covering
> installation, configuration, and ongoing assistance. Contact us at
> [Support@TazamaTech.com](mailto:Support@TazamaTech.com).

---

Checkmk extension for monitoring Oracle Data Guard Broker. Collects configuration
status, database status, and property consistency data from every monitored host
via the Checkmk agent and evaluates the results on the Checkmk server.

---

## Table of Contents

1. [Requirements — Checkmk Agent Host](#1-requirements--checkmk-agent-host)
2. [Requirements — Checkmk Server](#2-requirements--checkmk-server)
3. [Oracle Data Guard Broker](#3-oracle-data-guard-broker)
   - [3.1 Deploy the Agent Plugin](#31-deploy-the-agent-plugin)
   - [3.2 Adjusting Thresholds via Rules](#32-adjusting-thresholds-via-rules)
   - [3.3 How the Bakery Works](#33-how-the-bakery-works)
   - [3.4 Metric Reference](#34-metric-reference)
4. [Troubleshooting](#4-troubleshooting)

---

## 1. Requirements — Checkmk Agent Host

### Operating system

| Platform | `oracle_dataguard_broker.pl` |
|----------|------------------------------|
| Linux (x86-64, ARM) | Yes |
| AIX | Yes |
| Windows | Yes (manual deployment only) |

### Software

| Requirement | Notes |
|-------------|-------|
| Checkmk agent | Version matching the server (2.3.x or later) |
| Perl | 5.10 or later; standard installation, no extra modules needed |
| Oracle Database 11.2 or later | Provides `dgmgrl` and `sqlplus` |
| Data Guard Broker | Must be enabled (`dg_broker_start = TRUE`) on at least one instance |

### Required permissions

| Command | Privilege | OS group |
|---------|-----------|----------|
| `sqlplus / as sysdba` | `SYSDBA` | `dba` |
| `dgmgrl / as sysdg` | `SYSDG` (12c+) or `SYSDBA` | `dgdba` or `dba` |

The Checkmk agent user must belong to the **`dba`** OS group (covers both
commands on all Oracle versions). On Oracle 12c and later, the least-privilege
option is to add the user to **`dgdba`** (for `dgmgrl / as sysdg`) and grant
`SELECT_CATALOG_ROLE` in Oracle (for `sqlplus` access to `V$PARAMETER` without
SYSDBA):

```bash
usermod -aG dgdba cmk
```

```sql
-- As sysdba:
CREATE USER cmk IDENTIFIED EXTERNALLY;
GRANT SELECT_CATALOG_ROLE TO cmk;
```

### Firewall / connectivity

No additional network ports are required. The plugin runs locally on the agent
host and its output is collected by the standard Checkmk agent mechanism.

---

## 2. Requirements — Checkmk Server

| Requirement | Value |
|-------------|-------|
| Checkmk version | **2.3.0p1 or later** |
| Edition for agent baking | **CEE / CCE / MSP** (Enterprise editions) |
| Edition for manual deployment | **All editions** (RAW included) |

The check plugins, rulesets, and graphing definitions work on all editions.
The **bakery** (automatic agent deployment) requires an Enterprise edition with
the Agent Bakery feature enabled.

---

## 3. Oracle Data Guard Broker

### 3.1 Deploy the Agent Plugin

#### Oracle environment

The plugin discovers Oracle instances automatically using the following strategy:

1. **oratab** — reads `/etc/oratab` or `/var/opt/oracle/oratab` for all
   non-ASM entries whose Oracle home contains `dgmgrl`.
2. **Windows registry** — reads `HKLM\SOFTWARE\ORACLE` for `ORACLE_SID` and
   `ORACLE_HOME` pairs where `dgmgrl.exe` is present.
3. **Environment fallback** — uses `$ORACLE_SID` and `$ORACLE_HOME` if set.

For each discovered instance, the plugin checks whether Data Guard Broker is
enabled by querying `dg_broker_start` from `V$PARAMETER` via SQL*Plus. Instances
where the parameter is not `TRUE` are silently skipped — no data is emitted and
no Checkmk service is created.

The plugin requires access to:
- `$ORACLE_HOME/bin/sqlplus` — to check if `dg_broker_start = TRUE` (metric guard)
- `$ORACLE_HOME/bin/dgmgrl` — to collect broker metrics (5100–5130)

#### Option A — Agent Bakery (CEE/CCE/MSP only, recommended)

1. Go to **Setup → Agent rules → Agent plugins** (or search for
   *Oracle Data Guard Broker*).
2. Create a rule that matches your Oracle hosts and set **enabled = true**.
3. Go to **Setup → Agents → Windows, Linux, Solaris, AIX** and click
   **Bake agents**.
4. Deploy the newly baked agent to the target hosts via your normal mechanism.

The baked agent places the plugin at:

```
/usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl   (Linux)
/usr/check_mk/lib/plugins/oracle_dataguard_broker.pl         (AIX)
```

#### Option B — Manual deployment (all editions)

```bash
# Linux
cp oracle_dataguard_broker.pl /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl
chmod 755 /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl

# AIX
cp oracle_dataguard_broker.pl /usr/check_mk/lib/plugins/oracle_dataguard_broker.pl
chmod 755 /usr/check_mk/lib/plugins/oracle_dataguard_broker.pl

# Windows — copy to the agent plugins directory
copy oracle_dataguard_broker.pl "C:\Program Files (x86)\checkmk\service\plugins\"
```

#### Verify the plugin runs

```bash
cmk-agent-ctl dump | grep -A 20 'oracle_dataguard_broker'
```

Expected output (one instance `prim` with broker enabled):

```
<<<oracle_dataguard_broker:sep(124)>>>
prim|5100|0|STATUS=SUCCESS|None|None|None|None
prim|5110|0|STATUS=SUCCESS|REPORT=|None|None|None
prim|5120|0|None|None|None|None|None
prim|5130|0|None|None|None|None|None
```

---

### 3.2 Adjusting Thresholds via Rules

**Setup → Service monitoring rules → Oracle Data Guard Broker Metrics**

Each metric has three independently configurable parameters:

| Parameter | Description |
|-----------|-------------|
| **Enabled** | Toggle the metric on or off. Disabled metrics produce no service and no alert. |
| **Warning** | Threshold value that triggers a WARNING state. Accepts a number or `NaN` (disabled). |
| **Critical** | Threshold value that triggers a CRITICAL state. Accepts a number or `NaN` (disabled). |
| **Threshold type** | Read-only: `MAX` = alert when value *exceeds* the threshold. |

Default thresholds:

| Metric | Type | Warning | Critical | Enabled |
|--------|------|---------|----------|---------|
| m5100 — DG Configuration Status | MAX | `0.9` | `NaN` | Yes |
| m5110 — DG Database Status | MAX | `0.9` | `NaN` | Yes |
| m5120 — Inconsistent Properties | MAX | `0.9` | `NaN` | Yes |
| m5130 — Inconsistent Log Transport Props | MAX | `0.9` | `NaN` | Yes |

Services are **item-based** — one Checkmk service is created per SID per metric
(e.g. `Oracle DG Configuration Status prim`). Use the item filter in the rule
condition to target specific instances.

---

### 3.3 How the Bakery Works

- If **enabled**, the bakery includes `oracle_dataguard_broker.pl` in the baked
  agent package for **Linux** and **AIX** targets.
- If **disabled**, the script is not included.
- **Windows** is not supported by the bakery plugin; deploy manually if needed.
- No configuration file is generated — there are no user-configurable exclusions.

---

### 3.4 Metric Reference

All metrics are emitted in the agent section
`<<<oracle_dataguard_broker:sep(124)>>>` using a pipe (`|`) separator.
Output line format:

```
OBJECT | MetricNumber | Value | Option1 | Option2 | Option3 | Option4 | Option5
```

Where `OBJECT` is the Oracle SID. Check interval: **10 minutes**.

---

#### m5100 — DG Configuration Status

| | |
|-|-|
| Source | `dgmgrl show configuration` |
| Value | `0` = SUCCESS, `1` = WARNING, `2` = ERROR |
| Threshold type | MAX |
| Default warning | `0.9` — triggers on WARNING or ERROR |
| Default critical | `NaN` — disabled |
| Enabled by default | Yes |
| Service name | `Oracle DG Configuration Status <SID>` |

**Alert message:** `Data Guard Broker configuration for '<SID>' has status: <STATUS>.`

---

#### m5110 — DG Database Status

| | |
|-|-|
| Source | `dgmgrl show database 'SID'` + `show database 'SID' 'StatusReport'` |
| Value | `0` = SUCCESS, `1` = WARNING, `2` = ERROR |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` |
| Enabled by default | Yes |
| Service name | `Oracle DG Database Status <SID>` |

**Alert message:** `Data Guard Broker database '<SID>' has status: <STATUS>. <REPORT>`

---

#### m5120 — Inconsistent Properties

| | |
|-|-|
| Source | `dgmgrl show database 'SID' 'InconsistentProperties'` |
| Value | Count of inconsistent properties (`0` = healthy) |
| Threshold type | MAX |
| Default warning | `0.9` — triggers on any inconsistency |
| Default critical | `NaN` |
| Enabled by default | Yes |
| Service name | `Oracle DG Inconsistent Properties <SID>` |
| Performance counter | `dg_inconsistent_properties` |

**Alert message:** `<N> inconsistent DG propert(y/ies) found for database '<SID>': <ERRORLINE>`

---

#### m5130 — Inconsistent Log Transport Properties

| | |
|-|-|
| Source | `dgmgrl show database 'SID' 'InconsistentLogXptProps'` |
| Value | Count of inconsistent log transport properties (`0` = healthy) |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` |
| Enabled by default | Yes |
| Service name | `Oracle DG Inconsistent Log Transport Props <SID>` |
| Performance counter | `dg_inconsistent_log_xpt_props` |

**Alert message:** `<N> inconsistent DG log transport propert(y/ies) found for database '<SID>': <ERRORLINE>`

---

## 4. Troubleshooting

### Agent-side issues

#### `oracle_dataguard_broker` section missing entirely

```bash
ls -l /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl
perl -c /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl
sudo perl /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl
```

#### Section header present but no data rows

Either no instances with `dgmgrl` were found, or broker is not enabled
(`dg_broker_start != TRUE`) on any discovered instance.

```bash
# Check oratab
cat /etc/oratab

# Verify dgmgrl exists
test -x /u01/app/oracle/product/19c/db/bin/dgmgrl && echo "OK" || echo "MISSING"

# Check dg_broker_start parameter
echo "SHOW PARAMETER dg_broker_start;" | sqlplus -s / as sysdba
```

#### dgmgrl connect failure (warning in stderr)

The agent user must be in the `dba` or `dgdba` OS group:

```bash
id <agent-user>
sudo -u <agent-user> /u01/app/oracle/product/19c/db/bin/dgmgrl / as sysdg "show configuration;"
```

---

### Server-side issues

#### Service shows UNKNOWN — "No data received for `<item>`"

- Verify the agent plugin is running and producing output (see agent-side steps).
- Verify the metric is enabled in the active ruleset.
- Run a full re-discovery if the plugin was recently deployed or updated:

```bash
cmk -II <hostname>
cmk -R
```

Or via the web interface: **Setup → Hosts → <hostname> → Run service discovery**.

#### Services not discovered after MKP import

```bash
cmk -II <hostname>
cmk -R
```

#### Thresholds not applied

Rules are evaluated in Checkmk's standard precedence order. Use the **Analyse**
button on the rule set page to verify which rule is effective for a given host
and service. Confirm that the metric is marked **enabled** in the active rule.

#### Performance graphs missing for m5120 / m5130

Verify the service is in OK or WARN state — UNKNOWN state suppresses metric
storage. Confirm the counter name matches the graphing definition by checking
the service's performance data tab in the monitoring view.
