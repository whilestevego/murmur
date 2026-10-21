import Foundation

// MARK: - Measures and addresses

/// Reads measurements aloud, with their units in words.
func measures(_ text: String) -> String {
  let longestFirst = units.keys.sorted { $0.count > $1.count }
  let keys = longestFirst.map(NSRegularExpression.escapedPattern(for:)).joined(separator: "|")
  let glued = gluedUnits.keys.joined(separator: "|")
  var t = text
  // For example, "2°C" becomes "2 degrees Celsius".
  t = replace(t, #"(\d+(?:\.\d+)?)\h?[°º]\h?([CF])?\b"#) { g in
    let deg = g[1] == "1" ? "degree" : "degrees"
    return "\(g[1]) \(deg)" + (g[2].isEmpty ? "" : g[2] == "C" ? " Celsius" : " Fahrenheit")
  }
  // For example, "5 m2" becomes "5 square meters", and "41459 km³" becomes "41459 cubic kilometers".
  t = replace(t, #"(\d+(?:\.\d+)?)\h?(km|cm|mm|m|ft)(2|²|3|³)(?!\w)"#) { g in
    let names = ["km": "kilometers", "cm": "centimeters", "mm": "millimeters", "m": "meters", "ft": "feet"]
    guard let name = names[g[2]] else { return nil }
    return "\(g[1]) \("2²".contains(g[3]) ? "square" : "cubic") \(name)"
  }
  // A unit after a slash is read with "per". For example, "60 km/h" becomes "60 km per hour".
  t = replace(t, "(?<=[\\w])\\h?/\\h?(\(keys)|\(glued))(?![\\w/])") { g in
    (units[g[1]] ?? gluedUnits[g[1]]).map { " per \($0.0)" }
  }
  // For example, "200ms" becomes "200 milliseconds", and "100 million kg" becomes "100 million kilograms".
  t = replace(
    t,
    "(?<![\\w.])(\\d+(?:\\.\\d+)?)((?:\\h(?:thousand|million|billion|trillion))?)(?:\\h?(\(keys))|(\(glued)))(?![\\w/])"
  ) { g in
    guard let unit = g[3].isEmpty ? gluedUnits[g[4]] : units[g[3]] else { return nil }
    return "\(g[1])\(g[2]) \(g[1] == "1" && g[2].isEmpty ? unit.0 : unit.1)"
  }
  t = replace(t, "\\b(half|halves|quarters?|thirds?)\\h+(\(keys))(?![\\w/])") { g in
    units[g[2]].map { "\(g[1]) \($0.1)" }
  }
  return t
}

let units: [String: (String, String)] = [
  "ms": ("millisecond", "milliseconds"), "µs": ("microsecond", "microseconds"), "ns": ("nanosecond", "nanoseconds"),
  "sec": ("second", "seconds"), "secs": ("second", "seconds"), "min": ("minute", "minutes"),
  "mins": ("minute", "minutes"),
  "hr": ("hour", "hours"), "hrs": ("hour", "hours"),
  "KB": ("kilobyte", "kilobytes"), "kB": ("kilobyte", "kilobytes"), "MB": ("megabyte", "megabytes"),
  "GB": ("gigabyte", "gigabytes"), "TB": ("terabyte", "terabytes"),
  "kbps": ("kilobit per second", "kilobits per second"), "Kbps": ("kilobit per second", "kilobits per second"),
  "mbps": ("megabit per second", "megabits per second"), "Mbps": ("megabit per second", "megabits per second"),
  "gbps": ("gigabit per second", "gigabits per second"), "Gbps": ("gigabit per second", "gigabits per second"),
  "px": ("pixel", "pixels"), "pt": ("point", "points"), "fps": ("frame per second", "frames per second"),
  "Hz": ("hertz", "hertz"), "kHz": ("kilohertz", "kilohertz"), "MHz": ("megahertz", "megahertz"),
  "GHz": ("gigahertz", "gigahertz"),
  "kg": ("kilogram", "kilograms"), "KG": ("kilogram", "kilograms"), "mg": ("milligram", "milligrams"),
  "lb": ("pound", "pounds"), "lbs": ("pound", "pounds"), "oz": ("ounce", "ounces"),
  "km": ("kilometer", "kilometers"), "cm": ("centimeter", "centimeters"), "mm": ("millimeter", "millimeters"),
  "ft": ("foot", "feet"), "mph": ("mile per hour", "miles per hour"),
  "kph": ("kilometer per hour", "kilometers per hour"),
]
/// Units that are read as units only when they follow a number directly, as in "5s" or "200g".
///
/// With a space before them, these letters are more often words than units.
let gluedUnits: [String: (String, String)] = [
  "s": ("second", "seconds"), "m": ("minute", "minutes"), "h": ("hour", "hours"), "g": ("gram", "grams"),
]

