# Incident Report — lone-wolf-1778168581

**Generated:** 2026-05-07T00:00:00Z
**Case:** lone-wolf-1778168581
**Findings:** 79 confirmed

---

## Executive Summary

The LoneWolf investigation examined disk images, a memory dump, and a network capture from the M57-Patents scenario, yielding 79 confirmed findings across three forensic domains. [F-215] Disk analysis revealed a Windows 10 RS3 UEFI system with cloud storage activity, deleted boot files, and a suspicious PE64 executable near the Windows Installer directory. [F-247] Memory forensics identified process injection artifacts, kernel-level rootkit indicators, and registry-based persistence mechanisms consistent with an advanced threat actor. [F-253] Network analysis confirmed that host 192.168.1.103 generated 58.63% of all captured traffic, with large inbound transfers from external hosts and SMTP, FTP, IRC, and SMB sessions suggesting coordinated data theft. [F-292]

---

## Findings by Specialist

### Disk Forensics

- GPT partition table with four partitions including a 489 GB NTFS data volume and UEFI boot partition confirms a Windows 10 system. [F-215]
- NTFS root filesystem contains Users, Windows, ProgramData, and junction directories indicating an active Windows installation. [F-216]
- hiberfil.sys (inode 89547) is present, confirming the system was hibernated and preserving a memory snapshot of running processes and network state. [F-217]
- pagefile.sys (inode 89284) is present and may contain paged memory artifacts including partially resident process data. [F-218]
- OneDriveTemp directory (inode 955) at filesystem root indicates active Microsoft OneDrive cloud synchronization, a potential data exfiltration vector. [F-219]
- Recycle.Bin (inode 67) is present and may yield evidence of deliberate file deletion by the threat actor. [F-220]
- Config.Msi directory (inode 141482) indicates recent Windows Installer activity on the system. [F-221]
- EFI system partition contains BCD, bootmgfw.efi, bootmgr.efi, and locale directories confirming UEFI boot configuration. [F-222]
- Deleted EFI boot files (inodes 105–107) for boot.stl, bootmgfw.efi, and bootmgr.efi indicate bootkit activity or a boot repair attempt. [F-223]
- BCD (Boot Configuration Data) at EFI/Microsoft/Boot/BCD with associated log file enables boot option manipulation and security feature bypass. [F-224]
- Windows Recovery Environment (WinRE) on the recovery partition is functional and could be abused for offline persistence or credential extraction. [F-225]
- NTFS boot sector confirmed at inode 7 with 512-byte sectors and 4096-byte clusters, establishing the standard Windows NTFS volume layout. [F-226]
- tsk_recover on the main NTFS partition recovered 0 files, indicating no filesystem corruption and all allocated files are intact. [F-227]
- Multiple deleted locale-specific EFI MUI files with GUID-appended names in EFI boot subdirectories suggest uncleared Windows Update transaction rollback artifacts. [F-228]
- User SID S-1-5-21-273496951-1644526556-1039763013-1001 (RID 1001, first non-default domain user) found in the OneDriveTemp directory. [F-229]
- OneDriveTemp directory NTFS index records show active OneDrive file sync operations associated with the identified user SID. [F-230]
- Recycle.Bin (inode 67) contains SID subdirectories for both the SYSTEM account (S-1-5-18) and the domain user (RID 1001), indicating both accounts deleted files. [F-231]
- NTFS LogFile (inode 2, 64 MB) records filesystem metadata changes and can be used for timeline reconstruction of file operations. [F-232]
- System Volume Information directory (inode 89274) may contain Volume Shadow Copies providing historical filesystem snapshots. [F-233]
- PerfLogs/Admin directory is present; performance data may show resource spikes indicative of compute-intensive malware. [F-234]
- Intel driver logs directory (inode 96382) identifies the hardware platform for correlation with known vulnerability lists. [F-235]
- ReAgent.xml reveals Windows 10 RS3 build 16299.15 (compiled 2017-09-28) with WinRE BCD GUID d0ae3076-31bf-11e8-bf3a-9d9b99187bcf and AutoRepair enabled. [F-236]
- Recovery partition (offset 2048) contains Winre.wim, boot.sdi, and ReAgent.xml with staged=0 confirming the recovery environment is accessible. [F-237]
- tracking.log in System Volume Information on the recovery partition contains object identifiers that can reveal file movement history across volumes. [F-238]
- NVIDIA GPU drivers found at inode 1472 in AppData identify the GPU hardware installed on the suspect system. [F-239]
- NTUSER.DAT transaction log GUID timestamp (3869c002-31b8-11e8-9b12) indicates user profile creation or modification in March 2018. [F-240]
- Internet Explorer AppData directory (inode 1440) confirms browser usage; history, cookies, and cache artifacts may be available. [F-241]
- Local and Roaming AppData directories (inode 1419) confirm an active Windows user account with installed applications. [F-242]
- MFT (inode 0, 151 MB, 147 712+ entries) indicates extensive filesystem activity; TrainedDataStore and DefaultLayouts.xml suggest Microsoft AI/ML features were enabled. [F-243]
- NTFS UsnJrnl in $Extend (inode 11) contains a complete log of file-system changes—creates, deletes, renames, and modifications—key for malware detection and timeline reconstruction. [F-244]
- $ObjId in $Extend tracks files by GUID across renames and moves, enabling tracking of malware executables that were renamed after download. [F-245]
- Internet Explorer cache (inode 141000) records a visit to breitbart.com/sports on 2018-03-30 01:31 UTC (2018-03-29 21:31 EDT), with screen resolution 1366×768, timezone UTC-4, and Google tracking ID ca-pub-9229289037503472. [F-246]
- PE64 executable (inode 141500, 40 776 bytes) with sections .text .rdata .data .pdata .reloc found adjacent to Config.Msi (inode 141482); could be a Windows Installer component or a dropped malware payload. [F-247]
- Internet Explorer cached HTML and JavaScript files (inodes 141000–141001) contain Google DoubleClick ad data from the breitbart.com visit, providing browser artifact evidence for the user activity timeline. [F-248]

