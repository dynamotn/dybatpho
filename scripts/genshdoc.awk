#!/usr/bin/env gawk -f

BEGIN {
	module_file = ""
	module_brief = ""
	header_done = 0
	header_count = 0
	pending_count = 0
	fn_count = 0
	function_declaration = ""
	pending_section = ""
}

{
	if (! header_done) {
		if ($0 ~ /^#!/ || $0 ~ /^[[:space:]]*#/ || $0 ~ /^[[:space:]]*$/) {
			header_lines[++header_count] = $0
			next
		}
		header_done = 1
		parse_header()
	}
	if ($0 ~ /^[[:space:]]*#/) {
		pending_lines[++pending_count] = $0
		next
	}
	if (match($0, /^[[:blank:]]*(function[[:blank:]]+)?([a-zA-Z0-9_\-:\.]+)[[:blank:]]*(\([[:blank:]]*\))?[[:blank:]]*\{/, m)) {
		parse_function_block(m[2])
		pending_count = 0
		delete pending_lines
		function_declaration = ""
		next
	}
	if (match($0, /^[[:blank:]]*(function[[:blank:]]+)?([a-zA-Z0-9_\-:\.]+)[[:blank:]]*(\([[:blank:]]*\))?[[:blank:]]*$/, m)) {
		function_declaration = $0
		next
	}
	if ($0 ~ /^[[:blank:]]*\{/ && function_declaration != "") {
		match(function_declaration, /^[[:blank:]]*(function[[:blank:]]+)?([a-zA-Z0-9_\-:\.]+)[[:blank:]]*(\([[:blank:]]*\))?[[:blank:]]*$/, m)
		parse_function_block(m[2])
		pending_count = 0
		delete pending_lines
		function_declaration = ""
		next
	}
	if ($0 ~ /^[[:blank:]]*$/ && function_declaration != "") {
		next
	}
	if ($0 !~ /^[[:space:]]*$/) {
		parse_module_block()
		pending_count = 0
		delete pending_lines
		function_declaration = ""
	}
}

END {
	if (! header_done) {
		parse_header()
	}
	render_module()
}

function append_item(kind, idx, value, key)
{
	key = kind SUBSEP idx SUBSEP counts[kind, idx]
	if (items[key] == "") {
		items[key] = value
	} else {
		items[key] = items[key] " " trim(value)
	}
}

function append_text(kind, idx, value, key)
{
	key = kind SUBSEP idx
	if (value == "__BLANK__") {
		if (texts[key] == "") {
			return
		}
		if (texts[key] !~ /\n\n$/) {
			texts[key] = texts[key] "\n\n"
		}
		return
	}
	if (texts[key] == "") {
		texts[key] = value
	} else {
		texts[key] = texts[key] "\n" value
	}
}

function clean_comment(line)
{
	sub(/^[[:space:]]*#[[:space:]]?/, "", line)
	sub(/[[:space:]]+$/, "", line)
	return line
}

function dedent(text, n, arr, i, line, indent, min_indent, out)
{
	n = split(text, arr, /\n/)
	min_indent = -1
	for (i = 1; i <= n; i++) {
		line = arr[i]
		if (trim(line) == "") {
			continue
		}
		match(line, /^[[:space:]]*/)
		indent = RLENGTH
		if (min_indent < 0 || indent < min_indent) {
			min_indent = indent
		}
	}
	if (min_indent < 0) {
		return text
	}
	out = ""
	for (i = 1; i <= n; i++) {
		line = arr[i]
		if (min_indent > 0) {
			line = substr(line, min_indent + 1)
		}
		out = out (i == 1 ? "" : "\n") line
	}
	return out
}

function is_separator(line, stripped)
{
	stripped = trim(line)
	return (stripped != "" && stripped ~ /^#+$/)
}

function warn(message)
{
	printf("warning: %s\n", message) > "/dev/stderr"
}

function normalize_ref(text, out)
{
	out = trim(text)
	gsub(/^`+|`+$/, "", out)
	gsub(/^\[[^]]+\]\(/, "", out)
	gsub(/\)$/, "", out)
	return out
}

function github_anchor(text, out)
{
	out = normalize_ref(text)
	gsub(/[`*]/, "", out)
	out = tolower(out)
	gsub(/[^[:alnum:] _-]/, "", out)
	gsub(/[[:space:]]+/, "-", out)
	gsub(/-+/, "-", out)
	gsub(/^-+|-+$/, "", out)
	return out
}

function doc_link_target(text, out)
{
	out = normalize_ref(text)
	if (out ~ /^doc\//) {
		sub(/^doc\//, "", out)
	} else if (out ~ /^(example|src|scripts)\//) {
		out = "../" out
	}
	return out
}

function render_link(text, url)
{
	text = normalize_ref(text)
	if (text ~ /^(doc|example|src|scripts)\//) {
		url = doc_link_target(text)
		return "[" text "](" url ")"
	}
	if (text ~ /^\.{0,2}\//) {
		return "[" text "](" text ")"
	}
	if (text ~ /\[[^]]+\]\([^)]+\)/) {
		return text
	}
	url = github_anchor(text)
	return "[" text "](#" url ")"
}

function render_source_link()
{
	return "[src/" module_file "](../src/" module_file ")"
}

function render_function_link(name)
{
	return "[`" name "`](#" github_anchor(name) ")"
}

function append_nav_link(nav, label, anchor)
{
	if (anchor == "") {
		return nav
	}
	return nav (nav == "" ? "" : " · ") "[" label "](#" github_anchor(anchor) ")"
}

function print_option_item(text, m, term, desc)
{
	if (match(text, /^(((-[[:alnum:]]([[:blank:]]*<[^>]+>)?|--[[:alnum:]][[:alnum:]-]*((=|[[:blank:]]+)<[^>]+>)?)([[:blank:]]*\|?[[:blank:]]+))+)([^[:blank:]|<-].*)?$/, m)) {
		term = trim(m[1])
		desc = trim(m[8])
		gsub(/[[:blank:]]+\|[[:blank:]]+/, " | ", term)
		gsub(/</, "\\<", term)
		gsub(/>/, "\\>", term)
		if (desc != "") {
			print "- **" term "**: " desc
		} else {
			print "- **" term "**"
		}
	} else {
		print "- " text
	}
}

function scan_pending_meta(i, line, rest)
{
	pending_internal = 0
	for (i = 1; i <= pending_count; i++) {
		line = pending_lines[i]
		if (line !~ /^[[:space:]]*#/) {
			continue
		}
		line = clean_comment(line)
		if (line ~ /^@internal([[:space:]]+|$)/) {
			pending_internal = 1
		} else if (line ~ /^@section[[:space:]]+/) {
			rest = trim(substr(line, 9))
			if (rest != "") {
				pending_section = rest
			}
		}
	}
}

function parse_module_block(i, line, mode, rest)
{
	mode = ""
	for (i = 1; i <= pending_count; i++) {
		line = pending_lines[i]
		if (line !~ /^[[:space:]]*#/) {
			continue
		}
		line = clean_comment(line)
		if (is_separator(line) || line ~ /^shellcheck disable=/) {
			continue
		}
		if (trim(line) == "") {
			continue
		}
		if (line ~ /^@env([[:space:]]+|$)/) {
			rest = trim(substr(line, 5))
			if (rest != "") {
				push_item("module_env", 0, rest)
			}
			mode = "env"
			continue
		}
		if (line ~ /^@license([[:space:]]+|$)/) {
			rest = trim(substr(line, 9))
			if (rest != "") {
				push_item("module_license", 0, rest)
			}
			mode = "license"
			continue
		}
		if (line ~ /^@deprecated([[:space:]]+|$)/) {
			rest = trim(substr(line, 12))
			if (rest != "") {
				push_item("module_deprecated", 0, rest)
			}
			mode = "deprecated"
			continue
		}
		if (line ~ /^@see([[:space:]]+|$)/) {
			rest = trim(substr(line, 5))
			if (rest != "") {
				push_item("module_see", 0, rest)
			}
			mode = "see"
			continue
		}
		if (line ~ /^@tip([[:space:]]+|$)/) {
			rest = trim(substr(line, 5))
			if (rest != "") {
				push_item("module_tip", 0, rest)
			}
			mode = "tip"
			continue
		}
		if (mode == "env" && counts["module_env", 0] > 0) {
			append_item("module_env", 0, line)
		} else if (mode == "license" && counts["module_license", 0] > 0) {
			append_item("module_license", 0, line)
		} else if (mode == "deprecated" && counts["module_deprecated", 0] > 0) {
			append_item("module_deprecated", 0, line)
		} else if (mode == "see" && trim(line) ~ /^-[[:space:]]+/) {
			rest = trim(line)
			push_item("module_see", 0, trim(substr(rest, 3)))
		} else if (mode == "see" && counts["module_see", 0] > 0) {
			append_item("module_see", 0, line)
		} else if (mode == "tip" && counts["module_tip", 0] > 0) {
			append_item("module_tip", 0, line)
		}
	}
}

function parse_function_block(name, i, line, mode, key, rest, parts, argline)
{
	scan_pending_meta()
	if (pending_internal) {
		pending_section = ""
		return
	}
	fn_count++
	fn_name[fn_count] = name
	public_names[fn_count] = name
	fn_section[fn_count] = pending_section
	pending_section = ""
	mode = ""
	for (i = 1; i <= pending_count; i++) {
		line = pending_lines[i]
		if (line !~ /^[[:space:]]*#/) {
			continue
		}
		line = clean_comment(line)
		if (is_separator(line) || line ~ /^shellcheck disable=/) {
			continue
		}
		if (trim(line) == "") {
			if (mode == "description") {
				append_text("fn_desc", fn_count, "__BLANK__")
			} else if (mode == "example" && counts["fn_example", fn_count] > 0) {
				key = "fn_example" SUBSEP fn_count SUBSEP counts["fn_example", fn_count]
				items[key] = items[key] "\n"
			}
			continue
		}
		if (line ~ /^@/) {
			split(substr(line, 2), parts, /[[:space:]]+/)
			key = parts[1]
			rest = trim(substr(line, 2 + length(key)))
			if (key == "description") {
				if (rest != "") {
					append_text("fn_desc", fn_count, rest)
				}
				mode = "description"
			} else if (key == "example") {
				push_item("fn_example", fn_count, rest)
				mode = "example"
			} else if (key == "arg") {
				push_item("fn_arg", fn_count, rest)
				mode = "arg"
			} else if (key == "option") {
				push_item("fn_option", fn_count, rest)
				mode = "option"
			} else if (key == "env") {
				push_item("fn_env", fn_count, rest)
				mode = "env"
			} else if (key == "stdin") {
				push_item("fn_stdin", fn_count, rest)
				mode = "stdin"
			} else if (key == "stdout") {
				push_item("fn_stdout", fn_count, rest)
				mode = "stdout"
			} else if (key == "stderr") {
				push_item("fn_stderr", fn_count, rest)
				mode = "stderr"
			} else if (key == "exitcode") {
				push_item("fn_exitcode", fn_count, rest)
				mode = "exitcode"
			} else if (key == "set") {
				push_item("fn_set", fn_count, rest)
				mode = "set"
			} else if (key == "see") {
				push_item("fn_see", fn_count, rest)
				mode = "see"
			} else if (key == "tip") {
				push_item("fn_tip", fn_count, rest)
				mode = "tip"
			} else if (key == "deprecated") {
				push_item("fn_deprecated", fn_count, rest)
				mode = "deprecated"
			} else if (key == "note") {
				push_item("fn_note", fn_count, rest)
				mode = "note"
			} else if (key == "noargs") {
				fn_noargs[fn_count] = 1
				mode = ""
			} else {
				mode = ""
			}
			continue
		}
		if (mode == "description") {
			append_text("fn_desc", fn_count, line)
		} else if (mode == "example" && counts["fn_example", fn_count] > 0) {
			key = "fn_example" SUBSEP fn_count SUBSEP counts["fn_example", fn_count]
			if (items[key] == "") {
				items[key] = line
			} else {
				items[key] = items[key] "\n" line
			}
		} else if ((mode == "stdin" || mode == "stdout" || mode == "stderr") && counts["fn_" mode, fn_count] > 0) {
			key = "fn_" mode SUBSEP fn_count SUBSEP counts["fn_" mode, fn_count]
			if (items[key] == "") {
				items[key] = line
			} else {
				items[key] = items[key] "\n" line
			}
		} else if (mode == "env" && counts["fn_env", fn_count] > 0) {
			append_item("fn_env", fn_count, line)
		} else if (mode != "") {
			append_item("fn_" mode, fn_count, line)
		}
	}
}

function parse_header(i, line, mode, rest)
{
	mode = ""
	for (i = 1; i <= header_count; i++) {
		line = header_lines[i]
		if (line ~ /^#!/) {
			continue
		}
		if (line !~ /^[[:space:]]*#/) {
			continue
		}
		line = clean_comment(line)
		if (is_separator(line) || line ~ /^shellcheck disable=/) {
			continue
		}
		if (trim(line) == "") {
			if (mode == "description") {
				append_text("module_desc", 0, "__BLANK__")
			} else if (mode == "usage") {
				append_text("module_usage", 0, "__BLANK__")
			}
			continue
		}
		if (line ~ /^@file[[:space:]]+/) {
			module_file = trim(substr(line, 7))
			mode = ""
			continue
		}
		if (line ~ /^@brief[[:space:]]+/) {
			module_brief = trim(substr(line, 8))
			mode = ""
			continue
		}
		if (line ~ /^@(name|file)[[:space:]]+/) {
			module_file = trim(substr(line, index(line, " ") + 1))
			mode = ""
			continue
		}
		if (line ~ /^@description/) {
			rest = trim(substr(line, 13))
			if (rest != "") {
				append_text("module_desc", 0, rest)
			}
			mode = "description"
			continue
		}
		if (line ~ /^@usage([[:space:]]+|$)/) {
			rest = trim(substr(line, 7))
			if (rest != "") {
				append_text("module_usage", 0, rest)
			}
			mode = "usage"
			continue
		}
		if (line ~ /^@see([[:space:]]+|$)/) {
			rest = trim(substr(line, 5))
			if (rest != "") {
				push_item("module_see", 0, rest)
			}
			mode = "see"
			continue
		}
		if (line ~ /^@tip([[:space:]]+|$)/) {
			rest = trim(substr(line, 5))
			push_item("module_tip", 0, rest)
			mode = "tip"
			continue
		}
		if (line ~ /^@env([[:space:]]+|$)/) {
			rest = trim(substr(line, 5))
			if (rest != "") {
				push_item("module_env", 0, rest)
			}
			mode = "env"
			continue
		}
		if (line ~ /^@license([[:space:]]+|$)/) {
			rest = trim(substr(line, 9))
			if (rest != "") {
				push_item("module_license", 0, rest)
			}
			mode = "license"
			continue
		}
		if (line ~ /^@deprecated([[:space:]]+|$)/) {
			rest = trim(substr(line, 12))
			if (rest != "") {
				push_item("module_deprecated", 0, rest)
			}
			mode = "deprecated"
			continue
		}
		if (line ~ /^\*\*.*\((string|bool|number)\):/) {
			push_item("module_globals", 0, line)
			continue
		}
		if (mode == "description") {
			append_text("module_desc", 0, line)
		} else if (mode == "usage") {
			append_text("module_usage", 0, line)
		} else if (mode == "see" && trim(line) ~ /^-[[:space:]]+/) {
			rest = trim(line)
			push_item("module_see", 0, trim(substr(rest, 3)))
		} else if (mode == "see" && counts["module_see", 0] > 0) {
			append_item("module_see", 0, line)
		} else if (mode == "tip" && counts["module_tip", 0] > 0) {
			append_item("module_tip", 0, line)
		} else if (mode == "env" && counts["module_env", 0] > 0) {
			append_item("module_env", 0, line)
		} else if (mode == "license" && counts["module_license", 0] > 0) {
			append_item("module_license", 0, line)
		} else if (mode == "deprecated" && counts["module_deprecated", 0] > 0) {
			append_item("module_deprecated", 0, line)
		}
	}
}

function print_arg_item(text, m)
{
	if (match(text, /^(\$[^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
		print "- `" m[1] "` (" m[2] "): " m[3]
	} else {
		print "- " text
	}
}

function print_exit_item(text, m)
{
	if (match(text, /^([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
		print "- `" m[1] "`: " m[2]
	} else {
		print "- " text
	}
}

function md_escape(text)
{
	gsub(/\|/, "\\|", text)
	return text
}

function print_table_row(c1, c2, c3, has_three)
{
	c1 = md_escape(c1)
	c2 = md_escape(c2)
	c3 = md_escape(c3)
	if (has_three) {
		print "| " c1 " | " c2 " | " c3 " |"
	} else {
		print "| " c1 " | " c2 " |"
	}
}

function print_arg_table(kind, idx, i, key, text, m)
{
	print "| Name | Type | Description |"
	print "| --- | --- | --- |"
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (match(text, /^(\$[^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
			print_table_row("`" m[1] "`", m[2], m[3], 1)
		} else {
			print_table_row(text, "", "", 1)
		}
	}
}

function print_exit_table(kind, idx, i, key, text, m)
{
	print "| Code | Meaning |"
	print "| --- | --- |"
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (match(text, /^([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
			print_table_row("`" m[1] "`", m[2], "", 0)
		} else {
			print_table_row(text, "", "", 0)
		}
	}
}

function print_option_table(kind, idx, i, key, text, m, term, desc)
{
	print "| Option | Description |"
	print "| --- | --- |"
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (match(text, /^(((-[[:alnum:]]([[:blank:]]*<[^>]+>)?|--[[:alnum:]][[:alnum:]-]*((=|[[:blank:]]+)<[^>]+>)?)([[:blank:]]*\|?[[:blank:]]+))+)([^[:blank:]|<-].*)?$/, m)) {
			term = trim(m[1])
			desc = trim(m[8])
			gsub(/[[:blank:]]+\|[[:blank:]]+/, " | ", term)
			gsub(/</, "\\<", term)
			gsub(/>/, "\\>", term)
			print_table_row("**" term "**", desc, "", 0)
		} else {
			print_table_row(text, "", "", 0)
		}
	}
}

function print_env_table(kind, idx, i, key, text, m)
{
	print "| Variable | Type | Description |"
	print "| --- | --- | --- |"
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (match(text, /^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
			print_table_row("**`" m[1] "`**", m[2], m[3], 1)
		} else {
			print_table_row(text, "", "", 1)
		}
	}
}

function print_simple_table(kind, idx, header, i, key)
{
	print "| " header " |"
	print "| --- |"
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		print "| " md_escape(items[key]) " |"
	}
}

function print_link_table(kind, idx, header, i, key)
{
	print "| " header " |"
	print "| --- |"
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		print "| " md_escape(render_link(items[key])) " |"
	}
}

function cell_escape(text)
{
	text = md_escape(text)
	gsub(/\n/, "<br>", text)
	return text
}

function append_join(acc, text, sep)
{
	if (text == "") {
		return acc
	}
	return acc (acc == "" ? "" : sep) text
}

function format_arg_items(kind, idx, i, key, text, m, out)
{
	out = ""
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (match(text, /^(\$[^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
			out = append_join(out, "`" m[1] "` (" m[2] ") — " m[3], "<br>")
		} else {
			out = append_join(out, text, "<br>")
		}
	}
	return out
}

function format_exit_items(kind, idx, i, key, text, m, out)
{
	out = ""
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (match(text, /^([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
			out = append_join(out, "`" m[1] "` — " m[2], "<br>")
		} else {
			out = append_join(out, text, "<br>")
		}
	}
	return out
}

function format_option_items(kind, idx, i, key, text, m, term, desc, out)
{
	out = ""
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (match(text, /^(((-[[:alnum:]]([[:blank:]]*<[^>]+>)?|--[[:alnum:]][[:alnum:]-]*((=|[[:blank:]]+)<[^>]+>)?)([[:blank:]]*\|?[[:blank:]]+))+)([^[:blank:]|<-].*)?$/, m)) {
			term = trim(m[1])
			desc = trim(m[8])
			gsub(/[[:blank:]]+\|[[:blank:]]+/, " | ", term)
			gsub(/</, "\\<", term)
			gsub(/>/, "\\>", term)
			out = append_join(out, "`" term "`" (desc != "" ? " — " desc : ""), "<br>")
		} else {
			out = append_join(out, text, "<br>")
		}
	}
	return out
}

function format_env_items(kind, idx, i, key, text, m, out)
{
	out = ""
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (match(text, /^([^[:space:]]+)[[:space:]]+([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
			out = append_join(out, "`" m[1] "` (" m[2] ") — " m[3], "<br>")
		} else {
			out = append_join(out, text, "<br>")
		}
	}
	return out
}

function format_simple_items(kind, idx, i, key, out)
{
	out = ""
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		out = append_join(out, items[key], "<br>")
	}
	return out
}

function format_link_items(kind, idx, i, key, out)
{
	out = ""
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		out = append_join(out, render_link(items[key]), "<br>")
	}
	return out
}

function format_example_items(kind, idx, i, key, ex, lines, n, j, rendered, out)
{
	out = ""
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		ex = dedent(items[key])
		n = split(ex, lines, /\n/)
		rendered = ""
		for (j = 1; j <= n; j++) {
			rendered = append_join(rendered, "<code>" cell_escape(lines[j]) "</code>", "<br>")
		}
		out = append_join(out, (counts[kind, idx] > 1 ? "**Example " i ":**<br>" : "") rendered, "<br><br>")
	}
	return out
}

function print_field_row(label, content)
{
	print "| " md_escape(label) " | " cell_escape(content) " |"
}

function decorate_block_title(title)
{
	if (title == "Arguments") return "🧾 Arguments"
	if (title == "Options") return "🎛️ Options"
	if (title == "Environment variables") return "🌍 Environment variables"
	if (title == "Exit codes") return "🚦 Exit codes"
	if (title == "Input on stdin") return "📥 Input on stdin"
	if (title == "Output on stdout") return "📤 Output on stdout"
	if (title == "Output on stderr") return "📤 Output on stderr"
	if (title == "See also") return "🔗 See also"
	if (title == "Notes") return "📝 Notes"
	if (title == "Variable sets") return "🧩 Variable sets"
	return title
}

function print_bullet_list(kind, idx, formatter, i, key, text, m)
{
	for (i = 1; i <= counts[kind, idx]; i++) {
		key = kind SUBSEP idx SUBSEP i
		text = items[key]
		if (formatter == "see") {
			print "- " render_link(text)
		} else if (formatter == "exit" && match(text, /^([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
			print "- `" m[1] "`: " m[2]
		} else if (formatter == "set" && match(text, /^([^[:space:]]+)[[:space:]]+(.*)$/, m)) {
			print "- **`" m[1] "`**: " m[2]
		} else {
			print "- " text
		}
	}
}

function print_function(idx, fn_desc_key, fn_heading_level)
{
	if (fn_section[idx] != "" && fn_section[idx] != last_printed_section) {
		print "### 🧩 " fn_section[idx]
		print ""
		last_printed_section = fn_section[idx]
	}
	fn_heading_level = (fn_section[idx] != "" ? "####" : "###")
	print fn_heading_level " `" fn_name[idx] "`"
	print ""
	if (counts["fn_deprecated", idx] > 0) {
		print "> ⚠️ **Deprecated**"
		print ">"
		for (i = 1; i <= counts["fn_deprecated", idx]; i++) {
			print "> " items["fn_deprecated", idx, i]
		}
		print ""
	}
	fn_desc_key = "fn_desc" SUBSEP idx
	if (fn_desc_key in texts) {
		print_multiline(texts[fn_desc_key] "")
		print ""
	}
	if (counts["fn_example", idx] > 0) {
		if (counts["fn_example", idx] == 1) {
			print "**🧪 Example**"
		} else {
			print "**🧪 Examples**"
		}
		print ""
		for (i = 1; i <= counts["fn_example", idx]; i++) {
			print "```bash"
			print dedent(items["fn_example", idx, i])
			print "```"
			print ""
		}
	}
	if (fn_noargs[idx]) {
		print "_Function has no arguments._"
		print ""
	}
	print_list("fn_option", idx, "Options", "option")
	print_list("fn_arg", idx, "Arguments", "arg")
	print_list("fn_env", idx, "Environment variables", "env")
	print_list("fn_set", idx, "Variable sets", "set")
	print_list("fn_note", idx, "Notes", "bullet")
	print_list("fn_stdin", idx, "Input on stdin", "bullet")
	print_list("fn_stdout", idx, "Output on stdout", "bullet")
	print_list("fn_stderr", idx, "Output on stderr", "bullet")
	print_list("fn_exitcode", idx, "Exit codes", "exit")
	print_list("fn_see", idx, "See also", "see")
}

function print_list(kind, idx, title, formatter, i, key, text)
{
	if (counts[kind, idx] == 0) {
		return
	}
	print "**" decorate_block_title(title) "**"
	print ""
	if (formatter == "arg") {
		print_arg_table(kind, idx)
	} else if (formatter == "option") {
		print_option_table(kind, idx)
	} else if (formatter == "env") {
		print_env_table(kind, idx)
	} else if (formatter == "see") {
		print_bullet_list(kind, idx, "see")
	} else if (formatter == "exit") {
		print_bullet_list(kind, idx, "exit")
	} else {
		print_bullet_list(kind, idx, "")
	}
	print ""
}

function print_multiline(text, n, arr, i)
{
	n = split(text, arr, /\n/)
	for (i = 1; i <= n; i++) {
		print arr[i]
	}
}

function print_related_examples(cmd, path, found, content, i, j, skip, rel_path)
{
	if (example_dir == "") {
		return
	}
	cmd = "find \"" example_dir "\" -maxdepth 1 -type f -name '*.sh' | sort"
	found = 0
	while ((cmd | getline path) > 0) {
		content = ""
		while ((getline line < path) > 0) {
			content = content line "\n"
		}
		close(path)
		for (i = 1; i <= fn_count; i++) {
			if (index(content, fn_name[i]) > 0) {
				rel_path = path
				gsub(/^.*\/example\//, "example/", rel_path)
				skip = 0
				for (j = 1; j <= counts["module_see", 0]; j++) {
					if (normalize_ref(items["module_see", 0, j]) == rel_path) {
						skip = 1
						break
					}
				}
				if (!skip) {
					related[path] = 1
					found = 1
				}
				break
			}
		}
	}
	close(cmd)
	if (! found) {
		return
	}
	print "## 🧪 Related examples"
	print ""
	for (path in related) {
		gsub(/^.*\/example\//, "", path)
		print "- " render_link("example/" path)
	}
}

function print_tips_section(i, j, has_tips)
{
	has_tips = counts["module_tip", 0] > 0
	if (! has_tips) {
		for (i = 1; i <= fn_count; i++) {
			if (counts["fn_tip", i] > 0) {
				has_tips = 1
				break
			}
		}
	}
	if (! has_tips) {
		return
	}
	print "## 💡 Tips"
	print ""
	if (counts["module_tip", 0] > 0) {
		for (j = 1; j <= counts["module_tip", 0]; j++) {
			print "- " items["module_tip", 0, j]
		}
		print ""
	}
	for (i = 1; i <= fn_count; i++) {
		if (counts["fn_tip", i] == 0) {
			continue
		}
		print "### `" fn_name[i] "`"
		print ""
		for (j = 1; j <= counts["fn_tip", i]; j++) {
			print "- " items["fn_tip", i, j]
		}
		print ""
	}
}

function print_quick_links(i, nav, section_nav, section_name, has_tips)
{
	nav = ""
	has_tips = counts["module_tip", 0] > 0
	if (! has_tips) {
		for (i = 1; i <= fn_count; i++) {
			if (counts["fn_tip", i] > 0) {
				has_tips = 1
				break
			}
		}
	}
	nav = append_nav_link(nav, "Overview", "Overview")
	if (texts["module_usage", 0] != "") {
		nav = append_nav_link(nav, "Usage", "Usage")
	}
	if (counts["module_see", 0] > 0) {
		nav = append_nav_link(nav, "See also", "See also")
	}
	if (has_tips) {
		nav = append_nav_link(nav, "Tips", "Tips")
	}
	if (fn_count > 0) {
		nav = append_nav_link(nav, "Reference", "Reference")
	}
	if (nav != "") {
		print "> 🧭 Source: " render_source_link()
		print ">"
		print "> Jump to: " nav
	}
	section_nav = ""
	for (i = 1; i <= fn_count; i++) {
		section_name = fn_section[i]
		if (section_name == "" || seen_sections[section_name]) {
			continue
		}
		seen_sections[section_name] = 1
		section_nav = append_nav_link(section_nav, section_name, section_name)
	}
	delete seen_sections
	if (section_nav != "") {
		print ">"
		print "> Reference sections: " section_nav
	}
	if (nav != "" || section_nav != "") {
		print ""
	}
}

function push_item(kind, idx, value, key)
{
	counts[kind, idx]++
	key = kind SUBSEP idx SUBSEP counts[kind, idx]
	items[key] = value
}

function render_module(i, desc, intro, usage, rest, n, j, line, in_rest)
{
	last_printed_section = ""
	print "# " module_file
	print ""
	if (module_brief != "") {
		print module_brief
		print ""
	}
	print_quick_links()
	if (counts["module_deprecated", 0] > 0) {
		print "> ⚠️ **Deprecated module**"
		print ">"
		for (i = 1; i <= counts["module_deprecated", 0]; i++) {
			print "> " items["module_deprecated", 0, i]
		}
		print ""
	}
	print "## ✨ Overview"
	print ""
	desc = texts["module_desc", 0]
	if (desc != "") {
		desc = dedent(desc)
		intro = ""
		rest = ""
		in_rest = 0
		n = split(desc, desc_lines, /\n/)
		for (j = 1; j <= n; j++) {
			line = desc_lines[j]
			if (! in_rest && (line ~ /^###[[:space:]]/ || line ~ /^##[[:space:]]/)) {
				in_rest = 1
			}
			if (in_rest) {
				rest = rest (rest == "" ? "" : "\n") line
			} else {
				intro = intro (intro == "" ? "" : "\n") line
			}
		}
		if (intro != "") {
			print_multiline(intro)
			print ""
		}
	}
	if (counts["module_globals", 0] > 0) {
		print "### 🧰 Module variables"
		print ""
		for (i = 1; i <= counts["module_globals", 0]; i++) {
			print "- " items["module_globals", 0, i]
		}
		print ""
	}
	if (counts["module_env", 0] > 0) {
		print "### 🌍 Environment"
		print ""
		print_env_table("module_env", 0)
		print ""
	}
	if (fn_count > 0) {
		print "### 🚀 Highlights"
		print ""
		for (i = 1; i <= fn_count; i++) {
			print "- " render_function_link(fn_name[i]) " \342\200\224 " summary(texts["fn_desc", i])
		}
		print ""
	}
	if (rest != "") {
		print_multiline(rest)
		print ""
	}
	usage = texts["module_usage", 0]
	if (usage != "") {
		print "## 🚀 Usage"
		print ""
		print_multiline(dedent(usage))
		print ""
	}
	if (counts["module_see", 0] > 0) {
		print "## 🔗 See also"
		print ""
		for (i = 1; i <= counts["module_see", 0]; i++) {
			line = items["module_see", 0, i]
			print "- " render_link(line)
		}
		print ""
	}
	print_tips_section()
	if (fn_count > 0) {
		print "## 📚 Reference"
		print ""
		for (i = 1; i <= fn_count; i++) {
			print_function(i)
			if (i < fn_count) {
				print ""
			}
		}
	}
	if (counts["module_license", 0] > 0) {
		print ""
		print "## 📄 License"
		print ""
		for (i = 1; i <= counts["module_license", 0]; i++) {
			print "- " items["module_license", 0, i]
		}
	}
	if (example_dir != "") {
		print ""
		print_related_examples()
	}
}

function summary(text, out)
{
	out = text
	gsub(/\n+/, " ", out)
	gsub(/[[:space:]]+/, " ", out)
	return trim(out)
}

function trim(s)
{
	sub(/^[[:space:]]+/, "", s)
	sub(/[[:space:]]+$/, "", s)
	return s
}
