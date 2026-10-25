function apply_sgr(params, count, codes, i, code, mode) {
    if (params == "") {
        dim = 0
        return
    }

    count = split(params, codes, ";")
    for (i = 1; i <= count; i++) {
        code = codes[i]
        if (code ~ /^(38|48|58):/) continue
        if (code == "" || code == "0" || code == "22") dim = 0
        else if (code == "2") dim = 1
        else if (code == "38" || code == "48" || code == "58") {
            mode = codes[i + 1]
            if (mode == "2") i += 4
            else if (mode == "5") i += 2
        }
    }
}

{
    line = $0
    gsub("\302\240", " ", line)
    sub(/\r$/, "", line)
    plain = ""
    dim_mask = ""
    dim = 0
    for (i = 1; i <= length(line);) {
        if (substr(line, i, 1) == "\033" && substr(line, i + 1, 1) == "[") {
            j = i + 2
            while (j <= length(line) && substr(line, j, 1) !~ /[@-~]/) j++
            if (j <= length(line)) {
                if (substr(line, j, 1) == "m") {
                    apply_sgr(substr(line, i + 2, j - i - 2))
                }
                i = j + 1
                continue
            }
        }

        char = substr(line, i, 1)
        plain = plain char
        dim_mask = dim_mask (dim ? "1" : "0")
        i++
    }

    if (match(plain, /^[[:space:]]*(❯|›)/)) {
        found = 1
        occupied = 0
        for (i = RSTART + RLENGTH; i <= length(plain); i++) {
            char = substr(plain, i, 1)
            if (substr(dim_mask, i, 1) == "0" && char ~ /[^[:space:]]/) {
                occupied = 1
                break
            }
        }
    }
}

END {
    if (!found) print "unknown"
    else if (occupied) print "occupied"
    else print "empty"
}
