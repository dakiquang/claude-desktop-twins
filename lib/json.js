// JSON reads for session stores, run with `osascript -l JavaScript`.
// plutil cannot parse every session file (it rejects escaped NUL characters), so all
// session JSON goes through here.
//
//   scan <dir>                      one line per local_*.json:
//                                   id, originCwd or cwd, cliSessionId, separated by
//                                   0x1f so empty fields survive a shell read
//   archived <idx>                  archived ids, one per line (none if idx is missing)
ObjC.import('Foundation');

function readText(path) {
  const s = $.NSString.stringWithContentsOfFileEncodingError($(path), $.NSUTF8StringEncoding, null);
  if (s.isNil()) throw new Error('cannot read ' + path);
  return s.js;
}

function exists(path) {
  return $.NSFileManager.defaultManager.fileExistsAtPath($(path));
}

function clean(v) {
  return (typeof v === 'string' ? v : '').replace(/[\t\n\r\x1f]/g, ' ');
}

function readIdx(path) {
  if (!exists(path)) return { v: 1, archived: [] };
  const idx = JSON.parse(readText(path));
  if (!Array.isArray(idx.archived)) throw new Error('unexpected format: ' + path);
  return idx;
}

function scan(dir) {
  const names = $.NSFileManager.defaultManager.contentsOfDirectoryAtPathError($(dir), null);
  if (names.isNil()) throw new Error('cannot list ' + dir);
  const lines = [];
  names.js.map((n) => n.js).sort().forEach((name) => {
    if (!/^local_.*\.json$/.test(name)) return;
    const s = JSON.parse(readText(dir + '/' + name));
    const id = name.replace(/\.json$/, '');
    lines.push([id, clean(s.originCwd || s.cwd), clean(s.cliSessionId)].join('\x1f'));
  });
  return lines.join('\n');
}

function run(argv) {
  const cmd = argv[0];
  if (cmd === 'scan') return scan(argv[1]);
  if (cmd === 'archived') return readIdx(argv[1]).archived.join('\n');
  throw new Error('unknown command: ' + cmd);
}
