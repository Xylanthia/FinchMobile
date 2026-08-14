import Foundation

/// Maps IoT Vulns probe evidence to **real** CVE-IDs for physical red-team speed.
/// Only emits known published CVEs — never invents IDs from prose.
enum CVEEnricher {
    static func enrich(
        hits: [OffenseHit],
        banners: [Banner],
        fingerprint: FingerprintMatch?,
        vendor: String?
    ) -> [OffenseHit] {
        let blob = evidenceBlob(banners: banners, fingerprint: fingerprint, vendor: vendor)
        var out = hits.map { enrichHit($0, blob: blob, fingerprint: fingerprint) }

        // Device-class advisories even when the specific probe was only "open port"
        out.append(contentsOf: fingerprintAdvisories(fingerprint: fingerprint, vendor: vendor, banners: banners))
        out.append(contentsOf: bannerVersionAdvisories(banners: banners))

        // Dedupe by id, prefer hits that already carry CVEs
        var seen = Set<String>()
        var deduped: [OffenseHit] = []
        for hit in out.sorted(by: { $0.cves.count > $1.cves.count }) {
            if seen.contains(hit.id) { continue }
            seen.insert(hit.id)
            deduped.append(hit)
        }
        return deduped
    }

    // MARK: - Per-hit

    private static func enrichHit(_ hit: OffenseHit, blob: String, fingerprint: FingerprintMatch?) -> OffenseHit {
        var cves = hit.cves
        let src = hit.source.lowercased()
        let sum = (hit.summary + " " + hit.detail).lowercased()
        let family = IoTPorts.family(for: hit.port)
        let udpFam = IoTPorts.udpFamily(for: hit.port)

        func add(_ list: [CVERef]) {
            for c in list where !cves.contains(where: { $0.cve == c.cve }) {
                cves.append(c)
            }
        }

        // Service / probe class
        switch src {
        case "offense.redis":
            if sum.contains("without auth") || sum.contains("redis_version") {
                add(redisUnauth)
            }
        case "offense.memcached":
            add(memcachedOpen)
        case "offense.mongodb":
            add(mongoExposed)
        case "offense.mqtt":
            add(mqttOpen)
        case "offense.snmp":
            add(snmpPublic)
        case "offense.coap":
            add(coapOpen)
        case "offense.telnet":
            add(telnetExposed)
        case "offense.ftp":
            if sum.contains("anonymous") {
                add(ftpAnonymous)
            } else {
                add(ftpExposed)
            }
        case "offense.rtsp", "offense.onvif":
            add(cameraSurface(blob: blob, fingerprint: fingerprint))
        case "offense.http":
            add(httpSurface(blob: blob + " " + sum, fingerprint: fingerprint, port: hit.port))
        case "offense.ports":
            if family == "adb" || hit.port == 5555 {
                add(adbExposed)
            } else if family == "tr069" || hit.port == 7547 {
                add(tr069Surface(blob: blob))
            } else if family == "dahua" || hit.port == 37777 {
                add(dahuaAuth)
            } else if family == "hikvision-dvr" || hit.port == 34567 {
                add(hikvisionAuth)
            } else if hit.port == 445 {
                add(smbExposed)
            } else if hit.port == 3389 {
                add(rdpExposed)
            } else if family == "telnet" {
                add(telnetExposed)
            }
        case "offense.udp":
            if udpFam == "snmp" { add(snmpPublic) }
            if udpFam == "coap" || udpFam == "coaps" { add(coapOpen) }
            if udpFam == "tftp" { add(tftpOpen) }
            if udpFam == "mavlink" { add(mavlinkOpen) }
        default:
            break
        }

        // Camera packs only when evidence looks like a camera/DVR — not every HTTP port
        if src.contains("rtsp") || src.contains("onvif")
            || (src.contains("http") && cameraEvidence(blob: blob, fingerprint: fingerprint)) {
            add(cameraSurface(blob: blob, fingerprint: fingerprint))
        }

        if blob.contains("hikvision") || blob.contains("dvrdvs") || blob.contains("isapi") {
            add(hikvisionAuth)
        }
        if blob.contains("dahua") || blob.contains("dh-") {
            add(dahuaAuth)
        }
        if blob.contains("log4j") || blob.contains("log4shell") || sum.contains("log4j") {
            add([ref("CVE-2021-44228", "Apache Log4j RCE (Log4Shell)",
                    "Java logging RCE — verify Log4j 2.x on this service.", "banner", "check-version")])
        }
        if blob.contains("fortinet") || blob.contains("fortigate") || blob.contains("fortios") {
            add([ref("CVE-2018-13379", "Fortinet FortiOS path traversal",
                    "SSL VPN credential theft path — common on FortiGate.", "banner", "likely")])
        }
        if (blob.contains("pulse") && blob.contains("secure")) || blob.contains("pulsesecure") || blob.contains("ivanti") {
            add([ref("CVE-2019-11510", "Pulse Secure VPN arbitrary file read",
                    "Classic VPN pre-auth file read — check Pulse/Ivanti.", "banner", "likely")])
        }
        if blob.contains("citrix") || blob.contains("netscaler") {
            add([ref("CVE-2019-19781", "Citrix ADC / Gateway path traversal",
                    "Pre-auth RCE chain starter on Citrix ADC/Gateway.", "banner", "likely")])
        }
        if blob.contains("zyxel") {
            add([
                ref("CVE-2020-29583", "Zyxel hardcoded credentials",
                    "Hardcoded admin-class credentials on some Zyxel firewalls.", "banner", "likely"),
                ref("CVE-2023-28771", "Zyxel IKEv2 buffer overflow RCE",
                    "Remote RCE via IKEv2 on vulnerable Zyxel firmware.", "banner", "check-version")
            ])
        }

        var copy = hit
        copy.cves = cves
        if !cves.isEmpty {
            let criticalIDs: Set<String> = [
                "CVE-2021-36260", "CVE-2021-44228", "CVE-2017-0144",
                "CVE-2021-33044", "CVE-2021-33045", "CVE-2019-0708", "CVE-2020-0796"
            ]
            if cves.contains(where: { criticalIDs.contains($0.cve) }),
               hit.severity == "INFO" || hit.severity == "MEDIUM" || hit.severity == "HIGH" {
                copy.severity = "CRITICAL"
            }
        }
        return copy
    }

