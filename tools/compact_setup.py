"""Keep infrequent setup routines as source in flash, parsing them on demand.

Only explicitly listed functions are transformed. The control loop, sensor
receiver, output guards and telemetry remain ordinary compiled closures.
"""
import json
import re
from pathlib import Path


def compact_setup(text, names, sources):
    for name in names:
        match = re.search(r'\(defun\s+' + re.escape(name) + r'\s+\(([^()]*)\)', text)
        if not match:
            raise ValueError('Setup function missing: ' + name)
        args = match[1].split()
        if any(not re.fullmatch(r'[a-zA-Z_][a-zA-Z_0-9-]*', arg) for arg in args):
            raise ValueError('Unsupported setup argument list: ' + name)
        depth, quoted, escaped, end = 0, False, False, None
        for i in range(match.start(), len(text)):
            char = text[i]
            if quoted:
                if escaped:
                    escaped = False
                elif char == '\\':
                    escaped = True
                elif char == '"':
                    quoted = False
            elif char == '"':
                quoted = True
            elif char in '({':
                depth += 1
            elif char in ')}':
                depth -= 1
                if depth == 0:
                    end = i + 1
                    break
        if end is None:
            raise ValueError('Unbalanced setup function: ' + name)
        body = text[match.end():end - 1].strip()
        source = '(lambda (' + ' '.join(args) + ') ' + body + ')'
        # VESC Tool bundles imports in the source partition. Stock firmware
        # exposes them as const arrays without copying their bytes into the
        # separate 128 KiB compiled-image partition. A string literal here
        # would consume both partitions and still overflow the image.
        symbol = 'cu-setup-' + name
        if symbol in sources:
            raise ValueError('Duplicate setup function: ' + name)
        sources[symbol] = source
        actual = '(append (list ' + ' '.join(args) + ') (rest-args))' if args else '(rest-args)'
        wrapper = '(defun ' + name + ' (' + ' '.join(args) + ') (apply (eval (read ' + symbol + ')) ' + actual + '))'
        text = text[:match.start()] + wrapper + text[end:]
    return text


def setup_manifest(source):
    path = Path(source) / 'compact_setup.json'
    if not path.exists():
        return {}
    manifest = json.loads(path.read_text())
    if not isinstance(manifest, dict):
        raise ValueError('Setup manifest must map Lisp files to function lists')
    seen = set()
    for filename, names in manifest.items():
        if (not isinstance(filename, str) or not filename.endswith('.lisp')
                or Path(filename).is_absolute() or '..' in Path(filename).parts):
            raise ValueError('Invalid setup source: ' + repr(filename))
        if not isinstance(names, list):
            raise ValueError('Setup functions must be a list: ' + filename)
        for name in names:
            if not isinstance(name, str) or not re.fullmatch(r'[a-zA-Z_][a-zA-Z_0-9-]*', name):
                raise ValueError('Invalid setup function: ' + repr(name))
            if name in seen:
                raise ValueError('Duplicate setup function: ' + name)
            seen.add(name)
    return manifest
