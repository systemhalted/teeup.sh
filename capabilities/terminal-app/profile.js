// profile.js - teeup's Terminal.app profiles, run as
//   osascript -l JavaScript profile.js apply <name> <font> <size> <export> <Key=#rrggbb>...
//   osascript -l JavaScript profile.js remove
//   osascript -l JavaScript profile.js has <name>
//
// Terminal keeps its profiles in the "Window Settings" dictionary of the
// com.apple.Terminal preferences, one dictionary per profile, and stores each
// colour and the font as NSKeyedArchiver data. Neither `defaults` nor
// Terminal's AppleScript dictionary can write the ANSI colours, so this uses
// the JavaScript for Automation bridge to AppKit, which ships with macOS.
//
// Only a profile whose name starts with "teeup " is ever written or deleted.
// Every other profile, the user's own and Terminal's built-in ones, is copied
// back unchanged.
//
// TEEUP_TEST_TERMINAL_PLIST, when set, points the program at a plist file
// instead of the com.apple.Terminal domain. The test suite uses it so a run
// on a Mac never touches the real Terminal settings.

ObjC.import('Foundation');
ObjC.import('AppKit');

var PREFIX = 'teeup ';
var DOMAIN = 'com.apple.Terminal';
var SETTINGS = 'Window Settings';
var COLOR_KEYS = [
  'BackgroundColor', 'TextColor', 'TextBoldColor', 'CursorColor', 'SelectionColor',
  'ANSIBlackColor', 'ANSIRedColor', 'ANSIGreenColor', 'ANSIYellowColor',
  'ANSIBlueColor', 'ANSIMagentaColor', 'ANSICyanColor', 'ANSIWhiteColor',
  'ANSIBrightBlackColor', 'ANSIBrightRedColor', 'ANSIBrightGreenColor', 'ANSIBrightYellowColor',
  'ANSIBrightBlueColor', 'ANSIBrightMagentaColor', 'ANSIBrightCyanColor', 'ANSIBrightWhiteColor'
];

function isNil(o) {
  return o === undefined || o === null || (typeof o.isNil === 'function' && o.isNil());
}

function fail(message) {
  throw new Error('teeup profile.js: ' + message);
}

function env(name) {
  var v = $.NSProcessInfo.processInfo.environment.objectForKey(name);
  return isNil(v) ? '' : ObjC.unwrap(v);
}

// The settings store: the real preferences domain, or a plist file for tests.
// Only the "Window Settings" key is read and written; every other key in the
// domain is left to Terminal.
function openStore() {
  var path = env('TEEUP_TEST_TERMINAL_PLIST');
  if (path) {
    return {
      read: function () {
        var d = $.NSDictionary.dictionaryWithContentsOfFile(path);
        return isNil(d) ? null : d.objectForKey(SETTINGS);
      },
      write: function (settings) {
        var d = $.NSDictionary.dictionaryWithContentsOfFile(path);
        var m = isNil(d) ? $.NSMutableDictionary.dictionary : $.NSMutableDictionary.dictionaryWithDictionary(d);
        m.setObjectForKey(settings, SETTINGS);
        if (!m.writeToFileAtomically(path, true)) fail('could not write ' + path);
      }
    };
  }
  // initWithSuiteName with another app's bundle identifier reads and writes
  // that app's preferences through cfprefsd, the same path `defaults` takes.
  var defaults = $.NSUserDefaults.alloc.initWithSuiteName(DOMAIN);
  if (isNil(defaults)) fail('could not open the ' + DOMAIN + ' preferences');
  return {
    read: function () {
      var d = defaults.dictionaryForKey(SETTINGS);
      return isNil(d) ? null : d;
    },
    write: function (settings) {
      defaults.setObjectForKey(settings, SETTINGS);
      defaults.synchronize;
    }
  };
}

function mutableSettings(store) {
  var current = store.read();
  return current ? $.NSMutableDictionary.dictionaryWithDictionary(current) : $.NSMutableDictionary.dictionary;
}

function profileNames(settings) {
  return ObjC.deepUnwrap(settings.allKeys) || [];
}

