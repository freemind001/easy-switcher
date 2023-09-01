program easyswitcher;

{$mode objfpc}

uses
  cThreads,
  BaseUnix,
  Linux,
  SysUtils,
  Classes,
  IniFiles,
  EventLog,
  Errors;

type
  input_event = record   //c-style struct input_event
    time: timeval;
    ie_type: cuint16;
    code: cuint16;
    Value: cint32;
  end;

  input_id = record   //c-style struct input_id
    bustype: cuint16;
    vendor: cuint16;
    product: cuint16;
    version: cuint16;
  end;

  uinput_setup = record //c-style struct uinput_setup
    id: input_id;
    Name: array[0..79] of char;
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
  TQueueSelector = (TCIFLUSH, TCOFLUSH, TCIOFLUSH);

const
  EASY_SWITCHER_VERSION = '0.2';

  SYSTEMD_UNIT_FILE = '/lib/systemd/system/easy-switcher.service';
  CONFIG_FILE = '/etc/easy-switcher/default.conf';
  INPUT_DEVICES_DIR = '/dev/input/';
  UINPUT_FILE = '/dev/uinput';

  EV_SYN = $0000; //key events
  EV_KEY = $0001;
  SYN_REPORT = $0000;

  UI_SET_EVBIT = $40045564;   // magic numbers
  UI_SET_KEYBIT = $40045565;
  UI_DEV_SETUP = $405C5503;
  UI_DEV_CREATE = $5501;
  UI_DEV_DESTROY = $5502;

  BUS_USB = $0003;  //virtual keyboard bus

  EINTR = $0004;  // Interrupted system call
  EIO = $0005;    // I/O error

  TCFLSH = $0000540B;

  //keys to watch and replace
  Letters = [2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12, 13, 14, 16, 17, 18,
    19, 20, 21, 22, 23, 24, 25, 26, 27, 28, 30, 31, 32, 33, 34, 35,
    36, 37, 38, 39, 40, 41, 43, 44, 45, 46, 47, 48, 49, 50, 51, 52,
    53, 55, 57, 71, 72, 73, 74, 75, 76, 77, 78, 79, 80, 81, 82, 83, 96, 98];
  Shifts = [42, 54];
  BufKillers = [15, 102, 103, 104, 105, 106, 107, 108, 109, 110];

  KEY_BACKSPACE: word = 14;    //Backspace
  KEY_SPACE: word = 57;        //Space
  KEY_ENTER: word = 28;        //Enter

  KeyName: array [0..248] of string =
    ('RESERVED', 'ESC', '1', '2', '3', '4', '5', '6', '7',
    '8', '9', '0', 'MINUS', 'EQUAL', 'BACKSPACE',
    'TAB', 'Q', 'W', 'E', 'R', 'T', 'Y', 'U', 'I',
    'O', 'P', 'LEFTBRACE', 'RIGHTBRACE', 'ENTER', 'LEFTCTRL',
    'A', 'S', 'D', 'F', 'G', 'H', 'J', 'K', 'L', 'SEMICOLON',
    'APOSTROPHE', 'GRAVE', 'LEFTSHIFT', 'BACKSLASH', 'Z', 'X',
    'C', 'V', 'B', 'N', 'M', 'COMMA', 'DOT', 'SLASH',
    'RIGHTSHIFT', 'KPASTERISK', 'LEFTALT',
    'SPACE', 'CAPSLOCK', 'F1', 'F2', 'F3', 'F4', 'F5',
    'F6', 'F7', 'F8', 'F9', 'F10', 'NUMLOCK', 'SCROLLLOCK',
    'KP7', 'KP8', 'KP9', 'KPMINUS', 'KP4', 'KP5', 'KP6', 'KPPLUS', 'KP1',
    'KP2', 'KP3', 'KP0', 'KPDOT', '(84)', 'ZENKAKUHANKAKU', '102ND',
    'F11', 'F12', 'RO', 'KATAKANA', 'HIRAGANA', 'HENKAN',
    'KATAKANAHIRAGANA', 'MUHENKAN', 'KPJPCOMMA', 'KPENTER',
    'RIGHTCTRL', 'KPSLASH', 'SYSRQ', 'RIGHTALT', 'LINEFEED', 'HOME',
    'UP', 'PAGEUP', 'LEFT', 'RIGHT', 'END', 'DOWN', 'PAGEDOWN',
    'INSERT', 'DELETE', 'MACRO', 'MUTE', 'VOLUMEDOWN', 'VOLUMEUP',
    'POWER', 'KPEQUAL', 'KPPLUSMINUS', 'PAUSE', 'SCALE', 'KPCOMMA',
    'HANGEUL', 'HANJA', 'YEN', 'LEFTMETA', 'RIGHTMETA', 'COMPOSE',
    'STOP', 'AGAIN', 'PROPS', 'UNDO', 'FRONT', 'COPY', 'OPEN',
    'PASTE', 'FIND', 'CUT', 'HELP', 'MENU', 'CALC', 'SETUP', 'SLEEP',
    'WAKEUP', 'FILE', 'SENDFILE', 'DELETEFILE', 'XFER', 'PROG1',
    'PROG2', 'WWW', 'MSDOS', 'COFFEE', 'ROTATE_DISPLAY', 'CYCLEWINDOWS',
    'MAIL', 'BOOKMARKS', 'COMPUTER', 'BACK', 'FORWARD', 'CLOSECD',
    'EJECTCD', 'EJECTCLOSECD', 'NEXTSONG', 'PLAYPAUSE', 'PREVIOUSSONG',
    'STOPCD', 'RECORD', 'REWIND', 'PHONE', 'ISO', 'CONFIG', 'HOMEPAGE',
    'REFRESH', 'EXIT', 'MOVE', 'EDIT', 'SCROLLUP', 'SCROLLDOWN',
    'KPLEFTPAREN', 'KPRIGHTPAREN', 'NEW', 'REDO', 'F13', 'F14', 'F15',
    'F16', 'F17', 'F18', 'F19', 'F20', 'F21', 'F22', 'F23', 'F24',
    '(195)', '(196)', '(197)', '(198)', '(199)', 'PLAYCD', 'PAUSECD',
    'PROG3', 'PROG4', 'ALL_APPLICATIONS', 'SUSPEND', 'CLOSE', 'PLAY',
    'FASTFORWARD', 'BASSBOOST', 'PRINT', 'HP', 'CAMERA', 'SOUND',
    'QUESTION', 'EMAIL', 'CHAT', 'SEARCH', 'CONNECT', 'FINANCE',
    'SPORT', 'SHOP', 'ALTERASE', 'CANCEL', 'BRIGHTNESSDOWN', 'BRIGHTNESSUP',
    'MEDIA', 'SWITCHVIDEOMODE', 'KBDILLUMTOGGLE', 'KBDILLUMDOWN',
    'KBDILLUMUP', 'SEND', 'REPLY', 'FORWARDMAIL', 'SAVE', 'DOCUMENTS',
    'BATTERY', 'BLUETOOTH', 'WLAN', 'UWB', 'UNKNOWN', 'VIDEO_NEXT',
    'VIDEO_PREV', 'BRIGHTNESS_CYCLE', 'BRIGHTNESS_AUTO', 'DISPLAY_OFF',
    'WWAN', 'RFKILL', 'MICMUTE');

