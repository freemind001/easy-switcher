program easyswitcher;

{$mode objfpc}
{$h+}
{$notes off}
{$codepage utf8}

uses
  cThreads,
  BaseUnix,
  Linux,
  SysUtils,
  Classes,
  IniFiles,
  EventLog,
  Errors,
  ctypes,
  dynlibs,
  process,
  DateUtils,
  Generics.Collections;

type
  // input.h struct input_event
  input_event = record
    time: timeval;
    ie_type: cuint16;
    code: cuint16;
    value: cint32;
  end;

  // uinput.h struct uinput_setup
  uinput_setup = record
    id: record
      bustype: cuint16;
      vendor: cuint16;
      product: cuint16;
      version: cuint16;
      end;
    name: array[0..79] of char;
    ff_effects_max: cuint32;
  end;

  KeyboardDetectInfo = record
    Id: PtrInt;
    Active: boolean;
    Path: string;
  end;

  TKeyboardList = array of KeyboardDetectInfo;
  TKeyBuf = array of input_event;
  TEmitBuf = array [1..2] of input_event;
  TBufferAction = (KeepBuffer, ReplaceAll, ReplaceWord);

  // --- auto-correct addition: Hunspell C API, loaded dynamically at runtime ---
  THunspellCreate = function(affpath, dpath: PChar): Pointer; cdecl;
  THunspellDestroy = procedure(handle: Pointer); cdecl;
  THunspellSpell = function(handle: Pointer; word: PChar): cint; cdecl;
  TCharTable = array [0..248] of UTF8String;
  TBigramCounts = specialize TDictionary<UTF8String, Int64>;
  TCharArray = array of UTF8String;

const
  EASY_SWITCHER_VERSION = '0.4';

  SYSTEMD_UNIT_FILE = '/lib/systemd/system/easy-switcher.service';
  CONFIG_FILE = '/etc/easy-switcher/default.conf';
  INPUT_DEVICES_DIR = '/dev/input/';
  UINPUT_FILE = '/dev/uinput';

  // event types
  EV_SYN = $00;
  EV_KEY = $01;

  // synchronization event codes
  SYN_REPORT = $00;

  // bus types
  BUS_USB = $03;

  // ioctl commands
  UI_SET_EVBIT = $40045564;
  UI_SET_KEYBIT = $40045565;
  UI_DEV_SETUP = $405C5503;
  UI_DEV_CREATE = $00005501;
  UI_DEV_DESTROY = $00005502;

  //keys to watch and replace
  Letters = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18, 19, 20, 21, 22, 23, 24,
    25, 26, 27, 28, 30, 31, 32, 33, 34, 35, 36, 37, 38, 39, 40, 41, 43, 44, 45, 46, 47, 48,
    49, 50, 51, 52, 53, 55, 57, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 96, 98];
  Shifts = [42, 54];
  BufKillers = [15, 29, 56, 97, 100, 102, 103, 104, 105, 106, 107, 108, 109, 110];

  KEY_BACKSPACE: word = 14;    //Backspace
  KEY_SPACE: word = 57;        //Space
  KEY_ENTER: word = 28;        //Enter
  KEY_KPENTER = 96;            //keypad Enter

  KeyName: array [0..248] of string =
    ('RESERVED', 'ESC', '1', '2', '3', '4', '5', '6', '7', '8', '9', '0', 'MINUS', 'EQUAL',
    'BACKSPACE', 'TAB', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I', 'O', 'P', 'LEFTBRACE',
    'RIGHTBRACE', 'ENTER', 'LEFTCTRL', 'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'SEMICOLON',
    'APOSTROPHE', 'GRAVE', 'LEFTSHIFT', 'BACKSLASH', 'Z', 'X', 'C', 'V', 'B', 'N', 'M', 'COMMA',
    'DOT', 'SLASH', 'RIGHTSHIFT', 'KPASTERISK', 'LEFTALT', 'SPACE', 'CAPSLOCK', 'F1', 'F2',
    'F3', 'F4', 'F5', 'F6', 'F7', 'F8', 'F9', 'F10', 'NUMLOCK', 'SCROLLLOCK', 'KP7', 'KP8',
    'KP9', 'KPMINUS', 'KP4', 'KP5', 'KP6', 'KPPLUS', 'KP1', 'KP2', 'KP3', 'KP0', 'KPDOT',
    '(84)', 'ZENKAKUHANKAKU', '102ND', 'F11', 'F12', 'RO', 'KATAKANA', 'HIRAGANA', 'HENKAN',
    'KATAKANAHIRAGANA', 'MUHENKAN', 'KPJPCOMMA', 'KPENTER', 'RIGHTCTRL', 'KPSLASH', 'SYSRQ',
    'RIGHTALT', 'LINEFEED', 'HOME', 'UP', 'PAGEUP', 'LEFT', 'RIGHT', 'END', 'DOWN', 'PAGEDOWN',
    'INSERT', 'DELETE', 'MACRO', 'MUTE', 'VOLUMEDOWN', 'VOLUMEUP', 'POWER', 'KPEQUAL',
    'KPPLUSMINUS', 'PAUSE', 'SCALE', 'KPCOMMA', 'HANGEUL', 'HANJA', 'YEN', 'LEFTMETA',
    'RIGHTMETA', 'COMPOSE', 'STOP', 'AGAIN', 'PROPS', 'UNDO', 'FRONT', 'COPY', 'OPEN', 'PASTE',
    'FIND', 'CUT', 'HELP', 'MENU', 'CALC', 'SETUP', 'SLEEP', 'WAKEUP', 'FILE', 'SENDFILE',
    'DELETEFILE', 'XFER', 'PROG1', 'PROG2', 'WWW', 'MSDOS', 'COFFEE', 'ROTATE_DISPLAY',
    'CYCLEWINDOWS', 'MAIL', 'BOOKMARKS', 'COMPUTER', 'BACK', 'FORWARD', 'CLOSECD', 'EJECTCD',
    'EJECTCLOSECD', 'NEXTSONG', 'PLAYPAUSE', 'PREVIOUSSONG', 'STOPCD', 'RECORD', 'REWIND',
    'PHONE', 'ISO', 'CONFIG', 'HOMEPAGE', 'REFRESH', 'EXIT', 'MOVE', 'EDIT', 'SCROLLUP',
    'SCROLLDOWN', 'KPLEFTPAREN', 'KPRIGHTPAREN', 'NEW', 'REDO', 'F13', 'F14', 'F15', 'F16',
    'F17', 'F18', 'F19', 'F20', 'F21', 'F22', 'F23', 'F24', '(195)', '(196)', '(197)', '(198)',
    '(199)', 'PLAYCD', 'PAUSECD', 'PROG3', 'PROG4', 'ALL_APPLICATIONS', 'SUSPEND', 'CLOSE',
    'PLAY', 'FASTFORWARD', 'BASSBOOST', 'PRINT', 'HP', 'CAMERA', 'SOUND', 'QUESTION', 'EMAIL',
    'CHAT', 'SEARCH', 'CONNECT', 'FINANCE', 'SPORT', 'SHOP', 'ALTERASE', 'CANCEL',
    'BRIGHTNESSDOWN', 'BRIGHTNESSUP', 'MEDIA', 'SWITCHVIDEOMODE', 'KBDILLUMTOGGLE',
    'KBDILLUMDOWN', 'KBDILLUMUP', 'SEND', 'REPLY', 'FORWARDMAIL', 'SAVE', 'DOCUMENTS', 'BATTERY',
    'BLUETOOTH', 'WLAN', 'UWB', 'UNKNOWN', 'VIDEO_NEXT', 'VIDEO_PREV', 'BRIGHTNESS_CYCLE',
    'BRIGHTNESS_AUTO', 'DISPLAY_OFF', 'WWAN', 'RFKILL', 'MICMUTE');

  // --- auto-correct addition ---
  HUNSPELL_CANDIDATES: array [0..3] of string = (
    'libhunspell-1.7.so.0',
    'libhunspell-1.7.so',
    'libhunspell.so.0',
    'libhunspell.so'
    );
  DEFAULT_EN_AFF = '/usr/share/hunspell/en_US.aff';
  DEFAULT_EN_DIC = '/usr/share/hunspell/en_US.dic';
  DEFAULT_RU_AFF = '/usr/share/hunspell/ru_RU.aff';
  DEFAULT_RU_DIC = '/usr/share/hunspell/ru_RU.dic';
  DEFAULT_AUTOTOGGLE_KEY = 70;    // SCROLLLOCK
  DEFAULT_MIN_WORD_LENGTH = 4;
  DEFAULT_ACTIVE_WINDOW_TOOL = 'kdotool';
  DEFAULT_ACTIVE_WINDOW_TIMEOUT_MS = 200;
  DEFAULT_ACTIVE_WINDOW_CACHE_MS = 400;
  EN_BIGRAM_ALPHABET = 27 * 27;
  RU_BIGRAM_ALPHABET = 34 * 34;
  DEFAULT_BIGRAM_THRESHOLD = 1.2;

