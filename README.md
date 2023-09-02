# Easy Switcher
Easy Switcher is a keyboard layout switcher and input corrector for Linux.  
It runs as a daemon on your system, is independent from your desktop environment and windowing system, works with the keyboard directly via kernel input, so it is reliable and smooth.   

## How does it work?
Easy Switcher writes your keystrokes to internal buffer, and when you press a special key (Pause/Break by default), it erases what you have written, changes the layout, and writes the correct input back.

## Usage
Install, configure & run the daemon.   
If you have entered text in the wrong layout, press Pause/Break to convert the last word, or Shift+Pause/Break to convert the whole phrase. 

## How to build
Easy Switcher is written in Pascal. It can be built with [fpc](https://www.freepascal.org/) or [Lazarus](https://www.lazarus-ide.org/).  
To build with fpc:
* Install fpc version 3.2.2 or later
* Clone this repository.
* Go to the sources folder `cd <path to easy-switcher.lpr folder>`.
* Build Easy Switcher `fpc easy-switcher.lpr`.

## Installation
### Ubuntu & Debian
* Download the [latest deb](https://github.com/freemind001/easy-switcher/releases).
* Install the package: `sudo dpkg -i <path to easy-switcher.deb>`.
* Configure: `sudo easy-switcher -c`.
* Install & run Easy Switcher daemon:
  ```
  sudo easy-switcher -i
  sudo systemctl enable easy-switcher
  sudo systemctl start easy-switcher
  ```
  
### Other Linux & your own builds
* Build Easy Switcher or download the [latest binary](https://github.com/freemind001/easy-switcher/releases).
* Copy easy-switcher binary to /usr/bin/ and allow execute the file as program.
* Configure: `sudo easy-switcher -c` 
* Install & run Easy Switcher as daemon:  
  If your OS supports systemd:
  ```
  sudo easy-switcher -i
  sudo systemctl enable easy-switcher
  sudo systemctl start easy-switcher
  ```  
  If your OS doesn't support systemd, please refer your OS documentation on how to install and run daemons. You may need to use -o or --old-style switch to run Easy Switcher as an "old-style" (true) daemon.
  
## Configuring
Easy Switcher has a built-in configuration tool. For automatic configuration, run it in the terminal with the -c or --configure switch.    
Additional tuning is available with manual configuration, please edit /etc/easy-switcher/default.conf.  

## Troubleshooting
Run-time errors are written to syslog.  
For detailed info run Easy Switcher in terminal in a debug mode with -d or --debug switch. 

## Known bugs & issues
* Doesn't work correctly together with key remappers such as keyd.  
