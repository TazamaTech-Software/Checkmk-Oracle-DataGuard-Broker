# Oracle Data Guard Broker — Checkmk MKP Technical Documentation

## Table of Contents

1. [Overview](#1-overview)
2. [Requirements](#2-requirements)
   - [2.1 Checkmk Agent Requirements](#21-checkmk-agent-requirements)
   - [2.2 Checkmk Server Requirements](#22-checkmk-server-requirements)
3. [Installation & Configuration](#3-installation--configuration)
   - [3.1 Importing the MKP](#31-importing-the-mkp)
   - [3.2 Deploying the Agent Script](#32-deploying-the-agent-script)
   - [3.3 Configuring Rules in Checkmk](#33-configuring-rules-in-checkmk)
   - [3.4 How the Bakery Works](#34-how-the-bakery-works)
4. [Monitored Metrics & Services](#4-monitored-metrics--services)
   - [4.1 Service Overview](#41-service-overview)
   - [4.2 Metric Descriptions](#42-metric-descriptions)
   - [4.3 Check States & Logic](#43-check-states--logic)
5. [Troubleshooting](#5-troubleshooting)
   - [5.1 Agent-Side Troubleshooting](#51-agent-side-troubleshooting)
   - [5.2 Server-Side Troubleshooting](#52-server-side-troubleshooting)
6. [Uninstallation](#6-uninstallation)
7. [Security Considerations](#7-security-considerations)
8. [Known Limitations & Compatibility Notes](#8-known-limitations--compatibility-notes)
9. [Appendix](#9-appendix)
   - [9.1 File Structure of the MKP](#91-file-structure-of-the-mkp)
   - [9.2 Example Agent Output](#92-example-agent-output)
   - [9.3 Glossary](#93-glossary)
   - [9.4 References & Further Reading](#94-references--further-reading)

---

## 1. Overview

**Oracle Data Guard Broker** is a Checkmk Monitoring Extension Package (MKP)
that monitors Oracle Data Guard Broker configuration and database status. It
discovers Oracle instances with `dg_broker_start = TRUE` and checks broker
health via `dgmgrl`, emitting one Checkmk service per SID per metric.

| Attribute | Value |
|-----------|-------|
| Plugin type | Agent-based (Perl agent plugin + Python check plugins) |
| Agent section | `oracle_dataguard_broker` |
| Separator | Pipe (`\|`, ASCII 124) |
| Number of check plugins | 4 |
| Number of WATO rule sets | 2 (agent config + check parameters) |
| Check interval | 10 minutes (all metrics) |
| Services | Item-based — one service per SID per metric |
| Cluster-aware | Yes — all check plugins implement `cluster_check_function` |
| Cluster algorithm | WorstOf (reports the worst state across all cluster nodes) |

### Supported Checkmk editions

| Edition | Supported | Notes |
|---------|-----------|-------|
| Checkmk Raw (CRE) | Yes | Manual agent deployment only; no bakery |
| Checkmk Standard (CSE) | Yes | Manual agent deployment only; no bakery |
| Checkmk Cloud (CCE) | Yes | Full support including bakery |
| Checkmk Enterprise (CEE) | Yes | Full support including bakery |
| Checkmk MSP (CME) | Yes | Full support including bakery |

### Supported Checkmk versions

| Version | Status |
|---------|--------|
| 2.3.x | Supported (minimum required) |
| 2.4.x | Supported |

### Changelog

| Version | Date | Summary |
|---------|------|---------|
| 1.0.0 | 2026-05-05 | Initial release — configuration status, database status, inconsistent properties, inconsistent log transport properties |

---

## 2. Requirements

### 2.1 Checkmk Agent Requirements

#### Operating system

| Platform | Bakery deployment | Manual deployment |
|----------|------------------|-------------------|
| Linux (x86-64, ARM) | Yes | Yes |
| AIX | Yes | Yes |
| Windows | No | Yes |

> **NOTE:** The Agent Bakery deploys the plugin for Linux and AIX only. On
> Windows, the plugin must be placed in the agent plugins directory manually.
> All four metrics are supported on all platforms where the corresponding
> Oracle binaries are present.

#### Software on the monitored host

| Requirement | Version / Notes |
|-------------|-----------------|
| Checkmk agent | Must match the server version (2.3.x or later) |
| Perl | 5.10 or later; no CPAN modules required — the plugin is fully self-contained |
| Oracle Database | 11.2 or later; provides `dgmgrl` and `sqlplus` |
| Data Guard Broker | Must be configured and `dg_broker_start = TRUE` on at least one instance |

The plugin calls Oracle binaries directly:
- `$ORACLE_HOME/bin/sqlplus` — to verify `dg_broker_start = TRUE` before
  attempting any dgmgrl calls
- `$ORACLE_HOME/bin/dgmgrl` — to collect all four broker metrics

Both binaries must be present in the Oracle home. The plugin discovers Oracle
homes automatically and sets `ORACLE_HOME` before each invocation.

#### Oracle instance discovery

The plugin resolves Oracle instances at runtime from multiple sources:

1. **oratab** — `/etc/oratab` (Linux) or `/var/opt/oracle/oratab` (AIX/Solaris).
   All non-ASM entries (SID not starting with `+`) whose Oracle home contains
   `bin/dgmgrl` are included.
2. **Windows registry** — `HKLM\SOFTWARE\ORACLE` and
   `HKLM\SOFTWARE\WOW6432Node\ORACLE`. All `ORACLE_SID` / `ORACLE_HOME` pairs
   where `dgmgrl.exe` is present are included.
3. **Environment variables** — `$ORACLE_SID` and `$ORACLE_HOME` if set and the
   home contains `dgmgrl`.

Duplicate `SID:ORAHOME` pairs are deduplicated across all sources.

#### Broker enablement check

For each discovered instance the plugin connects to SQL*Plus as SYSDBA and
queries:

```sql
SELECT VALUE FROM V$PARAMETER WHERE NAME = 'dg_broker_start';
```

If the result is not `TRUE`, the instance is silently skipped. No dgmgrl
commands are run and no output is emitted for that SID. This prevents spurious
errors on hosts that have Oracle installed but are not part of a Data Guard
configuration.

#### Required user permissions

| Command | Minimum Oracle privilege | OS group (Linux) |
|---------|--------------------------|------------------|
| `sqlplus / as sysdba` | `SYSDBA` | `dba` |
| `dgmgrl / as sysdg` | `SYSDG` (Oracle 12c+) or `SYSDBA` | `dgdba` (12c+) or `dba` |

Adding the Checkmk agent OS user to the **`dba`** group covers both commands
on all Oracle versions. For least-privilege on Oracle 12c+, add the user to
**`dgdba`** (for dgmgrl) and grant `SELECT_CATALOG_ROLE` or direct `SELECT` on
`V$PARAMETER` (for sqlplus without SYSDBA).

Example (Linux — agent runs as `cmk`, Oracle user is `oracle`):

```bash
usermod -aG dba cmk
# Or for least-privilege on 12c+:
usermod -aG dgdba cmk
```

```sql
-- And in Oracle (as sysdba):
CREATE USER cmk IDENTIFIED EXTERNALLY;
GRANT SELECT_CATALOG_ROLE TO cmk;
```

#### Network ports

None. All data is collected via local process execution (`sqlplus`, `dgmgrl`).
No TCP/UDP ports are opened by the plugin.

#### Required environment variables and config files

| Resource | Purpose | Required |
|----------|---------|----------|
| `/etc/oratab` or `/var/opt/oracle/oratab` | Oracle instance discovery | No — only needed if homes cannot be discovered from environment |
| `$ORACLE_SID` | Explicit SID override | No — discovered automatically |
| `$ORACLE_HOME` | Explicit Oracle home override | No — discovered automatically |
| `$MK_TEMPDIR` | Temp directory for dgmgrl spool files | No — falls back to `$TEMP`/`$TMP` or `/tmp` |

The plugin sets the following environment variables before executing Oracle
commands, ensuring English-language output regardless of OS locale:

```
ORACLE_SID         = <SID for current instance>
ORACLE_HOME        = <discovered home for each invocation>
LD_LIBRARY_PATH    = <ORACLE_HOME>/lib
LIBPATH            = <ORACLE_HOME>/lib   (AIX)
SRVM_PROPERTY_DEFS = -Duser.language=en -Duser.country=US
NLS_LANG           = AMERICAN_AMERICA
```

---

### 2.2 Checkmk Server Requirements

#### Minimum version and edition

| Attribute | Value |
|-----------|-------|
| Minimum Checkmk version | **2.3.0p1** |
| Bakery support | Enterprise, Cloud, and MSP editions only |
| Check and rule functionality | All editions |

#### Python environment

The check plugins use only Python packages that ship with Checkmk 2.3+:

| Package | Source |
|---------|--------|
| `cmk.agent_based.v2` | Checkmk core |
| `cmk.rulesets.v1` | Checkmk core |
| `cmk.graphing.v1` | Checkmk core |
| `cmk.ccc.debug` / `cmk.utils.debug` | Checkmk core (version-dependent path) |

No pip packages or third-party libraries are required.

#### Disk space

Metrics m5120 and m5130 emit performance counters (`dg_inconsistent_properties`
and `dg_inconsistent_log_xpt_props`). Checkmk creates one RRD file per
counter per service on the Checkmk server. Metrics m5100 and m5110 are
status enums and produce no RRD data.

#### Permissions on the Checkmk server

Standard Checkmk site-user permissions are sufficient. No elevated privileges
are required to install or run this MKP.

---

## 3. Installation & Configuration

### 3.1 Importing the MKP

#### Via the web interface

1. Download the latest `oracle_dataguard_broker-X.Y.Z.mkp` from the
   [Releases page](https://github.com/TazamaTech-Software/Checkmk-Oracle-DataGuard-Broker/releases).
2. Log in to Checkmk as an administrator.
3. Navigate to **Setup → Extension packages**.
4. Click **Upload package**, select the `.mkp` file, and click **Upload**.
5. The package appears in the list with status **Enabled**.

> **NOTE:** No site restart is required. Extension packages are loaded
> dynamically in Checkmk 2.3+.

#### Via the command line

Log in as the Checkmk site user, then:

```bash
# Copy the MKP to the site first (if needed)
scp oracle_dataguard_broker-1.0.0.mkp <checkmk-server>:/tmp/

# Install
mkp install /tmp/oracle_dataguard_broker-1.0.0.mkp

# Verify
mkp list | grep oracle_dataguard_broker
```

Expected output of `mkp list`:

```
oracle_dataguard_broker  1.0.0  Oracle DataGuard Broker Monitoring
```

#### Building the MKP locally

The repository includes a self-contained build script that requires only
Python 3 and the `local/` directory tree:

```powershell
# Windows (PowerShell, from the repository root)
python build.py --version 1.0.0

# Linux / macOS
python3 build.py --version 1.0.0
```

This produces `oracle_dataguard_broker-1.0.0.mkp` in the current directory.
To write the output to a subdirectory:

```bash
python3 build.py --version 1.0.0 --output-dir dist/
```

#### Verifying successful installation

```bash
# Confirm the agent plugin is present on the Checkmk server
ls -l ~/local/share/check_mk/agents/plugins/oracle_dataguard_broker.pl

# Check that Python files are importable
python3 -c "import cmk_addons.plugins.oracle_dataguard_broker.oracle_dataguard_broker_metrics"
```

The two rule sets appear in the Checkmk web interface under:
- **Setup → Agents → Agent rules** → search **Oracle Data Guard Broker** (agent config rule)
- **Setup → Service monitoring rules** → search **Oracle Data Guard Broker** (check parameters rule)

---

### 3.2 Deploying the Agent Script

#### What the script does

`oracle_dataguard_broker.pl` is a self-contained Perl script that:

1. Discovers all Oracle instances from oratab, Windows registry, and environment.
2. Filters to instances whose Oracle home contains `dgmgrl`.
3. For each instance, sets the Oracle environment and queries `V$PARAMETER` via
   SQL*Plus to verify `dg_broker_start = TRUE`. Instances where the broker is
   not enabled are silently skipped.
4. For broker-enabled instances, runs `dgmgrl -silent` with a command script
   that spools output for `show configuration`, `show database`, and property
   consistency queries.
5. Parses the spooled output and emits metrics 5100–5130 as pipe-delimited
   Checkmk agent section rows.

The script has no external Perl module dependencies. Temp files (dgmgrl command
script and spool files) are written to `$MK_TEMPDIR` and cleaned up after each
run.

#### Option A — Agent Bakery (Enterprise/Cloud/MSP only, recommended)

> **NOTE:** This option requires a Checkmk edition that includes the Agent
> Bakery (CEE, CCE, or CME). It is not available in Checkmk Raw or Standard.

1. In Checkmk go to **Setup → Agents → Agent rules** and search for
   **Oracle Data Guard Broker**.
2. Create a new rule, set **enabled = true**, and assign the rule to the host
   group or folder containing your Oracle Data Guard hosts.
3. Navigate to **Setup → Agents → Windows, Linux, Solaris, AIX** and click
   **Bake agents**.
4. Deploy the baked agent package to the target hosts using your normal
   mechanism (Checkmk auto-update, Ansible, manual RPM/DEB install, etc.).

The baked agent places the plugin at:

```
# Linux
/usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl

# AIX
/usr/check_mk/lib/plugins/oracle_dataguard_broker.pl
```

#### Option B — Manual deployment (all editions)

```bash
# Linux
sudo cp oracle_dataguard_broker.pl /usr/lib/check_mk_agent/plugins/
sudo chmod 755 /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl
sudo chown root:root /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl

# AIX
cp oracle_dataguard_broker.pl /usr/check_mk/lib/plugins/
chmod 755 /usr/check_mk/lib/plugins/oracle_dataguard_broker.pl
```

```cmd
:: Windows — copy to the agent plugins directory
copy oracle_dataguard_broker.pl "C:\Program Files (x86)\checkmk\service\plugins\"
```

#### Triggering service discovery after deployment

After the script is deployed and producing output, run a service discovery on
the host:

```bash
# As site user — discover new services
cmk -I <hostname>

# Apply changes
cmk -R
```

Or via the web interface: **Setup → Hosts → <hostname> → Run service discovery**.

#### Verifying the script output

```bash
# Run as root on the monitored host (Linux)
perl /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl

# From the Checkmk server, inspect cached agent output
cmk --debug --cache <hostname> | grep -A 20 'oracle_dataguard_broker'

# Or dump a fresh agent run via the agent controller
cmk-agent-ctl dump | grep -A 20 'oracle_dataguard_broker'
```

Expected output (two broker-enabled instances: `prim` and `standby`):

```
<<<oracle_dataguard_broker:sep(124)>>>
prim|5100|0|STATUS=SUCCESS|None|None|None|None
prim|5110|0|STATUS=SUCCESS|REPORT=|None|None|None
prim|5120|0|None|None|None|None|None
prim|5130|0|None|None|None|None|None
standby|5100|0|STATUS=SUCCESS|None|None|None|None
standby|5110|0|STATUS=SUCCESS|REPORT=|None|None|None
standby|5120|0|None|None|None|None|None
standby|5130|0|None|None|None|None|None
```

---

### 3.3 Configuring Rules in Checkmk

#### Locating the rule set

**Setup → Service monitoring rules → Oracle Data Guard Broker Metrics**

(Direct path: search "Oracle Data Guard Broker" in the Setup search bar.)

Rule set name (internal identifier): `oracle_dataguard_broker_parameters`

The rule set appears under the **Databases** topic.

#### Available parameters

The rule contains one sub-section per metric. Each metric has four fields:

| Parameter | Type | Accepted values | Description |
|-----------|------|-----------------|-------------|
| `enabled` | Boolean | `true` / `false` | Whether the metric is evaluated. Disabled metrics produce no service and no alert, even if data is present in the agent output. |
| `warning` | String (numeric or `NaN`) | Any number or literal `NaN` | Threshold value for WARNING state. `NaN` disables the WARNING threshold. |
| `critical` | String (numeric or `NaN`) | Any number or literal `NaN` | Threshold value for CRITICAL state. `NaN` disables the CRITICAL threshold. |
| `type` | Read-only string | `MAX` | Direction of threshold comparison. Fixed to MAX for all metrics — alert when value *exceeds* the threshold. |

#### Default parameter values

| Metric | enabled | type | warning | critical |
|--------|---------|------|---------|----------|
| m5100 — DG Configuration Status | `true` | MAX | `0.9` | `NaN` |
| m5110 — DG Database Status | `true` | MAX | `0.9` | `NaN` |
| m5120 — Inconsistent Properties | `true` | MAX | `0.9` | `NaN` |
| m5130 — Inconsistent Log Transport Props | `true` | MAX | `0.9` | `NaN` |

These defaults are compiled into the check plugin (`check_default_parameters`
in `oracle_dataguard_broker.py`) and apply when no matching WATO rule exists.

#### Threshold semantics

- **m5100 / m5110** — Status enum: `0` = SUCCESS, `1` = WARNING, `2` = ERROR.
  A warning threshold of `0.9` triggers on any non-SUCCESS value. To escalate
  ERROR directly to CRITICAL, set `critical = 1.9` (and `warning = 0.9`).
- **m5120 / m5130** — Counts of inconsistent properties. `0` = healthy; any
  positive value indicates a problem. A warning threshold of `0.9` triggers
  on any non-zero count. Set `critical = 0.9` to escalate to CRITICAL instead
  of WARNING.

#### Item-based rule conditions

Services are item-based. The item is the Oracle SID (e.g. `prim`). Use the
**Item** filter in the rule condition to target thresholds at specific
instances.

#### Example rule configurations

**Escalate ERROR configuration status directly to CRITICAL:**

```
m5100:
  enabled: true
  type: MAX        (read-only)
  warning: 0.9
  critical: 1.9
```

**Disable inconsistent property monitoring for a specific host:**

```
m5120:
  enabled: false
m5130:
  enabled: false
```

**Apply a stricter threshold to a specific SID by item filter:**

Set the rule condition item filter to `prim` to apply the rule only to the
primary database instance.

---

### 3.4 How the Bakery Works

#### What is baked

The bakery plugin (`cmk/base/cee/plugins/bakery/oracle_dataguard_broker.py`)
is called by the Agent Bakery when generating agent packages. When the plugin
is enabled via a WATO rule (`conf['enabled'] == True`), it:

1. Includes `oracle_dataguard_broker.pl` in the baked package for:
   - `OS.LINUX` — deployed to `/usr/lib/check_mk_agent/plugins/`
   - `OS.AIX` — deployed to `/usr/check_mk/lib/plugins/`

No configuration file is generated. There are no user-configurable exclusions
for this plugin.

If the plugin is **disabled** (no matching rule, or rule explicitly sets
`enabled = false`), the Perl script is not included. Windows is not supported
by the bakery plugin; deploy manually if needed.

#### Baking workflow

**GUI:**

1. Configure the agent rule (Section 3.3).
2. Go to **Setup → Agents → Windows, Linux, Solaris, AIX**.
3. Click **Bake agents** and wait for the bake job to complete.
4. Deploy the agent package via your normal mechanism.

**CLI (as site user):**

```bash
# Bake all agents
cmk -v --bake-agents

# Bake for a specific host only
cmk -v --bake-agents <hostname>
```

#### Verifying baked content

```bash
# List baked agent packages
ls /omd/sites/<site>/var/check_mk/agents/

# Inspect a specific package (replace with actual filename)
tar -tzf /omd/sites/<site>/var/check_mk/agents/<package>.tar.gz | grep oracle
```

You should see `plugins/oracle_dataguard_broker.pl` in the archive.

> **WARNING:** Do not modify `oracle_dataguard_broker.pl` inside a baked
> package. Changes to the source file must be made in
> `local/share/check_mk/agents/plugins/oracle_dataguard_broker.pl` (on the
> Checkmk server), followed by a new bake and re-deployment.

---

## 4. Monitored Metrics & Services

### 4.1 Service Overview

Services are **item-based** — one service is created per SID per metric type.
The service item is the Oracle SID, making each service uniquely identifiable
by instance name.

| Service Name Template | Check Plugin | Default | Description |
|---|---|---|---|
| `Oracle DG Configuration Status <SID>` | `oracle_m5100` | Enabled | Broker configuration status via `show configuration` |
| `Oracle DG Database Status <SID>` | `oracle_m5110` | Enabled | Database status via `show database` |
| `Oracle DG Inconsistent Properties <SID>` | `oracle_m5120` | Enabled | Inconsistent properties count |
| `Oracle DG Inconsistent Log Transport Props <SID>` | `oracle_m5130` | Enabled | Inconsistent log transport properties count |

Example service names on a host with two broker-enabled instances:

```
Oracle DG Configuration Status prim
Oracle DG Configuration Status standby
Oracle DG Database Status prim
Oracle DG Database Status standby
Oracle DG Inconsistent Properties prim
Oracle DG Inconsistent Properties standby
Oracle DG Inconsistent Log Transport Props prim
Oracle DG Inconsistent Log Transport Props standby
```

All four check plugins read from the same agent section
(`oracle_dataguard_broker`) and implement `cluster_check_function`. In a
Checkmk cluster object, each service aggregates data from all cluster nodes
using the WorstOf algorithm.

---

### 4.2 Metric Descriptions

#### m5100 — DG Configuration Status

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5100` |
| Service name | `Oracle DG Configuration Status <SID>` |
| Source command | `dgmgrl show configuration` |
| Value type | Status enum |
| Unit | `0` = SUCCESS, `1` = WARNING, `2` = ERROR |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` (disabled) |
| Performance counter | None |
| Enabled by default | Yes |

Parses the `Configuration Status:` field from the `show configuration` output.
Reflects the overall health of the Data Guard Broker configuration including
all members. A value of `1` (WARNING) or `2` (ERROR) triggers an alert.
`UNKNOWN` and `DISABLED` statuses are silently ignored (no metric emitted).

**Alert text:** `Data Guard Broker configuration for '<OBJECT>' has status: <STATUS>.`

---

#### m5110 — DG Database Status

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5110` |
| Service name | `Oracle DG Database Status <SID>` |
| Source command | `dgmgrl show database 'SID'` + `show database 'SID' 'StatusReport'` |
| Value type | Status enum |
| Unit | `0` = SUCCESS, `1` = WARNING, `2` = ERROR |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` (disabled) |
| Performance counter | None |
| Enabled by default | Yes |

Parses the `Database Status:` and `Database Error(s):` fields from
`show database` output. When the status is WARNING or ERROR, the
`StatusReport` property is also parsed to extract per-instance severity and
error text, which is included in the alert description via `OPTION2=REPORT=`.

**Alert text:** `Data Guard Broker database '<OBJECT>' has status: <STATUS>. <REPORT>`

---

#### m5120 — Inconsistent Properties

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5120` |
| Service name | `Oracle DG Inconsistent Properties <SID>` |
| Source command | `dgmgrl show database 'SID' 'InconsistentProperties'` |
| Value type | Count |
| Unit | Number of inconsistent properties (0 = healthy) |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` (disabled) |
| Performance counter | `dg_inconsistent_properties` |
| Enabled by default | Yes |

Counts the number of properties listed in the `InconsistentProperties` output
where the instance name matches the SID. A count greater than zero indicates
that one or more broker properties have a value that differs between the broker
configuration and the database memory or spfile. The list of property names is
included in the alert description.

**Alert text:** `<N> inconsistent DG propert(y/ies) found for database '<OBJECT>': <ERRORLINE>`

---

#### m5130 — Inconsistent Log Transport Properties

| Attribute | Value |
|-----------|-------|
| Check plugin | `oracle_m5130` |
| Service name | `Oracle DG Inconsistent Log Transport Props <SID>` |
| Source command | `dgmgrl show database 'SID' 'InconsistentLogXptProps'` |
| Value type | Count |
| Unit | Number of inconsistent log transport properties (0 = healthy) |
| Threshold type | MAX |
| Default warning | `0.9` |
| Default critical | `NaN` (disabled) |
| Performance counter | `dg_inconsistent_log_xpt_props` |
| Enabled by default | Yes |

Counts the number of properties listed in the `InconsistentLogXptProps` output
where the instance name matches the SID. Inconsistent log transport properties
can cause redo transport failures between primary and standby. The list of
affected standby-and-property pairs is included in the alert description.

**Alert text:** `<N> inconsistent DG log transport propert(y/ies) found for database '<OBJECT>': <ERRORLINE>`

---

### 4.3 Check States & Logic

#### State calculation

All four check plugins share a single state calculation function (`calc_state`
in `oracle_dataguard_broker_lib.py`). All metrics use **MAX** threshold type:

```
if value > critical  →  CRIT   (when critical ≠ NaN)
if value > warning   →  WARN   (when warning ≠ NaN)
otherwise            →  OK
```

CRITICAL is evaluated before WARNING. With the default threshold of
`warning = 0.9` and `critical = NaN`:
- m5100 / m5110: any non-SUCCESS status (value ≥ 1) triggers WARNING.
- m5120 / m5130: any non-zero inconsistency count triggers WARNING.

#### Disabled metric behavior

If a metric is marked `enabled = false` in the active rule, the check function
returns without yielding any result. The service will show OK regardless of the
measured value. To fully suppress the service, disable it in the rule *before*
running discovery, or manually remove the service.

#### No-data behavior

If the agent section contains no data row for a given item and metric, the
check function yields:

```
State.UNKNOWN — "No data received for <item>"
```

This occurs when the agent plugin stopped running, the SID was removed from the
host, or the broker was disabled on the instance after the service was already
discovered. UNKNOWN state does not write to the RRD.

#### Cluster behavior

All four check plugins implement `cluster_check_function` using the **WorstOf**
algorithm:

- Each node's individual state is calculated using the same `calc_state` logic.
- `State.worst(*node_states.values())` selects the most severe state across all
  nodes.
- In a Data Guard cluster object, each node independently runs the agent plugin
  and reports broker metrics for its local SID. WorstOf ensures that a problem
  on any node is surfaced at the cluster level.
- If a SID is present on one node but absent (or broker-disabled) on another,
  only the nodes that report data contribute to the cluster result.

---

## 5. Troubleshooting

### 5.1 Agent-Side Troubleshooting

#### Running the plugin manually

```bash
# Run as root on the monitored host (Linux)
perl /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl

# AIX
perl /usr/check_mk/lib/plugins/oracle_dataguard_broker.pl

# With stderr (connection failures and skip messages)
perl /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl 2>/tmp/dg_debug.log
cat /tmp/dg_debug.log
```

If the script emits only the section header with no data rows:

```
<<<oracle_dataguard_broker:sep(124)>>>
```

Either no Oracle home with `dgmgrl` was found, or `dg_broker_start` is not
`TRUE` for any discovered instance.

#### Common errors and solutions

---

**No Oracle home discovered (empty section)**

```bash
# Inspect oratab
cat /etc/oratab | grep -v '^#' | grep -v '^$'

# Locate dgmgrl manually
find /u01 /app /oracle -name dgmgrl 2>/dev/null

# Test with explicit override
ORACLE_SID=prim ORACLE_HOME=/u01/app/oracle/product/19c/db \
  perl /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl
```

If the explicit override works, set `ORACLE_HOME` and `ORACLE_SID` in the
Checkmk agent environment, or add the correct entry to `/etc/oratab`:

```
prim:/u01/app/oracle/product/19c/db:N
```

---

**Section header present but no data rows — broker not enabled**

The plugin found Oracle instances but `dg_broker_start` is not `TRUE`:

```bash
# Check parameter as agent user or root
export ORACLE_SID=prim
export ORACLE_HOME=/u01/app/oracle/product/19c/db
echo "SET PAGESIZE 0 FEEDBACK OFF HEADING OFF
SELECT VALUE FROM V\$PARAMETER WHERE NAME = 'dg_broker_start';
EXIT" | $ORACLE_HOME/bin/sqlplus -s / as sysdba
```

If it returns `FALSE`, set the parameter in Oracle and restart the broker:

```sql
ALTER SYSTEM SET dg_broker_start = TRUE SCOPE=BOTH;
```

---

**dgmgrl connect failure (warning in stderr)**

```
oracle_dataguard_broker.pl: dgmgrl connect failed for SID 'prim': ...
```

Check OS group membership and test the connection manually:

```bash
id <agent-user>

sudo -u <agent-user> \
  ORACLE_SID=prim ORACLE_HOME=/u01/app/oracle/product/19c/db \
  /u01/app/oracle/product/19c/db/bin/dgmgrl / as sysdg "show configuration;"
```

If the connection fails, add the agent user to the `dba` or `dgdba` OS group:

```bash
usermod -aG dba <agent-user>
```

---

**sqlplus not found or fails**

```bash
# Verify sqlplus is present in the Oracle home
ls -l $ORACLE_HOME/bin/sqlplus

# Test as agent user
sudo -u <agent-user> ORACLE_SID=prim ORACLE_HOME=/u01/app/oracle/product/19c/db \
  /u01/app/oracle/product/19c/db/bin/sqlplus -s / as sysdba <<EOF
SELECT VALUE FROM V\$PARAMETER WHERE NAME='dg_broker_start';
EXIT
EOF
```

---

**Plugin not running at all (section missing from agent output)**

```bash
# Check file exists and is executable
ls -l /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl

# Check for syntax errors
perl -c /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl

# Run agent manually to confirm section appears
check_mk_agent | grep oracle_dataguard_broker
```

---

**Plugin times out**

`dgmgrl` and `sqlplus` may hang if the Oracle instance is in a partial failure
state. The Checkmk agent has a global plugin timeout (default: 60 seconds).
Run manually with a timeout to reproduce:

```bash
timeout 30 perl /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl
```

---

#### Agent log file locations

| Platform | Log location |
|----------|-------------|
| Linux (systemd) | `journalctl -u check-mk-agent.socket` |
| Linux (xinetd) | `/var/log/syslog` or `/var/log/messages` |
| AIX | `/var/log/check_mk/check_mk_agent.log` |
| Windows | Event Viewer → Applications and Services Logs → Checkmk |

---

### 5.2 Server-Side Troubleshooting

#### Inspecting service discovery output

```bash
# As site user — list discovered services for a host
cmk -v --checks=oracle_m5100,oracle_m5110,oracle_m5120,oracle_m5130 <hostname>

# Re-run discovery
cmk -vv -I <hostname>
```

#### Debugging check execution

```bash
# Verbose check run for all oracle_dataguard_broker plugins
cmk -v --debug <hostname> 2>&1 | grep -A 5 oracle_dataguard

# Debug a single check plugin with full output
cmk -v --debug --checks=oracle_m5100 <hostname>
```

The `--debug` flag activates the `if debug.enabled():` branches in
`oracle_dataguard_broker_lib.py`, which print the parsed section dictionary
and intermediate state calculations to stdout.

#### Inspecting raw agent output

```bash
# From cached output (updated on last agent contact)
cat /omd/sites/<site>/tmp/check_mk/cache/<hostname> | grep -A 30 oracle_dataguard_broker

# From a live agent run
cmk --debug --cache <hostname> | grep -A 30 oracle_dataguard_broker
```

#### Common server-side errors and solutions

---

**Services go UNKNOWN — "No data received for `<item>`"**

1. Verify the agent plugin is running and producing output (Section 5.1).
2. Verify the metric is still enabled in the active WATO rule.
3. Check whether the SID item matches exactly — the item is case-sensitive and
   must match the SID as reported in the agent output.
4. If the MKP was recently updated or the plugin redeployed, run a full
   re-discovery:

```bash
cmk -I <hostname>
cmk -R
```

---

**Services not discovered after MKP import**

```bash
cmk -II <hostname>   # force full re-discovery
cmk -R
```

---

**Thresholds not applied — service always OK despite broker issues**

1. Check the active rule via the GUI Analyse button.
2. Confirm the metric's `enabled` field is `true` in the active rule.
3. Confirm `warning` and `critical` are numeric values (not `NaN`) for the
   state you expect.
4. Run the check with debug to see the raw value and threshold evaluation:

```bash
cmk -v --debug --checks=oracle_m5100 <hostname> 2>&1 | grep -i "m5100\|state\|warn\|crit"
```

---

**Bakery not including the agent script**

1. Confirm an agent rule for **Oracle Data Guard Broker** exists and matches
   the host.
2. Re-bake: `cmk -v --bake-agents <hostname>`.
3. Inspect the baked package:

```bash
ls /omd/sites/<site>/var/check_mk/agents/
tar -tzf /omd/sites/<site>/var/check_mk/agents/<package>.tar.gz | grep oracle
```

If the script is absent, the agent rule may not be matching (check folder
assignment and host labels).

---

**Performance graphs not showing for m5120 / m5130**

Verify the counter names match. In the agent output, m5120 and m5130 emit
non-zero values only when inconsistencies are present. Check that the service
is not in UNKNOWN state (which suppresses RRD writes). Inspect the service's
performance data tab in Checkmk to confirm the counter is being stored.

---

#### Server log locations

| Log | Location | Relevant for |
|-----|----------|-------------|
| Microcore (CEE) | `/omd/sites/<site>/var/log/cmc.log` | Check scheduling, staleness |
| Nagios core (RAW) | `/omd/sites/<site>/var/log/nagios/nagios.log` | Check scheduling |
| GUI/REST errors | `/omd/sites/<site>/var/log/web.log` | MKP install errors |
| Agent output cache | `/omd/sites/<site>/tmp/check_mk/cache/<hostname>` | Raw agent data |

---

## 6. Uninstallation

### Remove the MKP from the Checkmk server

**Via the web interface:**

1. Navigate to **Setup → Extension packages**.
2. Find `oracle_dataguard_broker` and click **Delete**.

**Via the command line:**

```bash
mkp remove oracle_dataguard_broker
```

> **NOTE:** Removing the MKP does not automatically delete services that were
> already discovered. Existing services will go UNKNOWN on the next check cycle
> because the check plugins are no longer present.

### Remove stale services

After removing the MKP, remove the Data Guard Broker services from all
affected hosts:

```bash
# For each affected host
cmk -I <hostname>   # re-discovery removes services with no matching plugin
cmk -R
```

Or remove services manually via **Monitor → <host> → Services → Remove services**.

### Remove the agent plugin from monitored hosts

**Manual removal:**

```bash
# Linux
sudo rm /usr/lib/check_mk_agent/plugins/oracle_dataguard_broker.pl

# AIX
rm /usr/check_mk/lib/plugins/oracle_dataguard_broker.pl
```

**Via bakery:** Disable the Oracle Data Guard Broker agent rule, re-bake, and
redeploy the agent package. The Perl script will be absent from the new package.

### Impact on monitoring data

Metrics m5120 and m5130 have performance counters and may have RRD files on
the Checkmk server. These are not automatically removed when the MKP is
uninstalled. Remove them manually if needed:

```bash
find /omd/sites/<site>/var/pnp4nagios/perfdata/<hostname>/ \
  -name '*oracle_m512*' -o -name '*oracle_m513*' | xargs rm -f
```

---

## 7. Security Considerations

### Data accessed and transmitted

The agent plugin accesses Oracle Data Guard Broker state information via local
process execution. It **connects to the local Oracle instance** using OS
authentication (no password required) and reads broker configuration metadata.
It does **not** read application data, user tables, or Oracle credentials.

Data transmitted to the Checkmk server in the `oracle_dataguard_broker` section:

- Oracle SID name
- Broker configuration status (`SUCCESS`, `WARNING`, `ERROR`)
- Database status and status report text
- Names of inconsistent broker properties and standby names
- Count of inconsistent log transport properties

This data reveals the topology and current fault state of the Data Guard
configuration. It does not include database content, user data, or credentials.

### Principle of least privilege

For least-privilege operation (Oracle 12c+):

1. Add the agent OS user to the `dgdba` group (for `dgmgrl / as sysdg`):

   ```bash
   usermod -aG dgdba <agent-user>
   ```

2. Grant `SELECT_CATALOG_ROLE` in Oracle (for SQL*Plus `V$PARAMETER` query
   without SYSDBA):

   ```sql
   CREATE USER cmk IDENTIFIED EXTERNALLY;
   GRANT SELECT_CATALOG_ROLE TO cmk;
   ```

   Then change the sqlplus connect string in `oracle_dataguard_broker.pl` from
   `/ as sysdba` to `/` (or the appropriate external auth user).

For simplicity in most environments, adding the agent user to the `dba` group
and using `/ as sysdba` is the recommended approach.

### Credentials

This plugin stores **no credentials**. No database passwords, no OS user
passwords, no API tokens. Both `sqlplus` and `dgmgrl` use OS-level
authentication (`/`) relying on group membership only.

### Temp file security

The plugin writes dgmgrl command scripts and spool files to `$MK_TEMPDIR`
(or `/tmp` as fallback). Files are created with mode `0600` (owner read/write
only) on Unix and are deleted immediately after use. File names include the PID
to avoid collisions between concurrent agent runs.

### Network exposure

The plugin runs locally on the agent host. The only network connection involved
is the standard Checkmk agent transport (TCP 6556 or agent controller TLS
tunnel) used to deliver the section output to the server.

### Output sanitisation

The Perl script sanitises all values before including them in the pipe-delimited
output:
- Literal pipe characters (`|`) in Oracle output are replaced with `?` to
  prevent field splitting.
- Output strings are truncated to 512 characters with a ` ...` suffix to
  prevent unbounded agent output.

---

## 8. Known Limitations & Compatibility Notes

| Limitation | Detail |
|------------|--------|
| Windows not supported by bakery | The bakery plugin targets `OS.LINUX` and `OS.AIX` only. Windows deployment is manual. |
| No async execution | The plugin runs synchronously. If `dgmgrl` or `sqlplus` hangs (e.g. stuck Oracle instance), the agent check cycle is delayed for that host. |
| English-only output | The plugin forces English locale via `NLS_LANG=AMERICAN_AMERICA`. If Oracle produces output in a different language, the pattern matching in metric state detection may not work correctly. |
| Debug API path change | The plugin imports `cmk.ccc.debug` (2.4.0+) with a fallback to `cmk.utils.debug` (2.3.x). If Checkmk changes this path in a future release, the import will fail. |
| UNKNOWN and DISABLED broker states silently ignored | `show configuration` statuses of `UNKNOWN` or `DISABLED` do not produce a metric 5100 record. No Checkmk service is created for these states. |
| Single DG configuration per SID assumed | The plugin queries `show database 'SID'` using the instance SID. Environments where the broker database name differs from the SID may require a customised query. |
| Broker check requires sysdba or sysdg | The `V$PARAMETER` query requires SYSDBA or `SELECT_CATALOG_ROLE`. The dgmgrl connection requires SYSDG or SYSDBA. See Section 7 for least-privilege options. |

### Upgrade notes

When upgrading from one plugin version to another:

1. Install the new MKP (it replaces the old one).
2. Re-bake and redeploy agents if using the bakery.
3. Run service re-discovery if new metrics were added or removed.
4. Review WATO rules — new default parameters may differ from previous versions.

---

## 9. Appendix

### 9.1 File Structure of the MKP

#### Repository layout

```
Checkmk-Oracle-DataGuard-Broker/
├── .mkp-builder.ini                           Package metadata and build configuration
├── build.py                                   MKP build script (pure Python, no dependencies)
├── DOCUMENTATION.md                           This document
├── README.md                                  Quick-start configuration guide
└── local/                                     MKP payload (mirrors Checkmk site/local/)
    ├── lib/python3/
    │   ├── cmk/base/cee/plugins/bakery/
    │   │   └── oracle_dataguard_broker.py     Bakery plugin (CEE/CCE/MSP only)
    │   └── cmk_addons/plugins/oracle_dataguard_broker/
    │       ├── agent_based/
    │       │   ├── oracle_dataguard_broker.py        Check plugin registrations (4 plugins)
    │       │   └── oracle_dataguard_broker_lib.py    Parsing, state calculation, cluster logic
    │       ├── graphing/
    │       │   └── oracle_dataguard_broker.py        Graphing and perfometer definitions
    │       ├── rulesets/
    │       │   ├── ruleset_oracle_dataguard_broker.py      WATO rule set registrations
    │       │   └── ruleset_oracle_dataguard_broker_lib.py  Rule form specification
    │       └── oracle_dataguard_broker_metrics.py    Central metric definitions (METRIC_DEF)
    └── share/check_mk/agents/plugins/
        └── oracle_dataguard_broker.pl         Agent plugin (Perl, Linux + AIX + Windows)
```

#### MKP archive layout

The `.mkp` file is a gzip-compressed tar archive. The outer archive contains
metadata files and one inner tar per file section.

```
oracle_dataguard_broker-1.0.0.mkp  (tar.gz)
├── info                                       Package metadata (Python literal dict)
├── info.json                                  Package metadata (JSON)
├── agents.tar
│   └── plugins/
│       └── oracle_dataguard_broker.pl
└── cmk_addons_plugins.tar
    └── oracle_dataguard_broker/
        ├── agent_based/
        │   ├── oracle_dataguard_broker.py
        │   └── oracle_dataguard_broker_lib.py
        ├── graphing/
        │   └── oracle_dataguard_broker.py
        ├── oracle_dataguard_broker_metrics.py
        └── rulesets/
            ├── ruleset_oracle_dataguard_broker.py
            └── ruleset_oracle_dataguard_broker_lib.py
```

> **NOTE:** The bakery plugin (`cmk/base/cee/plugins/bakery/oracle_dataguard_broker.py`)
> is in the `lib` section and is installed under `local/lib/python3/cmk/base/`.
> It is only loaded on Enterprise/Cloud/MSP editions that have the Agent Bakery.

---

### 9.2 Example Agent Output

#### Healthy host — two broker-enabled instances

```
<<<oracle_dataguard_broker:sep(124)>>>
prim|5100|0|STATUS=SUCCESS|None|None|None|None
prim|5110|0|STATUS=SUCCESS|REPORT=|None|None|None
prim|5120|0|None|None|None|None|None
prim|5130|0|None|None|None|None|None
standby|5100|0|STATUS=SUCCESS|None|None|None|None
standby|5110|0|STATUS=SUCCESS|REPORT=|None|None|None
standby|5120|0|None|None|None|None|None
standby|5130|0|None|None|None|None|None
```

#### Degraded host — configuration WARNING, inconsistent properties

```
<<<oracle_dataguard_broker:sep(124)>>>
prim|5100|1|STATUS=WARNING|None|None|None|None
prim|5110|1|STATUS=WARNING|REPORT=WARNING: ORA-16714: the value of property ArchiveLagTarget is inconsistent with the database setting; |None|None|None
prim|5120|2|ERRORLINE=InconsistentProperties: ArchiveLagTarget LogArchiveMaxProcesses |None|None|None|None
prim|5130|0|None|None|None|None|None
```

#### No broker-enabled instance found (plugin ran but no data)

```
<<<oracle_dataguard_broker:sep(124)>>>
```

#### Field format reference

```
OBJECT | MetricNumber | Value | Option1 | Option2 | Option3 | Option4 | Option5
```

| Field | Content |
|-------|---------|
| OBJECT | Oracle SID — uniquely identifies the database instance |
| MetricNumber | Raw metric number: `5100`, `5110`, `5120`, or `5130` |
| Value | Status enum (5100/5110: 0/1/2) or count (5120/5130: 0+) |
| Option1 | `STATUS=<value>` (5100/5110) or `ERRORLINE=<text>` (5120/5130) or `None` |
| Option2 | `REPORT=<text>` (5110 only) or `None` |
| Option3 | `ERRORLINE=<text>` (5110 error line, when present) or `None` |
| Option4 | Always `None` (reserved) |
| Option5 | Always `None` (reserved) |

---

### 9.3 Glossary

| Term | Definition |
|------|------------|
| **Data Guard Broker** | Oracle's framework for automating the creation, maintenance, and monitoring of Data Guard configurations; controlled via `dgmgrl` |
| **dgmgrl** | Data Guard Manager CLI — Oracle's command-line tool for managing and monitoring Data Guard Broker configurations; located in `$ORACLE_HOME/bin/` |
| **dg_broker_start** | Oracle initialization parameter that controls whether the Data Guard Broker process (DMON) starts with the instance; must be `TRUE` for this plugin to collect data |
| **Grid Home** | The Oracle installation directory for Grid Infrastructure (CRS, ASM, network services) |
| **InconsistentProperties** | A dgmgrl property report listing broker-managed properties whose value in the broker configuration differs from the database memory or spfile value |
| **InconsistentLogXptProps** | A dgmgrl property report listing log transport properties whose value in the broker configuration differs between primary and standby |
| **MKP** | Monitoring Extension Package — Checkmk's format for distributing plugins as a single installable archive (gzip-compressed tar) |
| **MK_TEMPDIR** | Environment variable set by the Checkmk agent before invoking plugins; points to a directory suitable for temporary files |
| **NaN** | "Not a Number" — used in threshold fields to indicate that a threshold level is disabled |
| **oratab** | A text file listing Oracle database instances with their home directories; typically `/etc/oratab` |
| **SYSDG** | Oracle system privilege introduced in 12c that grants the minimum permissions required to manage Data Guard; used with `dgmgrl / as sysdg` |
| **WorstOf** | Checkmk cluster algorithm that reports the most severe state across all cluster nodes |
| **WATO** | Web Administration Tool — Checkmk's configuration system; accessed via the **Setup** menu |

---

### 9.4 References & Further Reading

| Resource | URL |
|----------|-----|
| MKP source repository | https://github.com/TazamaTech-Software/Checkmk-Oracle-DataGuard-Broker |
| Checkmk MKP documentation | https://docs.checkmk.com/latest/en/mkps.html |
| Checkmk Agent Bakery API | https://docs.checkmk.com/latest/en/bakery_api.html |
| Checkmk agent-based check API v2 | https://docs.checkmk.com/latest/en/devel_check_plugins.html |
| Checkmk Extension Packages (Exchange) | https://exchange.checkmk.com |
| Oracle dgmgrl reference | https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/oracle-data-guard-broker-commands.html |
| Oracle Data Guard Broker concepts | https://docs.oracle.com/en/database/oracle/oracle-database/19/dgbkr/oracle-data-guard-broker-concepts.html |
| Oracle dg_broker_start parameter | https://docs.oracle.com/en/database/oracle/oracle-database/19/refrn/DG_BROKER_START.html |
| Oracle SYSDG privilege | https://docs.oracle.com/en/database/oracle/oracle-database/19/dbseg/configuring-privilege-and-role-authorization.html |
