locals {
  rke2_nodes = {
    rke2-cp01 = {
      vm_id        = 111
      ipv4_address = "10.20.0.11/24"
      cpu_cores    = 2
      memory_mb    = 3072
      disk_size_gb = 30
    }

    rke2-cp02 = {
      vm_id        = 112
      ipv4_address = "10.20.0.12/24"
      cpu_cores    = 2
      memory_mb    = 3072
      disk_size_gb = 30
    }

    rke2-cp03 = {
      vm_id        = 113
      ipv4_address = "10.20.0.13/24"
      cpu_cores    = 2
      memory_mb    = 3072
      disk_size_gb = 30
    }

    rke2-worker01 = {
      vm_id        = 121
      ipv4_address = "10.20.0.21/24"
      cpu_cores    = 4
      memory_mb    = 4096
      disk_size_gb = 50
    }
  }
}

module "rke2_nodes" {
  source = "./modules/proxmox-vm"

  for_each = local.rke2_nodes

  name           = each.key
  node_name      = "proxmox-lab"
  vm_id          = each.value.vm_id
  clone_vm_id    = 9000
  cpu_cores      = each.value.cpu_cores
  memory_mb      = each.value.memory_mb
  disk_size_gb   = each.value.disk_size_gb
  datastore_id   = "local-lvm"
  bridge         = "vmbr1"
  username       = "automation"
  ssh_public_key = var.ssh_public_key

  ipv4_address = each.value.ipv4_address
  ipv4_gateway = "10.20.0.1"

  dns_servers = [
    "1.1.1.1",
    "8.8.8.8",
  ]

  dns_domain = "local"

  started = true
}

output "rke2_nodes" {
  value = {
    for name, node in module.rke2_nodes :
    name => {
      vm_id          = node.vm_id
      ipv4_addresses = node.ipv4_addresses
    }
  }
}
