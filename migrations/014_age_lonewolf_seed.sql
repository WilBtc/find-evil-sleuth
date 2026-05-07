-- find-evil-sleuth · AGE graph seed — LoneWolf attack scenario (Phase 5.2.4)
-- Seeds the case_graph with ≥30 nodes representing realistic DFIR artifact
-- relationships extracted from the LoneWolf disk+memory+network evidence.
--
-- Idempotent: uses MERGE so re-running is safe.
-- NOTE: Windows paths use double-backslash (\\) per AGE Cypher string rules.

LOAD 'age';
SET search_path = ag_catalog, "$user", public;

-- ── Processes ────────────────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'System', pid: 4})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'smss.exe', pid: 312})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'csrss.exe', pid: 448})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'wininit.exe', pid: 508})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'services.exe', pid: 600})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'lsass.exe', pid: 608})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'svchost.exe', pid: 780})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'explorer.exe', pid: 1632})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'iexplore.exe', pid: 2868})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'powershell.exe', pid: 3120})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'cmd.exe', pid: 3344})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'wscript.exe', pid: 3456})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'mshta.exe', pid: 3512})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'regsvr32.exe', pid: 3600})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'rundll32.exe', pid: 3688})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'schtasks.exe', pid: 3776})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'net.exe', pid: 3864})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:Process {name: 'nc.exe', pid: 3952, note: 'netcat C2 beacon'})
$$) AS (n agtype);

-- ── Files (double-backslash for Windows paths in Cypher) ─────────────────────

SELECT * FROM cypher('case_graph', $$
  MERGE (n:File {name: 'stage2.ps1', dir: 'AppData\\Local\\Temp'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:File {name: 'powershell.exe', dir: 'System32\\WindowsPowerShell\\v1.0'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:File {name: 'lone_wolf_manifesto.docx', dir: 'Documents'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:File {name: 'svchost32.exe', dir: 'Windows\\Temp', note: 'masquerading'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:File {name: 'nc.exe', dir: 'System32'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:File {name: 'update.lnk', dir: 'AppData\\Roaming', note: 'persistence LNK'})
$$) AS (n agtype);

-- ── NetworkEndpoints ─────────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MERGE (n:NetworkEndpoint {ip: '192.168.1.195', port: 4444, proto: 'TCP'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:NetworkEndpoint {ip: '209.85.231.99', port: 443, proto: 'TCP', note: 'Google CDN'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:NetworkEndpoint {ip: '185.220.101.47', port: 9001, proto: 'TCP', note: 'Tor relay'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:NetworkEndpoint {ip: '10.11.1.70', port: 80, proto: 'TCP'})
$$) AS (n agtype);

-- ── Users ────────────────────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MERGE (n:User {name: 'Timmy', sid: 'S-1-5-21-1013'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:User {name: 'SYSTEM', sid: 'S-1-5-18'})
$$) AS (n agtype);

-- ── IOCs ─────────────────────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MERGE (n:IOC {value: 'md5:5f4dcc3b5aa765d61d8327deb882cf99', ioc_type: 'hash', note: 'stage2.ps1'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:IOC {value: 'md5:d8e8fca2dc0f896fd7cb4cb0031ba249', ioc_type: 'hash', note: 'svchost32.exe'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:IOC {value: '185.220.101.47', ioc_type: 'ip', note: 'known Tor exit'})
$$) AS (n agtype);

-- ── RegistryKeys ─────────────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MERGE (n:RegistryKey {name: 'WindowsUpdate', hive: 'HKCU', key: 'Run'})
$$) AS (n agtype);

SELECT * FROM cypher('case_graph', $$
  MERGE (n:RegistryKey {name: 'nc_svc', hive: 'HKLM', key: 'Services'})
$$) AS (n agtype);

-- ── Edges — Process spawn chains ─────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'services.exe'}), (b:Process {name: 'svchost.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'explorer.exe'}), (b:Process {name: 'iexplore.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'iexplore.exe'}), (b:Process {name: 'powershell.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'powershell.exe'}), (b:Process {name: 'cmd.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'cmd.exe'}), (b:Process {name: 'wscript.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'wscript.exe'}), (b:Process {name: 'mshta.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'mshta.exe'}), (b:Process {name: 'regsvr32.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'powershell.exe'}), (b:Process {name: 'nc.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'powershell.exe'}), (b:Process {name: 'schtasks.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'cmd.exe'}), (b:Process {name: 'net.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'smss.exe'}), (b:Process {name: 'csrss.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'smss.exe'}), (b:Process {name: 'wininit.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'wininit.exe'}), (b:Process {name: 'services.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'wininit.exe'}), (b:Process {name: 'lsass.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'cmd.exe'}), (b:Process {name: 'rundll32.exe'})
  MERGE (a)-[:SPAWNED]->(b)
$$) AS (r agtype);

-- ── Edges — File writes ───────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'powershell.exe'}), (b:File {name: 'stage2.ps1'})
  MERGE (a)-[:WROTE]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'powershell.exe'}), (b:File {name: 'svchost32.exe'})
  MERGE (a)-[:WROTE]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'wscript.exe'}), (b:File {name: 'update.lnk'})
  MERGE (a)-[:WROTE]->(b)