    // MARK: - Fingerprint / banner advisories

    private static func fingerprintAdvisories(
        fingerprint: FingerprintMatch?,
        vendor: String?,
        banners: [Banner]
    ) -> [OffenseHit] {
        let v = ((fingerprint?.vendor ?? "") + " " + (vendor ?? "") + " " + (fingerprint?.model ?? "")).lowercased()
        let port = banners.first?.port ?? 80
        var hits: [OffenseHit] = []

        if v.contains("hikvision") {
            hits.append(
                OffenseHit(
                    source: "cve.fingerprint",
                    severity: "CRITICAL",
                    port: port,
                    proto: "tcp",
                    summary: "Hikvision device — priority CVEs",
                    detail: "Fingerprinted Hikvision. Validate patch level against cmd-injection / auth-bypass.",
                    cves: hikvisionAuth
                )
            )
        }
        if v.contains("dahua") || v.contains("amcrest") {
            hits.append(
                OffenseHit(
                    source: "cve.fingerprint",
                    severity: "CRITICAL",
                    port: port,
                    proto: "tcp",
                    summary: "Dahua/Amcrest device — priority CVEs",
                    detail: "Fingerprinted Dahua-family camera/DVR. Check auth-bypass CVEs before deeper tests.",
                    cves: dahuaAuth
                )
            )
        }
        if v.contains("axis") {
            hits.append(
                OffenseHit(
                    source: "cve.fingerprint",
                    severity: "HIGH",
                    port: port,
                    proto: "tcp",
                    summary: "Axis camera — priority CVEs",
                    detail: "Axis VAPIX surface — check firmware against known Axis CVEs.",
                    cves: [
                        ref("CVE-2018-10660", "Axis IP camera shell command injection",
                            "Unauth/low-auth command injection on multiple Axis models.", "fingerprint", "likely"),
                        ref("CVE-2018-10661", "Axis IP camera access-control bypass",
                            "Companion Axis flaw from the same 2018 advisory set.", "fingerprint", "likely")
                    ]
                )
            )
        }
        if v.contains("reolink") {
            hits.append(
                OffenseHit(
                    source: "cve.fingerprint",
                    severity: "HIGH",
                    port: port,
                    proto: "tcp",
                    summary: "Reolink camera — priority CVEs",
                    detail: "Reolink devices have had key disclosure / auth issues — verify firmware.",
                    cves: [
                        ref("CVE-2021-40149", "Reolink E1 Zoom SSL private key disclosure",
                            "Web root can expose /self.key — pull cert/key if present.", "fingerprint", "likely"),
                        ref("CVE-2020-25169", "Reolink P2P cleartext sensitive data",
                            "P2P path may leak camera feeds / sensitive data in transit.", "fingerprint", "likely")
                    ]
                )
            )
        }
        return hits
    }

