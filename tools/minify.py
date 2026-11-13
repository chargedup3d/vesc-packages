#!/usr/bin/env python3
"""Remove comments and indentation while preserving LispBM string literals."""
import sys

def strip(src):
    out = []
    buf = []
    instr = False
    i = 0
    while i < len(src):
        c = src[i]
        if instr:
            # Newlines, indentation, semicolons and escaped quotes are data.
            buf.append(c)
            if c == "\\" and i + 1 < len(src):
                buf.append(src[i + 1]); i += 2; continue
            if c == '"':
                instr = False
        elif c == ";":
            while i < len(src) and src[i] != "\n":
                i += 1
            continue
        elif c == "\n":
            line = "".join(buf).rstrip()
            if line:
                out.append(line)
            buf = []
        elif c == '"':
            buf.append(c)
            instr = True
        elif buf or not c.isspace():
            buf.append(c)
        i += 1
    if instr:
        raise ValueError("Unterminated Lisp string literal")
    line = "".join(buf).rstrip()
    if line:
        out.append(line)
    return "\n".join(out) + "\n"

def balanced(src):
    stack = []; instr = False; i = 0
    pairs = {')': '(', ']': '[', '}': '{'}
    while i < len(src):
        c = src[i]
        if instr:
            if c == "\\": i += 2; continue
            if c == '"': instr = False
        else:
            if c == ";":
                while i < len(src) and src[i] != "\n": i += 1
                continue
            if c == '"': instr = True
            elif c in "([{": stack.append(c)
            elif c in pairs:
                if not stack or stack.pop() != pairs[c]:
                    return False
        i += 1
    return not stack and not instr

if __name__ == "__main__":
    src = open(sys.argv[1]).read()
    out = strip(src)
    if not balanced(src):
        sys.exit("refusing to minify: the source is not balanced to begin with")
    if not balanced(out):
        sys.exit("minify changed the paren balance - not writing")
    # every string literal in the source must survive unchanged
    def strings(t):
        r = []; i = 0
        while i < len(t):
            if t[i] == ";":
                while i < len(t) and t[i] != "\n": i += 1
                continue
            if t[i] == '"':
                j = i + 1; buf = ['"']
                while j < len(t):
                    if t[j] == "\\": buf.append(t[j:j+2]); j += 2; continue
                    buf.append(t[j])
                    if t[j] == '"': j += 1; break
                    j += 1
                r.append("".join(buf)); i = j; continue
            i += 1
        return r
    a, b = strings(src), strings(out)
    if a != b:
        sys.exit(f"minify altered a string literal ({len(a)} -> {len(b)})")
    open(sys.argv[2], "w").write(out)
    print(f"  {sys.argv[1]}: {len(src)} -> {len(out)} chars "
          f"({100 - 100*len(out)//len(src)}% smaller), {len(a)} strings intact")