var
  DaemonMode: boolean = True;
  AppEventLog: TEventLog = nil;
  E: Exception;

  Key_RPL: word = 0;
  Keys_LS: array of word = nil;
  StrKeys_LS: string = '';

  NeedTrackMouse: boolean = False;
  NeedClearKeyBuf: boolean = False;

  KeyBuf: TKeyBuf;
  BufferAction: TBufferAction = KeepBuffer;

  StopAndExit: boolean = False;

  // --- auto-correct addition ---
  AutoModeStart: boolean = False;      // from config: start with auto-mode on?
  AutoModeActive: boolean = False;     // live toggle state
  Key_AUTOTOGGLE: word = DEFAULT_AUTOTOGGLE_KEY;
  MinWordLength: integer = DEFAULT_MIN_WORD_LENGTH;
  DictEnAff, DictEnDic, DictRuAff, DictRuDic: string;

  HunspellLib: TLibHandle = NilHandle;
  Hunspell_create: THunspellCreate = nil;
  Hunspell_destroy: THunspellDestroy = nil;
  Hunspell_spell: THunspellSpell = nil;
  EnDictHandle: Pointer = nil;
  RuDictHandle: Pointer = nil;
  HunspellReady: boolean = False;

  EnChar, EnCharShift, RuChar, RuCharShift: TCharTable;
  CurrentIsRu: boolean = False;   // best-guess active layout, tracked live
  LS0Down: boolean = False;
  LS1Down: boolean = False;

  ExcludeApps: string = '';               // comma-separated substrings, empty = feature off
  ActiveWindowTool: string = DEFAULT_ACTIVE_WINDOW_TOOL;
  ActiveWindowTimeoutMs: integer = DEFAULT_ACTIVE_WINDOW_TIMEOUT_MS;
  ActiveWindowCacheMs: integer = DEFAULT_ACTIVE_WINDOW_CACHE_MS;
  ActiveWindowUser: string = '';          // Linux username whose session bus to query
  ActiveWindowUid: string = '';           // resolved once at startup from ActiveWindowUser
  LastActiveWindowCheck: TDateTime = 0;
  LastActiveWindowClass: string = '';

  EnBigrams: TBigramCounts = nil;
  RuBigrams: TBigramCounts = nil;
  EnBigramTotal: Int64 = 0;
  RuBigramTotal: Int64 = 0;
  BigramReady: boolean = False;
  BigramThreshold: double = DEFAULT_BIGRAM_THRESHOLD;

  procedure Log(EventType: TEventType; aMessage: string; StdOutputOnly: boolean);
  begin
    if DaemonMode then
    begin
      if not StdOutputOnly then
        AppEventLog.Log(EventType, aMessage);
    end
    else
    begin
      if StdOutputOnly then
        writeln(aMessage)
      else
      begin
        writeln(aMessage);
        AppEventLog.Log(EventType, aMessage);
      end;
    end;
  end;

  // ============================================================
  // --- auto-correct addition: everything below this block, down
  //     to (and including) the "end of auto-correct addition" marker,
  //     is new compared to upstream easy-switcher.
  // ============================================================

  // Physical-key mapping between standard US QWERTY and standard RU
  // (Windows) ЙЦУКЕН layout. Covers letters + the punctuation keys that
  // double as Cyrillic letters ([, ], ;, ', `). Digit row is left
  // identical between tables on purpose - digits rarely decide word
  // validity, and getting the RU shifted-symbol row (!"№;%:?*()) exactly
  // right is not worth the risk of a typo in a table nobody can easily
  // proof-read. BACKSLASH is left as itself for the same reason: its
  // Cyrillic mapping varies by layout variant. If this matters to you,
  // it's a one-line fix per key right here.
  procedure InitCharTables();
    procedure SetKey(code: word; en, enShift, ru, ruShift: UTF8String);
    begin
      EnChar[code] := en;       EnCharShift[code] := enShift;
      RuChar[code] := ru;       RuCharShift[code] := ruShift;
    end;
  var
    i: integer;
  begin
    for i := 0 to 248 do
    begin
      EnChar[i] := '';  EnCharShift[i] := '';
      RuChar[i] := '';  RuCharShift[i] := '';
    end;

    // digit row - identical in both tables, shift-row symbols kept as EN
    // ('cause see comment above)
    SetKey(2, '1', '!', '1', '!');   SetKey(3, '2', '@', '2', '@');
    SetKey(4, '3', '#', '3', '#');   SetKey(5, '4', '$', '4', '$');
    SetKey(6, '5', '%', '5', '%');   SetKey(7, '6', '^', '6', '^');
    SetKey(8, '7', '&', '7', '&');   SetKey(9, '8', '*', '8', '*');
    SetKey(10, '9', '(', '9', '(');  SetKey(11, '0', ')', '0', ')');
    SetKey(12, '-', '_', '-', '_');  SetKey(13, '=', '+', '=', '+');

    // QWERTY row
    SetKey(16, 'q', 'Q', 'й', 'Й');  SetKey(17, 'w', 'W', 'ц', 'Ц');
    SetKey(18, 'e', 'E', 'у', 'У');  SetKey(19, 'r', 'R', 'к', 'К');
    SetKey(20, 't', 'T', 'е', 'Е');  SetKey(21, 'y', 'Y', 'н', 'Н');
    SetKey(22, 'u', 'U', 'г', 'Г');  SetKey(23, 'i', 'I', 'ш', 'Ш');
    SetKey(24, 'o', 'O', 'щ', 'Щ');  SetKey(25, 'p', 'P', 'з', 'З');
    SetKey(26, '[', '{', 'х', 'Х');  SetKey(27, ']', '}', 'ъ', 'Ъ');

    // ASDF row
    SetKey(30, 'a', 'A', 'ф', 'Ф');  SetKey(31, 's', 'S', 'ы', 'Ы');
    SetKey(32, 'd', 'D', 'в', 'В');  SetKey(33, 'f', 'F', 'а', 'А');
    SetKey(34, 'g', 'G', 'п', 'П');  SetKey(35, 'h', 'H', 'р', 'Р');
    SetKey(36, 'j', 'J', 'о', 'О');  SetKey(37, 'k', 'K', 'л', 'Л');
    SetKey(38, 'l', 'L', 'д', 'Д');  SetKey(39, ';', ':', 'ж', 'Ж');
    SetKey(40, '''', '"', 'э', 'Э'); SetKey(41, '`', '~', 'ё', 'Ё');

    SetKey(43, '\', '|', '\', '|');  // see comment above

    // ZXCV row
    SetKey(44, 'z', 'Z', 'я', 'Я');  SetKey(45, 'x', 'X', 'ч', 'Ч');
    SetKey(46, 'c', 'C', 'с', 'С');  SetKey(47, 'v', 'V', 'м', 'М');
    SetKey(48, 'b', 'B', 'и', 'И');  SetKey(49, 'n', 'N', 'т', 'Т');
    SetKey(50, 'm', 'M', 'ь', 'Ь');  SetKey(51, ',', '<', 'б', 'Б');
    SetKey(52, '.', '>', 'ю', 'Ю');  SetKey(53, '/', '?', '.', ',');
  end;

  function LoadHunspell(): boolean;
  var
    i: integer;
  begin
    Result := False;
    HunspellLib := NilHandle;
    for i := 0 to High(HUNSPELL_CANDIDATES) do
    begin
      HunspellLib := LoadLibrary(HUNSPELL_CANDIDATES[i]);
      if HunspellLib <> NilHandle then break;
    end;
    if HunspellLib = NilHandle then
    begin
      Log(etError, 'auto-mode: cannot load libhunspell, is it installed?', False);
      Exit;
    end;

    Pointer(Hunspell_create) := GetProcedureAddress(HunspellLib, 'Hunspell_create');
    Pointer(Hunspell_destroy) := GetProcedureAddress(HunspellLib, 'Hunspell_destroy');
    Pointer(Hunspell_spell) := GetProcedureAddress(HunspellLib, 'Hunspell_spell');
    if (not Assigned(Hunspell_create)) or (not Assigned(Hunspell_destroy)) or
      (not Assigned(Hunspell_spell)) then
    begin
      Log(etError, 'auto-mode: cannot resolve Hunspell symbols.', False);
      Exit;
    end;

    EnDictHandle := Hunspell_create(PChar(DictEnAff), PChar(DictEnDic));
    RuDictHandle := Hunspell_create(PChar(DictRuAff), PChar(DictRuDic));
    if (EnDictHandle = nil) or (RuDictHandle = nil) then
    begin
      Log(etError, 'auto-mode: cannot open dictionary files, check paths in config.', False);
      Exit;
    end;

    Result := True;
  end;

  procedure UnloadHunspell();
  begin
    if Assigned(Hunspell_destroy) then
    begin
      if EnDictHandle <> nil then Hunspell_destroy(EnDictHandle);
      if RuDictHandle <> nil then Hunspell_destroy(RuDictHandle);
    end;
    if HunspellLib <> NilHandle then
      FreeLibrary(HunspellLib);
  end;

  function IsRealWord(handle: Pointer; const word: UTF8String): boolean;
  begin
    Result := (handle <> nil) and (Hunspell_spell(handle, PChar(word)) <> 0);
  end;

  // Resolves a username to a numeric UID via the `id` tool, once, at
  // startup. Not done with the pwd/users fpc package on purpose - that
  // package isn't guaranteed to ship with every distro's plain `fpc`
  // install, whereas `id` is coreutils and always there.
  function ResolveUserUid(const Username: string): string;
  var
    P: TProcess;
    Output: TStringList;
  begin
    Result := '';
    if Trim(Username) = '' then Exit;
    P := TProcess.Create(nil);
    try
      P.Executable := 'id';
      P.Parameters.Add('-u');
      P.Parameters.Add(Username);
      P.Options := [poUsePipes];
      try
        P.Execute;
      except
        Exit;
      end;
      P.WaitOnExit;
      if P.ExitStatus <> 0 then Exit;
      Output := TStringList.Create;
      try
        Output.LoadFromStream(P.Output);
        if Output.Count > 0 then Result := Trim(Output[0]);
      finally
        Output.Free;
      end;
    finally
      P.Free;
    end;
  end;

  // Asks kdotool (or whatever ActiveWindowTool points at) for the focused
  // window's resource class. Runs as a subprocess with a hard timeout, so a
  // hung KWin/DBus round-trip can never freeze the keyboard-reading loop -
  // if it doesn't answer in time we kill it and report failure.
  //
  // This daemon runs as root (upstream's own systemd unit has no User=,
  // just a commented-out suggestion) but kdotool needs to reach KWin over
  // the *session* DBus bus of whoever is actually logged in graphically -
  // a bus root has no address for and, even knowing the address, no
  // standing invitation to join. So when active-window-user/ActiveWindowUid
  // is configured, the call is wrapped through `runuser` into that user's
  // context with the session bus env vars set explicitly; without it, the
  // tool is invoked directly, which only works if this daemon itself is
  // somehow already running as that user (not upstream's default setup,
  // but a valid one if you've rebuilt the service as a --user unit).
  function GetActiveWindowClass(TimeoutMs: integer): string;
  var
    P: TProcess;
    Output: TStringList;
    Waited: integer;
    EnvXdg, EnvBus: string;
  begin
    Result := '';
    P := TProcess.Create(nil);
    try
      if ActiveWindowUid <> '' then
      begin
        EnvXdg := Format('XDG_RUNTIME_DIR=/run/user/%s', [ActiveWindowUid]);
        EnvBus := Format('DBUS_SESSION_BUS_ADDRESS=unix:path=/run/user/%s/bus', [ActiveWindowUid]);
        P.Executable := 'runuser';
        P.Parameters.Add('-u'); P.Parameters.Add(ActiveWindowUser);
        P.Parameters.Add('--');
        P.Parameters.Add('env'); P.Parameters.Add(EnvXdg); P.Parameters.Add(EnvBus);
        P.Parameters.Add(ActiveWindowTool);
        P.Parameters.Add('getactivewindow');
        P.Parameters.Add('getwindowclassname');
      end
      else
      begin
        P.Executable := ActiveWindowTool;
        P.Parameters.Add('getactivewindow');
        P.Parameters.Add('getwindowclassname');
      end;
      P.Options := [poUsePipes];
      try
        P.Execute;
      except
        on E: Exception do
        begin
          Log(etError, Format('auto-mode: cannot run %s (%s)', [P.Executable, E.Message]), False);
          Exit;
        end;
      end;

      Waited := 0;
      while P.Running and (Waited < TimeoutMs) do
      begin
        Sleep(5);
        Inc(Waited, 5);
      end;

      if P.Running then
      begin
        Log(etError, Format('auto-mode: %s timed out after %dms, killing it',
          [ActiveWindowTool, TimeoutMs]), True);
        P.Terminate(9);
        Exit;   // fail closed: caller treats '' as "don't know"
      end;

      if P.ExitStatus <> 0 then Exit;

      Output := TStringList.Create;
      try
        Output.LoadFromStream(P.Output);
        if Output.Count > 0 then
          Result := LowerCase(Trim(Output[0]));
      finally
        Output.Free;
      end;
    finally
      P.Free;
    end;
  end;

  // Same, but only actually shells out at most once per ActiveWindowCacheMs -
  // keeps a burst of short words from spawning a process per word.
  function GetActiveWindowClassCached(): string;
  begin
    if (MilliSecondsBetween(Now, LastActiveWindowCheck) >= ActiveWindowCacheMs) then
    begin
      LastActiveWindowClass := GetActiveWindowClass(ActiveWindowTimeoutMs);
      LastActiveWindowCheck := Now;
    end;
    Result := LastActiveWindowClass;
  end;

  // ExcludeApps is a comma-separated list of substrings (app class names,
  // lowercase); '' means the feature is off (no subprocess ever spawned).
  // On any failure to determine the active window, we fail CLOSED - i.e.
  // treat it as excluded, since the whole point of this check is safety.
  function IsExcludedApp(): boolean;
  var
    ActiveClass, Part: string;
    Parts: TStringArray;
    i: integer;
  begin
    Result := False;
    if Trim(ExcludeApps) = '' then Exit;

    ActiveClass := GetActiveWindowClassCached();
    if ActiveClass = '' then
    begin
      Result := True;   // couldn't tell -> play it safe
      Exit;
    end;

    Parts := ExcludeApps.Split(',');
    for i := 0 to High(Parts) do
    begin
      Part := LowerCase(Trim(Parts[i]));
      if (Part <> '') and (Pos(Part, ActiveClass) > 0) then
      begin
        Result := True;
        Exit;
      end;
    end;
  end;

  // Decodes the word currently sitting at the end of KeyBuf (i.e. right
  // before the SPACE-up event that just triggered this check) into two
  // parallel strings: "what it would read as if EN was active" and
  // "...if RU was active". Purely a peek - never mutates KeyBuf.
  // Backspaces are resolved inline, so mid-word typos the user already
  // fixed don't pollute the result.
  procedure DecodeLastWord(out EnWord, RuWord: UTF8String; out EnChars, RuChars: TCharArray;
    out RawKeyCount: integer);
  var
    i, s: integer;
    ShiftActive: boolean;
  begin
    SetLength(EnChars, 0);
    SetLength(RuChars, 0);
    ShiftActive := False;

    // same cutoff search Convert() uses: most recent SPACE-up, excluding
    // the very last buffer element (that's the trailing space itself)
    s := 0;
    for i := 0 to Length(KeyBuf) - 1 do
      if (KeyBuf[i].value = 0) and (KeyBuf[i].code = KEY_SPACE) and (i <> Length(KeyBuf) - 1) then
        s := i + 1;

    for i := s to Length(KeyBuf) - 1 do
    begin
      if KeyBuf[i].code in Shifts then
      begin
        ShiftActive := (KeyBuf[i].value = 1);
        Continue;
      end;

      if (KeyBuf[i].code = KEY_BACKSPACE) and (KeyBuf[i].value = 1) then
      begin
        if Length(EnChars) > 0 then SetLength(EnChars, Length(EnChars) - 1);
        if Length(RuChars) > 0 then SetLength(RuChars, Length(RuChars) - 1);
        Continue;
      end;

      if (KeyBuf[i].value = 1) and (KeyBuf[i].code in Letters) and (KeyBuf[i].code <> KEY_SPACE) then
      begin
        SetLength(EnChars, Length(EnChars) + 1);
        SetLength(RuChars, Length(RuChars) + 1);
        if ShiftActive then
        begin
          EnChars[High(EnChars)] := EnCharShift[KeyBuf[i].code];
          RuChars[High(RuChars)] := RuCharShift[KeyBuf[i].code];
        end
        else
        begin
          EnChars[High(EnChars)] := EnChar[KeyBuf[i].code];
          RuChars[High(RuChars)] := RuChar[KeyBuf[i].code];
        end;
      end;
    end;

    EnWord := '';
    for i := 0 to High(EnChars) do EnWord := EnWord + EnChars[i];
    RuWord := '';
    for i := 0 to High(RuChars) do RuWord := RuWord + RuChars[i];
    RawKeyCount := Length(EnChars);
  end;

  // Splits a hunspell .dic word list into individual lowercase words,
  // stripping the trailing "/AFFIXFLAGS" hunspell uses. Same file the
  // Hunspell handle already loaded - just read a second time as plain text,
  // no need for anything spell-engine-specific here.
  function LoadWordListForBigrams(const Path: string): TStringList;
  var
    Lines: TStringList;
    i, SlashPos: integer;
    w: string;
  begin
    Result := TStringList.Create;
    if not FileExists(Path) then Exit;
    Lines := TStringList.Create;
    try
      Lines.LoadFromFile(Path);
      for i := 1 to Lines.Count - 1 do   // line 0 is hunspell's word-count header
      begin
        w := Lines[i];
        SlashPos := Pos('/', w);
        if SlashPos > 0 then w := Copy(w, 1, SlashPos - 1);
        w := Trim(w);
        if w <> '' then Result.Add(LowerCase(w));
      end;
    finally
      Lines.Free;
    end;
  end;

  // Minimal UTF-8 character-boundary helpers - no LazUtf8 dependency (that's
  // a Lazarus package, not part of a bare fpc install). Only needs to be
  // correct for our alphabet: single-byte ASCII (^, $, a-z) and two-byte
  // Cyrillic (U+0400 block) - so a 2/3/4-byte branch is enough, no need for
  // full UTF-8 validation.
  function MiniUTF8CharLen(const s: string; BytePos: integer): integer;
  var
    b: byte;
  begin
    b := Ord(s[BytePos]);
    if b < $80 then Result := 1
    else if (b and $E0) = $C0 then Result := 2
    else if (b and $F0) = $E0 then Result := 3
    else if (b and $F8) = $F0 then Result := 4
    else Result := 1;  // malformed lead byte - advance by 1 rather than loop forever
  end;

  function MiniUTF8CharAt(const s: string; BytePos: integer): string;
  begin
    Result := Copy(s, BytePos, MiniUTF8CharLen(s, BytePos));
  end;

  // Builds letter-bigram counts (with ^/$ word-boundary markers, same idea
  // as the Python prototype this was validated against) straight from a
  // dictionary's word list. Not linguistically precise - it's frequency
  // over the *word list*, not a real text corpus - but good enough to tell
  // "typical for this language" from "not", which is all this needs.
  function LoadBigramModel(const DicPath: string; out Counts: TBigramCounts;
    out Total: Int64): boolean;
  var
    Words: TStringList;
    w, ww: string;
    i, p, clen: integer;
    bg: UTF8String;
    cur: Int64;
  begin
    Result := False;
    Total := 0;
    Counts := TBigramCounts.Create;
    Words := LoadWordListForBigrams(DicPath);
    try
      if Words.Count = 0 then Exit;
      for i := 0 to Words.Count - 1 do
      begin
        w := Words[i];
        ww := '^' + w + '$';
        // walk ww by logical (possibly multi-byte) character, not by byte
        p := 1;
        while p < Length(ww) do
        begin
          clen := MiniUTF8CharLen(ww, p);
          bg := MiniUTF8CharAt(ww, p) + MiniUTF8CharAt(ww, p + clen);
          if Counts.TryGetValue(bg, cur) then
            Counts[bg] := cur + 1
          else
            Counts.Add(bg, 1);
          Inc(Total);
          Inc(p, clen);
        end;
      end;
      Result := Total > 0;
    finally
      Words.Free;
    end;
  end;

  // Normalized (per-bigram) log-probability of Chars under a bigram model,
  // Laplace-smoothed so a bigram the model never saw doesn't zero the whole
  // score out - it just costs a small, bounded penalty instead.
  function BigramScore(const Chars: TCharArray; Counts: TBigramCounts;
    Total: Int64; AlphabetSize: integer): double;
  var
    Padded: TCharArray;
    i: integer;
    bg: UTF8String;
    cnt: Int64;
    LogP: double;
  begin
    Result := -999;   // "impossible" sentinel for the degenerate empty case
    if (Counts = nil) or (Total = 0) or (Length(Chars) = 0) then Exit;

    SetLength(Padded, Length(Chars) + 2);
    Padded[0] := '^';
    for i := 0 to High(Chars) do Padded[i + 1] := Chars[i];
    Padded[High(Padded)] := '$';

    LogP := 0;
    for i := 0 to High(Padded) - 1 do
    begin
      bg := Padded[i] + Padded[i + 1];
      if not Counts.TryGetValue(bg, cnt) then cnt := 0;
      LogP := LogP + ln((cnt + 1) / (Total + AlphabetSize));
    end;
    Result := LogP / (Length(Padded) - 1);
  end;

  // The actual decision: should the word that was just finished (ending
  // right before this SPACE) be auto-corrected?
  //
  // Dictionary lookup decides first, same as before, and wins outright:
  // a known word currently on screen is NEVER touched no matter what the
  // statistics say, and a known word in the other reading is corrected
  // exactly as before. Only when NEITHER reading is a real dictionary
  // word do we fall back to letter-typicality (BigramScore) - this is
  // what lets auto-mode react to things like "kubectl" or "gitignore"
  // that no dictionary will ever contain: not by knowing the word, but by
  // recognizing the *shape* of the language, the way upstream Punto
  // Switcher's own "atypical letter sequence" detection does.
  function ShouldAutoCorrect(): boolean;
  var
    EnWord, RuWord: UTF8String;
    EnChars, RuChars: TCharArray;
    RawKeyCount: integer;
    CurrentOk, OtherOk: boolean;
    CurrentScore, OtherScore: double;
  begin
    Result := False;
    if not HunspellReady then Exit;
    if IsExcludedApp() then Exit;

    DecodeLastWord(EnWord, RuWord, EnChars, RuChars, RawKeyCount);
    if RawKeyCount < MinWordLength then Exit;

    if CurrentIsRu then
    begin
      CurrentOk := IsRealWord(RuDictHandle, RuWord);
      OtherOk := IsRealWord(EnDictHandle, EnWord);
    end
    else
    begin
      CurrentOk := IsRealWord(EnDictHandle, EnWord);
      OtherOk := IsRealWord(RuDictHandle, RuWord);
    end;

    if CurrentOk then Exit;              // known word on screen - never touch
    if OtherOk then begin Result := True; Exit; end;  // known word the other way - correct, as before

    // neither reading is a dictionary word - fall back to letter-typicality
    if not BigramReady then Exit;
    if CurrentIsRu then
    begin
      CurrentScore := BigramScore(RuChars, RuBigrams, RuBigramTotal, RU_BIGRAM_ALPHABET);
      OtherScore := BigramScore(EnChars, EnBigrams, EnBigramTotal, EN_BIGRAM_ALPHABET);
    end
    else
    begin
      CurrentScore := BigramScore(EnChars, EnBigrams, EnBigramTotal, EN_BIGRAM_ALPHABET);
      OtherScore := BigramScore(RuChars, RuBigrams, RuBigramTotal, RU_BIGRAM_ALPHABET);
    end;

    Result := (OtherScore - CurrentScore) > BigramThreshold;
  end;

  // ============================================================
  // --- end of auto-correct addition ---
  // ============================================================

  procedure RunInstall();
  var
    UnitFile: TIniFile = nil;
  begin
    DaemonMode := False;
    try
      Log(etInfo, 'Installing Easy Switcher daemon...', False);
      UnitFile := TIniFile.Create(SYSTEMD_UNIT_FILE, []);
      UnitFile.WriteString('Unit', 'Description',
        'Easy Switcher - keyboard layout switcher');
      UnitFile.WriteString('Unit', 'Requires', 'local-fs.target');
      UnitFile.WriteString('Unit', 'After', 'local-fs.target');
      UnitFile.WriteString('Unit', 'StartLimitIntervalSec', '10');
      UnitFile.WriteString('Unit', 'StartLimitBurst', '3');
      UnitFile.WriteString('Service', 'Type', 'simple');
      UnitFile.WriteString('Service', 'ExecStart', ParamStr(0) + ' -r');
      UnitFile.WriteString('Service', '#User', 'easy-switcher');
      UnitFile.WriteString('Service', 'Restart', 'on-failure');
      UnitFile.WriteString('Service', 'RestartSec', '3');
      UnitFile.WriteString('Install', 'WantedBy', 'sysinit.target ');
      Log(etInfo, Format('Easy Switcher daemon successfully installed, version: %s',
        [EASY_SWITCHER_VERSION]), False);
      if Assigned(UnitFile) then
        FreeAndNil(UnitFile);
    except
      on E: Exception do
      begin
        Log(etError, Format('Error creating systemd control file. %s. Are you root?', [E.Message]), False);
        if Assigned(UnitFile) then
          FreeAndNil(UnitFile);
      end;
    end;
  end;

  procedure RunUninstall();
  begin
    DaemonMode := False;
    Log(etInfo, 'Uninstalling Easy Switcher daemon...', False);
    if FileExists(SYSTEMD_UNIT_FILE) then
      if DeleteFile(SYSTEMD_UNIT_FILE) then
        Log(etInfo, 'Easy Switcher daemon is successfully uninstalled.', False)
      else
        Log(etError, Format('Error removing systemd control file %s. Are you root?',
          [SYSTEMD_UNIT_FILE]), False)
    else
      Log(etError, Format('Nothing to uninstall. Unit file not found %s.', [SYSTEMD_UNIT_FILE]), False);
  end;

  function KeyboardDetectThread(ptr: Pointer): ptrint;
  var
    KeyboardPath: string = '';
    KeyboardFD: longint = -1;
    KeyIE: input_event;
    ioRes: int64 = -1;
    i: integer = 0;
  begin
    KeyIE := Default(input_event);
    KeyboardPath := KeyboardDetectInfo(ptr^).Path;
    KeyboardFD := fpOpen(KeyboardPath, O_RDONLY);
    if KeyboardFD <> -1 then
    begin
      while i < 5700 do //waiting a lil bit less than 60 seconds
      begin
        ioRes := fpRead(KeyboardFD, KeyIE, SizeOf(KeyIE));
        if (ioRes = SizeOf(KeyIE)) then
        begin
          if ((KeyIE.ie_type = 1) and ((KeyIE.code = KEY_ENTER) or (KeyIE.code = KEY_KPENTER)) and
            (KeyIE.value in [0, 1, 2])) then
          begin
            KeyboardDetectInfo(ptr^).active := True;
            break;
          end;
        end;
        sleep(10);
      end;
      FpClose(KeyboardFD);
    end;
    Result := 0;
  end;

  procedure RunConfig();
  var
    ConfigIniFile: TIniFile = nil;  //TInifile to read config
    Config: TStringList = nil;
    //TStringList to save config, instead of TInifile to preserve #comments
    KeyboardPath: string = '';
    MousePath: string = '/dev/input/mice';
    ReverseMode: boolean = False;
    Delay: integer = 10;
    SRec: TSearchRec;
    KeyboardList: TKeyboardList;
    i: integer = 0;
    k: integer = 0;
    KeyboardFD: longint = -1;
    ioRes: int64 = -1;
    KeyIE: input_event;
  begin
    DaemonMode := False;
    KeyboardList := Default(TKeyboardList);
    SRec := Default(TSearchRec);
    KeyIE := Default(input_event);

    Log(etInfo, 'Easy Switcher keyboard configuration started.', False);
    Log(etInfo, 'Trying to read existing config file...', True);
    if ForceDirectories(ExtractFileDir(CONFIG_FILE)) then
    begin
      try
        ConfigIniFile := TIniFile.Create(CONFIG_FILE, [ifoStripQuotes]);
        MousePath := ConfigIniFile.ReadString('Easy Switcher', 'mouse', '/dev/input/mice');
        ReverseMode := StrToBool(ConfigIniFile.ReadString('Easy Switcher', 'reverse-mode', 'False'));
        Delay := ConfigIniFile.ReadInteger('Easy Switcher', 'delay', 10);
        Log(etInfo, 'Done.', True);
        if Assigned(ConfigIniFile) then
          FreeAndNil(ConfigIniFile);
      except
        on E: Exception do
        begin
          Log(etInfo, Format('Error reading config file, Easy Switcher will create new one. %s',
            [E.Message]), False);
          if Assigned(ConfigIniFile) then
            FreeAndNil(ConfigIniFile);
        end;
      end;

      Log(etInfo, '', True);
      Log(etInfo, 'Easy Switcher will try to detect your keyboard automatically.', True);
      sleep(100);
      if FindFirst(INPUT_DEVICES_DIR + 'event*', faAnyFile, SRec) = 0 then
      begin
        repeat
          with SRec do
          begin
            if (Attr and faDirectory) <> 0 then
              continue;

            if (fpOpen((INPUT_DEVICES_DIR + Name), O_RDONLY or O_NONBLOCK) = -1) then
              continue;

            SetLength(KeyboardList, Length(KeyboardList) + 1);
            KeyboardList[i].id := i;
            KeyboardList[i].Active := False;
            KeyboardList[i].path := INPUT_DEVICES_DIR + Name;
            Inc(i);
          end;
        until FindNext(SRec) <> 0;
        FindClose(SRec);
      end;

      if Length(KeyboardList) > 0 then
      begin
        for i := 0 to Length(KeyboardList) - 1 do
        begin
          BeginThread(@KeyboardDetectThread, @(KeyboardList[i]));
        end;
        Log(etInfo, 'Please press ENTER...', True);
        ReadLn();

        i := 0;
        k := 0;
        for k := 0 to 600 do  //waiting for about 60 seconds
        begin
          sleep(100);
          for i := 0 to Length(KeyboardList) - 1 do
          begin
            if KeyboardList[i].Active then
            begin
              KeyboardPath := KeyboardList[i].path;
              break;
            end;
          end;
          if KeyboardPath <> '' then
            break;
        end;
        if KeyboardPath <> '' then
        begin
          Log(etInfo, Format('Found keyboard at %s', [KeyboardPath]), True);
          Log(etInfo, '', True);
          Sleep(500);
          KeyboardFD := fpOpen(KeyboardPath, O_RDONLY or O_SYNC);
          if KeyboardFD <> -1 then
          begin
            Log(etInfo, 'Press the key or combination of keys that changes layout in your system.', True);
            Log(etInfo, 'Waiting for your input...', True);
            i := 0;
            while i < 6000 do
            begin
              ioRes := 0;
              ioRes := fpRead(KeyboardFD, KeyIE, SizeOf(KeyIE));
              if (ioRes = SizeOf(KeyIE)) then
              begin
                if ((KeyIE.ie_type = EV_KEY) and (KeyIE.value in [0, 1])) then
                begin
                  SetLength(Keys_LS, Length(Keys_LS) + 1);
                  Keys_LS[Length(Keys_LS) - 1] := KeyIE.code;
                  if Length(Keys_LS) = 2 then
                  begin
                    if KeyIE.value = 0 then
                    begin
                      StrKeys_LS := IntToStr(Keys_LS[0]);
                    end
                    else
                    begin
                      StrKeys_LS := Format('%d+%d', [Keys_LS[0], Keys_LS[1]]);
                    end;
                    break;
                  end;
                end;
              end;
              sleep(10);
              Inc(i);
            end;
            if Length(Keys_LS) <> 0 then
            begin
              if SScanf(StrKeys_LS, '%d+%d', [@Keys_LS[0], @Keys_LS[1]]) = 1 then
              begin
                Log(etInfo, Format('Key %s captured', [KeyName[Keys_LS[0]]]), True);
                Log(etInfo, '', True);
              end
              else
              begin
                Log(etInfo, Format('Key combination %s+%s captured',
                  [KeyName[Keys_LS[0]], KeyName[Keys_LS[1]]]), True);
                Log(etInfo, '', True);
              end;
            end
            else
            begin
              Log(etError, 'Error reading the keyboard.', False);
              Halt(1);
            end;

            sleep(500);
            fpClose(KeyboardFD);
            KeyboardFD := fpOpen(KeyboardPath, O_RDONLY or O_SYNC);

            Log(etInfo, 'Press the key you will use to correct the text you have entered.', True);
            Log(etInfo, 'Waiting for your input...', True);
            i := 0;
            while i < 6000 do
            begin
              ioRes := 0;
              ioRes := fpRead(KeyboardFD, KeyIE, SizeOf(KeyIE));
              if (ioRes = SizeOf(KeyIE)) then
              begin
                if ((KeyIE.ie_type = 1) and (KeyIE.value = 1)) then
                begin
                  Key_RPL := KeyIE.code;
                  break;
                end;
              end;
              sleep(10);
              Inc(i);
            end;

            if Key_RPL <> 0 then
            begin
              Log(etInfo, Format('Key %s captured', [KeyName[Key_RPL]]), True);
              Log(etInfo, '', True);
            end
            else
            begin
              Log(etError, 'Error reading the keyboard.', False);
              Halt(1);
            end;

            FpClose(KeyboardFD);
            sleep(500);

            Log(etInfo, 'Writing configuration file...', True);
            try
              Config := TStringList.Create;
              Config.Add('[Easy Switcher]');
              Config.Add('# This is Easy Switcher config file.');
              Config.Add('');
              Config.Add('# Keyboard device path.');
              Config.Add('# Run ''~$ hwinfo --keyboard --short'' to get the list of your keyboard devices.');
              Config.Add('# keyboard="/dev/input/event2"');
              Config.Add('');
              Config.Add('keyboard="' + KeyboardPath + '"');
              Config.Add('');
              Config.Add('');
              Config.Add('# Mouse device path.');
              Config.Add('# Run ''~$ hwinfo --mouse --short'' to get the list of your mouse devices.');
              Config.Add('# mouse="/dev/input/mice"');
              Config.Add('');
              Config.Add('mouse="' + MousePath + '"');
              Config.Add('');
              Config.Add('');
              Config.Add('# Scancode of the key or combination of keys used to');
              Config.Add('# switch the layout in your system.');
              Config.Add('# Run ''~$ sudo showkey'' to find out your key scancodes.');
              Config.Add('# layout-switch-key=125');
              Config.Add('# layout-switch-key=29+42');
              Config.Add('');
              Config.Add('layout-switch-key=' + StrKeys_LS);
              Config.Add('');
              Config.Add('');
              Config.Add('# Scancode of the key to correct the text you have entered.');
              Config.Add('# Key combinations are not supported.');
              Config.Add('# PAUSE/BREAK key is used by default.');
              Config.Add('# Run ''~$ sudo showkey'' to find out your key scancodes.');
              Config.Add('# replace-key=119');
              Config.Add('');
              Config.Add('replace-key=' + IntToStr(Key_RPL));
              Config.Add('');
              Config.Add('');
              Config.Add('# If reverse-mode is false, pressing <replace-key> corrects');
              Config.Add('# only last word you have entered. Pressing Shift + <replace-key> corrects');
              Config.Add('# the whole phrase.');
              Config.Add('# If reverse-mode is true, pressing <replace-key> corrects');
              Config.Add('# the whole phrase you have entered, and Shift + <replace-key> corrects');
              Config.Add('# only the last word.');
              Config.Add('# Default reverse-mode value is false');
              Config.Add('# reverse-mode=false');
              Config.Add('');
              Config.Add('reverse-mode=' + BoolToStr(ReverseMode, True) + '');
              Config.Add('');
              Config.Add('');
              Config.Add('# Easy Switcher uses a delay to wait for your system to process the actions.');
              Config.Add('# The smaller delay is, the faster Easy Switcher works.');
              Config.Add('# However, your desktop environment may not be able to handle');
              Config.Add('# Easy Switcher output in a timely manner and you will get errors.');
              Config.Add('# Try to increase the delay if you get messy output.');
              Config.Add('# Default delay value is 10');
              Config.Add('# delay=10');
              Config.Add('');
              Config.Add('delay=' + IntToStr(Delay));
              Config.SaveToFile(CONFIG_FILE);
              Log(etInfo, 'Keyboard configuration successfully saved.', False);
              Log(etInfo, Format('See %s to edit additional parameters.', [CONFIG_FILE]), False);
              if Assigned(Config) then
                FreeAndNil(Config);
            except
              on E: Exception do
              begin
                Log(etError, Format('Error writing configuration file %s %s', [CONFIG_FILE, StrError(errno)]), False);
                if Assigned(Config) then
                  FreeAndNil(Config);
              end;
            end;
          end
          else
          begin
            Log(etError, 'Error attaching to keyboard.', False);
            Halt(1);
          end;
        end
        else
        begin
          Log(etError, 'Couldn''t capture your keypress. Are you root?', False);
          Halt(1);
        end;
      end
      else
      begin
        Log(etError, 'No input devices found. Are you root?', False);
        Halt(1);
      end;
    end
    else
    begin
      Log(etError, Format('Cannot create directory %s', [ExtractFilePath(CONFIG_FILE)]), False);
      Halt(1);
    end;
  end;

  procedure SignalHandler(aSignal: longint); cdecl;
  begin
    case aSignal of
      SIGTERM, SIGQUIT, SIGINT, SIGHUP:
      begin
        Log(etInfo, Format('Got signal to exit (%d). Bye.', [aSignal]), False);
        StopAndExit := True;
      end;
    end;
  end;

  function TrackMouseThread(PMouseFD: pointer): ptrint;
  var
    MouseData: array [0..2] of byte = (0, 0, 0);
    LeftBtn, MiddleBtn, RightBtn: integer;
    ioRes: int64 = -1;
  begin
    while not StopAndExit do
    begin
      ioRes := fpRead(PtrInt(PMouseFD^), MouseData, SizeOf(MouseData));
      if NeedTrackMouse then
      begin
        if ioRes = SizeOf(MouseData) then
        begin
          LeftBtn := MouseData[0] and $1;
          RightBtn := MouseData[0] and $2;
          MiddleBtn := MouseData[0] and $4;
          if (LeftBtn > 0) or (RightBtn > 0) or (MiddleBtn > 0) then
          begin
            Log(etInfo, 'mouse click', True);
            Log(etInfo, 'buffer clearing queued', True);
            NeedTrackMouse := False;
            NeedClearKeyBuf := True;
          end;
        end;
      end;
    end;
    Result := 0;
  end;

  procedure Run();
  var
    i: integer = 0;
    NewAct, OldAct: SigactionRec;
    ConfigIniFile: TIniFile = nil;
    KeyboardPath: string = '';
    MousePath: string = '';
    ReverseMode: boolean = False;
    Delay: integer = 10;
    ioRes: int64 = -1;
    KeyboardFD: longint = -1;
    vKeyboardFD: longint = -1;
    MouseFD: longint = -1;
    vKeyboardSetup: uinput_setup;
    KeyIE: input_event;
    KeyAction: array [0..2] of string = ('up', 'down', 'autorepeat');

    function GetBufferAction(): TBufferAction;
    var
      Last: integer = -1;
    begin
      Last := Length(KeyBuf) - 1;

      if Length(KeyBuf) < 2 then Exit(KeepBuffer);

      if Length(KeyBuf) < 4 then
        if (KeyBuf[Last].code = Key_RPL) and (KeyBuf[Last].value = 0) and
          (KeyBuf[Last - 1].code = Key_RPL) and (KeyBuf[Last - 1].value = 1) then
          Exit(ReplaceWord)
        else
          Exit(KeepBuffer);

      if (KeyBuf[Last].code = Key_RPL) and (KeyBuf[Last].value = 0) and (KeyBuf[Last - 1].code in Shifts) and
        (KeyBuf[Last - 1].value = 0) and (KeyBuf[Last - 2].code = Key_RPL) and
        (KeyBuf[Last - 2].value = 1) and (KeyBuf[Last - 3].code in Shifts) and (KeyBuf[Last - 3].value = 1) then
        Exit(ReplaceAll)  //shiftd rpld shiftu rplu
      else
      if (KeyBuf[Last].code = Key_RPL) and (KeyBuf[Last].value = 0) and (KeyBuf[Last - 1].code = Key_RPL) and
        (KeyBuf[Last - 1].value = 1) then
        if (KeyBuf[Last - 2].code in Shifts) and (KeyBuf[Last - 2].value = 1) then
          Exit(ReplaceAll)  //shiftd rpld rplu
        else
          Exit(ReplaceWord);  //rpld rplu

      Result := KeepBuffer;
    end;

    function GetBufferStr(): string;
    var
      i: integer;
    begin
      Result := '';
      for i := 0 to Length(KeyBuf) - 1 do
        Result := Result + Format('%s %s; ', [KeyName[KeyBuf[i].code], KeyAction[KeyBuf[i].value]]);
    end;

    procedure PrepareBuffer();
    var
      iBuf: array of input_event = nil;
      oBuf: array of input_event = nil;
      i: integer = 0;
      k: integer = 0;
      Last: integer = 0;
    begin
      //copy everything to iBuf and clear KeyBuf
      for i := 0 to Length(KeyBuf) - 1 do
      begin
        SetLength(iBuf, i + 1);
        iBuf[i] := KeyBuf[i];
      end;
      SetLength(KeyBuf, 0);

      //get rid of replace keys
      Last := Length(iBuf) - 1;
      if (iBuf[Last].code = Key_RPL) and (iBuf[Last].value = 0) and (iBuf[Last - 1].code in Shifts) and
        (iBuf[Last - 1].value = 0) and (iBuf[Last - 2].code = Key_RPL) and (iBuf[Last - 2].value = 1) and
        (iBuf[Last - 3].code in Shifts) and (iBuf[Last - 3].value = 1) then
        Last := Last - 4
      else if (iBuf[Last].code = Key_RPL) and (iBuf[Last].value = 0) and (iBuf[Last - 1].code = Key_RPL) and
        (iBuf[Last - 1].value = 1) then
        if (iBuf[Last - 2].code in Shifts) and (iBuf[Last - 2].value = 1) then
          Last := Last - 3
        else
          Last := Last - 2;
      for i := 0 to Last do
      begin
        SetLength(oBuf, i + 1);
        oBuf[i] := iBuf[i];
      end;

      SetLength(iBuf, 0);
      for i := 0 to Length(oBuf) - 1 do
      begin
        SetLength(iBuf, i + 1);
        iBuf[i] := oBuf[i];
      end;
      SetLength(oBuf, 0);

      //cut of last line only
      k := 0;
      for i := 0 to Length(iBuf) - 1 do
      begin
        if ((iBuf[i].code = KEY_ENTER) or (iBuf[i].code = KEY_KPENTER)) and (iBuf[i].value = 0) and
          (i <> Length(iBuf) - 1) then
        begin
          k := 0;
          SetLength(oBuf, k);
        end
        else
        begin
          SetLength(oBuf, k + 1);
          oBuf[k] := iBuf[i];
          k += 1;
        end;
      end;

      SetLength(iBuf, 0);
      for i := 0 to Length(oBuf) - 1 do
      begin
        SetLength(iBuf, i + 1);
        iBuf[i] := oBuf[i];
      end;
      SetLength(oBuf, 0);


      //get rid of shiftdown-shiftup
      k := 0;
      for i := 0 to Length(iBuf) - 1 do
      begin
        if (iBuf[i].code in Shifts) and (k > 0) then
        begin
          if (oBuf[k - 1].code in Shifts) then
          begin
            SetLength(oBuf, k - 1);
            k -= 1;
          end
          else
          begin
            SetLength(oBuf, k + 1);
            oBuf[k] := iBuf[i];
            k += 1;
          end;
        end
        else
        begin
          SetLength(oBuf, k + 1);
          oBuf[k] := iBuf[i];
          k += 1;
        end;
      end;

      SetLength(iBuf, 0);
      for i := 0 to Length(oBuf) - 1 do
      begin
        SetLength(iBuf, i + 1);
        iBuf[i] := oBuf[i];
      end;
      SetLength(oBuf, 0);

      //get rid of BS if any
      k := 0;
      for i := 0 to Length(iBuf) - 1 do
      begin
        if (iBuf[i].code = KEY_BACKSPACE) then
        begin
          if k = 0 then
            continue    //leading
          else
          begin
            k -= 1;
            if oBuf[k].code in Shifts then
              oBuf[k - 1] := oBuf[k];
            SetLength(oBuf, k);    //inline
          end;
        end
        else
        begin
          SetLength(oBuf, k + 1);
          oBuf[k] := iBuf[i];
          k += 1;
        end;
      end;

      //fill in prepared buffer back
      for i := 0 to Length(oBuf) - 1 do
      begin
        SetLength(KeyBuf, i + 1);
        KeyBuf[i] := oBuf[i];
      end;

      sleep(10);
    end;

    procedure Convert(SingleWord: boolean);
    var
      EmitBuf: TEmitBuf;  //static array to emit keys with key+syn
      IEBuf: array of input_event = nil;           //output buffer
      n: integer = 0;
      k: integer = 0;
      s: integer = 0;
      IETime: timeval;
    begin
      EmitBuf := Default(TEmitBuf);
      IETime := Default(timeval);
      clock_gettime(0, @IETime);   //emulating time to preserve key order
      IETime.tv_usec := 0;

      SetLength(IEBuf, 0);

      if SingleWord then
      begin
        for n := 0 to Length(KeyBuf) - 1 do
        begin
          if (KeyBuf[n].value = 0) and (KeyBuf[n].code = KEY_SPACE) and (n <> Length(KeyBuf) - 1) then
          begin
            s := n + 1; //set the conversion limit by SPACE UP
          end;
        end;
      end;

      for n := s to Length(KeyBuf) - 1 do
        if (KeyBuf[n].value in [1, 2]) and (not (KeyBuf[n].code in Shifts)) then
        begin
          k := Length(IEBuf);           //BS down
          SetLength(IEBuf, k + 1);
          IEBuf[k].ie_type := EV_KEY;
          IEBuf[k].code := KEY_BACKSPACE;
          IEBuf[k].value := 1;
          IEBuf[k].time.tv_sec := IETime.tv_sec;
          IEBuf[k].time.tv_usec := IETime.tv_usec;
          IETime.tv_usec := IETime.tv_usec + 200;

          k := Length(IEBuf);           //BS up
          SetLength(IEBuf, k + 1);
          IEBuf[k].ie_type := EV_KEY;
          IEBuf[k].code := KEY_BACKSPACE;
          IEBuf[k].value := 0;
          IEBuf[k].time.tv_sec := IETime.tv_sec;
          IEBuf[k].time.tv_usec := IETime.tv_usec;
          IETime.tv_usec := IETime.tv_usec + 200;
        end;

      k := Length(IEBuf);               //layout change down
      SetLength(IEBuf, k + 1);
      IEBuf[k].ie_type := EV_KEY;
      IEBuf[k].code := Keys_LS[0];
      IEBuf[k].value := 1;
      IEBuf[k].time.tv_sec := IETime.tv_sec;
      IEBuf[k].time.tv_usec := IETime.tv_usec;
      IETime.tv_usec := IETime.tv_usec + 200;

      if Length(Keys_LS) = 2 then
      begin
        k := Length(IEBuf);               //layout change down if combination
        SetLength(IEBuf, k + 1);
        IEBuf[k].ie_type := EV_KEY;
        IEBuf[k].code := Keys_LS[1];
        IEBuf[k].value := 1;
        IEBuf[k].time.tv_sec := IETime.tv_sec;
        IEBuf[k].time.tv_usec := IETime.tv_usec;
        IETime.tv_usec := IETime.tv_usec + 200;

        k := Length(IEBuf);               //layout change up if combination
        SetLength(IEBuf, k + 1);
        IEBuf[k].ie_type := EV_KEY;
        IEBuf[k].code := Keys_LS[1];
        IEBuf[k].value := 0;
        IEBuf[k].time.tv_sec := IETime.tv_sec;
        IEBuf[k].time.tv_usec := IETime.tv_usec;
        IETime.tv_usec := IETime.tv_usec + 200;
      end;

      k := Length(IEBuf);                 //layout change up
      SetLength(IEBuf, k + 1);
      IEBuf[k].ie_type := EV_KEY;
      IEBuf[k].code := Keys_LS[0];
      IEBuf[k].value := 0;
      IEBuf[k].time.tv_sec := IETime.tv_sec;
      IEBuf[k].time.tv_usec := IETime.tv_usec;
      IETime.tv_usec := IETime.tv_usec + 200;


      //writing to the intermediate buffer
      for n := s to Length(KeyBuf) - 1 do
      begin
        k := Length(IEBuf);            //key
        SetLength(IEBuf, k + 1);
        IEBuf[k].ie_type := EV_KEY;
        IEBuf[k].code := KeyBuf[n].code;
        IEBuf[k].value := KeyBuf[n].value;
        IEBuf[k].time.tv_sec := IETime.tv_sec;
        IEBuf[k].time.tv_usec := IETime.tv_usec;
        IETime.tv_usec := IETime.tv_usec + 200;
      end;

      //intermediate buffer ready, emitting
      for n := 0 to Length(IEBuf) - 1 do
      begin
        EmitBuf[1] := IEBuf[n];
        EmitBuf[2].ie_type := EV_SYN;
        EmitBuf[2].code := SYN_REPORT;
        EmitBuf[2].value := 0;
        EmitBuf[2].time.tv_sec := IEBuf[n].time.tv_sec;
        EmitBuf[2].time.tv_usec := IEBuf[n].time.tv_usec + 100;

        fpWrite(vKeyboardFD, EmitBuf[1], sizeof(EmitBuf[1]) * 2);
        Log(etInfo, Format('output %s %s', [KeyName[EmitBuf[1].code], KeyAction[EmitBuf[1].value]]), True);
        Sleep(Delay);
      end;
    end;

  begin
    if DaemonMode then
      Log(etInfo, Format('Starting Easy Switcher v%s...', [EASY_SWITCHER_VERSION]), False)
    else
      Log(etInfo, Format('Starting Easy Switcher v%s in debug mode...', [EASY_SWITCHER_VERSION]), False);

    //Init variables
    NewAct := Default(SigactionRec);
    OldAct := Default(SigactionRec);
    KeyIE := Default(input_event);
    KeyBuf := Default(TKeyBuf);
    SetLength(Keys_LS, 2);
    vKeyboardSetup := Default(uinput_setup);
    vKeyboardSetup.id.bustype := BUS_USB;
    vKeyboardSetup.id.vendor := $0777;
    vKeyboardSetup.id.product := $0777;
    vKeyboardSetup.name := 'Easy Switcher virtual input device';

    //Set signal processing handlers
    Log(etInfo, 'Setting up signal handlers...', True);
    NewAct.sa_handler := SigactionHandler(@SignalHandler);
    ioRes := fpSigaction(SIGHUP, @NewAct, @OldAct);
    ioRes += fpSigaction(SIGINT, @NewAct, @OldAct);
    ioRes += fpSigaction(SIGQUIT, @NewAct, @OldAct);
    ioRes += fpSigaction(SIGTERM, @NewAct, @OldAct);
    if ioRes <> 0 then
    begin
      Log(etError, 'Error setting up signal handlers.', False);
      Halt(1);
    end;
    Log(etInfo, 'Done.', True);
    ioRes := 0;

    //read config
    Log(etInfo, 'Reading config...', True);
    if FileExists(CONFIG_FILE) then
    begin
      try
        ConfigIniFile := TIniFile.Create(CONFIG_FILE, [ifoStripQuotes]);
        KeyboardPath := ConfigIniFile.ReadString('Easy Switcher', 'keyboard', '~');
        MousePath := ConfigIniFile.ReadString('Easy Switcher', 'mouse', '~');
        StrKeys_LS := ConfigIniFile.ReadString('Easy Switcher', 'layout-switch-key', '-1');
        Key_RPL := StrToInt(ConfigIniFile.ReadString('Easy Switcher', 'replace-key', '0'));
        ReverseMode := StrToBool(ConfigIniFile.ReadString('Easy Switcher', 'reverse-mode', 'False'));
        Delay := StrToInt(ConfigIniFile.ReadString('Easy Switcher', 'delay', '10'));
        SetLength(Keys_LS, SScanf(StrKeys_LS, '%d+%d', [@Keys_LS[0], @Keys_LS[1]]));

        // --- auto-correct addition: extra config keys, all optional ---
        Key_AUTOTOGGLE := StrToIntDef(ConfigIniFile.ReadString('Easy Switcher',
          'auto-mode-key', IntToStr(DEFAULT_AUTOTOGGLE_KEY)), DEFAULT_AUTOTOGGLE_KEY);
        AutoModeStart := StrToBool(ConfigIniFile.ReadString('Easy Switcher', 'auto-mode-start', 'False'));
        MinWordLength := StrToIntDef(ConfigIniFile.ReadString('Easy Switcher',
          'min-word-length', IntToStr(DEFAULT_MIN_WORD_LENGTH)), DEFAULT_MIN_WORD_LENGTH);
        DictEnAff := ConfigIniFile.ReadString('Easy Switcher', 'dict-en-aff', DEFAULT_EN_AFF);
        DictEnDic := ConfigIniFile.ReadString('Easy Switcher', 'dict-en-dic', DEFAULT_EN_DIC);
        DictRuAff := ConfigIniFile.ReadString('Easy Switcher', 'dict-ru-aff', DEFAULT_RU_AFF);
        DictRuDic := ConfigIniFile.ReadString('Easy Switcher', 'dict-ru-dic', DEFAULT_RU_DIC);
        CurrentIsRu := (LowerCase(ConfigIniFile.ReadString('Easy Switcher', 'start-layout', 'en')) = 'ru');

        // --- active-window addition ---
        ExcludeApps := ConfigIniFile.ReadString('Easy Switcher', 'exclude-apps', '');
        ActiveWindowTool := ConfigIniFile.ReadString('Easy Switcher', 'active-window-tool', DEFAULT_ACTIVE_WINDOW_TOOL);
        ActiveWindowTimeoutMs := StrToIntDef(ConfigIniFile.ReadString('Easy Switcher',
          'active-window-timeout-ms', IntToStr(DEFAULT_ACTIVE_WINDOW_TIMEOUT_MS)), DEFAULT_ACTIVE_WINDOW_TIMEOUT_MS);
        ActiveWindowCacheMs := StrToIntDef(ConfigIniFile.ReadString('Easy Switcher',
          'active-window-cache-ms', IntToStr(DEFAULT_ACTIVE_WINDOW_CACHE_MS)), DEFAULT_ACTIVE_WINDOW_CACHE_MS);
        BigramThreshold := StrToFloatDef(ConfigIniFile.ReadString('Easy Switcher',
          'bigram-threshold', FloatToStr(DEFAULT_BIGRAM_THRESHOLD)), DEFAULT_BIGRAM_THRESHOLD);
        ActiveWindowUser := ConfigIniFile.ReadString('Easy Switcher', 'active-window-user', '');

        if Assigned(ConfigIniFile) then
          FreeAndNil(ConfigIniFile);
        if ((KeyboardPath = '~') or (MousePath = '~') or (Length(Keys_LS) = 0) or (KEY_RPL = 0)) then
        begin
          Log(etError, 'Error parsing config file.', False);
          Halt(1);
        end;
      except
        on E: Exception do
        begin
          Log(etInfo, Format('Error reading config file. %s', [E.Message]), False);
          if Assigned(ConfigIniFile) then
            FreeAndNil(ConfigIniFile);
          Halt(1);
        end;
      end;
    end
    else
    begin
      Log(etError, Format('Missing config file %s, run ''easy-switcher -c'' to configure.', [CONFIG_FILE]), False);
      Halt(1);
    end;
    Log(etInfo, 'Done.', True);

    // --- auto-correct addition ---
    InitCharTables();
    HunspellReady := LoadHunspell();
    if HunspellReady then
      Log(etInfo, Format('auto-mode: dictionaries loaded, toggle key is %s.',
        [KeyName[Key_AUTOTOGGLE]]), False)
    else
      Log(etError, 'auto-mode: unavailable this session (see error above). ' +
        'Manual correction still works normally.', False);
    AutoModeActive := AutoModeStart and HunspellReady;
    Log(etInfo, Format('auto-mode: starting %s.', [BoolToStr(AutoModeActive, 'ON', 'OFF')]), False);

    BigramReady := LoadBigramModel(DictEnDic, EnBigrams, EnBigramTotal) and
      LoadBigramModel(DictRuDic, RuBigrams, RuBigramTotal);
    if BigramReady then
      Log(etInfo, Format('auto-mode: bigram fallback ready (%d/%d en/ru bigrams, threshold %.2f).',
        [EnBigrams.Count, RuBigrams.Count, BigramThreshold]), False)
    else
      Log(etError, 'auto-mode: bigram fallback unavailable, dictionary-only detection still works.', False);

    if Trim(ExcludeApps) <> '' then
    begin
      if Trim(ActiveWindowUser) = '' then
        Log(etError, 'auto-mode: exclude-apps is set but active-window-user is not. ' +
          'This daemon runs as root, so ' + ActiveWindowTool + ' almost certainly ' +
          'cannot reach your session DBus bus this way - every check will fail closed, ' +
          'meaning auto-mode will silently never correct anything. Set active-window-user ' +
          'to your login username.', False)
      else
      begin
        ActiveWindowUid := ResolveUserUid(ActiveWindowUser);
        if ActiveWindowUid = '' then
          Log(etError, Format('auto-mode: could not resolve uid for active-window-user=%s ' +
            '- exclude-apps will fail closed on every check.', [ActiveWindowUser]), False)
        else
          Log(etInfo, Format('auto-mode: active-window checks will run as %s (uid %s) via runuser.',
            [ActiveWindowUser, ActiveWindowUid]), False);
      end;
    end;

    //start keyboard reading
    Log(etInfo, 'Opening keyboard...', True);
    KeyboardFD := fpOpen(KeyboardPath, O_RDONLY or O_SYNC);
    if KeyboardFD = -1 then
    begin
      Log(etError, Format('Cannot open %s %s', [KeyboardPath, StrError(errno)]), False);
      Halt(1);
    end;
    Log(etInfo, 'Done.', True);

    //install virtual keyboard
    Log(etInfo, 'Installing virtual keyboard...', True);
    vKeyboardFD := fpOpen(UINPUT_FILE, O_WRONLY or O_SYNC);   // or O_NONBLOCK
    if vKeyboardFD = -1 then
    begin
      Log(etError, Format('Cannot open %s %s', [UINPUT_FILE, StrError(errno)]), False);
      Halt(1);
    end;
    ioRes += fpIOCtl(vKeyboardFD, UI_SET_EVBIT, Pointer(EV_SYN));
    ioRes += fpIOCtl(vKeyboardFD, UI_SET_EVBIT, Pointer(EV_KEY));
    for i := 0 to 248 do
      ioRes += fpIOCtl(vKeyboardFD, UI_SET_KEYBIT, Pointer(i));
    ioRes += fpIOCtl(vKeyboardFD, UI_DEV_SETUP, @vKeyboardSetup);
    ioRes += fpIOCtl(vKeyboardFD, UI_DEV_CREATE, nil);
    if ioRes <> 0 then
    begin
      Log(etError, Format('Cannot install virtual keyboard. %s', [StrError(errno)]), False);
      Halt(1);
    end;
    ioRes := -1;
    i := 0;
    Log(etInfo, 'Done.', True);

    //start mouse clicks reading
    Log(etInfo, 'Getting mouse input...', True);
    MouseFD := fpOpen(MousePath, O_RDONLY);
    if MouseFD = -1 then
    begin
      Log(etError, Format('Cannot open %s %s', [MousePath, StrError(errno)]), False);
      Halt(1);
    end;
    BeginThread(@TrackMouseThread, @MouseFD);
    Log(etInfo, 'Done.', True);

    //started successfully, now working
    Log(etInfo, 'Easy Switcher started successfully.', False);
    while not StopAndExit do
    begin
      ioRes := fpRead(KeyboardFD, KeyIE, SizeOf(KeyIE));
      if (ioRes = SizeOf(KeyIE)) then
      begin
        if NeedClearKeyBuf then
        begin
          SetLength(KeyBuf, 0);
          NeedClearKeyBuf := False;
          Log(etInfo, 'buffer cleared', True);
        end;
        if ((KeyIE.ie_type = EV_KEY) and (KeyIE.value in [0, 1])) then //, 2
        begin
          Log(etInfo, Format('input %s %s', [KeyName[KeyIE.code], KeyAction[KeyIE.value]]), True);
          sleep(50);

          // --- auto-correct addition: track real layout-switch presses so
          // we know which decoded reading ("EN" vs "RU") is actually on
          // screen right now. Mirrors Convert()'s own single-key/combo logic.
          if (Length(Keys_LS) >= 1) and (KeyIE.code = Keys_LS[0]) then
            LS0Down := (KeyIE.value = 1);
          if (Length(Keys_LS) = 2) and (KeyIE.code = Keys_LS[1]) then
            LS1Down := (KeyIE.value = 1);
          if (KeyIE.value = 1) then
          begin
            if (Length(Keys_LS) = 1) and (KeyIE.code = Keys_LS[0]) then
              CurrentIsRu := not CurrentIsRu
            else if (Length(Keys_LS) = 2) and LS0Down and LS1Down and
              ((KeyIE.code = Keys_LS[0]) or (KeyIE.code = Keys_LS[1])) then
              CurrentIsRu := not CurrentIsRu;
          end;

          // --- auto-correct addition: toggle key, works regardless of buffer state ---
          if HunspellReady and (KeyIE.code = Key_AUTOTOGGLE) and (KeyIE.value = 0) then
          begin
            AutoModeActive := not AutoModeActive;
            Log(etInfo, Format('auto-mode: switched %s', [BoolToStr(AutoModeActive, 'ON', 'OFF')]), False);
          end;

          if ((KeyIE.code in Letters) or (KeyIE.code in Shifts) or (KeyIE.code = KEY_RPL)) then
          begin
            i := Length(KeyBuf);
            SetLength(KeyBuf, i + 1);
            KeyBuf[i].ie_type := KeyIE.ie_type;
            KeyBuf[i].code := KeyIE.code;
            KeyBuf[i].value := KeyIE.value;
            KeyBuf[i].time.tv_sec := 0;
            KeyBuf[i].time.tv_usec := 0;
            NeedTrackMouse := True;
          end;
          if (KeyIE.code in BufKillers) and (KeyIE.value = 0) then
          begin
            SetLength(KeyBuf, 0);
            NeedClearKeyBuf := False;
            Log(etInfo, 'buffer cleared', True);
          end;

          // --- auto-correct addition: check the word just finished on SPACE-up ---
          if AutoModeActive and (KeyIE.code = KEY_SPACE) and (KeyIE.value = 0) and (Length(KeyBuf) > 0) then
          begin
            if ShouldAutoCorrect() then
            begin
              Log(etInfo, 'auto-mode: wrong layout detected, correcting', False);
              PrepareBuffer;
              Convert(True);
              CurrentIsRu := not CurrentIsRu;  // Convert() itself just switched layout
              fpClose(KeyboardFD);
              KeyboardFD := fpOpen(KeyboardPath, O_RDONLY or O_SYNC);
            end;
          end;

          if Length(KeyBuf) > 0 then
            if ((KeyIE.code = KEY_RPL) and (KeyIE.value = 0)) or
              ((KeyIE.code in Shifts) and (KeyIE.value = 0)) then
            begin
              BufferAction := GetBufferAction;
              if BufferAction <> KeepBuffer then
              begin
                Log(etInfo, 'prepare buffer', True);
                Log(etInfo, '  raw: ' + GetBufferStr, True);
                PrepareBuffer;
                Log(etInfo, '  prepared: ' + GetBufferStr, True);
                if (BufferAction = ReplaceAll) xor ReverseMode then
                begin
                  Log(etInfo, 'convert all', True);
                  Convert(False);
                  CurrentIsRu := not CurrentIsRu;  // auto-correct addition: Convert() itself just switched layout
                end
                else
                begin
                  Log(etInfo, 'convert word', True);
                  Convert(True);
                  CurrentIsRu := not CurrentIsRu;  // auto-correct addition
                end;
                fpClose(KeyboardFD);
                KeyboardFD := fpOpen(KeyboardPath, O_RDONLY or O_SYNC);
              end;
            end;
        end;
      end
      else
        Sleep(10);
    end;

    if KeyboardFD <> -1 then fpClose(KeyboardFD);
    if MouseFD <> -1 then fpClose(MouseFD);
    if vKeyboardFD <> -1 then
    begin
      fpIOCtl(vKeyboardFD, UI_DEV_DESTROY, nil);
      fpClose(vKeyboardFD);
    end;
    if HunspellReady then UnloadHunspell();  // auto-correct addition
    FreeAndNil(EnBigrams);
    FreeAndNil(RuBigrams);
  end;

  procedure RunDebug();
  begin
    DaemonMode := False;
    Run();
  end;

  procedure RunOldStyleDaemon();
  var
    pid, sid: TPid;
  begin
    pid := FpFork;
    if pid < 0 then
    begin
      Log(etError, 'Failed to fork', False);
      Halt(1);
    end;
    if pid > 0 then
    begin
      FpExit(0);
    end;
    sid := FpSetsid;
    if sid < 0 then
    begin
      Log(etError, '1st child process failed to become session leader', False);
      FpExit(0);
    end;

    pid := FpFork;
    if pid < 0 then
    begin
      Log(etError, 'Failed to fork from 1st child', False);
      Halt(1);
    end;
    if pid > 0 then
    begin
      FpExit(0);
    end;

    FpUmask(0);
    ChDir('/');
    FpClose(StdInputHandle);
    FpClose(StdOutputHandle);
    FpClose(StdErrorHandle);

    Run();
  end;

  procedure RunHelp();
  begin
    DaemonMode := False;
    Log(etInfo, Format('Easy Switcher - keyboard layout switcher v%s', [EASY_SWITCHER_VERSION]), True);
    Log(etInfo, '', True);
    Log(etInfo, 'Usage: easy-switcher [option]', True);
    Log(etInfo, '', True);
    Log(etInfo, 'Options:', True);
    Log(etInfo, '   -i,   --install     install as systemd daemon', True);
    Log(etInfo, '   -u,   --uninstall   uninstall systemd daemon', True);
    Log(etInfo, '   -c,   --configure   configure Easy Switcher', True);
    Log(etInfo, '   -r,   --run         run', True);
    Log(etInfo, '   -d,   --debug       run in a debug mode', True);
    Log(etInfo, '   -o,   --old-style   run as an "old-style" (not systemd) daemon', True);
    Log(etInfo, '   -h,   --help        show this help', True);
    Log(etInfo, '', True);
    Log(etInfo, 'Auto-mode (this fork''s addition, not in upstream): configure by', True);
    Log(etInfo, 'hand in ' + CONFIG_FILE + ', keys are:', True);
    Log(etInfo, '   auto-mode-start=true|false   (default false)', True);
    Log(etInfo, '   auto-mode-key=<scancode>     (default 70, SCROLLLOCK)', True);
    Log(etInfo, '   start-layout=en|ru           (default en, best-guess at daemon start)', True);
    Log(etInfo, '   min-word-length=<n>          (default 4)', True);
    Log(etInfo, '   dict-en-aff / dict-en-dic / dict-ru-aff / dict-ru-dic', True);
    Log(etInfo, '     (default to /usr/share/hunspell/{en_US,ru_RU}.{aff,dic})', True);
    Log(etInfo, '   exclude-apps=<comma-separated substrings>   (default empty = off)', True);
    Log(etInfo, '     matched against the active window class via active-window-tool;', True);
    Log(etInfo, '     e.g. "konsole,yakuake,code" to stay out of terminals/editors', True);
    Log(etInfo, '   active-window-tool=<binary>       (default kdotool, KDE Wayland only)', True);
    Log(etInfo, '   active-window-user=<username>     (REQUIRED for exclude-apps - this daemon', True);
    Log(etInfo, '     runs as root, so reaching your session DBus bus for kdotool needs', True);
    Log(etInfo, '     an explicit runuser hop into your login user)', True);
    Log(etInfo, '   active-window-timeout-ms=<n>      (default 200)', True);
    Log(etInfo, '   active-window-cache-ms=<n>        (default 400)', True);
    Log(etInfo, '   bigram-threshold=<float>          (default 1.2)', True);
    Log(etInfo, '     fallback for words in neither dictionary: how much more', True);
    Log(etInfo, '     "typical" (letter-sequence-wise) the other reading has to', True);
    Log(etInfo, '     look before correcting - lower = more aggressive', True);
  end;

begin
  AppEventLog := TEventLog.Create(nil);  //enable logging to syslog
  AppEventLog.LogType := ltSystem;

  if paramCount() <> 1 then RunHelp      //parse params
  else
    case ParamStr(1) of
      '-i', '--install': RunInstall;
      '-u', '--uninstall': RunUninstall;
      '-c', '--configure': RunConfig;
      '-r', '--run': Run;
      '-d', '--debug': RunDebug;
      '-o', '--old-style': RunOldStyleDaemon;
      '-h', '--help': RunHelp;
      else
        RunHelp;
    end;

  if Assigned(AppEventLog) then FreeAndNil(AppEventLog);
end.