    private static func bannerVersionAdvisories(banners: [Banner]) -> [OffenseHit] {
        var hits: [OffenseHit] = []
        for b in banners {
            let text = (b.rawASCII + " " + b.headers.map { "\($0.key):\($0.value)" }.joined()).lowercased()

            if let ver = firstMatch(text, pattern: #"redis_version:([0-9]+\.[0-9]+\.[0-9]+)"#) {
                hits.append(
                    OffenseHit(
                        source: "cve.banner",
                        severity: "HIGH",
                        port: b.port,
                        proto: "tcp",
                        summary: "Redis \(ver) — version CVE check",
                        detail: "Banner reports redis_version \(ver). Cross-check NVD for this exact version.",
                        cves: redisUnauth
                    )
                )
            }
            if text.contains("openssh") {
                hits.append(
                    OffenseHit(
                        source: "cve.banner",
                        severity: "MEDIUM",
                        port: b.port,
                        proto: "tcp",
                        summary: "OpenSSH banner — version CVE check",
                        detail: String(b.rawASCII.prefix(160)),
                        cves: [
                            ref("CVE-2024-6387", "OpenSSH regreSSHion (signal handler RACE)",
                                "RCE as root on glibc systems — unpatched OpenSSH 8.5–9.7p1.", "banner", "check-version"),
                            ref("CVE-2023-38408", "OpenSSH ssh-agent PKCS#11 remote code load",
                                "Agent forwarding RCE class — relevant if agent forwarding used.", "banner", "check-version")
                        ]
                    )
                )
            }
            if text.contains("apache/") {
                hits.append(
                    OffenseHit(
                        source: "cve.banner",
                        severity: "HIGH",
                        port: b.port,
                        proto: "tcp",
                        summary: "Apache HTTP — priority CVEs",
                        detail: String(b.rawASCII.prefix(160)),
                        cves: [
                            ref("CVE-2021-41773", "Apache 2.4.49 path traversal / RCE",
                                "Path traversal; RCE if CGI enabled.", "banner", "check-version"),
                            ref("CVE-2021-42013", "Apache 2.4.50 path traversal / RCE",
                                "Incomplete fix follow-up to 41773.", "banner", "check-version")
                        ]
                    )
                )
            }
            if text.contains("nginx/") {
                // nginx CVEs are often less critical; still give operators a pointer
                hits.append(
                    OffenseHit(
                        source: "cve.banner",
                        severity: "MEDIUM",
                        port: b.port,
                        proto: "tcp",
                        summary: "nginx banner — version CVE check",
                        detail: String(b.rawASCII.prefix(160)),
                        cves: [
                            ref("CVE-2021-23017", "nginx DNS resolver off-by-one RCE",
                                "Resolver vulnerability in certain nginx builds.", "banner", "check-version")
                        ]
                    )
                )
            }
            if text.contains("elasticsearch") || text.contains("lucene") {
                hits.append(
                    OffenseHit(
                        source: "cve.banner",
                        severity: "CRITICAL",
                        port: b.port,
                        proto: "tcp",
                        summary: "Elasticsearch — priority CVEs",
                        detail: String(b.rawASCII.prefix(160)),
                        cves: elasticsearchExposed
                    )
                )
            }
            if text.contains("samba") || text.contains("microsoft") && b.port == 445 {
                hits.append(
                    OffenseHit(
                        source: "cve.banner",
                        severity: "CRITICAL",
                        port: b.port,
                        proto: "tcp",
                        summary: "SMB service — priority CVEs",
                        detail: String(b.rawASCII.prefix(160)),
                        cves: smbExposed
                    )
                )
            }
        }
        return hits
    }

