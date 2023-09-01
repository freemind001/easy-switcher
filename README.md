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

	sudo dpkg -i <path to easy-switcher.deb>
* Configure

	sudo easy-switcher -c
* Run Easy Switcher daemon

	sudo systemctl start easy-switcher

### Other Linux & your own builds
* Build Easy Switcher or download the [latest binary](https://github.com/freemind001/easy-switcher/releases)


