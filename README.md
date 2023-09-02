# Easy Switcher
keyboard layout switcher for Linux

## How to build
Easy Switcher is written in Free Pascal. 
The simplest way to build is install [Lazarus](https://www.lazarus-ide.org/), clone this repository, open the project (easy-switcher.lpi) and build it.
You may also build with [fpc](https://www.freepascal.org/)

## Installation
### Ubuntu & Debian
* Download the [latest deb](https://github.com/freemind001/easy-switcher/releases)
* Install package

	`sudo dpkg -i <path to easy-switcher.deb>`
* Configure

	`sudo easy-switcher -c`
* Run Easy Switcher daemon

	`sudo systemctl start easy-switcher`

### Other Linux & your own builds
* Build Easy Switcher or download the [latest binary](https://github.com/freemind001/easy-switcher/releases)
* Copy copy easy-switcher to /usr/bin/ and allow execute the file as program
* install Easy Switcher as daemon  
If your OS supports systemd:

	`sudo easy-switcher -i`

If your OS doesn't support systemd, please refer your OS documentation on how to install daemons. You need to use -o or --old-style key to run Easy Switcher as an "old-style" (true) daemon
* Configure

	`sudo easy-switcher -c`
* Run Easy Switcher daemon
If your OS supports systemd:

	`sudo systemctl start easy-switcher`
If your OS doesn't support systemd, please refer your OS documentation on how to run daemons

## Configuring
For manual configuration please edit /etc/easy-switcher/default.conf after installation
Easy Switcher has built-in configuration tool. Please use -c or --configure key to configure Easy Switcher automatically.

## Known bugs & issues
* Doesn't work correctly togethe with key remappers such as keyd
