# Observed in the Claude Code, Codex, and agy input captures: plain SGR 0, 1,
# 2, 7, 22, 27, and 36; 38;5;n and 38;2;r;g;b foregrounds; and 48;2;r;g;b
# backgrounds. Every other SGR or control sequence in the input area is unsafe.

function canonical_number(value) {
    return value == "0" || value ~ /^[1-9][0-9]*$/
}

function valid_sgr(params, codes, count, i, code, mode, j) {
    if (params !~ /^[0-9]+(;[0-9]+)*$/) return 0

    count = split(params, codes, ";")
    for (i = 1; i <= count; i++) {
        code = codes[i]
        if (!canonical_number(code)) return 0
        if (code == "38" || code == "48") {
            if (i == count) return 0
            mode = codes[i + 1]
            if (!canonical_number(mode)) return 0
            if (code == "38" && mode == "5") {
                if (i + 2 > count || !canonical_number(codes[i + 2]) || codes[i + 2] + 0 > 255) return 0
                i += 2
            }
            else if (mode == "2") {
                if (i + 4 > count) return 0
                for (j = i + 2; j <= i + 4; j++) {
                    if (!canonical_number(codes[j]) || codes[j] + 0 > 255) return 0
                }
                i += 4
            }
            else return 0
        }
        else if (code !~ /^(0|1|2|7|22|27|36)$/) return 0
    }
    return 1
}

function apply_sgr(params, codes, count, i, code, mode) {
    if (!valid_sgr(params, codes)) return 0
    count = split(params, codes, ";")
    for (i = 1; i <= count; i++) {
        code = codes[i]
        if (code == "0") {
            dim = 0
            gray = 0
            reverse = 0
        }
        else if (code == "2") dim = 1
        else if (code == "7") reverse = 1
        else if (code == "22") dim = 0
        else if (code == "27") reverse = 0
        else if (code == "36") gray = 0
        else if (code == "38") {
            mode = codes[i + 1]
            if (mode == "5") {
                gray = (codes[i + 2] == "8")
                i += 2
            }
            else {
                gray = 0
                i += 4
            }
        }
        else if (code == "48") i += (codes[i + 1] == "5" ? 2 : 4)
    }
    return 1
}

{
    line = $0
    gsub("\302\240", " ", line)
    sub(/\r$/, "", line)
    plain = ""
    dim_mask = ""
    gray_mask = ""
    reverse_mask = ""
    bad_count = 0
    dim = 0
    gray = 0
    reverse = 0

    for (i = 1; i <= length(line);) {
        char = substr(line, i, 1)
        if (char == "\033") {
            if (substr(line, i + 1, 1) == "[") {
                j = i + 2
                while (j <= length(line) && substr(line, j, 1) !~ /[@-~]/) j++
                if (j > length(line)) {
                    bad_offsets[++bad_count] = length(plain)
                    i = length(line) + 1
                    continue
                }
                final = substr(line, j, 1)
                if (final != "m" || !apply_sgr(substr(line, i + 2, j - i - 2), codes)) {
                    bad_offsets[++bad_count] = length(plain)
                }
                i = j + 1
                continue
            }

            bad_offsets[++bad_count] = length(plain)
            next_char = substr(line, i + 1, 1)
            if (next_char == "]" || next_char == "P" || next_char == "^" || next_char == "_") {
                i += 2
                while (i <= length(line)) {
                    if (substr(line, i, 1) == "\007") {
                        i++
                        break
                    }
                    if (substr(line, i, 1) == "\033" && substr(line, i + 1, 1) == "\\") {
                        i += 2
                        break
                    }
                    i++
                }
            }
            else if (i < length(line)) i += 2
            else i++
            continue
        }

        if (char ~ /[[:cntrl:]]/) {
            bad_offsets[++bad_count] = length(plain)
            i++
            continue
        }

        # LC_ALL=C sees UTF-8 C1 controls as bytes, not control characters.
        if (char == "\302" && substr(line, i + 1, 1) ~ /^[\200-\237]$/) {
            bad_offsets[++bad_count] = length(plain)
            i += 2
            continue
        }

        plain = plain char
        dim_mask = dim_mask (dim ? "1" : "0")
        gray_mask = gray_mask (gray ? "1" : "0")
        reverse_mask = reverse_mask (reverse ? "1" : "0")
        i++
    }

    if (match(plain, /^[[:space:]]*(❯|›)/) || match(plain, /^ ? ?>( |$)/)) {
        found = 1
        occupied = 0
        prompt_end = RSTART + RLENGTH - 1

        for (i = 1; i <= bad_count; i++) {
            if (bad_offsets[i] >= prompt_end) {
                occupied = 1
                break
            }
        }

        non_dim_count = 0
        cursor_index = 0
        if (!occupied) {
            for (i = prompt_end + 1; i <= length(plain); i++) {
                if (substr(plain, i, 1) ~ /[[:space:]]/) continue
                if (substr(dim_mask, i, 1) == "1" || substr(gray_mask, i, 1) == "1") continue
                non_dim_count++
                cursor_index = i
            }

            if (non_dim_count > 0) {
                if (non_dim_count != 1 || substr(reverse_mask, cursor_index, 1) != "1") occupied = 1
                else {
                    next_index = cursor_index + 1
                    if (next_index > length(plain) ||
                        substr(plain, next_index, 1) ~ /[[:space:]]/ ||
                        (substr(dim_mask, next_index, 1) != "1" && substr(gray_mask, next_index, 1) != "1")) {
                        occupied = 1
                    }
                }
            }
        }
    }
}

END {
    if (!found) print "unknown"
    else if (occupied) print "occupied"
    else print "empty"
}