/// Reads street addresses aloud.
func addresses(_ text: String) -> String {
  let street = [
    "St": "Street", "Ave": "Avenue", "Rd": "Road", "Ct": "Court", "Blvd": "Boulevard", "Dr": "Drive", "Ln": "Lane",
    "Expy": "Expressway", "Hwy": "Highway", "Pkwy": "Parkway", "Pl": "Place",
  ]
  let way = ["N": "North", "S": "South", "E": "East", "W": "West"]
  // For example, "1428 Elm St" becomes "14 28 Elm Street", and "708 N 1st St" becomes "7 0 8 North 1st Street".
  var t = replace(
    text,
    #"\b(\d{1,5})\h+(?:([NSEW])\.?\h+)?((?:(?:[A-Z][a-z]+|\d+(?:st|nd|rd|th))\h+){1,3})(?i:(st|ave|rd|ct|blvd|dr|ln|expy|hwy|pkwy|pl))\b"#
  ) { g in
    guard let kind = street.first(where: { $0.key.lowercased() == g[4].lowercased() })?.value else { return nil }
    return "\(houseNumber(g[1])) \(way[g[2]].map { $0 + " " } ?? "")\(g[3])\(kind)"
  }
  // A state code after a street name is read as the state's name, and the ZIP code is read digit by digit. For example,
  // "Street, Santa Clara, CA 95051" becomes "Street, Santa Clara, California 9 5 0 5 1".
  t = replace(
    t,
    #"((?:Street|Avenue|Road|Court|Boulevard|Drive|Lane|Expressway|Highway|Parkway|Place)(?:,\h+[A-Z][a-z]+(?:\h[A-Z][a-z]+)*)?),\h+([A-Z]{2})\b(,?\h+\d{5})?"#
  ) { g in
    guard let state = states[g[2]] else { return nil }
    return "\(g[1]), \(state)"
      + (g[3].isEmpty ? "" : (g[3].hasPrefix(",") ? "," : "") + " " + spaced(g[3].filter(\.isNumber)))
  }
  return t
}

/// Returns a house number as it's spoken.
///
/// For example, "1428" becomes "14 28", "123" becomes "1 23", and "708" becomes "7 0 8".
func houseNumber(_ n: String) -> String {
  switch n.count {
  case 3: return n.dropFirst().hasPrefix("0") ? spaced(n) : "\(n.prefix(1)) \(n.suffix(2))"
  case 4: return n.suffix(2).hasPrefix("0") ? n : "\(n.prefix(2)) \(n.suffix(2))"
  default: return n
  }
}

private let states = [
  "AL": "Alabama", "AK": "Alaska", "AZ": "Arizona", "AR": "Arkansas", "CA": "California", "CO": "Colorado",
  "CT": "Connecticut", "DE": "Delaware", "FL": "Florida", "GA": "Georgia", "HI": "Hawaii", "ID": "Idaho",
  "IL": "Illinois", "IN": "Indiana", "IA": "Iowa", "KS": "Kansas", "KY": "Kentucky", "LA": "Louisiana", "ME": "Maine",
  "MD": "Maryland", "MA": "Massachusetts", "MI": "Michigan", "MN": "Minnesota", "MS": "Mississippi", "MO": "Missouri",
  "MT": "Montana", "NE": "Nebraska", "NV": "Nevada", "NH": "New Hampshire", "NJ": "New Jersey", "NM": "New Mexico",
  "NY": "New York", "NC": "North Carolina", "ND": "North Dakota", "OH": "Ohio", "OK": "Oklahoma", "OR": "Oregon",
  "PA": "Pennsylvania", "RI": "Rhode Island", "SC": "South Carolina", "SD": "South Dakota", "TN": "Tennessee",
  "TX": "Texas", "UT": "Utah", "VT": "Vermont", "VA": "Virginia", "WA": "Washington", "WV": "West Virginia",
  "WI": "Wisconsin", "WY": "Wyoming", "DC": "D C",
]
