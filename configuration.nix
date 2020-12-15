# Edit this configuration file to define what should be installed on
# your system.  Help is available in the configuration.nix(5) man page
# and in the NixOS manual (accessible by running ‘nixos-help’).

{ config, pkgs, lib, ... }:

let
  # TODO: Improve this by making it a global name keyboard layout instead of using
  #       `sessionCommands`, see https://nixos.org/nixos/manual/#custom-xkb-layouts
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
    ''
      xfconf-query --channel xfce4-session --create --property /general/LockCommand --set '${pkgs.xsecurelock}/bin/xsecurelock' --type string
      ${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.xsecurelock}/bin/xsecurelock &
    ''
  ];
  screenlockScriptName = "screenlock-script";
  screenlock-script = pkgs.writeScriptBin screenlockScriptName screenlockScriptText;

  # From https://nixos.wiki/wiki/Nvidia#offload_mode
  nvidia-offload = pkgs.writeShellScriptBin "nvidia-offload" ''
    export __NV_PRIME_RENDER_OFFLOAD=1
    export __NV_PRIME_RENDER_OFFLOAD_PROVIDER=NVIDIA-G0
    export __GLX_VENDOR_LIBRARY_NAME=nvidia
    export __VK_LAYER_NV_optimus=NVIDIA_only
    exec -a "$0" "$@"
  '';

  # Trying to have pulseaudio forbid Chromium to adjust volume gain,
  # but so far none of these have been effective.
  # See https://askubuntu.com/questions/689209/how-to-disable-microphone-volume-auto-adjustment-in-cisco-webex
  puseaudio_with_mic_boost_disabled =
    let
      constantVolume = 40;
    in
    pkgs.pulseaudio.overrideAttrs (old: {
      # name = "pulseaudio-patched";
      name = "${old.name}-patched-without-mic-boost";
      # Instead of overriding some post-build action, which would require a
      # pulseaudio rebuild, we override the entire `buildCommand` to produce
      # its outputs by copying the original package's files (much faster).
      buildCommand = ''
        set -euo pipefail

        ${# Copy original files, for each split-output (`out`, `dev` etc.).
          lib.concatStringsSep "\n"
            (map
              (outputName:
                ''
                  echo "Copying output ${outputName}"
                  set -x
                  cp -a ${pkgs.pulseaudio.${outputName}} ''$${outputName}
                  set +x
                ''
              )
              old.outputs
            )
        }

        # Replace:
        #     [Element Capture]
        #     switch = mute
        #     volume = merge
        # by:
        #     [Element Capture]
        #     switch = mute
        #     volume = ${toString constantVolume}
        # The target file `analog-input-internal-mic.conf` should be determined
        # by the output of `pacmd list-sources` for the relevant microphone `index:`,
        # which for my microphone is:
        #     active port: <analog-input-internal-mic>
        set -x
        INFILE=$out/share/pulseaudio/alsa-mixer/paths/analog-input-internal-mic.conf
        cat $INFILE \
          | ${pkgs.python3}/bin/python -c 'import re,sys; print(re.sub(r"\[Element Capture\]\nswitch = mute\nvolume = merge", "[Element Capture]\nswitch = mute\nvolume = ${toString constantVolume}", sys.stdin.read()))' \
          > tmp.conf
        # Ensure file changed (something was replaced)
        ! cmp tmp.conf $INFILE
        chmod +w $out/share/pulseaudio/alsa-mixer/paths/analog-input-internal-mic.conf
        cp tmp.conf $INFILE
        set +x
      '';
    });

  # Needs a channel to be added via:
  #     sudo nix-channel --add https://nixos.org/channels/nixos-unstable unstable
  unstable = import <unstable> { config.allowUnfree = true; };