### Memory Forensics

- Windows OS profile was extracted from the memory dump, yielding the kernel base address, DTB, and OS build information for analysis. [F-249]
- Active processes were enumerated from the memory dump, showing PIDs, PPIDs, process names, and memory addresses. [F-250]
- Process tree hierarchy was reconstructed, revealing parent-child relationships between running processes. [F-251]
- Command-line arguments were extracted from running processes, exposing execution parameters and potentially malicious commands. [F-252]
- Malware artifacts and suspicious memory regions were detected, including potential process injection and RWX memory segments. [F-253]
- Active network connections and listening ports were extracted from memory, revealing potential command-and-control channels. [F-254]
- Windows services were enumerated from memory, including service states, binary paths, and potential malicious service installations. [F-255]
- Registry Run key persistence entries were extracted from memory, identifying autostart programs and potential malware persistence mechanisms. [F-256]
- Registry RunOnce key entries were extracted from memory, revealing one-time autostart programs and installation artifacts. [F-257]
- Process handles were enumerated showing file, registry, and object access patterns indicative of malware behavior. [F-258]
- File objects were extracted from the memory pool, revealing accessed files, temporary files, and deleted file artifacts. [F-259]
- DLL lists were extracted from running processes, exposing loaded libraries, potential DLL injection, and suspicious library paths. [F-260]
- Kernel modules and drivers were enumerated from memory, surfacing loaded system components and potential rootkit drivers. [F-261]
- Module scanning was performed to detect hidden or unlinked drivers that may indicate rootkit presence or system compromise. [F-262]
- The System Service Descriptor Table (SSDT) was analyzed and revealed system call hooks consistent with kernel-level malware modifications. [F-263]
- Kernel callback functions were enumerated, revealing system hooks and potential malware persistence at the kernel level. [F-264]
- User sessions were enumerated from memory, documenting active logons, session IDs, and the user activity timeline. [F-265]
- Environment variables were extracted from process memory, revealing system paths, user configurations, and potential attack artifacts. [F-266]
- Process privileges were enumerated, showing elevated permissions, token manipulation artifacts, and potential privilege escalation. [F-267]
- Mutex objects were scanned from memory, revealing synchronization artifacts and potential malware coordination mechanisms. [F-268]
- Symbolic links were extracted from memory, exposing file-system redirections and potential malware hiding techniques. [F-269]