    // MARK: - CVE packs (real IDs only)

    private static let hikvisionAuth: [CVERef] = [
        ref("CVE-2021-36260", "Hikvision web server command injection",
            "Unauthenticated RCE on many Hikvision cameras/NVRs — #1 physical RT check.", "fingerprint", "likely"),
        ref("CVE-2017-7921", "Hikvision authentication bypass",
            "Auth bypass / credential disclosure on older Hikvision firmware.", "fingerprint", "check-version")
    ]

    private static let dahuaAuth: [CVERef] = [
        ref("CVE-2021-33044", "Dahua auth bypass (IPC/VTH/VTO…)",
            "Identity authentication bypass — widely exploited on Dahua gear.", "fingerprint", "likely"),
        ref("CVE-2021-33045", "Dahua auth bypass (same family)",
            "Companion auth bypass to 33044 — same engagement checklist.", "fingerprint", "likely")
    ]

    private static let redisUnauth: [CVERef] = [
        ref("CVE-2022-0543", "Redis Lua sandbox escape (Debian/Ubuntu package)",
            "Unauth Redis + packaged Lua = RCE on Debian-based Redis packages.", "service", "likely"),
        ref("CVE-2025-21605", "Redis DoS via unlimited output buffers",
            "Unauthenticated clients can exhaust memory — NVD confirmed.", "service", "likely"),
        ref("CVE-2023-36824", "Redis heap overflow in COMMAND GETKEYS",
            "Memory corruption in some Redis 7.0 builds — check version.", "service", "check-version")
    ]

    private static let memcachedOpen: [CVERef] = [
        ref("CVE-2018-1000115", "Memcached UDP amplification / abuse",
            "Open Memcached often abused for DDoS amplification.", "service", "likely"),
        ref("CVE-2016-8704", "Memcached binary protocol append/prepend RCE",
            "Integer overflow RCE class on vulnerable Memcached.", "service", "check-version")
    ]

    private static let mongoExposed: [CVERef] = [
        ref("CVE-2019-2390", "MongoDB JS injection via $where / mapReduce",
            "Exposed Mongo without auth historically led to wipe/ransom campaigns.", "exposure", "exposure"),
        ref("CVE-2021-20330", "MongoDB server-side JS issues",
            "Check Mongo version if JS execution features enabled.", "service", "check-version")
    ]

    private static let mqttOpen: [CVERef] = [
        ref("CVE-2017-7650", "Eclipse Mosquitto ACL bypass",
            "Open MQTT brokers often Mosquitto — check ACL/auth config.", "service", "check-version"),
        ref("CVE-2018-12546", "Mosquitto ACL reapply after modify",
            "ACL not reapplied correctly on some Mosquitto versions.", "service", "check-version"),
        ref("CVE-2019-11779", "Mosquitto SUBSCRIBE heap overflow",
            "Malformed SUBSCRIBE can crash/corrupt some Mosquitto builds.", "service", "check-version")
    ]

