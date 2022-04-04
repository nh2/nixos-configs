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

      # I found some segfaults of `xfce4-notifyd`; enable debug info so next time
      # it happens I can check it (`cordumptctl`).
      xfce4.xfce4-notifyd = previous.xfce4.xfce4-notifyd.overrideAttrs (oldAttrs: {
        separateDebugInfo = true;
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

  boot.extraModulePackages = [
    # For being able to flip/mirror my webcam.
    config.boot.kernelPackages.v4l2loopback
  ];

  # Register a v4l2loopback device at boot
  boot.kernelModules = [
    "v4l2loopback"
  ];

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

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    awscli2 # official `aws` CLI program
    autossh
    cura
    eternal-terminal
    mumble # need at least 1.3.4 to avoid package loss
    (lib.hiPrio pkgs.parallel) # to take precedence over `parallel` from `moreutils`
    # (wineStaging.override { wineBuild = "wineWow"; }) # `wineWow` enables 64-bit support
    wineWowPackages.staging # `wineWow` enables 64-bit support
    apg
    atop
    attr.bin # for `getfattr` etc.
    bind.dnsutils # for `dig` etc.
    binutils # objdump, nm, readelf etc
    blender
    bless
    calibre
    chromium
    cloudcompare
    cryptsetup
    custom-keyboard-layout
    screenlock-script
    diffoscope
    ethtool
    exfat-utils
    ffmpeg
    file
    #(if useWayland then firefox-wayland else firefox)
    firefox
    fractal
    fzf
    gajim
    gdb
    gimp
    git
    # TODO: Replace by `delta` as soon as it's built on unstable
    gitAndTools.diff-so-fancy
    gitAndTools.git-absorb
    gitAndTools.git-branchless
    gitAndTools.hub
    gksu # for `gksudo` because `pkexec` currently cannot start Sublime Text
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
    gnome3.nautilus # xfce's `thunar` freezes the UI during large MTP transfers, nautilus doesn't
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
    krename
    libarchive # bsdtar
    libcap_ng
    libqrencode # qrencode
    libreoffice
    linuxPackages.perf
    lm_sensors
    lsof
    lz4
    lzop
    meld
    (meshlab.overrideAttrs (old: {
      # Fixes:
      # * "Select faces by view angle" "Get" button gets normal instead of position
      #   https://github.com/cnr-isti-vclab/meshlab/issues/1207
      # * GUI regression: Popups broken on Linux Xorg tiling window managers
      #   https://github.com/cnr-isti-vclab/meshlab/issues/1209
      src = pkgs.fetchFromGitHub {
        owner = "cnr-isti-vclab";
        repo = "meshlab";
        rev = "cb2f5ed4fd1ab78fa3a1420fb6c47a6e97a17143";
        sha256 = "19ryyxn9lb5h3vqbxyi3gjk9sz5x4hla39hab6vifb2w8g086rl2";
        fetchSubmodules = true; # for vcglib
      };
    }))
    moreutils
    mplayer
    ncdu
    nebula
    netcat-openbsd
    nix-diff
    nix-index
    nix-review
    nload
    ntfy
    openscad
    openssl
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
    python3
    qtpass
    rclone
    remmina
    reptyr
    ripgrep
    rofi
    rxvt-unicode
    screen
    screen-message
    shellcheck
    signal-desktop
    skype
    smartmontools
    smem
    sshfs-fuse
    stack
    stress-ng
    sublime4
    # sublime-merge
    sysdig
    sysstat
    tcpdump
    thunderbird
    traceroute
    unzip
    usbutils # for lsusb
    v4l-utils
    veracrypt
    vlc
    wget
    wirelesstools # iwconfig/iwgetid for wifi info
    wireshark
    x11vnc
    xorg.xhost
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

    jetbrains.clion
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

    vim
    # TODO: Cannot currently use the following, it breaks the Backspace and
    #       Delete keys, see https://github.com/LnL7/vim-nix/issues/38.
    # From https://nixos.wiki/wiki/Editor_Modes_for_Nix_Files#vim-nix
    (pkgs.vim_configurable.customize {
      name = "vim";
      vimrcConfig.packages.myplugins = with pkgs.vimPlugins; {
        # start = [ vim-nix ]; # load plugin on startup
        start = []; # load plugin on startup
      };
    })

    vscode

    turbovnc

    bitwarden

    bupstash

    # OnlyOffice. Sstart with `DesktopEditors`.
    # I had to download Windows fonts `Symbol.ttf` and `wingding.ttf`
    # into `~/.local/share/fonts/` for bullet points to look correct,
    # and Calibri to render my Calibri-written Word docs correctly.
    # Arial is also required to be put there so that the default templates
    # look as expected.
    onlyoffice-bin

    config.boot.kernelPackages.nvidia_x11

    wireguard
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
      5201 # iperf3
    ];
    # Or disable the firewall altogether.
    # enable = false;
  };

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

  # Disabled in order to use PipeWire, as recommended on https://nixos.wiki/wiki/PipeWire
  # # Enable sound.
  # sound.enable = true;
  # hardware.pulseaudio.enable = true;
  # # Network sink streaming support
  # hardware.pulseaudio.tcp.enable = true;
  # # Note: As of writing (20.03), enabling zeroconf adds an `avahi` dep to the
  # #       pulseaudio dep so it will be compiled, not fetched from cache.
  # # hardware.pulseaudio.zeroconf.discovery.enable = true;
  # # TODO: disable
  # # hardware.pulseaudio.zeroconf.publish.enable = true;

  security.rtkit.enable = true; # rtkit is optional but recommended for PipeWire
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
  };

  # Allow core dumps
  systemd.extraConfig = ''
    # core dump limit in KB
    DefaultLimitCORE=1000000

    # Note that systemd-coredump may still throw away coredumps if you have
    # < 15% disk free, see:
    # https://unix.stackexchange.com/questions/554442/coredumpctl-cannot-read-core-dump-gives-message-file-is-not-readable-or-no-su/554460#554460
  '';

  # Install debug symbols for all packages that provide it.
  environment.enableDebugInfo = true;

  # Steam needs this, see https://nixos.org/nixpkgs/manual/#sec-steam-play
  hardware.opengl.driSupport32Bit = true;
  hardware.pulseaudio.support32Bit = true;
  hardware.opengl.extraPackages = with pkgs; [
    # See https://www.reddit.com/r/DotA2/comments/e24l6q/a_game_file_appears_to_be_missing_or_corrupted/
    libva
  ];

  # Enable the X11 windowing system.
  services.xserver.enable = !useWayland;
  # Produce XKB dir containing custom keyboard layout by symlink-copying
  # the normal XKB dir, and copying our keymap in.
  # TODO: This might stop working in the future:
  #       https://github.com/NixOS/nixpkgs/pull/138207#issuecomment-972442368
  services.xserver.xkbDir = pkgs.runCommand "custom-keyboard-layout-xkb-dir" {} ''
    cp -r --symbolic-link "${pkgs.xkeyboard_config}/share/X11/xkb" "$out"
    chmod -R u+w "$out"

    mkdir -p "$out/keymap"
    cp ${./xkb/keymap}/* "$out/keymap"
    mkdir -p "$out/symbols"
    cp ${./xkb/symbols}/* "$out/symbols"
  '';
  services.xserver.layout = "gb-CapsLockIsHyperL";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable touchpad support.
  services.xserver.libinput.enable = true;

  services.xserver.videoDrivers = if useWayland then [ "intel" ] else [ "nvidia" ];
  # services.xserver.videoDrivers = [ "intel" ];
  # See https://nixos.wiki/wiki/Nvidia#offload_mode
  # Disabled for VFIO for now
  hardware.nvidia.prime = lib.mkIf (!useWayland) {
    offload.enable = true; # offload mode (NVIDIA only used with `nvidia-offload` wrapper script)
    # sync.enable = true; # sync mode (both Intel and NVIDIA on all the time; resume-from-suspend gives black screen)

    # Bus ID of the NVIDIA GPU. You can find it using lspci, either under 3D or VGA
    nvidiaBusId = "PCI:2:0:0";

    # Bus ID of the Intel GPU. You can find it using lspci, either under 3D or VGA
    intelBusId = "PCI:0:2:0";
  };
  hardware.nvidia.powerManagement.enable = true;
  hardware.nvidia.modesetting.enable = true;

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
  services.xserver.displayManager.defaultSession = "xfce+i3";
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

  # Credential storage for GNOME programs (also gajim, fractal).
  # Otherwise they won't remember credentials across restarts.
  services.gnome.gnome-keyring.enable = true;

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
    ];
    shell = pkgs.zsh;
  };

  virtualisation.virtualbox.host.enable = true;
  users.extraGroups.vboxusers.members = [ "niklas" ];

  virtualisation.libvirtd = {
    enable = true;
    qemu.ovmf.enable = true;
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
  system.stateVersion = "19.09"; # Did you read the comment?

  services.keybase.enable = true;

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
}