// archive(object) -> NSData. archivedDataWithRootObject:requiringSecureCoding:error:
// exists from macOS 10.13; the older archivedDataWithRootObject: is the
// fallback for anything before that.
function archive(object) {
  var data = null;
  try {
    data = $.NSKeyedArchiver.archivedDataWithRootObjectRequiringSecureCodingError(object, false, $());
  } catch (e) {
    data = null;
  }
  if (isNil(data)) data = $.NSKeyedArchiver.archivedDataWithRootObject(object);
  if (isNil(data)) fail('could not archive ' + ObjC.unwrap(object.description));
  return data;
}

function color(hex) {
  var m = /^#([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})([0-9A-Fa-f]{2})$/.exec(hex);
  if (!m) fail('not a #rrggbb colour: ' + hex);
  return $.NSColor.colorWithSRGBRedGreenBlueAlpha(
    parseInt(m[1], 16) / 255, parseInt(m[2], 16) / 255, parseInt(m[3], 16) / 255, 1);
}

// font(family, size) -> an NSFont, or null when it is not installed. The name
// teeup records is a family ("JetBrainsMono Nerd Font"); fontWithName:size:
// wants a font name, so the family is asked of NSFontManager when that fails.
function font(family, size) {
  var f = $.NSFont.fontWithNameSize(family, size);
  if (isNil(f)) f = $.NSFontManager.sharedFontManager.fontWithFamilyTraitsWeightSize(family, 0, 5, size);
  return isNil(f) ? null : f;
}

function apply(args) {
  var name = args[0], family = args[1], size = parseFloat(args[2]), exportPath = args[3];
  var pairs = args.slice(4), seen = {}, messages = [];
  if (!name || name.indexOf(PREFIX) !== 0 || name.length === PREFIX.length) {
    fail('refusing to write a profile whose name does not start with "' + PREFIX + '": ' + name);
  }
  if (!(size > 0)) fail('not a font size: ' + args[2]);
  var profile = $.NSMutableDictionary.dictionary;
  pairs.forEach(function (pair) {
    var eq = pair.indexOf('=');
    var key = pair.slice(0, eq), hex = pair.slice(eq + 1);
    if (eq < 1 || COLOR_KEYS.indexOf(key) < 0) fail('not a Terminal colour key: ' + pair);
    profile.setObjectForKey(archive(color(hex)), key);
    seen[key] = true;
  });
  COLOR_KEYS.forEach(function (key) {
    if (!seen[key]) fail('no colour given for ' + key);
  });
  if (family) {
    var f = font(family, size);
    if (f) {
      profile.setObjectForKey(archive(f), 'Font');
    } else {
      messages.push(family + ' is not installed, so the ' + name + ' profile keeps Terminal\'s default font.');
    }
  }
  profile.setObjectForKey(name, 'name');
  profile.setObjectForKey('Window Settings', 'type');
  profile.setObjectForKey($.NSNumber.numberWithDouble(2.04), 'ProfileCurrentVersion');

  var store = openStore();
  var settings = mutableSettings(store);
  settings.setObjectForKey(profile, name);
  store.write(settings);
  if (exportPath && !profile.writeToFileAtomically(exportPath, true)) {
    messages.push('Could not save a copy of the profile to ' + exportPath + '.');
  }
  return messages.join('\n');
}

function remove() {
  var store = openStore();
  var current = store.read();
  if (!current) return 'Terminal.app has no teeup profiles to remove.';
  var settings = $.NSMutableDictionary.dictionaryWithDictionary(current);
  var gone = profileNames(settings).filter(function (n) { return n.indexOf(PREFIX) === 0; });
  if (gone.length === 0) return 'Terminal.app has no teeup profiles to remove.';
  gone.forEach(function (n) { settings.removeObjectForKey(n); });
  store.write(settings);
  return 'Removed from Terminal.app: ' + gone.join(', ');
}

function has(name) {
  var current = openStore().read();
  if (!current) return 'absent';
  return profileNames(current).indexOf(name) >= 0 ? 'present' : 'absent';
}

function run(argv) {
  var action = argv[0];
  if (action === 'apply') return apply(argv.slice(1));
  if (action === 'remove') return remove();
  if (action === 'has') return has(argv[1]);
  fail('unknown action: ' + action + ' (use apply, remove or has)');
}