    private static let snmpPublic: [CVERef] = [
        ref("CVE-2017-6736", "Cisco IOS SNMP remote code execution",
            "If this is Cisco gear with SNMP, check IOS SNMP RCE advisories.", "service", "check-version"),
        ref("CVE-2008-0960", "SNMPv3 HMAC authentication bypass",
            "Classic SNMP auth issues — public community already = full read.", "exposure", "exposure")
    ]

    private static let coapOpen: [CVERef] = []

    private static let tftpOpen: [CVERef] = [
        ref("CVE-2015-7767", "Konica Minolta TFTP directory traversal",
            "Open TFTP frequently allows firmware/config pull on printers/IoT.", "service", "check-version")
    ]

    private static let mavlinkOpen: [CVERef] = [
        ref("CVE-2020-10282", "MAVLink v1.0 missing authentication",
            "Open MAVLink UDP = spoof/command drone/autopilot traffic.", "service", "likely"),
        ref("CVE-2020-10283", "MAVLink v2.0 weak/optional authentication",
            "MAVLink 2 auth is optional/negotiable — treat open UDP as hostile.", "service", "likely")
    ]

    private static let telnetExposed: [CVERef] = [
        ref("CVE-2017-17215", "Huawei HG532 remote code execution via CWMP",
            "Cleartext Telnet on gateways often pairs with TR-069/Mirai-class paths.", "exposure", "check-version")
    ]

    private static let ftpAnonymous: [CVERef] = [
        ref("CVE-2015-3306", "ProFTPD mod_copy unauthenticated copy (RCE chain)",
            "Anonymous/unauth FTP features have led to RCE on ProFTPD.", "service", "check-version"),
        ref("CVE-2011-2523", "vsftpd 2.3.4 smiley-face backdoor",
            "If banner is vsftpd 2.3.4, treat as planted backdoor implant.", "banner", "likely")
    ]

    private static let ftpExposed: [CVERef] = [
        ref("CVE-2015-3306", "ProFTPD mod_copy unauthenticated copy",
            "Cleartext FTP — check server software/version for known RCE.", "service", "check-version")
    ]

    private static let adbExposed: [CVERef] = [
        // ADB itself is an intentional debug surface; cite Android stack issues operators know.
        ref("CVE-2016-5195", "Dirty COW (local privilege escalation)",
            "Open ADB gives a shell — local LPE CVEs like Dirty COW matter after shell.", "exposure", "exposure")
    ]

    private static let smbExposed: [CVERef] = [
        ref("CVE-2017-0144", "EternalBlue SMBv1 RCE (MS17-010)",
            "Still hits unpatched Windows / some NAS — first check on TCP/445.", "service", "likely"),
        ref("CVE-2020-0796", "SMBGhost (SMBv3 compression RCE)",
            "Unpatched Windows 10 / Server 1903–1909 SMBv3.", "service", "check-version")
    ]

    private static let rdpExposed: [CVERef] = [
        ref("CVE-2019-0708", "BlueKeep RDP RCE",
            "Unpatched RDP on older Windows — wormable.", "service", "likely"),
        ref("CVE-2019-1181", "DejaBlue RDP RCE family",
            "Follow-on RDP RCEs — check Windows patch level.", "service", "check-version")
    ]

    private static let elasticsearchExposed: [CVERef] = [
        ref("CVE-2015-1427", "Elasticsearch Groovy sandbox RCE",
            "Historic but still seen on forgotten ELK boxes.", "service", "check-version"),
        ref("CVE-2014-3120", "Elasticsearch dynamic scripting RCE",
            "Older Elasticsearch with dynamic scripts enabled.", "service", "check-version"),
        ref("CVE-2015-5531", "Elasticsearch directory traversal",
            "Snapshot API traversal on older ES.", "service", "check-version")
    ]

