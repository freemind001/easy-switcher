# Easy Switcher
Easy Switcher is a keyboard layout switcher and input corrector for Linux.  
It runs as a daemon on your system, is independent from your desktop environment and windowing system, works with the keyboard directly via kernel input, so it is reliable and smooth.   

## How does it work?
The program catches your keystrokes, remembers them, and when you press a special key (Pause/Break by default), it erases what you have written, changes the layout, and writes the correct input back.

## How to build
Easy Switcher is written in Pascal.  
The simplest way to build is to install [Lazarus](https://www.lazarus-ide.org/), clone this repository, open the project (easy-switcher.lpi) and build it.  
You may also build with [fpc](https://www.freepascal.org/).

## Installation
### Ubuntu & Debian
* Download the [latest deb](https://github.com/freemind001/easy-switcher/releases).
* Install the package: `sudo dpkg -i <path to easy-switcher.deb>`.
* Configure: `sudo easy-switcher -c`.
* Run Easy Switcher daemon: `sudo systemctl start easy-switcher`.
### Other Linux & your own builds
* Build Easy Switcher or download the [latest binary](https://github.com/freemind001/easy-switcher/releases).
* Copy easy-switcher to /usr/bin/ and allow execute the file as program.
* Install Easy Switcher as daemon:  
If your OS supports systemd: `sudo easy-switcher -i`.  
If your OS doesn't support systemd, please refer your OS documentation on how to install daemons. You need to use -o or --old-style key to run Easy Switcher as an "old-style" (true) daemon.
* Configure: `sudo easy-switcher -c`  
* Run Easy Switcher daemon:  
If your OS supports systemd: `sudo systemctl start easy-switcher`.  
If your OS doesn't support systemd, please refer your OS documentation on how to run daemons.  

## Configuring
For manual configuration please edit /etc/easy-switcher/default.conf after installation.  
Easy Switcher has built-in configuration tool. Please use -c or --configure key to configure Easy Switcher automatically.  

## Configuring
Run-time errors are written to syslog.  
For detailed info run Easy Switcher in terminal in the debug mode using -d or --debug key. 

## Known bugs & issues
* Doesn't work correctly together with key remappers such as keyd  