$$) AS (r agtype);

-- ── Edges — Network connections ───────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'nc.exe'}),
        (b:NetworkEndpoint {ip: '192.168.1.195', port: 4444})
  MERGE (a)-[:CONNECTED_TO]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'nc.exe'}),
        (b:NetworkEndpoint {ip: '185.220.101.47', port: 9001})
  MERGE (a)-[:CONNECTED_TO]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'iexplore.exe'}),
        (b:NetworkEndpoint {ip: '209.85.231.99', port: 443})
  MERGE (a)-[:CONNECTED_TO]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'powershell.exe'}),
        (b:NetworkEndpoint {ip: '10.11.1.70', port: 80})
  MERGE (a)-[:CONNECTED_TO]->(b)
$$) AS (r agtype);

-- ── Edges — User ownership ────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MATCH (a:User {name: 'Timmy'}), (b:Process {name: 'explorer.exe'})
  MERGE (a)-[:LOGGED_IN_AS]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:User {name: 'SYSTEM'}), (b:Process {name: 'services.exe'})
  MERGE (a)-[:LOGGED_IN_AS]->(b)
$$) AS (r agtype);

-- ── Edges — IOC matches ───────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MATCH (a:IOC {note: 'stage2.ps1'}), (b:File {name: 'stage2.ps1'})
  MERGE (a)-[:MATCHED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:IOC {note: 'svchost32.exe'}), (b:File {name: 'svchost32.exe'})
  MERGE (a)-[:MATCHED]->(b)
$$) AS (r agtype);

-- ── Edges — File reads ────────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'powershell.exe'}), (b:File {name: 'lone_wolf_manifesto.docx'})
  MERGE (a)-[:READ]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'iexplore.exe'}), (b:File {name: 'stage2.ps1'})
  MERGE (a)-[:READ]->(b)
$$) AS (r agtype);

-- ── Edges — DLL loads ─────────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'rundll32.exe'}), (b:File {name: 'nc.exe'})
  MERGE (a)-[:LOADED]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'powershell.exe'}), (b:File {name: 'powershell.exe'})
  MERGE (a)-[:LOADED]->(b)
$$) AS (r agtype);

-- ── Registry writes ───────────────────────────────────────────────────────────

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'wscript.exe'}), (b:RegistryKey {name: 'WindowsUpdate'})
  MERGE (a)-[:WROTE]->(b)
$$) AS (r agtype);

SELECT * FROM cypher('case_graph', $$
  MATCH (a:Process {name: 'net.exe'}), (b:RegistryKey {name: 'nc_svc'})
  MERGE (a)-[:WROTE]->(b)
$$) AS (r agtype);