    private static func tr069Surface(blob: String) -> [CVERef] {
        var list = [
            ref("CVE-2016-10372", "Eir D1000 / ZyXEL TR-064 remote command execution",
                "TR-069/TR-064 on TCP/7547 — Mirai’s classic NewNTPServer path.", "service", "likely"),
            ref("CVE-2017-17215", "Huawei HG532 RCE via TR-069/CWMP",
                "TR-069 open on LAN/WAN was a Mirai loader path.", "service", "likely")
        ]
        if blob.contains("huawei") || blob.contains("hg532") {
            list.insert(
                ref("CVE-2017-17215", "Huawei HG532 RCE via TR-069/CWMP",
                    "Huawei evidence + TR-069 — prioritize this CVE.", "banner", "likely"),
                at: 0
            )
        }
        return dedupe(list)
    }

    private static func cameraEvidence(blob: String, fingerprint: FingerprintMatch?) -> Bool {
        let v = ((fingerprint?.vendor ?? "") + " " + (fingerprint?.deviceType ?? "") + " " + blob).lowercased()
        let needles = [
            "hikvision", "dahua", "amcrest", "reolink", "axis", "onvif", "rtsp", "isapi",
            "ipcam", "ip camera", "dvr", "nvr", "hisilicon", "goahead", "vacron", "tvt", "tbk"
        ]
        return needles.contains { v.contains($0) }
            || (fingerprint?.deviceType.lowercased().contains("camera") ?? false)
            || (fingerprint?.deviceType.lowercased().contains("dvr") ?? false)
    }

    private static func cameraSurface(blob: String, fingerprint: FingerprintMatch?) -> [CVERef] {
        var list: [CVERef] = []
        let v = ((fingerprint?.vendor ?? "") + " " + blob).lowercased()
        // White-label DVR packs only when evidence points at that class — not every camera
        if v.contains("tbk") || v.contains("tvt") || v.contains("vacron") || v.contains("device.rsp")
            || v.contains("login.rsp") {
            list.append(
                ref("CVE-2018-9995", "TBK DVR / TVT credential disclosure",
                    "Many white-label DVRs leak credentials via `/device.rsp`.", "exposure", "likely")
            )
        }
        if v.contains("hisilicon") || v.contains("hi35") || v.contains("xm") && v.contains("dvr") {
            list.append(
                ref("CVE-2020-25078", "HiSilicon-based DVR credential disclosure",
                    "Unauth credential dump on some HiSilicon DVR/camera OEMs.", "exposure", "likely")
            )
        }
        if v.contains("hikvision") { list.append(contentsOf: hikvisionAuth) }
        if v.contains("dahua") || v.contains("amcrest") { list.append(contentsOf: dahuaAuth) }
        if v.contains("reolink") {
            list.append(contentsOf: [
                ref("CVE-2021-40149", "Reolink E1 Zoom SSL private key disclosure",
                    "Web root can expose /self.key — pull cert/key if present.", "fingerprint", "likely"),
                ref("CVE-2020-25169", "Reolink P2P cleartext sensitive data",
                    "P2P path may leak camera feeds / sensitive data in transit.", "fingerprint", "likely")
            ])
        }
        if v.contains("axis") {
            list.append(contentsOf: [
                ref("CVE-2018-10660", "Axis IP camera shell command injection",
                    "Unauth/low-auth command injection on multiple Axis models.", "fingerprint", "likely"),
                ref("CVE-2018-10661", "Axis IP camera access-control bypass",
                    "Companion Axis flaw from the same 2018 advisory set.", "fingerprint", "likely")
            ])
        }
        return dedupe(list)
    }

