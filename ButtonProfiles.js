.pragma library

// Plain profile data shared by the QML model and isolated contract checks.
var keys = ["back", "forward", "middle", "tiltLeft", "tiltRight"];
var maxProfiles = 32;

function copy(value) { return JSON.parse(JSON.stringify(value)); }

function profile(id, name, source) {
  var result = {id: id, name: name, buttons: {}, customShortcuts: {}, customCommands: {}};
  keys.forEach(function(key) {
    result.buttons[key] = source && source.buttons && source.buttons[key] || "default";
    result.customShortcuts[key] = source && source.customShortcuts && source.customShortcuts[key] || "";
    result.customCommands[key] = source && source.customCommands && source.customCommands[key] || "";
  });
  return result;
}

function fromConfig(cfg, defaultName) {
  if (cfg && cfg.version === 2) {
    return {profiles: copy(cfg.profiles), activeProfileId: cfg.activeProfileId,
      profileShortcut: cfg.profileShortcut};
  }
  return {profiles: [profile("main", defaultName, cfg)], activeProfileId: "main", profileShortcut: ""};
}

function find(profiles, id) {
  return profiles.find(function(item) { return item.id === id; }) || null;
}

// Exactly one key with optional modifiers. Never accepts commands or Lua syntax.
function shortcut(value) {
  var text = String(value || "").trim();
  if (!text) return null;
  if (text.length > 256) throw new Error("Invalid shortcut");
  var modifiers = {SHIFT: 1, CTRL: 4, CONTROL: 4, ALT: 8, SUPER: 64, WIN: 64, META: 64, LOGO: 64};
  var aliases = {SPACE: "space", ENTER: "Return", RETURN: "Return", ESC: "Escape", ESCAPE: "Escape",
    TAB: "Tab", BACKSPACE: "BackSpace", DELETE: "Delete", DEL: "Delete", INSERT: "Insert", INS: "Insert",
    HOME: "Home", END: "End", PAGEUP: "Prior", PGUP: "Prior", PRIOR: "Prior",
    PAGEDOWN: "Next", PGDN: "Next", NEXT: "Next", LEFT: "Left", RIGHT: "Right", UP: "Up", DOWN: "Down",
    PRINT: "Print", PRINTSCREEN: "Print", PAUSE: "Pause", MENU: "Menu"};
  var mask = 0, key = "";
  var tokens = text.toUpperCase().replace(/\+/g, " ").trim().split(/\s+/);
  tokens.forEach(function(token) {
    if (modifiers[token]) mask |= modifiers[token];
    else {
      if (key) throw new Error("Use one key");
      key = aliases[token] || (/^[A-Z0-9]$/.test(token) || /^F(?:[1-9]|1[0-9]|2[0-4])$/.test(token) ? token : "");
      if (!key) throw new Error("Unsupported key");
    }
  });
  if (!key) throw new Error("Missing key");
  var mods = [];
  [[64, "SUPER"], [4, "CTRL"], [8, "ALT"], [1, "SHIFT"]].forEach(function(pair) {
    if (mask & pair[0]) mods.push(pair[1]);
  });
  return {key: key, modmask: mask, keys: mods.concat([key]).join(" + ")};
}
