"""Build one VESC package, leaving its readable source files untouched."""
import argparse
import datetime
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import zlib

from minify import balanced, strip


GENERATED = ('README-gen.md', 'ui.qml', 'version.lisp')


def package_version(source):
    version = (source / 'version').read_text().strip()
    if not re.fullmatch(r'[0-9]+\.[0-9]+(?:\.[0-9]+)?(?:-[0-9A-Za-z.-]+)?', version):
        raise ValueError('Invalid package version: ' + repr(version))
    return version


def build_info(source, version):
    epoch = os.environ.get('SOURCE_DATE_EPOCH')
    date = (datetime.datetime.fromtimestamp(int(epoch), datetime.timezone.utc)
            if epoch is not None else datetime.datetime.now(datetime.timezone.utc))
    lines = ['### Build Info', '', '- Version: ' + version,
             '- Build Date: ' + date.strftime('%Y-%m-%d %H:%M:%S UTC')]
    # Do not accidentally attribute a source archive to an enclosing repository.
    root = source.parent
    if (root / '.git').exists():
        commit = subprocess.run(['git', '-C', str(root), 'rev-parse', '--short=12', 'HEAD'],
                                capture_output=True, text=True, check=False)
        if commit.returncode == 0:
            lines.append('- Git Commit: ' + commit.stdout.strip())
    return '\n'.join(lines)


def render_template(source, name, version):
    template = (source / (name + '.in')).read_text()
    if '{{VERSION}}' not in template:
        raise ValueError('Version placeholder missing: ' + name + '.in')
    return template.replace('{{VERSION}}', version)


def native_directories(source):
    directories = sorted({path.parent for path in source.rglob('*.c')})
    for directory in directories:
        if not (directory / 'Makefile').is_file():
            raise ValueError('Native source has no Makefile: ' + str(directory))
    return directories


def package_description(source, descriptor, info=None):
    filename = re.search(r'pkgDescriptionMd:\s*"([^"]+)"', descriptor)[1]
    if filename != 'README-gen.md':
        raise ValueError('pkgDescriptionMd must point to README-gen.md')
    description = (source / 'README.md').read_text().rstrip()
    if info is None:
        info = build_info(source, package_version(source))
    description += '\n\n' + info + '\n'
    notices = [source / name for name in
               ('NOTICE.txt', 'LICENSE', 'LICENSE.txt', 'FONT-NOTICES.txt')
               if (source / name).is_file()]
    notices += sorted((source / 'font' / 'licenses').glob('*.txt'))
    if notices:
        description = description.rstrip() + '\n\n## License texts and notices\n'
        for path in notices:
            description += '\n### ' + path.relative_to(source).as_posix() + '\n\n'
            description += '```text\n' + path.read_text().rstrip() + '\n```\n'
    return filename, description


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('package', nargs='?', default='.')
    parser.add_argument('--vesc-tool', default='vesc_tool')
    parser.add_argument('--clean', action='store_true', help='Remove package and native build outputs')
    args = parser.parse_args()
    source = Path(args.package).resolve()
    descriptor = (source / 'pkgdesc.qml').read_text()
    output = re.search(r'pkgOutput:\s*"([^"]+)"', descriptor)[1]
    if Path(output).name != output or not output.endswith('.vescpkg'):
        parser.error('pkgOutput must be a .vescpkg filename in the package folder')
    native = [directory.relative_to(source) for directory in native_directories(source)]
    if args.clean:
        (source / output).unlink(missing_ok=True)
        for name in GENERATED:
            (source / name).unlink(missing_ok=True)
        for directory in native:
            subprocess.run(['make', 'clean'], cwd=source / directory, check=True)
        return
    version = package_version(source)
    generated = {name: render_template(source, name, version)
                 for name in ('ui.qml', 'version.lisp')}
    filename, description = package_description(source, descriptor, build_info(source, version))
    generated[filename] = description
    executable = shutil.which(args.vesc_tool)
    if executable is None:
        parser.error('VESC Tool executable not found: ' + args.vesc_tool)
    executable = str(Path(executable).resolve())
    with tempfile.TemporaryDirectory(prefix='vesc-package-') as temp:
        work = Path(temp) / source.name
        shutil.copytree(source, work,
            ignore=shutil.ignore_patterns('*.vescpkg', '*.o', '*.elf', '__pycache__', '.DS_Store'))
        for name, contents in generated.items():
            (work / name).write_text(contents)
        native_outputs = []
        for directory in native:
            helper = work / directory
            # Never trust prebuilt binaries or timestamps from an extracted archive.
            for binary in helper.glob('*.bin'):
                binary.unlink()
            subprocess.run(['make', '-B'], cwd=helper, check=True)
            binaries = sorted(helper.glob('*.bin'))
            if not binaries or any(path.stat().st_size == 0 for path in binaries):
                raise ValueError('Native build produced no usable binary: ' + str(directory))
            native_outputs += binaries
        for path in work.rglob('*.lisp'):
            text = path.read_text()
            if not balanced(text):
                raise ValueError('Unbalanced Lisp source: ' + str(path.relative_to(work)))
            compact = strip(text)
            if not balanced(compact):
                raise ValueError('Invalid Lisp after minifying: ' + str(path.relative_to(work)))
            path.write_text(compact)
        subprocess.run([executable, '--buildPkgFromDesc', 'pkgdesc.qml'],
            cwd=work, env={**os.environ, 'QT_QPA_PLATFORM': 'offscreen'}, check=True)
        package = work / output
        raw = package.read_bytes()
        if not zlib.decompress(raw[4:]).startswith(b'VESC Packet\0'):
            raise ValueError('VESC Tool did not produce a valid package')
        # Publish outputs only after every helper and the package build succeeded.
        for name, contents in generated.items():
            (source / name).write_text(contents)
        for binary in native_outputs:
            shutil.copy2(binary, source / binary.relative_to(work))
        shutil.copy2(package, source / output)
    print(source / output)


if __name__ == '__main__':
    main()