    private static func httpSurface(blob: String, fingerprint: FingerprintMatch?, port: Int) -> [CVERef] {
        var list: [CVERef] = []
        let b = blob.lowercased()
        if b.contains("hikvision") || b.contains("isapi") { list.append(contentsOf: hikvisionAuth) }
        if b.contains("dahua") || b.contains("amcrest") { list.append(contentsOf: dahuaAuth) }
        if cameraEvidence(blob: blob, fingerprint: fingerprint) {
            list.append(contentsOf: cameraSurface(blob: blob, fingerprint: fingerprint))
        }
        if port == 9200 || b.contains("elasticsearch") {
            list.append(contentsOf: elasticsearchExposed)
        }
        if b.contains("goahead") && cameraEvidence(blob: blob, fingerprint: fingerprint) {
            list.append(
                ref("CVE-2017-8225", "Wireless IP camera GoAhead — hardcoded creds / backdoor class",
                    "GoAhead-based OEM cameras often ship with default/hardcoded accounts.", "banner", "likely")
            )
        }
        return dedupe(list)
    }

    // MARK: - Helpers

    private static func evidenceBlob(banners: [Banner], fingerprint: FingerprintMatch?, vendor: String?) -> String {
        var parts: [String] = []
        if let vendor { parts.append(vendor) }
        if let fingerprint {
            parts.append(fingerprint.vendor)
            parts.append(fingerprint.model)
            parts.append(fingerprint.deviceType)
            parts.append(contentsOf: fingerprint.tags)
        }
        for b in banners {
            parts.append(b.rawASCII)
            parts.append(b.protocolGuess)
            for (k, v) in b.headers { parts.append("\(k):\(v)") }
        }
        return parts.joined(separator: " ").lowercased()
    }

    private static func ref(
        _ cve: String,
        _ title: String,
        _ why: String,
        _ match: String,
        _ confidence: String
    ) -> CVERef {
        CVERef(cve: cve, title: title, why: why, match: match, confidence: confidence)
    }

    private static func dedupe(_ list: [CVERef]) -> [CVERef] {
        var seen = Set<String>()
        var out: [CVERef] = []
        for c in list where !seen.contains(c.cve) {
            seen.insert(c.cve)
            out.append(c)
        }
        return out
    }

    private static func firstMatch(_ text: String, pattern: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]),
              let m = re.firstMatch(in: text, range: NSRange(text.startIndex..., in: text)),
              m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }
}

// MARK: - BLE Radar CVE mapping

/// Maps Nearby Bluetooth (BLE Radar) device identity to real CVE-IDs for physical RT.
enum BLECVEEnricher {
    static func cves(for device: BLEDevice) -> [CVERef] {
        // Advertisements do not include firmware versions. Do not invent CVE hits here.
        _ = device
        return []
    }

    // MARK: Packs (real CVE-IDs only)

    private static let tpmsCVEs: [CVERef] = [
        ref("CVE-2024-39081", "SMART TYRE / BLE TPMS capture-replay MITM",
            "BLE tire-pressure apps/sensors — MITM & replay of Bluetooth auth.", "ble-tpms", "likely"),
        ref("CVE-2025-2082", "Tesla Model 3 VCSEC RCE via TPMS certificate response",
            "Spoofed TPMS BLE traffic → integer overflow RCE on VCSEC / CAN access.", "ble-tpms", "likely")
    ]

    private static let teslaBLE: [CVERef] = [
        ref("CVE-2025-2082", "Tesla Model 3 VCSEC RCE via TPMS",
            "Priority if Tesla BLE / TPMS advertisements are in range.", "ble-vehicle", "likely")
    ]

    private static let trackerCVEs: [CVERef] = [
        ref("CVE-2020-9770", "Apple Bluetooth traffic interception (iOS/iPadOS)",
            "Logic issue fixed in iOS 13.4 — Continuity/Find My ads still matter for tracking ops.", "ble-tracker", "check-version"),
        ref("CVE-2019-9506", "KNOB — Bluetooth encryption key negotiation",
            "Trackers with long-lived bonds can have encryption downgraded.", "ble-tracker", "exposure")
    ]