var
  DaemonMode: boolean = True;
  AppEventLog: TEventLog = nil;
  E: Exception;

  Key_RPL: word;
  Keys_LS: array of word = nil;
  StrKeys_LS: string = '';

  NeedTrackMouse: boolean = False;
  NeedClearKeyBuf: boolean = False;

  KeyBuf: TKeyBuf;
  BufferAction: TBufferAction = KeepBuffer;

  StopAndExit: boolean = False;

  procedure Log(EventType: TEventType; const aMessage: string; StdOutputOnly: boolean);
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
        Log(etError, Format('Error creating systemd control file. %s. Are you root?',
          [E.Message]), False);
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
      Log(etError, Format('Nothing to uninstall. Unit file not found %s.',
        [SYSTEMD_UNIT_FILE]), False);
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
          if ((KeyIE.ie_type = 1) and (KeyIE.code = KEY_ENTER) and
            (KeyIE.Value in [0, 1, 2])) then
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
        MousePath := ConfigIniFile.ReadString('Easy Switcher', 'mouse',
          '/dev/input/mice');
        ReverseMode := StrToBool(ConfigIniFile.ReadString('Easy Switcher',
          'reverse-mode', 'False'));
        Delay := ConfigIniFile.ReadInteger('Easy Switcher', 'delay', 10);
        Log(etInfo, 'Done.', True);
        if Assigned(ConfigIniFile) then
          FreeAndNil(ConfigIniFile);
      except
        on E: Exception do
        begin
          Log(etInfo, Format(
            'Error reading config file, Easy Switcher will create new one. %s',
            [E.Message]), False);
          if Assigned(ConfigIniFile) then
            FreeAndNil(ConfigIniFile);
        end;
      end;

      Log(etInfo, '', True);
      Log(etInfo, 'Easy Switcher will try to detect your keyboard automatically.', True);
      sleep(100);
      if FindFirst(INPUT_DEVICES_DIR + 'event*', faSysFile, SRec) = 0 then
      begin
        repeat
          with SRec do
          begin
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
        Log(etInfo, 'Please press ENTER...', True);
        for i := 0 to Length(KeyboardList) - 1 do
        begin
          BeginThread(@KeyboardDetectThread, @(KeyboardList[i]));
        end;

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
            Log(etInfo,
              'Press the key or combination of keys that changes layout in your system.',
              True);
            Log(etInfo, 'Waiting for your input...', True);
            i := 0;
            while i < 6000 do
            begin
              ioRes := 0;
              ioRes := fpRead(KeyboardFD, KeyIE, SizeOf(KeyIE));
              if (ioRes = SizeOf(KeyIE)) then
              begin
                if ((KeyIE.ie_type = EV_KEY) and (KeyIE.Value in [0, 1])) then
                begin
                  SetLength(Keys_LS, Length(Keys_LS) + 1);
                  Keys_LS[Length(Keys_LS) - 1] := KeyIE.code;
                  if Length(Keys_LS) = 2 then
                  begin
                    if KeyIE.Value = 0 then
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

            Log(etInfo,
              'Press the key you will use to correct the text you have entered.',
              True);
            Log(etInfo, 'Waiting for your input...', True);
            i := 0;
            while i < 6000 do
            begin
              ioRes := 0;
              ioRes := fpRead(KeyboardFD, KeyIE, SizeOf(KeyIE));
              if (ioRes = SizeOf(KeyIE)) then
              begin
                if ((KeyIE.ie_type = 1) and (KeyIE.Value = 1)) then
                begin
                  Key_RPL := KeyIE.code;
                  break;
                end;
              end;
              sleep(10);
              Inc(i);
            end;

            if Key_RPL <> -1 then
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

            //flush terminal buffer
            ioRes := fpIOCtl(StdInputHandle, TCFLSH, pointer(Ord(TCIFLUSH)));

            Log(etInfo, 'Writing configuration file...', True);
            try
              Config := TStringList.Create;
              Config.Add('[Easy Switcher]');
              Config.Add('# This is Easy Switcher config file.');
              Config.Add('');
              Config.Add('# Keyboard device path.');
              Config.Add(
                '# Run ''~$ hwinfo --keyboard --short'' to get the list of your keyboard devices.');
              Config.Add('# keyboard="/dev/input/event2"');
              Config.Add('');
              Config.Add('keyboard="' + KeyboardPath + '"');
              Config.Add('');
              Config.Add('');
              Config.Add('# Mouse device path.');
              Config.Add(
                '# Run ''~$ hwinfo --mouse --short'' to get the list of your mouse devices.');
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
              Config.Add(
                '# only last word you have entered. Pressing Shift + <replace-key> corrects');
              Config.Add('# the whole phrase.');
              Config.Add('# If reverse-mode is true, pressing <replace-key> corrects');
              Config.Add(
                '# the whole phrase you have entered, and Shift + <replace-key> corrects');
              Config.Add('# only the last word.');
              Config.Add('# Default reverse-mode value is false');
              Config.Add('# reverse-mode=false');
              Config.Add('');
              Config.Add('reverse-mode=' + BoolToStr(ReverseMode, True) + '');
              Config.Add('');
              Config.Add('');
              Config.Add(
                '# Easy Switcher uses a delay to wait for your system to process the actions.');
              Config.Add('# The smaller delay is, the faster Easy Switcher works.');
              Config.Add('# However, your desktop environment may not be able to handle');
              Config.Add(
                '# Easy Switcher output in a timely manner and you will get errors.');
              Config.Add('# Try to increase the delay if you get messy output.');
              Config.Add('# Default delay value is 10');
              Config.Add('# delay=10');
              Config.Add('');
              Config.Add('delay=' + IntToStr(Delay));
              Config.SaveToFile(CONFIG_FILE);
              Log(etInfo, 'Keyboard configuration successfully saved.', False);
              Log(etInfo, Format('See %s to edit additional parameters.',
                [CONFIG_FILE]), False);
              if Assigned(Config) then
                FreeAndNil(Config);
            except
              on E: Exception do
              begin
                Log(etError, Format('Error writing configuration file %s %s',
                  [CONFIG_FILE, StrError(errno)]), False);
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
      Log(etError, Format('Cannot create directory %s',
        [ExtractFilePath(CONFIG_FILE)]), False);
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
      ioRes := fpRead(longint(PMouseFD), MouseData, SizeOf(MouseData));
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

      if Length(KeyBuf) < 3 then Exit(KeepBuffer);

      if (KeyBuf[Last].code = Key_RPL) and (KeyBuf[Last].Value = 0) and
        (KeyBuf[Last - 1].code = Key_RPL) and (KeyBuf[Last - 1].Value = 1) then
        if (KeyBuf[Last - 2].code in Shifts) and (KeyBuf[Last - 2].Value = 1) then
          Exit(ReplaceAll)
        else
          Exit(ReplaceWord);
      Result := KeepBuffer;
    end;

    function GetBufferStr(): string;
    var
      i: integer;
    begin
      Result := '';
      for i := 0 to Length(KeyBuf) - 1 do
        Result := Result + Format('%s %s; ', [KeyName[KeyBuf[i].code],
          KeyAction[KeyBuf[i].Value]]);
    end;

    procedure PrepareBuffer();
    var
      TempBuf: array of input_event = nil;
      i: integer = 0;
      k: integer = 0;
      Last: integer = 0;
    begin
      Last := Length(KeyBuf) - 1;

      //get rid of RPL
      if (KeyBuf[Last].code = Key_RPL) and (KeyBuf[Last].Value = 0) and
        (KeyBuf[Last - 1].code = Key_RPL) and (KeyBuf[Last - 1].Value = 1) then
        if (KeyBuf[Last - 2].code in Shifts) and (KeyBuf[Last - 2].Value = 1) then
          Last := Last - 3
        else
          Last := Last - 2;

      for i := 0 to Last do
      begin
        //get rid of BS, if any
        if (KeyBuf[i].code = KEY_BACKSPACE) then
        begin
          if (k = 0) then
            continue
          else
          begin
            k := Length(TempBuf) - 1;
            if TempBuf[k].code in Shifts then
              TempBuf[k - 1] := TempBuf[k];
            SetLength(TempBuf, k);
            continue;
          end;
        end;

        SetLength(TempBuf, k + 1);
        TempBuf[k] := KeyBuf[i];
        k += 1;
      end;

      SetLength(KeyBuf, 0);
      k := 0;

      for i := 0 to Length(TempBuf) - 1 do
      begin
        //convert repeated keys to keydowns, works bad, probably kernel bug
        if TempBuf[i].Value = 2 then
        begin
          SetLength(KeyBuf, k + 1);
          KeyBuf[k] := TempBuf[i];
          KeyBuf[k].Value := 0;
          k += 1;

          SetLength(KeyBuf, k + 1);
          KeyBuf[k] := TempBuf[i];
          KeyBuf[k].Value := 1;
          k += 1;
        end
        else
        begin
          SetLength(KeyBuf, k + 1);
          KeyBuf[k] := TempBuf[i];
          k += 1;
        end;
      end;
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
          if (KeyBuf[n].Value = 0) and (KeyBuf[n].code = KEY_SPACE) and
            (n <> Length(KeyBuf) - 1) then
          begin
            s := n + 1; //set the conversion limit by SPACE UP
          end;
        end;
      end;

      for n := s to Length(KeyBuf) - 1 do
        if (KeyBuf[n].Value in [1, 2]) and (not (KeyBuf[n].code in Shifts)) then
        begin
          k := Length(IEBuf);           //BS down
          SetLength(IEBuf, k + 1);
          IEBuf[k].ie_type := EV_KEY;
          IEBuf[k].code := KEY_BACKSPACE;
          IEBuf[k].Value := 1;
          IEBuf[k].time.tv_sec := IETime.tv_sec;
          IEBuf[k].time.tv_usec := IETime.tv_usec;
          IETime.tv_usec := IETime.tv_usec + 200;

          k := Length(IEBuf);           //BS up
          SetLength(IEBuf, k + 1);
          IEBuf[k].ie_type := EV_KEY;
          IEBuf[k].code := KEY_BACKSPACE;
          IEBuf[k].Value := 0;
          IEBuf[k].time.tv_sec := IETime.tv_sec;
          IEBuf[k].time.tv_usec := IETime.tv_usec;
          IETime.tv_usec := IETime.tv_usec + 200;
        end;

      k := Length(IEBuf);               //layout change down
      SetLength(IEBuf, k + 1);
      IEBuf[k].ie_type := EV_KEY;
      IEBuf[k].code := Keys_LS[0];
      IEBuf[k].Value := 1;
      IEBuf[k].time.tv_sec := IETime.tv_sec;
      IEBuf[k].time.tv_usec := IETime.tv_usec;
      IETime.tv_usec := IETime.tv_usec + 200;

      if Length(Keys_LS) = 2 then
      begin
        k := Length(IEBuf);               //layout change down if combination
        SetLength(IEBuf, k + 1);
        IEBuf[k].ie_type := EV_KEY;
        IEBuf[k].code := Keys_LS[1];
        IEBuf[k].Value := 1;
        IEBuf[k].time.tv_sec := IETime.tv_sec;
        IEBuf[k].time.tv_usec := IETime.tv_usec;
        IETime.tv_usec := IETime.tv_usec + 200;

        k := Length(IEBuf);               //layout change up if combination
        SetLength(IEBuf, k + 1);
        IEBuf[k].ie_type := EV_KEY;
        IEBuf[k].code := Keys_LS[1];
        IEBuf[k].Value := 0;
        IEBuf[k].time.tv_sec := IETime.tv_sec;
        IEBuf[k].time.tv_usec := IETime.tv_usec;
        IETime.tv_usec := IETime.tv_usec + 200;
      end;

      k := Length(IEBuf);                 //layout change up
      SetLength(IEBuf, k + 1);
      IEBuf[k].ie_type := EV_KEY;
      IEBuf[k].code := Keys_LS[0];
      IEBuf[k].Value := 0;
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
        IEBuf[k].Value := KeyBuf[n].Value;
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
        EmitBuf[2].Value := 0;
        EmitBuf[2].time.tv_sec := IEBuf[n].time.tv_sec;
        EmitBuf[2].time.tv_usec := IEBuf[n].time.tv_usec + 100;

        fpWrite(vKeyboardFD, EmitBuf[1], sizeof(EmitBuf[1]) * 2);
        Log(etInfo, Format('output %s %s', [KeyName[EmitBuf[1].code],
          KeyAction[EmitBuf[1].Value]]), True);
        Sleep(Delay);
      end;
    end;

  begin
    if DaemonMode then
      Log(etInfo, Format('Starting Easy Switcher v%s...',
        [EASY_SWITCHER_VERSION]), False)
    else
      Log(etInfo, Format('Starting Easy Switcher v%s in debug mode...',
        [EASY_SWITCHER_VERSION]), False);

    //Init values
    NewAct := Default(SigactionRec);
    OldAct := Default(SigactionRec);
    KeyIE := Default(input_event);
    KeyBuf := Default(TKeyBuf);
    SetLength(Keys_LS, 2);
    vKeyboardSetup := Default(uinput_setup);
    vKeyboardSetup.id.bustype := BUS_USB;
    vKeyboardSetup.id.vendor := $0777;
    vKeyboardSetup.id.product := $0777;
    vKeyboardSetup.Name := 'Easy Switcher virtual input device';

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
        StrKeys_LS := ConfigIniFile.ReadString('Easy Switcher',
          'layout-switch-key', '-1');
        Key_RPL := StrToUInt(ConfigIniFile.ReadString('Easy Switcher',
          'replace-key', '-1'));
        ReverseMode := StrToBool(ConfigIniFile.ReadString('Easy Switcher',
          'reverse-mode', 'False'));
        Delay := StrToInt(ConfigIniFile.ReadString('Easy Switcher', 'delay', '10'));
        SetLength(Keys_LS, SScanf(StrKeys_LS, '%d+%d', [@Keys_LS[0], @Keys_LS[1]]));
        if Assigned(ConfigIniFile) then
          FreeAndNil(ConfigIniFile);
        if ((KeyboardPath = '~') or (MousePath = '~') or (Length(Keys_LS) = 0) or
          (KEY_RPL = -1)) then
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
      Log(etError, Format(
        'Missing config file %s, run ''easy-switcher -c'' to configure.',
        [CONFIG_FILE]), False);
      Halt(1);
    end;
    Log(etInfo, 'Done.', True);

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
    vKeyboardFD := fpOpen(UINPUT_FILE, O_WRONLY or O_SYNC);   //   or O_NONBLOCK
    if vKeyboardFD = -1 then
    begin
      Log(etError, Format('Cannot open %s %s', [UINPUT_FILE, StrError(errno)]), False);
      Halt(1);
    end;
    ioRes += fpIOCtl(vKeyboardFD, UI_SET_EVBIT, Pointer(EV_SYN));
    ioRes += fpIOCtl(vKeyboardFD, UI_SET_EVBIT, Pointer(EV_KEY));
    for i := 0 to 248 do
      iores += fpIOCtl(vKeyboardFD, UI_SET_KEYBIT, Pointer(i));
    ioRes += fpIOCtl(vKeyboardFD, UI_DEV_SETUP, @vKeyboardSetup);
    ioRes += fpIOCtl(vKeyboardFD, UI_DEV_CREATE, nil);
    if ioRes <> 0 then
    begin
      Log(etError, Format('Cannot install virtual keyboard. %s',
        [StrError(errno)]), False);
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
    BeginThread(@TrackMouseThread, Pointer(MouseFD));
    Log(etInfo, 'Done.', True);

    //started successfully, now working
    Log(etInfo, 'Easy Switcher started successfully.', False);
    while not StopAndExit do
    begin
      ioRes := fpRead(KeyboardFD, KeyIE, SizeOf(KeyIE));
      if (ioRes <> SizeOf(KeyIE)) then
      begin
        if (errno = EINTR) then
          Continue
        else
        begin
          errno := EIO;
          Log(etError, Format('Abnormal data read from %s %s',
            [KeyboardPath, StrError(errno)]), False);
          Continue;
        end;
      end
      else
      begin
        if NeedClearKeyBuf then
        begin
          SetLength(KeyBuf, 0);
          NeedClearKeyBuf := False;
          Log(etInfo, 'buffer cleared', True);
        end;
        if ((KeyIE.ie_type = EV_KEY) and (KeyIE.Value in [0, 1, 2])) then
        begin
          Log(etInfo, Format('input %s %s', [KeyName[KeyIE.code],
            KeyAction[KeyIE.Value]]), True);
          sleep(50);
          if ((KeyIE.code in Letters) or (KeyIE.code in Shifts) or
            (KeyIE.code = KEY_RPL)) then
          begin
            i := Length(KeyBuf);
            SetLength(KeyBuf, i + 1);
            KeyBuf[i].ie_type := KeyIE.ie_type;
            KeyBuf[i].code := KeyIE.code;
            KeyBuf[i].Value := KeyIE.Value;
            KeyBuf[i].time.tv_sec := 0;
            KeyBuf[i].time.tv_usec := 0;

            NeedTrackMouse := True;
          end;
          if (KeyIE.code in BufKillers) and (KeyIE.Value = 0) then
          begin
            SetLength(KeyBuf, 0);
            NeedClearKeyBuf := False;
            Log(etInfo, 'buffer cleared', True);
          end;
          if Length(KeyBuf) > 0 then
            if ((KeyIE.code = KEY_RPL) and (KeyIE.Value = 0)) or
              ((KeyIE.code in Shifts) and (KeyIE.Value = 0)) then
            begin
              BufferAction := GetBufferAction;
              if BufferAction <> KeepBuffer then
              begin
                Log(etInfo, 'prepare buffer', True);
                Log(etInfo, ' raw: ' + GetBufferStr, True);
                PrepareBuffer;
                Log(etInfo, ' prepared: ' + GetBufferStr, True);
                if (BufferAction = ReplaceAll) xor ReverseMode then
                begin
                  Log(etInfo, 'convert all', True);
                  Convert(False);
                end
                else
                begin
                  Log(etInfo, 'convert word', True);
                  Convert(True);
                end;
                fpClose(KeyboardFD);
                KeyboardFD := fpOpen(KeyboardPath, O_RDONLY or O_SYNC);
              end;
            end;
        end;
      end;
    end;

    if KeyboardFD <> -1 then fpClose(KeyboardFD);
    if MouseFD <> -1 then fpClose(MouseFD);
    if vKeyboardFD <> -1 then
    begin
      fpIOCtl(vKeyboardFD, UI_DEV_DESTROY, nil);
      fpClose(vKeyboardFD);
    end;
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
    Log(etInfo, Format('Easy Switcher - keyboard layout switcher v%s',
      [EASY_SWITCHER_VERSION]), True);
    Log(etInfo, '', True);
    Log(etInfo, 'Usage: easy-switcher [option]', True);
    Log(etInfo, '', True);
    Log(etInfo, 'Options:', True);
    Log(etInfo, '   -i,   --install     install as systemd daemon', True);
    Log(etInfo, '   -u,   --uninstall   uninstall systemd daemon', True);
    Log(etInfo, '   -c,   --configure   configure Easy Switcher', True);
    Log(etInfo, '   -r,   --run         run', True);
    Log(etInfo, '   -d,   --debug       run in a debug mode', True);
    Log(etInfo, '   -o,   --old-style   run as an "old-style" (not systemd) daemon',
      True);
    Log(etInfo, '   -h,   --help        show this help', True);
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
