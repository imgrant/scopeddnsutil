import Foundation
import SystemConfiguration

struct CIDR {
    let network: [UInt8]  // IPv4 address octets
    let prefix: Int
    
    init?(_ cidrString: String) {
        let parts = cidrString.split(separator: "/")
        guard parts.count == 2,
              let prefix = Int(parts[1]),
              prefix >= 0 && prefix <= 32 else {
            return nil
        }
        
        let ipParts = parts[0].split(separator: ".")
        guard ipParts.count == 4,
              let octet1 = UInt8(ipParts[0]),
              let octet2 = UInt8(ipParts[1]),
              let octet3 = UInt8(ipParts[2]),
              let octet4 = UInt8(ipParts[3]) else {
            return nil
        }
        
        self.network = [octet1, octet2, octet3, octet4]
        self.prefix = prefix
    }
    
    func toReverseDomains() -> [String] {
        // Calculate how many octets are fully matched and which octet is partial
        let fullOctets = prefix / 8  // How many complete octets are matched
        let partialBits = prefix % 8  // How many bits in the next octet
        
        // If we have a partial octet, calculate the range for that octet
        if partialBits > 0 {
            let octetIndex = fullOctets
            if (octetIndex >= network.count) {
                return []  // Invalid prefix for this address
            }
            
            // Calculate the start of the range using the mask
            let mask = UInt8(0xFF & (0xFF << (8 - partialBits)))
            let baseOctet = network[octetIndex] & mask
            let rangeSize = 1 << (8 - partialBits)
            
            // Build the prefix of the reverse domain
            let prefix = (0..<octetIndex).reversed().map { String(network[$0]) }.joined(separator: ".")
            let suffix = prefix.isEmpty ? "in-addr.arpa" : ".\(prefix).in-addr.arpa"
            
            // Generate all addresses in the range
            return (0..<rangeSize).map { offset in
                let octetValue = Int(baseOctet) + offset
                return "\(octetValue)\(suffix)"
            }
        } else {
            // We match exactly on octet boundaries (e.g., /8, /16, /24)
            if (fullOctets > network.count) {
                return []  // Invalid prefix for this address
            }
            let reversedOctets = (0..<fullOctets).reversed().map { String(network[$0]) }
            return [reversedOctets.joined(separator: ".") + ".in-addr.arpa"]
        }
    }
}

struct DomainConfig {
    let forward: [String]
    let cidrs: [CIDR]
    
    var reverse: [String] {
        cidrs.flatMap { $0.toReverseDomains() }
    }
    
    var all: [String] { forward + reverse }
    
    static func fromCommandLine(domains: String, cidrs: String?) -> DomainConfig {
        let forward = domains
            .split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .map { $0.hasPrefix(".") ? String($0.dropFirst()) : $0 }
        
        let customCIDRs: [CIDR]
        if let cidrString = cidrs {
            customCIDRs = cidrString
                .split(separator: ",")
                .map { $0.trimmingCharacters(in: .whitespaces) }
                .compactMap { CIDR($0) }
        } else {
            customCIDRs = []  // Empty array if no CIDRs specified
        }
        
        return DomainConfig(forward: forward, cidrs: customCIDRs)
    }
}