    private static let appleBLE: [CVERef] = [
        ref("CVE-2020-9770", "Apple Bluetooth traffic interception",
            "Privileged-network Bluetooth intercept on older iOS — check Continuity devices in range.", "ble-apple", "check-version"),
        ref("CVE-2024-0230", "Apple Magic Keyboard pairing-key extraction",
            "Physical/access accessory attack — extract BT pairing key & monitor traffic.", "ble-apple", "check-version"),
        ref("CVE-2023-45866", "Bluetooth HID keystroke injection",
            "If host accepts Bluetooth keyboards — inject keystrokes over the air.", "ble-apple", "check-version"),
        ref("CVE-2019-9506", "KNOB attack against Bluetooth encryption",
            "Still relevant against older companion phones/watches in range.", "ble-apple", "exposure")
    ]

    private static let audioBLE: [CVERef] = [
        ref("CVE-2019-9506", "KNOB — weak Bluetooth encryption negotiation",
            "Headphones/earbuds often stay paired with weak BR/EDR crypto.", "ble-audio", "exposure"),
        ref("CVE-2020-0022", "Android Bluetooth High Extremely Dangerous (BlueFrag)",
            "If the companion phone is Android nearby — BlueFrag RCE class.", "ble-audio", "check-version")
    ]

    private static let wearableBLE: [CVERef] = [
        ref("CVE-2020-15802", "Bluetooth LE Secure Connections authentication bypass",
            "Fitness bands often use weak LE pairing — check bonding requirements.", "ble-wearable", "check-version"),
        ref("CVE-2019-9506", "KNOB — Bluetooth encryption key downgrade",
            "Wearables frequently keep long-lived pairings vulnerable to key-length attacks.", "ble-wearable", "exposure")
    ]

    private static let hidBLE: [CVERef] = [
        ref("CVE-2023-45866", "Bluetooth HID keystroke injection",
            "Unauthenticated HID injection against hosts that accept Bluetooth keyboards.", "ble-hid", "likely"),
        ref("CVE-2024-0230", "Apple Magic Keyboard pairing-key extraction",
            "If this is an Apple keyboard accessory — pairing key can be extracted.", "ble-hid", "check-version")
    ]

    private static let sweyntooth: [CVERef] = [
        ref("CVE-2020-10061", "Sweyntooth — Link Layer Length Overflow",
            "Crashes/DoS (and worse on some SoCs) via malformed BLE LL Length.", "ble-sdk", "likely"),
        ref("CVE-2020-10069", "Sweyntooth — Link Layer LLID deadlocks",
            "SoftDevice / BLE stack DoS via LLID manipulation.", "ble-sdk", "likely"),
        ref("CVE-2019-16336", "Sweyntooth — Truncated L2CAP causes hard fault",
            "Nordic SoftDevice hard-fault via truncated L2CAP.", "ble-sdk", "check-version")
    ]

    private static let espressifBLE: [CVERef] = [
        ref("CVE-2020-10061", "Sweyntooth-class BLE LL overflow (ESP/SDK ecosystems)",
            "ESP32 BLE stacks historically shared Sweyntooth-class bugs — verify IDF version.", "ble-esp", "check-version")
    ]

    private static let connectableBLE: [CVERef] = [
        ref("CVE-2017-0781", "BlueBorne — Android BNEP information disclosure",
            "Connectable classic/BLE-adjacent Android surfaces — BlueBorne family.", "ble-connectable", "check-version"),
        ref("CVE-2017-1000251", "BlueBorne — Linux Bluetooth stack RCE",
            "If a Linux IoT/host is connectable over Bluetooth — BlueBorne RCE.", "ble-connectable", "check-version"),
        ref("CVE-2020-15802", "Bluetooth LE Secure Connections authentication bypass",
            "Pairing/auth bypass on some LE Secure Connections implementations.", "ble-connectable", "check-version")
    ]

    private static func ref(
        _ cve: String,
        _ title: String,
        _ why: String,
        _ match: String,
        _ confidence: String
    ) -> CVERef {
        CVERef(cve: cve, title: title, why: why, match: match, confidence: confidence)
    }
}