in
{
  imports =
    [ # Include the results of the hardware scan.
      ./hardware-configuration.nix
      # Needs to be installed (see https://github.com/NixOS/nixos-hardware):
      #     sudo nix-channel --add https://github.com/NixOS/nixos-hardware/archive/master.tar.gz nixos-hardware
      <nixos-hardware/lenovo/thinkpad/t470s>
    ] ++ lib.optional (builtins.pathExists ./private-configuration.nix) ./private-configuration.nix;

  nixpkgs.config.allowUnfree = true;

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
    })
  ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "25252525";
  boot.zfs.requestEncryptionCredentials = true;

  # Enable exFAT support to use external storage (USB drives, SD cards etc).
  boot.extraModulePackages = [ config.boot.kernelPackages.exfat-nofuse ];

  # For mounting many cameras.
  # Need to set `users.users.alice.extraGroups = ["camera"];` for each user allowed.
  programs.gphoto2.enable = true;

  # Enable fan control for the Thinkpad; allows spinning the fan to max with:
  #     echo level disengaged | sudo tee /proc/acpi/ibm/fan
  boot.extraModprobeConfig = ''
    options thinkpad_acpi fan_control=1
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

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    awscli2 # official `aws` CLI program
    cura
    eternal-terminal
    mumble
    (lib.hiPrio pkgs.parallel) # to take precedence over `parallel` from `moreutils`
    # (wineStaging.override { wineBuild = "wineWow"; }) # `wineWow` enables 64-bit support
    wineWowPackages.staging # `wineWow` enables 64-bit support
    atop
    attr.bin # for `getfattr` etc.
    bind.dnsutils # for `dig` etc.
    binutils # objdump, nm, readelf etc
    blender
    calibre
    chromium
    custom-keyboard-layout
    screenlock-script
    diffoscope
    ethtool
    file
    firefox
    fzf
    gajim
    gdb
    gimp
    git
    # TODO: Replace by `delta` as soon as it's built on unstable
    gitAndTools.diff-so-fancy
    gitAndTools.git-absorb
    gitAndTools.hub
    glxinfo
    gnome-themes-standard # Provides theme in the XFCE theme switcher
    gnome3.cheese
    gnome3.eog
    gnome3.evince
    gnome3.file-roller
    gnome3.glade
    gnome3.gnome-screenshot
    gnome3.gnome-system-monitor
    gnome3.gnome-terminal
    gnome3.nautilus # xfce's `thunar` freezes the UI during lage MTP transfers, nautilus doesn't
    gnome3.totem
    gnome3.vinagre
    gnumake
    gnupg
    gptfdisk
    graphviz
    hdparm
    htop
    inkscape
    iotop
    iperf3
    jq
    keybase
    keybase-gui
    killall
    libcap_ng
    libreoffice
    linuxPackages.perf
    lm_sensors
    lsof
    lz4
    lzop
    meld
    meshlab
    moreutils
    mplayer
    ncdu
    netcat-openbsd
    nix-diff
    nix-index
    nix-review
    nload
    openscad
    openssl
    paprefs
    parted
    (pass.withExtensions (exts: [ exts.pass-otp ]))
    pasystray
    patchelf
    pavucontrol
    pciutils # lspci
    powertop
    pv
    python3
    qtpass
    rclone
    reptyr
    ripgrep
    rofi
    rxvt-unicode
    screen
    screen-message
    signal-desktop
    skype
    smartmontools
    smem
    sshfs-fuse
    stack
    steam
    stress-ng
    sublime3
    sublime-merge
    sysdig
    sysstat
    tcpdump
    thunderbird
    traceroute
    unzip
    usbutils # for lsusb
    vlc
    wget
    wireshark
    xorg.xev
    xorg.xkbcomp
    xorg.xkill
    xorg.xwininfo
    xournal
    xsecurelock
    xss-lock
    yubikey-personalization
    yubikey-personalization-gui
    yubikey-manager # for `ykman`, e.g. to set the touch requirement for PGP
    zip
    zoom-us

    apcupsd
    rustc cargo binutils gcc pkgconfig # Rust development (from https://nixos.org/nixpkgs/manual/#rust)
    cmake freetype # for Alacritty rust development

    audacity
    obs-studio
    simplescreenrecorder
    ghc

    cmakeWithGui
    gitg

    # TODO Answer https://discourse.nixos.org/t/gst-all-1-gstreamer-packages-does-not-install-gst-launch-1-0-etc/5369
    gst_all_1.gstreamer.dev
    youtube-dl

    gparted
    ntfs3g # for mounting NTFS USB drives

    marktext

    slack
    libnotify # for `notify-send`

    unstable.jetbrains.clion
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

    ripcord

    luminanceHDR

    nix-top

    python3Packages.grip
    bup

    barrier

    nvidia-offload

    virt-manager

    zbar # QR code reader

    # From https://nixos.wiki/wiki/Editor_Modes_for_Nix_Files#vim-nix
    (pkgs.vim_configurable.customize {
      name = "vim";
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
        start = [ vim-nix ]; # load plugin on startup
      };
    })
  ];

  # documentation.dev.enable = true;

  powerManagement.enable = true;

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

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  networking.networkmanager.enable = true;

  services.avahi = {
    enable = true;
    nssmdns = true; # allows pinging *.local from this machine
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

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;
  hardware.pulseaudio.package = puseaudio_with_mic_boost_disabled;
  # Network sink streaming support
  hardware.pulseaudio.tcp.enable = true;
  # Note: As of writing (20.03), enabling zeroconf adds an `avahi` dep to the
  #       pulseaudio dep so it will be compiled, not fetched from cache.
  # hardware.pulseaudio.zeroconf.discovery.enable = true;
  # TODO: disable
  # hardware.pulseaudio.zeroconf.publish.enable = true;

  # Steam needs this, see https://nixos.org/nixpkgs/manual/#sec-steam-play
  hardware.opengl.driSupport32Bit = true;
  hardware.pulseaudio.support32Bit = true;
  hardware.opengl.extraPackages = with pkgs; [
    # See https://www.reddit.com/r/DotA2/comments/e24l6q/a_game_file_appears_to_be_missing_or_corrupted/
    libva
  ];

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.layout = "gb";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable touchpad support.
  services.xserver.libinput.enable = true;

  services.xserver.videoDrivers = [ "nvidia" ];
  # See https://nixos.wiki/wiki/Nvidia#offload_mode
  hardware.nvidia.prime = {
    offload.enable = true; # offload mode (NVIDIA only used with `nvidia-offload` wrapper script)
    # sync.enable = true; # sync mode (both Intel and NVIDIA on all the time; resume-from-suspend gives black screen)

    # Bus ID of the NVIDIA GPU. You can find it using lspci, either under 3D or VGA
    nvidiaBusId = "PCI:2:0:0";

    # Bus ID of the Intel GPU. You can find it using lspci, either under 3D or VGA
    intelBusId = "PCI:0:2:0";
  };
  hardware.nvidia.powerManagement.enable = true;
  # hardware.nvidia.modesetting.enable = true;

  # Workaround to make standby resume work with nvidia without getting a black screen because the display is off.
  # See https://github.com/NixOS/nixpkgs/issues/73494
  systemd.services.nvidia-resume.serviceConfig = {
    # Note: This has lightdm hardcoded.
    ExecStartPost = "${pkgs.bash}/bin/bash -c 'sleep 2 && XAUTHORITY=/var/run/lightdm/root/:0 ${pkgs.xorg.xrandr}/bin/xrandr --display :0.0 --auto'";
  };

  # Enable the KDE Desktop Environment.
  # services.xserver.displayManager.sddm.enable = true;
  # services.xserver.desktopManager.plasma5.enable = true;

  services.xserver.displayManager.lightdm.enable = true;
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
  services.xserver.displayManager.defaultSession = "xfce+i3";
  services.xserver.windowManager.i3 = {
    enable = true;
    extraPackages = with pkgs; [
      dmenu
      i3status
      i3lock
    ];
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

  # earlyoom; I have swap enabled for hibernation, so any swapping
  # causes irrecoverable GUI freezes. earlyoom makes them short.
  services.earlyoom = {
    enable = true;
    # freeMemThreshold = 5; # percent
    freeMemThreshold = 10; # using a bit more because even https://github.com/rfjakob/earlyoom/pull/191 under-computes the amount of memory ZFS needs
    # See note below
    # freeSwapThreshold = 100; # percent
  };
  # earlyoom now accepts `-m/s PERCENT[,KILL_PERCENT]` with a comma,
  # but NixOS does not allow us to configure the behind-the-comma part,
  # so we manually override the `ExecStart` line.
  # We need `-s 100,100`, because by default the behind-the-comma part
  # is half of the before-the-comma part, so even if you set `freeSwapThreshold = 100`,
  # it will translate to `-s 100,50`, so earlyoom would only start killing
  # after 50% of the swap is full, which can take forever to happen.
  # See https://github.com/NixOS/nixpkgs/issues/83504
  systemd.services.earlyoom.serviceConfig.ExecStart = lib.mkForce "${pkgs.earlyoom}/bin/earlyoom -m 5 -s 100,100";

  # zsh
  programs.zsh.enable = true;

  # Without this `gnome-terminal` errors with:
  #     Error constructing proxy for org.gnome.Terminal:/org/gnome/Terminal/Factory0: Error calling StartServiceByName for org.gnome.Terminal: Unit gnome-terminal-server.service not found.
  programs.gnome-terminal.enable = true;

  # i3 needs it, see https://nixos.wiki/wiki/I3#DConf
  programs.dconf.enable = true;
  services.dbus.packages = [ pkgs.gnome3.dconf ];

  # Yubikey
  services.udev.packages = [ pkgs.yubikey-personalization ];
  services.pcscd.enable = true;

  # locate
  services.locate = {
    enable = true;
    locate = pkgs.mlocate;
    localuser = null; # required for mlocate, see https://github.com/NixOS/nixpkgs-channels/blob/42674051d12540d4a996504990c6ea3619505953/nixos/modules/misc/locate.nix#L130
  };

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.niklas = {
    isNormalUser = true;
    extraGroups = [
      # TODO: check if necessary
      "audio" # See https://nixos.wiki/wiki/PulseAudio
      "networkmanager"
      "wheel" # Enable ‘sudo’ for the user.
      "camera" # Enable `gphoto2` camera access.
      "libvirtd" # manage VMs
      "mlocate" # allow using `locate`
    ];
    shell = pkgs.zsh;
  };

  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ "niklas" ];

  virtualisation.libvirtd.enable = true;

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
  system.stateVersion = "19.09"; # Did you read the comment?

  # Workaround for >4GiB files from Ricoh Theta being cut off during transfer.
  # TODO: Remove if either:
  #         * https://github.com/gphoto/libgphoto2/issues/582 made it into nixpkgs.
  #         * https://github.com/libmtp/libmtp/pull/68 is fixed.
  services.udev.extraRules = ''
    # Ricoh Theta V (MTP)
    ATTR{idVendor}=="05ca", ATTR{idProduct}=="0368", SYMLINK+="libmtp-%k", ENV{ID_MTP_DEVICE}="1", ENV{ID_MEDIA_PLAYER}="1"

    # Ricoh Theta Z1 (MTP)
    ATTR{idVendor}=="05ca", ATTR{idProduct}=="036d", SYMLINK+="libmtp-%k", ENV{ID_MTP_DEVICE}="1", ENV{ID_MEDIA_PLAYER}="1"
  '';
  services.gvfs.package = lib.mkForce (
    (pkgs.gnome3.gvfs.overrideAttrs (old: {
      patches = (old.patches or []) ++ [
        (pkgs.fetchpatch {
          name = "gvfs-mtp-Fix-crashes-when-LIBMTP_devicestorage_t.patch";
          url = "https://gitlab.gnome.org/nh2/gvfs/-/commit/4eddc5d5588321918ec2780bdfba673a0d2d374b.patch";
          sha256 = "1xqnyw1pdzsbzc9qs2srs94f5dr3w649qjsm2l40rh5hdc39wlxg";
        })
      ];
    })).override (old: {
      libmtp = old.libmtp.overrideAttrs (old: {
        patches = (old.patches or []) ++ [
          (pkgs.fetchpatch {
            name = "libmtp-Add-Ricoh-Theta-V-and-Z1.patch";
            url = "https://github.com/libmtp/libmtp/commit/395b1a22fcf7f089df3b1e37ee9942d622ef64a0.patch";
            sha256 = "0f5bwxssqhwn3px4nqjfavsbxzv8zz4xq7p920pgkq62i02w8gr0";
          })
        ];
      });
    })
  );
}
