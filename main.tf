terraform {
  required_providers {
    libvirt = {
      source  = "dmacvicar/libvirt"
      version = "~> 0.8.0"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

variable "vm_count" {
  type    = number
  default = 3
}

variable "vm_ips" {
  type    = list(string)
  default = ["192.168.29.192", "192.168.29.193", "192.168.29.194"]
}

resource "libvirt_volume" "vm_disk" {
  count  = var.vm_count
  name   = "ubuntu-vm-${count.index + 1}.qcow2"
  pool   = "default"
  size   = 21474836480
  format = "qcow2"
}

resource "libvirt_cloudinit_disk" "commoninit" {
  count = var.vm_count
  name  = "cloudinit-${count.index + 1}.iso"

  # User Data: This is where we install packages and set the hostname
  user_data = <<EOF
#cloud-config
hostname: ubuntu-vm-${count.index + 1}
manage_etc_hosts: true
package_update: true
# These are the packages you requested:
packages:
  - net-tools
  - dos2unix
  - neovim
# Ensure the user 'ubuntu' exists and has sudo (adjust as needed for your setup)
users:
  - name: ubuntu
    sudo: ALL=(ALL) NOPASSWD:ALL
    groups: sudo
    shell: /bin/bash
    lock_passwd: false
    hashed_passwd: $6$rounds=4096$la0Vb79L4M.Syz3D$bEp1jnf33yFI3IZzcqH9kroYhHv2vEfvJH6dCo8WvwQnIuqHlIcLdDzrPKqPYcOvNr50gctTnzEIojQWyBzVH.
EOF

  # Network Config: This tells the VM to use the static IP we assigned in the variable
  network_config = <<EOF
version: 2
ethernets:
  enp1s0:
    dhcp4: false
    addresses: [${var.vm_ips[count.index]}/24]
    gateway4: 192.168.29.1
    nameservers:
      addresses: [8.8.8.8, 1.1.1.1]
EOF

  # Meta Data: Sets a unique instance ID so cloud-init runs only once per VM
  meta_data = <<EOF
instance-id: instance-${count.index + 1}
local-hostname: ubuntu-vm-${count.index + 1}
EOF
}

# --- 4. Create the Virtual Machines (Looping) ---
resource "libvirt_domain" "vm" {
  count  = var.vm_count
  name   = "ubuntu-vm-${count.index + 1}"
  memory = 4096
  vcpu   = 2

  # Attach the unique disk for this VM
  disk {
    volume_id = libvirt_volume.vm_disk[count.index].id
  }

  # Attach the Cloud-Init ISO so packages get installed
  disk {
    file = libvirt_cloudinit_disk.commoninit[count.index].id
  }

  # Attach the Ubuntu Installation ISO (from your original command)
  disk {
    file = "/var/lib/libvirt/images/noble-live-server-amd64.iso"
  }

  network_interface {
    bridge = "br0"
  }

  graphics {
    type           = "vnc"
    listen_type    = "address"
    listen_address = "0.0.0.0"
    autoport       = true
  }
}
