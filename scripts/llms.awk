# Read the shdoc comments of dybatpho's sources and print one tab-separated
# record per module and per public function, for `scripts/docs.sh` to turn into
# `llms.txt`, `llms-full.txt` and the skill's module reference:
#
#   M <TAB> module <TAB> @brief
#   F <TAB> module <TAB> signature <TAB> first sentence of @description
#
# A public function is a `function dybatpho::*` whose comment block carries no
# `@internal`. Its signature is built from the `@arg` types, `[type]` for an
# optional one (`type?`, or a description starting `[default:`), `...` for
# `$@`, and a leading `[options]` when the block lists any `@option`.

function reset_block() {
	desc = ""
	tag = ""
	desc_done = 0
	internal = 0
	options = 0
	nargs = 0
}

# The first sentence of a paragraph: up to the first `.`, `!` or `?` that ends a
# word, outside inline code, and not the dot of `e.g.`, `i.e.` or `etc.`.
function first_sentence(s, i, c, ticks, before) {
	ticks = 0
	for (i = 1; i <= length(s); i++) {
		c = substr(s, i, 1)
		if (c == "`") {
			ticks++
			continue
		}
		if (ticks % 2 || (c != "." && c != "!" && c != "?")) continue
		if (i < length(s) && substr(s, i + 1, 1) != " ") continue
		before = substr(s, 1, i)
		if (before ~ /(^|[ (])(e\.g|i\.e|etc|vs)\.$/) continue
		return before
	}
	return s
}

function trim(s) {
	sub(/^[[:space:]]+/, "", s)
	sub(/[[:space:]]+$/, "", s)
	return s
}

FNR == 1 {
	module = FILENAME
	sub(/.*\//, "", module)
	sub(/\.sh$/, "", module)
	brief_seen = 0
	reset_block()
}

/^#/ {
	line = $0
	# The `#####` fences around a block end the tag they follow.
	if (line ~ /^##+[[:space:]]*$/) {
		tag = ""
		next
	}
	sub(/^#[[:space:]]?/, "", line)
	if (match(line, /^[[:space:]]*@[a-z]+/)) {
		tag = trim(substr(line, 1, RLENGTH))
		text = trim(substr(line, RLENGTH + 1))
		if (tag == "@brief" && !brief_seen) {
			print "M\t" module "\t" text
			brief_seen = 1
		} else if (tag == "@description") {
			desc = text
			desc_done = 0
		} else if (tag == "@internal") {
			internal = 1
		} else if (tag == "@option") {
			options = 1
		} else if (tag == "@arg") {
			split(text, parts, /[[:space:]]+/)
			type = parts[2]
			rest = text
			sub(/^[^[:space:]]+[[:space:]]+[^[:space:]]+[[:space:]]*/, "", rest)
			optional = (type ~ /\?$/ || rest ~ /^\[default:/)
			sub(/\?$/, "", type)
			arg = (parts[1] == "$@" ? type "..." : type)
			args[++nargs] = (optional ? "[" arg "]" : "<" arg ">")
		}
		next
	}
	if (tag != "@description" || desc_done) next
	# A blank comment line ends the first paragraph of the description.
	if (trim(line) == "") {
		if (desc != "") desc_done = 1
		next
	}
	desc = (desc == "" ? trim(line) : desc " " trim(line))
	next
}

/^function dybatpho::[A-Za-z0-9_:]+/ && !internal && desc != "" {
	name = $2
	sig = name
	if (options) sig = sig " [options]"
	for (i = 1; i <= nargs; i++) sig = sig " " args[i]
	gsub(/[[:space:]]+/, " ", desc)
	print "F\t" module "\t" sig "\t" first_sentence(desc)
}

{ reset_block() }
