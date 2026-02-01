# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

let
  useWayland = false;

  # TODO: Improve this by making it a global name keyboard layout instead of using
  #       `sessionCommands`, see https://nixos.org/nixos/manual/#custom-xkb-layouts
  #       But do this only once https://github.com/NixOS/nixpkgs/issues/117657
  #       is implemented, otherwise every single package that depends on the X server
  #       will need to be recompiled by adding a keyboard layout.
  customKeyboardLayoutScriptName = "keyboard-layout-gb-CapsLockIsHyperL";
  custom-keyboard-layout =
    # See https://nixos.wiki/wiki/Keyboard_Layout_Customization
    let
      xkb_root = ./xkb;
      compiledLayout = pkgs.runCommand "keyboard-layout" {} ''
        ${pkgs.xorg.xkbcomp}/bin/xkbcomp "-I${xkb_root}" "-R${xkb_root}" keymap/gb-CapsLockIsHyperL "$out"
      '';
    in
      pkgs.writeScriptBin customKeyboardLayoutScriptName ''
        ${pkgs.xorg.xkbcomp}/bin/xkbcomp "${compiledLayout}" "$DISPLAY"
      '';

  screenlockScriptText = lib.concatStrings [
    # Make `xsecurelock` happen on `xflock4`, `loginctl lock-session`, and suspend/hibernate.
    # Note that when we use `xss-lock` this way, the setting
    #     [ ] Lock screen when system is going to sleep
    # needs to be disabled in xfce4-power-manager's settings,
    # because otherwise `xsecurelock` is double-invoked,
    # which prevents suspend from happening on low battery,
    # requiring unlocking the first lockscreen before the second one
    # immediately appears and the system goes to sleep.
    ''
      xfconf-query --channel xfce4-session --create --property /general/LockCommand --set '${pkgs.xsecurelock}/bin/xsecurelock' --type string
      ${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.xsecurelock}/bin/xsecurelock &
    ''
  ];
  screenlockScriptName = "screenlock-script";
  screenlock-script = pkgs.writeScriptBin screenlockScriptName screenlockScriptText;

  # Needs a channel to be added via:
  #     sudo nix-channel --add https://nixos.org/channels/nixos-unstable unstable
  unstable = import <unstable> {
    config = {
      allowUnfree = true;
      permittedInsecurePackages = [
      ];
    };
  };

  # Adapted from https://github.com/NixOS/nixpkgs/issues/186570#issuecomment-1627797219
  # cura-appimage =
  #   let
  #     cura5 = pkgs.appimageTools.wrapType2 rec {
  #       name = "cura5";
  #       version = "5.9.0";
  #       src = fetchurl {
  #         url = "https://github.com/Ultimaker/Cura/releases/download/${version}/UltiMaker-Cura-${version}-linux-X64.AppImage";
  #         hash = "sha256-STtVeM4Zs+PVSRO3cI0LxnjRDhOxSlttZF+2RIXnAp4=";
  #       };
  #       extraPkgs = pkgs: with pkgs; [ ];
  #     };
  #   in
  #     writeScriptBin "cura" ''
  #       #! ${pkgs.bash}/bin/bash
  #       # AppImage version of Cura loses current working directory and treats all paths relateive to $HOME.
  #       # So we convert each of the files passed as argument to an absolute path.
  #       # This fixes use cases like `cd /path/to/my/files; cura mymodel.stl anothermodel.stl`.
  #       args=()
  #       for a in "$@"; do
  #         if [ -e "$a" ]; then
  #           a="$(realpath "$a")"
  #         fi
  #         args+=("$a")
  #       done
  #       exec "${cura5}/bin/cura5" "''${args[@]}"
  #     '';
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Needs to be installed (see https://github.com/NixOS/nixos-hardware):
      #     sudo nix-channel --add https://github.com/NixOS/nixos-hardware/archive/master.tar.gz nixos-hardware
      <nixos-hardware/lenovo/thinkpad/t470s>
    ] ++ lib.optional (builtins.pathExists ./private-configuration.nix) ./private-configuration.nix;

  options = with lib; {

    gpuMode = mkOption {
      type = types.enum [
        "intel"
        "nvidia"
        "intel-nvidia-offload" # offload mode (NVIDIA only used with `nvidia-offload` wrapper script)
        "intel-nvidia-sync" # # sync mode (both Intel and NVIDIA on all the time; resume-from-suspend gives black screen)
      ];
      default = "intel";
      description = "Which GPU to use, and how.";
      visible = false; # don't show in manual, to prevent rebuilding the manual
    };

  };

  config = {

    nixpkgs.config = {
      allowUnfree = true;
      permittedInsecurePackages = [
        "openssl-1.1.1w" # Sublime Text 4 currently needs this, see https://github.com/sublimehq/sublime_text/issues/5984
        "electron-24.8.6" # TODO: Remove once `bitwarden` has updated its electron dependency
      ];
    };

    nixpkgs.overlays = [
      (final: previous: {

        # TODO: Remove when https://github.com/rfjakob/earlyoom/pull/191 is merged and available.
        earlyoom = previous.earlyoom.overrideAttrs (old: {
          src = final.fetchFromGitHub {
            owner = "nh2";
            repo = "earlyoom";
            rev = "e0534b0ee26df23181ca326e1b7ed09520d7d4e5";
            sha256 = "1av7q5ndm7xx2rpxaqxyaidf15fndc5br9z197gzwj23wxjhjc7a";
          };
        });

        # I found some segfaults of `xfce4-notifyd`; enable debug info so next time
        # it happens I can check it (`cordumptctl`).
        xfce4.xfce4-notifyd = previous.xfce4.xfce4-notifyd.overrideAttrs (oldAttrs: {
          separateDebugInfo = true;
        });

        # nm-applet: prevent menu refresh while user is hovering over it
        # Fixes https://gitlab.gnome.org/GNOME/network-manager-applet/-/issues/160
        # From: https://gitlab.gnome.org/GNOME/network-manager-applet/-/merge_requests/169
        networkmanagerapplet = previous.networkmanagerapplet.overrideAttrs (oldAttrs: {
          patches = (oldAttrs.patches or []) ++ [
            (final.fetchpatch {
              name = "applet-prevent-menu-refresh-while-user-is-hovering-over-it.patch";
              url = "https://gitlab.gnome.org/GNOME/network-manager-applet/-/commit/6c6e9ab4392a884bc74510858a416f88c3f0ce1c.patch";
              hash = "sha256-zgBMaGBzre1hMyKWCF0A+tr4LbDx1MoKPmXi40JdGNo=";
            })
          ];
        });

      })
    ];

    # Use the systemd-boot EFI boot loader.
    boot.loader.systemd-boot.enable = true;
    boot.loader.efi.canTouchEfiVariables = true;

    boot.supportedFilesystems = [ "zfs" ];
    networking.hostId = "25252525";
    boot.zfs.requestEncryptionCredentials = true;
    # Hibernation with ZFS is unsafe; thus disable it.
    # This is likely the case even if the swap is put on a non-ZFS partition,
    # because the ZFS code paths do not handle being hibernated properly.
    # See:
    # * https://nixos.wiki/wiki/ZFS#Known_issues
    # * https://github.com/openzfs/zfs/issues/12842
    # * https://github.com/openzfs/zfs/issues/12843
    boot.kernelParams = [ "nohibernate" ];

    # Enable BBR congestion control
    boot.kernelModules = [ "tcp_bbr" ];
    boot.kernel.sysctl."net.ipv4.tcp_congestion_control" = "bbr";
    boot.kernel.sysctl."net.core.default_qdisc" = "fq"; # see https://news.ycombinator.com/item?id=14814530

    # Increase TCP window sizes for high-bandwidth WAN connections, assuming
    # 10 GBit/s Internet over 200ms latency as worst case.
    #
    # Choice of value:
    #     BPP         = 10000 MBit/s / 8 Bit/Byte * 0.2 s = 250 MB
    #     Buffer size = BPP * 4 (for BBR)                 = 1 GB
    # Explanation:
    # * According to http://ce.sc.edu/cyberinfra/workshops/Material/NTP/Lab%208.pdf
    #   and other sources, "Linux assumes that half of the send/receive TCP buffers
    #   are used for internal structures", so the "administrator must configure
    #   the buffer size equals to twice" (2x) the BPP.
    # * The article's section 1.3 explains that with moderate to high packet loss
    #   while using BBR congestion control, the factor to choose is 4x.
    #
    # Note that the `tcp` options override the `core` options unless `SO_RCVBUF`
    # is set manually, see:
    # * https://stackoverflow.com/questions/31546835/tcp-receiving-window-size-higher-than-net-core-rmem-max
    # * https://bugzilla.kernel.org/show_bug.cgi?id=209327
    # There is an unanswered question in there about what happens if the `core`
    # option is larger than the `tcp` option; to avoid uncertainty, we set them
    # equally.
    boot.kernel.sysctl."net.core.wmem_max" = 1073741824; # 1 GiB
    boot.kernel.sysctl."net.core.rmem_max" = 1073741824; # 1 GiB
    boot.kernel.sysctl."net.ipv4.tcp_rmem" = "4096 87380 1073741824"; # 1 GiB max
    boot.kernel.sysctl."net.ipv4.tcp_wmem" = "4096 87380 1073741824"; # 1 GiB max
    # We do not need to adjust `net.ipv4.tcp_mem` (which limits the total
    # system-wide amount of memory to use for TCP, counted in pages) because
    # the kernel sets that to a high default of ~9% of system memory, see:
    # * https://github.com/torvalds/linux/blob/a1d21081a60dfb7fddf4a38b66d9cef603b317a9/net/ipv4/tcp.c#L4116

    boot.extraModulePackages = [
      # For being able to flip/mirror my webcam.
      config.boot.kernelPackages.v4l2loopback
    ];

    # Register a v4l2loopback device at boot
    #boot.kernelModules = [
    # "v4l2loopback"
    #];

    # For mounting many cameras.
    # Need to set `users.users.alice.extraGroups = ["camera"];` for each user allowed.
    programs.gphoto2.enable = true;

    boot.extraModprobeConfig =
      # Enable fan control for the Thinkpad; allows spinning the fan to max with:
      #     echo level disengaged | sudo tee /proc/acpi/ibm/fan
      ''
        options thinkpad_acpi fan_control=1
      ''
      + ''
        options v4l2loopback exclusive_caps=1
      '';

    networking.hostName = "t25"; # Define your hostname.
    # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

    # The global useDHCP flag is deprecated, therefore explicitly set to false here.
    # Per-interface useDHCP will be mandatory in the future, so this generated config
    # replicates the default behaviour.
    networking.useDHCP = false;
    # Using network-manager instead.
    #networking.interfaces.enp0s31f6.useDHCP = true;
    #networking.interfaces.wlp4s0.useDHCP = true;

    # Configure network proxy if necessary
    # networking.proxy.default = "http://user:password@proxy:port/";
    # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

    # Select internationalisation properties.
    i18n = {
      # defaultLocale = "en_US.UTF-8";
    };
    console.keyMap = "uk";


    # Set your time zone.
    time.timeZone = "Europe/Berlin";

    # services.teamviewer.enable = true;

    environment.sessionVariables = {
      # Necessary for e.g. `i3` config `exec` commands to use `gsettings`,
      # e.g. to bind keys for switching light/dark mode.
      # See: https://github.com/NixOS/nixpkgs/issues/273275
      XDG_DATA_DIRS =
        let
          schema = pkgs.gsettings-desktop-schemas;
          datadir = "${schema}/share/gsettings-schemas/${schema.name}";
        in [ datadir ];
    };

    # List packages installed in system profile. To search, run:
    # $ nix search wget
    environment.systemPackages = with pkgs; [
      awscli2 # official `aws` CLI program
      autossh
      b3sum
      # cura # TODO: dependency `libarcus` is marked broken in nixpkgs
      cura-appimage
      eternal-terminal
      mumble # need at least 1.3.4 to avoid package loss
      (lib.hiPrio pkgs.parallel) # to take precedence over `parallel` from `moreutils`
      # (wineStaging.override { wineBuild = "wineWow"; }) # `wineWow` enables 64-bit support
      wineWowPackages.staging # `wineWow` enables 64-bit support
      alsa-utils
      apg
      atop
      attr.bin # for `getfattr` etc.
      bind.dnsutils # for `dig` etc.
      binutils # objdump, nm, readelf etc
      blender
      calibre
      cheese
      chromium
      cloudcompare
      cryptsetup
      custom-keyboard-layout
      screenlock-script
      # diffoscope # Re-enable when https://github.com/NixOS/nixpkgs/issues/328350 is fixed
      eog
      ethtool
      evince
      exfat
      ffmpeg
      file
      file-roller
      #(if useWayland then firefox-wayland else firefox)
      firefox
      fractal
      fzf
      gajim
      gdb
      gh
      gimp
      git
      # TODO: Replace by `delta` as soon as it's built on unstable
      diff-so-fancy
      git-absorb
      git-branchless
      glade
      mesa-demos # glxinfo
      gnome-connections
      gnome-screenshot
      gnome-system-monitor
      gnome-terminal
      gnome-themes-extra # Provides theme in the XFCE theme switcher
      gnumake
      gnupg
      gptfdisk
      graphviz
      hdparm
      htop
      imhex
      inkscape
      iotop
      iperf3
      jq
      keybase
      keybase-gui
      killall
      krename
      lapce
      libarchive # bsdtar
      libcap_ng
      libreoffice
      perf
      lm_sensors
      lsof
      lutris
      lz4
      lzop
      meld
      (meshlab.overrideAttrs (old: {
        # For debugging crashes
        # cmakeBuildType = "RelWithDebInfo";
        # dontStrip = true;
        # hardeningDisable = [ "all" ];

        patches = (old.patches or []) ++ [
          # TODO: Remove when https://github.com/Z3roCo0l/meshlab/commit/bcf2d6c201738c32f69afc347eb88d5a93218e7f is PR'd, merged, and available
          (pkgs.fetchpatch {
            name = "meshlab-Dialogbox-for-mainwindow-actions.patch";
            url = "https://github.com/Z3roCo0l/meshlab/commit/bcf2d6c201738c32f69afc347eb88d5a93218e7f.patch";
            sha256 = "sha256-oRBKQVq4fOmeD9OZFW3f7pXKkvuj41dJ0IyYaVSl0F0=";
          })
          (pkgs.fetchpatch {
            name = "meshlab-Remove-dialogbox-from-new-project-function.patch";
            url = "https://github.com/Z3roCo0l/meshlab/commit/d887778f09a1ff954f46c68a9c4c306556981440.patch";
            sha256 = "sha256-rsIcZv8zB1it/RR+fYxQODPqqUjP3C2mdhzCTD8i3g8=";
          })
          (pkgs.fetchpatch {
            name = "meshlab-Inverting-Selection-mode-CTRL-modifier.patch";
            url = "https://github.com/Z3roCo0l/meshlab/commit/799975189feaa951344f89c24155d7f1f32906f1.patch";
            sha256 = "sha256-FUPWiRgO+/f49w5TMbX3a7baAaz7wfYPm8Qp1CtIm+c=";
          })
        ];
      }))
      moreutils
      mosh
      mplayer
      mpv
      nautilus # xfce's `thunar` freezes the UI during large MTP transfers, nautilus doesn't
      ncdu
      nebula
      netcat-openbsd
      nix-diff
      nix-index
      nix-output-monitor
      nix-tree
      nixpkgs-review
      nload
      nmap
      nom
      # ntfy
      openscad
      openssl
      p7zip
      paprefs
      parted
      (pass.withExtensions (exts: [ exts.pass-otp ]))
      pasystray
      patchelf
      pavucontrol
      pdfarranger
      pciutils # lspci
      powertop
      psmisc # fuser
      pv
      (python3.withPackages (ps: with ps; [ numpy ]))
      qrencode
      qtpass
      rclone
      remmina
      reptyr
      ripgrep
      rofi
      rxvt-unicode
      screen
      screen-message
      scrot
      shellcheck
      signal-desktop
      smartmontools
      smem
      sshfs-fuse
      stack
      stress-ng
      sublime4
      # sublime-merge
      sysdig
      sysstat
      tesseract
      tcpdump
      texmacs
      thunderbird
      totem
      traceroute
      unzip
      usbutils # for lsusb
      v4l-utils
      veracrypt
      vlc
      vokoscreen-ng
      wget
      wirelesstools # iwconfig/iwgetid for wifi info
      wireshark
      x11vnc
      xclip
      xorg.xhost
      xorg.xev
      xorg.xkbcomp
      xorg.xkill
      xorg.xwininfo
      xournalpp
      xpra
      xsecurelock
      xss-lock
      yubikey-personalization
      yubioath-flutter
      yubikey-manager # for `ykman`, e.g. to set the touch requirement for PGP
      zip
      zoom-us

      apcupsd
      rustc cargo binutils gcc pkg-config # Rust development (from https://nixos.org/nixpkgs/manual/#rust)
      cmake freetype # for Alacritty rust development

      audacity
      simplescreenrecorder
      ghc

      cmakeWithGui
      gitg

      # TODO Answer https://discourse.nixos.org/t/gst-all-1-gstreamer-packages-does-not-install-gst-launch-1-0-etc/5369
      gst_all_1.gstreamer.dev
      yt-dlp

      gparted
      ntfs3g # for mounting NTFS USB drives

      marktext

      slack
      libnotify # for `notify-send`

      xdotool
      valgrind
      sqlite
      glib # gio for MTP mounting

      discord
      zstd

      nix-prefetch-github

      # man pages
      man-pages # Linux development manual pages (2p syscalls / wrappers)
      glibcInfo # GNU Info manual of the GNU C Library

      blugon # blue-light filter

      inotify-tools # for inotifywait etc.

      # ripcord

      nix-top

      python3Packages.grip
      bup

      deskflow # replacement for synergy/barrier/input-leap

      virt-manager

      zbar # QR code reader

      vim
      # TODO: Cannot currently use the following, it breaks the Backspace and
      #       Delete keys, see https://github.com/LnL7/vim-nix/issues/38.
      # From https://nixos.wiki/wiki/Editor_Modes_for_Nix_Files#vim-nix
      (pkgs.vim-full.customize {
        name = "vim";
        vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
          # start = [ vim-nix ]; # load plugin on startup
          start = []; # load plugin on startup
        };
      })

      vscode

      turbovnc

      bitwarden-desktop

      bupstash

      # OnlyOffice. Sstart with `DesktopEditors`.
      # I had to download Windows fonts `Symbol.ttf` and `wingding.ttf`
      # into `~/.local/share/fonts/` for bullet points to look correct,
      # and Calibri to render my Calibri-written Word docs correctly.
      # Arial is also required to be put there so that the default templates
      # look as expected.
      onlyoffice-desktopeditors

      config.boot.kernelPackages.nvidia_x11

      wireguard-tools
    ];

    # documentation.dev.enable = true;

    powerManagement.enable = true;

    # When suspending, kill all sshfs instances, as otherwise it can make
    # either suspend or resume hang (hang on resume requires force reboot).
    powerManagement.powerDownCommands = ''
      ${pkgs.procps}/bin/pkill -9 sshfs
    '';

    # Some programs need SUID wrappers, can be configured further or are
    # started in user sessions.
    programs.mtr.enable = true;
    programs.gnupg.agent = { enable = true; enableSSHSupport = true; };

    programs.ssh.extraConfig = ''
      # Don't ask for fingerprint confirmation on first connection.
      # If we know the fingerprint ahead of time, we should put it into `known_hosts` directly.
      StrictHostKeyChecking=accept-new
    '';

    # List services that you want to enable:

    # Enable the OpenSSH daemon.
    services.openssh.enable = true;

    networking.firewall = {
      # Reject instead of drop.
      rejectPackets = true;
      logRefusedConnections = false; # Helps with auth brueforce log spam.
      # Open ports in the firewall.
      allowedTCPPorts = [
        5201 # iperf3
      ];
      allowedUDPPorts = [
        69 # tftp
        5201 # iperf3
      ];
      # Or disable the firewall altogether.
      # enable = false;
    };

    networking.networkmanager.enable = true;

    services.avahi = {
      enable = true;
      nssmdns4 = true; # allows pinging *.local from this machine
      publish = { # allows other machines to see this one
        enable = true;
        addresses = true;
        workstation = true;
      };
    };

    # Enable CUPS to print documents.
    services.printing.enable = true;
    services.printing.drivers = with pkgs; [
      brlaser
      gutenprint
      hplip
    ];

    # To fix ThinkPad throttling too early. See https://news.ycombinator.com/item?id=35026337
    services.thermald.enable = true;

    # Disabled in order to use PipeWire, as recommended on https://nixos.wiki/wiki/PipeWire
    # # Enable sound.
    # sound.enable = true;
    # services.pulseaudio.enable = true;
    # # Network sink streaming support
    # services.pulseaudio.tcp.enable = true;
    # # Note: As of writing (20.03), enabling zeroconf adds an `avahi` dep to the
    # #       pulseaudio dep so it will be compiled, not fetched from cache.
    # # services.pulseaudio.zeroconf.discovery.enable = true;
    # # TODO: disable
    # # services.pulseaudio.zeroconf.publish.enable = true;

    # Bluetooth
    hardware.bluetooth.enable = true;
    hardware.bluetooth.powerOnBoot = false;
    services.blueman.enable = true;

    security.rtkit.enable = true; # rtkit is optional but recommended for PipeWire
    services.pipewire = {
      enable = true;
      alsa.enable = true;
      # alsa.support32Bit = true; # probably no longer needed
      pulse.enable = true;
      # The below was configurable via NixOS options in the past but is no longer.
      # If I want this, it should go into `/etc/pipewire/pipewire.conf.d/`:
      #
      #     # Trying to fix crackling (more apparent when many audio sources are playing simultaneously):
      #     # Does not seem to help :(
      #     "context.properties" = {
      #       "default.clock.quantum" = "2048";
      #       "default.clock.min-quantum" = "1024";
      #       "default.clock.max-quantum" = "4096";
      #     };
    };

    # Allow core dumps.
    # Truncated core dumps are not very useful to GDB, see:
    # * https://unix.stackexchange.com/questions/155389/can-anything-useful-be-done-with-a-truncated-core
    systemd.settings.Manager = {
      # core dump limit in KB
      DefaultLimitCORE = 20000000;

      # Note that systemd-coredump may still throw away coredumps if you have
      # < 15% disk free, see:
      # https://unix.stackexchange.com/questions/554442/coredumpctl-cannot-read-core-dump-gives-message-file-is-not-readable-or-no-su/554460#554460
    };

    # Install debug symbols for all packages that provide it.
    #environment.enableDebugInfo = true;

    hardware.sane.enable = true; # enables support for SANE scanners
    # Override disabled because of this claim that the problem is fixed; need to validate when I have the scanner: https://github.com/NixOS/nixpkgs/pull/328459#issuecomment-2244359050
    hardware.sane.backends-package = lib.mkIf false (pkgs.sane-backends.overrideAttrs (old: {
      configureFlags = (old.configureFlags or []) ++ [
        # "--localstatedir=/var" # `sane-backends` puts e.g. lock files in here, must not be in /nix/store
        # "--with-lockdir=/var/lock/sane" # `sane-backends` puts e.g. lock files in here, must not be in /nix/store

        # Ugly workaround for https://github.com/NixOS/nixpkgs/issues/273280#issuecomment-1848873028
        # Really we should make `sane-backends` be able to provide a real lock dir (e.g. `/var/lock/sane`).
        "--disable-locking"
      ];
      # Alternative workaround for https://github.com/NixOS/nixpkgs/issues/273280#issuecomment-1848873028
      # We'd prefer to just set in `configureFlags`
      #     "--localstatedir=/var" # `sane-backends` puts e.g. lock files in here, must not be in /nix/store
      # but that does not work because the install step tries to create this directory,
      # which fails in the nix build sandbox.
      # So instead, we set the preprocessor variable directly, see:
      #     https://gitlab.com/sane-project/backends/-/blob/65779d6b595547d155a1954958bce5faaad45a5d/configure.ac#L635-652
      # A problem is that this lock dir also needs to exist and have write permissions.
      # Right now you have to do that manually with:
      #     sudo mkdir -p /var/lock/sane && sudo chown root:scanner /var/lock/sane && sudo chmod g+w /var/lock/sane
      # Maybe we should use the `scanner` group for that, and/or configure it with systemd `tmpfiles`.
      #NIX_CFLAGS_COMPILE = "-DPATH_SANE_LOCK_DIR=/var/lock/sane";
    }));

    # Enable the X11 windowing system.
    services.xserver.enable = !useWayland;
    # Produce XKB dir containing custom keyboard layout by symlink-copying
    # the normal XKB dir, and copying our keymap in.
    # TODO: This might stop working in the future:
    #       https://github.com/NixOS/nixpkgs/pull/138207#issuecomment-972442368
    services.xserver.xkb.dir = pkgs.runCommand "custom-keyboard-layout-xkb-dir" {} ''
      cp -r --dereference "${pkgs.xkeyboard_config}/share/X11/xkb" "$out"
      chmod -R u+w "$out"

      mkdir -p "$out/keymap"
      cp ${./xkb/keymap}/* "$out/keymap"
      mkdir -p "$out/symbols"
      cp ${./xkb/symbols}/* "$out/symbols"
    '';
    services.xserver.xkb.layout = "gb-CapsLockIsHyperL";
    # services.xserver.xkbOptions = "eurosign:e";

    # Enable touchpad support.
    services.libinput.enable = true;

    specialisation."nvidia".configuration = {
      system.nixos.tags = [ "nvidia" ];
      gpuMode = "nvidia";
    };
    specialisation."intel-nvidia-offload".configuration = {
      system.nixos.tags = [ "intel-nvidia-offload" ];
      gpuMode = "intel-nvidia-offload";
    };
    specialisation."intel-nvidia-sync".configuration = {
      system.nixos.tags = [ "intel-nvidia-sync" ];
      gpuMode = "intel-nvidia-sync";
    };

    services.xserver.videoDrivers = {
      "intel" = [ "modesetting" ];
      "nvidia" = [ "nvidia" ];
      # For offloading, `modesetting` is needed additionally,
      # otherwise the X-server will be running permanently on nvidia,
      # thus keeping the GPU always on (see `nvidia-smi`).
      # See https://discourse.nixos.org/t/how-to-use-nvidia-prime-offload-to-run-the-x-server-on-the-integrated-board/9091/31
      "intel-nvidia-offload" = [ "modesetting" "nvidia" ];
      "intel-nvidia-sync" = [ "nvidia" ];
    }.${config.gpuMode};
    hardware.nvidia.open = false; # The 940MX is too old for the open module.
    # See https://nixos.wiki/wiki/Nvidia#offload_mode
    # Disabled for VFIO for now
    hardware.nvidia.prime = lib.mkIf (!useWayland) {
      offload = lib.mkIf (config.gpuMode == "intel-nvidia-offload") {
        enable = true;
        enableOffloadCmd = true;
      };
      sync.enable = config.gpuMode == "intel-nvidia-sync";

      # Bus ID of the NVIDIA GPU. You can find it using lspci, either under 3D or VGA
      nvidiaBusId = "PCI:2:0:0";

      # Bus ID of the Intel GPU. You can find it using lspci, either under 3D or VGA
      intelBusId = "PCI:0:2:0";
    };
    hardware.nvidia.powerManagement.enable = true;
    hardware.nvidia.modesetting.enable = true;
    hardware.nvidia.dynamicBoost.enable = {
      "intel" = false;
      "nvidia" = true;
      "intel-nvidia-offload" = true;
      "intel-nvidia-sync" = true;
    }.${config.gpuMode};

    # Enable the KDE Desktop Environment.
    # services.xserver.displayManager.sddm.enable = true;
    # services.xserver.desktopManager.plasma5.enable = true;

    services.xserver.displayManager.lightdm.enable = !useWayland;
    services.xserver.displayManager.sessionCommands = ''
      # Map Caps_Lock to Hyper_L
      ${custom-keyboard-layout}/bin/${customKeyboardLayoutScriptName}

      # Turn on screen locker
      ${screenlockScriptText}

      # Screen notifications
      ${pkgs.xfce.xfce4-notifyd}/lib/xfce4/notifyd/xfce4-notifyd &
    '';

    # Make polkit prompt show only 1 choice instead of both root and all `wheel` users.
    security.polkit.adminIdentities = [ "unix-group:wheel" ];

    # Enables user icons in display manager.
    services.accounts-daemon.enable = true;

    services.xserver.desktopManager = {
      xterm.enable = false;
      # TODO: NixOS 20.03 adds a lot of new stuff for XFCE, see
      # https://github.com/NixOS/nixpkgs/commit/04e56aa016a19c8c8af1f02176bf230e02e6d6b8
      # This means we can disable a lot of manually set options when we're on that.
      xfce = {
        enable = true;
        noDesktop = true;
        enableXfwm = false;
      };
    };
    services.displayManager.defaultSession = "xfce+i3";
    services.xserver.windowManager.i3 = {
      enable = true;
      extraPackages = with pkgs; [
        dmenu
        i3status
        i3lock
      ];
    };

    programs.sway = lib.mkIf useWayland {
      enable = true;
      wrapperFeatures.gtk = true; # so that gtk works properly
      extraPackages = with pkgs; [
        swaylock
        swayidle
        wl-clipboard
        mako # notification daemon
        alacritty # Alacritty is the default terminal in the config
        dmenu # Dmenu is the default in the config but i recommend wofi since its wayland native
      ];
    };
    xdg = lib.mkIf useWayland {
      portal = {
        enable = true;
        wlr.enable = true;
        extraPortals = with pkgs; [
          xdg-desktop-portal-gtk
        ];
        gtkUsePortal = true;
      };
    };

    # Brightness control, see https://nixos.wiki/wiki/Backlight#Key_mapping
    programs.light.enable = true;
    services.actkbd = {
      enable = true;
      bindings = [
        { keys = [ 224 ]; events = [ "key" ]; command = "/run/current-system/sw/bin/light -U 5"; }
        { keys = [ 225 ]; events = [ "key" ]; command = "/run/current-system/sw/bin/light -A 5"; }
      ];
    };

    fonts.packages = with pkgs; [
      noto-fonts-cjk-sans # fixes e.g. Chinese characters being invisible in chromium
    ];

    # earlyoom; I have swap enabled for hibernation, so any swapping
    # causes irrecoverable GUI freezes. earlyoom makes them short.
    services.earlyoom = {
      enable = true;
      # freeMemThreshold = 5; # percent
      freeMemThreshold = 10; # using a bit more because even https://github.com/rfjakob/earlyoom/pull/191 under-computes the amount of memory ZFS needs
      # See note below
      freeSwapThreshold = 100; # percent
      freeSwapKillThreshold = 100; # see https://github.com/NixOS/nixpkgs/issues/83504
    };

    # Testing this scheduler to see how it affects desktop responsiveness.
    #services.system76-scheduler.enable = true;
    # Disabled for now to check if it fixes the occasional load spikes up to 50.0

    # zsh
    programs.zsh.enable = true;
    programs.zsh.interactiveShellInit = ''
      # Enable the below for profiling zsh's startup speed.
      # Once enabled, get numbers using:
      #     zsh -i -l -c 'zprof'
      #zmodload zsh/zprof

      # Disable `compaudit` being invoked from GRML cominit call.
      # See: https://grml.org/zsh/grmlzshrc.html
      # This speeds up shell loading.
      zstyle ':grml:completion:compinit' arguments -C

      # Load grml's zshrc.
      # Note that loading grml's zshrc here will override NixOS settings such as
      # `programs.zsh.histSize`, so they will have to be set again below.
      source ${pkgs.grml-zsh-config}/etc/zsh/zshrc

      # From https://htr3n.github.io/2018/07/faster-zsh/
      # Theoretically it should not be needed (as described on https://dev.to/djmoch/zsh-compinit--rtfm-47kg)
      # but I couldn't figure out how to make the GRML zshrc do only a single compinit
      # without compaudit but generating .zcompdump (I use `-C` for
      # `:grml:completion:compinit` above to avoid compaudit but that also skips
      # generating `.zcompdump` apparently).
      # Snippet based on https://gist.github.com/ctechols/ca1035271ad134841284
      autoload -Uz compinit
      if [[ -n ${ZDOTDIR:-$HOME}/.zcompdump(#qN.mh+24) ]]; then
        compinit
      else
        # We don't do `compinit -C` here because the GRML zshrc already did it above.
      fi

      # Disable grml's persistent dirstack feature.
      # This ensures that it cannot hang the shell when `.zdirs` contains
      # a path from a slow/hanging network mount.
      # This needs to be done before loading grml's zshrc, see:
      # https://github.com/grml/grml-etc-core/issues/136
      zstyle ':grml:chpwd:dirstack' enable false

      alias d='ls -lah'
      alias g=git

      # Increase history size.
      HISTSIZE=10000000

      # Prompt modifications.
      #
      # In current grml zshrc, changing `$PROMPT` no longer works,
      # and `zstyle` is used instead, see:
      # https://unix.stackexchange.com/questions/656152/why-does-setting-prompt-have-no-effect-in-grmls-zshrc

      # Disable the grml `sad-smiley` on the right for exit codes != 0;
      # it makes copy-pasting out terminal output difficult.
      # Done by setting the `items` of the right-side setup to the empty list
      # (as of writing, the default is `items sad-smiley`).
      # See: https://bts.grml.org/grml/issue2267
      zstyle ':prompt:grml:right:setup' items

      # Keybinding modifications
      source ${./zsh/keybindings-alt-left-right-word-jumping.zsh}
      source ${./zsh/disable-home-end-history-jumping.zsh}

      # Add nix-shell indicator that makes clear when we're in nix-shell.
      # Set the prompt items to include it in addition to the defaults:
      # Described in: http://bewatermyfriend.org/p/2013/003/
      function nix_shell_prompt () {
        REPLY=''${IN_NIX_SHELL+"(nix-shell) "}
      }
      grml_theme_add_token nix-shell-indicator -f nix_shell_prompt '%F{magenta}' '%f'
      zstyle ':prompt:grml:left:setup' items rc nix-shell-indicator change-root user at host path vcs percent
    '';
    programs.zsh.promptInit = ""; # otherwise it'll override the grml prompt
    # Speed up zsh start by running compinit manually (see config above).
    programs.zsh.enableGlobalCompInit = false;

    # Credential storage for GNOME programs (also gajim, fractal).
    # Otherwise they won't remember credentials across restarts.
    services.gnome.gnome-keyring.enable = true;

    # Without this `gnome-terminal` errors with:
    #     Error constructing proxy for org.gnome.Terminal:/org/gnome/Terminal/Factory0: Error calling StartServiceByName for org.gnome.Terminal: Unit gnome-terminal-server.service not found.
    programs.gnome-terminal.enable = true;

    # i3 needs it, see https://nixos.wiki/wiki/I3#DConf
    programs.dconf.enable = true;
    services.dbus.packages = [ pkgs.dconf ];

    # Yubikey
    services.udev.packages = [ pkgs.yubikey-personalization ];
    services.pcscd.enable = true;

    # Ultimate Hacking Keyboard
    services.udev.extraRules = ''
      # These are the udev rules for accessing the USB interfaces of the UHK as non-root users.
      # Copy this file to /etc/udev/rules.d and physically reconnect the UHK afterwards.
      SUBSYSTEM=="input", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="612[0-7]", GROUP="input", MODE="0660"
      SUBSYSTEMS=="usb", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="612[0-7]", TAG+="uaccess"
      KERNEL=="hidraw*", ATTRS{idVendor}=="1d50", ATTRS{idProduct}=="612[0-7]", TAG+="uaccess"
    '';

    # locate
    services.locate = {
      enable = true;
      package = pkgs.mlocate;
    };

    # Android adb
    programs.adb.enable = true;

    # Define a user account. Don't forget to set a password with ‘passwd’.
    users.users.niklas = {
      isNormalUser = true;
      extraGroups = [
        # TODO: check if necessary
        "adbusers" # Android ADB, see https://nixos.wiki/wiki/Android
        "audio" # See https://nixos.wiki/wiki/PulseAudio
        "networkmanager"
        "wheel" # Enable ‘sudo’ for the user.
        "camera" # Enable `gphoto2` camera access.
        "libvirtd" # manage VMs
        "mlocate" # allow using `locate`
        "scanner"
        "lp" # scanners that are also a printer
      ];
      shell = pkgs.zsh;
    };

    virtualisation.virtualbox.host.enable = true;
    users.extraGroups.vboxusers.members = [ "niklas" ];

    virtualisation.libvirtd = {
      enable = true;
      qemu.runAsRoot = false;
      onBoot = "ignore";
      onShutdown = "shutdown";
    };

    # For testing NixOS updates without letting newer versions mess with normal
    # user's home directory contents.
    users.users.nixos-test = {
      isNormalUser = true;
      extraGroups = [
        # TODO: check if necessary
        "audio" # See https://nixos.wiki/wiki/PulseAudio
        "networkmanager"
      ];
      # The password is set in `private-configuration.nix`.
    };

    # This value determines the NixOS release with which your system is to be
    # compatible, in order to avoid breaking some software such as database
    # servers. You should change this only after NixOS release notes say you
    # should.
    system.stateVersion = "25.05"; # Did you read the comment?

    # services.keybase.enable = true;

    hardware.trackpoint = {
      enable = true;
      # Documentation of the options is at:
      #     https://www.kernel.org/doc/Documentation/ABI/testing/sysfs-devices-platform-trackpoint
      sensitivity = 215; # default is too slow for me; 215 seems to be the max
    };

    # xinput to set my preferred scroll behaviour for the Tex Shinobi,
    # via `xorg.conf` so that it also applies when re-plugged.
    # The default scroll behaviour is:
    #     services.xserver.libinput.mouse.scrollMethod = "twofinger";
    # and we want the equivalent of
    #     services.xserver.libinput.mouse.scrollMethod = "button";
    # but only for this specific keyboard's trackpoint.
    # TODO: Until the above issue about naming is solved,
    #       the Shinobi is called `USB-HID Keyboard Mouse`.)
    services.xserver.config = ''
      # Instead of:
      #     xinput set-int-prop "USB-HID Keyboard Mouse" "libinput Scroll Method Enabled" 8 0 0 1
      # See: https://bbs.archlinux.org/viewtopqic.php?pid=1941373#p1941373
      # `0 0 1` translates to `button`, see https://www.mankier.com/4/libinput
      # in section `libinput Scroll Method Enabled`.

      Section "InputClass"
        Identifier   "Tex Shinobi scroll settings"
        MatchDriver  "libinput"
        MatchProduct "USB-HID Keyboard Mouse"
        Option       "ScrollMethod" "button"
      EndSection
    '';

    services.fwupd.enable = true;

    # Nvidia VFIO passthrough IOMMU settings, see
    # * https://alexbakker.me/post/nixos-pci-passthrough-qemu-vfio.html
    # * https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF
    # `DEVS` entry IDs are from https://wiki.archlinux.org/index.php/PCI_passthrough_via_OVMF#Ensuring_that_the_groups_are_valid,
    # which for me is
    #     IOMMU Group 10:
    #       02:00.0 3D controller [0302]: NVIDIA Corporation GM108M [GeForce 940MX] [10de:134d] (rev a2)
    # boot.kernelParams = [
    #   "intel_iommu=on" "iommu=pt"
    #   "video=efifb:off"
    # ];
    # boot.initrd.availableKernelModules = [ "vfio-pci" ];
    # boot.initrd.preDeviceCommands = ''
    #   DEVS="0000:02:00.0"
    #   for DEV in $DEVS; do
    #     echo "vfio-pci" > /sys/bus/pci/devices/$DEV/driver_override
    #   done
    #   modprobe -i vfio-pci
    # '';
    # # test by nh2
    # boot.blacklistedKernelModules = [ "nouveau" ];


    # Intel GPU passthrough

    # boot.kernelParams = [
    #   "intel_iommu=on" "iommu=pt"
    # ];
    # # See
    # # * https://nixos.wiki/wiki/IGVT-g
    # # * https://wiki.archlinux.org/index.php/Intel_GVT-g
    # virtualisation.kvmgt = {
    #   enable = true;
    #   vgpus = {
    #     "i915-GVTg_V5_2" = { # decides resolution, VRAM etc.
    #       uuid = [ "30d6a6bb-d06f-4e71-baf8-d75a4fb54c13" ]; # arbitrary; made with `uuidgen`
    #     };
    #   };
    # };

    boot.blacklistedKernelModules = [ "nouveau" ];

    # With the below, running games like Dota2 currently requires using `steam-run`, e.g.:
    #     steam-run ~/.steam/steam/steamapps/common/dota\ 2\ beta/game/bin/linuxsteamrt64/dota2
    # Otherwise they hang with a library error on startup.
    programs.steam.enable = true;

  };
}