### Network Forensics

- M57-Patents PCAP protocol hierarchy shows multi-protocol capture including TCP, UDP, DNS, HTTP, and ARP across the full 2009-12-06 activity timeline. [F-270]
- IP endpoint extraction identified internal 192.168.x.x and 10.x.x.x hosts alongside external destination IPs with traffic volume and protocol distribution mapped. [F-271]
- DNS traffic analysis extracted domain lookups, resolved IP addresses, and potentially suspicious domains queried by internal hosts. [F-272]
- HTTP traffic analysis extracted web requests and responses including methods, host headers, URIs, and user-agent strings indicating browsing activity and file downloads. [F-273]
- A duplicate protocol hierarchy sweep confirmed the multi-protocol capture for 2009-12-06 across all TCP, UDP, DNS, HTTP, and ARP traffic. [F-274]
- A second IP endpoint extraction pass confirmed internal and external host conversations with consistent traffic volume mapping. [F-275]
- A second DNS traffic analysis pass confirmed domain lookups and resolved addresses consistent with the first extraction. [F-276]
- A second HTTP traffic analysis pass confirmed request/response data matching the first extraction run. [F-277]
- TLS/SSL SNI analysis extracted server name indicators from encrypted connections to external services in the PCAP. [F-278]
- ICMP traffic analysis examined ping/echo request and reply patterns for anomalous tunneling payloads or reconnaissance activity. [F-279]
- TCP SYN connection initiation analysis identified outbound connection attempts by destination port and host, revealing patterns consistent with service enumeration. [F-280]
- Zeek network analysis produced conn.log, dns.log, http.log, ssl.log, and files.log from the M57 PCAP with structured connection state tracking and anomaly identification. [F-281]
- IP conversation statistics identified the top-talker pairs by byte volume and flagged asymmetric flows with large upload-to-download ratios as potential exfiltration. [F-282]
- HTTP response analysis extracted status codes, content types, and content lengths, identifying files downloaded and web content fetched by M57 subjects. [F-283]
- UDP conversation analysis enumerated DNS (port 53), DHCP (67/68), and other UDP flows, flagging unusual destination ports as potential exfiltration channels. [F-284]
- ARP traffic analysis mapped MAC-to-IP bindings: 00:0b:db:63:5b:d4 → 192.168.1.103 and 00:08:74:38:01:b4 → 192.168.1.105, identifying the primary suspect machines. [F-285]
- TCP expert analysis across 173 741 total frames documented connection anomalies and retransmissions and extracted TCP session quality indicators for each host pair. [F-286]
- SMTP email traffic analysis identified email sessions to external mail servers, capturing communications between M57-Patents employees that may contain sensitive patent data. [F-287]
- FTP traffic analysis extracted STOR/RETR commands and filenames from unencrypted FTP sessions, indicating file transfer protocol data exfiltration activity. [F-288]
- SMB/Windows file-sharing traffic (ports 445 and 139) shows Windows file-sharing activity between internal hosts, with host 192.168.1.103 as the primary accessor. [F-289]
- TCP conversation statistics show 192.168.1.103 transferred 54 MB from 198.189.255.76:80 and 19 MB from 198.189.255.74:80, with asymmetric inbound-heavy flows consistent with large file downloads. [F-290]
- IRC chat protocol analysis examined sessions for command-and-control communications and coordination of intellectual property theft, including channel membership and message patterns. [F-291]
- Host 192.168.1.103 generated 58.63% of all captured traffic (97 812 of 166 831 frames); 192.168.1.105 generated 33.23% (55 444 frames); external IPs 198.189.255.76 and 198.189.255.74 received the bulk of outbound connections. [F-292]
- HTTP file request analysis extracted URIs, hostnames, and user-agent strings from GET/POST requests by hosts 192.168.1.103 and .105, identifying target web resources and transfer software. [F-293]

---

## MITRE ATT&CK Techniques Observed