// Function to format domains for output (convert reverse zones to CIDR notation)
func formatDomainsForOutput(_ domains: [String]) -> String {
    // Split into forward and reverse domains
    let (forward, reverse) = domains.reduce(into: ([String](), [String]())) { result, domain in
        if domain.hasSuffix(".in-addr.arpa") {
            result.1.append(domain)
        } else {
            result.0.append(domain)
        }
    }
    
    // Group reverse domains by their common prefix
    var reverseGroups: [String: Set<Int>] = [:]
    for domain in reverse {
        let parts = domain.replacingOccurrences(of: ".in-addr.arpa", with: "")
            .split(separator: ".")
            .map { String($0) }
        
        if parts.count == 1 {
            // Handle /8 networks (e.g., "10.in-addr.arpa")
            reverseGroups[""] = reverseGroups["", default: []].union([Int(parts[0])!])
        } else {
            // Handle other networks
            let octet = Int(parts[0])!
            let prefix = parts.dropFirst().reversed()
            reverseGroups[prefix.joined(separator: ".")] = reverseGroups[prefix.joined(separator: "."), default: []].union([octet])
        }
    }
    
    // Convert to CIDR notation
    let cidrs = reverseGroups.compactMap { prefix, octets -> String? in
        let sortedOctets = Array(octets).sorted()
        let prefixParts = prefix.isEmpty ? [] : prefix.split(separator: ".").map { String($0) }
        
        if prefix.isEmpty && sortedOctets.count == 1 {
            // Single /8 network
            return "\(sortedOctets[0]).0.0.0/8"
        }
        
        // Handle other networks as before
        if sortedOctets.count > 1 &&
           sortedOctets.last! - sortedOctets.first! + 1 == sortedOctets.count {
            let rangeBits = Int(log2(Double(sortedOctets.count)))
            let prefixLength = 8 * (prefixParts.count + 1) - rangeBits
            
            var ipParts = prefixParts
            ipParts.append(String(sortedOctets[0]))
            while ipParts.count < 4 {
                ipParts.append("0")
            }
            return "\(ipParts.joined(separator: "."))/\(prefixLength)"
        } else {
            return sortedOctets.map { octet in
                var ipParts = prefixParts
                ipParts.append(String(octet))
                while ipParts.count < 4 {
                    ipParts.append("0")
                }
                return "\(ipParts.joined(separator: "."))/\((prefixParts.count + 1) * 8)"
            }.joined(separator: ", ")
        }
    }
    
    var parts: [String] = []
    if !forward.isEmpty {
        parts.append(forward.joined(separator: ", "))
    }
    if !cidrs.isEmpty {
        parts.append(cidrs.joined(separator: ", "))
    }
    
    return parts.joined(separator: ", ")
}

enum Verbosity: Comparable {
    case quiet
    case normal
    case verbose

    private var sortOrder: Int {
        switch self {
        case .quiet: return 0
        case .normal: return 1
        case .verbose: return 2
        }
    }
    
    static func < (lhs: Verbosity, rhs: Verbosity) -> Bool {
        return lhs.sortOrder < rhs.sortOrder
    }
}

func printMessage(_ message: String, verbosity: Verbosity, minimumLevel: Verbosity = .normal) {
    guard verbosity != .quiet && verbosity >= minimumLevel else { return }
    print(message)
}

// Function to find or manage the service key
func findOrUpdateServiceDNS(store: SCDynamicStore, domainConfig: DomainConfig?, nameservers: [String]?, remove: Bool) -> (key: CFString, existed: Bool, domains: [String]?, resolvers: [String]?)? {
    let servicePattern = "State:/Network/Service/[^/]+/DNS" as CFString
    if let services = SCDynamicStoreCopyKeyList(store, servicePattern) as? [String] {
        for serviceKey in services {
            if let config = SCDynamicStoreCopyValue(store, serviceKey as CFString) as? [String: Any],
               let existingDomains = config["SupplementalMatchDomains"] as? [String],
               let existingResolvers = config["ServerAddresses"] as? [String],
               let domains = domainConfig?.all,
               let resolvers = nameservers {
                
                let domainsMatch = !Set(existingDomains).isDisjoint(with: domains)
                let resolversMatch = !Set(existingResolvers).isDisjoint(with: resolvers)
                
                if domainsMatch && resolversMatch {
                    return (serviceKey as CFString, true, existingDomains, existingResolvers)
                }
            }
        }
    }
    
    if !remove {
        let serviceGUID = UUID().uuidString
        let key = "State:/Network/Service/\(serviceGUID)/DNS" as CFString
        return (key, false, nil, nil)
    }
    
    return nil
}

