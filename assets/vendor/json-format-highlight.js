// Adapted from json-format-highlight (MIT): https://github.com/luyilin/json-format-highlight
const DEFAULT_COLORS = {
  keyColor: "red",
  numberColor: "green",
  stringColor: "blue",
  trueColor: "#00ccff",
  falseColor: "#ff8080",
  nullColor: "magenta"
}

function formatJson(data, options) {
  const json = JSON.stringify(data, null, 2)
    .replace(/&/g, "&amp;")
    .replace(/</g, "&lt;")
    .replace(/>/g, "&gt;")

  return json.replace(
    /("(.*?)")(:)?|(\b)(true|false|null)(\b)|(\b)(\d+)(\b)/g,
    (match, quotedValue, _quotedInner, colon, _boolWordBoundaryStart, boolValue, _boolWordBoundaryEnd, _numWordBoundaryStart, numberValue) => {
      const keyColorToken = colon ? "keyColor" : "stringColor"

      const valueColorToken =
        boolValue
          ? boolValue === "true"
            ? "trueColor"
            : boolValue === "false"
              ? "falseColor"
              : "nullColor"
          : numberValue
            ? "numberColor"
            : "stringColor"

      const quotedFragment =
        quotedValue ? `<span style="color:${options[keyColorToken]};">${quotedValue}</span>` : ""

      const coloredValueFragment = `<span style="color:${options[valueColorToken]};">${match}</span>`
      return `${quotedFragment}${quotedValue ? coloredValueFragment.replace(quotedValue, "") : coloredValueFragment}`
    }
  )
}

export default function jsonFormatHighlight(data, customOptions = {}) {
  const options = {...DEFAULT_COLORS, ...customOptions}

  if (typeof data === "object") {
    return formatJson(data, options)
  }

  let parsed

  try {
    parsed = JSON.parse(data)
  } catch (_error) {
    return undefined
  }

  return formatJson(parsed, options)
}