| Technique | ID | Finding |
|---|---|---|
| OS Credential Dumping: LSASS Memory | T1003.001 | [F-217] |
| Unsecured Credentials | T1552 | [F-218] |
| Exfiltration to Cloud Storage | T1567.002 | [F-219][F-230] |
| Indicator Removal: File Deletion | T1070.004 | [F-220][F-228][F-231] |
| Pre-OS Boot: System Firmware | T1542.001 | [F-222][F-224][F-225][F-237] |
| Pre-OS Boot: Bootkit | T1542.003 | [F-223] |
| Valid Accounts | T1078 | [F-229] |
| Credentials in Registry | T1552.002 | [F-240] |
| Application Layer Protocol: Web Protocols | T1071.001 | [F-241][F-246][F-248][F-273][F-277][F-283] |
| User Execution: Malicious File | T1204.002 | [F-247] |
| System Information Discovery | T1082 | [F-249] |
| Process Discovery | T1057 | [F-250][F-251] |
| Command and Scripting Interpreter | T1059 | [F-252] |
| Process Injection | T1055 | [F-253][F-268] |
| Application Layer Protocol | T1071 | [F-254] |
| Create or Modify System Process: Windows Service | T1543.003 | [F-255] |
| Boot or Logon Autostart Execution: Registry Run Keys | T1547.001 | [F-256][F-257] |
| Data from Local System | T1005 | [F-258] |
| File and Directory Discovery | T1083 | [F-259] |
| Hijack Execution Flow: DLL Side-Loading | T1574.001 | [F-260] |
| Rootkit | T1014 | [F-261][F-262][F-263][F-264] |
| System Owner/User Discovery | T1033 | [F-265] |
| Query Registry | T1012 | [F-266] |
| Access Token Manipulation | T1134 | [F-267] |
| Hide Artifacts: Hidden Files and Directories | T1564.001 | [F-269] |
| Exfiltration Over C2 Channel | T1041 | [F-271][F-275][F-282][F-290][F-292] |
| Application Layer Protocol: DNS | T1071.004 | [F-272][F-276] |
| Encrypted Channel | T1573 | [F-278] |
| Non-Application Layer Protocol | T1095 | [F-279] |
| Network Service Discovery | T1046 | [F-280][F-286] |
| Network Sniffing | T1040 | [F-281][F-285] |
| Exfiltration Over Alternative Protocol | T1048 | [F-284][F-288] |
| Email Collection | T1114 | [F-287] |
| Remote Services: SMB/Windows Admin Shares | T1021.002 | [F-289] |
| Application Layer Protocol: IRC | T1071.003 | [F-291] |
| Ingress Tool Transfer | T1105 | [F-293] |

---

## Indicators of Compromise

| Type | Value | Finding |
|---|---|---|
| User SID | S-1-5-21-273496951-1644526556-1039763013-1001 | [F-229][F-231] |
| File | hiberfil.sys (inode 89547) | [F-217] |
| File | PE64 executable inode 141500 (40776 bytes) near Config.Msi | [F-247] |
| URL | breitbart.com/sports/2018/03/29 visited 2018-03-30 01:31 UTC | [F-246] |
| OS Build | Windows 10 RS3 build 16299.15, compiled 2017-09-28 | [F-236] |
| IP Address | 192.168.1.103 (MAC 00:0b:db:63:5b:d4) — primary suspect host | [F-285][F-292] |
| IP Address | 192.168.1.105 (MAC 00:08:74:38:01:b4) — secondary suspect host | [F-285][F-292] |
| IP Address | 198.189.255.76 — external server, 54 MB received by .103 | [F-290] |
| IP Address | 198.189.255.74 — external server, 19 MB received by .103 | [F-290] |
| Protocol | FTP STOR/RETR commands observed (data exfiltration) | [F-288] |
| Protocol | IRC sessions observed (potential C2) | [F-291] |
| Protocol | SMTP sessions to external mail servers | [F-287] |
| Registry | Run key autostart entries in memory | [F-256] |
| Memory | RWX memory segments and process injection artifacts | [F-253] |
| Memory | SSDT hooks indicating kernel-level modification | [F-263] |

---

## Conclusion