// Function to update DNS configuration
func updateServiceDNS(addDomains: Bool, domainConfig: DomainConfig, nameservers: [String]?, verbosity: Verbosity) -> Bool {
    guard let store = SCDynamicStoreCreate(nil, "DNSManager" as CFString, nil, nil) else {
        printMessage("Failed to create SCDynamicStore", verbosity: verbosity)
        return false
    }
    
    let isRemove = !addDomains
    let effectiveNameservers = nameservers ?? []
    
    guard let result = findOrUpdateServiceDNS(store: store, domainConfig: domainConfig, nameservers: effectiveNameservers, remove: isRemove) else {
        if isRemove {
            printMessage("No scoped DNS entries found matching domains \(formatDomainsForOutput(domainConfig.all)) and resolvers \(effectiveNameservers.joined(separator: ", "))", verbosity: verbosity)
            return false  // Changed from true to false
        }
        return false
    }
    
    let key = result.key
    let existingDomains = result.domains
    let existingResolvers = result.resolvers
    
    if isRemove {
        guard SCDynamicStoreRemoveValue(store, key),
              SCDynamicStoreNotifyValue(store, key) else {
            let errorCode = SCError()
            printMessage("Failed to remove service key. Error code: \(errorCode) (\(SCErrorString(errorCode)))", verbosity: verbosity)
            return false
        }
        if let domainsToRemove = existingDomains, let resolversToRemove = existingResolvers {
            let detailedMessage = "Removed scoped DNS entry for \(formatDomainsForOutput(domainsToRemove)) with resolver(s) \(resolversToRemove.joined(separator: ", "))"
            let simpleMessage = "Removed scoped DNS entry"
            printMessage(verbosity == .verbose ? detailedMessage : simpleMessage, verbosity: verbosity)
        }
    } else {
        let dnsConfig: [String: Any] = [
            "SupplementalMatchDomains": domainConfig.all,
            "ServerAddresses": effectiveNameservers,
            "SearchDomains": domainConfig.forward
        ]
        let newConfig = dnsConfig as CFDictionary
        
        guard SCDynamicStoreSetValue(store, key, newConfig),
              SCDynamicStoreNotifyValue(store, key) else {
            let errorCode = SCError()
            printMessage("Failed to set or notify DNS config. Error code: \(errorCode) (\(SCErrorString(errorCode)))", verbosity: verbosity)
            return false
        }
        let detailedMessage = "Added scoped DNS entry for \(formatDomainsForOutput(domainConfig.all)) with resolver(s) \(effectiveNameservers.joined(separator: ", "))"
        let simpleMessage = "Added scoped DNS entry"
        printMessage(verbosity == .verbose ? detailedMessage : simpleMessage, verbosity: verbosity)
    }
    
    return true
}

func printUsage() {
    let usage = """
    Usage: \(CommandLine.arguments[0]) [add|remove] [options]
    
    Required Options:
      -r, --resolvers <ip>[,<ip>...]         IP address(es) of DNS resolvers
      -d, --domains <domain>[,<domain>...]   Domain(s) to scope these resolvers for
    
    Optional:
      -i, --cidrs <cidr>[,<cidr>...]   IP address ranges in CIDR notation to scope to these resolvers
      -v, --verbose                    Show detailed output
      -q, --quiet                      Suppress all output
      -h, --help                       Show this help message
    """
    print(usage)
}

// Main logic with argument parsing
if CommandLine.argc < 2 || CommandLine.arguments.contains("-h") || CommandLine.arguments.contains("--help") {
    printUsage()
    exit(CommandLine.argc < 2 ? 1 : 0)
}

let action = CommandLine.arguments[1]
var nameservers: String? = nil
var domains: String? = nil
var cidrs: String? = nil
var verbosity: Verbosity = .normal

let args = Array(CommandLine.arguments.dropFirst())
var i = 0
while i < args.count {
    defer { i += 1 }
    switch args[i] {
    case "-r", "--resolvers":
        guard i + 1 < args.count else {
            print("Missing IP address for resolvers option")
            exit(1)
        }
        nameservers = args[i + 1]
        i += 1
    case "-d", "--domains":
        guard i + 1 < args.count else {
            print("Missing domain list for domains option")
            exit(1)
        }
        domains = args[i + 1]
        i += 1
    case "-i", "--cidrs":
        guard i + 1 < args.count else {
            print("Missing CIDR list for reverse lookup zones")
            exit(1)
        }
        cidrs = args[i + 1]
        i += 1
    case "-v", "--verbose":
        verbosity = .verbose
    case "-q", "--quiet":
        verbosity = .quiet
    default:
        continue
    }
}

// Validate required parameters
if domains == nil {
    print("Error: --domains parameter is required")
    exit(1)
}

if nameservers == nil {
    print("Error: --resolvers parameter is required")
    exit(1)
}

let resolverList = nameservers!.split(separator: ",").map { String($0.trimmingCharacters(in: .whitespaces)) }
let domainConfig = DomainConfig.fromCommandLine(domains: domains!, cidrs: cidrs)

switch action.lowercased() {
case "add":
    if !updateServiceDNS(addDomains: true, domainConfig: domainConfig, nameservers: resolverList, verbosity: verbosity) {
        printMessage("Failed to add scoped DNS entry", verbosity: verbosity)
        exit(1)
    }
case "remove":
    if !updateServiceDNS(addDomains: false, domainConfig: domainConfig, nameservers: resolverList, verbosity: verbosity) {
        printMessage("Failed to remove scoped DNS entry", verbosity: verbosity)
        exit(1)
    }
default:
    printMessage("Invalid argument. Use 'add' or 'remove'.", verbosity: verbosity)
    exit(1)
}
