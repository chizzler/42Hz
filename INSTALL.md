# Installing 42Hz

For Arch Linux and Omarchy. 42Hz is pre-release: expect rough edges.

## Install

Needs `git` and `base-devel`. `makepkg` fetches everything else.

```sh
git clone https://github.com/chizzler/42Hz.git
cd 42Hz/packaging
makepkg -si
```

42Hz conflicts with EasyEffects. If EasyEffects is installed, pacman offers to
remove it.

## Run

Launch **42Hz** from the app launcher, or run `42hz`.
`42hz --diagnostics` reports what it found if something looks wrong.

## Update

```sh
cd 42Hz
git pull
cd packaging
makepkg -si
```

## Remove

```sh
sudo pacman -R 42hz
```

Settings and presets stay in `~/.config/42hz`. Delete that folder to remove
them too.
