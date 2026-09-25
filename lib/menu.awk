# menu.awk - read teeup's menu definition and print one tab-separated
# id/field/value line per field, in file order.
#
# The grammar accepted here is deliberately narrower than JSON: the file is
# one object whose keys are dotted menu ids and whose values are objects whose
# values are one-line strings. The menu format is nothing more than that, and
# a parser that accepts only it fits in a hundred lines of awk instead of
# adding a dependency on jq -- macOS before 15 ships no jq, and the harness
# hides Homebrew's.
#
# Beyond the JSON grammar, two teeup-specific rules are enforced here rather
# than left to the shell that consumes the output: an id must match
# ^[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*$, and a field name must be one
# of label, icon, action, when or title. Both matter because the menu id
# reaches the shell unquoted in more than one place downstream (e.g. `for id
# in $ids`): an id of "*" would glob-expand to every file in the working
# directory, one containing a space would split into two words, and one
# containing a backslash would be rewritten by awk's own -v assignment. A
# duplicate id or a duplicate field within one file is refused for the same
# reason JSON leaves it undefined: silently keeping the last one (or merging
# both) hides a copy-paste mistake instead of reporting it.
#
# Errors go to stderr through `cat 1>&2` rather than "/dev/stderr", which not
# every awk implementation opens, and exit 1.

function fail(msg) {
  print "menu: " msg " (" FILENAME ", byte " i ")" | "cat 1>&2"
  close("cat 1>&2")
  exit 1
}

function skipws(   c) {
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == " " || c == "\t" || c == "\n" || c == "\r") { i++ } else { return }
  }
}

function at() { return substr(s, i, 1) }

function readstring(   out, c, e) {
  if (at() != "\"") fail("expected a double-quoted string")
  i++
  out = ""
  while (i <= n) {
    c = substr(s, i, 1)
    if (c == "\"") { i++; return out }
    # A tab or a newline inside a value would split the output line this
    # parser exists to produce, so both are refused rather than smuggled
    # through. The escapes \n and \t are refused for the same reason.
    if (c == "\n" || c == "\t" || c == "\r") fail("a value is one line of text; use no raw newlines or tabs")
    if (c == "\\") {
      i++
      e = substr(s, i, 1)
      if (e == "\"" || e == "\\" || e == "/") { out = out e }
      else fail("unsupported escape \\" e "; only \\\" \\\\ and \\/ are understood")
      i++
      continue
    }
    out = out c
    i++
  }
  fail("unterminated string")
}

function valid_id(x) { return (x ~ /^[a-z0-9][a-z0-9_-]*(\.[a-z0-9][a-z0-9_-]*)*$/) }

function valid_field(x) { return (x ~ /^(label|icon|action|when|title)$/) }

# The whole file is accumulated and then scanned, because the grammar is not
# line-oriented and awk's record splitting would fight it.
{ s = s $0 "\n" }

END {
  n = length(s)
  i = 1
  skipws()
  if (at() != "{") fail("the file must be one JSON object")
  i++
  skipws()
  if (at() == "}") { i++ } else {
    for (;;) {
      skipws(); id = readstring(); skipws()
      if (!valid_id(id)) fail("invalid id '" id "'; ids are lowercase letters, digits, '_' or '-' in dot-separated segments")
      if (id in seenid) fail("duplicate id '" id "'")
      seenid[id] = 1
      if (at() != ":") fail("expected ':' after the id " id)
      i++
      skipws()
      if (at() != "{") fail("the entry " id " must be an object")
      i++
      skipws()
      if (at() == "}") { i++ } else {
        for (;;) {
          skipws(); key = readstring(); skipws()
          if (!valid_field(key)) fail("unknown field '" id "." key "'; only label icon action when title are recognised")
          if ((id, key) in seenfield) fail("duplicate field '" id "." key "'")
          seenfield[id, key] = 1
          if (at() != ":") fail("expected ':' after " id "." key)
          i++
          skipws()
          if (at() != "\"") fail("the field " id "." key " must be a string")
          val = readstring()
          printf "%s\t%s\t%s\n", id, key, val
          skipws()
          if (at() == ",") { i++; continue }
          if (at() == "}") { i++; break }
          fail("expected ',' or '}' inside " id)
        }
      }
      skipws()
      if (at() == ",") { i++; skipws(); if (at() == "}") { i++; break }; continue }
      if (at() == "}") { i++; break }
      fail("expected ',' or '}' after " id)
    }
  }
  skipws()
  if (i <= n) fail("trailing content after the object")
}
