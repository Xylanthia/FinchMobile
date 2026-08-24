import Foundation

/// Public county assessor / GIS lookups — same portal catalog as desktop Finch.
enum CountyAssessorService {
    struct PortalRow: Codable {
        var state: String
        var county: String
        var zip_prefixes: [String]?
        var city_aliases: [String]?
        var search_url: String?
        var gis_url: String?
        var gis_kind: String?
        var gis_where: String?
        var gis_out_fields: String?
        var gis_owner_fields: [String]?
    }

    struct PortalBundle: Codable {
        var counties: [PortalRow]
    }

    struct AddressComponents {
        var raw: String
        var street: String
        var city: String
        var state: String
        var zip: String
        var county: String
        var standardized: String
        var lat: Double?
        var lng: Double?
    }

    struct CountyResult {
        var findings: [OsintFinding]
        var actions: [OsintAction]
    }

    private static let portals: PortalBundle = {
        guard let url = Bundle.main.url(forResource: "county_portals", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(PortalBundle.self, from: data) else {
            return PortalBundle(counties: [])
        }
        return decoded
    }()

    static func investigate(_ rawAddress: String) async -> CountyResult {
        var findings: [OsintFinding] = []
        var actions: [OsintAction] = []
        var comps = parseComponents(rawAddress)
        await enrichComponents(rawAddress, into: &comps, findings: &findings)

        if !comps.county.isEmpty {
            let label = [comps.county, comps.state].filter { !$0.isEmpty }.joined(separator: ", ")
            findings.append(OsintFinding(
                source: "county",
                kind: "property",
                value: label,
                relevance: "signal",
                note: "Census / geocoder county"
            ))
        }

        let matched = matchPortals(comps)
        if matched.isEmpty {
            findings.append(OsintFinding(
                source: "county",
                kind: "note",
                value: "No bundled assessor portal for \(comps.state.isEmpty ? "this ZIP" : comps.state + " " + comps.zip)",
                relevance: "static",
                url: "https://duckduckgo.com/?q=\(duckQuery(comps.raw))"
            ))
            return CountyResult(findings: findings, actions: actions)
        }

        for row in matched.prefix(3) {
            let countyLabel = row.county
            if let search = row.search_url, !search.isEmpty {
                let url = fillURL(search, comps: comps)
                findings.append(OsintFinding(
                    source: "assessor",
                    kind: "url",
                    value: "\(countyLabel) County assessor search",
                    relevance: "signal",
                    url: url
                ))
                await scrapeAssessorHTML(url: url, county: countyLabel, into: &findings, actions: &actions)
            }
            if let gis = row.gis_url, !gis.isEmpty {
                let kind = (row.gis_kind ?? "").lowercased()
                if kind == "arcgis_query" || (gis.contains("/MapServer/") && gis.hasSuffix("/query")) {
                    await queryArcGIS(row: row, comps: comps, into: &findings, actions: &actions)
                } else {
                    let url = fillURL(gis, comps: comps)
                    findings.append(OsintFinding(
                        source: "gis",
                        kind: "url",
                        value: "\(countyLabel) County GIS",
                        relevance: "signal",
                        url: url
                    ))
                }
            }
        }

        return CountyResult(findings: findings, actions: actions)
    }

    // MARK: - Geocode enrichment

    private static func enrichComponents(
        _ raw: String,
        into comps: inout AddressComponents,
        findings: inout [OsintFinding]
    ) async {
        let encoded = raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw

        if var urlComps = URLComponents(string: "https://nominatim.openstreetmap.org/search") {
            urlComps.queryItems = [
                URLQueryItem(name: "q", value: raw),
                URLQueryItem(name: "format", value: "json"),
                URLQueryItem(name: "addressdetails", value: "1"),
                URLQueryItem(name: "limit", value: "1")
            ]
            if let url = urlComps.url {
                let (code, data) = await OsintHTTP.get(url: url, headers: ["User-Agent": "FinchMobile/3.2 (authorized OSINT)"])
                if code == 200, let arr = OsintHTTP.jsonObject(data) as? [[String: Any]], let first = arr.first {
                    if let display = first["display_name"] as? String {
                        comps.standardized = display
                        findings.append(OsintFinding(source: "nominatim", kind: "property", value: display, relevance: "static"))
                    }
                    if let latStr = first["lat"] as? String, let lonStr = first["lon"] as? String {
                        comps.lat = Double(latStr)
                        comps.lng = Double(lonStr)
                    }
                    if let addr = first["address"] as? [String: Any] {
                        if comps.city.isEmpty {
                            comps.city = (addr["city"] as? String)
                                ?? (addr["town"] as? String)
                                ?? (addr["village"] as? String)
                                ?? (addr["suburb"] as? String)
                                ?? ""
                        }
                        if comps.zip.isEmpty, let pc = addr["postcode"] as? String {
                            comps.zip = String(pc.prefix(5))
                        }
                        if comps.state.isEmpty {
                            comps.state = stateAbbr(addr["state"] as? String) ?? comps.state
                        }
                        if comps.county.isEmpty {
                            comps.county = (addr["county"] as? String)
                                ?? (addr["city_district"] as? String)
                                ?? ""
                        }
                        let house = addr["house_number"] as? String ?? ""
                        let road = addr["road"] as? String ?? ""
                        if comps.street.isEmpty, !house.isEmpty, !road.isEmpty {
                            comps.street = "\(house) \(road)"
                        }
                    }
                }
            }
        }

        if let url = URL(string: "https://geocoding.geo.census.gov/geocoder/geographies/onelineaddress?address=\(encoded)&benchmark=Public_AR_Current&vintage=Current_Current&format=json") {
            let (code, data) = await OsintHTTP.get(url: url)
            if code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
               let result = obj["result"] as? [String: Any],
               let matches = result["addressMatches"] as? [[String: Any]],
               let first = matches.first {
                if let matched = first["matchedAddress"] as? String {
                    comps.standardized = matched
                    findings.append(OsintFinding(source: "census", kind: "property", value: matched, relevance: "signal"))
                }
                if let coords = first["coordinates"] as? [String: Any] {
                    let x = coords["x"] as? Double ?? 0
                    let y = coords["y"] as? Double ?? 0
                    if abs(x) > 0.0001 || abs(y) > 0.0001 {
                        comps.lat = y
                        comps.lng = x
                        findings.append(OsintFinding(
                            source: "census",
                            kind: "geo",
                            value: String(format: "%.5f, %.5f", y, x),
                            relevance: "static"
                        ))
                    }
                }
                if let attrs = first["addressComponents"] as? [String: Any] {
                    if comps.city.isEmpty, let city = attrs["city"] as? String { comps.city = city }
                    if comps.state.isEmpty, let st = attrs["state"] as? String { comps.state = st.uppercased() }
                    if comps.zip.isEmpty, let zip = attrs["zip"] as? String { comps.zip = String(zip.prefix(5)) }
                    let from = attrs["fromAddress"] as? String ?? ""
                    let preDir = attrs["preDirection"] as? String ?? ""
                    let streetName = attrs["streetName"] as? String ?? ""
                    let suffix = attrs["suffixType"] as? String ?? ""
                    if comps.street.isEmpty, !from.isEmpty, !streetName.isEmpty {
                        comps.street = [from, preDir, streetName, suffix].filter { !$0.isEmpty }.joined(separator: " ")
                    }
                }
                if let geos = first["geographies"] as? [String: Any],
                   let counties = geos["Counties"] as? [[String: Any]],
                   let c0 = counties.first {
                    let name = (c0["NAME"] as? String) ?? (c0["BASENAME"] as? String) ?? ""
                    if !name.isEmpty {
                        comps.county = name
                        if let geoid = c0["GEOID"] as? String {
                            findings.append(OsintFinding(
                                source: "census",
                                kind: "note",
                                value: "county FIPS \(geoid)",
                                relevance: "static"
                            ))
                        }
                    }
                }
            }
        }
    }

    // MARK: - Portal matching

    private static func matchPortals(_ comps: AddressComponents) -> [PortalRow] {
        let zip5 = comps.zip
        let prefix = zip5.count >= 3 ? String(zip5.prefix(3)) : ""
        let state = comps.state.uppercased()
        var cityLow = comps.city.trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
        if cityLow.isEmpty {
            let rawLow = comps.raw.lowercased()
            for hint in ["baltimore city", "baltimore"] {
                if rawLow.contains(hint) {
                    cityLow = hint
                    break
                }
            }
        }

        var hits: [PortalRow] = []
        for row in portals.counties {
            if !state.isEmpty, row.state.uppercased() != state { continue }
            let zips = row.zip_prefixes ?? []
            if !prefix.isEmpty, !zips.contains(prefix) { continue }
            hits.append(row)
            if hits.count >= 8 { break }
        }
        if hits.isEmpty, !prefix.isEmpty {
            for row in portals.counties where (row.zip_prefixes ?? []).contains(prefix) {
                hits.append(row)
                if hits.count >= 5 { break }
            }
        }
        guard !cityLow.isEmpty, !hits.isEmpty else { return Array(hits.prefix(5)) }

        var exact: [PortalRow] = []
        var fuzzy: [PortalRow] = []
        var other: [PortalRow] = []
        for row in hits {
            let aliases = (row.city_aliases ?? []).map { $0.lowercased() }
            let cname = row.county.lowercased()
            if aliases.contains(cityLow) {
                exact.append(row)
            } else if cityLow == cname || cname.hasPrefix(cityLow + " ") {
                fuzzy.append(row)
            } else if aliases.contains(where: { cityLow.contains($0) || $0.contains(cityLow) }) || cityLow.contains(cname) {
                fuzzy.append(row)
            } else {
                other.append(row)
            }
        }
        var ranked = exact + fuzzy + other
        ranked.sort { lhs, rhs in
            let lScore = (lhs.gis_kind != nil || lhs.gis_url != nil) ? 0 : 1
            let rScore = (rhs.gis_kind != nil || rhs.gis_url != nil) ? 0 : 1
            return lScore < rScore
        }
        return Array(ranked.prefix(5))
    }

    private static func fillURL(_ template: String, comps: AddressComponents) -> String {
        let q = comps.raw.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? comps.raw
        let street = comps.street.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? comps.street
        let city = comps.city.addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? comps.city
        let slug = slugAddress(comps.raw)
        return template
            .replacingOccurrences(of: "{q}", with: q)
            .replacingOccurrences(of: "{street}", with: street.isEmpty ? q : street)
            .replacingOccurrences(of: "{city}", with: city)
            .replacingOccurrences(of: "{zip}", with: comps.zip)
            .replacingOccurrences(of: "{state}", with: comps.state)
            .replacingOccurrences(of: "{slug}", with: slug)
    }

    // MARK: - Assessor HTML scrape

    private static func scrapeAssessorHTML(
        url: String,
        county: String,
        into findings: inout [OsintFinding],
        actions: inout [OsintAction]
    ) async {
        guard url.contains("http"), !url.contains("google.com/search"),
              let fetchURL = URL(string: url) else { return }
        let (code, data) = await OsintHTTP.get(url: fetchURL)
        guard code == 200, let text = String(data: data, encoding: .utf8) else { return }

        let ownerPatterns = [
            #"(?:Owner|Owners|Owner Name|Taxpayer)[:\s]+([A-Z][A-Za-z.'\-]+(?:\s+[A-Z][A-Za-z.'\-]+){1,3})"#,
            #"(?:Owner|Owners)</[^>]+>\s*([^<]{5,60})"#
        ]
        var seenOwners = Set<String>()
        for pat in ownerPatterns {
            guard let re = try? NSRegularExpression(pattern: pat, options: [.caseInsensitive]) else { continue }
            let range = NSRange(text.startIndex..<text.endIndex, in: text)
            for match in re.matches(in: text, range: range).prefix(6) {
                guard match.numberOfRanges > 1, let r = Range(match.range(at: 1), in: text) else { continue }
                let raw = String(text[r]).replacingOccurrences(of: "<[^>]+>", with: "", options: .regularExpression)
                guard let name = normalizeOwnerName(raw), !seenOwners.contains(name.lowercased()) else { continue }
                seenOwners.insert(name.lowercased())
                findings.append(OsintFinding(
                    source: "assessor",
                    kind: "name",
                    value: name,
                    relevance: "signal",
                    url: url,
                    note: "\(county) County public record"
                ))
                actions.append(OsintAction(title: "Engage owner \(name)", seed: name, pipeline: .identity))
            }
        }

        if let val = firstMatch(#"(?:Market|Assessed|Appraised|Total)\s*(?:Value)?[:\s\$]*([\d,]+)"#, in: text) {
            findings.append(OsintFinding(source: "assessor", kind: "property", value: "assessed $\(val)", relevance: "signal", note: county))
        }
        if let year = firstMatch(#"(?:Year Built|Yr Built|Built)[:\s]*(\d{4})"#, in: text) {
            findings.append(OsintFinding(source: "assessor", kind: "property", value: "built \(year)", relevance: "signal", note: county))
        }
        if let sqft = firstMatch(#"(?:Living Area|Sq\.?\s*Ft\.?|Square Feet)[:\s]*([\d,]+)"#, in: text) {
            findings.append(OsintFinding(source: "assessor", kind: "property", value: "\(sqft) sqft", relevance: "signal", note: county))
        }
    }

    // MARK: - ArcGIS public assessor layer

    private static func queryArcGIS(
        row: PortalRow,
        comps: AddressComponents,
        into findings: inout [OsintFinding],
        actions: inout [OsintAction]
    ) async {
        guard let base = row.gis_url, !base.isEmpty else { return }
        let street = comps.street.isEmpty ? comps.raw : comps.street
        let num = streetNumber(street)
        let sname = streetNameCore(street, city: comps.city)
        guard !num.isEmpty, !sname.isEmpty else { return }

        let whereTemplate = row.gis_where ?? "BLDG_NO='{num}' AND UPPER(ST_NAME) LIKE '%{street_name}%'"
        let whereClause = whereTemplate
            .replacingOccurrences(of: "{num}", with: num.replacingOccurrences(of: "'", with: "''"))
            .replacingOccurrences(of: "{street_name}", with: sname.replacingOccurrences(of: "'", with: "''"))
            .replacingOccurrences(of: "{street}", with: street.replacingOccurrences(of: "'", with: "''"))
            .replacingOccurrences(of: "{zip}", with: comps.zip)

        let outFields = row.gis_out_fields ?? "*"
        var urlComps = URLComponents(string: base)
        urlComps?.queryItems = [
            URLQueryItem(name: "where", value: whereClause),
            URLQueryItem(name: "outFields", value: outFields),
            URLQueryItem(name: "returnGeometry", value: "false"),
            URLQueryItem(name: "f", value: "json")
        ]
        guard let url = urlComps?.url else { return }
        let pivot = url.absoluteString

        let (code, data) = await OsintHTTP.get(url: url)
        guard code == 200, let obj = OsintHTTP.jsonObject(data) as? [String: Any],
              let feats = obj["features"] as? [[String: Any]], let first = feats.first,
              let attrs = first["attributes"] as? [String: Any] else {
            findings.append(OsintFinding(
                source: "gis",
                kind: "note",
                value: "ArcGIS query returned no parcel (HTTP \(code))",
                relevance: "static",
                url: pivot
            ))
            return
        }

        let county = row.county
        findings.append(OsintFinding(
            source: "gis",
            kind: "url",
            value: "\(county) County parcel (ArcGIS)",
            relevance: "signal",
            url: pivot
        ))

        let ownerFields = row.gis_owner_fields ?? ["OWNER_1", "OWNER_2", "OWNER_3", "OWNER", "OWNERNAME", "OWN_NAME"]
        var seenOwners = Set<String>()
        for fld in ownerFields {
            guard let raw = attrs[fld] as? String, !raw.trimmingCharacters(in: .whitespaces).isEmpty else { continue }
            guard let name = normalizeOwnerName(raw), !seenOwners.contains(name.lowercased()) else { continue }
            seenOwners.insert(name.lowercased())
            findings.append(OsintFinding(
                source: "gis",
                kind: "name",
                value: name,
                relevance: "signal",
                url: pivot,
                note: "\(county) assessor · \(fld)"
            ))
            actions.append(OsintAction(title: "Engage owner \(name)", seed: name, pipeline: .identity))
        }

        appendGISDetail("FULLADDR", attrs, label: "parcel address", county: county, pivot: pivot, into: &findings)
        appendGISDetail("BLOCKLOT", attrs, label: "block/lot", county: county, pivot: pivot, into: &findings)
        appendGISDetail("PIN", attrs, label: "PIN", county: county, pivot: pivot, into: &findings)
        appendGISDetail("NEIGHBOR", attrs, label: "neighborhood", county: county, pivot: pivot, into: &findings)
        appendGISDetail("MAILTOADD", attrs, label: "mailing address", county: county, pivot: pivot, into: &findings)

        if let year = attrs["YEAR_BUILD"] {
            findings.append(OsintFinding(source: "gis", kind: "property", value: "built \(year)", relevance: "signal", url: pivot, note: county))
        }
        if let sqft = attrs["STRUCTAREA"] {
            findings.append(OsintFinding(source: "gis", kind: "property", value: "\(sqft) sqft", relevance: "signal", url: pivot, note: county))
        }
        if let tax = attrs["TAXBASE"] {
            findings.append(OsintFinding(source: "gis", kind: "property", value: "tax base $\(tax)", relevance: "signal", url: pivot, note: county))
        }
        if let sale = attrs["SALEPRIC"], "\(sale)" != "0" {
            var note = county
            if let sd = attrs["SALEDATE"] as? String, !sd.isEmpty { note += " · sold \(formatSaleDate(sd))" }
            findings.append(OsintFinding(source: "gis", kind: "property", value: "last sale $\(sale)", relevance: "signal", url: pivot, note: note))
        }
        if let deedBook = attrs["DEEDBOOK"] as? String, let deedPage = attrs["DEEDPAGE"] as? String,
           !deedBook.trimmingCharacters(in: .whitespaces).isEmpty || !deedPage.trimmingCharacters(in: .whitespaces).isEmpty {
            findings.append(OsintFinding(
                source: "gis",
                kind: "record",
                value: "deed \(deedBook.trimmingCharacters(in: .whitespaces)) / \(deedPage.trimmingCharacters(in: .whitespaces))",
                relevance: "static",
                url: pivot,
                note: county
            ))
        }
        if let sdat = attrs["SDATLINK"] as? String, sdat.hasPrefix("http") {
            findings.append(OsintFinding(source: "gis", kind: "url", value: "Maryland SDAT record", relevance: "signal", url: sdat))
        }
    }

    private static func appendGISDetail(
        _ key: String,
        _ attrs: [String: Any],
        label: String,
        county: String,
        pivot: String,
        into findings: inout [OsintFinding]
    ) {
        guard let raw = attrs[key] else { return }
        let val = "\(raw)".trimmingCharacters(in: .whitespacesAndNewlines)
        guard !val.isEmpty else { return }
        findings.append(OsintFinding(source: "gis", kind: "property", value: "\(label): \(val)", relevance: "signal", url: pivot, note: county))
    }

    // MARK: - Parsing helpers

    private static func parseComponents(_ raw: String) -> AddressComponents {
        let q = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ")
        let zipRe = try? NSRegularExpression(pattern: #"\b(\d{5})(?:-(\d{4}))?\b"#)
        let stateRe = try? NSRegularExpression(pattern: #"\b([A-Z]{2})\b"#)
        var zip = ""
        var state = ""
        if let zipRe {
            let range = NSRange(q.startIndex..<q.endIndex, in: q)
            if let m = zipRe.firstMatch(in: q, range: range), let r = Range(m.range(at: 1), in: q) {
                zip = String(q[r])
            }
        }
        if let stateRe {
            let range = NSRange(q.startIndex..<q.endIndex, in: q)
            if let m = stateRe.firstMatch(in: q, range: range), let r = Range(m.range(at: 1), in: q) {
                state = String(q[r]).uppercased()
            }
        }
        var street = q
        var city = ""
        if q.contains(",") {
            let parts = q.split(separator: ",").map { $0.trimmingCharacters(in: .whitespaces) }
            street = parts.first ?? q
            if parts.count >= 2 {
                city = parts[1].replacingOccurrences(of: #"\b[A-Z]{2}\b.*$"#, with: "", options: .regularExpression)
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return AddressComponents(
            raw: q,
            street: street,
            city: city,
            state: state,
            zip: zip,
            county: "",
            standardized: q,
            lat: nil,
            lng: nil
        )
    }

    private static func stateAbbr(_ name: String?) -> String? {
        guard let name else { return nil }
        let map: [String: String] = [
            "Alabama": "AL", "Alaska": "AK", "Arizona": "AZ", "Arkansas": "AR", "California": "CA",
            "Colorado": "CO", "Connecticut": "CT", "Delaware": "DE", "Florida": "FL", "Georgia": "GA",
            "Hawaii": "HI", "Idaho": "ID", "Illinois": "IL", "Indiana": "IN", "Iowa": "IA",
            "Kansas": "KS", "Kentucky": "KY", "Louisiana": "LA", "Maine": "ME", "Maryland": "MD",
            "Massachusetts": "MA", "Michigan": "MI", "Minnesota": "MN", "Mississippi": "MS", "Missouri": "MO",
            "Montana": "MT", "Nebraska": "NE", "Nevada": "NV", "New Hampshire": "NH", "New Jersey": "NJ",
            "New Mexico": "NM", "New York": "NY", "North Carolina": "NC", "North Dakota": "ND", "Ohio": "OH",
            "Oklahoma": "OK", "Oregon": "OR", "Pennsylvania": "PA", "Rhode Island": "RI", "South Carolina": "SC",
            "South Dakota": "SD", "Tennessee": "TN", "Texas": "TX", "Utah": "UT", "Vermont": "VT",
            "Virginia": "VA", "Washington": "WA", "West Virginia": "WV", "Wisconsin": "WI", "Wyoming": "WY",
            "District of Columbia": "DC"
        ]
        if name.count == 2 { return name.uppercased() }
        return map[name] ?? map.first(where: { $0.key.caseInsensitiveCompare(name) == .orderedSame })?.value
    }

    private static func slugAddress(_ addr: String) -> String {
        let cleaned = addr.lowercased().replacingOccurrences(of: #"[^\w\s-]"#, with: "", options: .regularExpression)
        return cleaned.split(whereSeparator: \.isWhitespace).joined(separator: "-").prefix(120).description
    }

    private static func streetNumber(_ street: String) -> String {
        guard let re = try? NSRegularExpression(pattern: #"^(\d+[A-Za-z]?)\b"#),
              let m = re.firstMatch(in: street, range: NSRange(street.startIndex..<street.endIndex, in: street)),
              let r = Range(m.range(at: 1), in: street) else { return "" }
        return String(street[r])
    }

    private static func streetNameCore(_ street: String, city: String) -> String {
        var s = street.trimmingCharacters(in: .whitespacesAndNewlines)
        if let re = try? NSRegularExpression(pattern: #"^\d+[A-Za-z]?\s+"#) {
            let range = NSRange(s.startIndex..<s.endIndex, in: s)
            s = re.stringByReplacingMatches(in: s, range: range, withTemplate: "")
        }
        if !city.isEmpty {
            s = s.replacingOccurrences(of: city, with: " ", options: .caseInsensitive)
        }
        s = s.replacingOccurrences(of: #"\b(?:blvd|boulevard|ave|avenue|st|street|rd|road|dr|drive|ln|lane|ct|court|cir|circle|way|pl|place|pkwy|parkway|ter|terrace|hwy|highway)\b"#, with: " ", options: [.regularExpression, .caseInsensitive])
        s = s.replacingOccurrences(of: #"[^\w\s]"#, with: " ", options: .regularExpression)
        s = s.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        return s.split(separator: " ").first.map { String($0).uppercased() } ?? ""
    }

    private static func normalizeOwnerName(_ raw: String) -> String? {
        var s = raw.split(whereSeparator: \.isWhitespace).joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard !s.isEmpty else { return nil }
        s = s.replacingOccurrences(of: #"\s*\((?:LIFE|LE|TRUST|TR|ET\s*AL|ETUX|ETVIR|H/?W|W/?H)\)\s*"#, with: " ", options: [.regularExpression, .caseInsensitive])
        if s.contains(",") {
            let parts = s.split(separator: ",", maxSplits: 1).map(String.init)
            if parts.count == 2 {
                s = "\(parts[1].trimmingCharacters(in: .whitespaces)) \(parts[0].trimmingCharacters(in: .whitespaces))"
            }
        }
        let upperTokens: Set<String> = ["LLC", "LP", "INC", "CO", "NA", "II", "III", "IV"]
        s = s.split(separator: " ").map { tok -> String in
            let u = tok.uppercased()
            if upperTokens.contains(u) { return u }
            return tok.prefix(1).uppercased() + tok.dropFirst().lowercased()
        }.joined(separator: " ")
        return s.count >= 3 ? s : nil
    }

    private static func firstMatch(_ pattern: String, in text: String) -> String? {
        guard let re = try? NSRegularExpression(pattern: pattern, options: [.caseInsensitive]) else { return nil }
        let range = NSRange(text.startIndex..<text.endIndex, in: text)
        guard let m = re.firstMatch(in: text, range: range), m.numberOfRanges > 1,
              let r = Range(m.range(at: 1), in: text) else { return nil }
        return String(text[r])
    }

    private static func formatSaleDate(_ sd: String) -> String {
        let t = sd.trimmingCharacters(in: .whitespaces)
        if t.count == 8, t.allSatisfy(\.isNumber) {
            let i = t.index(t.startIndex, offsetBy: 2)
            let j = t.index(t.startIndex, offsetBy: 4)
            return "\(t[..<i])/\(t[i..<j])/\(t[j...])"
        }
        return t
    }

    private static func duckQuery(_ raw: String) -> String {
        (raw + " county assessor property search").addingPercentEncoding(withAllowedCharacters: .urlQueryAllowed) ?? raw
    }
}
