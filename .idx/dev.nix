{ pkgs, ... }: {
  channel = "stable-24.11";

  packages = [
    pkgs.qemu
    pkgs.htop
    pkgs.cloudflared
    pkgs.coreutils
    pkgs.gnugrep
    pkgs.wget
    pkgs.git
    pkgs.python3
  ];

  idx.workspace.onStart = {
    qemu = ''
      set -e

      # =========================
      # Cleanup once
      # =========================
      if [ ! -f /home/user/.cleanup_done ]; then
        rm -rf /home/user/.gradle/* /home/user/.emu/* || true
        find /home/user -mindepth 1 -maxdepth 1 \
          ! -name 'idx-windows-gui' \
          ! -name '.cleanup_done' \
          ! -name '.*' \
          -exec rm -rf {} + || true
        touch /home/user/.cleanup_done
      fi

      # =========================
      # Paths
      # =========================
      VM_DIR="$HOME/qemu"
      RAW_DISK="$VM_DIR/windows.qcow2"
      WIN_ISO="$VM_DIR/Win11_English_x64.iso"
      VIRTIO_ISO="$VM_DIR/virtio-win.iso"
      NOVNC_DIR="$HOME/noVNC"
      OVMF_DIR="$HOME/qemu/ovmf"
      OVMF_CODE="$OVMF_DIR/OVMF_CODE.fd"
      OVMF_VARS="$OVMF_DIR/OVMF_VARS.fd"

      mkdir -p "$VM_DIR" "$OVMF_DIR"

      # =========================
      # Download Windows 11 ISO from GitHub / idx mirror
      # =========================
      if [ ! -f "$WIN_ISO" ]; then
        echo "Downloading Windows 11 ISO from idx mirror..."
        wget -O "$WIN_ISO" "https://github.com/idx-mirror/Win11/releases/download/25H2/Win11_English_x64.iso"
      else
        echo "Windows 11 ISO already exists, skipping download."
      fi

      # =========================
      # Download VirtIO drivers ISO
      # =========================
      if [ ! -f "$VIRTIO_ISO" ]; then
        echo "Downloading VirtIO drivers ISO..."
        wget -O "$VIRTIO_ISO" \
          https://github.com/virtio-win/virtio-win-pkg-scripts/releases/download/virtio-0.1.271/virtio-win-0.1.271.iso
      else
        echo "VirtIO ISO already exists, skipping download."
      fi

      # =========================
      # Download OVMF firmware
      # =========================
      if [ ! -f "$OVMF_CODE" ]; then
        wget -O "$OVMF_CODE" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_CODE.fd
      fi
      if [ ! -f "$OVMF_VARS" ]; then
        wget -O "$OVMF_VARS" https://qemu.weilnetz.de/test/ovmf/usr/share/OVMF/OVMF_VARS.fd
      fi

      # =========================
      # Clone noVNC if missing
      # =========================
      if [ ! -d "$NOVNC_DIR/.git" ]; then
        git clone https://github.com/novnc/noVNC.git "$NOVNC_DIR"
      fi

      # =========================
      # Create QCOW2 disk if missing
      # =========================
      if [ ! -f "$RAW_DISK" ]; then
        qemu-img create -f qcow2 "$RAW_DISK" 50G
      fi

      # =========================
      # Start QEMU (Windows 11)
      # =========================
      nohup qemu-system-x86_64 \
        -enable-kvm \
        -cpu host,+topoext,hv_relaxed,hv_spinlocks=0x1fff,hv-passthrough,+pae,+nx,kvm=on,+svm \
        -smp 8,cores=8 \
        -M q35,usb=on \
        -device usb-tablet \
        -m 28672 \
        -device virtio-balloon-pci \
        -vga virtio \
        -net nic,netdev=n0,model=virtio-net-pci \
        -netdev user,id=n0,hostfwd=tcp::3389-:3389 \
        -boot c \
        -device virtio-serial-pci \
        -device virtio-rng-pci \
        -drive if=pflash,format=raw,readonly=on,file="$OVMF_CODE" \
        -drive if=pflash,format=raw,file="$OVMF_VARS" \
        -drive file="$RAW_DISK",format=qcow2,if=virtio \
        -cdrom "$WIN_ISO" \
        -drive file="$VIRTIO_ISO",media=cdrom,if=ide \
        -uuid e47ddb84-fb4d-46f9-b531-14bb15156336 \
        -vnc :0 \
        -display none \
        > /tmp/qemu.log 2>&1 &

      # =========================
      # Start noVNC
      # =========================
      nohup "$NOVNC_DIR/utils/novnc_proxy" --vnc 127.0.0.1:5900 --listen 8888 \
        > /tmp/novnc.log 2>&1 &

      # =========================
      # Start Cloudflared tunnel
      # =========================
      nohup cloudflared tunnel --no-autoupdate --url http://localhost:8888 \
        > /tmp/cloudflared.log 2>&1 &

      sleep 10

      if grep -q "trycloudflare.com" /tmp/cloudflared.log; then
        URL=$(grep -o "https://[a-z0-9.-]*trycloudflare.com" /tmp/cloudflared.log | head -n1)
        echo "========================================="
        echo " 🌍 Windows 11 QEMU + noVNC ready:"
        echo "     $URL/vnc.html"
        echo "     $URL/vnc.html" > /home/user/idx-windows-gui/noVNC-URL.txt
        echo "========================================="
      else
        echo "❌ Cloudflared tunnel failed"
      fi

      # =========================
      # Keep workspace alive
      # =========================
      while true; do sleep 60; done
    '';
  };

  idx.previews = {
    enable = true;
    previews = {
      qemu = { manager = "web"; command = ["bash" "-lc" "echo 'noVNC running on port 8888'"]; };
      terminal = { manager = "web"; command = ["bash"]; };
    };
  };
}
