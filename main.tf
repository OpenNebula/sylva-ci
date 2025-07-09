terraform {
  required_providers {
    opennebula = {
      source  = "OpenNebula/opennebula"
      version = "1.5.0"
    }
  }
}

variable "endpoint" {
  type = string
}
variable "username" {
  type = string
}
variable "password" {
  type = string
}

provider "opennebula" {
  endpoint = var.endpoint
  username = var.username
  password = var.password
}

variable "HYDRA_USER" {
  type    = string
  default = "oneadmin"
}
variable "HYDRA_PASSWORD" {
  type = string
}
variable "HYDRA_FLAKE_URL" {
  type    = string
  default = "https://github.com/OpenNebula/sylva-ci.git"
}

variable "GITLAB_PROJECT" {
  type = string
}
variable "GITLAB_TOKEN" {
  type = string
}

resource "random_id" "sylva-ci" {
  byte_length = 4
}

data "opennebula_virtual_network" "sylva-ci" {
  for_each = { service = null }
  name     = each.key
}

resource "opennebula_image" "sylva-ci" {
  for_each     = { nixos = "https://d24fmfybwxpuhu.cloudfront.net/nixos-25.05.803297.10d7f8d34e5e-20250609.qcow2" }
  name         = "sylva-ci-${each.key}-${random_id.sylva-ci.id}"
  datastore_id = "1"
  persistent   = false
  permissions  = "642"
  dev_prefix   = "vd"
  driver       = "qcow2"
  path         = each.value
}

locals {
  user_data = {
    hydra = {
      write_files = [
        {
          path        = "/var/tmp/setup-sylva-ci.sh"
          owner       = "root:root"
          permissions = "644"
          encoding    = "b64"
          content     = base64encode(file("${path.module}/setup-sylva-ci.sh"))
        }, {
          path        = "/var/tmp/report-sylva-ci.rb"
          owner       = "root:root"
          permissions = "644"
          encoding    = "b64"
          content     = base64encode(file("${path.module}/report-sylva-ci.rb"))
        },
      ]
      runcmd = [[
        "/run/current-system/sw/bin/bash", "--login", "/var/tmp/setup-sylva-ci.sh",
      ]]
    }
  }
}

resource "opennebula_virtual_machine" "sylva-ci" {
  for_each    = { hydra = opennebula_image.sylva-ci["nixos"].id }
  name        = "sylva-ci-${each.key}-${random_id.sylva-ci.id}"
  permissions = "642"
  cpu         = "2"
  vcpu        = "4"
  memory      = 24 * 1024

  context = {
    SET_HOSTNAME   = "sylva-ci"
    NETWORK        = "YES"
    TOKEN          = "YES"
    SSH_PUBLIC_KEY = "$USER[SSH_PUBLIC_KEY]"

    USER_DATA_ENCODING = "base64"
    USER_DATA          = base64encode(join("\n", ["#cloud-config", yamlencode(local.user_data[each.key])]))

    HYDRA_USER      = var.HYDRA_USER
    HYDRA_PASSWORD  = var.HYDRA_PASSWORD
    HYDRA_FLAKE_URL = var.HYDRA_FLAKE_URL

    GITLAB_PROJECT = var.GITLAB_PROJECT
    GITLAB_TOKEN   = var.GITLAB_TOKEN
  }

  os {
    arch = "x86_64"
    boot = ""
  }

  disk {
    image_id = each.value
    size     = 256 * 1024
  }

  nic {
    network_id = data.opennebula_virtual_network.sylva-ci["service"].id
  }

  graphics {
    keymap = "en-us"
    listen = "0.0.0.0"
    type   = "VNC"
  }
}