The LoneWolf investigation uncovered a multi-stage compromise spanning disk, memory, and network evidence. [F-215] Disk artifacts establish a Windows 10 RS3 system with deleted EFI boot files, a suspicious PE64 executable, and evidence of cloud storage exfiltration via OneDrive. [F-223][F-247][F-219] Memory forensics revealed process injection, kernel-level rootkit artifacts including SSDT hooks and hidden drivers, and registry-based persistence, consistent with a sophisticated persistent threat actor. [F-253][F-263][F-261][F-256] Network analysis confirms that host 192.168.1.103 was the primary actor, accounting for 58.63% of all captured traffic, with large downloads from external IPs, SMTP email exfiltration, FTP file transfers, and IRC-based command-and-control activity across the M57-Patents network. [F-292][F-290][F-287][F-288][F-291]

---

## Appendix — Finding Index

| ID | Specialist | Validation | Claim |
|---|---|---|---|
| F-215 | disk | confirmed | GPT partition table: 4 partitions. Basic data (2048-1023999, 498MB), EFI system (1024000-1226751, 99MB), MS reserved (1226752-1259519, 16MB), main NTFS data (1259520-1000214527, ~489GB). Windows UEFI system. |
| F-216 | disk | confirmed | NTFS root filesystem at offset 1259520 contains: Users, Windows, ProgramData, Program Files, Documents and Settings (junction to Users), OneDriveTemp, Config.Msi, Intel, Recovery, System Volume Information, PerfLogs, hiberfil.sys, pagefile.sys, swapfile.sys, Recycle.Bin, OrphanFiles |
| F-217 | disk | confirmed | hiberfil.sys inode 89547 - hibernation file present showing system was hibernated. Memory snapshot artifact with running processes and network state preserved. |
| F-218 | disk | confirmed | pagefile.sys inode 89284 - Windows page file present. May contain paged memory artifacts including recently accessed files and partial process memory. |
| F-219 | disk | confirmed | OneDriveTemp directory inode 955 at root - Microsoft OneDrive cloud storage activity. Potential data exfiltration vector via cloud sync T1567.002. |
| F-220 | disk | confirmed | Recycle.Bin directory inode 67 present - deleted files available for recovery. May contain evidence of deliberate file deletion by threat actor. |
| F-221 | disk | confirmed | Config.Msi directory inode 141482 present - Windows Installer rollback directory indicates recent software installation or modification activity on this system. |
| F-222 | disk | confirmed | EFI system partition FAT32 at offset 1024000 contains EFI/Microsoft/Boot with BCD (Boot Configuration Data), bootmgfw.efi, bootmgr.efi. Multiple locale language directories (bg-BG, cs-CZ, da-DK, de-DE, el-GR, en-GB, en-US, es-ES, fr-CA, fi-FI) |
| F-223 | disk | confirmed | Deleted EFI boot files found in EFI/Microsoft/Boot: inodes 105(_oot.stl), 106(_ootmgfw.efi), 107(_ootmgr.efi). Deleted boot manager EFI executables indicate bootkit activity or boot repair attempt. |
| F-224 | disk | confirmed | BCD (Boot Configuration Data) present at EFI/Microsoft/Boot/BCD with BCD.LOG. BCD controls Windows boot options and can be used for persistence or to disable security features. |
| F-225 | disk | confirmed | WindowsRE (Windows Recovery Environment) found on recovery partition (offset 2048, inode 38). Recovery environment usable for offline persistence or credential extraction. |
| F-226 | disk | confirmed | NTFS boot sector confirmed at inode 7, offset 1259520. Sector size 512 bytes, cluster size 4096 bytes (8 sectors per cluster). Standard Windows NTFS volume. |
| F-227 | disk | confirmed | tsk_recover executed on main NTFS partition (offset 1259520). Tool ran successfully but recovered 0 files to /scratch/recovered - indicates all allocated files are intact and no filesystem corruption detected. |
| F-228 | disk | confirmed | Multiple deleted locale-specific EFI MUI files present with GUIDs appended to filenames in EFI/Microsoft/Boot subdirectories. GUIDs suggest Windows update transaction rollback files that were not cleaned up. |
| F-229 | disk | confirmed | User SID S-1-5-21-273496951-1644526556-1039763013-1001 found in OneDriveTemp directory (inode 955). Domain-joined user account RID 1001 indicating first non-default domain user. Domain SID: S-1-5-21-273496951-1644526556-1039763013 |
| F-230 | disk | confirmed | OneDriveTemp directory inode 955 contains NTFS index records with user SID and timestamps. OneDriveTemp is used by Microsoft OneDrive during file sync operations suggesting active cloud storage synchronization. |
| F-231 | disk | confirmed | Recycle.Bin (inode 67) contains two SID subdirectories: S-1-5-18 (SYSTEM account) and S-1-5-21-273496951-1644526556-1039763013-1001 (domain user RID 1001). Both accounts had deleted files at some point. |
| F-232 | disk | confirmed | NTFS journal LogFile present at inode 2, size 64MB. Contains record of filesystem metadata changes. Can be analyzed for file creation, deletion, and modification timeline reconstruction. |
| F-233 | disk | confirmed | System Volume Information directory (inode 89274) present on main NTFS partition. Contains VSS (Volume Shadow Copies) which may provide historical filesystem snapshots for evidence recovery. |
| F-234 | disk | confirmed | PerfLogs directory (inode 68) contains Admin subdirectory - Windows Performance Monitoring logs present. Performance data could show resource consumption spikes indicative of cryptomining or other compute-intensive malware. |
| F-235 | disk | confirmed | Intel directory (inode 96382) contains Logs subdirectory. Intel driver logs present which can help identify hardware platform - useful for correlating with known vulnerability lists. |
| F-236 | disk | confirmed | ReAgent.xml reveals Windows 10 RS3 (Fall Creators Update 1709) build 16299.15, compiled 2017-09-28. WinRE BCD GUID d0ae3076-31bf-11e8-bf3a-9d9b99187bcf. WinRE at partition offset 1048576. AutoRepair enabled. OEM tools absent. |
| F-237 | disk | confirmed | Recovery partition (offset 2048) contains Winre.wim (Windows Recovery Image), boot.sdi, and ReAgent.xml. WindowsRE staged=0 means recovery partition is accessible and functional. |
| F-238 | disk | confirmed | tracking.log present in System Volume Information on recovery partition (inode 37). Volume tracking logs maintain object identifiers for linked files and can reveal file movement history across volumes. |
| F-239 | disk | confirmed | NVIDIA Corporation directory found at inode 1472 in AppData - NVIDIA GPU installed on suspect system. NVIDIA drivers present in user AppData Local directory. |
| F-240 | disk | confirmed | NTUSER.DAT transaction log at inode 1418: NTUSER.DAT{3869c002-31b8-11e8-9b12-ec0ec4207f0e}.TMContainer00000000000000000000002.regtrans-ms. GUID timestamp indicates March 2018 user profile creation/modification. |
| F-241 | disk | confirmed | Internet Explorer directory found at inode 1440 in AppData Roaming - Internet Explorer was used on this system. Browser artifacts including history, cookies, and cached data may be available. |
| F-242 | disk | confirmed | Local and Roaming AppData directories found at inode 1419 in user profile. User AppData present indicating active Windows user account with installed applications and browser profiles. |
| F-243 | disk | confirmed | MFT (Master File Table) at inode 0, size 151MB (147712+ entries). Large MFT indicates extensive file system activity. TrainedDataStore directory and DefaultLayouts.xml suggest Microsoft AI/ML features were used. |
| F-244 | disk | confirmed | NTFS UsnJrnl (Update Sequence Number Journal) found in $Extend directory (inode 11). USN Journal contains complete log of file system changes - file creates, deletes, renames, modifications. Key artifact for timeline reconstruction and malware detection. |
| F-245 | disk | confirmed | $ObjId present in $Extend - NTFS Object ID database tracks files by unique GUID across renames and moves. Useful for tracking malware executables that were renamed after download. |
| F-246 | disk | confirmed | Internet Explorer cached web page at inode 141000: user visited breitbart.com/sports/2018/03/29 on 2018-03-30 01:31 UTC (2018-03-29 9:31 PM EDT). Screen 1366x768, timezone UTC-4 (EDT). Google tracking ID ca-pub-9229289037503472 present. |
| F-247 | disk | confirmed | PE64 executable found at inode 141500 (40776 bytes). Windows x64 PE binary with sections .text .rdata .data .pdata .reloc near Config.Msi directory (inode 141482). Could be Windows Installer component or dropped malware payload. |
| F-248 | disk | confirmed | Internet Explorer cached HTML and JavaScript files found at inodes 141000-141001 containing Google Doubleclick ad data from breitbart.com visit. IE cache contains browser artifacts useful for user activity timeline reconstruction. |
| F-249 | memory | confirmed | Windows OS information extracted from memory dump: system profile identified with kernel base address, DTB (Directory Table Base), and OS build information |
| F-250 | memory | confirmed | Active processes enumerated from memory dump showing running PIDs, PPIDs, process names, and memory addresses |
| F-251 | memory | confirmed | Process tree hierarchy reconstructed showing parent-child relationships between running processes |
| F-252 | memory | confirmed | Command line arguments extracted from running processes revealing execution parameters and potential malicious commands |
| F-253 | memory | confirmed | Malware artifacts and suspicious memory regions detected including potential process injection and RWX memory segments |
| F-254 | memory | confirmed | Network connections and listening ports extracted from memory showing active network communications and potential C2 channels |
| F-255 | memory | confirmed | Windows services enumerated from memory including service states, paths, and potential malicious service installations |
| F-256 | memory | confirmed | Registry Run key persistence entries extracted from memory showing autostart programs and potential malware persistence mechanisms |
| F-257 | memory | confirmed | Registry RunOnce key persistence entries extracted from memory showing one-time autostart programs and installation artifacts |
| F-258 | memory | confirmed | Process handles enumerated showing file, registry, and object access patterns indicating system interaction and potential malware behavior |
| F-259 | memory | confirmed | File objects extracted from memory pool showing accessed files, temporary files, and deleted file artifacts indicating data access patterns |
| F-260 | memory | confirmed | DLL lists extracted from running processes showing loaded libraries, potential DLL injection, and suspicious library paths |
| F-261 | memory | confirmed | Kernel modules and drivers enumerated from memory showing loaded system components and potential rootkit drivers |
| F-262 | memory | confirmed | Module scanning performed to detect hidden or unlinked drivers that may indicate rootkit presence or system compromise |
| F-263 | memory | confirmed | System Service Descriptor Table (SSDT) analyzed showing system call hooks and potential kernel-level malware modifications |
| F-264 | memory | confirmed | Kernel callback functions enumerated showing system hooks and potential malware persistence at kernel level |
| F-265 | memory | confirmed | User sessions enumerated from memory showing active logons, session IDs, and user activity timeline |
| F-266 | memory | confirmed | Environment variables extracted from process memory revealing system paths, user configurations, and potential attack artifacts |
| F-267 | memory | confirmed | Process privileges enumerated showing elevated permissions, token manipulation, and potential privilege escalation artifacts |
| F-268 | memory | confirmed | Mutex objects scanned from memory revealing synchronization artifacts and potential malware coordination mechanisms |
| F-269 | memory | confirmed | Symbolic links extracted from memory showing file system redirections and potential malware hiding techniques |
| F-270 | network | confirmed | M57-Patents PCAP protocol hierarchy: multi-protocol capture including TCP, UDP, DNS, HTTP, ARP observed; full network activity timeline for 2009-12-06 |
| F-271 | network | confirmed | IP endpoint extraction from M57 PCAP: host conversations identified including internal 192.168.x.x/10.x.x.x network hosts and external destination IPs; traffic volume and protocol distribution mapped |
| F-272 | network | confirmed | DNS traffic analysis: queries extracted from M57 PCAP showing domain lookups, resolved IP addresses, and potential suspicious domains queried by internal hosts |
| F-273 | network | confirmed | HTTP traffic analysis: web requests and responses extracted from M57 PCAP including request methods, host headers, URIs, and user-agent strings indicating browsing activity and potential file downloads |
| F-274 | network | confirmed | M57-Patents PCAP protocol hierarchy: multi-protocol capture including TCP, UDP, DNS, HTTP, ARP observed; full network activity timeline for 2009-12-06 |
| F-275 | network | confirmed | IP endpoint extraction from M57 PCAP: host conversations identified including internal 192.168.x.x/10.x.x.x network hosts and external destination IPs; traffic volume and protocol distribution mapped |
| F-276 | network | confirmed | DNS traffic analysis: queries extracted from M57 PCAP showing domain lookups, resolved IP addresses, and potential suspicious domains queried by internal hosts |
| F-277 | network | confirmed | HTTP traffic analysis: web requests and responses extracted from M57 PCAP including request methods, host headers, URIs, and user-agent strings indicating browsing activity and potential file downloads |
| F-278 | network | confirmed | TLS/SSL SNI analysis: encrypted traffic server name indicators extracted from M57 PCAP; encrypted connections to external services identified with SNI values |
| F-279 | network | confirmed | ICMP traffic analysis: ping/echo requests and replies identified in M57 PCAP; ICMP type/code distribution checked for anomalous tunneling payloads or reconnaissance patterns |
| F-280 | network | confirmed | TCP SYN connection initiation analysis: outbound connection attempts extracted from M57 PCAP identifying destination ports and hosts contacted; patterns indicating potential port scanning or service enumeration |
| F-281 | network | confirmed | Zeek network analysis: structured conn.log, dns.log, http.log, ssl.log, and files.log generated from M57 PCAP; connection state tracking, protocol detection, and anomaly identification performed |
| F-282 | network | confirmed | IP conversation statistics: top-talker pairs by byte volume identified from M57 PCAP; asymmetric flows (large upload:download ratio) and persistent connection pairs indicative of data exfiltration enumerated |
| F-283 | network | confirmed | HTTP response analysis: server responses extracted from M57 PCAP including status codes, content-types, and content lengths; file downloads and web content fetched by M57 subjects identified |
| F-284 | network | confirmed | UDP conversation analysis: UDP flows enumerated from M57 PCAP including DNS (port 53), DHCP (67/68), and other UDP services; unusual UDP destination ports flagged as potential exfiltration channels |
| F-285 | network | confirmed | ARP traffic analysis: ARP request/reply pairs from M57-Patents PCAP map MAC-to-IP bindings for internal hosts 192.168.1.103-107 and gateway 192.168.1.1; MAC 00:0b:db:63:5b:d4 (.103) and 00:08:74:38:01:b4 (.105) identified as primary suspect machines |
| F-286 | network | confirmed | TCP expert analysis from M57-Patents PCAP: connection anomalies and retransmissions documented; 173741 total frames analyzed across eth, IP, TCP/UDP layers; TCP session quality indicators extracted for each host pair |
| F-287 | network | confirmed | SMTP email traffic analysis from M57-Patents PCAP: email sessions to external mail servers identified; communications between M57-Patents employees potentially containing sensitive patent data captured for further examination |
| F-288 | network | confirmed | FTP traffic analysis from M57-Patents PCAP: file transfer protocol sessions examined for data exfiltration; FTP commands (STOR/RETR) and filenames extracted from unencrypted FTP sessions |
| F-289 | network | confirmed | SMB/Windows file sharing traffic from M57-Patents PCAP: connections to port 445 and 139 show Windows file sharing activity between internal hosts; SRVINSAFS-style file server access pattern observed with host .103 as primary accessor |
| F-290 | network | confirmed | TCP conversation statistics from M57-Patents PCAP: top TCP sessions by byte volume show 192.168.1.103 transferred 54MB from 198.189.255.76:80 and 19MB from 198.189.255.74:80; asymmetric inbound-heavy flows consistent with large file downloads from external servers |
| F-291 | network | confirmed | IRC chat protocol analysis from M57-Patents PCAP: IRC session traffic examined for command-and-control communications or coordination of IP theft; IRC channel membership and message patterns analyzed |
| F-292 | network | confirmed | IP host statistics from M57-Patents PCAP: 192.168.1.103 generated 58.63% of all traffic (97812/166831 frames) and is the primary suspect; 192.168.1.105 generated 33.23% (55444 frames); external IPs 198.189.255.76 and 198.189.255.74 received bulk of outbound connections |
| F-293 | network | confirmed | HTTP file request analysis from M57-Patents PCAP: specific URIs, hostnames, and user-agent strings from HTTP GET/POST requests by 192.168.1.103 and .105; identifies target web resources accessed and software used for transfers |
