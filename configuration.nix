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
  # nixpkgs.overlays = [
  #   (final: previous: {
  #   })
  # ];

  # Use the systemd-boot EFI boot loader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  boot.supportedFilesystems = [ "zfs" ];
  networking.hostId = "25252525";
  boot.zfs.requestEncryptionCredentials = true;

  boot.extraModprobeConfig = ''
    options thinkpad_acpi fan_control=1
  '';

  networking.hostName = "t25"; # Define your hostname.
  # networking.wireless.enable = true;  # Enables wireless support via wpa_supplicant.

  # The global useDHCP flag is deprecated, therefore explicitly set to false here.
  # Per-interface useDHCP will be mandatory in the future, so this generated config
  # replicates the default behaviour.
  networking.useDHCP = false;
  networking.interfaces.enp0s31f6.useDHCP = true;
  networking.interfaces.wlp4s0.useDHCP = true;

  # Configure network proxy if necessary
  # networking.proxy.default = "http://user:password@proxy:port/";
  # networking.proxy.noProxy = "127.0.0.1,localhost,internal.domain";

  # Select internationalisation properties.
  i18n = {
    # consoleFont = "Lat2-Terminus16";
    consoleKeyMap = "uk";
    # defaultLocale = "en_US.UTF-8";
  };

  # Set your time zone.
  time.timeZone = "Europe/Berlin";

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    (import <unstable> {}).cura # TODO: Remove with NixOS 20.03
    (import <unstable> {}).eternal-terminal # TODO: Remove with NixOS 20.03
    (import <unstable> {}).mumble # TODO: Remove with NixOS 20.03
    (lib.hiPrio pkgs.parallel) # to take precedence over `parallel` from `moreutils`
    (wineStaging.override { wineBuild = "wineWow"; }) # `wineWow` enables 64-bit support
    atop
    attr.bin # for `getfattr` etc.
    bind.dnsutils # for `dig` etc.
    binutils # objdump, nm, readelf etc
    blender
    chromium
    custom-keyboard-layout
    diffoscope
    ethtool
    file
    firefox
    fzf
    gdb
    gimp
    git
    gitAndTools.diff-so-fancy
    gitAndTools.hub
    glxinfo
    gnome-themes-standard # Provides theme in the XFCE theme switcher
    gnome3.eog
    gnome3.evince
    gnome3.file-roller
    gnome3.gnome-screenshot
    gnome3.gnome-system-monitor
    gnome3.gnome-terminal
    gnome3.totem
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
    meshlab
    moreutils
    mplayer
    ncdu
    netcat-openbsd
    nix-diff
    nix-index
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
    powertop
    pv
    python3
    qtpass
    reptyr
    ripgrep
    screen
    signal-desktop
    smartmontools
    smem
    sshfs-fuse
    stack
    steam
    stress-ng
    sublime3
    sysdig
    sysstat
    tcpdump
    thunderbird
    traceroute
    unzip
    vim
    vlc
    wget
    wireshark
    xorg.xev
    xorg.xkbcomp
    xorg.xwininfo
    xournal
    xsecurelock
    xss-lock
    yubikey-personalization
    yubikey-personalization-gui
    zoom-us
  ];

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

  services.avahi.enable = true;
  services.avahi.nssmdns = true; # allows pinging *.local

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound.
  sound.enable = true;
  hardware.pulseaudio.enable = true;
  # Network sink streaming support
  hardware.pulseaudio.tcp.enable = true;
  hardware.pulseaudio.zeroconf.discovery.enable = true;
  # TODO: disable
  hardware.pulseaudio.zeroconf.publish.enable = true;

  # Steam needs this, see https://nixos.org/nixpkgs/manual/#sec-steam-play
  hardware.opengl.driSupport32Bit = true;
  hardware.pulseaudio.support32Bit = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.layout = "gb";
  # services.xserver.xkbOptions = "eurosign:e";

  # Enable touchpad support.
  services.xserver.libinput.enable = true;

  services.xserver.videoDrivers = [ "nvidia" ];
  hardware.nvidia.optimus_prime.enable = true;
  # Bus ID of the NVIDIA GPU. You can find it using lspci, either under 3D or VGA
  hardware.nvidia.optimus_prime.nvidiaBusId = "PCI:2:0:0";
  # Bus ID of the Intel GPU. You can find it using lspci, either under 3D or VGA
  hardware.nvidia.optimus_prime.intelBusId = "PCI:0:2:0";
 

  # Enable the KDE Desktop Environment.
  # services.xserver.displayManager.sddm.enable = true;
  # services.xserver.desktopManager.plasma5.enable = true;

  services.xserver.displayManager.lightdm.enable = true;
  services.xserver.displayManager.sessionCommands = lib.concatStrings [
    # Map Caps_Lock to Hyper_L
    ''
      ${custom-keyboard-layout}/bin/${customKeyboardLayoutScriptName}
    ''
    # Make `xsecurelock` happen on `xflock4`, `loginctl lock-session`, and suspend/hibernate.
    ''
      xfconf-query --channel xfce4-session --create --property /general/LockCommand --set '${pkgs.xsecurelock}/bin/xsecurelock' --type string
      ${pkgs.xss-lock}/bin/xss-lock --transfer-sleep-lock -- ${pkgs.xsecurelock}/bin/xsecurelock &
    ''
    # Start PolicyKit agent manually
    # TODO: Remove with NixOS 20.03, see:
    #   https://github.com/NixOS/nixpkgs/commit/04e56aa016a19c8c8af1f02176bf230e02e6d6b8
    ''
      ${pkgs.polkit_gnome}/libexec/polkit-gnome-authentication-agent-1 &
    ''
  ];

  # Make polkit prompt show only 1 choice instead of both root and all `wheel` users.
  security.polkit.adminIdentities = [ "unix-group:wheel" ];

  # Enables user icons in display manager.
  services.accounts-daemon.enable = true;

  services.xserver.desktopManager = {
    default = "xfce";
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
  services.xserver.windowManager.default = "i3";
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

  # zsh
  programs.zsh.enable = true;

  # i3 needs it, see https://nixos.wiki/wiki/I3#DConf
  programs.dconf.enable = true;
  services.dbus.packages = [ pkgs.gnome3.dconf ];

  # Yubikey
  services.udev.packages = [ pkgs.yubikey-personalization ];
  # TODO: Remove with NixOS 20.03
  services.udev.extraRules = ''
    ATTRS{idVendor}=="1038", ATTRS{idProduct}=="12ad", ENV{PULSE_PROFILE_SET}="steelseries-arctis-usb-audio.conf"
  '';
  services.pcscd.enable = true;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.niklas = {
    isNormalUser = true;
    extraGroups = [
      # TODO: check if necessary
      "audio" # See https://nixos.wiki/wiki/PulseAudio
      "networkmanager"
      "wheel" # Enable ‘sudo’ for the user.
    ];
    shell = pkgs.zsh;
  };

  # This value determines the NixOS release with which your system is to be
  # compatible, in order to avoid breaking some software such as database
  # servers. You should change this only after NixOS release notes say you
  # should.
  system.stateVersion = "19.09"; # Did you read the comment?

}
